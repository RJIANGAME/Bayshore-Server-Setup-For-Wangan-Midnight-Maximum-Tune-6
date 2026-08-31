@echo off
setlocal
cd /d "%~dp0"
where pyw.exe >nul 2>&1
if not errorlevel 1 (
  start "Bayshore Database Editor" pyw.exe "%~dp0database-editor\BayshoreDatabaseEditor.pyw"
  exit /b 0
)
where py.exe >nul 2>&1
if not errorlevel 1 (
  py.exe "%~dp0database-editor\BayshoreDatabaseEditor.pyw"
  exit /b %errorlevel%
)
echo Python 3 was not found. Install Python 3 with Tkinter, then run this launcher again.
pause
exit /b 1
