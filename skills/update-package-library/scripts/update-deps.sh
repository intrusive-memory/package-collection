#!/opt/homebrew/bin/bash
#
# update-deps.sh — for each package in collection.json, parse Package.swift
# at its latest release tag, extract the declared dependencies, and write a
# `dependencies` object onto the package entry.
#
# The `dependencies` shape is a dictionary mapping dependency-repo to the
# version spec declared in that package's Package.swift:
#   {
#     "owner/name": "from: 1.0.0",
#     "apple/swift-argument-parser": "upToNextMajor: 1.0.0"
#   }
#
# - Keys are owner/name for github.com URLs, otherwise the URL minus .git.
# - Values are compact version specs preserving intent:
#     from: X, exact: X, branch: X, revision: X,
#     upToNextMajor: X, upToNextMinor: X, or "unknown" if unparseable.
# - `.package(path: ...)` local dependencies are skipped.
#
# Usage: update-deps.sh [--only owner/repo] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

ONLY=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '3,20p' "$0" | sed 's|^# \{0,1\}||'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

COLLECTION=$(resolve_collection_json)
echo "Updating dependencies in $COLLECTION"

PACKAGE_COUNT=$(jq '.packages | length' "$COLLECTION")
UPDATED=0
FAILED=()

WORK=$(mktemp)
cp "$COLLECTION" "$WORK"

for (( i=0; i<PACKAGE_COUNT; i++ )); do
  url=$(jq -r ".packages[$i].url" "$WORK")
  repo=$(owner_repo_from_url "$url")
  name="${repo##*/}"

  if [[ -n "$ONLY" && "$repo" != "$ONLY" ]]; then
    continue
  fi

  echo "→ $name"

  tag=""
  if ! tag=$(get_latest_release_tag "$repo"); then
    FAILED+=("$repo (no release)")
    continue
  fi

  content=""
  if ! content=$(fetch_package_swift "$repo" "$tag"); then
    FAILED+=("$repo (no Package.swift at $tag)")
    continue
  fi

  deps=$(extract_dependencies "$content")
  count=$(echo "$deps" | jq 'length')
  echo "  $count dependency/ies"
  if [[ "$count" -gt 0 ]]; then
    echo "$deps" | jq -r 'to_entries[] | "    - \(.key): \(.value)"'
  fi

  tmp=$(mktemp)
  jq --argjson d "$deps" --argjson i "$i" \
    '.packages[$i].dependencies = $d' "$WORK" > "$tmp"
  mv "$tmp" "$WORK"
  UPDATED=$((UPDATED + 1))
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo
  echo "FAILURES:" >&2
  for f in "${FAILED[@]}"; do
    echo "  - $f" >&2
  done
  echo >&2
  echo "Aborting without writing changes." >&2
  rm -f "$WORK"
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "Dry run — $UPDATED package(s) would have dependencies refreshed. No changes written."
  # Show what we would have written, for inspection
  jq '[.packages[] | {name: (.url | split("/") | last | sub("\\.git$";"")), dependencies: (.dependencies // {})}]' "$WORK"
  rm -f "$WORK"
  exit 0
fi

mv "$WORK" "$COLLECTION"
new_rev=$(bump_revision "$COLLECTION")
echo
echo "✓ Refreshed dependencies for $UPDATED package(s). Collection is now revision $new_rev."
