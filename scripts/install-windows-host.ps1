# Jarvis Windows host bootstrap
# Run from the repository root in PowerShell.
$ErrorActionPreference = "Stop"

if (-not (Test-Path "pyproject.toml") -or -not (Test-Path "jarvis_api/main.py")) {
    throw "Open PowerShell in the Jarvis repository root first."
}

$py = Get-Command py -ErrorAction SilentlyContinue
if ($py) {
    & py -3.11 --version
    if ($LASTEXITCODE -ne 0) { throw "Python 3.11+ is required. Install Python 3.11 or newer." }
    $Python = "py"
    $PythonArgs = @("-3.11")
} else {
    $Python = "python"
    $version = & python -c "import sys; print(sys.version_info >= (3,11))"
    if ($version -ne "True") { throw "Python 3.11+ is required." }
    $PythonArgs = @()
}

if (-not (Test-Path ".venv")) {
    & $Python @PythonArgs -m venv .venv
}
$VenvPython = Join-Path (Get-Location) ".venv\Scripts\python.exe"
& $VenvPython -m pip install --upgrade pip
& $VenvPython -m pip install -e ".[dev,windows-agent]"

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
}
$envText = Get-Content ".env" -Raw
if ($envText -notmatch "(?m)^JARVIS_REMOTE_GATEWAY_TOKEN=.+$") {
    $token = & $VenvPython -c "import secrets; print(secrets.token_urlsafe(48))"
    if ($envText -match "(?m)^JARVIS_REMOTE_GATEWAY_TOKEN=.*$") {
        $envText = [regex]::Replace($envText, "(?m)^JARVIS_REMOTE_GATEWAY_TOKEN=.*$", "JARVIS_REMOTE_GATEWAY_TOKEN=$token")
    } else {
        $envText += "`r`nJARVIS_REMOTE_GATEWAY_TOKEN=$token`r`n"
    }
    Set-Content -Path ".env" -Value $envText -NoNewline
    Write-Host "Generated a private remote gateway token in .env. Do not share or commit this file." -ForegroundColor Green
}

Write-Host ""
Write-Host "Jarvis PC host dependencies are installed." -ForegroundColor Green
Write-Host "Next: edit .env and set JARVIS_API_KEY, JARVIS_MODEL and JARVIS_BASE_URL for your chosen OpenAI-compatible provider."
Write-Host "Then run: .\scripts\start-windows-host.ps1"
