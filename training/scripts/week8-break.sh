#!/usr/bin/env bash
# Week 8: three simultaneous breaks (admin bad image, api unready, celery beat scaled to 0).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

# Break 1: admin ImagePullBackOff
replace "$OVERRIDES/admin.yaml.gotmpl" \
  'tag: "{{ .StateValues.ADMIN_DOCKER_TAG }}"' \
  'tag: "v9.9.9-incident-drill"'

# Break 2: api readiness probe failing
api_readiness_path '/_status?simple=true' '/_broken_for_drill'

# Break 3: celery beat has zero replicas
replace_re "$OVERRIDES/celery.yaml.gotmpl" \
  '^  beat:\n    deployment:\n(?:      [^\n]*\n){2}      replicas: \K[^\n]*' \
  '0'

deploy "app in (notify-admin,notify-api,notify-celery)"
echo "Week 8 break applied."
