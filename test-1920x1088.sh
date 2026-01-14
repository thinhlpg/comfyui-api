#!/bin/bash
# Test Z-Image Turbo workflow with 1920x1088 resolution

API_URL="${1:-http://localhost:3001}"

echo "🎨 Testing Z-Image Turbo workflow (1920x1088)"
echo "API: $API_URL"
echo ""

START_TIME=$(date +%s.%N)

curl -X POST "$API_URL/prompt" \
  -H "Content-Type: application/json" \
  -o z-image-1920x1088.json \
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
          "width": 1920,
          "height": 1088,
          "batch_size": 1
        }
      },
      "8": {
        "class_type": "KSampler",
        "inputs": {
          "seed": 42,
                 "steps": 8,
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
          "filename_prefix": "z-image-turbo-1920x1088"
        }
      }
    }
  }'

END_TIME=$(date +%s.%N)
ELAPSED=$(python3 -c "print(f'{($END_TIME - $START_TIME):.2f}')")

if [ -f "z-image-1920x1088.json" ] && [ -s "z-image-1920x1088.json" ]; then
    if jq -e '.images[0]' z-image-1920x1088.json > /dev/null 2>&1; then
        echo ""
        echo "✅ Success! Decoding image..."
        jq -r '.images[0]' z-image-1920x1088.json | base64 -d > z-image-turbo-1920x1088.png
        file z-image-turbo-1920x1088.png
        ls -lh z-image-turbo-1920x1088.png
        echo ""
        echo "⏱️  Total time: ${ELAPSED}s"
    else
        echo ""
        echo "❌ Failed - no image in response"
        cat z-image-1920x1088.json | head -10
    fi
else
    echo ""
    echo "❌ Failed - no response"
fi
