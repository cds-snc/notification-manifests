# SigNoz Version Management Strategy

## Understanding Version Compatibility

ClickHouse and SigNoz versions are **tightly coupled**. Each SigNoz chart version is built for specific ClickHouse versions.

### Compatible Pairs

| SigNoz | ClickHouse | Status |
|--------|-----------|--------|
| 0.110.0 | 25.5.6 | ✅ Production current |
| 0.138.0 | 25.5.6+ / 25.12.5 | ✅ Staging (supports both) |
| 0.138.0+ | 25.12.5+ | ✅ Future versions |

**Key constraint**: You cannot run SigNoz 0.110.0 with ClickHouse 25.12.5 - they're schema-incompatible.

## Upgrade Paths

### Current Situation (Production)
```
SigNoz 0.110.0 + ClickHouse 25.5.6
```

### Initial Upgrade (Cross Major Versions)

To move from (0.110.0 + 25.5.6) to (0.138.0 + 25.12.5), you **must cross a compatibility boundary**. This requires:

```
Step 1: Pre-stage ClickHouse 25.5.6 → 25.12.5
        (Use signoz-upgrade-clickhouse-prestage.sh or manual kubectl patch)
        ↓
        SigNoz 0.110.0 + ClickHouse 25.12.5
        (Temporary - only valid for a few hours)
        ↓
Step 2: Upgrade SigNoz 0.110.0 → 0.138.0
        (Migrator now runs on compatible CH 25.12.5)
        ↓
        SigNoz 0.138.0 + ClickHouse 25.12.5 ✅
```

### Future Upgrades (Within Same Major Version)

Once you're at (0.138.0 + 25.12.5), future upgrades are simple because each version pair within 0.138.0+ can handle CH independently:

```
Simple PR approach:

PR 1: Bump ClickHouse only
      helmfile/overrides/system/signoz.yaml.gotmpl
      image.tag: 25.12.5 → 25.13.0
      
      Wait 24 hours ✅
      
PR 2: Bump SigNoz only
      helmfile/helmfile.yaml.gotmpl
      version: 0.138.0 → 0.140.0
```

## Implementation Strategy

### For Current Upgrade (0.110.0 → 0.138.0)

We cannot fully eliminate the pre-staging script for this initial boundary-crossing upgrade. You need:

```bash
# 1. Ensure these scripts are in place
./scripts/signoz-upgrade-preflight.sh
./scripts/signoz-upgrade-clickhouse-prestage.sh
./scripts/signoz-upgrade-postflight.sh

# 2. When ready to upgrade:
# Step A: Pre-stage CH (takes 10-15 minutes)
./scripts/signoz-upgrade-clickhouse-prestage.sh staging 25.12.5

# Step B: Update helmfile and bump SigNoz (takes 5-10 minutes)
# Edit helmfile/helmfile.yaml.gotmpl
# version: 0.110.0 → 0.138.0

# Step C: Verify upgrade succeeded
./scripts/signoz-upgrade-postflight.sh staging
```

### After Initial Upgrade (0.138.0+)

Once you've crossed to 0.138.0+, you can use the simpler two-PR approach:

```bash
# PR 1: Bump CH version in values
vim helmfile/overrides/system/signoz.yaml.gotmpl
# Update: image.tag

# PR 2 (next day after verification): Bump SigNoz version
vim helmfile/helmfile.yaml.gotmpl
# Update: version
```

## Why This Approach?

1. **One-time complexity**: The pre-staging scripts are only needed for boundary-crossing upgrades
2. **Future simplicity**: Once on 0.138.0+, you get the two-PR workflow
3. **Safety**: Separating CH and SigNoz changes makes failures easier to diagnose
4. **Stability**: Waiting between PRs allows time to catch issues

## Documentation

- **For boundary-crossing upgrades**: Use `docs/SIGNOZ_UPGRADE_GUIDE.md`
- **For within-version upgrades**: Use `docs/SIGNOZ_UPGRADE_RUNBOOK.md`
- **For ClickHouse-only changes**: Edit `helmfile/overrides/system/signoz.yaml.gotmpl` image.tag
- **For SigNoz version changes**: Edit `helmfile/helmfile.yaml.gotmpl` version field

## Troubleshooting

### "Schema migrator waiting for ClickHouse version X"

This means:
- The helmfile specifies one CH version
- The actual pods are running a different version
- The pods haven't restarted yet (or upgrade is hung)

**Solution**:
1. Check current pod version: `kubectl get pods -n signoz -l app.kubernetes.io/instance=signoz`
2. If version mismatch, check pod events: `kubectl describe pod -n signoz signoz-clickhouse-0-0-0`
3. If stuck, use pre-staging script to force the update: `./scripts/signoz-upgrade-clickhouse-prestage.sh <env> <version>`

### "Can't upgrade SigNoz because pre-upgrade hook fails"

This is the original problem. Solutions:

**Option A** (Recommended): Use pre-staging script
```bash
./scripts/signoz-upgrade-clickhouse-prestage.sh staging 25.12.5
# Wait for completion
# Then update helmfile and push
```

**Option B** (Manual): Manually patch ClickHouse before helm upgrade
```bash
# Get the new CH version from the chart
helm show values signoz/signoz --version 0.138.0 | grep image

# Patch it manually
kubectl patch chi -n signoz signoz-clickhouse --type=json -p='[{"op":"replace","path":"/spec/templates/podTemplates/0/spec/containers/0/image","value":"docker.io/clickhouse/clickhouse-server:25.12.5"}]'

# Wait for rolling restart
# Then push helmfile update
```

## Key Takeaway

✅ **You can't decouple SigNoz and ClickHouse versions completely**  
✅ **But you CAN control them via separate files in helmfile**  
✅ **This makes the workflow much simpler once you cross the initial upgrade boundary**
