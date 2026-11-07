@echo off
setlocal EnableExtensions
title VpnCMD
set "SELF=%~f0"
set "ORIGDIR=%~dp0"

rem ---- Elevate if not running as administrator ----
powershell -NoProfile -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if errorlevel 1 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

rem ---- Extract the embedded PowerShell script (everything after :PS1_BEGIN) ----
set "PS1=%TEMP%\VpnCMD.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; try { $lines = [System.IO.File]::ReadAllLines($env:SELF); $i = [Array]::IndexOf($lines, ':PS1_BEGIN'); if ($i -lt 0) { exit 2 }; $enc = New-Object System.Text.UTF8Encoding -ArgumentList $true; [System.IO.File]::WriteAllLines($env:PS1, $lines[($i + 1)..($lines.Length - 1)], $enc) } catch { Write-Host ('[ERROR] ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 goto :extract_failed
if not exist "%PS1%" goto :extract_failed

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%errorLevel%"
del /f /q "%PS1%" >nul 2>&1
exit /b %RC%

:extract_failed
echo [ERROR] Failed to create PowerShell script.
pause
exit /b 1

:PS1_BEGIN
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'VpnCMD'

# Force TLS 1.2 (Windows PowerShell 5.1 may default to older protocols)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # ignore
}

function Show-Banner {
    Clear-Host
    $art = @(
        '  __     __            ____ __  __ ____',
        '   \ \   / / __  _ __  / ___|  \/  |  _ \',
        '    \ \ / / ''_ \| ''_ \| |   | |\/| | | | |',
        '     \ V /| |_) | | | | |___| |  | | |_| |',
        '      \_/ | .__/|_| |_|\____|_|  |_|____/',
        '          |_|'
    )
    Write-Host ''
    foreach ($line in $art) {
        foreach ($ch in $line.ToCharArray()) {
            Write-Host -NoNewline $ch
            Start-Sleep -Milliseconds 10
        }
        Write-Host ''
    }
    Write-Host ''
    Write-Host '============================================'
    Write-Host ' VpnCMD - Zapret + WARP Auto Installer'
    Write-Host '============================================'
    Write-Host ''
    Start-Sleep -Seconds 1
}

function Show-Logo {
    Clear-Host
    Write-Host ''
    Write-Host '  __     __            ____ __  __ ____'
    Write-Host '   \ \   / / __  _ __  / ___|  \/  |  _ \'
    Write-Host '    \ \ / / ''_ \| ''_ \| |   | |\/| | | | |'
    Write-Host '     \ V /| |_) | | | | |___| |  | | |_| |'
    Write-Host '      \_/ | .__/|_| |_|\____|_|  |_|____/'
    Write-Host '          |_|'
    Write-Host ''
    Write-Host '============================================'
    Write-Host ' VpnCMD - Zapret + WARP Auto Installer'
    Write-Host '============================================'
    Write-Host ''
}

function Test-ZapretInstalled {
    return ($null -ne (Get-Service -Name 'zapret' -ErrorAction SilentlyContinue))
}

