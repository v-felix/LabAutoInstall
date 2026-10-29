@echo off
setlocal
set "LAB_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LAB_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LAB_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Lab.ps1"
set "LAB_RESULT=%ERRORLEVEL%"
echo SchoolLab exit code: %LAB_RESULT%
if "%LAB_RESULT%"=="3010" echo Restart required. Sign out and back in after restarting.
if "%LAB_RESULT%"=="0" echo Completed. Read the result above before closing this window.
echo Logs: %ProgramData%\SchoolLab\Logs\%COMPUTERNAME%
pause
exit /b %LAB_RESULT%
