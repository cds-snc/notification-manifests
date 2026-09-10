# SigNoz Automated Upgrade Guide

## Overview

This guide documents the automated SigNoz upgrade process, designed to safely handle chart upgrades across production and staging environments. The process was built to prevent and recover from the issues encountered during the 0.110.0 → 0.138.0 upgrade incident.

## Key Features

1. **Pre-flight health checks** - Verifies ClickHouse cluster is ready before any changes
2. **Staged ClickHouse upgrade** - Updates ClickHouse version BEFORE chart versions to avoid chicken-and-egg problems
3. **Environment-aware config** - Automatic exporter name selection based on environment
4. **Post-upgrade verification** - Comprehensive health checks after deployment
5. **Slack notifications** - Status updates on completion

## Why This Approach?

The SigNoz 0.110.0 → 0.138.0 incident revealed several critical issues:

1. **Pre-upgrade hook runs on old ClickHouse** - The `signoz-telemetrystore-migrator` pre-upgrade job runs BEFORE the ClickHouse pod is updated, so it fails on older ClickHouse binaries that don't support new settings like `object_serialization_version`.

2. **Readonly table lockups** - ClickHouse replicas diverge during rolling restarts (too many unexpected data parts), causing tables to go readonly. This blocks the entire upgrade.

3. **Exporter name changes** - The signoz-k8s chart renames exporters between versions (otlp → otlphttp), breaking collector configs if not updated simultaneously.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Manual Input: Version numbers, Environment                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                    ┌────▼──────┐
                    │  Preflight │  ← Check replica health, ZK, DDL
                    └────┬──────┘
                         │
              ┌──────────▼──────────┐
              │  ClickHouse Pre-    │  ← Patch CHI image tag
              │  Stage Upgrade      │  ← Wait for rolling restart
              └──────────┬──────────┘  ← Verify replicas in sync
                         │
              ┌──────────▼──────────┐
              │  Helmfile Apply     │  ← Apply SigNoz chart updates
              │  (Chart Versions)   │
              └──────────┬──────────┘
                         │
              ┌──────────▼──────────┐
              │  Post-flight        │  ← Wait for migrator job
              │  Verification       │  ← Check tables writable
              │                     │  ← Verify pods ready
              └──────────┬──────────┘
                         │
                    ┌────▼──────┐
                    │  Notify   │
                    │  Slack    │
                    └───────────┘
```

## Typical Upgrade Timeline

### Staging
- **Pre-flight**: 2-3 minutes
- **ClickHouse pre-stage**: 5-10 minutes (rolling restart)
- **Helmfile apply**: 3-5 minutes
- **Post-flight**: 5-10 minutes (waiting for migrator job)
- **Total**: ~20-35 minutes

### Production
- Same as staging, plus extra verification time
- Pre-flight checks more thorough due to stricter requirements
- **Total**: ~30-45 minutes

## Prerequisites

- Helm 3.x and helmfile 1.4.4+
- kubectl with access to target cluster
- AWS credentials with appropriate IAM roles
- VPN access configured via setup-cluster-access action

## Manual Usage

You can also run the upgrade scripts manually if needed:

### 1. Pre-flight Checks

```bash
cd /path/to/notification-manifests
chmod +x ./scripts/signoz-upgrade-preflight.sh
./scripts/signoz-upgrade-preflight.sh staging  # or production

# Exit codes:
# 0 = Healthy, safe to proceed
# 1 = Unhealthy, DO NOT proceed
# 2 = Degraded, proceed with caution
```

**What it checks:**
- Cluster access and namespace existence
- All ClickHouse replicas are writable
- ZooKeeper quorum is healthy (2+ nodes responding)
- Replicas are synchronized (parts match between nodes)
- DDL queue is empty (no pending operations)

### 2. ClickHouse Pre-Stage Upgrade

```bash
export ENVIRONMENT=staging
export CH_VERSION=25.12.5

chmod +x ./scripts/signoz-upgrade-clickhouse-prestage.sh
./scripts/signoz-upgrade-clickhouse-prestage.sh $ENVIRONMENT $CH_VERSION

