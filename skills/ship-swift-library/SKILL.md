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

### 3. Bump Version and Audit Documentation

Make sure you're on the `development` branch, then update the version:

```bash
git checkout development
git pull origin development
```

Edit the version file (e.g. `Sources/<LibraryName>/<LibraryName>.swift`).

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

Commit everything together — version bump + lint fixes + doc updates — in a single commit:

```bash
git add Sources/<LibraryName>/<LibraryName>.swift README.md AGENTS.md CLAUDE.md GEMINI.md
git commit -m "Bump version to X.Y.Z and update documentation

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push origin development
```

**Important**: The version bump and doc updates are now part of the PR diff and will be included when the PR is merged.

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

After a squash merge, development's original commits are not ancestors of the squash commit on main. A `git merge main` would make the code identical but leave those old commits visible in the next PR (tons of commits, zero diff). Rebase eliminates them by replaying any new work on top of main's squash commit.

```bash
# Update local main with the merge commit and tag
git checkout main
git pull origin main

# Rebase development onto main (fast-forwards when no new commits exist)
git checkout development
git pull origin development
git rebase main
git push origin development --force-with-lease
```

**Why rebase instead of merge?** Squash merge creates a new commit on main that has no ancestry relationship with development's commits. `git merge main` brings the content in but leaves the old commits dangling — the next PR shows them all with 0 diff. Rebase moves development's base to main's tip, so only truly new commits appear in the next PR.

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

- Version bumped to X.Y.Z on development ✅
- Swift source formatted with make lint ✅
- Documentation organized with /organize-agent-docs ✅
  - AGENTS.md: Universal project documentation
  - CLAUDE.md: Claude-specific instructions only
  - GEMINI.md: Gemini-specific instructions only
- README.md updated (user-facing documentation) ✅
- CI checks passed ✅
- Pull Request #<NUMBER> merged to main (includes version bump + docs) ✅
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
2. **Run `make lint` before committing** - Format all Swift source files with swift format
3. **Organize docs with /organize-agent-docs** - Ensure proper separation of universal vs agent-specific documentation
4. **Wait for CI after version bump** - Don't merge until the new CI run passes
5. **Use --squash** - Keep main branch history clean with single commits per PR
6. **Don't delete development** - It's a long-lived branch
7. **Tag on main after merge** - The tag goes on the squash merge commit
8. **Rebase development after release** - Rebase onto main (not merge) to avoid phantom commits in the next PR
9. **Create next cycle PR** - Always open a new development→main PR after release so the branch is ready for new work
10. **NEVER manually build or upload release tarballs** - The `release.yml` CI workflow owns binary production. Never run `make dist` as part of releasing, never pass local file paths to `gh release create`.
11. **NEVER manually edit the Homebrew formula** - CI dispatches a `formula-update` event to homebrew-tap after uploading the tarball. The tap updates itself. If it doesn't, investigate the CI workflow — do not patch the formula by hand.

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
