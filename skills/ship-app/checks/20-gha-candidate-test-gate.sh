#!/bin/bash
# 20-gha-candidate-test-gate — Verify a GitHub Actions workflow runs the test
# suite on the release-candidate tag push (push targeting `v*-rc.*` tags).
#
# The release candidate is a TAG on `main` (v<version>-rc.<k>), not a branch, and
# merging that tag into `release/*` is what PROMOTES code to the App Store. When a
# test gate for the candidate exists it is owned by GitHub CI, not Xcode Cloud
# (Xcode Cloud only builds/archives/uploads; its runners are Intel and can't run
# the Apple-Silicon-specific suite, so any test gate must live in GitHub Actions
# on Apple-Silicon runners). OPTIONAL — SKIPs when absent: the RC tag points at
# `main` code that already cleared the development → main test gate (check 09), so
# re-running the suite on the RC tag is a belt-and-suspenders extra, not a
# requirement. Repos that want it can add a `push: tags: ['v*-rc*']` trigger.
#
# Best-effort YAML scan (grep-based, not a real parser). If a real workflow
# exists but doesn't match, refine the patterns below rather than declaring this
# check broken.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

[ -d .github/workflows ] || skip ".github/workflows/ directory does not exist (optional RC-tag test gate)"

shopt -s nullglob
MATCH=""
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] || continue

  # Must trigger on a push with a tags filter.
  grep -qE '^\s*push:' "$f" || continue
  grep -qE '^\s*tags:' "$f" || continue

  # Must match an RC tag pattern (v*-rc*, list form or inline-array form).
  if ! grep -qE "(^\s*-\s*['\"]?v\*?-?rc[^'\"]*['\"]?\s*$)|(tags:\s*\[[^]]*rc)" "$f"; then
    continue
  fi

  # Must invoke a test command.
  grep -qE 'xcodebuild\s+test|swift\s+test|make\s+test|test_macos|test_sim|fastlane\s+test' "$f" || continue

  MATCH="$f"
  break
done

if [ -n "$MATCH" ]; then
  pass "RC-tag test gate: $(basename "$MATCH")"
else
  skip "no GitHub Actions test gate on push → v*-rc.* tags (optional — the RC tag points at main code already cleared by the development → main test gate, check 09)"
fi
