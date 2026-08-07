#!/bin/bash

set -euo pipefail

NAMESPACE="notification-canada-ca"
params_buffer=""

get_env_and_secrets() {
    local deployment_name=$1
    local secret_name=${2:-$deployment_name}

    while IFS= read -r env_var; do
        [[ -n "$env_var" ]] && params_buffer+="$env_var"$'\n'
    done < <(kubectl get deployment "$deployment_name" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[*].env[*]}' \
        | jq -r 'select(.value != null and .value != "") | .name + "=" + .value')

    while IFS= read -r secret_var; do
        [[ -n "$secret_var" ]] && params_buffer+="$secret_var"$'\n'
    done < <(kubectl get secret "$secret_name" -n "$NAMESPACE" -o jsonpath='{.data}' \
        | jq -r 'to_entries[] | "\(.key)=\(.value | @base64d)"')
}

# API
params_buffer=""
get_env_and_secrets "notify-api"
params_api=$(printf '%s' "$params_buffer" | sed '/^$/d' | sort -u)
aws ssm get-parameters --region ca-central-1 --with-decryption --names ENVIRONMENT_VARIABLES --query 'Parameters[*].Value' --output text > .previous.env
aws ssm put-parameter --region ca-central-1 --name ENVIRONMENT_VARIABLES --type SecureString --key-id alias/aws/ssm --value "$params_api" --tier "Intelligent-Tiering" --overwrite
aws ssm get-parameters --region ca-central-1 --with-decryption --names ENVIRONMENT_VARIABLES --query 'Parameters[*].Value' --output text > .new.env
DIFF_OUTPUT=$(diff -B .new.env .previous.env || true)
DIFF=$(printf '%s' "$DIFF_OUTPUT" | wc -l | tr -d ' ')
echo "DIFF=$DIFF"
export DIFF

# ADMIN
params_buffer=""
get_env_and_secrets "notify-admin"
params_admin=$(printf '%s' "$params_buffer" | sed '/^$/d' | sort -u)
aws ssm put-parameter --region ca-central-1 --name ENVIRONMENT_VARIABLES_ADMIN --type SecureString --key-id alias/aws/ssm --value "$params_admin" --tier "Intelligent-Tiering" --overwrite
