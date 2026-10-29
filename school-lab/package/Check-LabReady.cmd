@echo off
setlocal
set "LAB_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LAB_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LAB_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check-LabReady.ps1"
set "LAB_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %LAB_RESULT%
