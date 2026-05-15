@echo off
REM =============================================================================
REM FYP Project - Start Script (Windows)
REM =============================================================================
REM Usage: start.bat                        - Start existing containers
REM        start.bat rebuild                - Rebuild all and start
REM        start.bat rebuild frontend       - Rebuild specific containers
REM        start.bat rebuild backend ml_manager
REM =============================================================================

setlocal enabledelayedexpansion

cd /d "%~dp0.."

set DOCKER_BUILDKIT=1
set COMPOSE_DOCKER_CLI_BUILD=1

set "REBUILD=0"
set "SERVICES="

echo.
echo ============================================================
echo   FYP Project - Start Script
echo ============================================================
echo.

REM --- Parse "rebuild" flag (must be first arg) ---
if /i "%~1"=="rebuild"   set "REBUILD=1" & shift /1
if /i "%~1"=="--rebuild" set "REBUILD=1" & shift /1
if /i "%~1"=="-r"        set "REBUILD=1" & shift /1

REM --- Collect remaining args as service names (no shift inside blocks) ---
:collect_services
if "%~1"=="" goto services_done
set "SERVICES=!SERVICES! %~1"
shift /1
goto collect_services
:services_done

REM --- Check Docker is running ---
docker info >nul 2>&1
if !errorlevel! neq 0 (
    echo [*] Starting Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"

    echo [*] Waiting for Docker to start...
    set "ATTEMPTS=0"

    :wait_docker
    timeout /t 2 /nobreak >nul
    docker info >nul 2>&1
    if !errorlevel! neq 0 (
        set /a ATTEMPTS+=1
        if !ATTEMPTS! geq 60 (
            echo [ERROR] Docker failed to start. Please start Docker Desktop manually.
            pause
            exit /b 1
        )
        echo     Waiting... [!ATTEMPTS!/60]
        goto wait_docker
    )
)

echo [OK] Docker is running

REM --- Ensure images exist when not rebuilding ---
if "%REBUILD%"=="0" (
    docker compose images -q 2>nul | findstr /r "." >nul
    if !errorlevel! neq 0 (
        echo [^!] No built images found.
        echo.
        echo Please run setup.bat first to build the project.
        echo Or run:  start.bat rebuild
        echo.
        pause
        exit /b 1
    )
)

REM --- Start containers ---
if "%REBUILD%"=="1" (
    echo [*] Rebuilding and starting containers...!SERVICES!
    docker compose up -d --build!SERVICES!
) else (
    echo [*] Starting existing containers...!SERVICES!
    docker compose up -d!SERVICES!
)

if !errorlevel! neq 0 (
    echo [ERROR] Failed to start containers.
    echo.
    echo Tip: If you got a timeout, just run this command again.
    echo Docker caches everything that succeeded so retries are fast.
    pause
    exit /b 1
)

echo [*] Waiting for services to be ready...
timeout /t 10 /nobreak >nul

echo.
echo Container Status:
docker compose ps

echo.
echo ============================================================
echo   Project Started
echo ============================================================
echo.
echo   Web App:     http://localhost
echo   API Docs:    http://localhost:8000/docs
echo   API Health:  http://localhost:8000/health
echo.
echo   To view logs:  docker compose logs -f
echo   To stop:       commandScripts\stop.bat
echo   To rebuild:    commandScripts\start.bat rebuild
echo.
pause
