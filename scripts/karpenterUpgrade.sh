#!/bin/bash

# This script is used to upgrade Karpenter when there are breaking changes
# that prevent a smooth upgrade with Helmfile.
# This should only be used if you can not smoothly upgrade with Helmfile.
# It will delete all the existing CRDs and Karpenter resources
# and then reapply the new CRDs and resources

ENVIRONMENT=$1
if [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 <environment>"
    exit 1
fi

EC2_NODE_CLASSES=$(kubectl get ec2nodeclasses.karpenter.k8s.aws | awk '{print $1}' | tail -n +2)

for NODE_CLASS in $EC2_NODE_CLASSES; do
    kubectl delete ec2nodeclass $NODE_CLASS &
    kubectl patch ec2nodeclass $NODE_CLASS -p '{"metadata":{"finalizers":null}}' --type=merge
done

NODE_CLAIMS=$(kubectl get nodeclaims.karpenter.sh | awk '{print $1}' | tail -n +2)
for NODE_CLAIM in $NODE_CLAIMS; do
    kubectl delete nodeclaim $NODE_CLAIM &
    kubectl patch nodeclaim $NODE_CLAIM -p '{"metadata":{"finalizers":null}}' --type=merge
done

NODE_POOLS=$(kubectl get nodepools.karpenter.sh | awk '{print $1}' | tail -n +2)
for NODE_POOL in $NODE_POOLS; do
    kubectl delete nodepool $NODE_POOL &
    kubectl patch nodepool $NODE_POOL -p '{"metadata":{"finalizers":null}}' --type=merge
done

kubectl delete namespace karpenter

kubectl delete crd $(kubectl get crd -n karpenter | grep karpenter | awk '{print $1}')

pushd ../helmfile
source getContext.sh
helmfile -e $ENVIRONMENT -l app=karpenter,tier=crd sync
sleep 5
helmfile -e $ENVIRONMENT -l app=karpenter,tier=main apply
sleep 5
helmfile -e $ENVIRONMENT -l app=karpenter,tier=nodepool apply
popd
