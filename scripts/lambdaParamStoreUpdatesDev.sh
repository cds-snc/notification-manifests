#!/bin/bash

NAMESPACE="notification-canada-ca"
get_env_and_secrets() {
local DEPLOYMENT_NAME=$1
local SECRET_NAME=${2:-$DEPLOYMENT_NAME}
env_vars=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].env[*]}')
secrets=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key)=\(.value | @base64d)"')
for env_var in $(echo "$env_vars" | jq -r 'select(.value != null and .value != "") | .name + "=" + .value'); do
    params="$params\n$env_var"
done
params="$params\n$secrets"
}
params=""
# API
get_env_and_secrets "notify-api"
params=$(echo -e "$params" | sort -u)
aws ssm get-parameters --region ca-central-1 --with-decryption --names ENVIRONMENT_VARIABLES --query 'Parameters[*].Value' --output text > .previous.env
aws ssm put-parameter --region ca-central-1 --name ENVIRONMENT_VARIABLES --type SecureString --key-id alias/aws/ssm --value "$params" --tier "Intelligent-Tiering" --overwrite
aws ssm get-parameters --region ca-central-1 --with-decryption --names ENVIRONMENT_VARIABLES --query 'Parameters[*].Value' --output text > .new.env
DIFF=$(diff -B .new.env .previous.env | wc -l | tr -d ' ')
echo "DIFF=$DIFF"
export DIFF
params=""
# ADMIN
get_env_and_secrets "notify-admin"
params=$(echo -e "$params" | sort -u)
aws ssm put-parameter --region ca-central-1 --name ENVIRONMENT_VARIABLES_ADMIN --type SecureString --key-id alias/aws/ssm --value "$params" --tier "Intelligent-Tiering" --overwrite