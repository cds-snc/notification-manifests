#!/bin/sh

set -eu

SIGNOZ_URL="${SIGNOZ_URL:-http://signoz:8080}"
SIGNOZ_API_KEY="${SIGNOZ_API_KEY:-}"
DASHBOARDS_ROOT="${DASHBOARDS_ROOT:-/dashboards}"

if [ -z "$SIGNOZ_API_KEY" ]; then
  echo "ERROR: SIGNOZ_API_KEY is required"
  exit 1
fi

found_any="false"
failed_count=0

for dashboard_file in "$DASHBOARDS_ROOT"/*/dashboard.json; do
  if [ ! -f "$dashboard_file" ]; then
    continue
  fi

  found_any="true"
  dashboard_name="$(basename "$(dirname "$dashboard_file")")"
  echo "Importing dashboard: $dashboard_name"

  dashboard_uuid="$(jq -r '.uuid // empty' "$dashboard_file")"
  if [ -z "$dashboard_uuid" ] || [ "$dashboard_uuid" = "null" ]; then
    echo "✗ Skipping dashboard '$dashboard_name': missing uuid in JSON"
    failed_count=$((failed_count + 1))
    continue
  fi
  echo "Dashboard UUID: $dashboard_uuid"

  all_dashboards="$(curl -s \
    -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
    "${SIGNOZ_URL%/}/api/v1/dashboards")"

  dashboard_id="$(echo "$all_dashboards" | jq -r --arg uuid "$dashboard_uuid" \
    '.data[]? | select(.data.uuid == $uuid) | .id' | head -n1)"

  if [ -n "$dashboard_id" ]; then
    echo "Dashboard already exists (ID: $dashboard_id) - updating..."
    response="$(curl -s -w "\n%{http_code}" -X PUT \
      -H "Content-Type: application/json" \
      -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
      --data-binary "@$dashboard_file" \
      "${SIGNOZ_URL%/}/api/v1/dashboards/$dashboard_id")"
  else
    echo "Dashboard does not exist - creating..."
    response="$(curl -s -w "\n%{http_code}" -X POST \
      -H "Content-Type: application/json" \
      -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
      --data-binary "@$dashboard_file" \
      "${SIGNOZ_URL%/}/api/v1/dashboards")"
  fi

  http_code="$(echo "$response" | tail -n1)"
  body="$(echo "$response" | sed '$d')"

  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "✓ Successfully imported dashboard: $dashboard_name"
  else
    echo "✗ Failed to import dashboard: $dashboard_name (HTTP $http_code)"
    if [ -n "$body" ]; then
      echo "Response: $body"
    fi
    failed_count=$((failed_count + 1))
  fi
done

if [ "$found_any" != "true" ]; then
  echo "No dashboards found under $DASHBOARDS_ROOT"
fi

echo "Dashboard import complete (failures: $failed_count)"
