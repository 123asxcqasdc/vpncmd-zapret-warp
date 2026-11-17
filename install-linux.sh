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
readonly LINUX_INSTALL_URL="https://vpn-cmd.p7z.ru/install-linux.sh"

say()  { printf '\n[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[x] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- root
# При запуске файлом ($0/ BASH_SOURCE — путь) перезапускаем себя через sudo.
# При запуске через `curl ... | bash`-script из stdin перезапуск невозможен,
# поэтому корректный вариант для сайта: `curl ... | sudo bash`.
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    script_path="${BASH_SOURCE[0]:-}"
    if [[ -n "$script_path" && -f "$script_path" ]]; then
        say "Нужны права root — перезапускаю через sudo"
        exec sudo bash "$script_path" "$@"
    fi
    die "Нужны права root. Запуск с сайта: curl -fsSL $LINUX_INSTALL_URL | sudo bash"
fi

# ---------------------------------------------------------------- ОС
[[ -r /etc/os-release ]] || die "Файл /etc/os-release не найден"
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
    ubuntu|debian) say "ОС: ${PRETTY_NAME:-$ID}" ;;
    *) die "Поддерживаются только Ubuntu и Debian (обнаружено: ${ID:-неизвестно})" ;;
esac

# -------------------------------------------------- лицензия Cloudflare
say "Cloudflare WARP"
echo "    Документация:     https://developers.cloudflare.com/warp-client/get-started/linux/"
echo "    Условия (ToS):    $CF_TOS"
echo "    Конфиденциальность: $CF_PRIVACY"
WARP_ACCEPT="no"
answer=""
# Читаем именно из /dev/tty: при запуске через `curl ... | sudo bash`
# stdin занят телом скрипта, обычный read сразу получил бы EOF.
if read -r -p "Принимаете лицензионное соглашение Cloudflare? [y/N]: " answer < /dev/tty 2>/dev/null; then
    if [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]; then
        WARP_ACCEPT="yes"
    fi
else
    warn "Не удалось запросить согласие (нет терминала): лицензия не принята, WARP пропущен"
fi
echo "    Решение: ${WARP_ACCEPT}"

# ---------------------------------------------------------------- зависимости
say "Установка зависимостей (apt)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    curl ca-certificates gnupg lsb-release iptables ipset procps
command -v systemctl >/dev/null 2>&1 || die "systemd (systemctl) не найден"

# ---------------------------------------------------------------- zapret
TMP_DIR="$(mktemp -d /tmp/vpncmd-zapret.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

say "Скачивание zapret-linux-easy"
curl -fsSL --retry 3 -o "$TMP_DIR/main.tar.gz" "$ZAPRET_ARCHIVE"
tar -xzf "$TMP_DIR/main.tar.gz" -C "$TMP_DIR"
SRC="$TMP_DIR/zapret-linux-easy-main"
[[ -d "$SRC/files" ]] || die "В архиве нет папки files/"

arch="$(uname -m)"
case "$arch" in
    x86_64)          bin_dir="x86_64" ;;
    i386|i686)       bin_dir="x86" ;;
    aarch64)         bin_dir="arm64" ;;
    armv7l|armv6l)   bin_dir="arm" ;;
    riscv64)         bin_dir="riscv64" ;;
    *) die "Неподдерживаемая архитектура: $arch" ;;
esac
[[ -f "$SRC/bins/$bin_dir/nfqws" ]] || die "Нет бинарника nfqws для $arch ($bin_dir)"

say "Установка zapret в /opt/zapret"
systemctl stop zapret >/dev/null 2>&1 || true
pkill -x nfqws >/dev/null 2>&1 || true
rm -rf /opt/zapret
mkdir -p /opt/zapret
cp -a "$SRC/files/." /opt/zapret/
install -m 0755 "$SRC/bins/$bin_dir/nfqws" /opt/zapret/system/nfqws

# Фиксированные параметры установки: iptables + ВСЕ WAN-интерфейсы
printf 'iptables\n' > /opt/zapret/system/FWTYPE
: > /opt/zapret/system/IFACE_WAN
: > /opt/zapret/system/IFACE_LAN

# На всякий случай убираем старый юнит из /usr/lib, чтобы не было двух копий
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

systemctl daemon-reload
systemctl enable --now zapret
if systemctl is-active --quiet zapret && pidof nfqws >/dev/null 2>&1; then
    say "zapret запущен (iptables, все WAN-интерфейсы)"
else
    warn "zapret запущен, но nfqws не найден — проверьте: systemctl status zapret"
fi

# ---------------------------------------------------------------- WARP
if [[ "$WARP_ACCEPT" == "yes" ]]; then
    say "Установка Cloudflare WARP"
    if command -v warp-cli >/dev/null 2>&1; then
        say "warp-cli уже установлен, пропускаю установку пакета"
    else
        mkdir -p "$(dirname "$CF_KEYRING")"
        curl -fsSL --retry 3 https://pkg.cloudflareclient.com/pubkey.gpg \
            | gpg --yes --dearmor --output "$CF_KEYRING"
        codename="$(lsb_release -cs)"
        printf 'deb [signed-by=%s] https://pkg.cloudflareclient.com/ %s main\n' \
            "$CF_KEYRING" "$codename" > "$CF_LIST"
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends cloudflare-warp
    fi

    say "Регистрация и подключение WARP (лицензия принята)"
    warp-cli --accept-tos registration new || warn "registration new завершилось с ошибкой"
    warp-cli --accept-tos connect         || warn "connect завершилось с ошибкой"
    sleep 2
    warp-cli --accept-tos status || true

    if curl -fsS --max-time 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null \
        | grep -q '^warp=on'; then
        say "WARP подключён (warp=on)"
    else
        warn "WARP не подключён — проверьте: warp-cli status"
    fi
else
    say "WARP пропущен (лицензия Cloudflare не принята)"
fi

# ---------------------------------------------------------------- итог
cat <<'EOF'

==================== Готово ====================
Управление zapret:
  systemctl status|stop|start|restart zapret
  конфиг:  /opt/zapret/config.txt
  списки:  /opt/zapret/autohosts.txt, ipset.txt, ignore.txt, whitelist.txt
  проверка: /opt/zapret/check.sh

Управление WARP (если установлен):
  warp-cli status
  warp-cli disconnect / connect
  warp-cli mode warp+doh | doh

Источники:
  https://github.com/ImMALWARE/zapret-linux-easy
  https://developers.cloudflare.com/warp-client/get-started/linux/
===============================================
EOF
