# Fix Xcode Architecture — Force arm64

Finds and replaces all occurrences of `$(ARCHS_STANDARD)` in Xcode project files with explicit `arm64`, and ensures xcconfig files enforce arm64-only builds. Use when Xcode or Xcode Cloud builds are compiling for Intel (x86_64) instead of Apple Silicon.

## When to Use

This skill addresses these symptoms:

- Xcode Cloud builds compiling for x86_64 / Intel
- `lipo` or linker errors referencing x86_64 slices
- Test targets building for the wrong architecture
- SPM dependencies pulling in x86_64 variants

## Root Cause

`ARCHS = "$(ARCHS_STANDARD)"` expands to **both** `arm64` and `x86_64`. On Xcode Cloud runners (or any environment where the build system doesn't filter architectures), this causes Intel builds. The `EXCLUDED_ARCHS` xcconfig setting is supposed to counteract this, but target-level `ARCHS` settings take precedence over xcconfig-level `EXCLUDED_ARCHS`, creating a loophole.

## Implementation

When this skill is invoked:

### Step 1: Find All Xcode Projects

Search the working directory for `.xcodeproj` bundles:

```bash
find . -name "*.xcodeproj" -maxdepth 3
```

### Step 2: Scan project.pbxproj for ARCHS_STANDARD

For each project found, search `project.pbxproj` for any reference to `ARCHS_STANDARD`:

```
grep -n 'ARCHS_STANDARD' <project>/project.pbxproj
```

Report the count and which build configurations are affected. Show surrounding context (the configuration name and target identifier) so the user knows exactly what will change.

### Step 3: Identify Affected Targets

For each `ARCHS = "$(ARCHS_STANDARD)"` occurrence, read the surrounding build configuration block to determine:
- The configuration ID (e.g., `D6F089202F6B77AF00117A36`)
- Debug vs Release
- Which target it belongs to (look for `PRODUCT_BUNDLE_IDENTIFIER`, `TEST_TARGET_NAME`, or `TEST_HOST` to identify the target)

Report findings like:
```
Found 6 configurations using $(ARCHS_STANDARD):
  - VinetasIOS Debug (D6F089202F6B77AF00117A36)
  - VinetasIOS Release (D6F089212F6B77AF00117A36)
  - VinetasIOSTests Debug (D6F089222F6B77AF00117A36)
  - VinetasIOSTests Release (D6F089232F6B77AF00117A36)
  - VinetasIOSUITests Debug (D6F089242F6B77AF00117A36)
  - VinetasIOSUITests Release (D6F089252F6B77AF00117A36)
```

### Step 4: Replace in project.pbxproj

For each affected configuration, use the Edit tool to replace:

```
ARCHS = "$(ARCHS_STANDARD)";
```

with:

```
ARCHS = arm64;
```

Each edit must target a unique context (include the configuration ID line to ensure uniqueness). Do NOT use sed or global find-replace on `project.pbxproj` — use the Edit tool for each occurrence so the user can review changes.

### Step 5: Ensure xcconfig Enforcement

Find all `.xcconfig` files in the project:

```bash
find . -name "*.xcconfig" -maxdepth 3
```

For each xcconfig, check whether it already contains architecture enforcement. If not, add:

```
// Force arm64 only — no Intel builds
ARCHS = arm64
EXCLUDED_ARCHS = x86_64
VALID_ARCHS = arm64
```

If the xcconfig already has `EXCLUDED_ARCHS` or `VALID_ARCHS` but is missing `ARCHS = arm64`, add it. The xcconfig serves as a fallback for any configuration that doesn't set `ARCHS` at the target level.

### Step 6: Verify No Remaining References

Run a final scan to confirm zero `ARCHS_STANDARD` references remain:

```
grep -rn 'ARCHS_STANDARD' <project>/project.pbxproj
```

If any remain, report them and fix them.

### Step 7: Report Summary

Print a summary of all changes made:
- Number of configurations fixed
- Which targets were affected
- Which xcconfig files were updated
- Recommend building to verify (using the project's preferred build method)

## What This Skill Does NOT Do

- Does not create ci_scripts or CI/CD hooks (that's a separate concern)
- Does not modify scheme files
- Does not change deployment targets or SDK settings
- Does not commit changes (leave that to the user)

## Notes

- `VALID_ARCHS` is deprecated in newer Xcode versions but still respected. Including it provides defense-in-depth for older toolchains.
- Target-level build settings always override xcconfig settings. That's why both must be fixed — the xcconfig catches new targets that forget to set `ARCHS` explicitly, and the target-level fix handles existing configurations.
- `$(ARCHS_STANDARD)` is the default Xcode uses when creating new targets. Any time a new target is added to the project, this skill should be re-run to catch it.
