#!/bin/bash
# 14-xcc-appstore-workflow — For each app this repo ships, look for an Xcode
# Cloud workflow with a BRANCH start condition matching `release/*` (archive +
# upload to App Store Connect). In the ship-app model, merging into release/<n>
# IS the App Store upload.
#
# Multi-app: loops every app from resolve_apps. An app with no release workflow
# is an informational skip (Xcode Cloud gates what it builds — that app isn't
# shipped to the App Store from this repo). PASS if ≥1 app is wired; SKIP if
# none yet. Phase B requires this green for each app being promoted.
#
# Reference name: "RELEASE => APP STORE". Match is by start-condition shape.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

match_release() {
  local wf="$1" id
  id=$(echo "$wf" | jq -r '
    .[] | select(
      [ (.attributes.branchStartCondition.source.patterns[]?.pattern // empty) ]
      | any(. == "release" or test("^release/"))
    ) | .id' 2>/dev/null | head -1)
  [ -z "$id" ] && id=$(echo "$wf" | jq -r '
    .[] | select((.attributes.branchStartCondition // {}) | tostring | test("release"; "i")) | .id' 2>/dev/null | head -1)
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
  [ "$CHECK_VERBOSE" = "1" ] && echo "$wf" | jq --arg a "$label" '.[] | {app:$a, id, name: .attributes.name, branchStartCondition: .attributes.branchStartCondition}' >&2

  id=$(match_release "$wf")
  if [ -n "$id" ]; then
    name=$(echo "$wf" | jq --arg id "$id" -r '.[] | select(.id==$id) | .attributes.name // "(unnamed)"')
    info "$label: App Store workflow '$name' (${id:0:12}…)"; agg_add 0
  else
    info "$label: no branch=release/* workflow — not shipped to the App Store"; agg_add 2
  fi
done <<< "$(echo "$APPS" | jq -c '.[]')"

agg_finish "App Store workflow (branch=release/*)"
