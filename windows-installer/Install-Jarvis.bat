@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Jarvis.ps1"
if errorlevel 1 (
  echo.
  echo Jarvis installation did not complete. Read the error above.
  pause
)
