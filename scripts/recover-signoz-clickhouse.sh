#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-signoz}"
CLICKHOUSE_POD="${CLICKHOUSE_POD:-}"
ZOOKEEPER_HOST="${ZOOKEEPER_HOST:-signoz-zookeeper.signoz.svc.cluster.local}"
ZOOKEEPER_PORT="${ZOOKEEPER_PORT:-2181}"
COLLECTOR_DEPLOYMENT="${COLLECTOR_DEPLOYMENT:-signoz-otel-collector}"
DATABASE_FILTER="${DATABASE_FILTER:-signoz_%}"
SCALE_COLLECTOR="${SCALE_COLLECTOR:-true}"
RUN_SYNC="${RUN_SYNC:-true}"
DRY_RUN="${DRY_RUN:-false}"
RESTART_CLICKHOUSE="${RESTART_CLICKHOUSE:-true}"

usage() {
  cat <<'EOF'
Usage: recover-signoz-clickhouse.sh [options]

Automates SigNoz ClickHouse queue recovery after restore/replication drift:
1) (optional) scale collector down
2) stop replication queues for affected tables
3) remove stuck Keeper queue nodes
4) start queues
5) restart + sync affected replicas
6) (optional) scale collector back up
7) print final replica health

Options:
  -n, --namespace <ns>           Kubernetes namespace (default: signoz)
  -p, --pod <name>               ClickHouse pod to run commands in (auto-detect if unset)
  -z, --zookeeper-host <host>    ZooKeeper/Keeper host (default: signoz-zookeeper.signoz.svc.cluster.local)
      --zookeeper-port <port>    ZooKeeper/Keeper port (default: 2181)
  -c, --collector <deploy>       Collector deployment (default: signoz-otel-collector)
      --db-filter <pattern>      SQL LIKE pattern for databases (default: signoz_%)
      --no-scale-collector       Do not scale collector down/up
      --no-sync                  Skip SYSTEM SYNC REPLICA (restart only)
      --no-restart-clickhouse    Skip ClickHouse StatefulSet restart
      --dry-run                  Print actions without executing
  -h, --help                     Show help

Environment variables:
  NAMESPACE, CLICKHOUSE_POD, ZOOKEEPER_HOST, ZOOKEEPER_PORT, COLLECTOR_DEPLOYMENT,
  DATABASE_FILTER, SCALE_COLLECTOR, RUN_SYNC, RESTART_CLICKHOUSE, DRY_RUN
EOF
}

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf 'DRY_RUN: %s\n' "$*"
    return 0
  fi
  eval "$@"
}

sql_escape() {
  local input="$1"
  printf "%s" "$input" | sed "s/'/''/g"
}

find_clickhouse_pod() {
  if [[ -n "$CLICKHOUSE_POD" ]]; then
    return 0
  fi

  local pod
  pod="$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=clickhouse -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$pod" ]]; then
    echo "Unable to auto-detect ClickHouse pod in namespace '$NAMESPACE'." >&2
    echo "Pass --pod <name>." >&2
    exit 1
  fi
  CLICKHOUSE_POD="$pod"
}

ch_query() {
  local query="$1"
  kubectl -n "$NAMESPACE" exec "$CLICKHOUSE_POD" -- clickhouse-client -q "$query"
}

keeper_query() {
  local query="$1"
  kubectl -n "$NAMESPACE" exec "$CLICKHOUSE_POD" -- \
    clickhouse-keeper-client --host "$ZOOKEEPER_HOST" --port "$ZOOKEEPER_PORT" -q "$query"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      -p|--pod)
        CLICKHOUSE_POD="$2"
        shift 2
        ;;
      -z|--zookeeper-host)
        ZOOKEEPER_HOST="$2"
        shift 2
        ;;
      --zookeeper-port)
        ZOOKEEPER_PORT="$2"
        shift 2
        ;;
      -c|--collector)
        COLLECTOR_DEPLOYMENT="$2"
        shift 2
        ;;
      --db-filter)
        DATABASE_FILTER="$2"
        shift 2
        ;;
      --no-scale-collector)
        SCALE_COLLECTOR="false"
        shift
        ;;
      --no-sync)
        RUN_SYNC="false"
        shift
        ;;
      --no-restart-clickhouse)
        RESTART_CLICKHOUSE="false"
        shift
        ;;
      --dry-run)
        DRY_RUN="true"
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

