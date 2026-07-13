#!/bin/bash
# 06-app-id — Verify at least one App Store Connect app is resolvable, and list
# every app this repo ships (one repo may ship several — e.g. an iOS app and a
# macOS app, each its own ASC record). All later per-app checks loop this set.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v jq >/dev/null || skip "jq not installed (check 03)"

APPS=$(resolve_apps)
COUNT=$(echo "$APPS" | jq 'length' 2>/dev/null || echo 0)

[ "$COUNT" = "0" ] && fail "no app resolvable (declare .asc.json apps[], or set --app / ASC_APP_ID / .asc.json .app)"

if [ "$CHECK_VERBOSE" = "1" ]; then
  echo "$APPS" | jq -r '.[] | "  · \(.name // .appId)  appId=\(.appId // "?")  platform=\(.platform // "?")  scheme=\(.scheme // "?")"' >&2
fi

LABELS=$(echo "$APPS" | jq -r '[.[] | (.name // .appId)] | join(", ")')
if [ "$COUNT" = "1" ]; then
  pass "1 app: $LABELS"
else
  pass "$COUNT apps: $LABELS"
fi
