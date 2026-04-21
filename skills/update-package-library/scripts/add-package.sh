#!/opt/homebrew/bin/bash
#
# add-package.sh — add a new repo to collection.json.
#
# The repo must already have at least one published GitHub release; this
# script fetches the manifest from that release and inserts a new package
# entry in alphabetical order (by the repo name).
#
# Usage:
#   add-package.sh owner/repo \
#     --summary "One-line description of the package" \
#     --keywords "kw1,kw2,kw3"
#
# The --summary and --keywords flags are required — they cannot be derived
# from the repository and are part of the collection's curated metadata.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

REPO=""
SUMMARY=""
KEYWORDS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --summary) SUMMARY="$2"; shift 2 ;;
    --keywords) KEYWORDS="$2"; shift 2 ;;
    -h|--help) sed -n '3,15p' "$0" | sed 's|^# \{0,1\}||'; exit 0 ;;
    -*) echo "unknown arg: $1" >&2; exit 2 ;;
    *) REPO="$1"; shift ;;
  esac
done

if [[ -z "$REPO" || -z "$SUMMARY" || -z "$KEYWORDS" ]]; then
  echo "usage: add-package.sh owner/repo --summary '...' --keywords 'a,b,c'" >&2
  exit 2
fi

COLLECTION=$(resolve_collection_json)

# Reject duplicates.
if jq -e --arg r "https://github.com/${REPO}.git" '.packages[] | select(.url == $r)' "$COLLECTION" >/dev/null; then
  echo "error: ${REPO} is already in the collection" >&2
  exit 1
fi

echo "Adding ${REPO}"

tag=$(get_latest_release_tag "$REPO")
version=$(strip_v "$tag")
echo "  release: $tag"

content=$(fetch_package_swift "$REPO" "$tag")
versions=$(build_versions_entry "$content" "$version")

# Build keywords JSON array from comma-separated input.
kw_json=$(jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; ""))' <<< "$KEYWORDS")

pkg_entry=$(jq -n \
  --arg url "https://github.com/${REPO}.git" \
  --arg summary "$SUMMARY" \
  --argjson keywords "$kw_json" \
  --arg readme "https://github.com/${REPO}/blob/main/README.md" \
  --argjson versions "$versions" \
  '{
    url: $url,
    summary: $summary,
    keywords: $keywords,
    readmeURL: $readme,
    versions: $versions
  }')

# Insert in alphabetical order by trailing repo name in the URL.
tmp=$(mktemp)
jq --argjson p "$pkg_entry" '
  .packages = (.packages + [$p] | sort_by(.url | split("/") | last))
' "$COLLECTION" > "$tmp"
mv "$tmp" "$COLLECTION"

new_rev=$(bump_revision "$COLLECTION")
echo "✓ Added ${REPO} @ ${version}. Collection is now revision $new_rev."
