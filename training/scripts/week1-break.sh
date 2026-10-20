#!/usr/bin/env bash
# Week 1: notify-admin is pointed at an image tag that does not exist (ImagePullBackOff).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$OVERRIDES/admin.yaml.gotmpl" \
  'tag: "{{ .StateValues.ADMIN_DOCKER_TAG }}"' \
  'tag: "v9.9.9-does-not-exist"'

deploy "app=notify-admin"
echo "Week 1 break applied."
