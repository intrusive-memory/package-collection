#!/opt/homebrew/bin/bash
#
# list.sh — print each tracked package with its current collection version
# and the latest GitHub release. Marks packages that are out of date.
#
# Exit status is non-zero if any package has no published release.
#
# Usage: list.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

COLLECTION=$(resolve_collection_json)

PACKAGE_COUNT=$(jq '.packages | length' "$COLLECTION")
OUT_OF_DATE=0
MISSING_RELEASE=0

printf '%-32s %-14s %-14s %s\n' "PACKAGE" "CURRENT" "LATEST" "STATUS"
printf '%-32s %-14s %-14s %s\n' "-------" "-------" "------" "------"

for (( i=0; i<PACKAGE_COUNT; i++ )); do
  url=$(jq -r ".packages[$i].url" "$COLLECTION")
  repo=$(owner_repo_from_url "$url")
  name="${repo##*/}"
  current=$(jq -r ".packages[$i].versions[0].version // \"—\"" "$COLLECTION")

  latest=""
  status="ok"
  if tag=$(get_latest_release_tag "$repo" 2>/dev/null); then
    latest=$(strip_v "$tag")
    if [[ "$current" != "$latest" ]]; then
      status="OUT OF DATE"
      OUT_OF_DATE=$((OUT_OF_DATE + 1))
    fi
  else
    latest="—"
    status="NO RELEASE"
    MISSING_RELEASE=$((MISSING_RELEASE + 1))
  fi

  printf '%-32s %-14s %-14s %s\n' "$name" "$current" "$latest" "$status"
done

echo
echo "${PACKAGE_COUNT} tracked · ${OUT_OF_DATE} out of date · ${MISSING_RELEASE} without a release"

if [[ "$MISSING_RELEASE" -gt 0 ]]; then
  exit 1
fi
