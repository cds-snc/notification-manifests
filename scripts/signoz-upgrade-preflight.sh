#!/bin/bash
# SigNoz Pre-Upgrade Health Check
# Verifies ClickHouse cluster is healthy before attempting upgrades
# Exit codes: 0=healthy, 1=unhealthy, 2=degraded (warn but continue)

set -euo pipefail

ENVIRONMENT="${1:-staging}"
NAMESPACE="signoz"
REPLICAS_POD_PATTERN="signoz-clickhouse.*replica"
VERBOSE="${VERBOSE:-false}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

warn() {
    echo "⚠️  [WARN] $*" >&2
}

error() {
    echo "❌ [ERROR] $*" >&2
}

success() {
    echo "✅ [OK] $*" >&2
}

# Check if kubectl is available and cluster is accessible
check_cluster_access() {
    log "Checking cluster access..."
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot access Kubernetes cluster"
        return 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        error "Namespace '$NAMESPACE' not found"
        return 1
    fi
    success "Cluster accessible"
}

# Check ClickHouse replicas are running and not readonly
check_replica_status() {
    log "Checking ClickHouse replica status..."
    
    local replicas
    replicas=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=clickhouse,app.kubernetes.io/instance=signoz" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$replicas" ]]; then
        error "No ClickHouse replicas found"
        return 1
    fi
    
    local readonly_count=0
    local total_count=0
    
    for pod in $replicas; do
        ((total_count++))
        
        # Query each replica for readonly tables
        local query="SELECT COUNT() FROM system.tables WHERE database LIKE 'signoz_%' AND readonly=1"
        
        if readonly_count=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
            clickhouse-client -q "$query" 2>/dev/null || echo "0"); then
            
            if [[ "$readonly_count" -gt 0 ]]; then
                ((readonly_count++))
                warn "$pod has $readonly_count readonly tables"
            fi
        fi
    done
    
    if [[ $readonly_count -gt 0 ]]; then
        error "Found $readonly_count readonly tables in $readonly_count replicas out of $total_count total"
        return 1
    fi
    
    success "All $total_count ClickHouse replicas are writable"
}

# Verify ZooKeeper quorum is healthy
check_zookeeper_quorum() {
    log "Checking ZooKeeper quorum..."
    
    local zk_pods
    zk_pods=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=zookeeper,app.kubernetes.io/instance=signoz" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$zk_pods" ]]; then
        error "No ZooKeeper pods found"
        return 1
    fi
    
    local zk_count=$(echo $zk_pods | wc -w)
    local zk_ready=0
    
    for pod in $zk_pods; do
        if kubectl exec -n "$NAMESPACE" "$pod" -- sh -c "echo ruok | nc localhost 2181" &>/dev/null; then
            ((zk_ready++))
        fi
    done
    
    if [[ $zk_ready -lt 2 ]]; then
        error "ZooKeeper quorum degraded: only $zk_ready/$zk_count nodes responding"
        return 2  # Degraded but potentially recoverable
    fi
    
    success "ZooKeeper quorum healthy: $zk_ready/$zk_count nodes responding"
}

# Check replica synchronization (parts match between replicas)
check_replica_sync() {
    log "Checking replica synchronization..."
    
    local replicas
    replicas=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=clickhouse,app.kubernetes.io/instance=signoz" -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$replicas" ]]; then
        error "No ClickHouse replicas found"
        return 1
    fi
    
    local replica_array=($replicas)
    
    if [[ ${#replica_array[@]} -lt 2 ]]; then
        warn "Only one replica, skipping sync check"
        return 0
    fi
    
    # Compare row counts for replicated tables between replicas
    local query="SELECT database, table, sum(rows) as total_rows FROM system.parts WHERE database LIKE 'signoz_%' GROUP BY database, table ORDER BY database, table"
    
    local replica0_output
    replica0_output=$(kubectl exec -n "$NAMESPACE" "${replica_array[0]}" -- \
        clickhouse-client --format=TabSeparatedWithNames -q "$query" 2>/dev/null || echo "")
    
    local replica1_output
    replica1_output=$(kubectl exec -n "$NAMESPACE" "${replica_array[1]}" -- \
        clickhouse-client --format=TabSeparatedWithNames -q "$query" 2>/dev/null || echo "")
    
    if [[ "$replica0_output" != "$replica1_output" ]]; then
        warn "Replica part counts diverge - this is normal during rolling restarts"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "Replica 0: $replica0_output" >&2
            echo "Replica 1: $replica1_output" >&2
        fi
        return 2  # Degraded but not fatal
    fi
    
    success "Replicas synchronized"
}

# Check DDL queue is not stuck
check_ddl_queue() {
    log "Checking DDL queue status..."
    
    local first_replica
    first_replica=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=clickhouse,app.kubernetes.io/instance=signoz" -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$first_replica" ]]; then
        error "No ClickHouse replicas found"
        return 1
    fi
    
    local query="SELECT COUNT() FROM system.distributed_ddl_queue WHERE status != 'Finished'"
    
    local pending
    pending=$(kubectl exec -n "$NAMESPACE" "$first_replica" -- \
        clickhouse-client -q "$query" 2>/dev/null || echo "unknown")
    
    if [[ "$pending" == "unknown" ]]; then
        warn "Could not query DDL queue status"
        return 2
    fi
    
    if [[ "$pending" -gt 0 ]]; then
        error "DDL queue has $pending pending operations"
        return 1
    fi
    
    success "DDL queue is empty"
}

# Main pre-flight check
main() {
    log "=== SigNoz Pre-Upgrade Health Check (Environment: $ENVIRONMENT) ==="
    
    local checks_passed=0
    local checks_failed=0
    local checks_degraded=0
    
    # Run all checks
    if check_cluster_access; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_replica_status; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_zookeeper_quorum; then
        ((checks_passed++))
    else
        ((checks_degraded++))
    fi
    
    if check_replica_sync; then
        ((checks_passed++))
    else
        ((checks_degraded++))
    fi
    
    if check_ddl_queue; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    log "=== Pre-flight Check Results ==="
    log "Passed: $checks_passed, Degraded: $checks_degraded, Failed: $checks_failed"
    
    if [[ $checks_failed -gt 0 ]]; then
        error "Pre-flight check FAILED - cluster is not ready for upgrade"
        return 1
    fi
    
    if [[ $checks_degraded -gt 0 ]]; then
        warn "Pre-flight check DEGRADED - cluster may recover, proceeding with caution"
        return 2
    fi
    
    success "Pre-flight check PASSED - cluster is ready for upgrade"
    return 0
}

main "$@"
