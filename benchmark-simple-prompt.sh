#!/bin/bash
# Benchmark simple prompt workflow with varying seeds
# Run 6 times, calculate average of last 5 runs

API_URL="${1:-http://localhost:3001}"
WIDTH="${2:-1024}"
HEIGHT="${3:-1024}"
RUNS=6

echo "🎨 Simple Prompt Benchmark"
echo "API: $API_URL"
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo "Runs: $RUNS (calculating average of last 5)"
echo ""

PROMPT="A cute anime girl with pink hair, detailed, high quality, masterpiece"

# Create results directory
RESULTS_DIR="benchmark-simple-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

TIMES=()
SEEDS=(42 123 456 789 1337 2024)

for i in $(seq 1 $RUNS); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Run $i/$RUNS (seed: ${SEEDS[$((i-1))]})"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    START_TIME=$(date +%s.%N)
    SEED=${SEEDS[$((i-1))]}
    
    # Build JSON payload using jq
    PAYLOAD=$(jq -n \
      --arg prompt "$PROMPT" \
      --argjson width "$WIDTH" \
      --argjson height "$HEIGHT" \
      --argjson seed "$SEED" \
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
              "seed": ($seed | tonumber),
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
      }')
    
    # Run workflow
    curl -X POST "$API_URL/prompt" \
      -H "Content-Type: application/json" \
      -o "$RESULTS_DIR/run-$i.json" \
      -w "\n" \
      -s \
      -d "$PAYLOAD" > /dev/null 2>&1
    
    END_TIME=$(date +%s.%N)
    ELAPSED=$(python3 -c "print(f'{($END_TIME - $START_TIME):.2f}')")
    
    # Check if successful
    if [ -f "$RESULTS_DIR/run-$i.json" ] && [ -s "$RESULTS_DIR/run-$i.json" ]; then
        # Check if it's JSON with images
        if jq -e '.images[0]' "$RESULTS_DIR/run-$i.json" > /dev/null 2>&1; then
            TIMES+=($ELAPSED)
            printf "✅ Run $i (seed $SEED): %ss\n" $ELAPSED
            
            # Save image
            jq -r '.images[0]' "$RESULTS_DIR/run-$i.json" | base64 -d > "$RESULTS_DIR/run-$i-seed-$SEED.png" 2>/dev/null
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
    printf "  Run %d (seed %d): %ss\n" $((i+1)) ${SEEDS[$i]} ${TIMES[$i]}
done

echo ""
echo "Last 5 runs (excluding first):"
# Convert arrays to comma-separated strings for Python
TIMES_STR=$(IFS=','; echo "${LAST_5[*]}")
SEEDS_STR=$(IFS=','; echo "${SEEDS[*]}")
python3 << PYEOF
import sys
times = [float(x) for x in "${TIMES_STR}".split(',') if x.strip()]
seeds = [int(x) for x in "${SEEDS_STR}".split(',') if x.strip()]

for i, t in enumerate(times):
    seed_idx = i + 1  # Skip first seed
    print(f"  Run {i+2} (seed {seeds[seed_idx]}): {t:.2f}s")

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