# Exit code 0 = Success, safe to proceed with helm upgrade
# Exit code 1 = Failed, DO NOT proceed
```

**What it does:**
1. Patches the ClickHouseInstallation resource with new image tag
2. Waits for rolling restart (up to 20 minutes)
3. Verifies all replicas are ready
4. Checks for readonly tables (retries if temporary)

### 3. Helmfile Apply

```bash
cd helmfile
./getContext.sh -g  # Load environment variables
helmfile --environment production \
  -l 'app=signoz,app=signoz-k8s,app=signoz-telemetry,app=signoz-importer' \
  apply
```

**Important:** 
- For production, update the VERSION file instead of manual execution
- The helmfile.yaml.gotmpl automatically renders environment-aware configs
- signoz-k8s.yaml.gotmpl chooses exporter name based on environment

### 4. Post-Upgrade Verification

```bash
chmod +x ./scripts/signoz-upgrade-postflight.sh
./scripts/signoz-upgrade-postflight.sh production

# Exit code 0 = Healthy, upgrade successful
# Exit code 1 = Issues detected, investigate
```

**What it checks:**
- `signoz-telemetrystore-migrator` job completed successfully (waits up to 10 min)
- All ClickHouse tables are writable
- DDL queue is drained
- OTel collector pods are ready and not in crash loops
- SigNoz API pods are ready
- Ingress is responding to health checks

## GitHub Workflow Usage

### Via GitHub UI

1. Go to Actions → "SigNoz Upgrade"
2. Click "Run workflow"
3. Fill in required inputs:
   - **Environment**: staging or production
   - **SigNoz version**: e.g., 0.138.0
   - **SigNoz k8s version**: e.g., 0.17.0
   - **OpenTelemetry Operator version** (optional): e.g., 0.122.0
   - **ClickHouse version** (optional): e.g., 25.12.5
   - **Skip preflight** (optional): check only if you've already verified health
4. Click "Run workflow"

### Via GitHub CLI

```bash
gh workflow run signoz-upgrade.yaml \
  -f environment=staging \
  -f signoz_version=0.138.0 \
  -f signoz_k8s_version=0.17.0 \
  -f clickhouse_version=25.12.5
```

## Configuration

### Environment-Aware Settings

The helmfile automatically applies different configurations based on environment:

**signoz.yaml.gotmpl:**
- ClickHouse settings (replicas, storage, ZK config)
- SigNoz API settings (email, postgres)
- Node selectors and tolerations

**signoz-k8s.yaml.gotmpl:**
- Exporter names: `{{ if eq .Environment.Name "production" }}otlp{{ else }}otlphttp{{ end }}`
- Cloud integrations (CloudWatch, Lambda, etc.)
- Prometheus scrape configs

### Key Settings for Upgrade Safety

```yaml
# signoz.yaml.gotmpl
clickhouse:
  settings:
    # Allow replicas to recover from part divergence during rolling restarts
    merge_tree/replicated_max_ratio_of_wrong_parts: "1"
    # Prevent killing the node if too many parts are unexpectedly on disk
    merge_tree/max_suspicious_broken_parts: "200"
```

## Troubleshooting

### Issue: Pre-flight check fails - "readonly tables"

**Cause:** ClickHouse replicas have diverged from ZooKeeper metadata.

**Solutions:**
1. Wait 5-10 minutes and retry (auto-recovery often works)
2. Check DDL queue: `kubectl exec -n signoz signoz-clickhouse-0-0-0 -- clickhouse-client -q "SELECT * FROM system.distributed_ddl_queue"`
3. Manual recovery (last resort):
   ```bash
   # Get the healthy replica (check part counts in system.parts)
   # Then on the unhealthy replica:
   kubectl exec -n signoz POD_NAME -- clickhouse-client -q \
     "ALTER TABLE database.table ON CLUSTER 'signoz' DETACH PARTITION ALL"
   ```

### Issue: ClickHouse pre-stage times out after 20 minutes

**Cause:** Rolling restart is taking longer than expected (large data volumes).

**Solutions:**
1. Increase WAIT_TIMEOUT: `export WAIT_TIMEOUT=1800` (30 min)
2. Check pod events: `kubectl describe pod -n signoz signoz-clickhouse-0-0-0`
3. Check pod logs: `kubectl logs -n signoz signoz-clickhouse-0-0-0 -f`

### Issue: Post-flight check times out waiting for migrator job

**Cause:** Migration is running longer than expected (normal for large schemas).

**Solutions:**
1. Increase timeout: `export TIMEOUT=1200` (20 min)
2. Check job status: `kubectl get jobs -n signoz signoz-telemetrystore-migrator -o yaml`
3. Check job logs: `kubectl logs -n signoz -l job-name=signoz-telemetrystore-migrator`

### Issue: Collector pods crash with config errors

**Cause:** Exporter name mismatch (otlp vs otlphttp).

**Solution:** 
The signoz-k8s.yaml.gotmpl already handles this with:
```yaml
exporters:
  - {{ if eq .Environment.Name "production" }}otlp{{ else }}otlphttp{{ end }}
