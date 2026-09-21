#!/usr/bin/env bash
set -euo pipefail

retry_pattern='((Error:|error:).*(Failed to|failed to).*(fetch|Fetch)|failed to .*fetch) .*((504 )?Gateway Timeout|(504 )?gateway timeout|TLS handshake timeout|tls handshake timeout|connection reset by peer|i/o timeout)'

helmfile_directory="${HELMFILE_DIRECTORY:-helmfile}"

pushd "$helmfile_directory" >/dev/null

attempt=1
while true; do
  log_file=$(mktemp)
  set +e
  helmfile --environment "$HELMFILE_ENVIRONMENT" -l "$HELMFILE_SELECTOR" apply >"$log_file" 2>&1
  status=$?
  set -e
  cat "$log_file"

  if [ "$status" -eq 0 ]; then
    rm -f "$log_file"
    break
  elif tr '\n' ' ' < "$log_file" | grep -Eq "$retry_pattern" && [ "$attempt" -lt "$RETRY_ATTEMPTS" ]; then
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
