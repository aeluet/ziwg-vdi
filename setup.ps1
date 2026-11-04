# ZIWG azterketa - mahaigain birtualaren plantilla prestatzeko scripta (Windows).
# Exekutatu PowerShell administratzaile gisa:
#   irm https://raw.githubusercontent.com/aeluet/ziwg-vdi/main/setup.ps1 | iex
#
# Instalatzen du (makina osorako, erabiltzaile guztientzat):
#   - Visual C++ Redistributable, Git, Node.js LTS, VS Code (instalatzaile ofizialak, winget gabe)
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

function Install-Download($name, $url, $file, $arguments) {
    Write-Host "   $name"
    $path = "$env:TEMP\$file"
    Invoke-WebRequest -Uri $url -OutFile $path -UserAgent 'Mozilla/5.0'
    if ($file -like '*.msi') {
        $process = Start-Process msiexec.exe -ArgumentList "/i `"$path`" $arguments" -Wait -PassThru
    } else {
        $process = Start-Process $path -ArgumentList $arguments -Wait -PassThru
    }
    Remove-Item $path -ErrorAction SilentlyContinue
    # 3010 = success, reboot required; 1638 = a newer version is already installed.
    if ($process.ExitCode -notin 0, 3010, 1638) {
        Write-Host "   $name instalatzaileak $($process.ExitCode) kodea itzuli du" -ForegroundColor Yellow
    }
}

Step 'Instalatzaile ofizialak: VC++ Redistributable, Git, Node.js LTS, VS Code'
Install-Download 'Visual C++ Redistributable' 'https://aka.ms/vs/17/release/vc_redist.x64.exe' 'vc_redist.x64.exe' '/install /quiet /norestart'

$gitRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UserAgent 'Mozilla/5.0'
$gitAsset = $gitRelease.assets | Where-Object { $_.name -match '^Git-[\d.]+-64-bit\.exe$' } | Select-Object -First 1
Install-Download "Git ($($gitAsset.name))" $gitAsset.browser_download_url $gitAsset.name '/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES'

$nodeLts = (Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json') | Where-Object { $_.lts } | Select-Object -First 1
$nodeMsi = "node-$($nodeLts.version)-x64.msi"
Install-Download "Node.js $($nodeLts.version)" "https://nodejs.org/dist/$($nodeLts.version)/$nodeMsi" $nodeMsi '/qn /norestart'

Install-Download 'VS Code' 'https://update.code.visualstudio.com/latest/win32-x64/stable' 'VSCodeSetup-x64.exe' '/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath'
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
