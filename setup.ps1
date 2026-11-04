# ZIWG azterketa - mahaigain birtualaren plantilla prestatzeko scripta (Windows).
# Exekutatu PowerShell administratzaile gisa:
#   irm https://raw.githubusercontent.com/aeluet/ziwg-vdi/main/setup.ps1 | iex
#
# Instalatzen du (makina osorako, erabiltzaile guztientzat):
#   - Visual C++ Redistributable, Git, Node.js LTS, VS Code (winget)
#   - PHP 8.5 NTS x64 (windows.php.net) -> C:\Tools\php, php.ini Laravelerako
#   - Composer -> C:\Tools\composer
#   - Cheatsheet-a mahaigain publikoan (C:\Users\Public\Desktop)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw = 'https://raw.githubusercontent.com/aeluet/ziwg-vdi/main'
$Tools = 'C:\Tools'
$PhpDir = "$Tools\php"
$ComposerDir = "$Tools\composer"
$PublicDesktop = "$env:PUBLIC\Desktop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'PowerShell administratzaile gisa ireki behar da.' -ForegroundColor Red
    return
}

New-Item -ItemType Directory -Force -Path $Tools | Out-Null
Start-Transcript -Path "$Tools\ziwg-setup.log" -Append | Out-Null

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Add-MachinePath($dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (($current -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', "$current;$dir", 'Machine')
    }
    Refresh-Path
}

function Install-Winget($id) {
    Write-Host "   $id"
    winget install --id $id --exact --silent --scope machine --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        # -1978335189 = already installed. Some packages have no machine scope: retry without it.
        winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    }
}

Step 'winget paketeak: VC++ Redistributable, Git, Node.js LTS, VS Code'
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host 'winget ez dago eskuragarri. Instalatu "App Installer" Microsoft Store-etik eta berriro exekutatu.' -ForegroundColor Red
    Stop-Transcript | Out-Null
    return
}
foreach ($id in 'Microsoft.VCRedist.2015+.x64', 'Git.Git', 'OpenJS.NodeJS.LTS', 'Microsoft.VisualStudioCode') {
    Install-Winget $id
}
Refresh-Path

Step 'PHP 8.5 (NTS x64)'
$releases = Invoke-RestMethod -Uri 'https://windows.php.net/downloads/releases/releases.json' -UserAgent 'Mozilla/5.0'
$zipName = $releases.'8.5'.'nts-vs17-x64'.zip.path
Write-Host "   $zipName"
$zipPath = "$env:TEMP\$zipName"
Invoke-WebRequest -Uri "https://windows.php.net/downloads/releases/$zipName" -OutFile $zipPath -UserAgent 'Mozilla/5.0'
if (Test-Path $PhpDir) { Remove-Item -Recurse -Force $PhpDir }
Expand-Archive -Path $zipPath -DestinationPath $PhpDir
Remove-Item $zipPath

$ini = Get-Content "$PhpDir\php.ini-development"
$extensions = 'curl', 'fileinfo', 'gd', 'intl', 'mbstring', 'openssl', 'pdo_sqlite', 'sqlite3', 'zip'
$ini = $ini -replace '^;\s*extension_dir\s*=\s*"ext"', 'extension_dir = "ext"'
foreach ($ext in $extensions) {
    $ini = $ini -replace "^;extension=$ext\s*$", "extension=$ext"
}
$ini = $ini -replace '^upload_max_filesize\s*=.*', 'upload_max_filesize = 8M'
$ini = $ini -replace '^post_max_size\s*=.*', 'post_max_size = 10M'
$ini = $ini -replace '^memory_limit\s*=.*', 'memory_limit = 512M'
$ini = $ini -replace '^;date.timezone\s*=.*', 'date.timezone = Europe/Madrid'
Set-Content -Path "$PhpDir\php.ini" -Value $ini -Encoding ASCII
Add-MachinePath $PhpDir

Step 'Composer'
New-Item -ItemType Directory -Force -Path $ComposerDir | Out-Null
Invoke-WebRequest -Uri 'https://getcomposer.org/download/latest-stable/composer.phar' -OutFile "$ComposerDir\composer.phar"
Set-Content -Path "$ComposerDir\composer.bat" -Value '@php "%~dp0composer.phar" %*' -Encoding ASCII
Add-MachinePath $ComposerDir

Step 'Cheatsheet-a mahaigainean'
Invoke-WebRequest -Uri "$RepoRaw/ZIWG-CheatSheet-Laravel.pdf" -OutFile "$PublicDesktop\ZIWG CheatSheet - Laravel (1. ebaluazioa).pdf"

Step 'Egiaztapena'
$extCheck = "$env:TEMP\ziwg-ext-check.php"
Set-Content -Path $extCheck -Encoding ASCII -Value @'
<?php
$missing = array_diff(['pdo_sqlite', 'sqlite3', 'mbstring', 'openssl', 'fileinfo', 'curl', 'zip', 'gd', 'intl'], get_loaded_extensions());
echo $missing ? 'FALTA: ' . implode(', ', $missing) : 'OK';
'@
$checks = [ordered]@{
    'PHP'       = { php -v | Select-Object -First 1 }
    'Luzapenak' = { php $extCheck }
    'Composer'  = { (composer --version --no-ansi) -replace '^Composer version (\S+).*', '$1' }
    'Node'      = { node --version }
    'npm'       = { npm --version }
    'Git'       = { git --version }
    'VS Code'   = { (code --version)[0] }
}
$failed = $false
foreach ($name in $checks.Keys) {
    try {
        $result = & $checks[$name] 2>$null
        if (-not $result -or "$result" -like 'FALTA*') { throw "$result" }
        Write-Host ("   {0,-10} {1}" -f $name, $result) -ForegroundColor Green
    } catch {
        Write-Host ("   {0,-10} HUTS: {1}" -f $name, $_) -ForegroundColor Red
        $failed = $true
    }
}

Stop-Transcript | Out-Null
if ($failed) {
    Write-Host "`nZerbaitek huts egin du. Erregistroa: $Tools\ziwg-setup.log" -ForegroundColor Red
} else {
    Write-Host "`nDena prest. Itxi eta ireki terminala PATH berria hartzeko." -ForegroundColor Green
}
