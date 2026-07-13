#!/bin/bash
# 11-gha-last-pr-passed — Verify the most recent merged development → main
# PR had no failed status checks.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v gh >/dev/null || skip "gh not installed (check 03)"
gh auth status >/dev/null 2>&1 || skip "gh not authenticated (check 04)"

LAST_PR_JSON=$(gh pr list --base main --head development --state merged --limit 1 \
  --json number,statusCheckRollup 2>/dev/null || echo "[]")

COUNT=$(echo "$LAST_PR_JSON" | jq 'length' 2>/dev/null || echo 0)
[ "$COUNT" -eq 0 ] && skip "no merged development → main PRs yet"

PR_NUM=$(echo "$LAST_PR_JSON" | jq -r '.[0].number')
FAILED=$(echo "$LAST_PR_JSON" | jq '[.[0].statusCheckRollup[]? | select(.conclusion=="FAILURE")] | length')

if [ "$FAILED" -eq 0 ]; then
  pass "last development → main PR #$PR_NUM had no failed checks"
else
  FAILED_NAMES=$(echo "$LAST_PR_JSON" | jq -r '.[0].statusCheckRollup[] | select(.conclusion=="FAILURE") | .name // .context // "?"' | tr '\n' ',' | sed 's/,$//')
  fail "last development → main PR #$PR_NUM had $FAILED failed check(s): $FAILED_NAMES"
fi
