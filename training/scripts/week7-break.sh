#!/usr/bin/env bash
# Week 7: email and SMS send workers point at scripts that do not exist, so API is healthy but nothing is sent.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

# Applies to both the static and burst send workers.
replace_all "$CHARTS/notify-celery/values.yaml" \
  'run_celery_send_email.sh' 'run_celery_send_email_missing.sh'
replace_all "$CHARTS/notify-celery/values.yaml" \
  'run_celery_send_sms.sh' 'run_celery_send_sms_missing.sh'

deploy "app=notify-celery"
echo "Week 7 break applied."
