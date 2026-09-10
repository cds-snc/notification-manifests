# ClickHouse Separate Management Guide

## Overview

ClickHouse is now managed **independently** from the SigNoz chart. This allows you to:
- Upgrade ClickHouse without upgrading SigNoz
- Upgrade SigNoz without upgrading ClickHouse
- Test each component separately
- Avoid version conflicts and pre-upgrade hook issues

## Architecture

```
helmfile.yaml.gotmpl
├── clickhouse-operator (step 1) - manages CH instances
├── signoz-clickhouse (step 2)   - the actual CH cluster
├── signoz (step 3)              - points to external CH
├── signoz-secret (step 4)       - SigNoz secrets
├── opentelemetry-operator (step 4)
├── signoz-k8s (step 5)
├── signoz-telemetry (step 6)
├── signoz-importer (step 7)
└── prometheus-cloudwatch-exporter (step 8)
```

**Key difference**: `signoz` now has `needs: [signoz-clickhouse]`, ensuring ClickHouse is ready before SigNoz tries to connect.

## Files Changed

### 1. New: `helmfile/overrides/system/signoz-clickhouse.yaml.gotmpl`
Contains ALL ClickHouse configuration:
- ClickHouseInstallation spec (replicas, layout, storage)
- ZooKeeper configuration (3 replicas for quorum)
- MergeTree settings (readonly protection, suspicious parts limit)
- Node selectors and tolerations

**To upgrade ClickHouse version**: Edit this file and update the image tag:
```yaml
spec:
  configuration:
    clusters:
      - name: default
        templates:
          podTemplates:
            - name: default
              spec:
                containers:
                  - name: clickhouse
                    image: clickhouse/clickhouse-server:25.12.5  # ← Change this
```

### 2. Updated: `helmfile/helmfile.yaml.gotmpl`
- Added `altinity-clickhouse-operator` repository
- Added `clickhouse-operator` release (step 1)
- Added `signoz-clickhouse` release (step 2)
- Updated `signoz` release:
  - Changed step from 2 to 3
  - Added `needs: [signoz-clickhouse]`
- Updated step numbers for all subsequent releases

### 3. Updated: `helmfile/overrides/system/signoz.yaml.gotmpl`
Removed entire `clickhouse:` section, replaced with:
```yaml
clickhouse:
  enabled: false
  # External ClickHouse connection parameters
  host: signoz-clickhouse.signoz.svc.cluster.local
  port: 9000
  database: default
  cluster: default
```

## Upgrade Workflows

### Scenario 1: Upgrade Only ClickHouse (Recommended First)

**Step 1: Create a PR to bump ClickHouse**
```yaml
# helmfile/overrides/system/signoz-clickhouse.yaml.gotmpl
image: clickhouse/clickhouse-server:25.12.5  # ← Update version
```

**Step 2: Merge PR**
- The existing `helmfile_production_apply` workflow will:
  1. Run pre-flight checks automatically (optional)
  2. Apply ClickHouse release
  3. Wait for rolling restart
  4. Apply other releases (SigNoz, etc.)

**Step 3: Monitor**
- Watch logs: `kubectl logs -n signoz -f -l app.kubernetes.io/component=clickhouse`
- Check tables writable: `kubectl exec -n signoz signoz-clickhouse-0-0-0 -- clickhouse-client -q "SELECT COUNT(*) FROM system.tables WHERE readonly=1"`

**Step 4: Verify stable**
- Wait at least 24 hours on staging
- Ensure no errors in ClickHouse logs
- Check SigNoz metrics still flowing

### Scenario 2: Upgrade Only SigNoz (After CH is stable)

**Step 1: Create a PR to bump SigNoz**
```yaml
# helmfile/helmfile.yaml.gotmpl
- name: signoz
  version: 0.138.0  # ← Update version
```

**Step 2: Merge PR**
- Workflow will:
  1. Skip ClickHouse (already at target version)
  2. Apply SigNoz release
  3. Wait for migrator job (uses the ClickHouse version from step 1)
  4. Apply other releases

### Scenario 3: Upgrade Both (But in Two PRs!)

**PR 1** (day 1):
- Update ClickHouse version in `signoz-clickhouse.yaml.gotmpl`
- Merge and test for 24 hours on staging

**PR 2** (day 2, after verifying CH is stable):
- Update SigNoz version in `helmfile.yaml.gotmpl`
- Merge
- Verify all components healthy

