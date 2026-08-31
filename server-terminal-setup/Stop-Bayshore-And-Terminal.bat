@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Stop-Bayshore-And-Terminal.ps1"
if errorlevel 1 (
  echo.
  echo Bayshore or the WMMT6 terminal failed to stop. Review the error above.
  pause
  exit /b 1
)
echo.
echo Bayshore and the WMMT6 terminal are stopped.
pause
