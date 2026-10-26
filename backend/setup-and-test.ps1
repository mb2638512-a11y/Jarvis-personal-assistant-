$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Run from this script's directory. Upstream projects stay isolated in backend/.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Ensure-Repo([string]$Url, [string]$Path) {
  if (Test-Path (Join-Path $Path '.git')) {
    Write-Host "Updating $Path"
    git -C $Path fetch --all --prune
  } elseif (Test-Path $Path) {
    throw "Path exists but is not a git repository: $Path"
  } else {
    git clone $Url $Path
    if ($LASTEXITCODE -ne 0) { throw "git clone failed: $Url" }
  }
}

Ensure-Repo 'https://github.com/FindlayHi/atticus-windows.git' 'atticus'
Ensure-Repo 'https://github.com/google/artemis.git' 'artemis'

$report = @()

# Atticus documented checks: Python unit tests + brain self-test. Windows executable
# self-test is attempted only if a built executable exists.
Push-Location (Join-Path $root 'atticus')
try {
  $env:PYTHONUTF8 = '1'
  python -m unittest discover -s tests -v
  $unitExit = $LASTEXITCODE
  python atticus.py --selftest
  $selfExit = $LASTEXITCODE
  $exe = Get-ChildItem -Path . -Filter 'Atticus.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  $exeExit = 'SKIPPED (Atticus.exe not built/found)'
  if ($exe) { & $exe.FullName --selftest; $exeExit = $LASTEXITCODE }
  $report += [pscustomobject]@{ Project='Atticus'; UnitTests=$unitExit; PythonSelfTest=$selfExit; WindowsExeSelfTest=$exeExit }
} finally { Pop-Location }

# ARTEMIS: install locked dependencies, then run repository's documented test target.
Push-Location (Join-Path $root 'artemis')
try {
  if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw 'uv is required for ARTEMIS verification. Install uv, then rerun this script.'
  }
  uv sync --locked
  if ($LASTEXITCODE -ne 0) { throw 'ARTEMIS dependency sync failed.' }
  uv run pytest
  $pytestExit = $LASTEXITCODE
  $report += [pscustomobject]@{ Project='ARTEMIS'; DependencySync='PASS'; Pytest=$pytestExit; DeviceTests='NOT RUN (requires authorized Android device/emulator)' }
} finally { Pop-Location }

$reportPath = Join-Path $root 'test-reports'
New-Item -ItemType Directory -Force -Path $reportPath | Out-Null
$reportFile = Join-Path $reportPath ("verification-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$report | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $reportFile
$report | Format-Table -AutoSize
Write-Host "Report saved: $reportFile"
if ($report | Where-Object { $_.UnitTests -is [int] -and $_.UnitTests -ne 0 -or $_.PythonSelfTest -is [int] -and $_.PythonSelfTest -ne 0 -or $_.Pytest -is [int] -and $_.Pytest -ne 0 }) { exit 1 }
