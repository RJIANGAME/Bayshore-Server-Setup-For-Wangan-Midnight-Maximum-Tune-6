@echo off
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Bayshore-And-Terminal.ps1" -Restart
if errorlevel 1 (
  echo.
  echo PostgreSQL, Bayshore, or the WMMT6 terminal failed to start. Review the error above.
  pause
  exit /b 1
)
echo.
echo PostgreSQL, Bayshore, MaxiTerminal, and the recovery watchdog are ready.
pause
