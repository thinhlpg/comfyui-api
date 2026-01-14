# ComfyUI API - Homelab Deployment

Stateless, horizontally-scalable API wrapper for ComfyUI.

**Image**: `ghcr.io/saladtechnologies/comfyui-api:comfy0.8.2-api1.17.0-torch2.8.0-cuda12.8-runtime`

- PyTorch: 2.8.0 (≥2.7 required for SM120/Blackwell)
- CUDA: 12.8 (compatible with driver 590.48.01)
- ComfyUI: 0.8.2
- API: 1.17.0

**Note**: Pre-built Docker image. No build required. Docker will automatically pull the image on first run.

## Deployment

```bash
ssh homelab
cd ~/code/comfyui-api
bash run.sh
```

## Endpoints

| Endpoint | Description |
|----------|-------------|
| `http://localhost:3001` | API base |
| `http://localhost:3001/docs` | Swagger documentation |
| `http://localhost:3001/health` | Health check |
| `http://localhost:3001/ready` | Readiness probe |
| `POST /prompt` | Submit ComfyUI workflow |

## Directory Structure

```
~/data/comfyui/
├── models/
│   ├── checkpoints/      # Main model weights
│   ├── vae/              # VAE models
│   ├── loras/            # LoRA weights
│   ├── controlnet/        # ControlNet models
│   ├── embeddings/        # Text embeddings
│   ├── upscale_models/    # Upscaler models
│   ├── clip/              # CLIP models
│   ├── text_encoders/     # Text encoders (Z-Image Turbo)
│   └── diffusion_models/  # Diffusion models (Z-Image Turbo)
├── output/                # Generated images
├── input/                 # Input images
├── cache/                 # Model cache (LRU, 50GB)
└── custom_nodes/          # Custom ComfyUI nodes
```

## Z-Image Turbo Configuration

### Required Models

| Model | Size | Location |
|-------|------|----------|
| `qwen_3_4b.safetensors` | 7.5GB | `~/data/comfyui/models/text_encoders/` |
| `z_image_turbo_bf16.safetensors` | 12GB | `~/data/comfyui/models/diffusion_models/` |
| `ae.safetensors` | 320MB | `~/data/comfyui/models/vae/` |

**Source**: Models are copied (hard-linked) from `~/code/comfyui/ComfyUI/models/` to `~/data/comfyui/models/` for container access.

### Workflow Structure

10-node workflow:

1. CLIPLoader → `qwen_3_4b.safetensors` (Lumina2)
2. UNETLoader → `z_image_turbo_bf16.safetensors`
3. VAELoader → `ae.safetensors`
4. ModelSamplingAuraFlow (shift: 3.0)
5. CLIPTextEncode
6. ConditioningZeroOut
7. EmptySD3LatentImage
8. KSampler (8 steps, `res_multistep`, `simple`)
9. VAEDecode
10. SaveImage

### Performance

| Resolution | Simple Prompt | Complex Prompt |
|------------|---------------|----------------|
| 1024×1024 | 1.67s avg (0.60 img/s) | 1.83s avg (0.55 img/s) |
| 1920×1088 | 4.25s | 4.25s |

First run includes model loading overhead.

### Testing

```bash
# Simple test
bash test-z-image-turbo.sh http://localhost:3001

# Custom resolution
bash test-jan-infographic.sh http://localhost:3001 1920 1088
```

## API Usage

**API có sẵn, không cần code wrapper.** Chỉ cần gọi HTTP endpoint.

### Quick Start

```bash
# Method 1: Dùng workflow JSON đã lưu
curl -X POST http://localhost:3001/prompt \
  -H "Content-Type: application/json" \
  -d @workflows/z-image-turbo.json \
  -o response.json

# Decode base64 image từ response
jq -r '.images[0]' response.json | base64 -d > output.png
```

### Response Format

```json
{
  "id": "uuid",
  "images": ["base64-encoded-image-string"],
  "filenames": ["output-filename.png"],
  "stats": { ... }
}
```

### Swagger Documentation

Xem tất cả endpoints và test trực tiếp tại:
- **Swagger UI**: `http://localhost:3001/docs`
- **OpenAPI Spec**: `http://localhost:3001/docs/json`

### Example: Python Client

```python
import requests
import base64
import json

API_URL = "http://localhost:3001"

# Load workflow
with open("workflows/z-image-turbo.json") as f:
    workflow = json.load(f)

# Update prompt
workflow["5"]["inputs"]["text"] = "Your custom prompt here"

# Submit
response = requests.post(
    f"{API_URL}/prompt",
    json={"prompt": workflow}
)

result = response.json()
image_base64 = result["images"][0]

# Save image
image_data = base64.b64decode(image_base64)
with open("output.png", "wb") as f:
    f.write(image_data)
```

### Example: curl với inline JSON

```bash
curl -X POST http://localhost:3001/prompt \
  -H "Content-Type: application/json" \
  -d '{"prompt": {...}}' \
  -o response.json
```

### Dynamic Model Loading

Models can be loaded from URLs:

```json
{
  "inputs": {
    "ckpt_name": "https://huggingface.co/.../model.safetensors"
  },
  "class_type": "CheckpointLoaderSimple"
}
```

Models are automatically downloaded and cached (50GB LRU cache).

## Management

```bash
# View logs
docker compose -f ~/code/comfyui-api/docker-compose.yml logs -f

# Stop
docker compose -f ~/code/comfyui-api/docker-compose.yml down

# Restart
docker compose -f ~/code/comfyui-api/docker-compose.yml restart

# Container shell
docker exec -it comfyui-api bash

# Verify models
docker exec comfyui-api ls -la /opt/ComfyUI/models/{text_encoders,diffusion_models,vae}/
```

## Configuration

Edit `docker-compose.yml`:

- `LRU_CACHE_SIZE_GB`: Model cache size (default: 50GB)
- `MAX_BODY_SIZE_MB`: Max request size (default: 200MB)
- `HF_TOKEN`: Hugging Face token for gated models (set via environment variable)
- `PORT`: API port (default: 3000, host: 3001)

Set `HF_TOKEN` in `.env` file or export before running:

```bash
export HF_TOKEN=your_token_here
docker compose up -d
```

## Troubleshooting

### Models Not Found

```bash
# Verify host models
ls -la ~/data/comfyui/models/{text_encoders,diffusion_models,vae}/

# Verify container access
docker exec comfyui-api ls -la /opt/ComfyUI/models/{text_encoders,diffusion_models,vae}/

# Copy if missing
cp -l ~/code/comfyui/ComfyUI/models/text_encoders/qwen_3_4b.safetensors ~/data/comfyui/models/text_encoders/
cp -l ~/code/comfyui/ComfyUI/models/diffusion_models/z_image_turbo_bf16.safetensors ~/data/comfyui/models/diffusion_models/
cp -l ~/code/comfyui/ComfyUI/models/vae/ae.safetensors ~/data/comfyui/models/vae/
```

### Port Conflict

Change port mapping in `docker-compose.yml`:

```yaml
ports:
  - "3002:3000"
```

### Seed Validation

KSampler requires seed ≥ 0. Use fixed seed or valid random value:

```json
{
  "seed": 42  // Valid
  // "seed": -1  // Invalid
}
```

## References

- [GitHub: SaladTechnologies/comfyui-api](https://github.com/SaladTechnologies/comfyui-api)
- [ComfyUI Workflow Templates](https://github.com/Comfy-Org/workflow_templates)
- [Z-Image Turbo on HuggingFace](https://huggingface.co/Comfy-Org/z_image_turbo)
