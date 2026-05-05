@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%restore.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if "%~1"=="" (
    echo.
    echo Press any key to close...
    pause >nul
)

exit /b %EXIT_CODE%
