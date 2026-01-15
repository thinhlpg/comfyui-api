#!/bin/bash
# Scale ComfyUI API instances with Docker Compose
# Usage: bash scripts/scale-compose.sh <replicas> [compose-file]

set -e

REPLICAS="${1:-1}"
COMPOSE_FILE="${2:-docker-compose.yml}"

if ! command -v docker &> /dev/null; then
    echo "Error: docker command not found"
    exit 1
fi

if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "Error: docker compose command not found"
    exit 1
fi

# Use docker compose or docker-compose
DOCKER_COMPOSE="docker compose"
if ! command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: Compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Validate replicas
if ! [[ "$REPLICAS" =~ ^[0-9]+$ ]] || [ "$REPLICAS" -lt 1 ]; then
    echo "Error: Replicas must be a positive integer"
    exit 1
fi

echo "Scaling comfyui-api to $REPLICAS replica(s)..."

# Check current replicas
CURRENT=$($DOCKER_COMPOSE -f "$COMPOSE_FILE" ps --services --filter "status=running" | wc -l | tr -d ' ')

if [ "$CURRENT" -eq "$REPLICAS" ]; then
    echo "Already at $REPLICAS replica(s)"
    exit 0
fi

# For single replica, use standard compose
if [ "$REPLICAS" -eq 1 ]; then
    $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d --scale comfyui-api=1
    echo "Scaled to 1 replica"
    exit 0
fi

# For multiple replicas, need to handle port conflicts
echo "Warning: Multiple replicas require unique port mappings"
echo "Create docker-compose.scale.yml with port mappings for each instance"
echo ""
echo "Example structure:"
echo "  comfyui-api-0: ports: ['3001:3000']"
echo "  comfyui-api-1: ports: ['3002:3000']"
echo "  comfyui-api-2: ports: ['3003:3000']"
echo ""
echo "Then run: $DOCKER_COMPOSE -f docker-compose.scale.yml up -d"

# Attempt to scale with current compose file (may fail on port conflicts)
if $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d --scale comfyui-api="$REPLICAS" 2>&1 | grep -q "port.*already allocated"; then
    echo ""
    echo "Port conflict detected. Create docker-compose.scale.yml with unique ports."
    exit 1
fi

echo "Scaled to $REPLICAS replica(s)"
echo ""
echo "Check status:"
$DOCKER_COMPOSE -f "$COMPOSE_FILE" ps