function Test-WarpInstalled {
    if (Get-Service -Name 'warp-svc' -ErrorAction SilentlyContinue) { return $true }
    if (Get-Command 'warp-svc.exe' -ErrorAction SilentlyContinue) { return $true }
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')
    foreach ($p in $paths) {
        if (Get-ItemProperty -Path $p -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Cloudflare WARP*' }) { return $true }
    }
    return $false
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Write-DownloadProgress {
    param(
        [string]$Label,
        [long]$Downloaded,
        [long]$Total,
        [double]$Elapsed,
        [switch]$Done
    )

    $speed = 0.0
    if ($Elapsed -gt 0.2) { $speed = $Downloaded / $Elapsed }

    $barWidth = 40
    try {
        $winWidth = $Host.UI.RawUI.WindowSize.Width
        if ($winWidth -gt 40) { $barWidth = [Math]::Max(10, [Math]::Min(50, $winWidth - 58)) }
    } catch { }

    if ($Total -gt 0) {
        $fraction = [Math]::Min(1.0, $Downloaded / [double]$Total)
        $filled = [int][Math]::Round($fraction * $barWidth)
        if ($filled -gt $barWidth) { $filled = $barWidth }
        $bar = ('#' * $filled) + ('.' * ($barWidth - $filled))
        $percent = [int]($fraction * 100)
        $line = '{0}: {1,3}% [{2}] {3} / {4}  {5}/s' -f $Label, $percent, $bar, (Format-Bytes $Downloaded), (Format-Bytes $Total), (Format-Bytes $speed)
        if ($fraction -lt 1.0 -and $speed -gt 0) {
            $remain = [int](($Total - $Downloaded) / $speed)
            $line += ('  ETA {0:00}:{1:00}' -f [int]($remain / 60), ($remain % 60))
        }
    } else {
        $line = '{0}: {1}  {2}/s' -f $Label, (Format-Bytes $Downloaded), (Format-Bytes $speed)
    }

    $lineWidth = 100
    try {
        $winWidth = $Host.UI.RawUI.WindowSize.Width
        if ($winWidth -gt 1) { $lineWidth = $winWidth - 1 }
    } catch { }

    if ($line.Length -gt $lineWidth) {
        $line = $line.Substring(0, $lineWidth)
    } else {
        $line = $line.PadRight($lineWidth)
    }

    if ($Done) {
        Write-Host ("`r" + $line)
    } else {
        Write-Host -NoNewline ("`r" + $line)
    }
}

function Download-File {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [hashtable]$Headers = @{},
        [string]$Label = 'Downloading',
        [int]$TimeoutSec = 600
    )

    if (-not ('System.Net.Http.HttpClient' -as [type])) {
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch { }

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Url)
    if (-not $Headers.ContainsKey('User-Agent')) {
        [void]$request.Headers.TryAddWithoutValidation('User-Agent', 'Mozilla/5.0')
    }
    foreach ($key in $Headers.Keys) {
        [void]$request.Headers.TryAddWithoutValidation($key, [string]$Headers[$key])
    }

    $response = $null
    $stream = $null
    $file = $null
    try {
        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw ('HTTP ' + [int]$response.StatusCode + ' ' + $response.ReasonPhrase)
        }

        $total = [long]0
        if ($null -ne $response.Content.Headers.ContentLength) {
            $total = [long]$response.Content.Headers.ContentLength
        }

        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $file = [System.IO.File]::Create($OutFile)
        $buffer = New-Object byte[] 81920
        $downloaded = [long]0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastDraw = [DateTime]::MinValue

        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $file.Write($buffer, 0, $read)
            $downloaded += $read
            $now = [DateTime]::UtcNow
            if (($now - $lastDraw).TotalMilliseconds -ge 120) {
                Write-DownloadProgress -Label $Label -Downloaded $downloaded -Total $total -Elapsed $stopwatch.Elapsed.TotalSeconds
                $lastDraw = $now
            }
        }

        Write-DownloadProgress -Label $Label -Downloaded $downloaded -Total $total -Elapsed $stopwatch.Elapsed.TotalSeconds -Done
        $stopwatch.Stop()
    } catch {
        if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue }
        throw
    } finally {
        if ($file) { $file.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

function Install-Zapret {
    param([string]$WorkDir)
    Show-Logo
    Write-Host '============================================'
    Write-Host ' Step 1: Download latest zapret release'
    Write-Host '============================================'
    $apiUrl = 'https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/latest'
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{'User-Agent'='Mozilla/5.0';'Accept'='application/vnd.github+json'} -TimeoutSec 30 -ErrorAction Stop
    } catch {
        Write-Host ('[ERROR] Failed to fetch GitHub API: ' + $_) -ForegroundColor Red
        return $null
    }
    $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { Write-Host '[ERROR] No zip asset found.' -ForegroundColor Red; return $null }
    $zipPath = Join-Path $WorkDir 'zapret_latest.zip'
    Write-Host ('Downloading: ' + $asset.browser_download_url)
    try {
        Download-File -Url $asset.browser_download_url -OutFile $zipPath -Label 'zapret' -TimeoutSec 300
    } catch {
        Write-Host ('[ERROR] Download failed: ' + $_) -ForegroundColor Red
        return $null
    }
    Write-Host 'Download complete.'
    Write-Host 'Extracting...'
    try {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $WorkDir -Force -ErrorAction Stop
    } catch {
        Write-Host ('[ERROR] ' + $_) -ForegroundColor Red
        return $null
    }
    $zapretDir = Get-ChildItem -Path $WorkDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'service.bat') } | Select-Object -First 1
    if (-not $zapretDir) {
        if (Test-Path (Join-Path $WorkDir 'service.bat')) { return $WorkDir }
        Write-Host '[ERROR] service.bat not found.' -ForegroundColor Red
        return $null
    }
    Write-Host ('Found zapret in: ' + $zapretDir.Name)
    return $zapretDir.FullName
}

