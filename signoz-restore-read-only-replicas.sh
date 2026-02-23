#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-signoz}"
POD="${POD:-chi-signoz-clickhouse-cluster-0-1-0}"
DATABASE_FILTER="${DATABASE_FILTER:-signoz_metrics}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-6}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3}"

usage() {
  cat <<'EOF'
Usage: restore-readonly-replicas.sh [options]

Finds read-only replicated ClickHouse tables and runs:
  SYSTEM RESTART REPLICA db.table
  SYSTEM RESTORE REPLICA db.table
with retries to handle transient KEEPER session-expired errors.

Options:
  -n, --namespace <ns>       Kubernetes namespace (default: signoz)
  -p, --pod <pod>            ClickHouse pod name
                             (default: chi-signoz-clickhouse-cluster-0-1-0)
  -d, --database <name>      Database to target (default: signoz_metrics)
  -a, --attempts <num>       Max retry attempts per table (default: 6)
  -s, --sleep <seconds>      Sleep between attempts (default: 3)
  -h, --help                 Show this help

Environment overrides:
  NAMESPACE, POD, DATABASE_FILTER, MAX_ATTEMPTS, SLEEP_SECONDS
EOF
}

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

ch() {
  local q="$1"
  kubectl -n "$NAMESPACE" exec "$POD" -- clickhouse-client -q "$q"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      -p|--pod)
        POD="$2"
        shift 2
        ;;
      -d|--database)
        DATABASE_FILTER="$2"
        shift 2
        ;;
      -a|--attempts)
        MAX_ATTEMPTS="$2"
        shift 2
        ;;
      -s|--sleep)
        SLEEP_SECONDS="$2"
        shift 2
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

restore_table() {
  local db="$1"
  local table="$2"
  local fqtn="${db}.${table}"
  local attempt=1

  while (( attempt <= MAX_ATTEMPTS )); do
    log "[$fqtn] attempt $attempt/$MAX_ATTEMPTS"

    # Re-establish keeper session for the replica before restore.
    if ! ch "SYSTEM RESTART REPLICA ${fqtn}" >/dev/null 2>&1; then
      log "[$fqtn] restart replica returned non-zero; retrying"
      sleep "$SLEEP_SECONDS"
      ((attempt++))
      continue
    fi

    if ch "SYSTEM RESTORE REPLICA ${fqtn}" >/dev/null 2>&1; then
      local ro
      ro="$(ch "SELECT is_readonly FROM system.replicas WHERE database='${db}' AND table='${table}' FORMAT TSVRaw" | head -n1 || true)"
      if [[ "$ro" == "0" ]]; then
        log "[$fqtn] restored successfully"
        return 0
      fi
      log "[$fqtn] restore command succeeded but table is still read-only"
    else
      log "[$fqtn] restore failed (likely transient keeper/session); retrying"
    fi

    sleep "$SLEEP_SECONDS"
    ((attempt++))
  done

  log "[$fqtn] FAILED after $MAX_ATTEMPTS attempts"
  return 1
}

main() {
  parse_args "$@"

  log "Namespace=$NAMESPACE Pod=$POD Database=$DATABASE_FILTER"
  log "Collecting read-only tables..."

  tables=()
  while IFS= read -r row; do
    [[ -n "$row" ]] && tables+=("$row")
  done < <(ch "
SELECT database, table
FROM system.replicas
WHERE database='${DATABASE_FILTER}' AND is_readonly=1
ORDER BY table
FORMAT TSVRaw")

  if [[ "${#tables[@]}" -eq 0 ]]; then
    log "No read-only tables found in database '${DATABASE_FILTER}'"
    exit 0
  fi

  log "Found ${#tables[@]} read-only tables"
  local failed=0
  for row in "${tables[@]}"; do
    db="${row%%$'\t'*}"
    table="${row#*$'\t'}"
    if ! restore_table "$db" "$table"; then
      ((failed++))
    fi
  done

  log "Final read-only state:"
  ch "
SELECT database, table, is_readonly
FROM system.replicas
WHERE database='${DATABASE_FILTER}'
ORDER BY table"

  if (( failed > 0 )); then
    log "$failed table(s) still failed restore"
    exit 1
  fi
}

main "$@"
