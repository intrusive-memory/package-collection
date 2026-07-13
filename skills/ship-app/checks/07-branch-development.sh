#!/bin/bash
# 07-branch-development — Verify origin/development exists.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

git rev-parse --git-dir >/dev/null 2>&1 || skip "not in a git repo (check 01)"

if git ls-remote --heads origin development 2>/dev/null | grep -q development; then
  pass "origin/development exists"
else
  fail "origin/development branch is missing"
fi
