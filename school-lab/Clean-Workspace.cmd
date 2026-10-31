@echo off
setlocal DisableDelayedExpansion
set "LAB_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LAB_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LAB_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Clean-Workspace.ps1" -Apply
set "LAB_RESULT=%ERRORLEVEL%"
echo Cleanup exit code: %LAB_RESULT%
pause
exit /b %LAB_RESULT%
