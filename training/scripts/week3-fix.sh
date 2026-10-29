#!/usr/bin/env bash
# Week 3 fix: restore notify-api memory request and limit.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$OVERRIDES/api.yaml.gotmpl" \
  '    memory: "50Mi"' \
  '    memory: {{ if eq .Environment.Name "production" }} "1000Mi" {{ else if eq .Environment.Name "staging" }} "1000Mi" {{ else }} "1000Mi" {{ end }}'
replace "$OVERRIDES/api.yaml.gotmpl" \
  '    memory: "64Mi"' \
  '    memory: {{ if eq .Environment.Name "production" }} "2000Mi" {{ else if eq .Environment.Name "staging" }} "2000Mi" {{ else }} "2000Mi" {{ end }}'

deploy "app=notify-api"
echo "Week 3 fix applied."