**Why two PRs?**
1. Easy to rollback if ClickHouse has issues
2. Clear separation of concerns
3. Time to catch ClickHouse issues before upgrading SigNoz
4. Matches the incident root cause (CH must be ready before migrator runs)

## Key Changes from Old Setup

| Aspect | Before | After |
|--------|--------|-------|
| **ClickHouse config location** | `signoz.yaml.gotmpl` clickhouse: section | New file: `signoz-clickhouse.yaml.gotmpl` |
| **CH version lock** | Locked to SigNoz chart version | Independent version control |
| **CH upgrade process** | Bump entire SigNoz chart | Edit one line in `signoz-clickhouse.yaml.gotmpl` |
| **CH + SigNoz coordinated upgrade** | Single PR, risky | Two separate PRs, safer |
| **Pre-upgrade hooks** | Run on potentially old CH | Run on already-upgraded CH ✅ |

## Monitoring ClickHouse Health

```bash
# SSH into ClickHouse pod
kubectl exec -it -n signoz signoz-clickhouse-0-0-0 -- bash

# Inside pod, run ClickHouse client
clickhouse-client

# Check for readonly tables
SELECT database, table, readonly FROM system.tables WHERE database LIKE 'signoz_%';

# Check DDL queue
SELECT * FROM system.distributed_ddl_queue;

# Check replica status
SELECT * FROM system.replicas;

# Check ZooKeeper connection
SHOW CREATE TABLE database.table;  -- Should show replica syntax if healthy
```

## Rollback Procedures

### Rollback ClickHouse Version

```bash
# Edit the version back
vim helmfile/overrides/system/signoz-clickhouse.yaml.gotmpl
# Change image tag back to previous version
# Save and commit

git add helmfile/overrides/system/signoz-clickhouse.yaml.gotmpl
git commit -m "Rollback ClickHouse to 25.5.6"
git push

# Workflow will auto-apply
```

### Rollback SigNoz Version

```bash
# Edit the version back
vim helmfile/helmfile.yaml.gotmpl
# Change signoz chart version back
# Save and commit

git add helmfile/helmfile.yaml.gotmpl
git commit -m "Rollback SigNoz to 0.110.0"
git push

# Workflow will auto-apply
```

## Troubleshooting

### ClickHouse pods not starting after upgrade

```bash
# Check pod events
kubectl describe pod -n signoz signoz-clickhouse-0-0-0

# Check operator logs
kubectl logs -n signoz -l app.kubernetes.io/name=clickhouse-operator -f

# Check if image pull error
kubectl get pods -n signoz -o wide
```

### SigNoz can't connect to ClickHouse

Check connection parameters in `signoz.yaml.gotmpl`:
```yaml
clickhouse:
  host: signoz-clickhouse.signoz.svc.cluster.local  # Must match K8s DNS
  port: 9000
```

Verify network connectivity:
```bash
kubectl exec -it -n signoz deployment/signoz -- \
  nc -zv signoz-clickhouse.signoz.svc.cluster.local 9000
```

### ZooKeeper quorum issues after ClickHouse upgrade

If you see readonly tables after CH upgrade:
```bash
# Check ZK pod status
kubectl get pods -n signoz -l app=zookeeper

# Check ZK health
kubectl exec -n signoz signoz-zookeeper-0 -- \
  sh -c "echo ruok | nc localhost 2181"
```

## Version Compatibility Notes

- **ClickHouse 25.5.6**: Current production version
- **ClickHouse 25.12.5**: Staging version (supports `object_serialization_version` setting)
- **SigNoz 0.110.0**: Current production version (uses CH 25.5.6)
- **SigNoz 0.138.0**: Staging version (compatible with CH 25.5.6 or 25.12.5)

## Next Steps

1. **Test on staging**: Merge this branch to staging and verify CH + SigNoz work together
2. **Test production**: Create prod PR to bump production CH to 25.12.5 when ready
3. **Plan SigNoz upgrade**: Once CH is stable, upgrade SigNoz in a separate PR
4. **Document in runbook**: Update team runbook with new upgrade procedure

## Questions?

Refer to:
- `docs/SIGNOZ_UPGRADE_GUIDE.md` - Comprehensive upgrade guide
- `docs/SIGNOZ_UPGRADE_RUNBOOK.md` - Quick reference for operators
- Original incident notes: `memories/repo/signoz-clickhouse-upgrade.md`
