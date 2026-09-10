# SigNoz Upgrade Runbook

## Quick 4-Step Upgrade Process

### Step 1: Pre-flight Health Check
```bash
./scripts/signoz-upgrade-preflight.sh production
```

Expected: `✅ [OK] Pre-flight check PASSED`

If any ❌ checks fail, **STOP** and investigate before proceeding.

### Step 2: Pre-stage ClickHouse (5-15 minutes)
```bash
./scripts/signoz-upgrade-clickhouse-prestage.sh production 25.12.5
```

Updates ClickHouse and waits for rolling restart.

Expected: `✅ [OK] Rolling restart complete`

### Step 3: Apply Helmfile Upgrade
```bash
helmfile sync --environment production
```

Bumps SigNoz to 0.138.0 and applies all config changes.

### Step 4: Post-Upgrade Verification (5-15 minutes)
```bash
./scripts/signoz-upgrade-postflight.sh production
```

Waits for migrator job and verifies all components.

Expected: `✅ [OK] Post-upgrade verification PASSED`

**Total time: 15-40 minutes**

---

## GitHub Actions Upgrade (Alternative)

### Step 1: Trigger Workflow

Go to: **Actions → SigNoz Upgrade → Run workflow**

Fill in:
- **Environment**: `staging` or `production`
- **SigNoz version**: e.g., `0.138.0`
- **SigNoz k8s version**: e.g., `0.17.0`
- **OpenTelemetry Operator**: (leave blank unless specifically updating)
- **ClickHouse version**: e.g., `25.12.5` (or leave blank for chart default)
- **Skip preflight**: Only if you manually verified cluster health

Click: **Run workflow**

### Step 2: Monitor Workflow Execution

Watch the workflow at: https://github.com/cds-snc/notification-manifests/actions/runs/[ID]

Expected stages:
1. **Pre-flight checks** (2-3 min) - Verifies cluster health
2. **ClickHouse pre-stage** (5-15 min) - Updates CH version, waits for rolling restart
3. **Helmfile apply** (3-5 min) - Applies chart updates
4. **Post-flight verification** (5-15 min) - Verifies all pods ready, migrator complete
5. **Slack notification** - Status update sent

### Step 3: Verify Upgrade

Once workflow succeeds:

```bash
# Check SigNoz API is responding
kubectl port-forward -n signoz svc/signoz 8080:3301 &
curl http://localhost:8080/api/v1/health

# Check ClickHouse is healthy
kubectl exec -n signoz signoz-clickhouse-0-0-0 -- clickhouse-client -q \
  "SELECT database, table, readonly FROM system.tables WHERE database LIKE 'signoz_%'"
# All should show readonly=0

# Check collector pods
kubectl get pods -n signoz -l app.kubernetes.io/component=otel-collector
# Should show READY 1/1
```

### Step 4: Monitor for Issues

First 30 minutes after upgrade:
- Watch logs: `kubectl logs -n signoz -f -l app.kubernetes.io/component=otel-collector`
- Check for pod restarts: `kubectl get events -n signoz --sort-by='.lastTimestamp'`
- Monitor CPU/memory spikes (expected for ~5 minutes after upgrade)

## Manual Upgrade Path (if GitHub Actions unavailable)

### Prerequisites

```bash
cd /path/to/notification-manifests
export ENVIRONMENT=staging  # or production
source ./helmfile/getContext.sh -g
```

### Step 1: Pre-flight Checks

```bash
chmod +x ./scripts/signoz-upgrade-preflight.sh
./scripts/signoz-upgrade-preflight.sh $ENVIRONMENT

# Expected output:
# ✅ [OK] Cluster accessible
# ✅ [OK] All X ClickHouse replicas are writable
# ✅ [OK] ZooKeeper quorum healthy: 3/3 nodes responding
# ✅ [OK] Replicas synchronized
# ✅ [OK] DDL queue is empty
# ✅ [OK] Pre-flight check PASSED - cluster is ready for upgrade
```

If any checks fail with ❌, **STOP** and investigate.
If "Degraded" warnings (⚠️), can proceed but watch closely.

### Step 2: Pre-stage ClickHouse

```bash
export NEW_CH_VERSION=25.12.5  # Update as needed
chmod +x ./scripts/signoz-upgrade-clickhouse-prestage.sh
./scripts/signoz-upgrade-clickhouse-prestage.sh $ENVIRONMENT $NEW_CH_VERSION

# This takes 5-15 minutes depending on data size
# Expected output:
# ✅ [OK] ClickHouse image patched to 25.12.5
# ✅ [OK] Rolling restart complete: 2/2 replicas ready
# ✅ [OK] Replica synchronization verified
# ✅ [OK] No readonly tables
# ✅ [OK] ClickHouse pre-stage upgrade completed successfully
```

