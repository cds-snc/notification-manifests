# Upgrade Karpenter

## Steps

1. Delete custom resources
```kubectl delete ec2nodeclasses.karpenter.k8s.aws $(kubectl get ec2nodeclasses.karpenter.k8s.aws | awk '{print $1}')```
```kubectl delete nodeclaims.karpenter.sh $(kubectl get nodeclaims.karpenter.sh | awk '{print $1}')```
```kubectl delete nodepools.karpenter.sh $(kubectl get nodepools.karpenter.sh | awk '{print $1}')```

2. Delete the karpenter namespace
```kubectl delete namespace karpenter```

3. Delete the CRDs
```kubectl delete crd $(kubectl get crd -n karpenter | grep karpenter | awk '{print $1}')```
4. Reapply the CRDs
```helmfile -e dev -l app=karpenter,tier=crd sync```
5. Reapply the Karpenter Main
```helmfile -e dev -l app=karpenter,tier=main apply```
6. Reapply the Karpenter Nodepools
```helmfile -e dev -l app=karpenter,tier=nodepool apply```

