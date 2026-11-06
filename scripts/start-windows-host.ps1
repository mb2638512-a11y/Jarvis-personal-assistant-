# Start Jarvis API on localhost only. Use Tailscale Serve for private HTTPS access.
$ErrorActionPreference = "Stop"
$VenvPython = Join-Path (Get-Location) ".venv\Scripts\python.exe"
if (-not (Test-Path $VenvPython)) { throw "Run .\scripts\install-windows-host.ps1 first." }
if (-not (Test-Path ".env")) { throw ".env is missing. Run the installer first." }
& $VenvPython -m uvicorn jarvis_api.main:app --host 127.0.0.1 --port 8000
