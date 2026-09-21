#!/usr/bin/env bash
set -euo pipefail

retry_pattern='((Error:|error:).*(Failed to|failed to).*(fetch|Fetch)|failed to .*fetch) .*((504 )?Gateway Timeout|(504 )?gateway timeout|TLS handshake timeout|tls handshake timeout|connection reset by peer|i/o timeout)'

helmfile_directory="${HELMFILE_DIRECTORY:-helmfile}"

is_retryable_failure() {
  local log_file=$1
  local flattened_log
  flattened_log=$(mktemp)
  tr '\n' ' ' < "$log_file" > "$flattened_log"
  if grep -Eq "$retry_pattern" "$flattened_log"; then
    rm -f "$flattened_log"
    return 0
  fi
  rm -f "$flattened_log"
  return 1
}

if [ ! -d "$helmfile_directory" ]; then
  echo "Helmfile directory not found: $helmfile_directory" >&2
  exit 1
fi

pushd "$helmfile_directory" >/dev/null

attempt=1
while true; do
  log_file=$(mktemp)
  log_pipe=$(mktemp -u)
  mkfifo "$log_pipe"
  tee "$log_file" < "$log_pipe" &
  tee_pid=$!
  set +e
  helmfile --environment "$HELMFILE_ENVIRONMENT" -l "$HELMFILE_SELECTOR" apply >"$log_pipe" 2>&1
  status=$?
  set -e
  wait "$tee_pid"
  rm -f "$log_pipe"

  if [ "$status" -eq 0 ]; then
    rm -f "$log_file"
    break
  elif is_retryable_failure "$log_file" && [ "$attempt" -lt "$RETRY_ATTEMPTS" ]; then
    should_retry=1
    attempt=$((attempt + 1))
  else
    should_retry=0
  fi

  rm -f "$log_file"

  if [ "$should_retry" -eq 1 ]; then
    echo "Helmfile command failed, retrying in ${RETRY_DELAY_SECONDS} seconds (attempt ${attempt}/${RETRY_ATTEMPTS})..."
    sleep "$RETRY_DELAY_SECONDS"
    continue
  fi

  popd >/dev/null
  exit "$status"
done

popd >/dev/null
