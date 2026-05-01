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

## Applicability Gate

Before doing anything else, verify this skill applies to the current repo:

```bash
# Must have a Package.swift at the root (it's a Swift package)
test -f Package.swift || { echo "NOT a Swift package — abort"; exit 1; }

# Must have a long-lived development branch
git ls-remote --heads origin development | grep -q development \
  || { echo "No development branch — this may be a main-only repo"; exit 1; }
```

If either check fails, stop and ask the user. A missing `development` branch usually means a main-only repo (like `package-collection`) and a different release flow applies.

For the full repo naming-convention table — which repos this skill applies to (`Swift<Word>`, `<kebab>-swift`, `<domain>-format`) and which it does NOT (`package-collection`, collaboration forks, CLI tools/apps) — see `references/applicability.md`.

## Process Overview

13 steps in order. Steps marked **[ref]** load a reference file before executing.

### 1. Check for Open Pull Request

```bash
gh pr list --base main --head development
```

If a PR exists, proceed. If not, ask the user whether to create one.

### 2. Determine Version Number

**The version in source code is NOT authoritative.** Derive the current version from git tags:

```bash
git fetch --tags
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -5
```

The first result is the last released version. If no tags exist, treat as `v0.0.0`.

Source files between releases carry an `X.Y.Z-dev` marker (set by step 11 of the previous cycle). Strip the `-dev` suffix before comparing:
- Source `1.4.2-dev` + tag `v1.4.2` → equivalent, in post-1.4.2 dev cycle.
- Source `1.4.2-dev` + tag `v1.4.1` → discrepancy, investigate.
- Source has no `-dev` suffix → flag it.

Ask the user for the new version, presenting the last tagged version as baseline:
- **Patch** (x.y.Z): Bug fixes, small improvements
- **Minor** (x.Y.0): New features, non-breaking changes
- **Major** (X.0.0): Breaking changes

**The new version MUST NOT contain `-dev`.** Tag and release are always clean semver.

### 3. Bump Version, Update Dependencies, Audit Documentation, and Audit CI Workflows **[ref]**

This is the heaviest step — four coupled sub-tasks that all land in a **single commit on `development`**:

1. Run `/spm-package-audit` to fix Package.resolved tracking and update intrusive-memory/* deps.
2. Edit version files, **stripping any `-dev` suffix**. The new version is clean semver.
3. Run `make lint` to format Swift sources.
4. Run `/organize-agent-docs` and update README.md.
5. Audit `.github/workflows/` and bump every action `uses:` reference to its latest major.
6. Commit everything together and push to `development`.

**Read `references/version-bump.md` for the full procedure** — including the `-dev` strip recipe, dependency verification, the dynamic CI-action audit table, and the canonical commit message.

### 4. Verify CI Checks Pass

The version-bump push triggers a new CI run. Wait for it:

```bash
gh pr checks <PR_NUMBER> --watch
```

If checks fail, stop and surface the failure.

### 5. Merge Pull Request

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch=false
```

Use `--squash` (clean single commit on main). Do NOT delete the `development` branch (it's long-lived).

### 6. Pull Merge Commit to Local Main

```bash
git checkout main
git pull origin main
git log --oneline -1   # Verify you're on the squash merge commit
```

### 7. Create Annotated Tag on Main

**Hard guard — refuse to tag a `-dev` version.** A `-dev` suffix means "developmental build, not a release." Run before tagging:

```bash
VERSION="X.Y.Z"   # the version you're about to tag
case "$VERSION" in
  *-dev*) echo "ABORT: '-dev' versions are developmental builds and MUST NOT be tagged. Strip the suffix first."; exit 1 ;;
esac
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "ABORT: '$VERSION' is not a clean semver string."; exit 1 ;;
esac
grep -RlE -- '-dev' Sources/ README.md AGENTS.md CLAUDE.md GEMINI.md 2>/dev/null \
  && { echo "ABORT: '-dev' marker still present. Re-run step 3."; exit 1; } \
  || echo "No -dev markers. Safe to tag."
```

Then tag:

```bash
git tag -a "v${VERSION}" -m "Release v${VERSION}: <Short description>

<Detailed release notes>"

git push origin "v${VERSION}"
```

### 8. Create GitHub Release (metadata only — NO tarball upload)

The `release.yml` CI workflow fires on `release: published` and builds + uploads the canonical tarball, then dispatches the Homebrew formula update. **Do NOT upload any tarball or binary assets** and **never run `make dist`** as part of releasing.

Re-check the `-dev` guard:

```bash
case "$VERSION" in
  *-dev*) echo "ABORT: '-dev' versions are developmental builds and MUST NOT be released."; exit 1 ;;
esac
```

```bash
gh release create vX.Y.Z \
  --title "vX.Y.Z: <Title>" \
  --notes "$(cat <<'EOF'
# <Library Name> vX.Y.Z

## <Emoji> <Feature Category>

<Description of what this release adds>

### New Features
- Feature 1

### Bug Fixes
- Fix 1

### Testing
- X tests passing

### Documentation
- Updated docs

---

**Full Changelog**: https://github.com/<owner>/<repo>/compare/vPREVIOUS...vX.Y.Z
EOF
)"
```

**CRITICAL**: Never pass a local file path to `gh release create`. Never run `make dist` as part of the release process. CI owns binary production.

### 9. Verify Release and Wait for CI

```bash
gh release view vX.Y.Z --json tagName,targetCommitish,url
gh run list --workflow=release.yml --limit=3
```

Wait for the `vX.Y.Z` run to show `completed / success`. The workflow:
1. Builds the tarball with `make dist` on a clean CI runner
2. Uploads it to the GitHub release
3. Dispatches a `formula-update` event to the homebrew-tap repo

Confirm Homebrew updated:

```bash
cd <path-to-homebrew-tap> && git fetch origin && git log --oneline origin/main -5
```

Look for `Update <formula> to vX.Y.Z`. **Never manually edit the formula** — if CI didn't dispatch, investigate the workflow.

### 10. Rebase Development onto Main **[ref]**

After a squash merge, development carries phantom commits whose patch-ids no longer match the squash on main. A naive `git merge main` leaves those phantoms visible in the next PR (huge commit list, zero diff).

The fix: temporarily unlock force-push, reset development to main's tip, cherry-pick only *genuinely new* commits (those added after the PR was created), force-push, then restore protection.

**Read `references/rebase-development.md` for the full procedure** — including the protection toggle, why `git cherry` fails on squash merges, and the verification step.

### 11. Mark Development Branch with `-dev` Version **[ref]**

After the rebase, development is bit-identical to main. Stamp it with `X.Y.Z-dev` (where `X.Y.Z` is what you just released) so:
1. `gh pr create` for the next-cycle PR has a non-empty diff and works reliably.
2. "Release vs. dev snapshot?" is answerable from source.

**Read `references/dev-marker.md` for the full procedure** — including which files to touch and which NOT to touch.

### 12. Create Next Development Cycle PR (Draft)

The `-dev` bump in step 11 guarantees a non-empty diff, so PR creation will succeed reliably. Draft mode signals the PR is a landing target for future work, not ready for review or merge:

```bash
gh pr create \
  --draft \
  --base main \
  --head development \
  --title "Development → Main" \
  --body "$(cat <<'EOF'
## Next Development Cycle

Development branch is synced with main after vX.Y.Z release and marked as `X.Y.Z-dev`.

This PR is in draft mode and will collect changes for the next release. The `-dev` suffix will be stripped when the next version is bumped.
EOF
)"
```

Confirm it's draft:

```bash
gh pr list --base main --head development --json number,isDraft,title
```

### 13. Summary Report

Provide a final summary covering: SPM audit applied, version bumped, lint, docs organized, README updated, CI workflows audited, CI passed, PR merged, tag created, GitHub release published, CI release workflow triggered, Homebrew formula updated, local branches updated, development synced and stamped `-dev`, draft next-cycle PR opened.

Include the release URL and the next-cycle PR URL.

## Critical Rules (NEVER VIOLATE)

1. **Derive version from git tags, not source code** — Run `git tag --sort=-v:refname` to find the last released version. The `version` string in source is informational and may be stale.
2. **Bump version BEFORE merging** — The version bump must be part of the PR.
3. **Run /spm-package-audit BEFORE version bump** — Auto-fixes Package.resolved tracking, sibling-dep pattern for intrusive-memory/*, and updates versions to latest. Verify no local `.path()` references remain.
4. **Run `make lint` before committing** — Format Swift sources with swift format.
5. **Organize docs with /organize-agent-docs** — Separate universal vs agent-specific documentation.
6. **Audit CI workflows for stale GitHub Actions** — Every `uses:` in `.github/workflows/` must be on the latest major. Older majors run on Node 16 (deprecated) and trigger warnings; some are decommissioned (e.g. `actions/upload-artifact@v3`).
7. **Wait for CI after version bump** — Don't merge until the new CI run passes.
8. **Use --squash** — Single commit per PR on main.
9. **Don't delete development** — It's a long-lived branch.
10. **Tag on main after merge** — Tag goes on the squash merge commit.
11. **Rebase development after release using the protected-branch procedure** — See `references/rebase-development.md`. Never `git merge main` (leaves phantom commits).
12. **Mark development as `-dev` after release** — See `references/dev-marker.md`. Never leave development bit-identical to main.
13. **NEVER tag, release, or publish a `-dev` version** — Steps 7 and 8 carry hard `case` guards. Do not bypass them.
14. **Create next cycle PR in DRAFT mode** — `gh pr create --draft`.
15. **NEVER manually build or upload release tarballs** — `release.yml` owns binary production. Never run `make dist`, never pass local file paths to `gh release create`.
16. **NEVER manually edit the Homebrew formula** — CI dispatches `formula-update` to homebrew-tap. If it doesn't, investigate the workflow.

## Correct Flow

```
development: [features on X.Y.Z-dev] -> [strip -dev, bump to A.B.C] -> [make lint] -> [/organize-agent-docs] -> [audit CI workflows] -> (CI passes) -> PR merged
main:        -----------------------------------------------------------------------------> [squash commit] -> [tag vA.B.C] -> [release (metadata only)]
CI:          -------------------------------------------------------------------------------------^-- [build tarball] -> [upload to release] -> [dispatch formula-update to homebrew-tap]
homebrew-tap:--------------------------------------------------------------------------------^-- (auto-updated by formula-update event)
development: [rebase onto main] -> [force-push] -> [stamp A.B.C-dev, commit, push] -> [draft PR to main]
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
