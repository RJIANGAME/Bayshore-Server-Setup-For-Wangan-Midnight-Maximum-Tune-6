@echo off
setlocal
cd /d "%~dp0"
powershell.exe -Sta -NoProfile -ExecutionPolicy Bypass -File "%~dp0WMMT6-Launch.ps1" -Borderless
if errorlevel 1 (
  echo.
  echo WMMT6 borderless launch failed. Review the message and WMMT6-Launch-Logs folder.
  pause
  exit /b 1
)
