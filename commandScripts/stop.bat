@echo off
REM =============================================================================
REM FYP Project - Stop Script (Windows)
REM =============================================================================
REM Usage: stop.bat          - Stop containers (keep data)
REM        stop.bat clean    - Stop and remove volumes (reset database)
REM =============================================================================

setlocal

cd /d "%~dp0.."

echo.
echo ============================================================
echo   FYP Project - Stop Script
echo ============================================================
echo.

if /i "%~1"=="clean"   goto clean
if /i "%~1"=="--clean" goto clean
if /i "%~1"=="-c"      goto clean

echo [*] Stopping all containers...
docker compose stop
if %errorlevel% neq 0 (
    echo [ERROR] Failed to stop containers.
    pause
    exit /b 1
)
echo [OK] All containers stopped
goto done

:clean
echo [!] WARNING: This will delete all database data and volumes.
set /p "CONFIRM=Are you sure? (y/N) "
if /i "%CONFIRM%"=="y" (
    echo [*] Stopping containers and removing volumes...
    docker compose down -v --remove-orphans
    if %errorlevel% neq 0 (
        echo [ERROR] Failed to remove containers and volumes.
        pause
        exit /b 1
    )
    echo [OK] All containers and volumes removed
) else (
    echo [!] Cancelled
)

:done
echo.
echo   To start again:  commandScripts\start.bat
echo.
pause
