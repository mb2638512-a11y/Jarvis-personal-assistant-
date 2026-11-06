# Start the local Windows agent against the Jarvis host on this same PC.
$ErrorActionPreference = "Stop"
$VenvPython = Join-Path (Get-Location) ".venv\Scripts\python.exe"
if (-not (Test-Path $VenvPython)) { throw "Run .\scripts\install-windows-host.ps1 first." }
$env:JARVIS_BASE_URL = "http://127.0.0.1:8000"
$envFile = Get-Content ".env"
$tokenLine = $envFile | Where-Object { $_ -match "^JARVIS_REMOTE_GATEWAY_TOKEN=" } | Select-Object -First 1
if (-not $tokenLine) { throw "JARVIS_REMOTE_GATEWAY_TOKEN is missing from .env." }
$env:JARVIS_REMOTE_GATEWAY_TOKEN = $tokenLine.Substring("JARVIS_REMOTE_GATEWAY_TOKEN=".Length).Trim().Trim('"')
$env:JARVIS_AGENT_ID = "main-windows-pc"
& $VenvPython "windows/jarvis_device_agent.py"
