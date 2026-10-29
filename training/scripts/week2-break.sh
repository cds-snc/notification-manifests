#!/usr/bin/env bash
# Week 2: notify-api gets a non-numeric GUNICORN_WORKERS and crashes at startup (CrashLoopBackOff).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$OVERRIDES/api.yaml.gotmpl" \
  'GUNICORN_WORKERS: "{{ .StateValues.API_GUNICORN_WORKERS }}"' \
  'GUNICORN_WORKERS: "not-a-number"'

deploy "app=notify-api"
echo "Week 2 break applied."
