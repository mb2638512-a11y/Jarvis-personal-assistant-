# Publish the localhost-only Jarvis API privately to the Tailscale network.
$ErrorActionPreference = "Stop"
$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tailscale) { throw "Install Tailscale and sign in on this PC first." }
try {
    $health = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -TimeoutSec 3 -UseBasicParsing
    if ($health.StatusCode -ne 200) { throw "Jarvis API is not healthy." }
} catch {
    throw "Start Jarvis first with .\scripts\start-windows-host.ps1. Details: $($_.Exception.Message)"
}
& tailscale serve --bg 8000
if ($LASTEXITCODE -ne 0) { throw "Tailscale Serve could not be configured. Check Tailscale login and tailnet HTTPS settings." }
& tailscale serve status
Write-Host "Use the private HTTPS URL shown above as JARVIS_BASE_URL on paired remote devices." -ForegroundColor Green
