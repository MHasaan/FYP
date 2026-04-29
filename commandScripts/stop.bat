@echo off
REM =============================================================================
REM FYP Project - Stop Script (Windows)
REM =============================================================================
REM Stops all running containers
REM
REM Usage: stop.bat          - Stop containers (keep data)
REM        stop.bat clean    - Stop and remove volumes (reset database)
REM =============================================================================

REM Navigate to project root (parent of scripts folder)
cd /d "%~dp0.."

echo.
echo ============================================================
echo   FYP Project - Stop Script
echo ============================================================
echo.

if "%1"=="clean" goto clean
if "%1"=="--clean" goto clean
if "%1"=="-c" goto clean

echo [*] Stopping all containers...
docker compose stop
echo [OK] All containers stopped
goto done

:clean
echo [!] WARNING: This will delete all database data!
set /p confirm="Are you sure? (y/N) "
if /i "%confirm%"=="y" (
    echo [*] Stopping containers and removing volumes...
    docker compose down -v --remove-orphans
    echo [OK] All containers and volumes removed
) else (
    echo [!] Cancelled
)

:done
echo.
echo   To start again:  start.bat
echo.
pause
