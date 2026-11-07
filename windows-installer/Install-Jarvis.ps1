param([string]$InstallRoot = (Join-Path $env:LOCALAPPDATA "Programs\Jarvis"))
$ErrorActionPreference = "Stop"
$BundleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$HostRoot = Join-Path $InstallRoot "host"
$AppRoot = Join-Path $InstallRoot "app"
Write-Host "JARVIS WINDOWS INSTALLER" -ForegroundColor Cyan
function Refresh-ProcessPath {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = @($machinePath, $userPath) -join ";"
}
function Find-Python311 {
  $py = Get-Command py.exe -ErrorAction SilentlyContinue
  if ($py) {
    & $py.Source -3.11 --version *> $null
    if ($LASTEXITCODE -eq 0) { return @{ Exe = $py.Source; Args = @("-3.11") } }
  }
  $python = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($python) {
    $version = & $python.Source -c "import sys; print(sys.version_info >= (3,11) and sys.version_info < (3,12))"
    if ($version -eq "True") { return @{ Exe = $python.Source; Args = @() } }
  }
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
    (Join-Path $env:ProgramFiles "Python311\python.exe"),
    (Join-Path \${env:ProgramFiles(x86)} "Python311\python.exe")
  ) | Where-Object { $_ -and (Test-Path $_) }
  foreach ($candidate in $candidates) {
    $version = & $candidate -c "import sys; print(sys.version_info >= (3,11) and sys.version_info < (3,12))"
    if ($version -eq "True") { return @{ Exe = $candidate; Args = @() } }
  }
  return $null
}
$python = Find-Python311
if (-not $python) {
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if (-not $winget) {
    throw "Python 3.11 is required. Install Python 3.11 or Microsoft App Installer (winget), then run Jarvis Setup again."
  }
  & $winget.Source install --id Python.Python.3.11 --exact --silent --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) { throw "Python 3.11 installation failed. Install Python 3.11 manually and rerun Jarvis Setup." }
  Refresh-ProcessPath
  $python = Find-Python311
}
if (-not $python) {
  throw "Python 3.11 was installed but could not be located. Restart Windows, then run Jarvis Setup again."
}
New-Item -ItemType Directory -Force -Path $HostRoot,$AppRoot | Out-Null
Copy-Item (Join-Path $BundleRoot "host\*") $HostRoot -Recurse -Force
Copy-Item (Join-Path $BundleRoot "app\*") $AppRoot -Recurse -Force
Copy-Item (Join-Path $BundleRoot "Start-Jarvis.ps1") (Join-Path $InstallRoot "Start-Jarvis.ps1") -Force
$launcherSource = Join-Path $BundleRoot "Jarvis.exe"
if (-not (Test-Path $launcherSource)) { throw "Jarvis.exe launcher is missing from the installer package." }
Copy-Item $launcherSource (Join-Path $InstallRoot "Jarvis.exe") -Force
$env:JARVIS_BOOTSTRAP_PYTHON = $python.Exe
Push-Location $HostRoot
try {
  & .\scripts\install-windows-host.ps1
  if ($LASTEXITCODE -ne 0) { throw "Backend dependency installation failed." }
} finally { Pop-Location }
$launcherExe = Join-Path $InstallRoot "Jarvis.exe"
$appPathKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Jarvis.exe"
New-Item -Path $appPathKey -Force | Out-Null
Set-Item -Path $appPathKey -Value $launcherExe
New-ItemProperty -Path $appPathKey -Name "Path" -Value $InstallRoot -PropertyType String -Force | Out-Null
Write-Host "Jarvis installed at $InstallRoot" -ForegroundColor Green
Write-Host "Start Menu and Desktop shortcuts now point to Jarvis.exe." -ForegroundColor Cyan