main() {
  parse_args "$@"
  find_clickhouse_pod

  log "Using namespace=$NAMESPACE pod=$CLICKHOUSE_POD zookeeper=$ZOOKEEPER_HOST:$ZOOKEEPER_PORT db_filter=$DATABASE_FILTER"

  local collector_replicas=""
  if [[ "$SCALE_COLLECTOR" == "true" ]]; then
    collector_replicas="$(kubectl -n "$NAMESPACE" get deploy "$COLLECTOR_DEPLOYMENT" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
    if [[ -n "$collector_replicas" ]]; then
      log "Scaling $COLLECTOR_DEPLOYMENT to 0 (was $collector_replicas)"
      run "kubectl -n '$NAMESPACE' scale deploy '$COLLECTOR_DEPLOYMENT' --replicas=0"
    else
      log "Collector deployment $COLLECTOR_DEPLOYMENT not found, continuing"
    fi
  fi

  if [[ "$RESTART_CLICKHOUSE" == "true" ]]; then
    log "Restarting ClickHouse StatefulSets"
    local sts_names=()
    while IFS= read -r line; do
      [[ -n "$line" ]] && sts_names+=("$line")
    done < <(kubectl -n "$NAMESPACE" get statefulset -l app.kubernetes.io/component=clickhouse -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

    if [[ "${#sts_names[@]}" -eq 0 ]]; then
      log "No ClickHouse StatefulSets found with label app.kubernetes.io/component=clickhouse"
    else
      for sts in "${sts_names[@]}"; do
        run "kubectl -n '$NAMESPACE' rollout restart statefulset '$sts'"
      done
      for sts in "${sts_names[@]}"; do
        run "kubectl -n '$NAMESPACE' rollout status statefulset '$sts' --timeout=10m"
      done
    fi
  fi

  local escaped_filter
  escaped_filter="$(sql_escape "$DATABASE_FILTER")"

  log "Discovering affected replicated tables"
  local affected_tables=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && affected_tables+=("$line")
  done < <(ch_query "
SELECT DISTINCT concat(database, '.', table)
FROM system.replicas
WHERE database LIKE '${escaped_filter}'
  AND (queue_size > 0 OR absolute_delay > 0 OR is_readonly = 1 OR last_queue_update_exception != '')
FORMAT TSVRaw")

  if [[ "${#affected_tables[@]}" -eq 0 ]]; then
    log "No affected tables found. Printing replica status:"
    ch_query "
SELECT database, table, queue_size, absolute_delay, is_readonly, last_queue_update_exception
FROM system.replicas
WHERE database LIKE '${escaped_filter}'
ORDER BY queue_size DESC, absolute_delay DESC"
    exit 0
  fi

  log "Affected tables (${#affected_tables[@]}): ${affected_tables[*]}"

  log "Stopping replication queues for affected tables"
  for table in "${affected_tables[@]}"; do
    run "ch_query \"SYSTEM STOP REPLICATION QUEUES $table\""
  done

  log "Collecting queue nodes to remove"
  local queue_paths=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && queue_paths+=("$line")
  done < <(ch_query "
SELECT concat(r.zookeeper_path, '/replicas/', r.replica_name, '/queue/', q.node_name)
FROM system.replication_queue q
INNER JOIN system.replicas r
  ON q.database = r.database AND q.table = r.table
WHERE q.database LIKE '${escaped_filter}'
FORMAT TSVRaw")

  if [[ "${#queue_paths[@]}" -eq 0 ]]; then
    log "No queue nodes found to remove"
  else
    log "Removing queue nodes (${#queue_paths[@]})"
    for path in "${queue_paths[@]}"; do
      local escaped_path
      escaped_path="$(sql_escape "$path")"
      run "keeper_query \"rm '${escaped_path}'\""
    done
  fi

  log "Starting replication queues for affected tables"
  for table in "${affected_tables[@]}"; do
    run "ch_query \"SYSTEM START REPLICATION QUEUES $table\""
  done

  log "Restarting replicas for affected tables"
  for table in "${affected_tables[@]}"; do
    run "ch_query \"SYSTEM RESTART REPLICA $table\""
  done

  if [[ "$RUN_SYNC" == "true" ]]; then
    log "Syncing replicas for affected tables (this may take time)"
    for table in "${affected_tables[@]}"; do
      run "ch_query \"SYSTEM SYNC REPLICA $table\""
    done
  fi

  if [[ "$SCALE_COLLECTOR" == "true" && -n "$collector_replicas" ]]; then
    log "Scaling $COLLECTOR_DEPLOYMENT back to $collector_replicas"
    run "kubectl -n '$NAMESPACE' scale deploy '$COLLECTOR_DEPLOYMENT' --replicas=$collector_replicas"
  fi

  log "Final replica status"
  ch_query "
SELECT database, table, queue_size, absolute_delay, is_readonly, last_queue_update_exception
FROM system.replicas
WHERE database LIKE '${escaped_filter}'
ORDER BY queue_size DESC, absolute_delay DESC"
}

main "$@"
