#!/usr/bin/env bash
# Week 6 fix: restore the SecretProviderClass object name.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$CHARTS/notify-api/values.yaml" \
  '- objectName: INTERNAL_DNS_KEY_BASE64_DOES_NOT_EXIST' \
  '- objectName: INTERNAL_DNS_KEY_BASE64'

deploy "app=notify-api"
echo "Week 6 fix applied."
