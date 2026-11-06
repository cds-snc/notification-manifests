#!/usr/bin/env bash
set -euo pipefail
umask 077

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
temporary=$(mktemp -d)
cleanup() {
  for directory in "$temporary/review" "$temporary/failed-review"; do
    if [[ -d "$directory" ]]; then
      rm -f "$directory/results.jsonl" "$directory/errors.log" \
        "$directory/report.json" "$directory/validation.log" "$directory/hashed.jsonl"
      rmdir "$directory"
    fi
  done
  rm -f "$temporary/results.jsonl" "$temporary/arguments" "$temporary/summary" \
    "$temporary/event.json" "$temporary/output" "$temporary/bin/docker" "$temporary/bin/trufflehog" \
    "$temporary/repo/.github/scripts/scan-secrets.sh" \
    "$temporary/repo/.github/trufflehog-baseline.json"
  rmdir "$temporary/repo/.github/scripts" "$temporary/repo/.github" \
    "$temporary/repo" "$temporary/bin" "$temporary"
}
trap cleanup EXIT
mkdir -p "$temporary/repo/.github/scripts" "$temporary/bin"
cp "$root/.github/scripts/scan-secrets.sh" "$temporary/repo/.github/scripts/"
cp "$root/.github/trufflehog-baseline.json" "$temporary/repo/.github/"
export FIXTURE="$temporary/results.jsonl"
export ARGUMENTS="$temporary/arguments"
export GITHUB_STEP_SUMMARY="$temporary/summary"
export GITHUB_EVENT_PATH="$temporary/event.json"
export GITHUB_EVENT_NAME=workflow_dispatch
export GITHUB_SHA=1111111111111111111111111111111111111111
export GITHUB_ACTIONS=false
export PATH="$temporary/bin:$PATH"

cat > "$temporary/bin/docker" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "trufflehog 3.99.7"
  exit 0
fi
printf '%s\n' "$@" > "$ARGUMENTS"
cat "$FIXTURE"
echo '{"msg":"finished scanning","chunks":123,"bytes":456,"unverified_secrets":1,"trufflehog_version":"3.99.7"}' >&2
exit "${SCANNER_EXIT:-0}"
SH
chmod +x "$temporary/bin/docker"
cp "$temporary/bin/docker" "$temporary/bin/trufflehog"

finding='{
  "DetectorName": "Github",
  "Verified": false,
  "Raw": "TEST_REVIEWED_PLACEHOLDER",
  "SourceMetadata": {"Data": {"Git": {
    "commit": "1111111111111111111111111111111111111111",
    "file": "fixture.yml",
    "line": 67
  }}}
}'
finding=$(printf '%s\n' "$finding" | jq -c .)

check() {
  local expected=$1
  local name=$2
  shift 2
  local status=0
  bash "$temporary/repo/.github/scripts/scan-secrets.sh" "$@" > "$temporary/output" 2>&1 || status=$?
  if [[ "$status" != "$expected" ]]; then
    echo "FAIL: $name (expected $expected, got $status)" >&2
    cat "$temporary/output" >&2
    exit 1
  fi
  if grep -q 'TEST_REVIEWED_PLACEHOLDER\|TEST_SENSITIVE_VALUE' "$temporary/output"; then
    echo "FAIL: detected value leaked to output" >&2
    exit 1
  fi
  echo "PASS: $name"
}

: > "$FIXTURE"
check 0 "clean scan"
grep -qx 'ghcr.io/trufflesecurity/trufflehog@sha256:0d003fc3abc4e1565eca8462b992001314de51451e96e3c44de80d116794d5d1' "$ARGUMENTS"
grep -qx -- '--no-verification' "$ARGUMENTS"
grep -qx -- '--no-update' "$ARGUMENTS"
grep -qx -- '--fail-on-scan-errors' "$ARGUMENTS"
if grep -qxE -- '--since-commit|--branch|--fail' "$ARGUMENTS"; then
  echo "FAIL: manual scan must include all refs and evaluate findings itself" >&2
  exit 1
fi

printf '%s\n' "$finding" > "$FIXTURE"
check 1 "new finding with repository baseline"
placeholder_hash=$(printf '%s' "TEST_REVIEWED_PLACEHOLDER" | node -e '
  const crypto = require("node:crypto");
  const fs = require("node:fs");
  console.log(crypto.createHash("sha256").update(fs.readFileSync(0)).digest("hex"));
')
jq -n --arg hash "$placeholder_hash" '[{
  detector: "Github",
  commit: "1111111111111111111111111111111111111111",
  file: "fixture.yml",
  raw_sha256: $hash,
  reason: "Synthetic non-secret regression fixture."
}]' > "$temporary/repo/.github/trufflehog-baseline.json"
check 0 "exact historical false positive"
grep -q '"baselined": 1' "$temporary/output"
grep -q 'Reviewed baseline exceptions: 1' "$GITHUB_STEP_SUMMARY"
grep -q '"finding":1' "$temporary/output"
grep -q '"chunks":123' "$temporary/output"

