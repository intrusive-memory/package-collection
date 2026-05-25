# Dependency Purge - Implementation

## Execution Flow

```
1. Parse arguments (--rebuild, --scheme)
2. Detect project type and name
3. Execute purge steps (DerivedData, SPM cache, Package.resolved)
4. Bump intrusive-memory/* floor versions in Package.swift to latest releases
5. Report summary
6. [Optional] Rebuild if --rebuild flag present
7. Report final status
```

**Ordering invariant**: Step 4 MUST run after Package.resolved removal (step 3)
and BEFORE any `swift package resolve` / `xcodebuild` invocation (step 6).
Otherwise the resolver locks in stale floors and the bump has no effect on
the resolved graph until the next purge.

## Argument Parsing

```bash
REBUILD=false
SCHEME=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --rebuild)
      REBUILD=true
      shift
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done
```

## Project Detection

```bash
# Find .xcodeproj
XCODEPROJ=$(find . -maxdepth 1 -name "*.xcodeproj" -print -quit)

if [[ -n "$XCODEPROJ" ]]; then
  PROJECT_TYPE="xcode"
  PROJECT_NAME=$(basename "$XCODEPROJ" .xcodeproj)
elif [[ -f "Package.swift" ]]; then
  PROJECT_TYPE="spm"
  PROJECT_NAME=$(basename "$PWD")
else
  echo "ERROR: Not in an Xcode or SPM project directory."
  exit 1
fi

# Default scheme = project name if not specified
SCHEME=${SCHEME:-$PROJECT_NAME}
```

## Purge Execution

```bash
DERIVED_COUNT=0
SPM_REMOVED=false
RESOLVED_COUNT=0

# 1. Remove DerivedData
echo "Purging DerivedData for ${PROJECT_NAME}..."
DERIVED_DIRS=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "${PROJECT_NAME}-*" 2>/dev/null)
if [[ -n "$DERIVED_DIRS" ]]; then
  DERIVED_COUNT=$(echo "$DERIVED_DIRS" | wc -l | tr -d ' ')
  rm -rf ~/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*
  echo "✓ Removed $DERIVED_COUNT DerivedData director(y|ies)"
else
  echo "✓ No DerivedData found (already clean)"
fi

# 2. Clear SPM cache
echo "Clearing SPM cache..."
if [[ -d ~/Library/Caches/org.swift.swiftpm ]]; then
  rm -rf ~/Library/Caches/org.swift.swiftpm
  SPM_REMOVED=true
  echo "✓ SPM cache cleared"
else
  echo "✓ SPM cache already clear"
fi

# 3. Remove Package.resolved
echo "Removing Package.resolved..."

# Root Package.resolved
if [[ -f Package.resolved ]]; then
  rm Package.resolved
  RESOLVED_COUNT=$((RESOLVED_COUNT + 1))
  echo "✓ Removed root Package.resolved"
fi

# Xcode Package.resolved
XCODE_RESOLVED="${PROJECT_NAME}.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [[ -f "$XCODE_RESOLVED" ]]; then
  rm "$XCODE_RESOLVED"
  RESOLVED_COUNT=$((RESOLVED_COUNT + 1))
  echo "✓ Removed Xcode Package.resolved"
fi

if [[ $RESOLVED_COUNT -eq 0 ]]; then
  echo "✓ No Package.resolved found (no SPM dependencies or already removed)"
fi
```

## Bump intrusive-memory floor versions

Runs after Package.resolved removal, before any resolve/build. Requires `gh`
authenticated to read public releases (anonymous works for public repos but
is rate-limited).

