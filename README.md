```
 __     __            ____ __  __ ____  
 ╲ ╲   ╱ ╱ __  _ __  ╱ ___│  ╲╱  │  _ ╲ 
  ╲ ╲ ╱ ╱ '_ ╲│ '_ ╲│ │   │ │╲╱│ │ │ │ │
   ╲ V ╱│ │_) │ │ │ │ │___│ │  │ │ │_│ │
    ╲_╱ │ .__╱│_│ │_│╲____│_│  │_│____╱ 
        │_│                             
```

# VpnCMD — установщик Zapret + Cloudflare WARP

**Сайт:** https://vpn-cmd.p7z.ru/ · **GitHub Pages:** https://123asxcqasdc.github.io/vpncmd-zapret-warp/

Автоматический установщик обхода DPI [zapret](https://github.com/Flowseal/zapret-discord-youtube) и [Cloudflare WARP](https://1.1.1.1/) для Windows и Linux (Ubuntu / Debian).

## Что делает скрипт

1. `install.ps1` скачивает установщик в `%USERPROFILE%\Downloads\VpnCMD` и запускает его с правами администратора (UAC).
2. Скачивает последнюю версию zapret с GitHub и распаковывает её.
3. Устанавливает службу `zapret` со стратегией `general (FAKE TLS AUTO).bat`.
4. Создаёт недостающие пользовательские списки (`lists\*-user.txt`), без которых `winws.exe` не запускается.
5. Если WARP не установлен — скачивает и устанавливает его.
6. Загрузка файлов сопровождается прогресс-баром в стиле apt.

Скрипт можно запускать повторно: уже установленные компоненты пропускаются.

## Установка

Откройте **cmd** и вставьте одну команду:

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://vpn-cmd.p7z.ru/install.ps1 | iex"
```

Команда скачает `VpnCMD.bat` в `%USERPROFILE%\Downloads\VpnCMD`, запустит его с правами администратора и покажет прогресс установки. Дождитесь сообщения `Done.`

При повторном запуске уже установленные компоненты пропускаются.

## Установка на Linux (Ubuntu / Debian)

Одна команда в терминале:

```bash
curl -fsSL https://vpn-cmd.p7z.ru/install-linux.sh | sudo bash
```

Скрипт делает следующее:

1. Спрашивает согласие с лицензией Cloudflare (ToS и Privacy Policy). При отказе WARP не устанавливается.
2. Ставит зависимости из apt (`curl`, `ca-certificates`, `gnupg`, `lsb-release`, `iptables`, `ipset`, `procps`).
3. Скачивает [zapret-linux-easy](https://github.com/ImMALWARE/zapret-linux-easy) и ставит zapret в `/opt/zapret`.
4. Использует `firewall type: iptables` и применяет правила ко **всем WAN-интерфейсам** (пустой `IFACE_WAN`).
5. Создаёт и включает systemd-службу `zapret` с автозапуском.
6. Если лицензия принята — добавляет официальный репозиторий Cloudflare, ставит `cloudflare-warp`, регистрирует и подключает WARP.

Управление:

```bash
systemctl status zapret
systemctl stop zapret
systemctl start zapret
warp-cli status
```

Конфиг zapret — `/opt/zapret/config.txt`, списки — `/opt/zapret/autohosts.txt`, `ipset.txt`, `ignore.txt`, `whitelist.txt`. Проверка конфига — `/opt/zapret/check.sh`.

## Сайт

Откройте **https://vpn-cmd.p7z.ru/** 

На странице есть:

- hero с ASCII-логотипом и командой установки
- разделы «О проекте», «Установка», «Возможности»
- команда установки с кнопкой `copy` в hero, в разделе установки и в футере
- ссылки на GitHub, zapret и Cloudflare WARP

## Требования

- Windows 10/11
- Windows PowerShell 5.1
- Права администратора
- Доступ к `vpn-cmd.p7z.ru`, `github.com` и `downloads.cloudflareclient.com`

### Linux

- Ubuntu или Debian
- systemd и `sudo`
- Доступ к `vpn-cmd.p7z.ru`, `github.com` и `pkg.cloudflareclient.com`

## Что создаётся

- папка `zapret_install\` рядом с `VpnCMD.bat` — рабочая папка
- служба Windows `zapret` (автозапуск)
- служба `WinDivert` (устанавливается `winws`)
- при необходимости — Cloudflare WARP

При установке через команду рабочая папка находится в `%USERPROFILE%\Downloads\VpnCMD\zapret_install`.

## Удаление

```bat
sc stop zapret
sc delete zapret
sc stop WinDivert
sc delete WinDivert
```

После этого удалите папку `zapret_install`.

## Примечание

Скрипт устанавливает стороннее ПО. Используйте на свой страх и риск и соблюдайте законодательство вашей страны.
