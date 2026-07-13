#!/bin/bash
# 01-git-repo — Verify we're inside a git repository.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

if git rev-parse --git-dir >/dev/null 2>&1; then
  pass "inside a git repository"
else
  fail "not inside a git repository"
fi
