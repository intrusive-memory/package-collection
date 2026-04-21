#!/opt/homebrew/bin/bash
#
# _common.sh — shared helpers for update-package-library scripts.
#
# Source this file; do not execute it directly.
#
# Requirements: gh (authenticated), jq, curl, bash 4+ (for associative arrays).

set -euo pipefail

# Locate collection.json. Prefers $COLLECTION_JSON if set; otherwise looks for
# collection.json in the current directory, then the git repo root.
resolve_collection_json() {
  if [[ -n "${COLLECTION_JSON:-}" ]]; then
    if [[ ! -f "$COLLECTION_JSON" ]]; then
      echo "error: COLLECTION_JSON=$COLLECTION_JSON does not exist" >&2
      return 1
    fi
    echo "$COLLECTION_JSON"
    return 0
  fi

  if [[ -f "./collection.json" ]]; then
    echo "$(pwd)/collection.json"
    return 0
  fi

  local repo_root
  if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    if [[ -f "$repo_root/collection.json" ]]; then
      echo "$repo_root/collection.json"
      return 0
    fi
  fi

  echo "error: could not find collection.json (set COLLECTION_JSON or cd to the repo)" >&2
  return 1
}

# Extract "owner/repo" from a GitHub URL like https://github.com/foo/bar.git
owner_repo_from_url() {
  local url="$1"
  echo "$url" | sed -E 's|^https?://github\.com/||; s|\.git$||'
}

# Get latest release tag for a repo. RELEASES ARE THE ONLY SOURCE OF TRUTH —
# this does NOT fall back to tags. Returns the raw tag name (with leading 'v'
# preserved) on stdout, or exits non-zero with a message on stderr.
get_latest_release_tag() {
  local repo="$1"
  local tag
  tag=$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null || true)
  if [[ -z "$tag" ]]; then
    echo "error: ${repo} has no published GitHub release" >&2
    return 1
  fi
  echo "$tag"
}

# Strip leading 'v' from a tag ("v1.2.3" -> "1.2.3").
strip_v() {
  local s="$1"
  echo "${s#v}"
}

# Fetch Package.swift content at a given ref. Prints the decoded source on
# stdout; exits non-zero if missing.
fetch_package_swift() {
  local repo="$1"
  local ref="$2"
  local content
  content=$(gh api "repos/${repo}/contents/Package.swift?ref=${ref}" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)
  if [[ -z "$content" ]]; then
    echo "error: could not fetch Package.swift for ${repo}@${ref}" >&2
    return 1
  fi
  printf '%s' "$content"
}

# Extract swift-tools-version from Package.swift (content on stdin).
extract_tools_version() {
  head -1 | sed -n 's|.*swift-tools-version:[[:space:]]*||p' | tr -d '[:space:]'
}

# Extract `name: "X"` from the Package(...) declaration — just the first match.
extract_package_name() {
  grep -oE 'name:[[:space:]]*"[^"]*"' | head -1 | sed 's/name:[[:space:]]*"//; s/"$//'
}

# Parse library product declarations. Outputs a JSON array of
# {name, type: {library: ["automatic"]}, targets: [...]}.
# Best-effort regex parser; not a full Swift parser.
extract_products() {
  local content="$1"
  local pkg_name="$2"
  local products="[]"

  while IFS= read -r line; do
    local name target_list
    name=$(echo "$line" | grep -oE 'name:[[:space:]]*"[^"]*"' | head -1 | sed 's/name:[[:space:]]*"//; s/"$//')
    target_list=$(echo "$line" | grep -oE 'targets:[[:space:]]*\[[^]]*\]' | head -1 | sed 's/targets:[[:space:]]*\[//; s/\]//' | tr -d ' "')
    if [[ -n "$name" && -n "$target_list" ]]; then
      local targets_json="[]"
      IFS=',' read -ra tgts <<< "$target_list"
      for t in "${tgts[@]}"; do
        [[ -z "$t" ]] && continue
        targets_json=$(echo "$targets_json" | jq --arg t "$t" '. + [$t]')
      done
      products=$(echo "$products" | jq \
        --arg n "$name" \
        --argjson tgts "$targets_json" \
        '. + [{"name": $n, "type": {"library": ["automatic"]}, "targets": $tgts}]')
    fi
  done < <(echo "$content" | grep -E '\.library\(' || true)

  # Fallback: no library products found — use the package name as both product
  # and target. Matches the shape of the existing collection.json entries.
  if [[ "$(echo "$products" | jq 'length')" == "0" ]]; then
    products=$(jq -n --arg n "$pkg_name" \
      '[{"name": $n, "type": {"library": ["automatic"]}, "targets": [$n]}]')
  fi

  echo "$products"
}