```bash
IM_UPDATED=0
IM_SKIPPED=0
IM_TOTAL=0

if [[ -f Package.swift ]]; then
  echo ""
  echo "Bumping intrusive-memory/* floor versions to latest releases..."

  # Extract every intrusive-memory dep name from Package.swift.
  # Matches https://github.com/intrusive-memory/<name>(.git)? in .package(url:) lines.
  IM_DEPS=$(grep -oE 'github\.com/intrusive-memory/[a-zA-Z0-9._-]+' Package.swift \
    | sed -E 's#github\.com/intrusive-memory/##; s#\.git$##' \
    | sort -u)

  if [[ -z "$IM_DEPS" ]]; then
    echo "  (no intrusive-memory/* dependencies found)"
  else
    # Backup once, in case something goes sideways.
    cp Package.swift Package.swift.purge.bak

    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      IM_TOTAL=$((IM_TOTAL + 1))

      # Latest published release tag (NOT a tag — must be a release).
      LATEST=$(gh release view --repo "intrusive-memory/$dep" \
                 --json tagName -q .tagName 2>/dev/null)

      if [[ -z "$LATEST" ]]; then
        echo "  ⚠ $dep: no published releases — skipped"
        IM_SKIPPED=$((IM_SKIPPED + 1))
        continue
      fi

      # Strip leading 'v' if present.
      LATEST_VER="${LATEST#v}"

      # Validate semver-ish shape (avoid pasting garbage into Package.swift).
      if ! [[ "$LATEST_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-].+)?$ ]]; then
        echo "  ⚠ $dep: tag '$LATEST' is not semver — skipped"
        IM_SKIPPED=$((IM_SKIPPED + 1))
        continue
      fi

      # Skip branch/revision-pinned deps for this package.
      if grep -E "intrusive-memory/$dep(\.git)?\"," Package.swift \
           | grep -qE 'branch:|revision:'; then
        echo "  ⚠ $dep: branch/revision-pinned — left untouched"
        IM_SKIPPED=$((IM_SKIPPED + 1))
        continue
      fi

      OLD_LINE=$(grep -nE "intrusive-memory/$dep(\.git)?\"" Package.swift | head -1)

      # Rewrite the version requirement on lines that reference this dep.
      # Patterns handled (Python is safer than sed for multi-pattern rewrites).
      python3 - "$dep" "$LATEST_VER" <<'PY'
import re, sys, pathlib
dep, new = sys.argv[1], sys.argv[2]
p = pathlib.Path("Package.swift")
src = p.read_text()

# Find each line containing this dep's URL, rewrite version arg only on those lines.
out_lines = []
url_re = re.compile(rf'github\.com/intrusive-memory/{re.escape(dep)}(\.git)?')
patterns = [
    # from: "X.Y.Z"
    (re.compile(r'(from:\s*")[^"]+(")'),                 rf'\g<1>{new}\g<2>'),
    # .upToNextMajor(from: "X.Y.Z") / .upToNextMinor(from: "X.Y.Z")
    (re.compile(r'(\.upToNext(?:Major|Minor)\(from:\s*")[^"]+(")'),
                                                          rf'\g<1>{new}\g<2>'),
    # exact: "X.Y.Z"
    (re.compile(r'(exact:\s*")[^"]+(")'),                 rf'\g<1>{new}\g<2>'),
    # "X.Y.Z"..<"A.B.C"  -> bump lower bound only
    (re.compile(r'"[^"]+"(\s*\.\.<\s*)"'),                rf'"{new}"\g<1>"'),
    # sibling("name", from: "X.Y.Z")  (toggle-sibling-libraries helper)
    (re.compile(r'(sibling\(\s*"[^"]+"\s*,\s*from:\s*")[^"]+(")'),
                                                          rf'\g<1>{new}\g<2>'),
]

for line in src.splitlines(keepends=True):
    if url_re.search(line):
        for pat, repl in patterns:
            line = pat.sub(repl, line)
    out_lines.append(line)

p.write_text("".join(out_lines))
PY

      NEW_LINE=$(grep -nE "intrusive-memory/$dep(\.git)?\"" Package.swift | head -1)
      if [[ "$OLD_LINE" != "$NEW_LINE" ]]; then
        echo "  ✓ $dep → $LATEST_VER"
        IM_UPDATED=$((IM_UPDATED + 1))
      else
        echo "  · $dep already at $LATEST_VER (no change)"
      fi
    done <<< "$IM_DEPS"

    # If nothing actually changed, drop the backup.
    if ! diff -q Package.swift Package.swift.purge.bak >/dev/null 2>&1; then
      echo "  (backup saved to Package.swift.purge.bak)"
    else
      rm -f Package.swift.purge.bak
    fi
  fi
fi
```

## Summary Report

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dependency Purge Complete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Project: ${PROJECT_NAME} (${PROJECT_TYPE})"
echo ""
echo "✓ DerivedData: $DERIVED_COUNT director(y|ies) removed"
echo "✓ SPM cache: $([ "$SPM_REMOVED" = true ] && echo "cleared" || echo "already clean")"
echo "✓ Package.resolved: $RESOLVED_COUNT location(s) removed"
if [[ $IM_TOTAL -gt 0 ]]; then
  echo "✓ intrusive-memory floors: $IM_UPDATED of $IM_TOTAL bumped ($IM_SKIPPED skipped)"
fi
echo ""
echo "Fresh dependency resolution will occur on next build."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

## Rebuild (Optional)

```bash
if [[ "$REBUILD" = true ]]; then
  echo ""
  echo "Rebuilding ${SCHEME}..."
  echo ""
  
  if [[ "$PROJECT_TYPE" = "xcode" ]]; then
    # Xcode project build
    xcodebuild build \
      -scheme "$SCHEME" \
      -destination 'platform=macOS,arch=arm64' \
      CLANG_ENABLE_CODE_COVERAGE=NO \
      GCC_GENERATE_TEST_COVERAGE_FILES=NO
    
    BUILD_EXIT=$?
  else
    # SPM package build
    swift build
    BUILD_EXIT=$?
  fi
  
  echo ""
  if [[ $BUILD_EXIT -eq 0 ]]; then
    echo "✓ Build succeeded after purge"
  else
    echo "✗ Build failed after purge"
    echo ""
    echo "This usually means:"
    echo "1. Dependency versions are incompatible"
    echo "2. Network issue prevented dependency download"
    echo "3. Underlying code/config issue (not cache-related)"
    echo ""
    echo "Investigate build errors above."
    exit 1
  fi
fi
```

## Claude Integration

When Claude invokes this skill, it should:

1. **Detect context**: Check if current issue matches purge-fixable patterns
2. **Ask user**: "This looks like a cache/dependency issue. Run dependency purge? [Y/n]"
3. **Execute**: Call `/dependency-purge --rebuild` if confirmed
4. **Verify**: Check build output for success
5. **Resume**: If purge fixed it, continue with mission; if not, escalate

### Purge-Fixable Pattern Detection

```
Known patterns that dependency-purge can fix:
- "Undefined symbol: ___llvm_profile_runtime"
- "Undefined symbols for architecture arm64"
- "ComplexModule symbols missing from MLX.framework"
- "No such module" when module exists
- "Could not resolve package dependencies"
- "Package.resolved is out of date"
- Xcode 26 transitive dylib bugs
```

### Integration with Mission Supervisor

The Mission Supervisor should invoke dependency-purge when:

1. A sortie agent escalates per the 2-turn rule
2. The error message matches known patterns (above)
3. Before marking a sortie as FATAL

Workflow:
```
Sortie fails → Check error → Match pattern? → Run purge → Retry sortie
                                             ↓
                                          No match → Escalate to user
```

---

**Status**: Ready for integration  
**Testing**: Validated on Produciesta (MLX linker issue resolution)
