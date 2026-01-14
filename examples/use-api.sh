#!/bin/bash
# Example: Using ComfyUI API with Z-Image Turbo workflow

API_URL="${1:-http://localhost:3001}"

echo "Using ComfyUI API at: $API_URL"
echo ""

# Method 1: Use saved workflow JSON file
echo "Method 1: Using saved workflow JSON"
curl -X POST "$API_URL/prompt" \
  -H "Content-Type: application/json" \
  -d @../workflows/z-image-turbo.json \
  -o response.json

# Extract base64 image
if [ -f "response.json" ]; then
    echo "Response received"
    # Decode base64 image
    jq -r '.images[0]' response.json | base64 -d > output.png
    echo "Image saved to output.png"
fi

echo ""
echo "Method 2: Direct API call with inline JSON"
curl -X POST "$API_URL/prompt" \
  -H "Content-Type: application/json" \
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
          "text": "A beautiful landscape, mountains, sunset"
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
          "filename_prefix": "z-image-turbo"
        }
      }
    }
  }' \
  -o response2.json

echo ""
echo "Check Swagger docs at: $API_URL/docs"
echo "Health check: curl $API_URL/health"
