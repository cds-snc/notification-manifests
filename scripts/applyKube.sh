#!/bin/bash

### This script will attempt to apply kustomize for a given environment, and retry up to 5 times on failure.
### This is primarily required for fresh environments and new app installs that have CRDs and Webhooks.
### Kustomize does not have a mechanism to wait for resources to become "ready" before proceeding

retryCount=0
workDir=$1
kubeConfig=$2
pushd $workDir
until [ "$retryCount" -ge 5 ]
do
   kubectl apply -k . $kubeConfig  && break  
   retryCount=$((retryCount+1)) 
   sleep 10
done
popd