function Get-WinwsArgs {
    param(
        [Parameter(Mandatory=$true)][string]$ZapretDir,
        [Parameter(Mandatory=$true)][string]$StrategyFile
    )

    $content = Get-Content -LiteralPath $StrategyFile -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) { return $null }

    $lines = $content -split "\r?\n"
    $root = $ZapretDir.TrimEnd('\') + '\'

    # Collect variables defined in the strategy file (BIN, LISTS, ...)
    $vars = @{}
    foreach ($line in $lines) {
        if ($line -match '^\s*set\s+"?([A-Za-z_][A-Za-z0-9_]*)=(.*?)"?\s*$') {
            $name = $Matches[1]
            $value = $Matches[2]
            if ($value) {
                $vars[$name] = $value.Replace('%~dp0', $root)
            }
        }
    }

    # Defaults used by service.bat when the game filter is disabled
    if (-not $vars.ContainsKey('BIN')) { $vars['BIN'] = (Join-Path $ZapretDir 'bin') + '\' }
    if (-not $vars.ContainsKey('LISTS')) { $vars['LISTS'] = (Join-Path $ZapretDir 'lists') + '\' }
    if (-not $vars.ContainsKey('GameFilterTCP')) { $vars['GameFilterTCP'] = '12' }
    if (-not $vars.ContainsKey('GameFilterUDP')) { $vars['GameFilterUDP'] = '12' }

    # Find the line with winws.exe and join caret-continued lines
    $idx = -1
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match 'winws\.exe') { $idx = $i; break }
    }
    if ($idx -lt 0) { return $null }

    $cmd = $lines[$idx]
    while ($cmd.TrimEnd().EndsWith('^') -and ($idx + 1) -lt $lines.Length) {
        $idx++
        $cmd = $cmd.TrimEnd()
        $cmd = $cmd.Substring(0, $cmd.Length - 1) + ' ' + $lines[$idx].Trim()
    }

    $pos = $cmd.IndexOf('winws.exe', [System.StringComparison]::OrdinalIgnoreCase)
    if ($pos -lt 0) { return $null }
    $argsStr = $cmd.Substring($pos + 'winws.exe'.Length).Trim()

    # Drop the closing quote of the winws.exe path, e.g. "...\winws.exe" --wf-tcp=...
    if ($argsStr.StartsWith('"')) { $argsStr = $argsStr.Substring(1).TrimStart() }

    # Expand %VAR% references
    for ($pass = 0; $pass -lt 5; $pass++) {
        $changed = $false
        foreach ($name in @($vars.Keys)) {
            $token = '%' + $name + '%'
            if ($argsStr.Contains($token)) {
                $argsStr = $argsStr.Replace($token, [string]$vars[$name])
                $changed = $true
            }
        }
        if (-not $changed) { break }
    }
    $argsStr = $argsStr.Replace('%~dp0', $root)

    # Remove batch escape characters that are not part of the real arguments
    $argsStr = $argsStr.Replace('^!', '!').Replace('^^', '^').Trim()

    return $argsStr
}

