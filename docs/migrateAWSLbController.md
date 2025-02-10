# Migrate AWS Load Balancer Controler to Helm
## DOWNTIME REQUIRED
This procedure requires downtime due to having to delete target group bindings


## Steps

1. Delete target group bindings
```kubectl delete targetGroupbindings $(kubectl get targetgroupbindings -n notification-canada-ca | awk '{print $1}') -n notification-canada-ca```
2. Delete aws lb controller
```kubectl delete -f base/notify-system/alb-ingress-controller.yaml```
3. Apply CRDs
```helmfile -e <environment> -l step=0 apply```
4. Apply AWS Load Balancer Controller
```helmfile -e <environment> -l app=aws-lb-controller apply```
5. Re-sync Notify to re-create targetgroupbindings
```helmfile -e <environment> -l step=5 sync```