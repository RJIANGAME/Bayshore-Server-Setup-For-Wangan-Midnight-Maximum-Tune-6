@echo off
setlocal
cd /d "%~dp0"
fltmc >nul 2>&1
if errorlevel 1 (
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server-setup\Configure-Server.ps1"
if errorlevel 1 (
  echo.
  echo Server setup failed. Review the error above.
  pause
  exit /b 1
)
pause
