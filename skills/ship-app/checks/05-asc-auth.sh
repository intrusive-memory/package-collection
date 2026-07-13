#!/bin/bash
# 05-asc-auth — Verify asc is authenticated / configured.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

command -v asc >/dev/null || skip "asc not installed (check 03)"

# `asc doctor` checks auth + config. It exits 0 when healthy.
if asc doctor >/dev/null 2>&1; then
  pass "asc reachable (asc doctor passes)"
else
  fail "asc not authenticated or misconfigured (run: asc doctor)"
fi
