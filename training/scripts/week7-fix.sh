#!/usr/bin/env bash
# Week 7 fix: restore the celery send worker scripts.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace_all "$CHARTS/notify-celery/values.yaml" \
  'run_celery_send_email_missing.sh' 'run_celery_send_email.sh'
replace_all "$CHARTS/notify-celery/values.yaml" \
  'run_celery_send_sms_missing.sh' 'run_celery_send_sms.sh'

deploy "app=notify-celery"
echo "Week 7 fix applied."
