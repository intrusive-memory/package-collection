#!/opt/homebrew/bin/bash
#
# generate-collection.sh
# Queries GitHub API for each repo, extracts version/targets/products from
# Package.swift, and builds collection.json.
#
# Requirements: gh (GitHub CLI), jq, curl
# Usage: ./generate-collection.sh [output-file]
#        Default output: collection.json in the same directory as this script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-${SCRIPT_DIR}/collection.json}"

# Repos: owner/name pairs
REPOS=(
  "intrusive-memory/SwiftBruja"
  "intrusive-memory/SwiftCompartido"
  "intrusive-memory/SwiftFFMpeg"
  "intrusive-memory/SwiftFijos"
  "intrusive-memory/SwiftHablare"
  "intrusive-memory/SwiftProyecto"
  "intrusive-memory/SwiftPruebas"
  "intrusive-memory/SwiftSecuencia"
  "intrusive-memory/SwiftEchada"
  "intrusive-memory/SwiftVoxAlta"
)

# Package metadata (summary, keywords) keyed by repo name
declare -A SUMMARIES=(
  [SwiftBruja]="On-device LLM inference for Apple Silicon via MLX. One-line queries with auto-download."
  [SwiftCompartido]="Screenplay parsing, SwiftData models, and SwiftUI display components. Supports Fountain, FDX, PDF, Highland, and more."
  [SwiftFFMpeg]="Swift wrapper for FFmpeg API for audio/video processing."
  [SwiftFijos]="Test fixture file discovery for Swift packages and Xcode projects."
  [SwiftHablare]="Voice generation library with Apple TTS, ElevenLabs, and Qwen TTS providers. SwiftUI components included."
  [SwiftProyecto]="Project metadata management, file discovery, and PROJECT.md parsing for screenplay projects."
  [SwiftPruebas]="Shared test utilities and helpers for the Intrusive Memory ecosystem."
  [SwiftSecuencia]="FCPXML timeline generation and audio export for Final Cut Pro X integration."
  [SwiftEchada]="Shared Swift utilities and extensions for the Intrusive Memory ecosystem."
  [SwiftVoxAlta]="On-device Qwen3-TTS voice design and cloning for SwiftHablare. Character voice pipeline with VoiceDesign, Base model cloning, and diga CLI."
)

declare -A KEYWORDS=(
  [SwiftBruja]='["llm","mlx","ai","apple-silicon"]'
  [SwiftCompartido]='["screenplay","fountain","parser","swiftui","swiftdata"]'
  [SwiftFFMpeg]='["ffmpeg","audio","video","media"]'
  [SwiftFijos]='["testing","fixtures","test-utilities"]'
  [SwiftHablare]='["tts","voice","audio","speech-synthesis","elevenlabs"]'
  [SwiftProyecto]='["project","metadata","file-discovery","yaml"]'
  [SwiftPruebas]='["testing","test-utilities"]'
  [SwiftSecuencia]='["fcpxml","final-cut-pro","timeline","audio-export"]'
  [SwiftEchada]='["utilities","extensions","swift"]'
  [SwiftVoxAlta]='["tts","qwen3","voice-cloning","voice-design","on-device","mlx"]'
)

