#!/usr/bin/env bash
# Week 8 fix: revert all three breaks.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$OVERRIDES/admin.yaml.gotmpl" \
  'tag: "v9.9.9-incident-drill"' \
  'tag: "{{ .StateValues.ADMIN_DOCKER_TAG }}"'

api_readiness_path '/_broken_for_drill' '/_status?simple=true'

replace_re "$OVERRIDES/celery.yaml.gotmpl" \
  '^  beat:\n    deployment:\n(?:      [^\n]*\n){2}      replicas: \K0$' \
  '{{ if eq .Environment.Name "production" }} 1 {{ else if eq .Environment.Name "staging" }} 1 {{ else }} 1 {{ end }}'

deploy "app in (notify-admin,notify-api,notify-celery)"
echo "Week 8 fix applied."
