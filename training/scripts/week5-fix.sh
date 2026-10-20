#!/usr/bin/env bash
# Week 5 fix: restore the PDB and the env var, then redeploy.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$OVERRIDES/api.yaml.gotmpl" '  minAvailable: 99' '  minAvailable: 2'
replace "$OVERRIDES/api.yaml.gotmpl" \
  'HELM_TEST_API: "HELM-IS-RADICAL!-API-V2"' \
  'HELM_TEST_API: "HELM-IS-RADICAL!-API"'

deploy "app=notify-api"
echo "Week 5 fix applied."
