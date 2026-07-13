#!/bin/bash
# 21-gha-release-tag-gate — (optional) Verify a GitHub Actions workflow runs the
# test suite when a release is finalized — either on a pushed `v*` tag or on a
# GitHub `release` event — so the tag/release step is CI-gated in GitHub
# (Apple-Silicon), not Xcode Cloud.
#
# OPTIONAL: many repos rely on the RC-tag test gate (check 20) as the last
# green-before-ship signal and don't add a separate final-tag gate. SKIPs (not
# FAILs) when absent.
#
# Best-effort YAML scan (grep-based, not a real parser).
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

[ -d .github/workflows ] || skip ".github/workflows/ directory does not exist"

shopt -s nullglob
MATCH=""
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] || continue

  # Trigger on a v* tag push OR a release event.
  TAGGED=0
  if grep -qE 'tags:' "$f" && grep -qE "(^\s*-\s*['\"]?v\*?['\"]?\s*$)|(tags:\s*\[[^]]*v\*)" "$f"; then
    TAGGED=1
  fi
  grep -qE '^\s*release:' "$f" && TAGGED=1
  [ "$TAGGED" = "1" ] || continue

  # Must invoke a test command.
  grep -qE 'xcodebuild\s+test|swift\s+test|make\s+test|test_macos|test_sim|fastlane\s+test' "$f" || continue

  MATCH="$f"
  break
done

if [ -n "$MATCH" ]; then
  pass "release/tag test gate: $(basename "$MATCH")"
else
  skip "no GitHub Actions test gate on v* tag / release event (optional — the required test gate is on development → main, check 09)"
fi
