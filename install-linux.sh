#!/usr/bin/env bash
# VpnCMD — установка zapret + Cloudflare WARP для Ubuntu / Debian
#
# zapret:   https://github.com/ImMALWARE/zapret-linux-easy
# WARP:     https://developers.cloudflare.com/warp-client/get-started/linux/
#
# Выбор при установке зафиксирован:
#   firewall type : 1 (iptables)
#   WAN-интерфейсы: ВСЕ (пустой /opt/zapret/system/IFACE_WAN)
#
# Запуск с сайта: curl -fsSL https://vpn-cmd.p7z.ru/install-linux.sh | sudo bash
# Запуск файлом:  sudo bash install-linux.sh
#                 (если запустить без sudo, скрипт сам перезапустится через sudo)

set -euo pipefail

readonly ZAPRET_REPO="https://github.com/ImMALWARE/zapret-linux-easy"
readonly ZAPRET_ARCHIVE="$ZAPRET_REPO/archive/refs/heads/main.tar.gz"
readonly CF_KEYRING="/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg"
readonly CF_LIST="/etc/apt/sources.list.d/cloudflare-client.list"
readonly CF_TOS="https://www.cloudflare.com/terms/"
readonly CF_PRIVACY="https://www.cloudflare.com/privacypolicy/"
readonly CF_DOCS="https://developers.cloudflare.com/warp-client/get-started/linux/"
readonly LINUX_INSTALL_URL="https://vpn-cmd.p7z.ru/install-linux.sh"

# ---------------------------------------------------------------- оформление
# Цвета такие же по смыслу, как Write-Host -ForegroundColor в Windows-скрипте.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[91m'
    C_YELLOW=$'\033[93m'
    C_GREEN=$'\033[92m'
    C_RESET=$'\033[0m'
else
    C_RED=""
    C_YELLOW=""
    C_GREEN=""
    C_RESET=""
fi

say()   { printf '%s\n' "$*"; }
check() { printf '[CHECK] %s\n' "$*"; }
ok()    { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }

show_logo() {
    if [[ -t 1 ]]; then clear >/dev/null 2>&1 || true; fi
    cat <<'EOF'
  __     __            ____ __  __ ____
   \ \   / / __  _ __  / ___|  \/  |  _ \
    \ \ / / '_ \| '_ \| |   | |\/| | | | |
     \ V /| |_) | | | | |___| |  | | |_| |
      \_/ | .__/|_| |_|\____|_|  |_|____/
          |_|
EOF
    printf '\n============================================\n'
    printf ' VpnCMD - Zapret + WARP Auto Installer (Linux)\n'
    printf '============================================\n\n'
}

show_banner() {
    show_logo
    if [[ -t 1 ]]; then sleep 1; fi
}

step() {
    show_logo
    printf '============================================\n'
    printf ' Step %s: %s\n' "$1" "$2"
    printf '============================================\n\n'
}

# ---------------------------------------------------------------- root
# При запуске файлом (BASH_SOURCE — путь) перезапускаем себя через sudo.
# При запуске через `curl ... | bash` скрипт живёт в stdin, поэтому
# корректный вариант для сайта: `curl ... | sudo bash`.
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    script_path="${BASH_SOURCE[0]:-}"
    if [[ -n "$script_path" && -f "$script_path" ]]; then
        say "Requesting administrator rights..."
        exec sudo bash "$script_path" "$@"
    fi
    die "Root required. Use: curl -fsSL $LINUX_INSTALL_URL | sudo bash"
fi

# ---------------------------------------------------------------- ОС
[[ -r /etc/os-release ]] || die "/etc/os-release not found"
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Unsupported OS: ${ID:-unknown}. Only Ubuntu and Debian are supported." ;;
esac

