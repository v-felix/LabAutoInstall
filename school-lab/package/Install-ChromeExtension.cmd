@echo off
setlocal
set "LAB_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LAB_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LAB_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ChromeExtension.ps1"
set "LAB_RESULT=%ERRORLEVEL%"
echo Chrome extension exit code: %LAB_RESULT%
pause
exit /b %LAB_RESULT%
