#!/bin/bash

# Script to delete all SigNoz dashboards
# Usage: ./delete-signoz-dashboards.sh

# Configuration
SIGNOZ_URL="${SIGNOZ_URL:-http://localhost:8080}"
SIGNOZ_API_KEY="${SIGNOZ_API_KEY}"

if [ -z "$SIGNOZ_API_KEY" ]; then
  echo "Error: SIGNOZ_API_KEY environment variable is required"
  echo "Usage: SIGNOZ_API_KEY=your-key ./delete-signoz-dashboards.sh"
  exit 1
fi

echo "Fetching all dashboards from $SIGNOZ_URL..."

# Fetch all dashboards
response=$(curl -s -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" "$SIGNOZ_URL/api/v1/dashboards")

# Extract UUIDs using jq (handles various response structures)
# Use the id field which is the actual dashboard ID for deletion
uuids=$(echo "$response" | jq -r '.data[]?.id // empty' 2>/dev/null | sort -u)

if [ -z "$uuids" ]; then
  echo "No dashboards found or unable to parse response"
  exit 0
fi

# Count dashboards
count=$(echo "$uuids" | wc -l | tr -d ' ')
echo "Found $count dashboard(s) to delete"

# Delete each dashboard
echo ""
while IFS= read -r uuid; do
  if [ -n "$uuid" ]; then
    echo "Deleting dashboard: $uuid"
    
    # Show the full DELETE request URL
    delete_url="$SIGNOZ_URL/api/v1/dashboards/$uuid"
    echo "DELETE URL: $delete_url"
    
    delete_response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X DELETE \
      -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
      "$delete_url")
    
    http_code=$(echo "$delete_response" | grep "HTTP_CODE:" | cut -d':' -f2)
    body=$(echo "$delete_response" | sed '/HTTP_CODE:/d')
    
    echo "HTTP Code: $http_code"
    if [ -n "$body" ]; then
      echo "Response Body: $body"
    fi
    
    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
      echo "✓ Deleted successfully"
    else
      echo "✗ Failed to delete (HTTP $http_code)"
    fi
    echo ""
  fi
done <<< "$uuids"

echo "Dashboard deletion complete!"
