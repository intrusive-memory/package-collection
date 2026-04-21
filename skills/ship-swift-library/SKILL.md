---
name: ship-swift-library
description: Ship and release Swift library versions by bumping the version on a short-lived release branch, merging the PR once CI passes, then tagging and creating a GitHub release from main
allowed-tools: Bash, Read, Grep, Glob, Edit, Skill
dependencies:
  - organize-agent-docs
---

# Ship Swift Library Skill

This skill handles the complete release process for Swift libraries.

**CRITICAL RULE**: Bump the version on a short-lived `release/vX.Y.Z` branch and ship it via a PR squash-merged into `main`. NEVER push the version bump directly to `main` — CI must run on the PR before the release is tagged.

## Process Overview

You will perform the following 10 steps in order. The library uses a single `main` branch; release work happens on a short-lived `release/vX.Y.Z` branch that is deleted after merge.

### 1. Determine Version Number

**CRITICAL**: The version string embedded in source code is NOT authoritative. It may be stale, wrong, or ahead of what was actually released. Always derive the current version from git tags.

```bash
git fetch --tags
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -5
```

This lists the most recent semver tags in descending order. The first result is the last released version. If no tags exist, treat the last released version as `v0.0.0`.

Also check the source file version for reference only — do not trust it as the authoritative released version:

```bash
grep 'version' Sources/<LibraryName>/<LibraryName>.swift
```

If the source version differs from the latest tag, flag this to the user before proceeding.

Ask the user what version this release should be, presenting the last tagged version as the baseline. Version increment rules:
- **Patch** (x.y.Z): Bug fixes, small improvements
- **Minor** (x.Y.0): New features, non-breaking changes
- **Major** (X.0.0): Breaking changes

### 2. Create Release Branch

Start from a clean `main` and cut a short-lived release branch:

```bash
git checkout main
git pull origin main
git checkout -b release/vX.Y.Z
```

The release branch lives only for the duration of this release and is deleted by `gh pr merge --delete-branch` in step 5.

### 3. Bump Version, Update Dependencies, and Audit Documentation

Edit the version file (e.g. `Sources/<LibraryName>/<LibraryName>.swift`).

**CRITICAL: Audit and Update All Dependencies in Package.swift**

Before making any other changes, check Package.swift for issues:

1. **Check for local file path references** — NO local dependencies:
   ```bash
   grep -n '\.path(' Package.swift
   ```
   If any `.path()` references exist, they MUST be replaced with GitHub repository URLs or removed. Local paths cannot be shipped.

2. **Query the latest version of each dependency** — Update all `package()` declarations to use the latest published version from GitHub releases, pinned to the next major version. For each dependency:
   ```bash
   gh api repos/<OWNER>/<REPO>/releases --jq '.[0].tag_name'
   ```

