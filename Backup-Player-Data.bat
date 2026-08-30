@echo off
setlocal
cd /d "%~dp0"
echo Bayshore player-data backup
echo ===========================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server-tools\Backup-Player-Data.ps1"
if errorlevel 1 (
  echo.
  echo Backup failed. Review the error above.
  pause
  exit /b 1
)
echo.
echo Backup completed successfully.
pause
