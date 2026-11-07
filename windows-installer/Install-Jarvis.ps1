param([string]$InstallRoot = (Join-Path $env:LOCALAPPDATA "Programs\Jarvis"))
$ErrorActionPreference = "Stop"
$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$HostRoot = Join-Path $InstallRoot "host"
$AppRoot = Join-Path $InstallRoot "app"
Write-Host "JARVIS WINDOWS INSTALLER" -ForegroundColor Cyan

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "Microsoft winget is required. Install/update App Installer from Microsoft Store, then run Jarvis Setup again."
}
$pythonOk = $false
if (Get-Command py -ErrorAction SilentlyContinue) {
  & py -3.11 --version *> $null
  $pythonOk = ($LASTEXITCODE -eq 0)
}
if (-not $pythonOk) {
  winget install --id Python.Python.3.11 --exact --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "Python 3.11 installation failed. Install Python 3.11 and rerun Jarvis Setup." }
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
  throw "Python launcher was not found after installation. Restart Windows and rerun Jarvis Setup."
}

New-Item -ItemType Directory -Force -Path $HostRoot,$AppRoot | Out-Null
Copy-Item (Join-Path $BundleRoot "host\*") $HostRoot -Recurse -Force
Copy-Item (Join-Path $BundleRoot "app\*") $AppRoot -Recurse -Force
Copy-Item (Join-Path $BundleRoot "Start-Jarvis.ps1") (Join-Path $InstallRoot "Start-Jarvis.ps1") -Force
$launcherSource = Join-Path $BundleRoot "JarvisLauncher.exe"
if (-not (Test-Path $launcherSource)) { throw "Native Jarvis launcher is missing from the installer package." }
Copy-Item $launcherSource (Join-Path $InstallRoot "JarvisLauncher.exe") -Force

Push-Location $HostRoot
try {
  & .\scripts\install-windows-host.ps1
  if ($LASTEXITCODE -ne 0) { throw "Backend dependency installation failed." }
} finally { Pop-Location }

# Register the native launcher for Windows Search and Run.
$launcherExe = Join-Path $InstallRoot "JarvisLauncher.exe"
$appPathKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Jarvis.exe"
New-Item -Path $appPathKey -Force | Out-Null
Set-Item -Path $appPathKey -Value $launcherExe
New-ItemProperty -Path $appPathKey -Name "Path" -Value $InstallRoot -PropertyType String -Force | Out-Null

Write-Host "Jarvis installed at $InstallRoot" -ForegroundColor Green
Write-Host "Use the Jarvis shortcut in Start Menu to launch the desktop app." -ForegroundColor Cyan