```

If still seeing issues, verify the correct versions are in helmfile.yaml.gotmpl.

### Issue: Helm apply fails with "pre-upgrade hook failed"

**Cause:** ClickHouse was not pre-staged (old version still running).

**Solution:**
1. Manually run ClickHouse pre-stage:
   ```bash
   ./scripts/signoz-upgrade-clickhouse-prestage.sh staging 25.12.5
   ```
2. Wait for completion (10+ minutes)
3. Retry helmfile apply

## Rollback Procedure

If something goes wrong during upgrade:

### Option 1: Revert helmfile manually

```bash
cd helmfile
./getContext.sh -g

# Apply the previous versions
helmfile --environment staging \
  -l 'app=signoz,app=signoz-k8s' \
  apply
# Update values manually to point to old versions
```

### Option 2: Use Velero snapshot (production)

Production has automatic pre-upgrade snapshots. If upgrade fails critically:

```bash
# Find latest snapshot
kubectl get volumesnapshot -n signoz

# Restore via Velero
gh workflow run velero_restore.yaml -f environment=production -f backup_type=helm
```

### Option 3: Pod restart without version changes

```bash
# Force pod restart if config issue
kubectl rollout restart deployment/signoz -n signoz
kubectl rollout restart deployment/signoz-otel-collector -n signoz
```

## Monitoring After Upgrade

After successful upgrade, monitor:

1. **ClickHouse cluster health:**
   ```bash
   kubectl exec -n signoz signoz-clickhouse-0-0-0 -- clickhouse-client -q \
     "SELECT database, table, readonly FROM system.tables WHERE database LIKE 'signoz_%'"
   ```

2. **DDL queue status:**
   ```bash
   kubectl exec -n signoz signoz-clickhouse-0-0-0 -- clickhouse-client -q \
     "SELECT * FROM system.distributed_ddl_queue"
   ```

3. **Collector health:**
   ```bash
   kubectl logs -n signoz -l app.kubernetes.io/component=otel-collector -f
   ```

4. **API logs:**
   ```bash
   kubectl logs -n signoz -l app.kubernetes.io/component=query-service -f
   ```

5. **Dashboard metrics:**
   - Navigate to https://signoz.INTERNAL_DNS_FQDN
   - Check System health dashboard
   - Monitor OTel collector metrics

## Version Compatibility Matrix

| SigNoz | signoz-k8s | opentelemetry-operator | ClickHouse | Notes |
|--------|-----------|------------------------|------------|-------|
| 0.110.0 | 0.15.1 | 0.112.1 | 25.5.6 | Production current |
| 0.138.0 | 0.17.0 | 0.122.0 | 25.12.5 | Staging current (exporter: otlphttp) |
| 0.138.0+ | 0.17.0+ | 0.122.0+ | 25.12.5+ | Uses otlphttp exporter |

**Important:** When upgrading signoz-k8s from 0.15.1 to 0.17.0+, the exporter name changes from `otlp` to `otlphttp`. The helmfile handles this automatically per environment.

## References

- [SigNoz Helm Charts](https://charts.signoz.io)
- [ClickHouse Operator](https://github.com/Altinity/clickhouse-operator)
- [OpenTelemetry Operator](https://opentelemetry.io/docs/kubernetes/operator/)
- Original incident notes: `/memories/repo/signoz-clickhouse-upgrade.md`
