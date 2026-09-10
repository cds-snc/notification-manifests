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

## Troubleshooting

### Migrator Job Stuck
```bash
kubectl get jobs -n signoz | grep migrator
kubectl logs -n signoz job/signoz-schema-migrator-async -f
```

Give it 30 minutes - large upgrades can take time.

### ClickHouse Pods Not Ready
```bash
kubectl get pods -n signoz -l "app.kubernetes.io/instance=signoz-clickhouse" -o wide
kubectl logs -n signoz <pod-name>
```

Check replicas are synced:
```bash
kubectl exec -n signoz chi-signoz-clickhouse-cluster-0-0-0 -- \
  clickhouse-client -q "SELECT replica_name, absolute_delay FROM system.replicas"
```

### Collector Pods Failing
```bash
kubectl logs -n signoz -l app.kubernetes.io/component=otel-collector
```

Likely cause: Invalid exporter config. Verify signoz-k8s.yaml.gotmpl has `otlphttp` (not `otlp`).

---

## Rollback (if needed)

```bash
git revert <commit-hash>
helmfile sync --environment production
```

Note: ClickHouse will NOT downgrade - only SigNoz/operator are rolled back.

---

## Context

- **Version compatibility**: SigNoz 0.138.0 requires ClickHouse 25.12.5
- **Pre-staging required**: CH must be updated first to avoid migrator hook failures
- **Why this matters**: SigNoz 0.110.0 had incompatible schema migrations for newer ClickHouse
- **See also**: [SIGNOZ_VERSION_STRATEGY.md](SIGNOZ_VERSION_STRATEGY.md) for version details
