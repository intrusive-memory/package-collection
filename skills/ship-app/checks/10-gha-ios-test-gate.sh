#!/bin/bash
# 10-gha-ios-test-gate — (optional) Verify a GitHub Actions workflow runs iOS
# unit/UI tests on pull_request → main.
#
# iOS simulator tests run on a macos-* runner, so the discriminator vs check 09
# is `platform=iOS` (or simctl / iPhone destination) rather than runner OS.
#
# OPTIONAL: all test gating lives in GitHub CI (Xcode Cloud never runs tests —
# its runners are Intel and parts of the suite are Apple-Silicon-specific). The
# iOS gate is still optional because some projects can't run iOS UI/simulator
# tests reliably on CI runners (they hang); those projects gate on the required
# macOS test suite (check 09) only. This check therefore SKIPs (not FAILs) when
# no iOS test gate is present. Xcode Cloud's PR build is NOT a substitute — it
# does not run tests.
set -uo pipefail
. "$(dirname "$0")/_common.sh"
parse_common_args "$@"

[ -d .github/workflows ] || fail ".github/workflows/ directory does not exist"

shopt -s nullglob
MATCH=""
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] || continue

  grep -q 'pull_request' "$f" || continue
  if ! grep -qE '(^\s*-\s*main\b)|(branches:\s*\[[^]]*\bmain\b)' "$f"; then
    continue
  fi

  # iOS-shaped: platform=iOS Simulator, simctl, or test_sim helpers.
  grep -qE 'platform=iOS\s+Simulator|destination[^#]*iOS\s+Simulator|test_sim|simctl|iPhone\s+[0-9]+' "$f" || continue

  # Must invoke a test command
  grep -qE 'xcodebuild\s+test|make\s+test|test_sim|fastlane\s+test' "$f" || continue

  MATCH="$f"
  break
done

if [ -n "$MATCH" ]; then
  pass "iOS test gate: $(basename "$MATCH")"
else
  skip "no iOS test gate in GitHub Actions (optional — some repos can't run iOS sim tests reliably on CI; macOS tests still gate via check 09)"
fi
