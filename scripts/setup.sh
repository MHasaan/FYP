#!/bin/bash
# =============================================================================
# FYP Project - One-Time Setup Script
# =============================================================================
# This script sets up the entire project from scratch:
# - Installs Docker Desktop (if not installed)
# - Builds all containers
# - Initializes the database
# - Applies any code changes
#
# Usage: ./setup.sh
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory and navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo -e "${BLUE}"
echo "============================================================"
echo "  FYP Project - Setup Script"
echo "============================================================"
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Function: Check if a command exists
# -----------------------------------------------------------------------------
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Function: Check if running on Windows
# -----------------------------------------------------------------------------
is_windows() {
    [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]
}

# -----------------------------------------------------------------------------
# Function: Check if Docker Desktop is installed
# -----------------------------------------------------------------------------
check_docker_installed() {
    if command_exists docker; then
        echo -e "${GREEN}[OK]${NC} Docker is installed"
        return 0
    else
        echo -e "${YELLOW}[!]${NC} Docker is not installed"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Install Docker Desktop on Windows
# -----------------------------------------------------------------------------
install_docker_windows() {
    echo -e "${YELLOW}[!]${NC} Docker Desktop not found. Attempting to install..."

    # Check if winget is available
    if command_exists winget; then
        echo -e "${BLUE}[*]${NC} Installing Docker Desktop via winget..."
        winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements

        echo -e "${YELLOW}[!]${NC} Docker Desktop installed. Please:"
        echo "    1. Restart your computer"
        echo "    2. Open Docker Desktop and complete the setup"
        echo "    3. Run this script again"
        exit 0
    else
        echo -e "${RED}[ERROR]${NC} winget not found. Please install Docker Desktop manually:"
        echo "    https://www.docker.com/products/docker-desktop/"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Start Docker Desktop on Windows
# -----------------------------------------------------------------------------
start_docker_windows() {
    echo -e "${BLUE}[*]${NC} Starting Docker Desktop..."

    # Try to start Docker Desktop
    if [[ -f "/c/Program Files/Docker/Docker/Docker Desktop.exe" ]]; then
        "/c/Program Files/Docker/Docker/Docker Desktop.exe" &
    elif [[ -f "/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe" ]]; then
        "/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe" &
    else
        # Try PowerShell
        powershell.exe -Command "Start-Process 'Docker Desktop'" 2>/dev/null || true
    fi

    # Wait for Docker to be ready
    echo -e "${BLUE}[*]${NC} Waiting for Docker to start..."
    local max_attempts=60
    local attempt=0

    while ! docker info >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${RED}[ERROR]${NC} Docker failed to start after ${max_attempts} seconds"
            echo "    Please start Docker Desktop manually and run this script again"
            exit 1
        fi
        echo -ne "\r    Waiting... ($attempt/$max_attempts)"
        sleep 1
    done
    echo ""
    echo -e "${GREEN}[OK]${NC} Docker is running"
}

# -----------------------------------------------------------------------------
# Function: Check if Docker is running
# -----------------------------------------------------------------------------
check_docker_running() {
    if docker info >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Docker daemon is running"
        return 0
    else
        echo -e "${YELLOW}[!]${NC} Docker daemon is not running"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Check Docker Compose
# -----------------------------------------------------------------------------
check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Docker Compose is available"
        return 0
    elif docker-compose version >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} Docker Compose (standalone) is available"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Docker Compose not found"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Get docker compose command
# -----------------------------------------------------------------------------
get_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# -----------------------------------------------------------------------------
# Function: Check .env file
# -----------------------------------------------------------------------------
check_env_file() {
    if [[ -f ".env" ]]; then
        echo -e "${GREEN}[OK]${NC} .env file exists"
    else
        echo -e "${YELLOW}[!]${NC} .env file not found, creating from template..."
        if [[ -f ".env.example" ]]; then
            cp .env.example .env
            echo -e "${GREEN}[OK]${NC} Created .env from .env.example"
        else
            echo -e "${RED}[ERROR]${NC} No .env or .env.example found"
            exit 1
        fi
    fi
}

# -----------------------------------------------------------------------------
# Function: Check NVIDIA GPU (optional)
# -----------------------------------------------------------------------------
check_nvidia_gpu() {
    echo -e "${BLUE}[*]${NC} Checking for NVIDIA GPU..."

    if docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} NVIDIA GPU detected and accessible"
        return 0
    else
        echo -e "${YELLOW}[!]${NC} NVIDIA GPU not detected or not accessible"
        echo "    ML inference will use CPU (slower but functional)"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Clean up old containers and volumes
# -----------------------------------------------------------------------------
cleanup_old() {
    local COMPOSE_CMD=$(get_compose_cmd)

    echo -e "${BLUE}[*]${NC} Cleaning up old containers..."
    $COMPOSE_CMD down --remove-orphans 2>/dev/null || true

    # Optionally remove volumes (commented out to preserve data)
    # echo -e "${BLUE}[*]${NC} Removing old volumes..."
    # $COMPOSE_CMD down -v 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Function: Build containers
# -----------------------------------------------------------------------------
build_containers() {
    local COMPOSE_CMD=$(get_compose_cmd)

    echo -e "${BLUE}[*]${NC} Building all containers (this may take a few minutes)..."
    $COMPOSE_CMD build --no-cache
    echo -e "${GREEN}[OK]${NC} All containers built successfully"
}

# -----------------------------------------------------------------------------
# Function: Pull base images
# -----------------------------------------------------------------------------
pull_images() {
    echo -e "${BLUE}[*]${NC} Pulling base images..."
    docker pull postgres:16-alpine
    docker pull redis:7-alpine
    echo -e "${GREEN}[OK]${NC} Base images pulled"
}

# -----------------------------------------------------------------------------
# Function: Start containers
# -----------------------------------------------------------------------------
start_containers() {
    local COMPOSE_CMD=$(get_compose_cmd)

    echo -e "${BLUE}[*]${NC} Starting all containers..."
    $COMPOSE_CMD up -d
    echo -e "${GREEN}[OK]${NC} All containers started"
}

# -----------------------------------------------------------------------------
# Function: Wait for services to be healthy
# -----------------------------------------------------------------------------
wait_for_services() {
    local COMPOSE_CMD=$(get_compose_cmd)

    echo -e "${BLUE}[*]${NC} Waiting for services to be healthy..."

    # Wait for database
    echo -ne "    Database: "
    local max_attempts=30
    local attempt=0
    while ! docker exec fyp-database pg_isready -U fyp_user >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${RED}FAILED${NC}"
            return 1
        fi
        sleep 1
    done
    echo -e "${GREEN}OK${NC}"

    # Wait for Redis
    echo -ne "    Redis: "
    attempt=0
    while ! docker exec fyp-redis redis-cli ping >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${RED}FAILED${NC}"
            return 1
        fi
        sleep 1
    done
    echo -e "${GREEN}OK${NC}"

    # Wait for Backend
    echo -ne "    Backend: "
    attempt=0
    while ! curl -s http://localhost:8000/health >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${RED}FAILED${NC}"
            return 1
        fi
        sleep 1
    done
    echo -e "${GREEN}OK${NC}"

    # Wait for Frontend
    echo -ne "    Frontend: "
    attempt=0
    while ! curl -s http://localhost:80 >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${YELLOW}TIMEOUT${NC} (may still be building)"
            return 0
        fi
        sleep 1
    done
    echo -e "${GREEN}OK${NC}"

    echo -e "${GREEN}[OK]${NC} All services are healthy"
}

# -----------------------------------------------------------------------------
# Function: Show status
# -----------------------------------------------------------------------------
show_status() {
    local COMPOSE_CMD=$(get_compose_cmd)

    echo ""
    echo -e "${BLUE}Container Status:${NC}"
    $COMPOSE_CMD ps
}

# -----------------------------------------------------------------------------
# Function: Show access info
# -----------------------------------------------------------------------------
show_access_info() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Setup Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  ${BLUE}Web App:${NC}     http://localhost"
    echo -e "  ${BLUE}API Docs:${NC}    http://localhost:8000/docs"
    echo -e "  ${BLUE}API Health:${NC}  http://localhost:8000/health"
    echo ""
    echo -e "  ${YELLOW}To start the project later:${NC}  ./start.sh"
    echo -e "  ${YELLOW}To stop the project:${NC}         docker compose down"
    echo -e "  ${YELLOW}To view logs:${NC}                docker compose logs -f"
    echo ""
}

# =============================================================================
# Main Script
# =============================================================================

echo -e "${BLUE}[1/8]${NC} Checking Docker installation..."
if ! check_docker_installed; then
    if is_windows; then
        install_docker_windows
    else
        echo -e "${RED}[ERROR]${NC} Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
fi

echo -e "${BLUE}[2/8]${NC} Checking Docker daemon..."
if ! check_docker_running; then
    if is_windows; then
        start_docker_windows
    else
        echo -e "${RED}[ERROR]${NC} Please start Docker daemon: sudo systemctl start docker"
        exit 1
    fi
fi

echo -e "${BLUE}[3/8]${NC} Checking Docker Compose..."
check_docker_compose || exit 1

echo -e "${BLUE}[4/8]${NC} Checking environment..."
check_env_file

echo -e "${BLUE}[5/8]${NC} Checking GPU (optional)..."
check_nvidia_gpu || true  # Don't fail if no GPU

echo -e "${BLUE}[6/8]${NC} Cleaning up old containers..."
cleanup_old

echo -e "${BLUE}[7/8]${NC} Building and starting containers..."
pull_images
build_containers
start_containers

echo -e "${BLUE}[8/8]${NC} Verifying services..."
wait_for_services

show_status
show_access_info
