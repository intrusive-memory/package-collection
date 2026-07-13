#!/bin/bash
# 15-xcc-pr-gate-workflow — (informational) For each app shipped from this repo,
# look for an Xcode Cloud workflow with a PULL-REQUEST start condition targeting
# `main`.
#
# IMPORTANT: this is a *build* gate only — it compiles/archives the app on a PR
# so build breaks surface early. It is NOT a test gate. Xcode Cloud never runs
# the test suite in this model (its runners are Intel; the suite has
# Apple-Silicon-specific tests). All test gating lives in GitHub CI (checks
# 09/10/20/21). This check is purely informational and SKIPs when absent.
#
# Reference name: "DEVELOPMENT => MAIN".
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

match_pr_main() {
  local wf="$1" id
  id=$(echo "$wf" | jq -r '
    .[] | select(
      (.attributes.pullRequestStartCondition // empty) != null
      and ((.attributes.pullRequestStartCondition | tostring) | test("\"main\""; "i"))
    ) | .id' 2>/dev/null | head -1)
  [ -z "$id" ] && id=$(echo "$wf" | jq -r '
    .[] | select((.attributes.pullRequestStartCondition // empty) != null) | .id' 2>/dev/null | head -1)
  echo "$id"
}

agg_reset
while IFS= read -r app; do
  [ -z "$app" ] && continue
  label=$(app_label "$app")
  appid=$(app_field "$app" appId)
  if [ -z "$appid" ]; then info "$label: no appId"; agg_add 2; continue; fi

  wf=$(xcc_workflows "$appid")
  if [ "$(echo "$wf" | jq 'length' 2>/dev/null || echo 0)" = "0" ]; then info "$label: no workflows configured"; agg_add 2; continue; fi
  [ "$CHECK_VERBOSE" = "1" ] && echo "$wf" | jq --arg a "$label" '.[] | {app:$a, id, name: .attributes.name, pullRequestStartCondition: .attributes.pullRequestStartCondition}' >&2

  id=$(match_pr_main "$wf")
  if [ -n "$id" ]; then
    name=$(echo "$wf" | jq --arg id "$id" -r '.[] | select(.id==$id) | .attributes.name // "(unnamed)"')
    info "$label: PR build-gate '$name' (${id:0:12}…)"; agg_add 0
  else
    info "$label: no Xcode Cloud PR build-gate (optional)"; agg_add 2
  fi
done <<< "$(echo "$APPS" | jq -c '.[]')"

if [ "${AGG_PASS:-0}" -gt 0 ]; then
  pass "Xcode Cloud PR build-gate (pull-request → main) present for ${AGG_PASS} app(s) — build gate only, not a test gate"
else
  skip "no Xcode Cloud PR build-gate (optional — GitHub CI owns all test gating)"
fi
