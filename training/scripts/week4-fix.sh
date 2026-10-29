#!/usr/bin/env bash
# Week 4 fix: restore the notify-api readiness probe path.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

api_readiness_path '/_this_path_does_not_exist' '/_status?simple=true'

deploy "app=notify-api"
echo "Week 4 fix applied."