# Build a targets array {name, moduleName} from a products JSON array.
targets_from_products() {
  local products_json="$1"
  echo "$products_json" | jq '[.[].targets[]] | unique | [.[] | {"name": ., "moduleName": .}]'
}

# Parse platform minimum versions (.macOS / .iOS) out of Package.swift.
# Outputs JSON array of {name, version}.
extract_platforms() {
  local content="$1"
  local platforms="[]"

  local os
  for os in macOS iOS; do
    if echo "$content" | grep -qE "\.${os}"; then
      local ver
      ver=$(echo "$content" | grep -oE "\.${os}\([^)]*\)" | head -1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -1 || true)
      if [[ -n "$ver" ]]; then
        [[ "$ver" == *"."* ]] || ver="${ver}.0"
        platforms=$(echo "$platforms" | jq --arg n "$os" --arg v "$ver" '. + [{"name":$n,"version":$v}]')
      fi
    fi
  done

  echo "$platforms"
}

# Build the full `versions` entry for a package from Package.swift content.
# Args: $1=package_swift_content. Output on stdout: JSON array with a single
# version object, shape matching collection.json.
build_versions_entry() {
  local content="$1"
  local version="$2"

  local tools_version pkg_name products targets platforms
  tools_version=$(printf '%s' "$content" | extract_tools_version)
  pkg_name=$(printf '%s' "$content" | extract_package_name)
  [[ -n "$tools_version" ]] || { echo "error: could not parse swift-tools-version" >&2; return 1; }
  [[ -n "$pkg_name" ]] || { echo "error: could not parse package name" >&2; return 1; }

  products=$(extract_products "$content" "$pkg_name")
  targets=$(targets_from_products "$products")
  platforms=$(extract_platforms "$content")

  jq -n \
    --arg version "$version" \
    --arg tools "$tools_version" \
    --arg pkgName "$pkg_name" \
    --argjson targets "$targets" \
    --argjson products "$products" \
    --argjson platforms "$platforms" \
    '[{
      version: $version,
      manifests: {
        ($tools): {
          toolsVersion: $tools,
          packageName: $pkgName,
          targets: $targets,
          products: $products,
          minimumPlatformVersions: $platforms
        }
      },
      defaultToolsVersion: $tools
    }]'
}

