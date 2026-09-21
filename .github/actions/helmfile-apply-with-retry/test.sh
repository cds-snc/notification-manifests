#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/.github/actions/helmfile-apply-with-retry/retry.sh"

run_case() {
  local scenario=$1
  local expected_status=$2
  local expected_calls=$3
  local helmfile_directory=${4:-helmfile}
  local create_directory=${5:-yes}

  local temp_dir
  temp_dir=$(mktemp -d)
  mkdir -p "$temp_dir/bin"
  if [ "$create_directory" = "yes" ]; then
    mkdir -p "$temp_dir/$helmfile_directory"
  fi

  cat > "$temp_dir/bin/helmfile" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

count=$(cat "$CALL_COUNT_FILE")
count=$((count + 1))
printf '%s' "$count" > "$CALL_COUNT_FILE"

case "$TEST_SCENARIO" in
  retry_then_success)
    if [ "$count" -eq 1 ]; then
      cat <<'LOG'
Error: Failed to render chart: exit status 1:
Error: failed to fetch https://example.invalid/metrics-server-3.14.0.tgz : 504 Gateway Timeout
Error: plugin "diff" exited with error
LOG
      exit 1
    fi
    echo "apply succeeded"
    ;;
  lowercase_fetch_timeout)
    if [ "$count" -eq 1 ]; then
      echo 'failed to fetch https://example.invalid/metrics-server-3.14.0.tgz : i/o timeout'
      exit 1
    fi
    echo "apply succeeded"
    ;;
  deterministic_failure)
    echo 'Error: release failed: rendered manifests contain a resource that already exists'
    exit 1
    ;;
  *)
    echo "unknown scenario: $TEST_SCENARIO" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$temp_dir/bin/helmfile"

  printf '0' > "$temp_dir/call-count"

  local status=0
  (
    cd "$temp_dir"
    export PATH="$temp_dir/bin:$PATH"
    export CALL_COUNT_FILE="$temp_dir/call-count"
    export TEST_SCENARIO="$scenario"
    export HELMFILE_ENVIRONMENT=staging
    export HELMFILE_SELECTOR='app!=notify-database,tier!=crd'
    export HELMFILE_DIRECTORY="$helmfile_directory"
    export RETRY_ATTEMPTS=2
    export RETRY_DELAY_SECONDS=0
    bash "$SCRIPT_UNDER_TEST"
  ) || status=$?

  if [ "$status" -ne "$expected_status" ]; then
    echo "scenario '$scenario' exited with $status, expected $expected_status" >&2
    rm -rf "$temp_dir"
    exit 1
  fi

  local calls
  calls=$(cat "$temp_dir/call-count")
  if [ "$calls" -ne "$expected_calls" ]; then
    echo "scenario '$scenario' ran helmfile $calls times, expected $expected_calls" >&2
    rm -rf "$temp_dir"
    exit 1
  fi

  rm -rf "$temp_dir"
}

run_case retry_then_success 0 2
run_case lowercase_fetch_timeout 0 2
run_case deterministic_failure 1 1
run_case retry_then_success 0 2 custom-helmfile
run_case retry_then_success 1 0 missing-helmfile no

echo "helmfile apply retry tests passed"
