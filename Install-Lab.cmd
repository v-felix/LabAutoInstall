@echo off
setlocal DisableDelayedExpansion
set "LAB_PACKAGE=%~dp0school-lab\dist\SchoolLab-2.7.1-20261031"
if not exist "%LAB_PACKAGE%\package-lock.json" goto missing
if not exist "%LAB_PACKAGE%\Install-Lab.cmd" goto missing
call "%LAB_PACKAGE%\Install-Lab.cmd"
exit /b %ERRORLEVEL%

:missing
echo Offline package not found: "%LAB_PACKAGE%"
echo Build the package first, or copy the complete SchoolLab-2.7.1-20261031
echo folder into school-lab\dist. See README.md for instructions.
pause
exit /b 2
