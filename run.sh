#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DEFAULT_DATA_ROOT="$HOME/data/comfyui"

# Create .env if missing
if [[ ! -f ".env" ]]; then
    cat > .env << EOF
MODEL_DIR=${DEFAULT_DATA_ROOT}/models
OUTPUT_DIR=${DEFAULT_DATA_ROOT}/output
INPUT_DIR=${DEFAULT_DATA_ROOT}/input
CACHE_DIR=${DEFAULT_DATA_ROOT}/cache
CUSTOM_NODES_DIR=${DEFAULT_DATA_ROOT}/custom_nodes
EOF
fi

# Source .env
source .env

# Create directories
mkdir -p "${MODEL_DIR/#\~/$HOME}" \
         "${OUTPUT_DIR/#\~/$HOME}" \
         "${INPUT_DIR/#\~/$HOME}" \
         "${CACHE_DIR/#\~/$HOME}" \
         "${CUSTOM_NODES_DIR/#\~/$HOME}"

# Create model subdirectories
mkdir -p "${MODEL_DIR/#\~/$HOME}/checkpoints" \
         "${MODEL_DIR/#\~/$HOME}/vae" \
         "${MODEL_DIR/#\~/$HOME}/loras" \
         "${MODEL_DIR/#\~/$HOME}/controlnet" \
         "${MODEL_DIR/#\~/$HOME}/embeddings" \
         "${MODEL_DIR/#\~/$HOME}/upscale_models" \
         "${MODEL_DIR/#\~/$HOME}/clip" \
         "${MODEL_DIR/#\~/$HOME}/clip_vision" \
         "${MODEL_DIR/#\~/$HOME}/text_encoders" \
         "${MODEL_DIR/#\~/$HOME}/diffusion_models" \
         "${MODEL_DIR/#\~/$HOME}/unet"

# Check GPU
if ! command -v nvidia-smi &> /dev/null; then
    echo "Error: nvidia-smi not found" >&2
    exit 1
fi

# Pull image
docker compose pull > /dev/null 2>&1

# Start service
docker compose up -d

# Wait for health
for i in {1..30}; do
    if curl -s http://localhost:3001/health > /dev/null 2>&1; then
        exit 0
    fi
    sleep 2
done

echo "Error: Service did not become healthy" >&2
exit 1
