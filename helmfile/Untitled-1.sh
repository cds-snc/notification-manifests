#!/bin/bash

DEPLOYMENT_NAME="notify-api"
NAMESPACE="notification-canada-ca"
env_vars=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].env[*]}')
secrets=$(kubectl get secret $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key)=\(.value | @base64d)"')
params="####### ENVIRONMENT VARIABLES ############\n"
for env_var in $(echo "$env_vars" | jq -r 'select(.value != null and .value != "") | .name + "=" + .value'); do
  params="$params\n$env_var"
done
params=$(echo -e "$params" | sort)
params="$params\n######### SECRET VARIABLES #########"
params="$params\n$secrets"
echo $params


