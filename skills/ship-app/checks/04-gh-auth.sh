#!/bin/bash
# 04-gh-auth — Verify gh is authenticated.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v gh >/dev/null || skip "gh not installed (check 03)"

if gh auth status >/dev/null 2>&1; then
  pass "gh authenticated"
else
  fail "gh is not authenticated (run: gh auth login)"
fi
