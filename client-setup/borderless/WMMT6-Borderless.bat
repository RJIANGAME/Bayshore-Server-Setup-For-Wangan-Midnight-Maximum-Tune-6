@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WMMT6-Borderless.ps1"
if errorlevel 1 (
  echo.
  echo WMMT6 borderless launch failed. Review the error above.
  pause
  exit /b 1
)
