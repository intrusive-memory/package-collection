# Fix Xcode Architecture Skill

**Category:** Build & CI/CD
**Platforms:** macOS, iOS
**Complexity:** Low

## Description

Scans Xcode project files for `$(ARCHS_STANDARD)` references and replaces them with explicit `arm64` (Apple Silicon). Also ensures xcconfig files enforce arm64-only builds with `EXCLUDED_ARCHS = x86_64`.

## When to Use

Invoke this skill when you encounter:

- Xcode Cloud building for Intel / x86_64 instead of Apple Silicon
- Linker or lipo errors referencing x86_64 slices
- New targets added to the project (Xcode defaults new targets to `$(ARCHS_STANDARD)`)
- After Xcode migrations that may reset architecture settings

## Usage

```bash
/xcode-fix-arches
```

Or via Claude:
```
"Fix the architecture settings in my Xcode project"
"My Xcode Cloud builds are compiling for Intel"
"Run xcode-fix-arches"
```

## What It Does

1. **Scans** all `.xcodeproj/project.pbxproj` files for `ARCHS_STANDARD`
2. **Identifies** which targets and configurations are affected
3. **Replaces** `ARCHS = "$(ARCHS_STANDARD)"` with `ARCHS = arm64`
4. **Updates** `.xcconfig` files to include `ARCHS = arm64` as a fallback
5. **Verifies** no `ARCHS_STANDARD` references remain

## Why This Matters

`$(ARCHS_STANDARD)` expands to `arm64 + x86_64`. Target-level `ARCHS` settings override xcconfig-level `EXCLUDED_ARCHS`, so even with `EXCLUDED_ARCHS = x86_64` in your xcconfig, any target that explicitly sets `ARCHS = $(ARCHS_STANDARD)` will still build for Intel.

## Safety

- Idempotent — safe to run multiple times
- Uses Edit tool per-occurrence, not global sed
- Does not commit — leaves that to the user
- Does not modify schemes, test plans, or deployment targets
