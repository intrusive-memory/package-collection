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

Find the current version (usually `Sources/<LibraryName>/<LibraryName>.swift`):

```swift
public static let version = "X.Y.Z"
```

Ask the user what version this release should be. Version increment rules:
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

### 8. Create GitHub Release

Create a GitHub release from the tag:

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

### 9. Verify Release

Confirm the release was created successfully:

```bash
gh release view vX.Y.Z --json tagName,targetCommitish,url
```

Verify:
- Tag is `vX.Y.Z`
- Target is `main` branch
- URL is accessible

### 10. Sync Local Branches and Development

Update both local branches to match remote state after the release:

```bash
# Update local main with the merge commit and tag
git checkout main
git pull origin main

# Switch to development and merge main back (avoids future merge conflicts)
git checkout development
git pull origin development
git merge origin/main
git push origin development
```

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
- GitHub release published ✅
- Local branches updated (main and development) ✅
- Development synced with main ✅
- New development cycle PR #<NEW_NUMBER> created ✅

Release URL: https://github.com/<owner>/<repo>/releases/tag/vX.Y.Z
Next cycle PR: https://github.com/<owner>/<repo>/pull/<NEW_NUMBER>

The library is now ready for use via Swift Package Manager.
```

## Critical Rules (NEVER VIOLATE)

1. **Bump version BEFORE merging** - The version bump must be part of the PR
2. **Run `make lint` before committing** - Format all Swift source files with swift format
3. **Organize docs with /organize-agent-docs** - Ensure proper separation of universal vs agent-specific documentation
4. **Wait for CI after version bump** - Don't merge until the new CI run passes
5. **Use --squash** - Keep main branch history clean with single commits per PR
6. **Don't delete development** - It's a long-lived branch
7. **Tag on main after merge** - The tag goes on the squash merge commit
8. **Sync development after release** - Merge main back to avoid future conflicts
9. **Create next cycle PR** - Always open a new development→main PR after release so the branch is ready for new work

## Correct Flow

```
development: [features] -> [version bump] -> [make lint] -> [/organize-agent-docs] -> (CI passes) -> PR merged
main:        -----------------------------------------------------------------> [squash commit] -> [tag vX.Y.Z] -> [release]
development: [sync local branches] -> [merge main back] -> [push] -> [new empty PR to main]
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
