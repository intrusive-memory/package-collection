---
name: ship-swift-library
description: Ship and release Swift library versions by bumping the version on development, merging the PR once CI passes, then tagging and creating a GitHub release from main
allowed-tools: Bash, Read, Grep, Glob, Edit, Skill
dependencies:
  - organize-agent-docs
---

# Ship Swift Library Skill

This skill handles the complete release process for Swift libraries.

**CRITICAL RULE**: Bump the version on `development` BEFORE merging the PR. The version bump ships as part of the PR merge to `main`. NEVER merge development directly to main when a PR exists.

## Applicability & Naming Convention

This skill applies to Swift libraries in the `intrusive-memory` GitHub organization that follow the standard `development → PR → main → tag` release flow. The repository name is your first signal of what kind of project you're looking at.

### `Swift<PascalCaseWord>` — in-house Swift library (skill applies)

The suffix is typically a Spanish noun or verb that hints at the library's purpose. These are native in-house libraries and always use this skill's flow.

| Repo | Word origin | Purpose |
|---|---|---|
| SwiftAcervo | Spanish: collection/archive | Shared model registry for HuggingFace models |
| SwiftBruja | Spanish: witch | On-device LLM inference via MLX |
| SwiftCompartido | Spanish: shared | Screenplay parsing & SwiftData models |
| SwiftEchada | Spanish: cast/thrown | Utilities & extensions for the ecosystem |
| SwiftFijos | Spanish: fixed (plural) | Test fixture discovery |
| SwiftHablare | Spanish: will speak | TTS voice generation |
| SwiftOnce | Spanish: eleven | ElevenLabs TTS REST API wrapper |
| SwiftProyecto | Spanish: project | Project metadata & PROJECT.md parsing |
| SwiftSecuencia | Spanish: sequence | FCPXML timeline generation |
| SwiftTuberia | Spanish: piping | Componentized MLX generation pipelines |
| SwiftVoxAlta | Latin/Spanish: high voice | Qwen3-TTS voice cloning |

**Exceptions to the Spanish-word pattern:** the suffix may be an English/tech name when wrapping a known upstream tech (e.g. `SwiftFFMpeg` for the FFmpeg wrapper).

### `<kebab-case>-swift` — Swift port or independent fork (skill applies)

Swift libraries that started as ports or independent forks of upstream projects. Naming follows upstream rather than the Spanish-noun convention, but releases belong to us and the flow is identical to in-house libraries.

| Repo | Notes |
|---|---|
| mlx-audio-swift | Independent fork of `Blaizzy/mlx-audio-swift`; our own release train |

### `<domain>-format` — file format library (skill applies)

Libraries that define and implement a file format, typically shipping a Swift reader/writer plus a CLI. These are ancillary in scope but are still releasable Swift libraries with their own tags, Homebrew formulae (where applicable), and dependency graphs.

| Repo | Format |
|---|---|
| vox-format | VOX open voice identity file format |

### `<kebab-case>` data/source-of-truth repo (skill does NOT apply)

Single-file or data-driven repos where the "release" is the file itself, not a tagged library version.

| Repo | What it is | Release flow |
|---|---|---|
| package-collection | Swift Package Collection JSON | **main-only, no development branch** |

### Collaboration fork — local copy for upstreaming (skill does NOT apply)

A repo we maintain as a fork solely to offer pull requests back to an external primary maintainer. We do not cut our own releases — the upstream does. Never run this skill against one of these.

| Repo | Upstream / collaborator |
|---|---|
| pipeline-neo | Maintained to send PRs to the primary maintainer |

### `<PascalCaseWord>` with no `Swift` prefix — CLI tool or app (skill does NOT apply)

Standalone CLI tools or apps. These may have their own `ship-*` skill (e.g. `ship-ios-app`) or a custom release flow.

| Repo | Kind |
|---|---|
| Produciesta | Podcast audio CLI (SwiftSecuencia-based) |

### Before invoking this skill, verify

