#!/bin/sh
set -eu

echo "[dummy-maintenance-c] start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[dummy-maintenance-c] env: ${NOTIFY_ENVIRONMENT:-unset}"
echo "[dummy-maintenance-c] reports-bucket: ${REPORTS_BUCKET_NAME:-unset}"
echo "[dummy-maintenance-c] done"
