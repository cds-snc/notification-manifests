# SigNoz Dashboards Helm Chart

Manage SigNoz dashboards as code using Helm.

## Usage

### Option 1: Load from Files (Recommended)

1. **Export your dashboards from SigNoz UI**
   - Go to Dashboard → Settings → Export
   - Save the JSON file to `charts/signoz-importer/dashboards/` directory
   - Example: `charts/signoz-importer/dashboards/k8s-node-overview.json`

2. **Configure the values file**
   
   In `overrides/system/signoz-importer.yaml`:
   
   ```yaml
   dashboards:
     - name: k8s-node-overview
       file: k8s-node-overview.json
     - name: k8s-pod-overview
       file: k8s-pod-overview.json
   ```

### Option 2: Inline Data

If you prefer to keep the JSON in the values file:

```yaml
dashboards:
  - name: k8s-node-overview
    data: |
      {
        "title": "K8s Node Overview",
        ... dashboard JSON ...
      }
```

## Deployment

Deploy with Helmfile:

```bash
helmfile -e <environment> apply
```

## How it Works

1. Dashboard JSON files are stored in ConfigMaps
2. A Helm hook Job runs after install/upgrade
3. The Job waits for SigNoz to be ready
4. Dashboards are imported via SigNoz API
5. Job cleans up automatically after 5 minutes

## Notes

- The chart uses a post-install/post-upgrade hook, so dashboards are imported after SigNoz is deployed
- Failed dashboard imports don't fail the entire job (continues with remaining dashboards)
- Old import jobs are automatically cleaned up
- Dashboard files in `dashboards/` directory are packaged with the chart
