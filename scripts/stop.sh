#!/bin/bash
# =============================================================================
# FYP Project - Stop Script
# =============================================================================
# Stops all running containers
#
# Usage: ./stop.sh
#        ./stop.sh --clean    # Stop and remove volumes (reset database)
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Get docker compose command
get_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

COMPOSE_CMD=$(get_compose_cmd)

echo -e "${BLUE}"
echo "============================================================"
echo "  FYP Project - Stop Script"
echo "============================================================"
echo -e "${NC}"

if [[ "$1" == "--clean" ]] || [[ "$1" == "-c" ]]; then
    echo -e "${YELLOW}[!]${NC} Stopping containers and removing volumes..."
    echo -e "${YELLOW}    WARNING: This will delete all database data!${NC}"
    read -p "    Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        $COMPOSE_CMD down -v --remove-orphans
        echo -e "${GREEN}[OK]${NC} All containers and volumes removed"
    else
        echo -e "${YELLOW}[!]${NC} Cancelled"
    fi
else
    echo -e "${BLUE}[*]${NC} Stopping all containers..."
    $COMPOSE_CMD stop
    echo -e "${GREEN}[OK]${NC} All containers stopped"
fi

echo ""
echo -e "  ${YELLOW}To start again:${NC}  ./start.sh"
echo ""
