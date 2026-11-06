$ErrorActionPreference = "Stop"
$InstallRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$HostRoot = Join-Path $InstallRoot "host"
$AppExe = Join-Path $InstallRoot "app\jarvis_personal_assistant.exe"
if (-not (Test-Path $AppExe)) { throw "Jarvis desktop app missing. Run installer again." }
if (-not (Test-Path (Join-Path $HostRoot ".venv\Scripts\python.exe"))) { throw "Backend missing. Run installer again." }
$hostScript = Join-Path $HostRoot "scripts\start-windows-host.ps1"
$agentScript = Join-Path $HostRoot "scripts\start-windows-agent.ps1"
$hostArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $hostScript)
$agentArgs = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $agentScript)
Start-Process powershell.exe -WindowStyle Minimized -ArgumentList $hostArgs -WorkingDirectory $HostRoot
Start-Sleep -Seconds 3
Start-Process powershell.exe -WindowStyle Minimized -ArgumentList $agentArgs -WorkingDirectory $HostRoot
$healthy = $false
for ($i = 0; $i -lt 20; $i++) {
  try { $response = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 2; if ($response.StatusCode -eq 200) { $healthy = $true; break } }
  catch { Start-Sleep -Seconds 1 }
}
if (-not $healthy) { Write-Warning "Backend did not respond yet. Check minimized PowerShell windows and host\.env." }
Start-Process $AppExe
