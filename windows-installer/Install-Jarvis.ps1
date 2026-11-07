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
  # Resolve the py launcher to the actual 3.11 interpreter. Passing py.exe
  # through to the bootstrap loses the -3.11 selector and can create no venv.
  $py = Get-Command py.exe -ErrorAction SilentlyContinue
  if ($py) {
    $resolved = & $py.Source -3.11 -c "import sys; print(sys.executable)" 2>$null
    if ($LASTEXITCODE -eq 0 -and $resolved) {
      $resolved = $resolved.Trim()
      if (Test-Path $resolved) { return @{ Exe = $resolved; Args = @() } }
    }
  }

  $python = Get-Command python.exe -ErrorAction SilentlyContinue
  if ($python) {
    $version = & $python.Source -c "import sys; print(sys.version_info >= (3,11) and sys.version_info < (3,12))" 2>$null
    if ($version -eq "True") { return @{ Exe = $python.Source; Args = @() } }
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
    (Join-Path $env:ProgramFiles "Python311\python.exe"),
    (Join-Path ([Environment]::GetFolderPath("ProgramFilesX86")) "Python311\python.exe")
  ) | Where-Object { $_ -and (Test-Path $_) }

  foreach ($candidate in $candidates) {
    $version = & $candidate -c "import sys; print(sys.version_info >= (3,11) and sys.version_info < (3,12))" 2>$null
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
  Write-Host "Creating Jarvis Python environment with $($python.Exe)..."
  & .\scripts\install-windows-host.ps1
  if (-not (Test-Path (Join-Path $HostRoot ".venv\Scripts\python.exe"))) {
    throw "Jarvis setup did not create host\.venv\Scripts\python.exe. Check Python and pip installation."
  }
} finally {
  Pop-Location
}

$launcherExe = Join-Path $InstallRoot "Jarvis.exe"
$appPathKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Jarvis.exe"
New-Item -Path $appPathKey -Force | Out-Null
Set-Item -Path $appPathKey -Value $launcherExe
New-ItemProperty -Path $appPathKey -Name "Path" -Value $InstallRoot -PropertyType String -Force | Out-Null
Write-Host "Jarvis installed at $InstallRoot" -ForegroundColor Green
Write-Host "Start Menu and Desktop shortcuts now point to Jarvis.exe." -ForegroundColor Cyan
