#!/bin/bash
set -e

# ComfyUI API Deployment Script for Homelab

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default paths
DEFAULT_DATA_ROOT="$HOME/data/comfyui"

echo -e "${GREEN}🎨 ComfyUI API Deployment${NC}"
echo "================================"

# Check if .env exists, if not create from example
if [[ ! -f ".env" ]]; then
    echo -e "${YELLOW}Creating .env from env.example...${NC}"
    cat > .env << EOF
# ComfyUI API Configuration
MODEL_DIR=${DEFAULT_DATA_ROOT}/models
OUTPUT_DIR=${DEFAULT_DATA_ROOT}/output
INPUT_DIR=${DEFAULT_DATA_ROOT}/input
CACHE_DIR=${DEFAULT_DATA_ROOT}/cache
CUSTOM_NODES_DIR=${DEFAULT_DATA_ROOT}/custom_nodes
EOF
    echo -e "${GREEN}Created .env with default paths at ${DEFAULT_DATA_ROOT}${NC}"
fi

# Source .env
source .env

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p "${MODEL_DIR/#\~/$HOME}" \
         "${OUTPUT_DIR/#\~/$HOME}" \
         "${INPUT_DIR/#\~/$HOME}" \
         "${CACHE_DIR/#\~/$HOME}" \
         "${CUSTOM_NODES_DIR/#\~/$HOME}"

# Create subdirectories for models
mkdir -p "${MODEL_DIR/#\~/$HOME}/checkpoints" \
         "${MODEL_DIR/#\~/$HOME}/vae" \
         "${MODEL_DIR/#\~/$HOME}/loras" \
         "${MODEL_DIR/#\~/$HOME}/controlnet" \
         "${MODEL_DIR/#\~/$HOME}/embeddings" \
         "${MODEL_DIR/#\~/$HOME}/upscale_models" \
         "${MODEL_DIR/#\~/$HOME}/clip" \
         "${MODEL_DIR/#\~/$HOME}/unet"

echo -e "${GREEN}✓ Directories created${NC}"

# Check GPU availability
echo -e "${YELLOW}Checking GPU availability...${NC}"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
    echo -e "${GREEN}✓ GPU available${NC}"
else
    echo -e "${RED}✗ nvidia-smi not found! GPU passthrough may not work.${NC}"
    exit 1
fi

# Pull latest image
echo -e "${YELLOW}Pulling ComfyUI API image...${NC}"
docker compose pull

# Start the service
echo -e "${YELLOW}Starting ComfyUI API...${NC}"
docker compose up -d

# Wait for health check
echo -e "${YELLOW}Waiting for service to be healthy...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:3001/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ ComfyUI API is healthy!${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}🎉 ComfyUI API is running!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo "API URL:       http://localhost:3001"
echo "Swagger Docs:  http://localhost:3001/docs"
echo "Health Check:  http://localhost:3001/health"
echo ""
echo "Model directory: ${MODEL_DIR/#\~/$HOME}"
echo ""
echo -e "${YELLOW}Tips:${NC}"
echo "  - Place your models in: ${MODEL_DIR/#\~/$HOME}/checkpoints/"
echo "  - View logs: docker compose logs -f"
echo "  - Stop: docker compose down"
echo "  - Restart: docker compose restart"
