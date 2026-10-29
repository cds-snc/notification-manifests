#!/usr/bin/env bash
# Week 1 fix: restore the notify-admin image tag.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

replace "$OVERRIDES/admin.yaml.gotmpl" \
  'tag: "v9.9.9-does-not-exist"' \
  'tag: "{{ .StateValues.ADMIN_DOCKER_TAG }}"'

deploy "app=notify-admin"
echo "Week 1 fix applied."
