#!/bin/bash
# Benchmark Z-Image Turbo workflow with Jan Infographic LoRA
# Run 6 times, exclude first run (model loading), average last 5

API_URL="${1:-http://localhost:3001}"
NUM_RUNS=6

echo "🎨 Benchmarking Z-Image Turbo - Jan Infographic with LoRA"
echo "API: $API_URL"
echo "Running $NUM_RUNS times (excluding first run for average)"
echo ""

# Use Python for robust timing and calculations
python3 << PYEOF
import requests
import json
import base64
import time
import random
import sys

api_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3001"
workflow_file = "workflows/z-image-turbo-jan-infographic-with-lora.json"
num_runs = 6

try:
    with open(workflow_file, "r") as f:
        workflow = json.load(f)
except FileNotFoundError:
    print(f"Error: Workflow file not found at {workflow_file}")
    sys.exit(1)
except json.JSONDecodeError:
    print(f"Error: Invalid JSON in {workflow_file}")
    sys.exit(1)

times = []

for run in range(1, num_runs + 1):
    # Generate random seed for each run
    seed = random.randint(0, 2**31 - 1)
    workflow["9"]["inputs"]["seed"] = seed
    
    payload = {"prompt": workflow}
    
    print(f"Run {run}/{num_runs} (seed: {seed})... ", end="", flush=True)
    start_time = time.time()
    
    try:
        response = requests.post(f"{api_url}/prompt", json=payload, timeout=300)
        elapsed = time.time() - start_time
        
        if response.status_code == 200:
            data = response.json()
            if "images" in data and len(data["images"]) > 0:
                times.append(elapsed)
                print(f"✅ {elapsed:.2f}s")
                
                # Save first image from first successful run
                if run == 1:
                    image_data = base64.b64decode(data["images"][0])
                    with open("jan-infographic-lora-benchmark.png", "wb") as f:
                        f.write(image_data)
            else:
                print(f"❌ No image in response")
                if run == 1:
                    print(json.dumps(data, indent=2))
        else:
            print(f"❌ HTTP {response.status_code}")
            if run == 1:
                try:
                    print(json.dumps(response.json(), indent=2))
                except:
                    print(response.text)
    except requests.exceptions.RequestException as e:
        print(f"❌ Error: {e}")
        if run == 1:
            sys.exit(1)

print("")
print("=" * 50)
print("Results:")
print("=" * 50)

if len(times) > 1:
    # Exclude first run (model loading)
    times_without_first = times[1:]
    
    print(f"Run 1 (excluded): {times[0]:.2f}s (model loading)")
    print("")
    print("Last 5 runs:")
    for i, t in enumerate(times_without_first, 2):
        print(f"  Run {i}: {t:.2f}s")
    
    avg = sum(times_without_first) / len(times_without_first)
    min_time = min(times_without_first)
    max_time = max(times_without_first)
    
    print("")
    print(f"Average (last 5): {avg:.2f}s")
    print(f"Min: {min_time:.2f}s")
    print(f"Max: {max_time:.2f}s")
    print(f"Throughput: {1/avg:.2f} img/s")
elif len(times) == 1:
    print(f"Only 1 successful run: {times[0]:.2f}s")
else:
    print("❌ No successful runs")
    sys.exit(1)
PYEOF
