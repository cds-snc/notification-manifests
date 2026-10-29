#!/usr/bin/env bash
# Week 2 fix: restore GUNICORN_WORKERS.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$OVERRIDES/api.yaml.gotmpl" \
  'GUNICORN_WORKERS: "not-a-number"' \
  'GUNICORN_WORKERS: "{{ .StateValues.API_GUNICORN_WORKERS }}"'

deploy "app=notify-api"
echo "Week 2 fix applied."
