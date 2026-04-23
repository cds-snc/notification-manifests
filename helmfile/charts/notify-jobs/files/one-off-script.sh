#!/bin/sh
set -eu

echo "[one-off] start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[one-off] host: ${HOSTNAME:-unknown}"
echo "[one-off] env NOTIFY_ENVIRONMENT=${NOTIFY_ENVIRONMENT:-unset}"
echo "[one-off] env API_HOST_NAME=${API_HOST_NAME:-unset}"
echo "[one-off] env AWS_REGION=${AWS_REGION:-unset}"
echo "[one-off] env REDIS_ENABLED=${REDIS_ENABLED:-unset}"
echo "[one-off] env FF_ENABLE_OTEL=${FF_ENABLE_OTEL:-unset}"

for required_secret in SQLALCHEMY_DATABASE_URI SECRET_KEY ADMIN_CLIENT_SECRET REDIS_URL; do
  eval "secret_value=\${$required_secret:-}"
  if [ -n "${secret_value}" ]; then
    echo "[one-off] secret ${required_secret} is set"
  else
    echo "[one-off] secret ${required_secret} is MISSING"
  fi
done

sleep_seconds="${DUMMY_SLEEP_SECONDS:-120}"
heartbeat=30
elapsed=0

echo "[one-off] simulating long-running work for ${sleep_seconds}s"
while [ "${elapsed}" -lt "${sleep_seconds}" ]; do
  remaining=$((sleep_seconds - elapsed))
  echo "[one-off] heartbeat elapsed=${elapsed}s remaining=${remaining}s"
  if [ "${remaining}" -lt "${heartbeat}" ]; then
    sleep "${remaining}"
    elapsed="${sleep_seconds}"
  else
    sleep "${heartbeat}"
    elapsed=$((elapsed + heartbeat))
  fi
done

echo "[one-off] complete: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