function Initialize-UserLists {
    param([string]$ZapretDir)
    $listsDir = Join-Path $ZapretDir 'lists'
    if (-not (Test-Path -LiteralPath $listsDir)) {
        New-Item -ItemType Directory -Path $listsDir -Force | Out-Null
    }
    $defaults = @{
        'ipset-exclude-user.txt' = @('203.0.113.113/32')
        'list-general-user.txt' = @('# Never leave this file empty', 'domain.example.abc')
        'list-exclude-user.txt' = @('domain.example.abc')
    }
    foreach ($name in $defaults.Keys) {
        $path = Join-Path $listsDir $name
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Host ('Creating default user list: ' + $name)
            Set-Content -LiteralPath $path -Value $defaults[$name] -Encoding ASCII
        }
    }
}

function Install-ZapretService {
    param([string]$ZapretDir)
    Show-Logo
    Write-Host '============================================'
    Write-Host ' Step 2: Install zapret service (FAKE TLS AUTO)'
    Write-Host '============================================'

    $strategyFile = $null
    $preferred = @(
        (Join-Path $ZapretDir 'general (FAKE TLS AUTO).bat'),
        (Join-Path $ZapretDir 'general (FAKE TLS AUTO ALT).bat'),
        (Join-Path $ZapretDir 'general.bat')
    )
    foreach ($candidate in $preferred) {
        if (Test-Path -LiteralPath $candidate) { $strategyFile = $candidate; break }
    }
    if (-not $strategyFile) {
        $strategyFile = Get-ChildItem -LiteralPath $ZapretDir -Filter '*.bat' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike 'service*' -and (Select-String -LiteralPath $_.FullName -Pattern 'winws\.exe' -Quiet) } |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $strategyFile) {
        Write-Host '[ERROR] No strategy .bat file found.' -ForegroundColor Red
        return $false
    }
    Write-Host ('Using strategy: ' + (Split-Path -Leaf $strategyFile))

    $winws = Join-Path (Join-Path $ZapretDir 'bin') 'winws.exe'
    if (-not (Test-Path -LiteralPath $winws)) {
        Write-Host ('[ERROR] winws.exe not found: ' + $winws) -ForegroundColor Red
        return $false
    }

    # The strategy references these user list files; winws refuses to start without them
    Initialize-UserLists -ZapretDir $ZapretDir

    # Enable TCP timestamps (required by zapret)
    & netsh.exe interface tcp set global timestamps=enabled 2>$null | Out-Null

    $argsStr = Get-WinwsArgs -ZapretDir $ZapretDir -StrategyFile $strategyFile
    if ([string]::IsNullOrWhiteSpace($argsStr)) {
        Write-Host '[ERROR] Could not extract winws.exe arguments from the strategy file.' -ForegroundColor Red
        return $false
    }
    Write-Host ('Final args: ' + $argsStr)

    $svcName = 'zapret'
    & sc.exe stop $svcName 2>$null | Out-Null
    & sc.exe delete $svcName 2>$null | Out-Null
    Start-Sleep -Milliseconds 800

    $binPathArg = '"' + $winws + '" ' + $argsStr
    Write-Host 'Creating service...'
    $created = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            New-Service -Name $svcName -BinaryPathName $binPathArg -DisplayName 'zapret' -StartupType Automatic -ErrorAction Stop | Out-Null
            $created = $true
            break
        } catch {
            Start-Sleep -Milliseconds 700
        }
    }
    if (-not $created) {
        Write-Host '[ERROR] Failed to create zapret service.' -ForegroundColor Red
        return $false
    }

    & sc.exe description $svcName 'Zapret DPI bypass software' 2>$null | Out-Null
    Start-Sleep -Milliseconds 300

    try {
        Start-Service -Name $svcName -ErrorAction Stop
    } catch {
        Write-Host ('[WARN] Could not start service: ' + $_.Exception.Message) -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 1
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host '[OK] Zapret service is running.' -ForegroundColor Green
        $name = [System.IO.Path]::GetFileNameWithoutExtension($strategyFile)
        Set-ItemProperty -Path ('HKLM:\System\CurrentControlSet\Services\' + $svcName) -Name 'zapret-discord-youtube' -Value $name -ErrorAction SilentlyContinue
        return $true
    }

    Write-Host '[WARN] Service is not running. Check manually: sc query zapret' -ForegroundColor Yellow
    return $false
}

