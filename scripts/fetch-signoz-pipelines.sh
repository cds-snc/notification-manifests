#!/usr/bin/env bash

set -euo pipefail

SIGNOZ_URL="${SIGNOZ_URL:-http://localhost:8080}"
SIGNOZ_API_KEY="${SIGNOZ_API_KEY:-}"
PIPELINE_VERSION="${PIPELINE_VERSION:-}"
OUTPUT_FILE=""
INSECURE_TLS="${INSECURE_TLS:-false}"

usage() {
  cat <<'EOF'
Fetch all SigNoz log pipelines and save them as JSON.

Usage:
  fetch-signoz-pipelines.sh [options]

Options:
  -u, --url <url>         SigNoz base URL (default: SIGNOZ_URL or http://localhost:8080)
  -k, --api-key <key>     SigNoz API key (default: SIGNOZ_API_KEY)
  -v, --version <value>   Pipeline API version number (for example: 0, 1, 2)
  -o, --output <path>     Output file path (default: ./signoz-pipelines-<timestamp>.json)
      --insecure          Allow insecure TLS (curl -k)
  -h, --help              Show help

Environment variables:
  SIGNOZ_URL
  SIGNOZ_API_KEY
  PIPELINE_VERSION
  INSECURE_TLS
EOF
}

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--url)
        SIGNOZ_URL="$2"
        shift 2
        ;;
      -k|--api-key)
        SIGNOZ_API_KEY="$2"
        shift 2
        ;;
      -v|--version)
        PIPELINE_VERSION="$2"
        shift 2
        ;;
      -o|--output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --insecure)
        INSECURE_TLS="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

fetch_with_version() {
  local version="$1"
  local body_file="$2"
  local status_file="$3"
  local url

  if [[ -n "$version" ]]; then
    url="${SIGNOZ_URL%/}/api/v1/logs/pipelines/${version}"
  else
    url="${SIGNOZ_URL%/}/api/v1/logs/pipelines"
  fi

  local -a curl_args=(
    -sS
    -o "$body_file"
    -w "%{http_code}"
    -H "SIGNOZ-API-KEY: ${SIGNOZ_API_KEY}"
    -H "Authorization: Bearer ${SIGNOZ_API_KEY}"
    "$url"
  )

  if [[ "$INSECURE_TLS" == "true" ]]; then
    curl_args=(-k "${curl_args[@]}")
  fi

  local http_code
  http_code="$(curl "${curl_args[@]}" || true)"
  printf '%s' "$http_code" > "$status_file"

  [[ "$http_code" =~ ^2[0-9][0-9]$ ]]
}

extract_latest_revision() {
  local body_file="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  jq -r '
    if (.data.history | type == "array" and (.data.history | length) > 0) then
      (.data.history | map(.version) | max)
    elif (.data.version != null) then
      .data.version
    else
      empty
    end
  ' "$body_file" 2>/dev/null || true
}

