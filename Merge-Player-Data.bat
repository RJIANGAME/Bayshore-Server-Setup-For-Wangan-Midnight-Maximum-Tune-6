@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server-tools\Merge-Player-Data.ps1"
if errorlevel 1 (
  echo.
  echo Merge failed. Review the error above before starting Bayshore.
  pause
  exit /b 1
)
echo.
echo Merge completed successfully. Bayshore and MaxiTerminal were restarted when configured.
pause