3. **Update Package.swift** — Modify all `.package()` declarations:
   - Replace `.path()` with GitHub URLs: `.package(url: "https://github.com/...", ...)`
   - Replace pinned versions with `.upToNextMajor(from: "X.Y.Z")` where X is the next major version boundary
   - **Example transformations**:
     - Old: `from: "0.5.0"` → New: `.upToNextMajor(from: "0.5.0")` (pins to <1.0.0)
     - Old: `from: "1.2.0"` → New: `.upToNextMajor(from: "1.2.0")` (pins to <2.0.0)
     - Old: `from: "5.0.0"` → New: `.upToNextMajor(from: "5.7.5")` (if latest is 5.7.5, pins to <6.0.0)
   - If a dependency has breaking changes in a new major version, keep the `.upToNextMajor()` pattern (don't pin to exact version unless necessary for compatibility)

4. **Verify all dependencies reference published versions** — Run:
   ```bash
   swift package describe --format json | jq '.dependencies[] | {name, url, requirement}'
   ```
   Confirm all URLs are GitHub repositories (not local paths) and all requirements use `.upToNextMajor()` or explicit version ranges.

**Run `make lint` to format all Swift source files before committing:**

```bash
make lint
```

This runs `swift format -i -r .` across the entire project. Any formatting changes will be included in the commit.

**Then organize and update project documentation** using the organize-agent-docs skill:

```
/organize-agent-docs
```

This will:
- Ensure AGENTS.md contains universal project documentation (architecture, APIs, dependencies)
- Ensure CLAUDE.md contains only Claude-specific instructions (tool preferences, build requirements)
- Ensure GEMINI.md contains only Gemini-specific instructions
- Update version numbers across all documentation
- Verify documentation structure follows best practices
- Check that agent-specific files properly reference AGENTS.md

**After running organize-agent-docs**, also update README.md:
- Update version numbers in installation examples
- Verify all code examples work with current API
- Add new features to feature list
- Update platform requirements (iOS/macOS/Swift/Xcode versions)
- Verify all doc links point to existing files

Commit everything together — version bump + dependency updates + lint fixes + doc updates — in a single commit:

```bash
git add Package.swift Sources/<LibraryName>/<LibraryName>.swift README.md AGENTS.md CLAUDE.md GEMINI.md
git commit -m "Bump version to X.Y.Z, update dependencies, and update documentation

Dependencies updated to latest published versions:
- All local path references replaced with GitHub URLs
- All dependencies pinned to next major version boundary

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push -u origin release/vX.Y.Z
```

### 4. Open Pull Request and Verify CI

Open the release PR from the release branch to main:

```bash
gh pr create \
  --base main \
  --head release/vX.Y.Z \
  --title "Release vX.Y.Z" \
  --body "$(cat <<'EOF'
## Release vX.Y.Z

Version bump, dependency audit, lint, and documentation updates for the vX.Y.Z release.

### Changes
- Version bumped to vX.Y.Z
- Dependencies audited and pinned to `.upToNextMajor()`
- Documentation organized with `/organize-agent-docs`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Wait for CI to complete:

```bash
gh pr checks <PR_NUMBER> --watch
```

If any checks fail, stop and report — do not proceed to merge.

### 5. Squash-Merge and Delete the Release Branch

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch
```

**Important**:
- `--squash` keeps `main` history clean (single commit per release)
- `--delete-branch` removes both the local and remote `release/vX.Y.Z` branch
- The squash commit on `main` now contains the version bump

### 6. Pull Merge Commit to Local Main

```bash
git checkout main
git pull origin main
```

Verify you're on the squash merge commit:

```bash
git log --oneline -1
```

### 7. Create Annotated Tag on Main

Tag the squash merge commit on main:

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z: <Short description>

<Detailed release notes>

Generated with [Claude Code](https://claude.com/claude-code)"

git push origin vX.Y.Z
```

### 8. Create GitHub Release (metadata only — NO tarball upload)

Create a GitHub release from the tag. **Do NOT upload any tarball or binary assets** — the `release.yml` CI workflow fires automatically on `release: published` and builds + uploads the canonical tarball, then dispatches the Homebrew formula update.

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z: <Title>" \
  --notes "$(cat <<'EOF'
# <Library Name> vX.Y.Z

## <Emoji> <Feature Category>

<Description of what this release adds>

### New Features

- Feature 1
- Feature 2

### Bug Fixes

- Fix 1
- Fix 2

### Testing

- X tests passing
- CI status

### Documentation

- Updated docs

---

**Full Changelog**: https://github.com/<owner>/<repo>/compare/vPREVIOUS...vX.Y.Z
EOF
)"
```

**CRITICAL**: Never pass a local file path to `gh release create`. Never run `make dist` as part of the release process. CI owns binary production.

### 9. Verify Release and Wait for CI

Confirm the release was created, then let CI do its work:

```bash
gh release view vX.Y.Z --json tagName,targetCommitish,url
```

Verify:
- Tag is `vX.Y.Z`
- Target is `main` branch
- URL is accessible

Then watch for the CI release workflow to complete:

```bash
gh run list --workflow=release.yml --limit=3
```

Wait until the run for `vX.Y.Z` shows `completed / success`. This workflow:
1. Builds the tarball with `make dist` on a clean CI runner
2. Uploads it to the GitHub release
3. Dispatches a `formula-update` event to the homebrew-tap repo

Once CI completes, confirm the Homebrew formula was updated:

```bash
cd <path-to-homebrew-tap> && git fetch origin && git log --oneline origin/main -5
```

Look for a commit like `Update <formula> to vX.Y.Z`. **Never manually edit the Homebrew formula** — if the CI dispatch didn't trigger it, investigate the `formula-update` workflow in homebrew-tap instead of patching by hand.

### 10. Summary Report

Provide final summary:

```
Release vX.Y.Z Complete

- Dependencies audited and updated to latest published versions ✅
  - No local path references in Package.swift
  - All dependencies pinned with .upToNextMajor()
- Version bumped to X.Y.Z on release/vX.Y.Z branch ✅
- Swift source formatted with make lint ✅
- Documentation organized with /organize-agent-docs ✅
  - AGENTS.md: Universal project documentation
  - CLAUDE.md: Claude-specific instructions only
  - GEMINI.md: Gemini-specific instructions only
- README.md updated (user-facing documentation) ✅
- CI checks passed on PR ✅
- Pull Request #<NUMBER> squash-merged to main; release branch deleted ✅
- Tag vX.Y.Z created on main ✅
- GitHub release published (metadata only — no manual tarball) ✅
- CI release workflow triggered (builds tarball + updates Homebrew) ✅
- Homebrew formula updated by CI at homebrew-tap ✅

Release URL: https://github.com/<owner>/<repo>/releases/tag/vX.Y.Z

The library is now ready for use via Swift Package Manager and Homebrew.
```

## Critical Rules (NEVER VIOLATE)

1. **Derive version from git tags, not source code** - Always run `git tag --sort=-v:refname` to find the last released version. The `version` string in source is informational and may be stale. If source version ≠ latest tag, flag it before proceeding.
2. **Bump version on a release branch BEFORE merging** - Cut `release/vX.Y.Z` from main, do all version/dep/doc work there, ship via PR. Never push the version bump directly to main.
3. **Audit and update ALL dependencies BEFORE version bump** - No library can ship with local file path references (`.path()`) in Package.swift. All dependencies MUST reference published GitHub releases and be pinned using `.upToNextMajor(from: "X.Y.Z")` to allow patch updates within the same major version. Check for local references first: `grep -n '\.path(' Package.swift` — if any exist, replace with GitHub URLs before proceeding.
4. **Run `make lint` before committing** - Format all Swift source files with swift format
5. **Organize docs with /organize-agent-docs** - Ensure proper separation of universal vs agent-specific documentation
6. **Wait for CI on the PR** - Don't merge until the PR's CI run passes
7. **Use --squash --delete-branch** - One squash commit per release on main; release branch is deleted on merge
8. **Tag on main after merge** - The tag goes on the squash merge commit
9. **NEVER manually build or upload release tarballs** - The `release.yml` CI workflow owns binary production. Never run `make dist` as part of releasing, never pass local file paths to `gh release create`.
10. **NEVER manually edit the Homebrew formula** - CI dispatches a `formula-update` event to homebrew-tap after uploading the tarball. The tap updates itself. If it doesn't, investigate the CI workflow — do not patch the formula by hand.

## Correct Flow

```
main:               [stable] -----------------------------------------------------------> [squash commit] -> [tag vX.Y.Z] -> [release (metadata only)]
release/vX.Y.Z:        └─ [version bump + deps + lint + docs] -> (CI passes on PR) -> PR merged -> branch deleted
CI:                                                                                         ^-- [build tarball] -> [upload to release] -> [dispatch formula-update to homebrew-tap]
homebrew-tap:                                                                                                                          ^-- (auto-updated by formula-update event)
```

## Error Handling

If any step fails:
1. Stop immediately
2. Explain what failed and why
3. Provide fix guidance
4. Do not proceed

## Notes

- Requires GitHub CLI (`gh`) authenticated
- Requires git configured with merge permissions
- All commits include Claude Code attribution
- The release branch is short-lived: it exists only between step 2 (creation) and step 5 (delete on merge)
