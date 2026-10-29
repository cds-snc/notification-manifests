#!/usr/bin/env bash
# Week 4: notify-api readiness probe hits a 404 path, so pods stay Running but 0/1 Ready.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
parse_args "$@"

api_readiness_path '/_status?simple=true' '/_this_path_does_not_exist'

deploy "app=notify-api"
echo "Week 4 break applied."