# ---------------------------------------------------------------- ярлык WARP
create_warp_desktop_shortcut() {
    local target_user="${SUDO_USER:-}"
    [[ -z "$target_user" || "$target_user" == "root" ]] && target_user="$(id -un)"

    local user_home
    user_home="$(getent passwd "$target_user" | cut -d: -f6)"
    [[ -n "$user_home" ]] || user_home="/home/$target_user"

    local desktop=""
    if command -v xdg-user-dir >/dev/null 2>&1; then
        desktop="$(sudo -u "$target_user" env HOME="$user_home" xdg-user-dir DESKTOP 2>/dev/null || true)"
    fi
    if [[ -z "$desktop" || "$desktop" == "$user_home" ]]; then
        local d
        for d in "$user_home/Desktop" "$user_home/Рабочий стол" "$user_home/desktop"; do
            if [[ -d "$d" ]]; then desktop="$d"; break; fi
        done
    fi
    [[ -z "$desktop" ]] && desktop="$user_home/Desktop"
    mkdir -p "$desktop"

    # Графический клиент входит в пакет cloudflare-warp с репозитория
    # https://pkg.cloudflareclient.com/ — это warp-taskbar (системный трей).
    local entry="$desktop/Cloudflare WARP.desktop"
    local system_entry="/usr/share/applications/com.cloudflare.WarpTaskbar.desktop"
    if [[ -f "$system_entry" ]]; then
        cp -f "$system_entry" "$entry"
        sed -i 's/^Name=.*/Name=Cloudflare WARP/' "$entry"
        sed -i 's/^Comment=.*/Comment=Cloudflare WARP - status and connection control/' "$entry"
    else
        warn "System WARP .desktop entry not found, creating a fallback shortcut"
        cat > "$entry" <<'DESKTOP'
[Desktop Entry]
Version=1.2
Type=Application
Name=Cloudflare WARP
Comment=Cloudflare WARP - status and connection control
Exec=/usr/bin/warp-taskbar
Icon=zero-trust-orange
Terminal=false
StartupNotify=false
Categories=Network;
DESKTOP
    fi
    chmod 0755 "$entry"
    systemctl --global enable warp-taskbar.service >/dev/null 2>&1 || true

    local group
    group="$(id -gn "$target_user" 2>/dev/null || printf '%s' "$target_user")"
    chown "$target_user:$group" "$entry" 2>/dev/null || true
    ok "Desktop shortcut created: $entry"
}

# ============================================================
#  MAIN
# ============================================================
show_banner
say "Work dir: /opt/zapret"
say ''
check "OS: ${PRETTY_NAME:-$ID}"

if systemctl is-enabled --quiet zapret 2>/dev/null; then
    check "Zapret is already installed (will be updated)."
else
    check "Zapret is NOT installed."
fi
if command -v warp-cli >/dev/null 2>&1; then
    check "Cloudflare WARP is already installed."
else
    check "Cloudflare WARP is NOT installed."
fi
say ''

# ---------------------------------------------------------------- Step 1
step 1 "Download latest zapret-linux-easy"
export DEBIAN_FRONTEND=noninteractive
say "Installing dependencies (apt)..."
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    curl ca-certificates gnupg lsb-release iptables ipset procps
command -v systemctl >/dev/null 2>&1 || die "systemd (systemctl) not found"

TMP_DIR="$(mktemp -d /tmp/vpncmd-zapret.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

say "Downloading: $ZAPRET_ARCHIVE"
curl -fsSL --retry 3 -o "$TMP_DIR/main.tar.gz" "$ZAPRET_ARCHIVE"
say "Download complete."
say "Extracting..."
tar -xzf "$TMP_DIR/main.tar.gz" -C "$TMP_DIR"
SRC="$TMP_DIR/zapret-linux-easy-main"
[[ -d "$SRC/files" ]] || die "zapret files/ folder not found in archive"

arch="$(uname -m)"
case "$arch" in
    x86_64)        bin_dir="x86_64" ;;
    i386|i686)     bin_dir="x86" ;;
    aarch64)       bin_dir="arm64" ;;
    armv7l|armv6l) bin_dir="arm" ;;
    riscv64)       bin_dir="riscv64" ;;
    *) die "Unsupported architecture: $arch" ;;
esac
[[ -f "$SRC/bins/$bin_dir/nfqws" ]] || die "nfqws binary not found for $arch ($bin_dir)"
ok "Found zapret in: zapret-linux-easy-main"

# ---------------------------------------------------------------- Step 2
step 2 "Install zapret service (iptables, all WAN interfaces)"
say "Installing zapret to /opt/zapret..."
systemctl stop zapret >/dev/null 2>&1 || true
pkill -x nfqws >/dev/null 2>&1 || true
rm -rf /opt/zapret
mkdir -p /opt/zapret
cp -a "$SRC/files/." /opt/zapret/
install -m 0755 "$SRC/bins/$bin_dir/nfqws" /opt/zapret/system/nfqws