# Parse the `dependencies:` block of a Package.swift, returning a JSON
# object mapping dependency-repo -> version-spec. Best-effort regex +
# brace-counting parser that handles the common forms:
#   .package(url: "...", from: "1.0.0")
#   .package(url: "...", exact: "1.2.3")
#   .package(url: "...", branch: "main")
#   .package(url: "...", revision: "abc123")
#   .package(url: "...", .upToNextMajor(from: "1.0.0"))
#   .package(url: "...", .upToNextMinor(from: "1.0.0"))
# Ignores .package(path:, ...) entries (they're local, not versioned).
extract_dependencies() {
  local content="$1"

  # Walk the source character-by-character to pull out each balanced
  # .package(...) declaration. awk is the right tool — shell regex can't
  # match balanced parens.
  local decls
  decls=$(printf '%s' "$content" | awk '
    BEGIN { depth=0; cur=""; inpkg=0 }
    {
      line=$0 "\n"
      n=length(line)
      for(i=1; i<=n; i++) {
        c=substr(line,i,1)
        if(!inpkg && i+8 <= n && substr(line,i,9)==".package(") {
          inpkg=1; depth=1; cur=".package("; i+=8; continue
        }
        if(inpkg) {
          cur=cur c
          if(c=="(") depth++
          else if(c==")") {
            depth--
            if(depth==0) {
              gsub(/\n/, " ", cur)
              gsub(/[ \t]+/, " ", cur)
              print cur
              cur=""; inpkg=0
            }
          }
        }
      }
    }
  ')

  local deps_json="{}"
  local decl
  while IFS= read -r decl; do
    [[ -z "$decl" ]] && continue

    # Skip local path dependencies — they have no version to record.
    if echo "$decl" | grep -qE 'path:[[:space:]]*"'; then
      continue
    fi

    # URL is required; without it we can't identify the dependency.
    local url
    url=$(echo "$decl" | grep -oE 'url:[[:space:]]*"[^"]*"' | head -1 | sed 's/url:[[:space:]]*"//; s/"$//')
    [[ -z "$url" ]] && continue

    # Version spec — try each recognized form in order. Results like
    # "from: 1.0.0" are compact strings that preserve intent.
    local ver=""
    if echo "$decl" | grep -qE '\.upToNextMajor\(from:[[:space:]]*"'; then
      ver="upToNextMajor: $(echo "$decl" | grep -oE 'upToNextMajor\(from:[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | head -1)"
    elif echo "$decl" | grep -qE '\.upToNextMinor\(from:[[:space:]]*"'; then
      ver="upToNextMinor: $(echo "$decl" | grep -oE 'upToNextMinor\(from:[[:space:]]*"[^"]*"' | grep -oE '"[^"]*"' | tr -d '"' | head -1)"
    elif echo "$decl" | grep -qE '(^|[,( ])from:[[:space:]]*"'; then
      ver="from: $(echo "$decl" | grep -oE 'from:[[:space:]]*"[^"]*"' | head -1 | sed 's/from:[[:space:]]*"//; s/"$//')"
    elif echo "$decl" | grep -qE '(^|[,( ])exact:[[:space:]]*"'; then
      ver="exact: $(echo "$decl" | grep -oE 'exact:[[:space:]]*"[^"]*"' | head -1 | sed 's/exact:[[:space:]]*"//; s/"$//')"
    elif echo "$decl" | grep -qE '(^|[,( ])branch:[[:space:]]*"'; then
      ver="branch: $(echo "$decl" | grep -oE 'branch:[[:space:]]*"[^"]*"' | head -1 | sed 's/branch:[[:space:]]*"//; s/"$//')"
    elif echo "$decl" | grep -qE '(^|[,( ])revision:[[:space:]]*"'; then
      ver="revision: $(echo "$decl" | grep -oE 'revision:[[:space:]]*"[^"]*"' | head -1 | sed 's/revision:[[:space:]]*"//; s/"$//')"
    else
      ver="unknown"
    fi

    # Identify the dependency by its owner/repo pair for github.com URLs;
    # otherwise fall back to the url-without-.git.
    local repo
    if [[ "$url" == *"github.com"* ]]; then
      repo=$(echo "$url" | sed -E 's|^https?://github\.com/||; s|\.git$||')
    else
      repo=$(echo "$url" | sed 's|\.git$||')
    fi

    deps_json=$(echo "$deps_json" | jq \
      --arg r "$repo" \
      --arg v "$ver" \
      '. + {($r): $v}')
  done <<< "$decls"

  echo "$deps_json"
}

# ISO-8601 UTC timestamp.
iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Increment the collection's top-level `revision` field.
bump_revision() {
  local file="$1"
  local current new
  current=$(jq '.revision // 0' "$file")
  new=$((current + 1))
  local tmp
  tmp=$(mktemp)
  jq --argjson r "$new" --arg t "$(iso_now)" \
    '.revision = $r | .generatedAt = $t' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "$new"
}
