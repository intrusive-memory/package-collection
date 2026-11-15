#!/bin/bash
# 18-tf-build-from-main-distributed — For each app shipped from this repo, verify
# the most recent build produced by that app's TestFlight (branch=main) workflow
# landed in TestFlight and is attached to at least one beta group.
#
# Multi-app: loops resolve_apps. An app with no main workflow / no completed run
# → informational skip. An app whose latest build reached no beta group → FAIL.
#
# Match strategy per app: latest completed run from the TestFlight workflow →
# its produced build → the beta groups the build is attached to.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

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

  runs=$(asc xcode-cloud build-runs list --workflow-id "$main_wf" --output json --limit 10 --sort "-number" 2>/dev/null | jq '.data // .' 2>/dev/null || echo "[]")
  latest_run=$(echo "$runs" | jq -r '.[] | select((.attributes.executionProgress // "") == "COMPLETE") | .id' | head -1)
  if [ -z "$latest_run" ]; then info "$label: TestFlight workflow has no completed runs yet"; agg_add 2; continue; fi

  builds=$(asc xcode-cloud build-runs builds --run-id "$latest_run" --output json 2>/dev/null | jq '.data // .' 2>/dev/null || echo "[]")
  build_id=$(echo "$builds" | jq -r '.[0].id // empty')
  if [ -z "$build_id" ]; then info "$label: run $latest_run completed but produced no build"; agg_add 1; continue; fi
  info "$label: build id $build_id"

  # Enumerate beta groups for the build. The reliable form is the builds list
  # with the betaGroups relationship included — `asc testflight groups list
  # --build-id` returns nothing for groups that auto-receive every build
  # (hasAccessToAllBuilds) even though the relationship exists.
  groups=""
  inc=$(asc builds list --app "$appid" --include betaGroups --paginate --output json 2>/dev/null \
    | jq -c --arg id "$build_id" '(.data // []) | map(select(.id == $id)) | .[0].relationships.betaGroups.data // empty' 2>/dev/null)
  if [ -n "$inc" ] && echo "$inc" | jq -e 'type == "array"' >/dev/null 2>&1; then groups="$inc"; fi
  [ -n "$groups" ] || for cmd in \
    "asc testflight groups list --build-id $build_id --output json" \
    "asc builds beta-groups --id $build_id --output json" \
    "asc beta-groups list --build-id $build_id --output json" \
    "asc builds view --id $build_id --output json"
  do
    out=$(eval "$cmd" 2>/dev/null) || continue
    norm=$(echo "$out" | jq '.data // .' 2>/dev/null) || continue
    if echo "$norm" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then groups="$norm"; break; fi
    if echo "$norm" | jq -e '.relationships.betaGroups.data | length > 0' >/dev/null 2>&1; then groups=$(echo "$norm" | jq '.relationships.betaGroups.data'); break; fi
  done

  if [ -z "$groups" ]; then info "$label: could not enumerate beta groups for $build_id"; agg_add 2; continue; fi
  gcount=$(echo "$groups" | jq 'length' 2>/dev/null || echo 0)
  if [ "$gcount" -ge 1 ]; then
    info "$label: build $build_id attached to $gcount TestFlight group(s)"; agg_add 0
  else
    info "$label: build $build_id not attached to any TestFlight group"; agg_add 1
  fi
done <<< "$(echo "$APPS" | jq -c '.[]')"

agg_finish "latest main build(s) distributed to a TestFlight group"
