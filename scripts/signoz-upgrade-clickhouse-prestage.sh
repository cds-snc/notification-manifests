#!/bin/bash
# SigNoz ClickHouse Pre-Stage Upgrade
# Updates ClickHouse image tag in the CHI resource before helm upgrade
# This ensures the migrator job can run on the new ClickHouse version

set -euo pipefail

ENVIRONMENT="${1:-staging}"
NAMESPACE="signoz"
CHI_NAME="signoz-clickhouse"
NEW_CH_VERSION="${2:-25.12.5}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-1200}"  # 20 minutes
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"

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

# Get current ClickHouse image tag
get_current_ch_version() {
    kubectl get chi -n "$NAMESPACE" "$CHI_NAME" -o jsonpath='{.spec.templates.podTemplates[0].spec.containers[0].image}' | sed -n 's/.*clickhouse-server:\([^"]*\).*/\1/p' || echo "unknown"
}

# Update ClickHouse image in CHI
update_ch_image() {
    log "Updating ClickHouse image to version $NEW_CH_VERSION..."
    
    local current_version
    current_version=$(get_current_ch_version)
    
    if [[ "$current_version" == "$NEW_CH_VERSION" ]]; then
        success "ClickHouse is already at version $NEW_CH_VERSION"
        return 0
    fi
    
    log "Current version: $current_version"
    log "Target version: $NEW_CH_VERSION"
    
    # Update via kubectl patch
    kubectl patch chi -n "$NAMESPACE" "$CHI_NAME" --type=json -p="[{\"op\":\"replace\",\"path\":\"/spec/templates/podTemplates/0/spec/containers/0/image\",\"value\":\"docker.io/clickhouse/clickhouse-server:${NEW_CH_VERSION}\"}]"
    
    success "ClickHouse image patched to $NEW_CH_VERSION"
}

# Wait for rolling restart to complete
wait_for_rolling_restart() {
    log "Waiting for ClickHouse rolling restart to complete..."
    
    local start_time=$(date +%s)
    local current_time
    local replica_count
    local running_count
    
    # Get expected replica count
    replica_count=$(kubectl get chi -n "$NAMESPACE" "$CHI_NAME" -o jsonpath='{.spec.configuration.clusters[0].layout.replicasCount}')
    log "Expected replicas: $replica_count"
    
    while true; do
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $WAIT_TIMEOUT ]]; then
            error "Timeout waiting for rolling restart after ${WAIT_TIMEOUT}s"
            return 1
        fi
        
        # Count running replicas
        running_count=$(kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null | grep "chi-${CHI_NAME}-cluster" | grep "Running" | wc -l)
        
        if [[ $running_count -eq $replica_count ]]; then
            log "All replicas running; verifying they're healthy..."
            
            # Get first pod name and verify via ClickHouse query
            local first_pod
            first_pod=$(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null | grep "chi-${CHI_NAME}-cluster" | head -1 | sed 's/pod\///')
            
            if [[ -n "$first_pod" ]]; then
                if kubectl exec -n "$NAMESPACE" "$first_pod" -- clickhouse-client -q "SELECT 1" &>/dev/null; then
                    success "Rolling restart complete: all $replica_count replicas ready"
                    return 0
                fi
            fi
        fi
        
        log "Rolling restart in progress: $running_count/$replica_count replicas running (${elapsed}s elapsed)"
        sleep "$CHECK_INTERVAL"
    done
}

# Verify replicas are in sync after upgrade
verify_replicas_in_sync() {
    log "Verifying replicas are synchronized..."
    
    local first_pod
    first_pod=$(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null | grep "chi-${CHI_NAME}-cluster" | head -1 | sed 's/pod\///')
    
    if [[ -z "$first_pod" ]]; then
        error "No ClickHouse replicas found"
        return 1
    fi
    
    # Check replica sync using system.replicas table
    # All replicas should have absolute_delay = 0
    local query="SELECT replica_name, is_leader, absolute_delay FROM system.replicas"
    
    local replica_status
    replica_status=$(kubectl exec -n "$NAMESPACE" "$first_pod" -- clickhouse-client -q "$query" 2>/dev/null || echo "")
    
    if [[ -z "$replica_status" ]]; then
        error "Could not query replica status"
        return 1
    fi
    
    # Check if any replica has non-zero delay
    local max_delay
    max_delay=$(echo "$replica_status" | tail -n +1 | awk '{print $NF}' | sort -n | tail -1)
    
    if [[ -n "$max_delay" && "$max_delay" -gt 0 ]]; then
        warn "Replicas still syncing (max delay: $max_delay). Waiting..."
        sleep 5
        
        replica_status=$(kubectl exec -n "$NAMESPACE" "$first_pod" -- clickhouse-client -q "$query" 2>/dev/null || echo "")
        max_delay=$(echo "$replica_status" | tail -n +1 | awk '{print $NF}' | sort -n | tail -1)
        
        if [[ -n "$max_delay" && "$max_delay" -gt 0 ]]; then
            error "Replicas failed to sync"
            echo "$replica_status" >&2
            return 1
        fi
    fi
    
    success "All replicas synchronized (delay=0)"
}

# Check for readonly tables (should be 0 after sync)
check_no_readonly_tables() {
    log "Checking for readonly tables..."
    
    local first_pod
    first_pod=$(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null | grep "chi-${CHI_NAME}-cluster" | head -1 | sed 's/pod\///')
    
    if [[ -z "$first_pod" ]]; then
        error "No ClickHouse replicas found"
        return 1
    fi
    
    local query="SELECT database, table FROM system.tables WHERE database LIKE 'signoz_%' AND is_readonly = 1"
    
    local readonly_tables
    readonly_tables=$(kubectl exec -n "$NAMESPACE" "$first_pod" -- clickhouse-client -q "$query" 2>/dev/null || echo "")
    
    if [[ -n "$readonly_tables" ]]; then
        warn "Found readonly tables - allowing time for auto-recovery..."
        echo "$readonly_tables" | while read -r line; do
            [[ -n "$line" ]] && warn "  - $line"
        done
        
        sleep 10
        
        readonly_tables=$(kubectl exec -n "$NAMESPACE" "$first_pod" -- clickhouse-client -q "$query" 2>/dev/null || echo "")
        
        if [[ -n "$readonly_tables" ]]; then
            error "Readonly tables still present after waiting"
            return 1
        fi
    fi
    
    success "No readonly tables"
}

# Main ClickHouse pre-stage upgrade
main() {
    log "=== SigNoz ClickHouse Pre-Stage Upgrade (Environment: $ENVIRONMENT) ==="
    log "Target ClickHouse version: $NEW_CH_VERSION"
    
    if update_ch_image; then
        if wait_for_rolling_restart; then
            if verify_replicas_in_sync; then
                if check_no_readonly_tables; then
                    success "ClickHouse pre-stage upgrade completed successfully"
                    return 0
                fi
            fi
        fi
    fi
    
    error "ClickHouse pre-stage upgrade failed"
    return 1
}

main "$@"