materialize_effective_pipelines() {
  local body_file="$1"
  local out_file="$2"

  if ! command -v jq >/dev/null 2>&1; then
    cp "$body_file" "$out_file"
    return 0
  fi

  jq '
    . as $input
    | (
        if ($input | type) == "array" then
          {
            status: "success",
            data: {
              version: null,
              pipelines: $input,
              history: [],
              latestHistoryVersion: null
            }
          }
        else
          $input
        end
      ) as $root
    | (
        if ($root.data.history | type == "array" and ($root.data.history | length) > 0)
        then ($root.data.history | max_by(.version))
        else null
        end
      ) as $latest
    | if (
        $latest != null and
        ($latest.config | type) == "string" and
        (($latest.config | length) > 0)
      ) then
        $root
        | .data.pipelines = (try ($latest.config | fromjson) catch .data.pipelines)
        | .data.latestHistoryVersion = ($latest.version // .data.version)
      else
        $root
      end
  ' "$body_file" > "$out_file"
}

main() {
  parse_args "$@"

  if [[ -z "$SIGNOZ_API_KEY" ]]; then
    echo "Error: SIGNOZ_API_KEY is required" >&2
    echo "Usage: SIGNOZ_API_KEY=your-key $0 [--output pipelines.json]" >&2
    exit 1
  fi

  # Accept v-prefixed values like "v1" and normalize to "1".
  if [[ "$PIPELINE_VERSION" =~ ^v([0-9]+)$ ]]; then
    PIPELINE_VERSION="${BASH_REMATCH[1]}"
  fi

  if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="./signoz-pipelines-$(date +'%Y%m%d-%H%M%S').json"
  fi

  local output_dir
  output_dir="$(dirname "$OUTPUT_FILE")"
  mkdir -p "$output_dir"

  tmp_body=""
  tmp_body="$(mktemp)"
  tmp_status=""
  tmp_status="$(mktemp)"
  trap 'rm -f "$tmp_body" "$tmp_status"' EXIT

  local selected_version=""
  local -a candidates=()

  if [[ -n "$PIPELINE_VERSION" ]]; then
    candidates=("$PIPELINE_VERSION")
  else
    candidates=("1" "0" "2" "3" "4" "5" "")
  fi

  for version in "${candidates[@]}"; do
    if [[ -n "$version" ]]; then
      log "Trying /api/v1/logs/pipelines/$version"
    else
      log "Trying /api/v1/logs/pipelines"
    fi

    if fetch_with_version "$version" "$tmp_body" "$tmp_status"; then
      selected_version="$version"
      break
    fi

    local code snippet
    code="$(cat "$tmp_status")"
    snippet="$(head -c 400 "$tmp_body" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    if [[ -z "$snippet" ]]; then
      snippet="<empty response body>"
    fi
    log "Failed endpoint (HTTP $code): $snippet"
  done

  if [[ -z "$selected_version" && -n "$PIPELINE_VERSION" ]]; then
    echo "Error: failed to fetch pipelines using version '$PIPELINE_VERSION'" >&2
    exit 1
  fi

  if [[ -z "$selected_version" && -z "$PIPELINE_VERSION" ]]; then
    echo "Error: failed to fetch pipelines using known endpoints" >&2
    exit 1
  fi

  # If caller did not pin a version, promote to the latest revision listed in history.
  if [[ -z "$PIPELINE_VERSION" && -n "$selected_version" ]]; then
    latest_revision="$(extract_latest_revision "$tmp_body")"
    if [[ -n "${latest_revision:-}" && "$latest_revision" != "$selected_version" ]]; then
      log "Latest pipeline revision appears to be '$latest_revision' (initial fetch was '$selected_version'); refetching"
      if fetch_with_version "$latest_revision" "$tmp_body" "$tmp_status"; then
        selected_version="$latest_revision"
      else
        code="$(cat "$tmp_status")"
        snippet="$(head -c 400 "$tmp_body" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
        if [[ -z "$snippet" ]]; then
          snippet="<empty response body>"
        fi
        log "Refetch of latest revision failed (HTTP $code): $snippet"
      fi
    fi
  fi

  if command -v jq >/dev/null 2>&1; then
    tmp_processed="$(mktemp)"
    trap 'rm -f "$tmp_body" "$tmp_status" "$tmp_processed"' EXIT
    materialize_effective_pipelines "$tmp_body" "$tmp_processed"
    jq . "$tmp_processed" > "$OUTPUT_FILE"

    pipelines_count="$(jq -r '.data.pipelines | length' "$OUTPUT_FILE" 2>/dev/null || echo "?")"
    latest_history_version="$(jq -r '.data.latestHistoryVersion // empty' "$OUTPUT_FILE" 2>/dev/null || true)"
    if [[ -n "$latest_history_version" ]]; then
      log "Materialized pipelines from latest history version '$latest_history_version' (count: $pipelines_count)"
    else
      log "Saved pipelines count: $pipelines_count"
    fi
  else
    cp "$tmp_body" "$OUTPUT_FILE"
  fi

  if [[ -n "$selected_version" ]]; then
    log "Fetched pipelines using version '$selected_version'"
  else
    log "Fetched pipelines using unversioned endpoint"
  fi
  log "Saved pipelines to $OUTPUT_FILE"
}

main "$@"
