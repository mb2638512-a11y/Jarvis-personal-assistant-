$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HostRoot = Join-Path $InstallRoot "host"
$AppExe = Join-Path $InstallRoot "app\jarvis_personal_assistant.exe"
$VenvPython = Join-Path $HostRoot ".venv\Scripts\python.exe"
$hostScript = Join-Path $HostRoot "scripts\start-windows-host.ps1"
$agentScript = Join-Path $HostRoot "scripts\start-windows-agent.ps1"
$logRoot = Join-Path $env:LOCALAPPDATA "Jarvis\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

if (-not (Test-Path $AppExe)) { throw "Jarvis desktop app is missing. Run Jarvis Setup again." }
if (-not (Test-Path $VenvPython)) { throw "Jarvis backend Python environment is missing. Run Jarvis Setup again." }
if (-not (Test-Path $hostScript)) { throw "Jarvis backend startup script is missing." }
if (-not (Test-Path $agentScript)) { throw "Jarvis PC agent startup script is missing." }

$powerShellExe = Join-Path $PSHOME "powershell.exe"
if (-not (Test-Path $powerShellExe)) { $powerShellExe = "powershell.exe" }

function Test-JarvisBackend {
  try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 2
    return ($response.StatusCode -eq 200)
  } catch { return $false }
}

if (-not (Test-JarvisBackend)) {
  $hostArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $hostScript + '"'
  Start-Process -FilePath $powerShellExe -WindowStyle Hidden -ArgumentList $hostArgs -WorkingDirectory $HostRoot -RedirectStandardOutput (Join-Path $logRoot "backend.log") -RedirectStandardError (Join-Path $logRoot "backend-error.log")
}

# Avoid starting a second PC agent when Jarvis is already running.
$agentRunning = $false
try {
  $agentRunning = [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*start-windows-agent.ps1*" })
} catch {
  Add-Content -Path (Join-Path $logRoot "launcher.log") -Value "Could not inspect existing agent process: $_"
}
if (-not $agentRunning) {
  $agentArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $agentScript + '"'
  Start-Process -FilePath $powerShellExe -WindowStyle Hidden -ArgumentList $agentArgs -WorkingDirectory $HostRoot -RedirectStandardOutput (Join-Path $logRoot "agent.log") -RedirectStandardError (Join-Path $logRoot "agent-error.log")
}

# ARTEMIS is optional and starts only when its local configuration is present.
$artemisScript = Join-Path $HostRoot "scripts\start-artemis.ps1"
if (Test-Path $artemisScript) {
  $artemisConfig = Join-Path $HostRoot ".env"
  $hasArtemisKey = (Test-Path $artemisConfig) -and ((Get-Content $artemisConfig -Raw) -match "(?m)^GOOGLE_API_KEY=.+$")
  if ($hasArtemisKey) {
    $artemisArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $artemisScript + '"'
    Start-Process -FilePath $powerShellExe -WindowStyle Hidden -ArgumentList $artemisArgs -WorkingDirectory $HostRoot -RedirectStandardOutput (Join-Path $logRoot "artemis.log") -RedirectStandardError (Join-Path $logRoot "artemis-error.log")
  }
}

$healthy = $false
for ($i = 0; $i -lt 45; $i++) {
  if (Test-JarvisBackend) { $healthy = $true; break }
  Start-Sleep -Seconds 1
}
if (-not $healthy) {
  throw "Jarvis backend did not become ready. Check $logRoot\backend-error.log and host\.env."
}

# Launch the actual Flutter desktop application. No PowerShell window is shown.
Start-Process -FilePath $AppExe -WorkingDirectory (Split-Path -Parent $AppExe)
