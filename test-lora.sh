#!/bin/bash
# Test Z-Image Turbo workflow with Jan Infographic LoRA

API_URL="${1:-http://localhost:3001}"

echo "🎨 Testing Z-Image Turbo with Jan Infographic LoRA"
echo "API: $API_URL"
echo ""

START_TIME=$(date +%s.%N)

# Use Python to properly send JSON payload
python3 << PYEOF
import json
import requests
import time

with open('workflows/z-image-turbo-with-lora.json', 'r') as f:
    workflow = json.load(f)

payload = {'prompt': workflow}
response = requests.post('$API_URL/prompt', json=payload, timeout=120)

with open('z-image-turbo-lora.json', 'w') as f:
    json.dump(response.json(), f)

print(f"HTTP Status: {response.status_code}")
PYEOF

HTTP_STATUS=$(python3 -c "import json; data=json.load(open('z-image-turbo-lora.json')); print('200' if 'images' in data else '500')" 2>/dev/null || echo "400")

END_TIME=$(date +%s.%N)
ELAPSED=$(python3 -c "print(f'{($END_TIME - $START_TIME):.2f}')")

if [ -f "z-image-turbo-lora.json" ] && [ -s "z-image-turbo-lora.json" ]; then
    if jq -e '.images[0]' z-image-turbo-lora.json > /dev/null 2>&1; then
        echo ""
        echo "✅ Success! Decoding image..."
        jq -r '.images[0]' z-image-turbo-lora.json | base64 -d > z-image-turbo-lora.png
        file z-image-turbo-lora.png
        ls -lh z-image-turbo-lora.png
        echo ""
        echo "⏱️  Total time: ${ELAPSED}s"
    else
        echo ""
        echo "❌ Failed - no image in response"
        cat z-image-turbo-lora.json | head -10
    fi
else
    echo ""
    echo "❌ Failed - no response"
fi
