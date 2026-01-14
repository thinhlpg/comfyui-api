#!/bin/bash
# Test Z-Image Turbo workflow with Jan Infographic prompt

API_URL="${1:-http://localhost:3001}"
WIDTH="${2:-1920}"
HEIGHT="${3:-1088}"

echo "🎨 Testing Z-Image Turbo - Jan Infographic"
echo "API: $API_URL"
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo ""

PROMPT="jan infographic Create an infographic that features the title \"Alan Dao's Life Progress Bar\" at the top. The main visualization is a horizontal bar chart showing age progression from 0 to 99 years old. The bar is divided into segments: ages 0-29 are filled in (showing \"29 years old\" at the current position), ages 30-98 are empty/unfilled, and age 99 is marked with a skull emoji or \"💀 DEATH\" text. Below the chart, there is text saying \"Only 70 more years to go!\" in a humorous font. The given data is: | Age Range | Status | |-----------|--------| | 0-29 | ✅ Completed | | 30-98 | ⏳ Remaining | | 99 | 💀 Death | Position & Pose: The mascot, positioned on the left side of the infographic and measuring approximately one-quarter of the panel's total height, is sitting wearing a colorful birthday hat on its head, with its right hand pointing at the \"29 years old\" mark on the progress bar and its left hand giving a thumbs up, displaying a cheeky smile as a small white cat wearing a tiny birthday hat lies perched on its head."

START_TIME=$(date +%s.%N)

# Build JSON payload using jq to properly escape the prompt
PAYLOAD=$(jq -n \
  --arg prompt "$PROMPT" \
  --argjson width "$WIDTH" \
  --argjson height "$HEIGHT" \
  '{
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
          "text": $prompt
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
          "width": ($width | tonumber),
          "height": ($height | tonumber),
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
          "filename_prefix": "jan-infographic"
        }
      }
    }
  }')

curl -X POST "$API_URL/prompt" \
  -H "Content-Type: application/json" \
  -o jan-infographic.json \
  -w "\n\nHTTP Status: %{http_code}\nTime: %{time_total}s\n" \
  -d "$PAYLOAD"

END_TIME=$(date +%s.%N)
ELAPSED=$(python3 -c "print(f'{($END_TIME - $START_TIME):.2f}')")

if [ -f "jan-infographic.json" ] && [ -s "jan-infographic.json" ]; then
    if jq -e '.images[0]' jan-infographic.json > /dev/null 2>&1; then
        echo ""
        echo "✅ Success! Decoding image..."
        jq -r '.images[0]' jan-infographic.json | base64 -d > jan-infographic-${WIDTH}x${HEIGHT}.png
        file jan-infographic-${WIDTH}x${HEIGHT}.png
        ls -lh jan-infographic-${WIDTH}x${HEIGHT}.png
        echo ""
        echo "⏱️  Total time: ${ELAPSED}s"
    else
        echo ""
        echo "❌ Failed - no image in response"
        cat jan-infographic.json | head -10
    fi
else
    echo ""
    echo "❌ Failed - no response"
fi
