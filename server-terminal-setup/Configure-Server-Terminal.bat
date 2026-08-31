@echo off
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Configure-Server-Terminal.ps1"
if errorlevel 1 (
  echo.
  echo Server terminal setup failed. Review the error above.
  pause
  exit /b 1
)
echo.
echo Server terminal setup completed.
pause
