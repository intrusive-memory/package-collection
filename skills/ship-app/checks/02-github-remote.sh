#!/bin/bash
# 02-github-remote — Verify origin points at a github.com URL.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

git rev-parse --git-dir >/dev/null 2>&1 || skip "not in a git repo (check 01)"

REMOTE=$(git remote get-url origin 2>/dev/null || true)
[ -z "$REMOTE" ] && fail "no 'origin' remote configured"

case "$REMOTE" in
  *github.com*) pass "origin is GitHub ($REMOTE)" ;;
  *) fail "origin is not GitHub: $REMOTE" ;;
esac
