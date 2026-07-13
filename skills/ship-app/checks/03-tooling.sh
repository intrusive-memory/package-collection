#!/bin/bash
# 03-tooling — Verify gh, asc, jq are on PATH.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

MISSING=()
for cmd in gh asc jq; do
  command -v "$cmd" >/dev/null || MISSING+=("$cmd")
done

if [ "${#MISSING[@]}" -eq 0 ]; then
  pass "gh, asc, jq all installed"
else
  fail "missing tooling: ${MISSING[*]}"
fi
