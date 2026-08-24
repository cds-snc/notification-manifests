#!/usr/bin/env zsh
# Re-signs every commit reachable from HEAD but not from any of the given "exclude" refs,
# preserving trees, messages, authorship, dates, and merge topology (unlike `rebase --exec`,
# which flattens merges). Only commits truly unique to this branch are touched -- commits
# already shared with/published on other refs (e.g. main merged in) are left untouched.
#
# Usage: resign-commits.sh <exclude-ref> [<exclude-ref> ...]
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <exclude-ref> [<exclude-ref> ...]" >&2
  exit 1
fi

BRANCH=$(git symbolic-ref --short HEAD)
OLD_HEAD=$(git rev-parse HEAD)

typeset -A old_to_new

exclude_args=()
for ref in "$@"; do
  exclude_args+=("^$ref")
done

commits=(${(f)"$(git rev-list --topo-order --reverse HEAD "${exclude_args[@]}")"})

for old in "${commits[@]}"; do
  parents=(${(f)"$(git show -s --format='%P' "$old")"})
  parents=(${=parents})

  parent_args=()
  for p in "${parents[@]}"; do
    if [[ -n "${old_to_new[$p]:-}" ]]; then
      parent_args+=(-p "${old_to_new[$p]}")
    else
      parent_args+=(-p "$p")
    fi
  done

  tree=$(git show -s --format='%T' "$old")
  author_name=$(git show -s --format='%an' "$old")
  author_email=$(git show -s --format='%ae' "$old")
  author_date=$(git show -s --format='%ad' --date=raw "$old")
  committer_name=$(git show -s --format='%cn' "$old")
  committer_email=$(git show -s --format='%ce' "$old")
  committer_date=$(git show -s --format='%cd' --date=raw "$old")
  message=$(git show -s --format='%B' "$old")

  new=$(GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" GIT_AUTHOR_DATE="$author_date" \
        GIT_COMMITTER_NAME="$committer_name" GIT_COMMITTER_EMAIL="$committer_email" GIT_COMMITTER_DATE="$committer_date" \
        git commit-tree -S "$tree" "${parent_args[@]}" -m "$message")

  old_to_new[$old]=$new
  echo "signed $old -> $new"
done

new_head="${old_to_new[$OLD_HEAD]}"
git update-ref "refs/heads/$BRANCH" "$new_head"

echo ""
echo "Done. Branch '$BRANCH' moved from $OLD_HEAD to $new_head"
echo "Old tip is still reachable via: git reflog"