```bash
# Must have a Package.swift at the root (it's a Swift package)
test -f Package.swift || { echo "NOT a Swift package — abort"; exit 1; }

# Must have a long-lived development branch
git ls-remote --heads origin development | grep -q development \
  || { echo "No development branch — this may be a main-only repo"; exit 1; }
```

If either check fails, stop and ask the user rather than improvising. A missing `development` branch usually means the repo is main-only (like `package-collection`) and a different release flow applies.

## Process Overview

You will perform the following 12 steps in order:

### 1. Check for Open Pull Request

Check if there's an open PR from `development` to `main`:

```bash
gh pr list --base main --head development
```

**If PR exists**: Proceed to step 2
**If no PR**: Ask user if they want to create one

### 2. Determine Version Number

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

### 3. Bump Version, Update Dependencies, and Audit Documentation

Make sure you're on the `development` branch, then update the version:

```bash
git checkout development
git pull origin development
```

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
git push origin development
```

**Important**: The version bump, dependency updates, and doc changes are now part of the PR diff and will be included when the PR is merged.

### 4. Verify CI Checks Pass

Wait for CI to run on the updated PR (the version bump push triggers a new CI run):

```bash
gh pr checks <PR_NUMBER>
```

If any checks fail, inform the user and do not proceed. If checks are pending, poll until they complete:

```bash
gh pr checks <PR_NUMBER> --watch
```

### 5. Merge Pull Request

**CRITICAL**: Squash merge the PR to keep main branch history clean:

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch=false
```

