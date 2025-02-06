# Migrate Cert-Manager To Helm

These are the steps to move cert-manager to helmfile. There is no downtime associated with this.

## Steps
1. Delete the existing cert-manager 
```kubectl delete -f base/notify-system/cert-manager.yaml```
2. Clean up orphaned certificate secrets
```scripts/cleanOrphanedCerts.sh kube-system```
3. Install the new cert-manager
```helmfile -e <targetEnv> -l app=cert-manager apply```