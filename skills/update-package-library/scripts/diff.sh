#!/opt/homebrew/bin/bash
#
# diff.sh — show what would change if update.sh were run. Reports version
# bumps, new/removed products, new/removed targets, and platform version
# changes for each package.
#
# Usage: diff.sh [--only owner/repo]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    -h|--help) sed -n '3,8p' "$0" | sed 's|^# \{0,1\}||'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

COLLECTION=$(resolve_collection_json)

PACKAGE_COUNT=$(jq '.packages | length' "$COLLECTION")
CHANGED=0

for (( i=0; i<PACKAGE_COUNT; i++ )); do
  url=$(jq -r ".packages[$i].url" "$COLLECTION")
  repo=$(owner_repo_from_url "$url")
  name="${repo##*/}"

  if [[ -n "$ONLY" && "$repo" != "$ONLY" ]]; then
    continue
  fi

  tag=""
  if ! tag=$(get_latest_release_tag "$repo" 2>/dev/null); then
    echo "⚠ $name — no published release"
    continue
  fi
  new_version=$(strip_v "$tag")

  content=""
  if ! content=$(fetch_package_swift "$repo" "$tag" 2>/dev/null); then
    echo "⚠ $name — could not fetch Package.swift@$tag"
    continue
  fi

  new_versions=$(build_versions_entry "$content" "$new_version")
  cur_entry=$(jq ".packages[$i].versions[0]" "$COLLECTION")
  new_entry=$(echo "$new_versions" | jq '.[0]')

  if [[ "$(echo "$cur_entry" | jq -S -c .)" == "$(echo "$new_entry" | jq -S -c .)" ]]; then
    continue
  fi

  CHANGED=$((CHANGED + 1))
  echo "◆ $name"

  cur_ver=$(echo "$cur_entry" | jq -r '.version')
  if [[ "$cur_ver" != "$new_version" ]]; then
    echo "    version: $cur_ver → $new_version"
  fi

  cur_tools=$(echo "$cur_entry" | jq -r '.defaultToolsVersion')
  new_tools=$(echo "$new_entry" | jq -r '.defaultToolsVersion')
  if [[ "$cur_tools" != "$new_tools" ]]; then
    echo "    tools-version: $cur_tools → $new_tools"
  fi

  # Product diff (by name)
  cur_products=$(echo "$cur_entry" | jq -r ".manifests[\"$cur_tools\"].products[].name" | sort)
  new_products=$(echo "$new_entry" | jq -r ".manifests[\"$new_tools\"].products[].name" | sort)
  while IFS= read -r p; do
    [[ -n "$p" ]] && echo "    + product: $p"
  done < <(comm -13 <(echo "$cur_products") <(echo "$new_products"))
  while IFS= read -r p; do
    [[ -n "$p" ]] && echo "    - product: $p"
  done < <(comm -23 <(echo "$cur_products") <(echo "$new_products"))

  # Target diff (by name)
  cur_targets=$(echo "$cur_entry" | jq -r ".manifests[\"$cur_tools\"].targets[].name" | sort)
  new_targets=$(echo "$new_entry" | jq -r ".manifests[\"$new_tools\"].targets[].name" | sort)
  while IFS= read -r t; do
    [[ -n "$t" ]] && echo "    + target: $t"
  done < <(comm -13 <(echo "$cur_targets") <(echo "$new_targets"))
  while IFS= read -r t; do
    [[ -n "$t" ]] && echo "    - target: $t"
  done < <(comm -23 <(echo "$cur_targets") <(echo "$new_targets"))

  # Platform version changes
  cur_plat=$(echo "$cur_entry" | jq -c ".manifests[\"$cur_tools\"].minimumPlatformVersions[]?")
  new_plat=$(echo "$new_entry" | jq -c ".manifests[\"$new_tools\"].minimumPlatformVersions[]?")
  while IFS= read -r np; do
    [[ -z "$np" ]] && continue
    n=$(echo "$np" | jq -r '.name')
    nv=$(echo "$np" | jq -r '.version')
    cv=$(echo "$cur_plat" | jq -r --arg n "$n" 'select(.name==$n).version' | head -1)
    if [[ -z "$cv" ]]; then
      echo "    + platform: $n $nv"
    elif [[ "$cv" != "$nv" ]]; then
      echo "    platform $n: $cv → $nv"
    fi
  done <<< "$new_plat"
done

echo
if [[ "$CHANGED" -eq 0 ]]; then
  echo "No changes — collection is up to date."
else
  echo "$CHANGED package(s) would change. Run update.sh to apply."
fi
