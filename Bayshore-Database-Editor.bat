@echo off
setlocal
cd /d "%~dp0"
where py.exe >nul 2>&1
if not errorlevel 1 (
  py.exe -3 -c "import sys, tkinter; assert sys.version_info >= (3, 10)" >nul 2>&1
  if errorlevel 1 goto missing_python
  where pyw.exe >nul 2>&1
  if not errorlevel 1 (
    start "Bayshore Database Editor" pyw.exe -3 "%~dp0database-editor\BayshoreDatabaseEditor.pyw"
    exit /b 0
  )
  py.exe -3 "%~dp0database-editor\BayshoreDatabaseEditor.pyw"
  exit /b
)
where python.exe >nul 2>&1
if not errorlevel 1 (
  python.exe -c "import sys, tkinter; assert sys.version_info >= (3, 10)" >nul 2>&1
  if errorlevel 1 goto missing_python
  where pythonw.exe >nul 2>&1
  if not errorlevel 1 (
    start "Bayshore Database Editor" pythonw.exe "%~dp0database-editor\BayshoreDatabaseEditor.pyw"
    exit /b 0
  )
  python.exe "%~dp0database-editor\BayshoreDatabaseEditor.pyw"
  exit /b
)
:missing_python
echo Python 3.10 or newer with Tkinter is required.
echo Install from https://www.python.org/downloads/windows/ then reopen this launcher.
pause
exit /b 1
