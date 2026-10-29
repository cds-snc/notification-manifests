#!/usr/bin/env bash
# Week 6: SecretProviderClass references a secret that does not exist (pods stuck in ContainerCreating).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

# Leading "- " skips the matching objectName under secretObjects.
replace "$CHARTS/notify-api/values.yaml" \
  '- objectName: INTERNAL_DNS_KEY_BASE64' \
  '- objectName: INTERNAL_DNS_KEY_BASE64_DOES_NOT_EXIST'

deploy "app=notify-api"
echo "Week 6 break applied."
