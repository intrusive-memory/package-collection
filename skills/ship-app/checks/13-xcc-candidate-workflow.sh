#!/bin/bash
# 13-xcc-candidate-workflow — For each app this repo ships, look for an Xcode
# Cloud workflow with a TAG start condition matching `v*-rc.*` (the
# release-candidate gate: build + archive, no upload).
#
# The release candidate is a TAG on `main` (v<version>-rc.<k>), not a branch —
# so this gate keys off a tag start condition, not a `candidate/*` branch.
#
# Multi-app: loops every app from resolve_apps. An app with no RC-tag workflow
# is an informational skip (Xcode Cloud gates what it builds). PASS if ≥1 app is
# wired; SKIP if none yet. Phase B still requires this green for each app being
# promoted to the App Store.
#
# Reference name: "RC => RELEASE". Match is by start-condition shape.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

match_rc_tag() {
  local wf="$1" id
  # A tagStartCondition whose pattern is an RC tag (v*-rc*, or just contains "rc").
  id=$(echo "$wf" | jq -r '
    .[] | select(
      [ (.attributes.tagStartCondition.source.patterns[]?.pattern // empty) ]
      | any(test("rc"; "i"))
    ) | .id' 2>/dev/null | head -1)
  # Fallback: any start condition mentioning an rc tag pattern.
  [ -z "$id" ] && id=$(echo "$wf" | jq -r '
    .[] | select((.attributes.tagStartCondition // {}) | tostring | test("rc"; "i")) | .id' 2>/dev/null | head -1)
  echo "$id"
}

agg_reset
while IFS= read -r app; do
  [ -z "$app" ] && continue
  label=$(app_label "$app")
  appid=$(app_field "$app" appId)
  if [ -z "$appid" ]; then info "$label: no appId"; agg_add 2; continue; fi

  wf=$(xcc_workflows "$appid")
  if [ "$(echo "$wf" | jq 'length' 2>/dev/null || echo 0)" = "0" ]; then
    info "$label: no workflows configured"; agg_add 2; continue
  fi
  [ "$CHECK_VERBOSE" = "1" ] && echo "$wf" | jq --arg a "$label" '.[] | {app:$a, id, name: .attributes.name, tagStartCondition: .attributes.tagStartCondition}' >&2

  id=$(match_rc_tag "$wf")
  if [ -n "$id" ]; then
    name=$(echo "$wf" | jq --arg id "$id" -r '.[] | select(.id==$id) | .attributes.name // "(unnamed)"')
    info "$label: RC gate '$name' (${id:0:12}…)"; agg_add 0
  else
    info "$label: no tag=v*-rc.* workflow"; agg_add 2
  fi
done <<< "$(echo "$APPS" | jq -c '.[]')"

agg_finish "RC (release-gate) workflow (tag=v*-rc.*)"
