#!/opt/homebrew/bin/bash
#
# verify.sh — validate every tracked package:
#   1. Repo is accessible via the GitHub API.
#   2. Repo has at least one published GitHub release.
#   3. Package.swift at the latest release tag is fetchable and parseable.
#
# Exit status is 0 if everything passes, 1 if any check fails.
#
# Usage: verify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

COLLECTION=$(resolve_collection_json)

PACKAGE_COUNT=$(jq '.packages | length' "$COLLECTION")
FAILED=0

for (( i=0; i<PACKAGE_COUNT; i++ )); do
  url=$(jq -r ".packages[$i].url" "$COLLECTION")
  repo=$(owner_repo_from_url "$url")
  name="${repo##*/}"

  # 1. Repo accessible
  if ! gh api "repos/${repo}" --jq '.full_name' >/dev/null 2>&1; then
    echo "✗ $name — repo not accessible (${repo})"
    FAILED=$((FAILED + 1))
    continue
  fi

  # 2. Release exists
  tag=""
  if ! tag=$(get_latest_release_tag "$repo" 2>/dev/null); then
    echo "✗ $name — no published release"
    FAILED=$((FAILED + 1))
    continue
  fi

  # 3. Package.swift at release tag is parseable
  content=""
  if ! content=$(fetch_package_swift "$repo" "$tag" 2>/dev/null); then
    echo "✗ $name — Package.swift missing at $tag"
    FAILED=$((FAILED + 1))
    continue
  fi

  tools=$(printf '%s' "$content" | extract_tools_version)
  pkg_name=$(printf '%s' "$content" | extract_package_name)
  if [[ -z "$tools" || -z "$pkg_name" ]]; then
    echo "✗ $name — Package.swift@$tag did not parse (tools=$tools name=$pkg_name)"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "✓ $name @ $tag (tools $tools)"
done

echo
if [[ "$FAILED" -gt 0 ]]; then
  echo "$FAILED of $PACKAGE_COUNT package(s) failed verification."
  exit 1
fi
echo "All $PACKAGE_COUNT package(s) verified."