check 0 "native local scan with private retained output" --native --output-dir "$temporary/review"
cmp "$FIXTURE" "$temporary/review/results.jsonl"
jq -e '.details[0].baselined == true' "$temporary/review/report.json" > /dev/null
test "$(stat -f '%Lp' "$temporary/review" 2>/dev/null || stat -c '%a' "$temporary/review")" = 700
check 1 "existing output directory rejected" --output-dir "$temporary/review"
GITHUB_ACTIONS=true check 1 "raw retention forbidden in Actions" --output-dir "$temporary/forbidden"
GITHUB_ACTIONS=true check 1 "native scanner forbidden in Actions" --native
check 1 "missing output directory argument" --output-dir
check 1 "unknown option rejected" --unknown
SCANNER_EXIT=125 check 125 "failed scan diagnostics retained" --output-dir "$temporary/failed-review"
test -s "$temporary/failed-review/errors.log"
test -s "$temporary/failed-review/results.jsonl"

for change in \
  '.DetectorName = "Box"' \
  '.Raw = "TEST_SENSITIVE_VALUE"' \
  '.SourceMetadata.Data.Git.commit = "2222222222222222222222222222222222222222"' \
  '.SourceMetadata.Data.Git.file = "other.yml"' \
  '.Verified = true'; do
  printf '%s\n' "$finding" | jq -c "$change" > "$FIXTURE"
  check 1 "nonmatching finding: $change"
done

jq '.[0].commit = "*"' "$temporary/repo/.github/trufflehog-baseline.json" > "$temporary/modified.jsonl"
mv "$temporary/modified.jsonl" "$temporary/repo/.github/trufflehog-baseline.json"
for commit in \
  1111111111111111111111111111111111111111 \
  2222222222222222222222222222222222222222; do
  printf '%s\n' "$finding" | jq -c --arg commit "$commit" '
    .SourceMetadata.Data.Git.commit = $commit
  ' > "$FIXTURE"
  check 0 "exact placeholder allowed across commits: $commit"
done
for change in \
  '.DetectorName = "Box"' \
  '.Raw = "TEST_SENSITIVE_VALUE"' \
  '.SourceMetadata.Data.Git.file = "other.yml"' \
  '.Verified = true'; do
  printf '%s\n' "$finding" | jq -c "$change" > "$FIXTURE"
  check 1 "wildcard does not broaden other fields: $change"
done

printf '%s\n' "$finding" > "$FIXTURE"
printf '%s\n' "$finding" | jq -c '.Raw = "TEST_SENSITIVE_VALUE"' >> "$FIXTURE"
check 1 "mixed baseline and new findings"

printf '%s\n' 'not valid JSON TEST_SENSITIVE_VALUE' > "$FIXTURE"
check 1 "malformed scanner output"
printf '%s\n' '{}' > "$FIXTURE"
check 1 "missing finding metadata"
printf '%s\n' "$finding" | jq -c 'del(.SourceMetadata)' > "$FIXTURE"
check 1 "missing source metadata"
printf '%s\n' "$finding" > "$FIXTURE"
SCANNER_EXIT=125 check 125 "Docker error"
SCANNER_EXIT=1 check 1 "scan error despite baselined finding"
SCANNER_EXIT=183 check 183 "unexpected finding exit is not accepted"

printf '%s\n' '{"pull_request":{"base":{"sha":"base-commit"},"head":{"sha":"head-commit"}}}' > "$GITHUB_EVENT_PATH"
GITHUB_EVENT_NAME=pull_request check 0 "PR scan range"
grep -qx 'base-commit' "$ARGUMENTS"
grep -qx 'head-commit' "$ARGUMENTS"
printf '%s\n' '{"before":"before-commit","after":"after-commit"}' > "$GITHUB_EVENT_PATH"
GITHUB_EVENT_NAME=push check 0 "push scan range"
grep -qx 'before-commit' "$ARGUMENTS"
grep -qx 'after-commit' "$ARGUMENTS"
printf '%s\n' '{"before":"0000000000000000000000000000000000000000","after":"after-commit"}' > "$GITHUB_EVENT_PATH"
GITHUB_EVENT_NAME=push check 0 "new branch scans full history"
if grep -qx -- '--since-commit' "$ARGUMENTS"; then
  echo "FAIL: new branch scan must include full history" >&2
  exit 1
fi
for event in schedule repository_dispatch local; do
  GITHUB_EVENT_NAME=$event check 0 "$event scans all refs"
  if grep -qxE -- '--branch|--since-commit' "$ARGUMENTS"; then
    echo "FAIL: $event scan must include all refs" >&2
    exit 1
  fi
done
GITHUB_EVENT_NAME=unsupported check 1 "unsupported event rejected"
printf '%s\n' '{"before":"same","after":"same"}' > "$GITHUB_EVENT_PATH"
GITHUB_EVENT_NAME=push check 1 "empty commit range rejected"
printf '%s\n' '{}' > "$GITHUB_EVENT_PATH"
GITHUB_EVENT_NAME=pull_request check 1 "missing PR range rejected"

for baseline in '{}' '[{}]' '[{"detector":"Github","commit":"*","file":"fixture.yml","raw_sha256":"invalid","reason":"Synthetic fixture"}]'; do
  printf '%s\n' "$baseline" > "$temporary/repo/.github/trufflehog-baseline.json"
  check 1 "invalid baseline rejected"
done
