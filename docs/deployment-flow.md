# Deployment Flow & Architecture

Visual guide showing what happens when infrastructure team runs the deployment.

## Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Infrastructure Team Runs: bash run.sh                         │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  run.sh Pre-Deployment Steps                                    │
│  - Creates .env from env.example (if missing)                   │
│  - Creates directory structure (~/data/comfyui/...)             │
│  - Creates model subdirectories (checkpoints, loras, vae, etc.)│
│  - Checks GPU availability (nvidia-smi)                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Docker Compose Reads: docker-compose.yml                   │
│     - Image: ghcr.io/saladtechnologies/comfyui-api:...         │
│     - Ports: 3001:3000 (API), 8188:8188 (ComfyUI)             │
│     - Volumes: models, output, input, cache, custom_nodes     │
│     - Environment: Reads from .env file                         │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Docker Pulls Image (if not cached)                          │
│     Source: ghcr.io (GitHub Container Registry)                │
│     Size: ~3.25GB compressed                                    │
│     Contains: ComfyUI + comfyui-api binary + dependencies      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Container Starts                                            │
│     - Mounts volumes from host to container                     │
│     - Sets environment variables (PORT, HF_TOKEN, etc.)         │
│     - Runs: python main.py --normalvram --listen 0.0.0.0       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. comfyui-api Server Starts                                   │
│     - Listens on port 3000 (internal)                           │
│     - Launches ComfyUI on port 8188 (internal)                  │
│     - Runs warmup workflow (if configured)                     │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. Health Checks Pass                                          │
│     - GET /health → 200 OK                                      │
│     - GET /ready → 200 OK                                       │
│     - Service ready to accept requests                          │
└─────────────────────────────────────────────────────────────────┘
```

## Component Connections

```
┌──────────────────────────────────────────────────────────────────┐
│                         Client Applications                      │
│                    (qwen-image-edit, etc.)                      │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │ HTTP POST /prompt
                             │
┌────────────────────────────▼────────────────────────────────────┐
│              comfyui-api (Port 3000)                            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  - Receives workflow JSON                                │  │
│  │  - Downloads input images (if URLs provided)             │  │
│  │  - Downloads models (if URLs in workflow)                │  │
│  │  - Queues prompt to ComfyUI                              │  │
│  │  - Waits for completion                                   │  │
│  │  - Returns base64 images or webhook                       │  │
│  └───────────────────────┬──────────────────────────────────┘  │
└──────────────────────────┼─────────────────────────────────────┘
                            │
                            │ Internal API calls
                            │ POST http://127.0.0.1:8188/prompt
                            │
┌───────────────────────────▼────────────────────────────────────┐
│              ComfyUI Core (Port 8188)                           │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  - Loads models from /opt/ComfyUI/models/                │  │
│  │  - Executes workflow nodes                               │  │
│  │  - Generates images                                       │  │
│  │  - Saves to /opt/ComfyUI/output/                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Download Sources & Disk Layout

### What Gets Downloaded

```
┌─────────────────────────────────────────────────────────────────┐
│  Download Sources                                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Docker Image (First Run)                                    │
│     Source: ghcr.io/saladtechnologies/comfyui-api               │
│     Size: ~3.25GB compressed                                    │
│     Location: Docker's image cache                              │
│                                                                  │
│  2. Models (On-Demand or Manifest)                             │
│     Sources:                                                    │
│     - Hugging Face: https://huggingface.co/.../model.safetensors│
│     - Local/NAS: Already in ${MODEL_DIR} (no download needed) │
│     Location: /cache/ (hashed filename) → symlink to models/   │
│     Note: Models can be pre-placed in models/ directory        │
│                                                                  │
│  3. Input Images (Per Request)                                  │
│     Sources:                                                    │
│     - URLs in workflow JSON                                    │
│     - Base64 in request body                                    │
│     Location: /opt/ComfyUI/input/ (temporary)                  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Disk Layout

**Single Instance:**
```
Host Filesystem (NAS/Shared Storage)     Container Filesystem
─────────────────────────────────────    ─────────────────────

${MODEL_DIR} (shared across instances)   /opt/ComfyUI/models/
├── checkpoints/     ──mount──>          ├── checkpoints/
├── loras/                               ├── loras/
├── vae/                                 ├── vae/
├── text_encoders/                       ├── text_encoders/
├── diffusion_models/                    ├── diffusion_models/
└── ...                                  └── ...

