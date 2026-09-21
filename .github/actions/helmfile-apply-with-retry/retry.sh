#!/usr/bin/env bash
set -euo pipefail

retry_pattern='((Error:|error:).*(Failed to|failed to).*(fetch|Fetch)|failed to .*fetch) .*((504 )?Gateway Timeout|(504 )?gateway timeout|TLS handshake timeout|tls handshake timeout|connection reset by peer|i/o timeout)'

pushd helmfile >/dev/null

attempt=1
while true; do
  log_file=$(mktemp)
  set +e
  helmfile --environment "$HELMFILE_ENVIRONMENT" -l "$HELMFILE_SELECTOR" apply 2>&1 | tee "$log_file"
  status=${PIPESTATUS[0]}
  set -e

  if [ "$status" -eq 0 ]; then
    rm -f "$log_file"
    break
  fi

  if ! tr '\n' ' ' < "$log_file" | grep -Eq "$retry_pattern"; then
    rm -f "$log_file"
    popd >/dev/null
    exit "$status"
  fi

  if [ "$attempt" -ge "$RETRY_ATTEMPTS" ]; then
    rm -f "$log_file"
    popd >/dev/null
    exit "$status"
  fi

  attempt=$((attempt + 1))
  echo "Helmfile command failed, retrying in ${RETRY_DELAY_SECONDS} seconds (attempt ${attempt}/${RETRY_ATTEMPTS})..."
  sleep "$RETRY_DELAY_SECONDS"
  rm -f "$log_file"
done

popd >/dev/null
