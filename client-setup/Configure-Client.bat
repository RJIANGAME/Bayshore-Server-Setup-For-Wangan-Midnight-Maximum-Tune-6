@echo off
setlocal
cd /d "%~dp0"
fltmc >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Configure-Client.ps1"
if errorlevel 1 (
    echo.
    echo Client configuration failed. Review the error above.
)
pause
