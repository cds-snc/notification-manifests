#!/usr/bin/env bash
# Shared helpers for the bootcamp break/fix scripts. Source this file; do not run it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELMFILE_DIR="$REPO_ROOT/helmfile"
CHARTS="$HELMFILE_DIR/charts"
OVERRIDES="$HELMFILE_DIR/overrides/notify"

die() {
  echo "error: $*" >&2
  exit 1
}

# Sets ENV_NAME and APPLY from the command line.
parse_args() {
  APPLY=true
  ENV_NAME=""
  for arg in "$@"; do
    case "$arg" in
      --no-apply) APPLY=false ;;
      -h | --help)
        echo "usage: $(basename "$0") <env> [--no-apply]"
        exit 0
        ;;
      *) ENV_NAME="$arg" ;;
    esac
  done
  if [[ "$APPLY" == true && -z "$ENV_NAME" ]]; then
    die "usage: $(basename "$0") <env> [--no-apply]"
  fi
  [[ "$ENV_NAME" != "production" ]] || die "refusing to run against production"
}

# replace <file> <old> <new>: replace the first occurrence of a single-line literal.
replace() { _replace first "$@"; }

# replace_all <file> <old> <new>: replace every occurrence of a single-line literal.
replace_all() { _replace all "$@"; }

_replace() {
  local mode=$1 file=$2 old=$3 new=$4
  grep -qF -- "$old" "$file" || die "pattern not found in ${file#"$REPO_ROOT"/} (already applied?): $old"
  if [[ "$mode" == all ]]; then
    OLD="$old" NEW="$new" perl -0pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$file"
  else
    OLD="$old" NEW="$new" perl -0pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/' "$file"
  fi
}

# replace_re <file> <perl-regex> <new>: multiline regex; use \K to keep a prefix.
replace_re() {
  local file=$1 regex=$2 new=$3 before
  before="$(cksum <"$file")"
  RE="$regex" NEW="$new" perl -0pi -e 's/$ENV{RE}/$ENV{NEW}/m' "$file"
  [[ "$before" != "$(cksum <"$file")" ]] || die "pattern not found in ${file#"$REPO_ROOT"/} (already applied?)"
}

# The readiness probe path is hardcoded in the notify-api templates, not in values.yaml.
api_readiness_path() {
  local old=$1 new=$2 f
  for f in deployment.yaml deployment-spot.yaml; do
    replace "$CHARTS/notify-api/templates/$f" "path: $old" "path: $new"
  done
}

# deploy <helmfile-selector>
deploy() {
  local selector=$1
  if [[ "$APPLY" == true ]]; then
    (cd "$HELMFILE_DIR" && helmfile -e "$ENV_NAME" apply -l "$selector")
  else
    echo "Skipped deploy. Run: cd helmfile && helmfile -e <env> apply -l '$selector'"
  fi
}
