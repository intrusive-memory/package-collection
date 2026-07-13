#!/bin/bash
# 16-xcc-recent-main-run — For each app shipped from this repo, verify the most
# recent commit on `origin/main` has a corresponding Xcode Cloud build run from
# that app's TestFlight (branch=main) workflow. Confirms the latest main push
# actually shipped each app to TestFlight.
#
# Multi-app: loops resolve_apps. An app with no main workflow → informational
# skip. An app whose main workflow has no run for the latest main commit → FAIL.
#
# Match strategy per app:
#   1. Resolve the TestFlight workflow id (branch start condition on main).
#   2. Read the latest commit SHA on origin/main (repo-wide).
#   3. Find a run sourced from that commit (SHA), falling back to branch name.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

git fetch origin main --quiet 2>/dev/null || true
LAST_MAIN_SHA=$(git ls-remote origin main 2>/dev/null | awk '{print $1}')
[ -z "$LAST_MAIN_SHA" ] && skip "could not resolve origin/main commit"
SHORT_SHA="${LAST_MAIN_SHA:0:7}"

agg_reset
while IFS= read -r app; do
  [ -z "$app" ] && continue
  label=$(app_label "$app")
  appid=$(app_field "$app" appId)
  if [ -z "$appid" ]; then info "$label: no appId"; agg_add 2; continue; fi

  wf=$(xcc_workflows "$appid")
  main_wf=$(echo "$wf" | jq -r '
    .[] | select((.attributes.branchStartCondition // {}) | tostring | test("\"main\""; "i")) | .id' | head -1)
  if [ -z "$main_wf" ]; then info "$label: no branch=main workflow (check 12)"; agg_add 2; continue; fi

  runs=$(asc xcode-cloud build-runs list --workflow-id "$main_wf" --output json --limit 30 --sort "-number" 2>/dev/null | jq '.data // .' 2>/dev/null || echo "[]")
  if [ "$(echo "$runs" | jq 'length' 2>/dev/null || echo 0)" = "0" ]; then
    info "$label: TestFlight workflow has zero build runs"; agg_add 1; continue
  fi
  [ "$CHECK_VERBOSE" = "1" ] && echo "$runs" | jq --arg a "$label" '.[] | {app:$a, number: .attributes.number, sha: .attributes.sourceCommit.commitSha, branch: .attributes.sourceBranchOrTag.name}' >&2

  matched=$(echo "$runs" | jq --arg full "$LAST_MAIN_SHA" --arg short "$SHORT_SHA" -r '
    .[] | select(
      (.attributes.sourceCommit.commitSha // "") == $full or
      ((.attributes.sourceCommit.commitSha // "") | startswith($short))
    ) | .attributes.number' | head -1)
  if [ -z "$matched" ]; then
    matched=$(echo "$runs" | jq -r '.[] | select((.attributes.sourceBranchOrTag.name // "") == "main") | .attributes.number' | head -1)
    [ -n "$matched" ] && info "$label: matched by branch name (no SHA match for $SHORT_SHA)"
  fi

  if [ -n "$matched" ]; then
    info "$label: TestFlight run #$matched for recent main"; agg_add 0
  else
    info "$label: no recent build run sourced from main"; agg_add 1
  fi
done <<< "$(echo "$APPS" | jq -c '.[]')"

agg_finish "TestFlight build run(s) for recent main (${SHORT_SHA})"
