# Dependency Purge Skill

Full nuclear clean for Xcode/SPM build issues. Removes all build artifacts, clears caches, and forces fresh dependency resolution.

## When to Use

Invoke when encountering transient build issues:
- Linker errors with SPM dependencies (MLX, swift-cmark, etc.)
- "Undefined symbol" errors that aren't in your code
- Package resolution conflicts
- Stale DerivedData causing phantom errors
- After major dependency updates
- Code coverage instrumentation leaking through

**Trigger phrases**: "clean build", "purge dependencies", "clear caches", "reset build state", "nuclear clean", "fresh dependency resolution"

## What It Does

Performs a complete build reset:

1. **Remove DerivedData** - Deletes all build artifacts for the project
2. **Clear SPM cache** - Removes `~/Library/Caches/org.swift.swiftpm`
3. **Remove Package.resolved** - Forces fresh dependency resolution (both root and Xcode project versions)
4. **Bump intrusive-memory floors** - For every `intrusive-memory/*` dependency in `Package.swift`, sets the floor version to the latest published GitHub release **before** SPM resolves. Prevents resolution from picking a stale floor.
5. **Rebuild** (optional) - Triggers a clean build with explicit flags

## Usage

```
/dependency-purge [--rebuild] [--scheme SCHEME_NAME]
```

### Arguments

- `--rebuild` (optional) - Trigger a build after purging
- `--scheme SCHEME_NAME` (optional) - Which scheme to build (defaults to project name)

### Examples

```bash
# Basic purge (no rebuild)
/dependency-purge

# Purge and rebuild default scheme
/dependency-purge --rebuild

# Purge and rebuild specific scheme
/dependency-purge --rebuild --scheme produciesta-cli
```

## Implementation

### Step 1: Detect Project

Look for indicators of project type:
1. Check for `.xcodeproj` directory → Xcode project
2. Check for `Package.swift` → SPM package
3. Both present → Xcode project with SPM dependencies (most common)

Extract project name from `.xcodeproj` directory name (strip `.xcodeproj` suffix).

### Step 2: Remove DerivedData

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*
```

**Note**: The glob pattern matches all DerivedData directories for this project (Xcode appends a hash suffix).

### Step 3: Clear SPM Cache

```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
```

**Important**: This is global SPM cache, not project-specific. Clears cached packages for all projects.

### Step 4: Remove Package.resolved

Check both locations:

```bash
# Root Package.resolved (if SPM package)
test -f Package.resolved && rm Package.resolved

# Xcode's Package.resolved (if Xcode project)
test -f ${PROJECT_NAME}.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && \
  rm ${PROJECT_NAME}.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

### Step 5: Bump intrusive-memory floor versions

**Runs only if `Package.swift` exists at the repo root.** Must execute **after** `Package.resolved` removal and **before** any SPM resolve/build, so the resolver sees the new floors on its first pass.

For every dependency in `Package.swift` whose URL matches `github.com/intrusive-memory/<name>`:

1. Resolve the latest **published release** (not tag) via `gh`:
   ```bash
   gh release view --repo intrusive-memory/<name> --json tagName -q .tagName
   ```
   - Strip a leading `v` if present.
   - Skip the dep (with a warning) if there are no published releases yet.
2. Rewrite the version requirement in `Package.swift` so the floor equals that release. Supported forms:
   - `.package(url: "…/intrusive-memory/<name>(.git)?", from: "X.Y.Z")`
   - `.package(url: "…", .upToNextMajor(from: "X.Y.Z"))`
   - `.package(url: "…", .upToNextMinor(from: "X.Y.Z"))`
   - `.package(url: "…", exact: "X.Y.Z")`
   - `.package(url: "…", "X.Y.Z"..<"A.B.C")` — bump the lower bound only.
3. Branch-pinned deps (`branch:` / `revision:`) are **left untouched** — print a warning so the human knows the floor wasn't bumped.
4. Sibling-helper pattern (`sibling("name", from: "X.Y.Z")` from [[toggle-sibling-libraries]]) is also rewritten: bump the `from:` argument.

Report each dep with its old → new floor. If nothing changed, say so.

### Step 6: Report

Output summary:
```
Dependency purge complete:
✓ DerivedData cleaned (N directories removed)
✓ SPM cache cleared
✓ Package.resolved removed (M locations)
✓ intrusive-memory floors bumped (K of L deps updated)

Fresh dependency resolution will occur on next build.
```

### Step 7: Rebuild (if --rebuild flag present)

If `--rebuild` flag is present:

1. Determine build command based on project type:
   - Xcode project: `xcodebuild build -scheme ${SCHEME}`
   - SPM package: `swift build`

2. Add critical flags for Xcode builds:
   - `CLANG_ENABLE_CODE_COVERAGE=NO`
   - `GCC_GENERATE_TEST_COVERAGE_FILES=NO`
   - (Prevents Xcode 26 code coverage linker issues)

3. Run build in foreground (user sees progress)

4. Report result:
   - Success: "Build succeeded after purge"
   - Failure: "Build failed - underlying issue requires investigation"

## Error Handling

### DerivedData Not Found
```
No DerivedData found for ${PROJECT_NAME}.
(This is normal if you haven't built the project recently)
```

### No Package.resolved Found
```
No Package.resolved found.
(This is normal for projects without SPM dependencies)
```

### Not in a Project Directory
```
ERROR: Not in an Xcode or SPM project directory.
Run this command from a directory containing:
- *.xcodeproj (Xcode project), or
- Package.swift (SPM package)
```

### Build Fails After Purge
```
Build failed after purge.

This usually means:
1. Dependency versions are incompatible (check Package.resolved diff)
2. Network issue prevented dependency download
3. Underlying code/config issue (not cache-related)

Investigate build errors above.
```

## Integration with Mission Supervisor

When the Mission Supervisor encounters build/test failures and an agent escalates per the "2-turn rule":

1. Supervisor checks if error matches known purge-fixable patterns:
   - "Undefined symbol: ___llvm_profile_runtime"
   - "Undefined symbols for architecture"
   - "ComplexModule symbols missing"
   - SPM resolution conflicts

2. If match found, supervisor invokes `/dependency-purge --rebuild --scheme ${TEST_SCHEME}`

3. If purge+rebuild succeeds, supervisor resumes the sortie (continuation dispatch)

4. If purge+rebuild fails, supervisor escalates to user (not a cache issue)

## Safety Notes

- **Non-destructive**: Only removes build artifacts and caches, never source code
- **Idempotent**: Safe to run multiple times (later runs are no-ops)
- **Global SPM cache**: Affects all projects (they'll re-download dependencies)
- **Time cost**: Fresh dependency resolution can take 2-5 minutes for large projects
- **Network required**: SPM will re-fetch remote dependencies

## Related Documentation

- `Docs/CODE_COVERAGE_DISABLED.md` - Why explicit coverage flags are needed
- `MEMORY.md` - Xcode 26 transitive dylib bug notes
- `CLAUDE.md` - Build preferences (XcodeBuildMCP, xcodebuild patterns)

---

**Last Updated**: 2026-05-25  
**Status**: Production-ready
