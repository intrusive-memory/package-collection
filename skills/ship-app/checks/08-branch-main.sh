#!/bin/bash
# 08-branch-main — Verify origin/main exists.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

git rev-parse --git-dir >/dev/null 2>&1 || skip "not in a git repo (check 01)"

if git ls-remote --heads origin main 2>/dev/null | grep -q main; then
  pass "origin/main exists"
else
  fail "origin/main branch is missing"
fi
