# Migrate Cert-Manager To Helm

These are the steps to move cert-manager to helmfile. There is no downtime associated with this.

## Steps
1. Delete the existing cert-manager 
```kubectl delete -f base/notify-system/cert-manager.yaml```
2. Install the new cert-manager
```helmfile -e <targetEnv> -l app=cert-manager apply```
3. Clean up orphaned certificate secrets
```scripts/cleanOrphanedCerts.sh kube-system```
4. Re-apply kustomize code to create new certs
```env/<environment>/kubectl apply -k .