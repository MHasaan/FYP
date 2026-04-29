#!/bin/bash
# =============================================================================
# FYP Project - Start Script
# =============================================================================
# This script starts the existing project containers:
# - Starts Docker Desktop (if not running)
# - Starts all containers (no rebuild)
#
# Usage: ./start.sh
#        ./start.sh --rebuild    # Force rebuild containers
#        ./start.sh --logs       # Start and follow logs
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
REBUILD=false
FOLLOW_LOGS=false
SERVICES=""

for arg in "$@"; do
    case $arg in
        rebuild|--rebuild|-r)
            REBUILD=true
            ;;
        --logs|-l)
            FOLLOW_LOGS=true
            ;;
        --help|-h)
            echo "Usage: ./start.sh [OPTIONS] [SERVICES...]"
            echo ""
            echo "Options:"
            echo "  rebuild, --rebuild, -r    Rebuild containers before starting"
            echo "  --logs, -l       Follow logs after starting"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            SERVICES="$SERVICES $arg"
            ;;
    esac
done

# Get script directory and navigate to project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo -e "${BLUE}"
echo "============================================================"
echo "  FYP Project - Start Script"
echo "============================================================"
echo -e "${NC}"

# -----------------------------------------------------------------------------
# Function: Check if running on Windows
# -----------------------------------------------------------------------------
is_windows() {
    [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WINDIR" ]]
}

# -----------------------------------------------------------------------------
# Function: Check if Docker is running
# -----------------------------------------------------------------------------
check_docker_running() {
    docker info >/dev/null 2>&1
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
# Function: Start Docker on Linux
# -----------------------------------------------------------------------------
start_docker_linux() {
    echo -e "${BLUE}[*]${NC} Starting Docker daemon..."

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl start docker
    elif command -v service >/dev/null 2>&1; then
        sudo service docker start
    else
        echo -e "${RED}[ERROR]${NC} Cannot start Docker. Please start it manually."
        exit 1
    fi

    # Wait for Docker
    local max_attempts=30
    local attempt=0
    while ! docker info >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${RED}[ERROR]${NC} Docker failed to start"
            exit 1
        fi
        sleep 1
    done
    echo -e "${GREEN}[OK]${NC} Docker is running"
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
# Function: Check if containers exist
# -----------------------------------------------------------------------------
check_containers_exist() {
    local COMPOSE_CMD=$(get_compose_cmd)
    local count=$($COMPOSE_CMD ps -a --format json 2>/dev/null | wc -l)

    if [[ $count -gt 0 ]]; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: Start containers
# -----------------------------------------------------------------------------
start_containers() {
    local COMPOSE_CMD=$(get_compose_cmd)

    if [[ "$REBUILD" == "true" ]]; then
        echo -e "${BLUE}[*]${NC} Rebuilding and starting containers... $SERVICES"
        $COMPOSE_CMD up -d --build $SERVICES
    else
        echo -e "${BLUE}[*]${NC} Starting existing containers... $SERVICES"
        $COMPOSE_CMD up -d $SERVICES
    fi

    echo -e "${GREEN}[OK]${NC} Containers started"
}

# -----------------------------------------------------------------------------
# Function: Wait for services to be healthy
# -----------------------------------------------------------------------------
wait_for_services() {
    echo -e "${BLUE}[*]${NC} Waiting for services to be ready..."

    # Wait for database
    echo -ne "    Database: "
    local max_attempts=30
    local attempt=0
    while ! docker exec fyp-database pg_isready -U fyp_user >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${YELLOW}TIMEOUT${NC}"
            break
        fi
        sleep 1
    done
    if [[ $attempt -lt $max_attempts ]]; then
        echo -e "${GREEN}OK${NC}"
    fi

    # Wait for Redis
    echo -ne "    Redis: "
    attempt=0
    while ! docker exec fyp-redis redis-cli ping >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${YELLOW}TIMEOUT${NC}"
            break
        fi
        sleep 1
    done
    if [[ $attempt -lt $max_attempts ]]; then
        echo -e "${GREEN}OK${NC}"
    fi

    # Wait for Backend
    echo -ne "    Backend: "
    attempt=0
    while ! curl -s http://localhost:8000/health >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${YELLOW}TIMEOUT${NC}"
            break
        fi
        sleep 1
    done
    if [[ $attempt -lt $max_attempts ]]; then
        echo -e "${GREEN}OK${NC}"
    fi

    # Wait for Frontend
    echo -ne "    Frontend: "
    attempt=0
    while ! curl -s http://localhost:80 >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo -e "${YELLOW}TIMEOUT${NC}"
            break
        fi
        sleep 1
    done
    if [[ $attempt -lt $max_attempts ]]; then
        echo -e "${GREEN}OK${NC}"
    fi
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
    echo -e "${GREEN}  Project Started!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "  ${BLUE}Web App:${NC}     http://localhost"
    echo -e "  ${BLUE}API Docs:${NC}    http://localhost:8000/docs"
    echo -e "  ${BLUE}API Health:${NC}  http://localhost:8000/health"
    echo ""
    echo -e "  ${YELLOW}To view logs:${NC}     docker compose logs -f"
    echo -e "  ${YELLOW}To stop:${NC}          docker compose down"
    echo -e "  ${YELLOW}To rebuild:${NC}       ./start.sh --rebuild"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: Follow logs
# -----------------------------------------------------------------------------
follow_logs() {
    local COMPOSE_CMD=$(get_compose_cmd)
    echo -e "${BLUE}[*]${NC} Following container logs (Ctrl+C to exit)..."
    $COMPOSE_CMD logs -f
}

# =============================================================================
# Main Script
# =============================================================================

# Check if Docker is running
echo -e "${BLUE}[1/4]${NC} Checking Docker..."
if ! check_docker_running; then
    if is_windows; then
        start_docker_windows
    else
        start_docker_linux
    fi
else
    echo -e "${GREEN}[OK]${NC} Docker is running"
fi

# Check if containers exist
echo -e "${BLUE}[2/4]${NC} Checking containers..."
if ! check_containers_exist && [[ "$REBUILD" == "false" ]]; then
    echo -e "${YELLOW}[!]${NC} No containers found. Running setup first..."
    echo ""
    echo -e "${YELLOW}Please run ./setup.sh first to build the containers.${NC}"
    echo ""
    exit 1
fi

# Start containers
echo -e "${BLUE}[3/4]${NC} Starting services..."
start_containers

# Wait for services
echo -e "${BLUE}[4/4]${NC} Checking service health..."
wait_for_services

show_status
show_access_info

# Follow logs if requested
if [[ "$FOLLOW_LOGS" == "true" ]]; then
    follow_logs
fi
