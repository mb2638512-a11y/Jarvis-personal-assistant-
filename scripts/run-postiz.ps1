$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PostizDir = Join-Path $Root "backend/vendor/postiz-app"
$ComposeFile = Join-Path $PostizDir "docker-compose.yaml"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker Desktop/Engine is required."
}
if (-not (Test-Path $ComposeFile)) {
    throw "Postiz source missing. Run: git submodule update --init --recursive"
}

Write-Host "Starting pinned open-source Postiz stack from $PostizDir"
Write-Host "Review Postiz environment requirements and license before public exposure."
docker compose -f $ComposeFile up -d --build
if ($LASTEXITCODE -ne 0) { throw "Postiz Docker Compose startup failed." }
docker compose -f $ComposeFile ps
