$ErrorActionPreference = "Stop"
$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot = Join-Path $env:LOCALAPPDATA "Programs\Jarvis"
$HostRoot = Join-Path $InstallRoot "host"
$AppRoot = Join-Path $InstallRoot "app"
Write-Host "JARVIS WINDOWS INSTALLER" -ForegroundColor Cyan
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget is required. Update App Installer from Microsoft Store, then rerun." }
$pythonOk = $false
if (Get-Command py -ErrorAction SilentlyContinue) { & py -3.11 --version *> $null; $pythonOk = ($LASTEXITCODE -eq 0) }
if (-not $pythonOk) {
  winget install --id Python.Python.3.11 --exact --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "Python 3.11 installation failed. Install it from python.org and rerun." }
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) { throw "Python launcher not found. Restart Windows or install Python 3.11, then rerun." }
New-Item -ItemType Directory -Force -Path $HostRoot,$AppRoot | Out-Null
Copy-Item (Join-Path $BundleRoot "host\*") $HostRoot -Recurse -Force
Copy-Item (Join-Path $BundleRoot "app\*") $AppRoot -Recurse -Force
Push-Location $HostRoot
try { & .\scripts\install-windows-host.ps1; if ($LASTEXITCODE -ne 0) { throw "Backend dependency installation failed." } } finally { Pop-Location }
$launcher = Join-Path $InstallRoot "Start-Jarvis.ps1"
$shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Jarvis.lnk"
$ws = New-Object -ComObject WScript.Shell
$shortcut = $ws.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launcher)
$shortcut.WorkingDirectory = $InstallRoot
$shortcut.IconLocation = Join-Path $AppRoot "jarvis_personal_assistant.exe"
$shortcut.Save()
Write-Host "Jarvis installed at $InstallRoot" -ForegroundColor Green
$envPath = Join-Path $HostRoot ".env"
$envText = Get-Content $envPath -Raw
if ($envText -notmatch "(?m)^JARVIS_API_KEY=.+$" -or $envText -match "(?m)^JARVIS_MODEL=\s*$") { Start-Process notepad.exe -ArgumentList $envPath -Wait }
$launcherArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launcher)
Start-Process powershell.exe -ArgumentList $launcherArgs -WorkingDirectory $InstallRoot
