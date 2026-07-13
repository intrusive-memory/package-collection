#!/bin/bash
# 12-xcc-testflight-workflow — For each app this repo ships, verify an Xcode
# Cloud workflow exists with a BRANCH start condition on `main` (merging to main
# builds + uploads that app to TestFlight). In the ship-app model, merging to
# main IS the TestFlight ship.
#
# Multi-app: loops every app from resolve_apps. An app with no main workflow is
# an informational skip (Xcode Cloud gates what it builds — that app simply
# doesn't ship at this stage). At least ONE app must have it, else FAIL: a repo
# must ship something to TestFlight.
#
# Reference name: "MAIN => TESTFLIGHT". Match is by start-condition shape, not
# by name. Run with --verbose to dump the workflow blobs and refine the jq.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

match_main() {
  # $1 = workflows JSON array. Echo the id of a workflow whose branch start
  # condition is exactly "main", falling back to any mention of "main".
  local wf="$1" id
  id=$(echo "$wf" | jq -r '
    .[] | select(
      [ (.attributes.branchStartCondition.source.patterns[]?.pattern // empty) ]
      | any(. == "main")
    ) | .id' 2>/dev/null | head -1)
  [ -z "$id" ] && id=$(echo "$wf" | jq -r '
    .[] | select((.attributes.branchStartCondition // {}) | tostring | test("\"main\""; "i")) | .id' 2>/dev/null | head -1)
  echo "$id"
}

# Here-string (not a pipe) so the loop runs in THIS shell and agg counters persist.
agg_reset
while IFS= read -r app; do
  [ -z "$app" ] && continue
  label=$(app_label "$app")
  appid=$(app_field "$app" appId)
  if [ -z "$appid" ]; then info "$label: no appId — skipping"; agg_add 2; continue; fi

  wf=$(xcc_workflows "$appid")
  if [ "$(echo "$wf" | jq 'length' 2>/dev/null || echo 0)" = "0" ]; then
    info "$label: no workflows configured"; agg_add 2; continue
  fi
  [ "$CHECK_VERBOSE" = "1" ] && echo "$wf" | jq --arg a "$label" '.[] | {app:$a, id, name: .attributes.name, branchStartCondition: .attributes.branchStartCondition}' >&2

  id=$(match_main "$wf")
  if [ -n "$id" ]; then
    name=$(echo "$wf" | jq --arg id "$id" -r '.[] | select(.id==$id) | .attributes.name // "(unnamed)"')
    info "$label: TestFlight workflow '$name' (${id:0:12}…)"; agg_add 0
  else
    info "$label: no branch=main workflow — not shipped to TestFlight"; agg_add 2
  fi
done <<< "$(echo "$APPS" | jq -c '.[]')"

if [ "${AGG_PASS:-0}" -gt 0 ]; then
  pass "TestFlight (branch=main) workflow present for ${AGG_PASS} app(s); ${AGG_SKIP:-0} not shipped to TestFlight"
else
  fail "no app has an Xcode Cloud workflow with a branch start condition on 'main' (run with --verbose to inspect)"
fi
