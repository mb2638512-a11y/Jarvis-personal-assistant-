# Keep Jarvis bound to localhost; Tailscale Serve provides private HTTPS access to paired devices.
$ErrorActionPreference = "Stop"
$envFile = Join-Path (Get-Location) ".env"
if (-not (Test-Path $envFile)) { throw "Jarvis .env is missing." }

$tailscaleCommand = Get-Command tailscale.exe -ErrorAction SilentlyContinue
$tailscalePath = if ($tailscaleCommand) { $tailscaleCommand.Source } else { Join-Path $env:ProgramFiles "Tailscale\tailscale.exe" }
if (-not (Test-Path $tailscalePath)) { $tailscalePath = $null }
if (-not $tailscalePath) {
  Write-Warning "Tailscale is not installed. Install and sign in to Tailscale on both PC and Android to enable private HTTPS pairing."
  return
}

try {
  # Serve is tailnet-only; never use Funnel or a public tunnel for the Jarvis API.
  $serveOutput = & $tailscalePath serve --bg 8000 2>&1 | Out-String
  $statusOutput = & $tailscalePath serve status 2>&1 | Out-String
  $combined = $serveOutput + " " + $statusOutput
  $match = [regex]::Match($combined, 'https://[A-Za-z0-9.-]+\.ts\.net')
  if (-not $match.Success) {
    Write-Warning "Tailscale Serve was invoked, but its HTTPS hostname was not detected. Enable HTTPS certificates in your tailnet and run 'tailscale serve 8000' once."
    return
  }
  $publicUrl = $match.Value.TrimEnd('/')
  $lines = @(Get-Content $envFile)
  $newLines = @()
  $found = $false
  foreach ($line in $lines) {
    if ($line -match '^JARVIS_PUBLIC_BASE_URL=') {
      $newLines += "JARVIS_PUBLIC_BASE_URL=$publicUrl"
      $found = $true
    } else { $newLines += $line }
  }
  if (-not $found) { $newLines += "JARVIS_PUBLIC_BASE_URL=$publicUrl" }
  Set-Content -Path $envFile -Value $newLines -Encoding UTF8
  Write-Host "Private Jarvis HTTPS endpoint: $publicUrl" -ForegroundColor Green
} catch {
  Write-Warning "Could not configure Tailscale Serve automatically: $_"
  Write-Warning "Run 'tailscale serve 8000' and set JARVIS_PUBLIC_BASE_URL in .env."
}
