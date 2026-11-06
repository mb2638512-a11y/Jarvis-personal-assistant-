$ErrorActionPreference = "Stop"
$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot = Join-Path $env:LOCALAPPDATA "Programs\Jarvis"
$HostRoot = Join-Path $InstallRoot "host"
$AppRoot = Join-Path $InstallRoot "app"
Write-Host "JARVIS WINDOWS INSTALLER" -ForegroundColor Cyan

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "Microsoft winget is required. Install/update App Installer from Microsoft Store, then run Jarvis-Setup.exe again."
}
$pythonOk = $false
if (Get-Command py -ErrorAction SilentlyContinue) {
  & py -3.11 --version *> $null
  $pythonOk = ($LASTEXITCODE -eq 0)
}
if (-not $pythonOk) {
  winget install --id Python.Python.3.11 --exact --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "Python 3.11 installation failed. Install Python 3.11 and rerun Jarvis-Setup.exe." }
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
  throw "Python launcher was not found after installation. Restart Windows and rerun Jarvis-Setup.exe."
}

New-Item -ItemType Directory -Force -Path $HostRoot,$AppRoot | Out-Null
Copy-Item (Join-Path $BundleRoot "host\*") $HostRoot -Recurse -Force
$envExample = Join-Path $BundleRoot "host\.env.example"
if (Test-Path $envExample) { Copy-Item $envExample (Join-Path $HostRoot ".env.example") -Force }
Copy-Item (Join-Path $BundleRoot "app\*") $AppRoot -Recurse -Force
Copy-Item (Join-Path $BundleRoot "Start-Jarvis.ps1") (Join-Path $InstallRoot "Start-Jarvis.ps1") -Force

Push-Location $HostRoot
try {
  & .\scripts\install-windows-host.ps1
  if ($LASTEXITCODE -ne 0) { throw "Backend dependency installation failed." }
} finally { Pop-Location }

$launcher = Join-Path $InstallRoot "Start-Jarvis.ps1"
$shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Jarvis.lnk"
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launcher)
$shortcut.WorkingDirectory = $InstallRoot
$shortcut.IconLocation = Join-Path $AppRoot "jarvis_personal_assistant.exe"
$shortcut.Save()

# Also register Jarvis in the current user's Start Menu so it is easy to find
# even if the desktop shortcut is hidden or the desktop is not visible.
$startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "Jarvis"
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$startMenuShortcut = $ws.CreateShortcut((Join-Path $startMenu "Jarvis.lnk"))
$startMenuShortcut.TargetPath = "powershell.exe"
$startMenuShortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launcher)
$startMenuShortcut.WorkingDirectory = $InstallRoot
$startMenuShortcut.IconLocation = Join-Path $AppRoot "jarvis_personal_assistant.exe"
$startMenuShortcut.Save()

Write-Host "Jarvis installed at $InstallRoot" -ForegroundColor Green
Write-Host "Next: open Jarvis and add your AI provider in the PC Model Control screen. API keys are encrypted in the PC vault." -ForegroundColor Cyan
