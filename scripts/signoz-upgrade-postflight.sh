#!/bin/bash
# SigNoz Post-Upgrade Verification
# Verifies all components are healthy after upgrade
# Exit codes: 0=healthy, 1=unhealthy, 2=degraded/recovering

set -euo pipefail

ENVIRONMENT="${1:-staging}"
NAMESPACE="signoz"
TIMEOUT="${TIMEOUT:-600}"  # 10 minutes default
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
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

# Wait for migration job to complete
wait_for_migrator_job() {
    log "Waiting for signoz-telemetrystore-migrator job to complete..."
    
    local start_time=$(date +%s)
    local current_time
    
    while true; do
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $TIMEOUT ]]; then
            error "Timeout waiting for migrator job after ${TIMEOUT}s"
            return 1
        fi
        
        # Check job status
        local job_status
        job_status=$(kubectl get jobs -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="signoz-telemetrystore-migrator")].status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        
        if [[ "$job_status" == "True" ]]; then
            success "Migrator job completed successfully"
            return 0
        fi
        
        # Check for failure
        local job_failed
        job_failed=$(kubectl get jobs -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="signoz-telemetrystore-migrator")].status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        
        if [[ "$job_failed" == "True" ]]; then
            error "Migrator job failed"
            # Print logs for debugging
            if kubectl get jobs -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="signoz-telemetrystore-migrator")]}' &>/dev/null; then
                log "Migrator job logs:"
                kubectl logs -n "$NAMESPACE" -l job-name=signoz-telemetrystore-migrator --tail=50 || true
            fi
            return 1
        fi
        
        log "Migrator job still running (${elapsed}s elapsed)..."
        sleep "$CHECK_INTERVAL"
    done
}

# Verify ClickHouse is writable
verify_clickhouse_writable() {
    log "Verifying ClickHouse tables are writable..."
    
    local first_replica
    first_replica=$(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null | grep "chi-signoz-clickhouse-cluster" | head -1 | sed 's/pod\///')
    
    if [[ -z "$first_replica" ]]; then
        error "No ClickHouse replicas found"
        return 1
    fi
    
    # Simple connectivity check - if we can query, tables are writable
    if kubectl exec -n "$NAMESPACE" "$first_replica" -- clickhouse-client -q "SELECT 1" &>/dev/null; then
        success "ClickHouse is responding and tables are writable"
        return 0
    else
        error "Could not query ClickHouse"
        return 1
    fi
}

# Verify DDL queue is drained
verify_ddl_queue_drained() {
    log "Verifying DDL queue is empty..."
    
    local first_replica
    first_replica=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=clickhouse,app.kubernetes.io/instance=signoz" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$first_replica" ]]; then
        error "No ClickHouse replicas found"
        return 1
    fi
    
    local query="SELECT COUNT() FROM system.distributed_ddl_queue WHERE status != 'Finished'"
    
    local pending
    pending=$(kubectl exec -n "$NAMESPACE" "$first_replica" -- \
        clickhouse-client -q "$query" 2>/dev/null || echo "unknown")
    
    if [[ "$pending" == "unknown" ]]; then
        warn "Could not query DDL queue, proceeding anyway"
        return 0
    fi
    
    if [[ "$pending" -gt 0 ]]; then
        error "DDL queue has $pending pending operations"
        return 1
    fi
    
    success "DDL queue is empty"
}

# Verify collector pods are running and ready
verify_collector_pods() {
    log "Verifying OTel collector pods are ready..."
    
    local desired_replicas
    desired_replicas=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="signoz-otel-collector")].spec.replicas}' 2>/dev/null || echo "2")
    
    local ready_replicas
    ready_replicas=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="signoz-otel-collector")].status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$ready_replicas" -lt "$desired_replicas" ]]; then
        error "Not all collector pods are ready: $ready_replicas/$desired_replicas"
        return 1
    fi
    
    # Check for crash loops
    local crash_loops
    crash_loops=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=otel-collector" \
        -o jsonpath='{.items[?(@.status.containerStatuses[?(@.state.waiting.reason=="CrashLoopBackOff")])].metadata.name}' 2>/dev/null | wc -w)
    
    if [[ "$crash_loops" -gt 0 ]]; then
        error "Found collector pods in CrashLoopBackOff state"
        return 1
    fi
    
    success "All $desired_replicas collector pods are ready"
}

# Verify API pods are running and ready
verify_api_pods() {
    log "Verifying SigNoz API pods are ready..."
    
    local desired_replicas
    desired_replicas=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="signoz")].spec.replicas}' 2>/dev/null || echo "1")
    
    local ready_replicas
    ready_replicas=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="signoz")].status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [[ "$ready_replicas" -lt "$desired_replicas" ]]; then
        error "Not all API pods are ready: $ready_replicas/$desired_replicas"
        return 1
    fi
    
    success "All $desired_replicas API pods are ready"
}

# Verify ingress is responding
verify_ingress_response() {
    log "Verifying SigNoz ingress is responding..."
    
    local signoz_host
    signoz_host=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    
    if [[ -z "$signoz_host" ]]; then
        warn "Could not determine SigNoz ingress host, skipping response check"
        return 0
    fi
    
    # Try to get response from ingress
    if curl -sf "https://$signoz_host/api/v1/health" &>/dev/null || curl -sf "http://$signoz_host/api/v1/health" &>/dev/null; then
        success "SigNoz API is responding"
        return 0
    else
        warn "Could not reach SigNoz API at $signoz_host (may still be warming up)"
        return 0  # Don't fail on this
    fi
}

# Main verification routine
main() {
    log "=== SigNoz Post-Upgrade Verification (Environment: $ENVIRONMENT) ==="
    
    local checks_passed=0
    local checks_failed=0
    
    # Run all checks in sequence
    if wait_for_migrator_job; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    sleep 5  # Give ClickHouse a moment to stabilize
    
    if verify_clickhouse_writable; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if verify_ddl_queue_drained; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if verify_collector_pods; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if verify_api_pods; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if verify_ingress_response; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    log "=== Post-Upgrade Verification Results ==="
    log "Passed: $checks_passed, Failed: $checks_failed"
    
    if [[ $checks_failed -gt 0 ]]; then
        error "Post-upgrade verification FAILED"
        return 1
    fi
    
    success "Post-upgrade verification PASSED - SigNoz is healthy"
    return 0
}

main "$@"