function Install-Warp {
    param([string]$WorkDir)
    Show-Logo
    Write-Host '============================================'
    Write-Host ' Step 3: Download and install Cloudflare WARP'
    Write-Host '============================================'
    $warpUrl = 'https://1111-releases.cloudflareclient.com/win/latest'
    Get-ChildItem -Path $WorkDir -Filter 'Cloudflare_WARP_*.msi' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $WorkDir -Filter 'WARP_*.msi' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host ('Downloading WARP from: ' + $warpUrl)
    $headers = @{'User-Agent'='Mozilla/5.0'}
    try {
        $resp = Invoke-WebRequest -Uri $warpUrl -Headers $headers -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $cd = $resp.Headers['Content-Disposition']
        $fileName = 'Cloudflare_WARP_latest.msi'
        if ($cd -match 'filename="?([^";]+)"?') { $fileName = $Matches[1] }
    } catch {
        $fileName = 'Cloudflare_WARP_latest.msi'
    }
    $msiPath = Join-Path $WorkDir $fileName
    try {
        Download-File -Url $warpUrl -OutFile $msiPath -Headers $headers -Label 'WARP' -TimeoutSec 600
    } catch {
        Write-Host ('[ERROR] WARP download failed: ' + $_) -ForegroundColor Red
        return $false
    }
    Write-Host ('Found installer: ' + $fileName)
    Write-Host 'Installing WARP silently...'
    try {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', ('"' + $msiPath + '"'), '/qn', '/norestart') -Wait -PassThru -ErrorAction Stop
    } catch {
        Write-Host ('[ERROR] WARP installation failed: ' + $_) -ForegroundColor Red
        return $false
    }
    $code = $p.ExitCode
    Write-Host ('WARP installer exit code: ' + $code)
    switch ($code) {
        0    { Write-Host '[OK] Cloudflare WARP installed.' -ForegroundColor Green; return $true }
        3010 { Write-Host '[OK] Cloudflare WARP installed. Reboot required.' -ForegroundColor Green; return $true }
        1641 { Write-Host '[OK] Cloudflare WARP installed. Reboot initiated.' -ForegroundColor Green; return $true }
        default { Write-Host ('[ERROR] WARP installation failed (code ' + $code + ').') -ForegroundColor Red; return $false }
    }
}

# ============================================================
#  MAIN
# ============================================================
Show-Banner

$baseDir = $env:ORIGDIR
if ([string]::IsNullOrWhiteSpace($baseDir)) { $baseDir = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($baseDir)) { $baseDir = (Get-Location).Path }

$WorkDir = Join-Path $baseDir 'zapret_install'
if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
Set-Location -LiteralPath $WorkDir

Write-Host ('Work dir: ' + $WorkDir)
Write-Host ''

$zapretInstalled = Test-ZapretInstalled
$warpInstalled = Test-WarpInstalled

if ($zapretInstalled) { Write-Host '[CHECK] Zapret service is already installed.' } else { Write-Host '[CHECK] Zapret service is NOT installed.' }
if ($warpInstalled) { Write-Host '[CHECK] Cloudflare WARP is already installed.' } else { Write-Host '[CHECK] Cloudflare WARP is NOT installed.' }
Write-Host ''

if (-not $zapretInstalled) {
    $zd = Install-Zapret -WorkDir $WorkDir
    if ($zd) {
        Install-ZapretService -ZapretDir $zd | Out-Null
    } else {
        Write-Host '[ERROR] Zapret download failed, skipping service install.' -ForegroundColor Red
    }
} else {
    Show-Logo
    Write-Host '============================================'
    Write-Host ' Step 1-2: SKIPPED - Zapret already installed'
    Write-Host '============================================'
}

if (-not $warpInstalled) {
    Install-Warp -WorkDir $WorkDir | Out-Null
} else {
    Show-Logo
    Write-Host '============================================'
    Write-Host ' Step 3: SKIPPED - WARP already installed'
    Write-Host '============================================'
}

Show-Logo
Write-Host '============================================'
Write-Host ' Done.'
Write-Host '============================================'
Write-Host ('Zapret installed in: ' + $WorkDir)
Write-Host ''
Write-Host 'Closing in 5 seconds...'
Start-Sleep -Seconds 5
