#!/bin/sh

set -eu

SIGNOZ_URL="${SIGNOZ_URL:-http://signoz:8080}"
SIGNOZ_API_KEY="${SIGNOZ_API_KEY:-}"
PIPELINES_FILE="${PIPELINES_FILE:-/pipelines/pipelines.json}"

if [ -z "$SIGNOZ_API_KEY" ]; then
  echo "ERROR: SIGNOZ_API_KEY is required"
  exit 1
fi

if [ ! -f "$PIPELINES_FILE" ]; then
  echo "ERROR: pipelines file not found: $PIPELINES_FILE"
  exit 1
fi

tmp_pipelines="$(mktemp)"
tmp_payload="$(mktemp)"
tmp_response="$(mktemp)"
trap 'rm -f "$tmp_pipelines" "$tmp_payload" "$tmp_response"' EXIT

# Normalize supported input shapes into an array of pipelines.
jq -c '
  if type == "array" then
    .
  elif (.data? and (.data | type) == "object") then
    if ((.data.history | type) == "array" and (.data.history | length) > 0) then
      (
        .data.history
        | max_by(.version)
        | .config
        | if type == "string" and length > 0 then (try fromjson catch []) else [] end
      )
    elif ((.data.pipelines | type) == "array") then
      .data.pipelines
    else
      []
    end
  elif ((.pipelines? | type) == "array") then
    .pipelines
  else
    []
  end
' "$PIPELINES_FILE" > "$tmp_pipelines"

count="$(jq -r 'length' "$tmp_pipelines")"
echo "Prepared $count pipeline(s) for import"

jq -c '{pipelines: .}' "$tmp_pipelines" > "$tmp_payload"

http_code="$(curl -s -o "$tmp_response" -w "%{http_code}" -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "SIGNOZ-API-KEY: $SIGNOZ_API_KEY" \
  -H "Authorization: Bearer $SIGNOZ_API_KEY" \
  --data-binary "@$tmp_payload" \
  "${SIGNOZ_URL%/}/api/v1/logs/pipelines")"

if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
  echo "Successfully imported pipelines (HTTP $http_code)"
else
  body="$(head -c 600 "$tmp_response" | tr '\n' ' ')"
  echo "ERROR: Failed to import pipelines (HTTP $http_code)"
  echo "Response: $body"
  exit 1
fi
