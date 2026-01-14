#!/bin/bash
# Test Z-Image Turbo workflow with ComfyUI API
# Models will be downloaded automatically on first run

API_URL="${1:-http://localhost:3001}"

echo "🎨 Testing Z-Image Turbo workflow"
echo "API: $API_URL"
echo ""

# Z-Image Turbo workflow with dynamic model loading
# Models from: https://huggingface.co/Comfy-Org/z_image_turbo

curl -X POST "$API_URL/prompt" \
  -H "Content-Type: application/json" \
  -o z-image-output.png \
  -w "\n\nHTTP Status: %{http_code}\nTime: %{time_total}s\n" \
  -d '{
    "prompt": {
      "1": {
        "class_type": "CLIPLoader",
        "inputs": {
          "clip_name": "qwen_3_4b.safetensors",
          "type": "lumina2",
          "weight_dtype": "default"
        }
      },
      "2": {
        "class_type": "UNETLoader",
        "inputs": {
          "unet_name": "z_image_turbo_bf16.safetensors",
          "weight_dtype": "default"
        }
      },
      "3": {
        "class_type": "VAELoader",
        "inputs": {
          "vae_name": "ae.safetensors"
        }
      },
      "4": {
        "class_type": "ModelSamplingAuraFlow",
        "inputs": {
          "model": ["2", 0],
          "shift": 3.0
        }
      },
      "5": {
        "class_type": "CLIPTextEncode",
        "inputs": {
          "clip": ["1", 0],
          "text": "A cute anime girl with pink hair, detailed, high quality, masterpiece"
        }
      },
      "6": {
        "class_type": "ConditioningZeroOut",
        "inputs": {
          "conditioning": ["5", 0]
        }
      },
      "7": {
        "class_type": "EmptySD3LatentImage",
        "inputs": {
          "width": 1024,
          "height": 1024,
          "batch_size": 1
        }
      },
      "8": {
        "class_type": "KSampler",
        "inputs": {
          "seed": 42,
          "steps": 4,
          "cfg": 1.0,
          "sampler_name": "res_multistep",
          "scheduler": "simple",
          "denoise": 1.0,
          "model": ["4", 0],
          "positive": ["5", 0],
          "negative": ["6", 0],
          "latent_image": ["7", 0]
        }
      },
      "9": {
        "class_type": "VAEDecode",
        "inputs": {
          "samples": ["8", 0],
          "vae": ["3", 0]
        }
      },
      "10": {
        "class_type": "SaveImage",
        "inputs": {
          "images": ["9", 0],
          "filename_prefix": "z-image-turbo"
        }
      }
    }
  }'

if [ -f "z-image-output.png" ] && [ -s "z-image-output.png" ]; then
    echo ""
    echo "✅ Success! Image saved to z-image-output.png"
    file z-image-output.png
else
    echo ""
    echo "❌ Failed or no image generated"
    cat z-image-output.png 2>/dev/null
fi
