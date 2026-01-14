#!/bin/bash
# Test Z-Image Turbo workflow with Jan Infographic prompt

API_URL="${1:-http://localhost:3001}"

echo "🎨 Testing Z-Image Turbo - Jan Infographic"
echo "API: $API_URL"
echo ""

# Use Python to send the JSON payload
python3 -c '
import requests
import json
import base64
import sys
import time

api_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:3001"
workflow_file = "workflows/z-image-turbo-jan-infographic-with-lora.json"

try:
    with open(workflow_file, "r") as f:
        workflow = json.load(f)
except FileNotFoundError:
    print(f"Error: Workflow file not found at {workflow_file}")
    sys.exit(1)
except json.JSONDecodeError:
    print(f"Error: Invalid JSON in {workflow_file}")
    sys.exit(1)

payload = {"prompt": workflow}

print("Sending request to API...")
start_time = time.time()

try:
    response = requests.post(f"{api_url}/prompt", json=payload, timeout=300)
    elapsed = time.time() - start_time
except requests.exceptions.RequestException as e:
    print(f"Error: Request failed - {e}")
    sys.exit(1)

if response.status_code == 200:
    data = response.json()
    if "images" in data and len(data["images"]) > 0:
        print("HTTP Status: 200")
        print("\n✅ Success! Decoding image...")
        image_data = base64.b64decode(data["images"][0])
        output_file = "jan-infographic-output.png"
        with open(output_file, "wb") as f:
            f.write(image_data)
        print(f"Image saved to {output_file}")
        print(f"\n⏱️  Total time: {elapsed:.2f}s")
        
        # Show file info
        import os
        size = os.path.getsize(output_file)
        print(f"File size: {size / 1024:.1f} KB")
    else:
        print(f"HTTP Status: {response.status_code}")
        print("\n❌ Failed - no image in response")
        print(json.dumps(data, indent=2))
else:
    print(f"HTTP Status: {response.status_code}")
    print("\n❌ Failed")
    try:
        error_data = response.json()
        print(json.dumps(error_data, indent=2))
    except:
        print(response.text)
' "$API_URL"