**Important**:
- Use `--squash` (clean single commit on main)
- Do NOT delete development branch (it's long-lived)
- The squash commit on main now contains the version bump

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

### 10. Rebase Development onto Main

After a squash merge, development's original commits are not ancestors of the squash commit on main. A `git merge main` would make the code identical but leave those old commits visible in the next PR (tons of commits, zero diff).

**Why not just `git rebase main`?** The `development` branch is protected with `allow_force_pushes: false`. A normal rebase requires force-push, which gets rejected. Additionally, the phantom commits conflict with the squash commit during rebase, causing conflicts even though there is no real diff. The solution is to temporarily unlock force-push, identify genuinely new commits using `git cherry`, reset development to main's tip, cherry-pick only the new commits, force-push, then restore the protection.

```bash
# Step 1: Update local main
git checkout main && git pull origin main
git checkout development && git pull origin development

# Step 2: Find genuinely new commits on development using git cherry.
# git cherry marks commits '+' if they are NOT already in upstream (genuinely new),
# and '-' if their diff is already present in main (phantom/squashed). We keep only '+'.
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
NEW_COMMITS=$(git cherry origin/main | grep '^+ ' | awk '{print $2}')
echo "Commits to preserve: ${NEW_COMMITS:-none}"

# Step 3: Temporarily enable force-push on the protected branch
gh api --method PUT "repos/${REPO}/branches/development/protection" \
  --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["Test on macOS", "Test on iOS Simulator"]},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": true
}
JSON

# Step 4: Reset development to main's tip, then cherry-pick any new commits
git reset --hard origin/main
if [ -n "$NEW_COMMITS" ]; then
  git cherry-pick $NEW_COMMITS
fi

# Step 5: Force-push the clean development branch
git push origin development --force-with-lease

# Step 6: Restore branch protection (disable force-push)
gh api --method PUT "repos/${REPO}/branches/development/protection" \
  --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["Test on macOS", "Test on iOS Simulator"]},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false
}
JSON

echo "Development rebased onto main. Force-push protection restored."
```

**Verify the result**: `git log --oneline -3` on development should show main's squash commit as the base, with only genuinely new commits on top (zero new commits is normal right after a release).

**If the CI status check names differ** from `"Test on macOS"` and `"Test on iOS Simulator"`, look them up first:
```bash
gh api "repos/${REPO}/branches/development/protection" --jq '.required_status_checks.checks[].context'
```
Use those exact strings in the protection API calls above.

### 11. Create Next Development Cycle PR

Create a new (empty) pull request from `development` to `main`. This signals that the development branch is open for new work and provides a landing target for future feature PRs:

```bash
gh pr create \
  --base main \
  --head development \
  --title "Development → Main" \
  --body "$(cat <<'EOF'
## Next Development Cycle

Development branch is synced with main after vX.Y.Z release and ready for new work.

This PR will collect changes for the next release.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Confirm the PR was created:

```bash
gh pr list --base main --head development
```

### 12. Summary Report

Provide final summary:

```
Release vX.Y.Z Complete

- Dependencies audited and updated to latest published versions ✅
  - No local path references in Package.swift
  - All dependencies pinned with .upToNextMajor()
- Version bumped to X.Y.Z on development ✅
- Swift source formatted with make lint ✅
- Documentation organized with /organize-agent-docs ✅
  - AGENTS.md: Universal project documentation
  - CLAUDE.md: Claude-specific instructions only
  - GEMINI.md: Gemini-specific instructions only
- README.md updated (user-facing documentation) ✅
- CI checks passed ✅
- Pull Request #<NUMBER> merged to main (includes version bump + dependency updates + docs) ✅
- Tag vX.Y.Z created on main ✅
- GitHub release published (metadata only — no manual tarball) ✅
- CI release workflow triggered (builds tarball + updates Homebrew) ✅
- Homebrew formula updated by CI at homebrew-tap ✅
- Local branches updated (main and development) ✅
- Development synced with main ✅
- New development cycle PR #<NEW_NUMBER> created ✅

Release URL: https://github.com/<owner>/<repo>/releases/tag/vX.Y.Z
Next cycle PR: https://github.com/<owner>/<repo>/pull/<NEW_NUMBER>

The library is now ready for use via Swift Package Manager and Homebrew.
```

## Critical Rules (NEVER VIOLATE)

1. **Derive version from git tags, not source code** - Always run `git tag --sort=-v:refname` to find the last released version. The `version` string in source is informational and may be stale. If source version ≠ latest tag, flag it before proceeding.
2. **Bump version BEFORE merging** - The version bump must be part of the PR
3. **Audit and update ALL dependencies BEFORE version bump** - No library can ship with local file path references (`.path()`) in Package.swift. All dependencies MUST reference published GitHub releases and be pinned using `.upToNextMajor(from: "X.Y.Z")` to allow patch updates within the same major version. Check for local references first: `grep -n '\.path(' Package.swift` — if any exist, replace with GitHub URLs before proceeding.
4. **Run `make lint` before committing** - Format all Swift source files with swift format
5. **Organize docs with /organize-agent-docs** - Ensure proper separation of universal vs agent-specific documentation
6. **Wait for CI after version bump** - Don't merge until the new CI run passes
7. **Use --squash** - Keep main branch history clean with single commits per PR
8. **Don't delete development** - It's a long-lived branch
9. **Tag on main after merge** - The tag goes on the squash merge commit
10. **Rebase development after release** - Use the protected-branch rebase procedure (Step 10): temporarily enable force-push via `gh api`, identify new commits with `git cherry`, reset to main, cherry-pick new commits, force-push, restore protection. Never use `git merge main` — it leaves phantom commits in the next PR.
11. **Create next cycle PR** - Always open a new development→main PR after release so the branch is ready for new work
12. **NEVER manually build or upload release tarballs** - The `release.yml` CI workflow owns binary production. Never run `make dist` as part of releasing, never pass local file paths to `gh release create`.
13. **NEVER manually edit the Homebrew formula** - CI dispatches a `formula-update` event to homebrew-tap after uploading the tarball. The tap updates itself. If it doesn't, investigate the CI workflow — do not patch the formula by hand.

## Correct Flow

```
development: [features] -> [version bump] -> [make lint] -> [/organize-agent-docs] -> (CI passes) -> PR merged
main:        -----------------------------------------------------------------> [squash commit] -> [tag vX.Y.Z] -> [release (metadata only)]
CI:          -------------------------------------------------------------------------^-- [build tarball] -> [upload to release] -> [dispatch formula-update to homebrew-tap]
homebrew-tap:--------------------------------------------------------------------^-- (auto-updated by formula-update event)
development: [rebase onto main] -> [force-push] -> [new empty PR to main]
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
