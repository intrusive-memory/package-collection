#!/opt/homebrew/bin/bash
#
# remove-package.sh — remove a package from collection.json.
#
# Accepts either "owner/repo" or just the repo name ("SwiftBruja"). Fails
# if the package is not in the collection or if the name is ambiguous
# across multiple owners.
#
# Usage:
#   remove-package.sh intrusive-memory/SwiftBruja
#   remove-package.sh SwiftBruja

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

if [[ $# -ne 1 ]]; then
  echo "usage: remove-package.sh owner/repo | name" >&2
  exit 2
fi

TARGET="$1"
COLLECTION=$(resolve_collection_json)

# Find matching package indexes. Match either full owner/repo or bare repo name.
matches=$(jq -r --arg t "$TARGET" '
  [.packages | to_entries[] |
    select(
      (.value.url | sub("^https?://github\\.com/"; "") | sub("\\.git$"; "")) == $t
      or (.value.url | split("/") | last | sub("\\.git$"; "")) == $t
    ) | .key]
  | .[]
' "$COLLECTION")

count=$(echo "$matches" | grep -c . || true)

if [[ "$count" -eq 0 ]]; then
  echo "error: no package matching '$TARGET' found in collection" >&2
  exit 1
fi
if [[ "$count" -gt 1 ]]; then
  echo "error: '$TARGET' is ambiguous — use owner/repo form" >&2
  exit 1
fi

idx=$(echo "$matches" | head -1)
url=$(jq -r --argjson i "$idx" '.packages[$i].url' "$COLLECTION")

tmp=$(mktemp)
jq --argjson i "$idx" 'del(.packages[$i])' "$COLLECTION" > "$tmp"
mv "$tmp" "$COLLECTION"

new_rev=$(bump_revision "$COLLECTION")
echo "✓ Removed $url. Collection is now revision $new_rev."
