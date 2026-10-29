#!/usr/bin/env bash
# Week 3: notify-api memory is far too low, so pods are OOMKilled.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

# The override file wins over charts/notify-api/values.yaml, so the break goes here.
replace "$OVERRIDES/api.yaml.gotmpl" \
  '    memory: {{ if eq .Environment.Name "production" }} "1000Mi" {{ else if eq .Environment.Name "staging" }} "1000Mi" {{ else }} "1000Mi" {{ end }}' \
  '    memory: "50Mi"'
replace "$OVERRIDES/api.yaml.gotmpl" \
  '    memory: {{ if eq .Environment.Name "production" }} "2000Mi" {{ else if eq .Environment.Name "staging" }} "2000Mi" {{ else }} "2000Mi" {{ end }}' \
  '    memory: "64Mi"'

deploy "app=notify-api"
echo "Week 3 break applied."
