@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"

title NetMedic - Windows Network Configuration Repair

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" (
    echo [ERROR] Windows PowerShell 5.1 was not found.
    exit /b 1
)

"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0NetworkRepair.ps1" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo [ERROR] NetMedic exited with code %RC%.
)

exit /b %RC%
