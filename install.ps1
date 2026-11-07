# VpnCMD bootstrap installer
# Usage in cmd:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://vpn-cmd.p7z.ru/install.ps1 | iex"
#
# Downloads VpnCMD.bat to %USERPROFILE%\Downloads\VpnCMD and runs it elevated.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$url = 'https://vpn-cmd.p7z.ru/VpnCMD.bat'

$base = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
if (-not (Test-Path -LiteralPath $base)) {
    $base = [Environment]::GetFolderPath('UserProfile')
}
$dir = Join-Path $base 'VpnCMD'
if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$bat = Join-Path $dir 'VpnCMD.bat'

Write-Host ''
Write-Host '  VpnCMD' -ForegroundColor Green
Write-Host '  zapret + Cloudflare WARP installer' -ForegroundColor DarkGray
Write-Host ''
Write-Host ('  downloading ' + $url) -ForegroundColor DarkGray

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $bat -UseBasicParsing
} catch {
    Write-Host ('  [ERROR] download failed: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

Write-Host ('  saved to ' + $bat) -ForegroundColor DarkGray

if ($env:VPNCMD_DRYRUN -eq '1') {
    Write-Host '  dry run: launch skipped (VPNCMD_DRYRUN=1)' -ForegroundColor Yellow
    return
}

Write-Host '  starting installer...' -ForegroundColor DarkGray
Write-Host ''

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    & $bat
} else {
    try {
        Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', ('"' + $bat + '"')) -Verb RunAs -Wait | Out-Null
    } catch {
        Write-Host ('  [ERROR] ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}