${OUTPUT_DIR} (per-instance)             /opt/ComfyUI/output/
└── *.png            ──mount──>          └── *.png

${INPUT_DIR} (per-instance)              /opt/ComfyUI/input/
└── (temporary)      ──mount──>          └── (temporary)

${CACHE_DIR} (per-instance)              /cache/
└── <32-char-hash>.safetensors ──mount──> └── <32-char-hash>.safetensors
    └── symlink ────────────────────────────────> /opt/ComfyUI/models/.../

${CUSTOM_NODES_DIR} (shared)             /opt/ComfyUI/custom_nodes/
└── extensions/      ──mount──>          └── extensions/
```

**Multiple Instances (Shared Models):**
```
Shared Storage (NAS)                     Multiple Containers
────────────────────                     ───────────────────

/mnt/nas/comfyui/models/  ──mount──>    Instance 1: /opt/ComfyUI/models/
├── checkpoints/                         Instance 2: /opt/ComfyUI/models/
├── loras/                               Instance 3: /opt/ComfyUI/models/
├── vae/                                 (all read from same source)
└── ...

Per-Instance Storage:
Instance 1: /data/comfyui-1/cache/  ──>  /cache/ (LRU managed)
Instance 2: /data/comfyui-2/cache/  ──>  /cache/ (LRU managed)
Instance 3: /data/comfyui-3/cache/  ──>  /cache/ (LRU managed)
```

**Key Points:**
- **MODEL_DIR**: Shared across all instances (NAS/mounted storage) - saves space
- **CACHE_DIR**: Per-instance (each has own LRU cache)
- **OUTPUT_DIR**: Per-instance (each generates to own directory)
- **Example**: Instance 1 serves image-edit, Instance 2 serves image-gen, both use same models

**Note:** Host paths come from `.env` file. Set `MODEL_DIR` to shared storage path (e.g., `/mnt/nas/comfyui/models`) for multi-instance deployments.

### Multi-Instance Deployment

**Use Case:** Run multiple instances (e.g., image-edit, image-gen) sharing the same models.

```
┌─────────────────────────────────────────────────────────────────┐
│  Shared Storage (NAS)                                           │
│  /mnt/nas/comfyui/models/                                        │
│  ├── checkpoints/ (shared)                                      │
│  ├── loras/ (shared)                                            │
│  ├── vae/ (shared)                                              │
│  └── ...                                                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
            ┌───────────────┼───────────────┐
            │               │               │
            ▼               ▼               ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ Instance 1       │ │ Instance 2       │ │ Instance 3       │
│ (image-edit)     │ │ (image-gen)      │ │ (video-gen)      │
│                  │ │                  │ │                  │
│ MODEL_DIR:       │ │ MODEL_DIR:       │ │ MODEL_DIR:       │
│ /mnt/nas/...     │ │ /mnt/nas/...     │ │ /mnt/nas/...     │
│ (shared)         │ │ (shared)         │ │ (shared)         │
│                  │ │                  │ │                  │
│ CACHE_DIR:       │ │ CACHE_DIR:       │ │ CACHE_DIR:       │
│ /data/inst1/...  │ │ /data/inst2/...  │ │ /data/inst3/...  │
│ (per-instance)   │ │ (per-instance)   │ │ (per-instance)   │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

**Configuration:**
- All instances mount same `MODEL_DIR` (shared storage/NAS)
- Each instance has own `CACHE_DIR` (per-instance LRU cache)
- Each instance has own `OUTPUT_DIR` (per-instance outputs)
- Models stored once, accessible by all instances

**Benefits:**
- Space efficient: Models stored once, not duplicated per instance
- Fast startup: No model download needed if pre-placed
- Flexible: Different instances can serve different workflows using same models

### Model Loading Flow

**Two Paths:**

**Path 1: Pre-placed Models (Local/NAS) - Recommended**
```
┌─────────────────────────────────────────────────────────────────┐
│  Models Already in ${MODEL_DIR} (mounted from NAS/local)        │
│  Example: qwen_3_4b.safetensors in models/text_encoders/         │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Direct Load (No Download)                                     │
│  - ComfyUI reads directly from /opt/ComfyUI/models/             │
│  - No cache lookup needed                                       │
│  - No symlink needed                                            │
│  - Fastest path (no network/download overhead)                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Load Model in ComfyUI                                          │
│  - Model loaded into GPU memory                                 │
│  - Workflow execution begins                                    │
└─────────────────────────────────────────────────────────────────┘
```

