#!/usr/bin/env bash
# Week 5: impossible PDB minAvailable plus a trivial env change to trigger a rollout.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

# The override file wins over charts/notify-api/values.yaml, so the break goes here.
replace "$OVERRIDES/api.yaml.gotmpl" '  minAvailable: 2' '  minAvailable: 99'
replace "$OVERRIDES/api.yaml.gotmpl" \
  'HELM_TEST_API: "HELM-IS-RADICAL!-API"' \
  'HELM_TEST_API: "HELM-IS-RADICAL!-API-V2"'

deploy "app=notify-api"
echo "Week 5 break applied."
