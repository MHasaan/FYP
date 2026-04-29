@echo off
REM =============================================================================
REM FYP Project - Setup Script (Windows)
REM =============================================================================
REM This script sets up the entire project from scratch.
REM Run this once to build all containers.
REM =============================================================================

setlocal enabledelayedexpansion

REM Navigate to project root (parent of scripts folder)
cd /d "%~dp0.."

echo.
echo ============================================================
echo   FYP Project - Setup Script
echo ============================================================
echo.

REM Check if Docker is installed
where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] Docker is not installed.
    echo.
    echo Please install Docker Desktop from:
    echo     https://www.docker.com/products/docker-desktop/
    echo.
    echo After installation, restart your computer and run this script again.
    pause
    exit /b 1
)

echo [OK] Docker is installed

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

REM Check .env file
if not exist ".env" (
    if exist ".env.example" (
        echo [*] Creating .env from .env.example...
        copy .env.example .env >nul
    ) else (
        echo [ERROR] No .env file found!
        pause
        exit /b 1
    )
)
echo [OK] .env file exists

REM Clean up old containers
echo [*] Cleaning up old containers...
docker compose down --remove-orphans 2>nul

REM Pull base images
echo [*] Pulling base images...
docker pull postgres:16-alpine
docker pull redis:7-alpine

REM Build containers
echo [*] Building all containers (this may take a few minutes)...
docker compose build
if %errorlevel% neq 0 (
    echo [ERROR] Build failed!
    pause
    exit /b 1
)

REM Start containers
echo [*] Starting all containers...
docker compose up -d
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
echo   Setup Complete!
echo ============================================================
echo.
echo   Web App:     http://localhost
echo   API Docs:    http://localhost:8000/docs
echo   API Health:  http://localhost:8000/health
echo.
echo   To start later:  start.bat
echo   To stop:         docker compose down
echo   To view logs:    docker compose logs -f
echo.
pause