# Get latest version tag for a repo. Tries releases first, falls back to tags.
get_latest_version() {
  local repo="$1"
  local version

  # Try latest release
  version=$(gh api "repos/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null || true)

  # Fall back to latest tag
  if [[ -z "$version" ]]; then
    version=$(gh api "repos/${repo}/tags" --jq '.[0].name' 2>/dev/null || true)
  fi

  # Strip leading 'v' if present
  version="${version#v}"
  echo "$version"
}

# Fetch Package.swift content from the repo default branch
get_package_swift() {
  local repo="$1"
  local ref="${2:-}"
  local url="repos/${repo}/contents/Package.swift"
  if [[ -n "$ref" ]]; then
    url="${url}?ref=${ref}"
  fi
  gh api "$url" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true
}

# Extract swift-tools-version from Package.swift content (passed via stdin)
extract_tools_version() {
  # First line like: // swift-tools-version: 6.2
  head -1 | sed -n 's|.*swift-tools-version:[[:space:]]*||p' | tr -d '[:space:]'
}

# Extract package name from Package.swift content
extract_package_name() {
  grep -oE 'name:[[:space:]]*"[^"]*"' | head -1 | sed 's/name:[[:space:]]*"//;s/"//'
}

# Extract product names and their targets from Package.swift
# Outputs JSON array of product objects
extract_products() {
  local content="$1"
  local pkg_name="$2"

  # Try to parse .library(name: "X", targets: ["Y", ...]) patterns
  # This is a best-effort regex parse -- not a full Swift parser
  local products="[]"

  # Extract library product declarations
  while IFS= read -r line; do
    local name target_list
    name=$(echo "$line" | grep -oE 'name:[[:space:]]*"[^"]*"' | head -1 | sed 's/name:[[:space:]]*"//;s/"//')
    target_list=$(echo "$line" | grep -oE 'targets:[[:space:]]*\[[^]]*\]' | head -1 | sed 's/targets:[[:space:]]*\[//;s/\]//' | tr -d ' "')

    if [[ -n "$name" && -n "$target_list" ]]; then
      local targets_json="[]"
      IFS=',' read -ra tgts <<< "$target_list"
      for t in "${tgts[@]}"; do
        targets_json=$(echo "$targets_json" | jq --arg t "$t" '. + [$t]')
      done
      products=$(echo "$products" | jq --arg n "$name" --argjson tgts "$targets_json" \
        '. + [{"name": $n, "type": {"library": ["automatic"]}, "targets": $tgts}]')
    fi
  done < <(echo "$content" | grep -E '\.library\(' || true)

  # Fallback: if no products found, use package name as single product+target
  if [[ "$(echo "$products" | jq 'length')" == "0" ]]; then
    products=$(jq -n --arg n "$pkg_name" \
      '[{"name": $n, "type": {"library": ["automatic"]}, "targets": [$n]}]')
  fi

  echo "$products"
}

# Extract targets (just names + moduleNames) from products JSON
extract_targets_from_products() {
  local products_json="$1"
  echo "$products_json" | jq '[.[].targets[]] | unique | [.[] | {"name": ., "moduleName": .}]'
}

# Extract platform versions from Package.swift
extract_platforms() {
  local content="$1"

  local platforms="[]"

  # Match patterns like .macOS(.v26), .iOS(.v26), .macOS("26.0"), etc.
  if echo "$content" | grep -qE '\.macOS'; then
    local ver
    ver=$(echo "$content" | grep -oE '\.macOS\([^)]*\)' | head -1 | grep -oE '[0-9]+[.0-9]*' | head -1)
    if [[ -n "$ver" ]]; then
      [[ "$ver" == *"."* ]] || ver="${ver}.0"
      platforms=$(echo "$platforms" | jq --arg v "$ver" '. + [{"name":"macOS","version":$v}]')
    fi
  fi

  if echo "$content" | grep -qE '\.iOS'; then
    local ver
    ver=$(echo "$content" | grep -oE '\.iOS\([^)]*\)' | head -1 | grep -oE '[0-9]+[.0-9]*' | head -1)
    if [[ -n "$ver" ]]; then
      [[ "$ver" == *"."* ]] || ver="${ver}.0"
      platforms=$(echo "$platforms" | jq --arg v "$ver" '. + [{"name":"iOS","version":$v}]')
    fi
  fi

  echo "$platforms"
}

# --- Main ---

echo "Generating Swift Package Collection..."

PACKAGES_JSON="[]"

for repo in "${REPOS[@]}"; do
  name="${repo##*/}"
  echo "Processing ${repo}..."

  version=$(get_latest_version "$repo")
  if [[ -z "$version" ]]; then
    echo "  WARNING: No version found for ${repo}, skipping."
    continue
  fi
  echo "  Version: ${version}"

  pkg_swift=$(get_package_swift "$repo" "v${version}")
  if [[ -z "$pkg_swift" ]]; then
    # Try without v prefix
    pkg_swift=$(get_package_swift "$repo" "${version}")
  fi
  if [[ -z "$pkg_swift" ]]; then
    # Try default branch
    pkg_swift=$(get_package_swift "$repo")
  fi

  if [[ -z "$pkg_swift" ]]; then
    echo "  WARNING: Could not fetch Package.swift for ${repo}, skipping."
    continue
  fi

  tools_version=$(echo "$pkg_swift" | extract_tools_version)
  pkg_name=$(echo "$pkg_swift" | extract_package_name)
  pkg_name="${pkg_name:-$name}"
  echo "  Package: ${pkg_name}, tools: ${tools_version}"

  products=$(extract_products "$pkg_swift" "$pkg_name")
  targets=$(extract_targets_from_products "$products")
  platforms=$(extract_platforms "$pkg_swift")

  summary="${SUMMARIES[$name]:-Swift package ${name}}"
  keywords="${KEYWORDS[$name]:-[]}"

  # Determine owner for URL
  owner="${repo%%/*}"
  repo_url="https://github.com/${repo}.git"
  readme_url="https://github.com/${repo}/blob/main/README.md"

  # Build package entry
  pkg_json=$(jq -n \
    --arg url "$repo_url" \
    --arg summary "$summary" \
    --argjson keywords "$keywords" \
    --arg readme "$readme_url" \
    --arg version "$version" \
    --arg tools "$tools_version" \
    --arg pkgName "$pkg_name" \
    --argjson targets "$targets" \
    --argjson products "$products" \
    --argjson platforms "$platforms" \
    '{
      url: $url,
      summary: $summary,
      keywords: $keywords,
      readmeURL: $readme,
      versions: [{
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
      }]
    }')

  PACKAGES_JSON=$(echo "$PACKAGES_JSON" | jq --argjson pkg "$pkg_json" '. + [$pkg]')
done

# Build final collection
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Compute revision: increment from existing if present
EXISTING_REVISION=0
if [[ -f "$OUTPUT" ]]; then
  EXISTING_REVISION=$(jq '.revision // 0' "$OUTPUT" 2>/dev/null || echo 0)
fi
NEW_REVISION=$((EXISTING_REVISION + 1))

jq -n \
  --arg name "Intrusive Memory Swift Packages" \
  --arg overview "Screenplay visualization and audio generation libraries by Intrusive Memory. Powers the Produciesta ecosystem for transforming screenplays into audio performances." \
  --argjson revision "$NEW_REVISION" \
  --arg generatedAt "$GENERATED_AT" \
  --argjson packages "$PACKAGES_JSON" \
  '{
    name: $name,
    overview: $overview,
    keywords: ["screenplay","tts","audio","swift","intrusive-memory"],
    formatVersion: "1.0",
    revision: $revision,
    generatedAt: $generatedAt,
    generatedBy: { name: "Intrusive Memory" },
    packages: $packages
  }' > "$OUTPUT"

echo "Collection written to ${OUTPUT} with ${#REPOS[@]} packages (revision ${NEW_REVISION})."
