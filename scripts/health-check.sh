#!/bin/bash
# Health check for ComfyUI API endpoints
# Usage: bash scripts/health-check.sh <base-url> [timeout]

set -e

BASE_URL="${1:-http://localhost:3001}"
TIMEOUT="${2:-5}"

if [ -z "$BASE_URL" ]; then
    echo "Usage: bash scripts/health-check.sh <base-url> [timeout]"
    echo "Example: bash scripts/health-check.sh http://localhost:3001"
    exit 1
fi

# Remove trailing slash
BASE_URL="${BASE_URL%/}"

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo "Error: curl command not found"
    exit 1
fi

check_endpoint() {
    local endpoint="$1"
    local name="$2"
    local url="${BASE_URL}${endpoint}"
    
    echo -n "Checking $name ($url)... "
    
    if response=$(curl -s -w "\n%{http_code}" --max-time "$TIMEOUT" "$url" 2>&1); then
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" = "200" ]; then
            echo "✓ OK (HTTP $http_code)"
            return 0
        else
            echo "✗ FAILED (HTTP $http_code)"
            echo "  Response: $body"
            return 1
        fi
    else
        echo "✗ FAILED (connection error)"
        return 1
    fi
}

echo "Health check for: $BASE_URL"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Check health endpoint
if ! check_endpoint "/health" "Health"; then
    exit 1
fi

# Check ready endpoint
if ! check_endpoint "/ready" "Readiness"; then
    exit 1
fi

echo ""
echo "All checks passed ✓"
