# Jarvis Windows host bootstrap
# Run from the installed host directory or repository root.
$ErrorActionPreference = "Stop"

if (-not (Test-Path "pyproject.toml") -or -not (Test-Path "jarvis_api/main.py")) {
    throw "Jarvis host files are incomplete. Rerun the Jarvis installer."
}

$Python = $env:JARVIS_BOOTSTRAP_PYTHON
$PythonArgs = @()
if (-not $Python -or -not (Test-Path $Python)) {
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        & $py.Source -3.11 --version
        if ($LASTEXITCODE -eq 0) {
            $Python = $py.Source
            $PythonArgs = @("-3.11")
        }
    }
}
if (-not $Python) {
    $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pythonCommand) {
        $version = & $pythonCommand.Source -c "import sys; print(sys.version_info >= (3,11) and sys.version_info < (3,12))"
        if ($version -eq "True") { $Python = $pythonCommand.Source }
    }
}
if (-not $Python) { throw "Python 3.11 is required. Run Jarvis Setup again after installing Python 3.11." }

$PythonVersion = & $Python @PythonArgs -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ($PythonVersion -ne "3.11") { throw "Jarvis requires Python 3.11; detected $PythonVersion." }

if (-not (Test-Path ".venv")) {
    & $Python @PythonArgs -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw "Could not create Jarvis Python environment." }
}
$VenvPython = Join-Path (Get-Location) ".venv\\Scripts\\python.exe"
& $VenvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "Could not update pip." }
& $VenvPython -m pip install -e ".[dev,windows-agent]"
if ($LASTEXITCODE -ne 0) { throw "Could not install Jarvis backend dependencies." }

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
Write-Host "Add your model provider in Jarvis Settings to enable AI chat."
