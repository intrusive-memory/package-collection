#!/bin/bash
# 09-gha-macos-test-gate — Verify a GitHub Actions workflow runs macOS unit/UI
# tests on pull_request → main.
#
# This is a best-effort YAML scan — grep-based, not a real parser. If a real
# workflow exists but doesn't match the heuristics here, refine the patterns
# below rather than declaring this check broken.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

[ -d .github/workflows ] || fail ".github/workflows/ directory does not exist"

shopt -s nullglob
MATCH=""
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] || continue

  # Must trigger on pull_request
  grep -q 'pull_request' "$f" || continue

  # Must target main in branches filter (handles list form and inline-array form)
  if ! grep -qE '(^\s*-\s*main\b)|(branches:\s*\[[^]]*\bmain\b)' "$f"; then
    continue
  fi

  # Must run on a macOS runner (iOS sim tests also run on macOS-* but use a different
  # destination — see check 10). Here we want the macOS-platform test target.
  grep -qE 'runs-on:\s*macos-' "$f" || continue
  grep -qE 'platform=macOS|test_macos|destination[^#]*platform=macOS' "$f" || continue

  # Must invoke a test command
  grep -qE 'xcodebuild\s+test|swift\s+test|make\s+test|test_macos|fastlane\s+test' "$f" || continue

  MATCH="$f"
  break
done

if [ -n "$MATCH" ]; then
  pass "macOS test gate: $(basename "$MATCH")"
else
  fail "no GitHub Actions workflow runs macOS tests on pull_request → main"
fi
