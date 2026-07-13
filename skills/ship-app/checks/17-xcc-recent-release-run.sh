#!/bin/bash
# 17-xcc-recent-release-run — If any release/* branch or v*-rc.* tag exists,
# verify, for each app shipped from this repo, that the most recent such ref
# has a corresponding Xcode Cloud build run (App Store / release-gate workflow).
# SKIP when no such ref exists yet.
#
# The release candidate is a TAG on `main` (v<version>-rc.<k>), not a branch, so
# the fallback target is the newest RC tag, matched against the RC workflow's
# tag start condition.
#
# Multi-app: loops resolve_apps. An app with no release/RC workflow →
# informational skip. An app whose workflow has no run for the ref tip → FAIL.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"
APPS=$(resolve_apps)
[ "$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)" = "0" ] && skip "no apps (check 06)"

git fetch origin --quiet 2>/dev/null || true
git fetch origin --tags --quiet 2>/dev/null || true

# Prefer a release/* branch (App Store); fall back to the newest v*-rc.* tag.
# WF_COND selects which Xcode Cloud start-condition kind to match the workflow by.
TARGET_REF=$(git ls-remote --heads origin 'release/*' 2>/dev/null \
  | sed 's#.*refs/heads/##' | grep -E '^release/[0-9]+$' | sort -t/ -k2 -n | tail -1)
WF_PATTERN="release"; WF_COND="branchStartCondition"; REF_KIND="refs/heads"
if [ -n "$TARGET_REF" ]; then
  TIP_SHA=$(git ls-remote origin "refs/heads/$TARGET_REF" 2>/dev/null | awk '{print $1}')
else
  TARGET_REF=$(git ls-remote --tags origin 'v*-rc.*' 2>/dev/null \
    | sed 's#.*refs/tags/##' | grep -v '\^{}' | sort -V | tail -1)
  WF_PATTERN="rc"; WF_COND="tagStartCondition"; REF_KIND="refs/tags"
  # For a tag, resolve the peeled (dereferenced) commit sha when available.
  TIP_SHA=$(git ls-remote origin "refs/tags/${TARGET_REF}^{}" 2>/dev/null | awk '{print $1}')
  [ -z "$TIP_SHA" ] && TIP_SHA=$(git ls-remote origin "refs/tags/$TARGET_REF" 2>/dev/null | awk '{print $1}')
fi
[ -z "$TARGET_REF" ] && skip "no release/* branches or v*-rc.* tags in repo yet"

SHORT="${TIP_SHA:0:7}"

agg_reset
while IFS= read -r app; do
  [ -z "$app" ] && continue
  label=$(app_label "$app")
  appid=$(app_field "$app" appId)
  if [ -z "$appid" ]; then info "$label: no appId"; agg_add 2; continue; fi

  wf=$(xcc_workflows "$appid")
  wf_id=$(echo "$wf" | jq -r --arg pat "$WF_PATTERN" --arg cond "$WF_COND" '
    .[] | select((.attributes[$cond] // {}) | tostring | test($pat; "i")) | .id' | head -1)
  if [ -z "$wf_id" ]; then info "$label: no '$WF_PATTERN' workflow (check 13/14)"; agg_add 2; continue; fi

  runs=$(asc xcode-cloud build-runs list --workflow-id "$wf_id" --output json --limit 30 --sort "-number" 2>/dev/null | jq '.data // .' 2>/dev/null || echo "[]")
  if [ "$(echo "$runs" | jq 'length' 2>/dev/null || echo 0)" = "0" ]; then
    info "$label: '$WF_PATTERN' workflow has zero build runs"; agg_add 1; continue
  fi
  [ "$CHECK_VERBOSE" = "1" ] && echo "$runs" | jq --arg a "$label" '.[] | {app:$a, number: .attributes.number, branch: .attributes.sourceBranchOrTag.name, sha: .attributes.sourceCommit.commitSha}' >&2

  matched=""
  if [ -n "$TIP_SHA" ]; then
    matched=$(echo "$runs" | jq --arg full "$TIP_SHA" --arg short "$SHORT" -r '
      .[] | select(
        (.attributes.sourceCommit.commitSha // "") == $full or
        ((.attributes.sourceCommit.commitSha // "") | startswith($short))
      ) | .attributes.number' | head -1)
  fi
  [ -z "$matched" ] && matched=$(echo "$runs" | jq --arg b "$TARGET_REF" -r '
    .[] | select((.attributes.sourceBranchOrTag.name // "") == $b) | .attributes.number' | head -1)

  if [ -n "$matched" ]; then
    info "$label: build run #$matched for $TARGET_REF (${SHORT})"; agg_add 0
  else
    info "$label: no build run sourced from $TARGET_REF tip (${SHORT})"; agg_add 1
  fi
done <<< "$(echo "$APPS" | jq -c '.[]')"

agg_finish "Xcode Cloud build run(s) for $TARGET_REF (${SHORT})"
