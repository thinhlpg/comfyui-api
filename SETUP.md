# Setup Summary

## Deployment

- **Method**: Docker Compose (no Kubernetes)
- **Image**: `ghcr.io/saladtechnologies/comfyui-api:comfy0.8.2-api1.17.0-torch2.8.0-cuda12.8-runtime`
- **Port**: 3001:3000 (host:container)
- **GPU**: NVIDIA passthrough configured

## Z-Image Turbo Models

Models copied from existing ComfyUI installation:

| Model | Source | Destination |
|-------|--------|-------------|
| `qwen_3_4b.safetensors` | `~/code/comfyui/ComfyUI/models/text_encoders/` | `~/data/comfyui/models/text_encoders/` |
| `z_image_turbo_bf16.safetensors` | `~/code/comfyui/ComfyUI/models/diffusion_models/` | `~/data/comfyui/models/diffusion_models/` |
| `ae.safetensors` | `~/code/comfyui/ComfyUI/models/vae/` | `~/data/comfyui/models/vae/` |

**Method**: Hard-linked copy (no duplicate storage).

## Issues Resolved

1. **Port conflict**: Changed mapping from `3000:3000` to `3001:3000`
2. **Model paths**: Switched from URLs to local file names
3. **Seed validation**: Fixed invalid seed `-1` → use seed ≥ 0
4. **JSON escaping**: Used `jq` for complex prompt payloads

## Performance

| Test | Resolution | Average | Throughput |
|------|------------|---------|------------|
| Simple prompt | 1024×1024 | 1.67s | 0.60 img/s |
| Complex prompt | 1024×1024 | 1.83s | 0.55 img/s |
| Large resolution | 1920×1088 | 4.25s | 0.24 img/s |

Measurements exclude first run (model loading overhead).

## Files

**Core:**
- `docker-compose.yml` - Container configuration
- `run.sh` - Deployment script
- `README.md` - Documentation

**Test Scripts:**
- `test-z-image-turbo.sh` - Basic workflow test
- `test-1920x1088.sh` - Large resolution test
- `test-jan-infographic.sh` - Complex prompt test
