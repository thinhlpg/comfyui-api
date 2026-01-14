#!/bin/bash
# Benchmark Z-Image Turbo workflow
# Run 6 times, calculate average of last 5 runs (skip first run due to model loading)

API_URL="${1:-http://localhost:3001}"
RUNS=6

echo "🎨 Z-Image Turbo Benchmark"
echo "API: $API_URL"
echo "Runs: $RUNS (calculating average of last 5)"
echo ""

# Create results directory
RESULTS_DIR="benchmark-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

TIMES=()

for i in $(seq 1 $RUNS); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Run $i/$RUNS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    START_TIME=$(date +%s.%N)
    
    # Run workflow
    curl -X POST "$API_URL/prompt" \
      -H "Content-Type: application/json" \
      -o "$RESULTS_DIR/run-$i.json" \
      -w "\n" \
      -s \
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
      }' > /dev/null 2>&1
    
    END_TIME=$(date +%s.%N)
    ELAPSED=$(python3 -c "print(f'{($END_TIME - $START_TIME):.2f}')")
    
    # Check if successful
    if [ -f "$RESULTS_DIR/run-$i.json" ] && [ -s "$RESULTS_DIR/run-$i.json" ]; then
        # Check if it's JSON with images
        if jq -e '.images[0]' "$RESULTS_DIR/run-$i.json" > /dev/null 2>&1; then
            TIMES+=($ELAPSED)
            printf "✅ Run $i: %ss\n" $ELAPSED
            
            # Save image
            jq -r '.images[0]' "$RESULTS_DIR/run-$i.json" | base64 -d > "$RESULTS_DIR/run-$i.png" 2>/dev/null
        else
            echo "❌ Run $i: Failed (no image in response)"
            cat "$RESULTS_DIR/run-$i.json" | head -5
        fi
    else
        echo "❌ Run $i: Failed (no response)"
    fi
    
    # Wait a bit between runs
    if [ $i -lt $RUNS ]; then
        sleep 2
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Results"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ${#TIMES[@]} -lt 2 ]; then
    echo "❌ Not enough successful runs for benchmark"
    exit 1
fi

# Calculate stats (skip first run)
SKIP_FIRST=1
LAST_5=("${TIMES[@]:$SKIP_FIRST}")

echo "All runs:"
for i in "${!TIMES[@]}"; do
    printf "  Run %d: %ss\n" $((i+1)) ${TIMES[$i]}
done

echo ""
echo "Last 5 runs (excluding first):"
# Convert array to comma-separated string for Python
TIMES_STR=$(IFS=','; echo "${LAST_5[*]}")
python3 << PYEOF
import sys
times = [float(x) for x in "${TIMES_STR}".split(',') if x.strip()]

for i, t in enumerate(times):
    print(f"  Run {i+2}: {t:.2f}s")

if times:
    total = sum(times)
    avg = total / len(times)
    min_time = min(times)
    max_time = max(times)
    
    print("")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("📈 Statistics (Last 5 runs)")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"Average: {avg:.2f}s")
    print(f"Min:     {min_time:.2f}s")
    print(f"Max:     {max_time:.2f}s")
    print(f"Total:   {total:.2f}s")
PYEOF

echo ""
echo "Results saved to: $RESULTS_DIR/"