### Step 3: Update Helmfile

Edit `helmfile/helmfile.yaml.gotmpl` and update chart versions:

```yaml
# Find these releases and update versions:
- name: signoz
  chart: signoz/signoz
  version: 0.138.0        # ← Update this
  
- name: signoz-k8s
  chart: signoz/k8s-infra
  version: 0.17.0         # ← Update this
  
- name: opentelemetry-operator
  chart: opentelemetry/opentelemetry-operator
  version: 0.122.0        # ← Update this (if needed)
```

Or update VERSION file (recommended for production):
```bash
echo "0.138.0" > VERSION
git add VERSION
git commit -m "Upgrade SigNoz to 0.138.0"
```

### Step 4: Apply with Helmfile

```bash
cd helmfile
helmfile --environment $ENVIRONMENT \
  -l 'app=signoz,app=signoz-k8s,app=signoz-telemetry,app=signoz-importer' \
  apply

# Expected output:
# ...
# Finished applying 4 releases: signoz, signoz-k8s, signoz-telemetry, signoz-importer
```

### Step 5: Wait for Migrator Job

```bash
# Monitor the migration job (takes 5-15 minutes for large schemas)
kubectl logs -n signoz -f -l job-name=signoz-telemetrystore-migrator

# Expected final log:
# [<timestamp>] Schema migration completed successfully
```

### Step 6: Post-flight Verification

```bash
chmod +x ./scripts/signoz-upgrade-postflight.sh
./scripts/signoz-upgrade-postflight.sh $ENVIRONMENT

# Expected output:
# ✅ [OK] Migrator job completed successfully
# ✅ [OK] All ClickHouse tables are writable
# ✅ [OK] DDL queue is empty
# ✅ [OK] All 2 collector pods are ready
# ✅ [OK] All 1 API pods are ready
# ✅ [OK] SigNoz API is responding
# ✅ [OK] Post-upgrade verification PASSED - SigNoz is healthy
```

## Rollback (if something goes wrong)

### Quick Rollback (reverse the helmfile changes)

```bash
# Revert helmfile.yaml.gotmpl to previous commit
git checkout HEAD~1 helmfile/helmfile.yaml.gotmpl

# Or manually edit back to previous versions
vim helmfile/helmfile.yaml.gotmpl

# Re-apply
cd helmfile
helmfile --environment $ENVIRONMENT \
  -l 'app=signoz,app=signoz-k8s,app=signoz-telemetry,app=signoz-importer' \
  apply

# Verify
../scripts/signoz-upgrade-postflight.sh $ENVIRONMENT
```

### ClickHouse Rollback (if stuck on new version)

```bash
# If ClickHouse is causing problems, rollback image
export PREVIOUS_CH_VERSION=25.5.6
../scripts/signoz-upgrade-clickhouse-prestage.sh $ENVIRONMENT $PREVIOUS_CH_VERSION
```

## Troubleshooting Quick Reference

| Issue | Cause | Fix |
|-------|-------|-----|
| Pre-flight fails - readonly tables | Replica divergence | Wait 5-10 min and retry, or check DDL queue |
| ClickHouse pre-stage times out | Large data volume | `export WAIT_TIMEOUT=1800` and retry |
| Migrator job timeout | Complex schema | Check logs: `kubectl logs -n signoz -l job-name=signoz-telemetrystore-migrator` |
| Collector pods crash | Exporter config mismatch | Verify helmfile has correct version (otlp vs otlphttp) |
| Helm apply fails | CH version mismatch | Run ClickHouse pre-stage first |

## Key Contacts & Resources

- **Slack**: #notification-platform
- **Incident channel**: #incidents-production
- **Documentation**: https://github.com/cds-snc/notification-manifests/blob/main/docs/SIGNOZ_UPGRADE_GUIDE.md
- **Incident notes**: `.../memories/repo/signoz-clickhouse-upgrade.md`
- **SigNoz charts**: https://charts.signoz.io
- **ClickHouse docs**: https://clickhouse.com/docs/

## Post-Upgrade Tasks

- [ ] Monitor logs for 30+ minutes
- [ ] Verify metrics are flowing (check SigNoz dashboard)
- [ ] Confirm no pod restarts occurring
- [ ] Update team in Slack with completion status
- [ ] Log version change in confluence/docs
- [ ] Check for any security advisories for new versions
