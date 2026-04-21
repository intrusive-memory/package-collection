#!/opt/homebrew/bin/bash
#
# update.sh — refresh collection.json with the latest release manifest for
# every tracked package.
#
# Fails loudly if any package has no published GitHub release — releases are
# the only source of truth.
#
# Usage: update.sh [--only owner/repo] [--dry-run]

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
    -h|--help)
      sed -n '3,10p' "$0" | sed 's|^# \{0,1\}||'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

COLLECTION=$(resolve_collection_json)
echo "Updating $COLLECTION"

PACKAGE_COUNT=$(jq '.packages | length' "$COLLECTION")
UPDATED=0
FAILED=()

WORK=$(mktemp)
cp "$COLLECTION" "$WORK"

for (( i=0; i<PACKAGE_COUNT; i++ )); do
  url=$(jq -r ".packages[$i].url" "$WORK")
  repo=$(owner_repo_from_url "$url")

  if [[ -n "$ONLY" && "$repo" != "$ONLY" ]]; then
    continue
  fi

  echo "→ $repo"

  tag=""
  if ! tag=$(get_latest_release_tag "$repo"); then
    FAILED+=("$repo (no release)")
    continue
  fi
  version=$(strip_v "$tag")
  echo "  release: $tag"

  content=""
  if ! content=$(fetch_package_swift "$repo" "$tag"); then
    FAILED+=("$repo (no Package.swift at $tag)")
    continue
  fi

  versions_json=""
  if ! versions_json=$(build_versions_entry "$content" "$version"); then
    FAILED+=("$repo (manifest parse failed)")
    continue
  fi

  deps_json=$(extract_dependencies "$content")

  tmp=$(mktemp)
  jq --argjson v "$versions_json" --argjson d "$deps_json" --argjson i "$i" \
    '.packages[$i].versions = $v | .packages[$i].dependencies = $d' "$WORK" > "$tmp"
  mv "$tmp" "$WORK"
  UPDATED=$((UPDATED + 1))
  echo "  ✓ refreshed ($(echo "$deps_json" | jq 'length') deps)"
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
  echo "Dry run — $UPDATED package(s) would be refreshed. No changes written."
  rm -f "$WORK"
  exit 0
fi

mv "$WORK" "$COLLECTION"
new_rev=$(bump_revision "$COLLECTION")
echo
echo "✓ Refreshed $UPDATED package(s). Collection is now revision $new_rev."
