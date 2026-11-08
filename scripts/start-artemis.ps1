$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Python = Join-Path $Root ".venv\Scripts\python.exe"
$Launcher = Join-Path $PSScriptRoot "start-artemis.py"
if (-not (Test-Path $Python)) { throw "Jarvis Python environment is missing. Run the Jarvis installer first." }
if (-not (Test-Path $Launcher)) { throw "Jarvis ARTEMIS launcher is missing." }
& $Python $Launcher
if ($LASTEXITCODE -ne 0) {
  Write-Warning "ARTEMIS exited with code $LASTEXITCODE. Check data\artemis-start.log and the ARTEMIS setup requirements."
}
