@echo on
REM =============================================================================
REM FYP Project - Start Script (Windows)
REM =============================================================================
REM This script starts the existing project containers.
REM Run setup.bat first if containers don't exist.
REM
REM Usage: start.bat          - Start existing containers
REM        start.bat rebuild  - Rebuild and start containers
REM =============================================================================

setlocal enabledelayedexpansion

REM Navigate to project root (parent of scripts folder)
cd /d "%~dp0.."

set REBUILD=0
if "%1"=="rebuild" set REBUILD=1
if "%1"=="--rebuild" set REBUILD=1
if "%1"=="-r" set REBUILD=1

if %REBUILD%==1 shift

set SERVICES=
:collect_services
if not "%1"=="" (
    set SERVICES=%SERVICES% %1
    shift
    goto collect_services
)

echo.
echo ============================================================
echo   FYP Project - Start Script
echo ============================================================
echo.

REM Check if Docker is running
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Starting Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"

    echo [*] Waiting for Docker to start...
    set /a attempts=0
    :wait_docker
    timeout /t 2 /nobreak >nul
    docker info >nul 2>&1
    if %errorlevel% neq 0 (
        set /a attempts+=1
        if !attempts! geq 60 (
            echo [ERROR] Docker failed to start. Please start Docker Desktop manually.
            pause
            exit /b 1
        )
        echo     Waiting... [!attempts!/60]
        goto wait_docker
    )
)

echo [OK] Docker is running

REM Check if containers exist
docker compose ps -a 2>nul | findstr "fyp" >nul
if %errorlevel% neq 0 (
    if %REBUILD%==0 (
        echo [!] No containers found.
        echo.
        echo Please run setup.bat first to build the containers.
        echo Or run: start.bat rebuild
        echo.
        pause
        exit /b 1
    )
)

REM Start containers
if %REBUILD%==1 (
    REM If rebuilding frontend (or rebuilding all), regenerate Flutter web assets first.
    if "%SERVICES%"=="" (
        echo [*] Building Flutter web (release)...
        powershell -ExecutionPolicy Bypass -File build.ps1
        if %errorlevel% neq 0 (
            echo [ERROR] Flutter web build failed!
            pause
            exit /b 1
        )
    ) else (
        echo %SERVICES% | findstr /i "frontend" >nul
        if %errorlevel%==0 (
            echo [*] Building Flutter web (release)...
            powershell -ExecutionPolicy Bypass -File build.ps1
            if %errorlevel% neq 0 (
                echo [ERROR] Flutter web build failed!
                pause
                exit /b 1
            )
        )
    )

    echo [*] Rebuilding and starting containers... %SERVICES%
    docker compose up -d --build %SERVICES%
) else (
    echo [*] Starting existing containers... %SERVICES%
    docker compose up -d %SERVICES%
)

if %errorlevel% neq 0 (
    echo [ERROR] Failed to start containers!
    pause
    exit /b 1
)

REM Wait for services
echo [*] Waiting for services to be ready...
timeout /t 10 /nobreak >nul

REM Show status
echo.
echo Container Status:
docker compose ps

echo.
echo ============================================================
echo   Project Started!
echo ============================================================
echo.
echo   Web App:     http://localhost
echo   API Docs:    http://localhost:8000/docs
echo   API Health:  http://localhost:8000/health
echo.
echo   To view logs:  docker compose logs -f
echo   To stop:       docker compose down
echo   To rebuild:    start.bat rebuild
echo.
pause
