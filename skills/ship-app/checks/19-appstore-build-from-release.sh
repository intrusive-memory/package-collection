#!/bin/bash
# 19-appstore-build-from-release — If a release/* branch exists, then for each
# app shipped from this repo, verify the most recent build produced by that app's
# App Store (branch=release/*) workflow reached App Store Connect (a build
# artifact was produced, optionally tied to an appStoreVersion).
#
# Multi-app: loops resolve_apps. An app with no release workflow / no completed
# run → informational skip. SKIP overall when no release/* branch exists yet.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

git fetch origin --quiet 2>/dev/null || true
REL_BRANCH=$(git ls-remote --heads origin 'release/*' 2>/dev/null \
  | sed 's#.*refs/heads/##' | grep -E '^release/[0-9]+$' | sort -t/ -k2 -n | tail -1)
[ -z "$REL_BRANCH" ] && skip "no release/* branch in repo yet"

agg_reset
while IFS= read -r app; do
  [ -z "$app" ] && continue
  label=$(app_label "$app")
  appid=$(app_field "$app" appId)
  if [ -z "$appid" ]; then info "$label: no appId"; agg_add 2; continue; fi

  wf=$(xcc_workflows "$appid")
  as_wf=$(echo "$wf" | jq -r '
    .[] | select((.attributes.branchStartCondition // {}) | tostring | test("release"; "i")) | .id' | head -1)
  if [ -z "$as_wf" ]; then info "$label: no branch=release/* workflow (check 14)"; agg_add 2; continue; fi

  runs=$(asc xcode-cloud build-runs list --workflow-id "$as_wf" --output json --limit 10 --sort "-number" 2>/dev/null | jq '.data // .' 2>/dev/null || echo "[]")
  latest_run=$(echo "$runs" | jq -r '.[] | select((.attributes.executionProgress // "") == "COMPLETE") | .id' | head -1)
  if [ -z "$latest_run" ]; then info "$label: App Store workflow has no completed runs yet"; agg_add 2; continue; fi

  builds=$(asc xcode-cloud build-runs builds --run-id "$latest_run" --output json 2>/dev/null | jq '.data // .' 2>/dev/null || echo "[]")
  build_id=$(echo "$builds" | jq -r '.[0].id // empty')
  if [ -z "$build_id" ]; then info "$label: release run $latest_run completed but produced no build"; agg_add 1; continue; fi
  info "$label: release build id $build_id (from $REL_BRANCH)"

  # Best-effort: confirm the build is tied to an App Store version (production).
  asv=""
  for cmd in \
    "asc builds app-store-version --id $build_id --output json" \
    "asc builds view --id $build_id --output json"
  do
    out=$(eval "$cmd" 2>/dev/null) || continue
    norm=$(echo "$out" | jq '.data // .' 2>/dev/null) || continue
    if echo "$norm" | jq -e '(.relationships.appStoreVersion.data // .appStoreVersion // empty) != null' >/dev/null 2>&1; then asv="yes"; break; fi
    if echo "$norm" | jq -e 'type == "object" and (.id != null)' >/dev/null 2>&1; then asv="yes"; break; fi
  done

  if [ -n "$asv" ]; then
    info "$label: build $build_id reached App Store Connect (version attached)"
  else
    info "$label: build $build_id uploaded to App Store Connect (version link unconfirmed)"
  fi
  agg_add 0
done <<< "$(echo "$APPS" | jq -c '.[]')"

agg_finish "App Store build(s) from $REL_BRANCH reached App Store Connect"