**Path 2: Download from Hugging Face (On-Demand)**
```
┌─────────────────────────────────────────────────────────────────┐
│  Workflow Request Contains Model URL                             │
│  Example: "ckpt_name": "https://hf.co/.../model.safetensors"   │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Check Cache                                                 │
│     - Hash URL → cache filename (first 32 chars + extension)   │
│     - Check: /cache/<32-char-hash>.safetensors exists?         │
│     - If yes: Use cached file (skip download)                  │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼ (if not cached)
┌─────────────────────────────────────────────────────────────────┐
│  2. Download from Hugging Face                                  │
│     Source: https://huggingface.co/.../model.safetensors       │
│     Auth: HF_TOKEN env var or credentials in request            │
│     Location: /cache/<32-char-hash>.safetensors                │
│     Example: URL → hash → "Pk6VSKLStckZydwGhX0bM8TqaqHEW9yt.safetensors"
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Create Symlink                                              │
│     From: /cache/<32-char-hash>.safetensors                     │
│     To: /opt/ComfyUI/models/<type>/<filename>                  │
│     Purpose: ComfyUI expects models in specific directories     │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Load Model in ComfyUI                                       │
│     - ComfyUI reads from /opt/ComfyUI/models/                   │
│     - Model loaded into GPU memory                               │
│     - Workflow execution begins                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Recommendation:** Pre-place models in `${MODEL_DIR}` (NAS/local) for faster startup and no download overhead.

## Network Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  External Request Flow                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Client → Load Balancer → comfyui-api:3000 → ComfyUI:8188      │
│                                                                  │
│  Port Mapping:                                                  │
│  - Host:3001 → Container:3000 (comfyui-api)                    │
│  - Host:8188 → Container:8188 (ComfyUI, internal only)         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Outbound Connections                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Container → Internet                                           │
│  - Hugging Face API (model downloads)                          │
│  - Webhook URLs (async responses)                              │
│  - Input image URLs (workflow inputs)                           │
│                                                                  │
│  Container → Local/NAS                                          │
│  - Models directory (${MODEL_DIR} mounted volume)              │
│  - Pre-placed models (no download needed)                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Environment Variables Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Environment Variable Sources                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. .env file (local)                                           │
│     - HF_TOKEN=...                                             │
│     - MODEL_DIR=...                                            │
│                                                                  │
│  2. docker-compose.yml (hardcoded)                              │
│     - PORT=3000                                                 │
│     - CMD=python main.py --normalvram --listen 0.0.0.0         │
│                                                                  │
│  3. Container environment                                       │
│     - All env vars passed to container                          │
│     - Used by comfyui-api and ComfyUI                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Volume Mounts

```
┌─────────────────────────────────────────────────────────────────┐
│  Volume Mounts (docker-compose.yml)                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Host Path              Container Path        Purpose           │
│  ─────────────────────────────────────────────────────────────  │
│  ${MODEL_DIR:-./models}  /opt/ComfyUI/models   Model storage     │
│                          (shared across instances for space)     │
│  ${OUTPUT_DIR:-./output} /opt/ComfyUI/output   Generated images  │
│                          (per-instance)                          │
│  ${INPUT_DIR:-./input}   /opt/ComfyUI/input    Input images      │
│                          (per-instance)                          │
│  ${CACHE_DIR:-./cache}   /cache                Model cache       │
│                          (per-instance, LRU managed)             │
│  ${CUSTOM_NODES_DIR:-...} /opt/ComfyUI/custom_nodes Extensions   │
│                          (shared across instances)                │
│                                                                  │
│  Note: Paths come from .env file (created by run.sh)            │
│        For multi-instance: Set MODEL_DIR to shared storage/NAS  │
│        Example: MODEL_DIR=/mnt/nas/comfyui/models              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Summary

**What Happens:**
1. Docker pulls pre-built image from GitHub Container Registry
2. Container starts with volume mounts and environment variables
3. comfyui-api server launches ComfyUI as subprocess
4. Models downloaded on-demand to cache, then symlinked to models/
5. Workflows execute, images saved to output/
6. API returns base64 images or sends webhook

**Key Points:**
- No build step required (pre-built image)
- Models shared across instances (single MODEL_DIR on NAS/shared storage)
- Cache per-instance (LRU eviction, each instance has own CACHE_DIR)
- Stateless API (can scale horizontally)
- Multi-instance: Different instances (image-edit, image-gen) share same models
- Health checks at `/health` and `/ready`
