@echo off
setlocal
set "LAB_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "LAB_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%LAB_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Lab.ps1"
set "LAB_RESULT=%ERRORLEVEL%"
echo SchoolLab exit code: %LAB_RESULT%
if "%LAB_RESULT%"=="3010" echo Final restart required/requested. Sign in to the SAME account for automatic readiness verification when enabled.
if "%LAB_RESULT%"=="69031" echo Applications installed, but classroom account setup was not completed. SFIT may not have been started. See the desktop account diagnostic above.
if "%LAB_RESULT%"=="0" echo Completed. Read the result above before closing this window.
echo Logs: %ProgramData%\SchoolLab\Logs\%COMPUTERNAME%
pause
exit /b %LAB_RESULT%