# Фиксированные параметры: iptables + ВСЕ WAN-интерфейсы
printf 'iptables\n' > /opt/zapret/system/FWTYPE
: > /opt/zapret/system/IFACE_WAN
: > /opt/zapret/system/IFACE_LAN
rm -f /usr/lib/systemd/system/zapret.service

cat > /etc/systemd/system/zapret.service <<'EOF'
[Unit]
Description=zapret (nfqws) - DPI bypass
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/zapret
ExecStart=/bin/bash /opt/zapret/system/starter.sh
ExecStop=/bin/bash /opt/zapret/system/stopper.sh

[Install]
WantedBy=multi-user.target
EOF

say "Creating service..."
systemctl daemon-reload
systemctl enable --now zapret
if systemctl is-active --quiet zapret && pidof nfqws >/dev/null 2>&1; then
    ok "Zapret service is running."
else
    warn "Service is not running. Check manually: systemctl status zapret"
fi

# ---------------------------------------------------------------- Step 3
step 3 "Download and install Cloudflare WARP"
say "Documentation: $CF_DOCS"
say "Packages:      https://pkg.cloudflareclient.com/"
say "Terms:         $CF_TOS"
say "Privacy:       $CF_PRIVACY"
say ''
WARP_ACCEPT="no"
answer=""
# Читаем из /dev/tty: при `curl ... | sudo bash` stdin занят телом скрипта.
if read -r -p "Accept the Cloudflare license agreement? [y/N]: " answer < /dev/tty 2>/dev/null; then
    if [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
        WARP_ACCEPT="yes"
    fi
else
    warn "No terminal available to ask for license acceptance."
fi

if [[ "$WARP_ACCEPT" == "yes" ]]; then
    if command -v warp-cli >/dev/null 2>&1; then
        check "Cloudflare WARP is already installed."
    else
        say "Downloading Cloudflare GPG key..."
        mkdir -p "$(dirname "$CF_KEYRING")"
        curl -fsSL --retry 3 https://pkg.cloudflareclient.com/pubkey.gpg \
            | gpg --yes --dearmor --output "$CF_KEYRING"
        codename="$(lsb_release -cs)"
        say "Adding repository: $codename"
        printf 'deb [signed-by=%s] https://pkg.cloudflareclient.com/ %s main\n' \
            "$CF_KEYRING" "$codename" > "$CF_LIST"
        apt-get update -qq
        say "Installing WARP (CLI + graphical taskbar)..."
        apt-get install -y -qq --no-install-recommends cloudflare-warp
        ok "Cloudflare WARP installed (warp-cli + warp-taskbar)."
    fi

    say "Registering WARP..."
    warp-cli --accept-tos registration new || warn "registration new failed"
    say "Connecting WARP..."
    warp-cli --accept-tos connect || warn "connect failed"
    sleep 2
    warp-cli --accept-tos status || true
    if curl -fsS --max-time 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | grep -q '^warp=on'; then
        ok "WARP is connected (warp=on)."
    else
        warn "WARP is not connected. Check: warp-cli status"
    fi
else
    warn "Cloudflare license not accepted - WARP installation skipped."
fi

# ---------------------------------------------------------------- Step 4
step 4 "Create Cloudflare WARP desktop shortcut"
if command -v warp-cli >/dev/null 2>&1; then
    create_warp_desktop_shortcut
else
    warn "Cloudflare WARP is not installed - shortcut skipped."
fi

# ---------------------------------------------------------------- Done
show_logo
printf '============================================\n'
printf ' Done.\n'
printf '============================================\n'
say "Zapret installed in: /opt/zapret"
say "WARP shortcut: Desktop/Cloudflare WARP.desktop (warp-taskbar)"
say "Tray icon will appear after the next login."
say ''
say "Zapret control: systemctl status|stop|start|restart zapret"
say "WARP control:   warp-cli status"
if [[ -t 1 ]]; then
    say ''
    say "Closing in 5 seconds..."
    sleep 5
fi
