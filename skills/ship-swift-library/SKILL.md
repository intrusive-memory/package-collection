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

Standalone CLI tools or apps. Apps have their own per-app `ship-<app-name>` skill that embeds the App Store Connect references for that specific app — there is no generalized app-shipping skill.

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

### 3. Bump Version, Update Dependencies, Audit Documentation, and Audit CI Workflows

Make sure you're on the `development` branch, then update the version:

```bash
git checkout development
git pull origin development
```

**CRITICAL: Run SPM Package Audit First**

Before any manual changes, run the spm-package-audit skill to automatically fix common package hygiene issues:

```
/spm-package-audit
```

This will:
- Remove Package.resolved from git tracking (libraries should not check this in)
- Add/update the sibling dependency pattern for intrusive-memory/* dependencies
- Update intrusive-memory/* dependency versions to latest GitHub releases
- Validate the sibling helper function is correct

**Then edit the version file** (e.g. `Sources/<LibraryName>/<LibraryName>.swift`).

**Verify All Dependencies in Package.swift**

After running spm-package-audit, verify no issues remain:

1. **Verify no local file path references remain** — spm-package-audit should have caught these, but double-check:
   ```bash
   grep -n '\.path(' Package.swift
   ```
   If any `.path()` references exist for non-intrusive-memory dependencies, replace with GitHub URLs.

2. **For non-intrusive-memory dependencies**, verify they use `.upToNextMajor()`:
   ```bash
   grep -A2 'package(url:' Package.swift | grep -v intrusive-memory
   ```
   Update any that use exact versions to `.upToNextMajor(from: "X.Y.Z")`.

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

**Then audit CI workflows for outdated GitHub Actions.**

Older action versions still pinned to Node 16 emit `Node.js 16 actions are deprecated` warnings on every CI run, and Node 16 runners have been removed entirely from some GitHub-hosted images. Audit every workflow file in `.github/workflows/` and bump each `uses:` reference to the latest published major version.

1. **List every action reference across all workflows** (covers `.yml` and `.yaml`, ignores commented-out lines):
   ```bash
   grep -hE '^[[:space:]]*uses:[[:space:]]*[^#]' .github/workflows/*.y*ml 2>/dev/null \
     | sed -E 's/^[[:space:]]*uses:[[:space:]]*//' \
     | sort -u
   ```

2. **Build the floor-version table dynamically — do NOT hard-code versions.**

   Hard-coded floor versions go stale the moment GitHub publishes a new major. Instead, build a per-release audit table by querying `releases/latest` for every action this repo actually uses. The output of step 1 is the input here.

   **Output target (illustrative shape only — values must come from live API calls):**

   | Action | Currently pinned | Latest major | Latest tag | Action required |
   |---|---|---|---|---|
   | `<owner>/<repo>` | `<extracted from workflow>` | `<derived from gh api>` | `<derived from gh api>` | bump / OK |

   **How to populate it**, one row per unique `<owner>/<repo>` discovered in step 1:

   ```bash
   # Extract just the owner/repo (strip @ref) and dedupe
   ACTIONS=$(grep -hE '^[[:space:]]*uses:[[:space:]]*[^#]' .github/workflows/*.y*ml 2>/dev/null \
     | sed -E 's/^[[:space:]]*uses:[[:space:]]*//; s/@.*$//' \
     | grep -v '^\./' \
     | sort -u)

   # For each, fetch the latest release tag and derive the major
   for action in $ACTIONS; do
     latest_tag=$(gh api "repos/${action}/releases/latest" --jq '.tag_name' 2>/dev/null)
     if [ -z "$latest_tag" ]; then
       # Fallback: some actions only publish tags (e.g. `v3`), no GitHub Releases.
       latest_tag=$(gh api "repos/${action}/tags" --jq '[.[].name | select(test("^v[0-9]+(\\.[0-9]+){0,2}$"))][0]' 2>/dev/null)
     fi
     latest_major=$(printf '%s\n' "$latest_tag" | sed -E 's/^(v?[0-9]+).*/\1/')
     printf '%-40s  latest_major=%s  latest_tag=%s\n' "$action" "$latest_major" "$latest_tag"
   done
   ```

   **Reading the result:**
   - `latest_major` is the value to pin to (e.g. `v4`, `v5`). Float on the major rather than the exact tag — actions follow GitHub's "v-major points at the latest patch within that major" convention, which mirrors how the user has the rest of this repo's deps pinned (`.upToNextMajor`).
   - If the workflow is already on the latest major, mark **OK** and move on.
   - If the workflow is on an older major, mark **bump** and proceed to step 3.
   - If `releases/latest` returned empty AND no semver tags exist (rare — usually a custom internal action), flag it for manual review rather than guessing.

   **Sanity check on the way out:** any row where `latest_major` does not match the pinned major is a mandatory bump. There are no exceptions for "stable enough" — the deprecation warnings only quiet down once every action is on its latest major.

   Capture this table in your working scratch (or paste it into the PR description) so the reviewer can see, per release, which actions you bumped and to what.

3. **Update each workflow file** and reconcile inputs/env vars for the new major.

   Whenever an action crosses a major boundary, GitHub Actions treats it as a contract change — inputs may rename, become required, or stop being inferred. **Always read the action's release notes for the major you are jumping to** before pushing the bump. Pull them on demand:

   ```bash
   # Release notes for the latest major of <owner>/<repo>
   gh release view --repo <owner>/<repo> "$latest_tag" --json body --jq '.body'

   # Or the full changelog between the currently pinned tag and latest
   gh api "repos/<owner>/<repo>/compare/<old_tag>...<latest_tag>" --jq '.commits[].commit.message'
   ```

   Categories of breaking change to look for in those notes (verify each against the action's actual release notes — do not assume):
   - **Required vs. inferred inputs**: did an input that used to be optional become mandatory? Common offenders are auth tokens (`token:` / `GITHUB_TOKEN` env), cache keys, and artifact names.
   - **Renamed or removed inputs**: `with:` blocks that compiled fine on the old major may now reference dead inputs.
   - **Uniqueness / scoping rules**: artifact actions in particular have tightened uniqueness rules across majors (per-job, per-run, per-matrix). If the workflow has matrix jobs sharing a name, that's the place to look.
   - **Default behaviour changes**: cross-run artifact downloads, cache key fallbacks, and shallow-clone defaults have all flipped at major boundaries.
   - **Runtime / Node version**: the whole reason for this audit. The release notes will say which Node runtime the action now requires.

   For each `with:` and `env:` block in your workflow, cross-check it against the new major's documented inputs. If you cannot find a definitive answer in the release notes, link the workflow line in the PR description and ask the reviewer to sanity-check rather than guessing.

4. **Verify the workflows still parse** before committing:
   ```bash
   # Preferred — actionlint catches version-specific input errors
   command -v actionlint >/dev/null && actionlint .github/workflows/*.y*ml \
     || echo "actionlint not installed — skipping (install: brew install actionlint)"
   ```
   Also run a YAML sanity check:
   ```bash
   for f in .github/workflows/*.y*ml; do
     python3 -c "import yaml,sys; yaml.safe_load(open('$f'))" || echo "FAIL: $f"
   done
   ```

5. **Re-confirm the `release.yml` workflow** specifically — it owns tarball production and the Homebrew dispatch (Step 8). If its actions were stale, the next release will fire on the updated workflow, so make sure it still uploads to the correct release and dispatches `formula-update` to homebrew-tap.

Commit everything together — version bump + SPM audit fixes + lint fixes + doc updates + workflow updates — in a single commit:

```bash
git add Package.swift .gitignore Sources/<LibraryName>/<LibraryName>.swift README.md AGENTS.md CLAUDE.md GEMINI.md .github/workflows/
git commit -m "Bump version to X.Y.Z, update dependencies, docs, and CI actions

SPM package audit applied:
- Package.resolved removed from git tracking (if present)
- Sibling dependency pattern added/updated for intrusive-memory/* deps
- All dependencies updated to latest published versions
- Dependencies pinned to next major version boundary

CI workflows updated:
- All GitHub Actions bumped to latest major (eliminates Node 16/20 deprecation warnings)
- Action inputs/env vars reconciled for new majors

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push origin development
```

**Important**: The version bump, SPM audit fixes, doc changes, and CI workflow updates are now part of the PR diff and will be included when the PR is merged.

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

**Why not just `git rebase main`?** The `development` branch is protected with `allow_force_pushes: false`. A normal rebase requires force-push, which gets rejected. Additionally, the phantom commits from the merged PR conflict with the squash commit during rebase, causing conflicts even though there is no real diff. The solution is to temporarily unlock force-push, reset development to main's tip, cherry-pick only *genuinely new* commits (those added after the PR was created), force-push, then restore the protection.

**Why NOT `git cherry` for detecting new commits?** `git cherry` compares by patch-id. After a squash merge, the individual dev commits each have different patch-ids than the combined squash commit on main — so `git cherry` flags ALL of them as "+" (new) even though their content is already in main. Cherry-picking those phantoms produces duplicates or no-op conflicts. Use the **content diff** as the primary signal, and the **PR's own commit list** as the exclusion set.

```bash
# Step 1: Update local main and development
git checkout main && git pull origin main
git checkout development && git pull origin development

# Step 2: Discover repo and required status check contexts dynamically
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
CHECKS_JSON=$(gh api "repos/${REPO}/branches/development/protection" \
  --jq '[.required_status_checks.checks[].context]')
echo "Required status checks: ${CHECKS_JSON}"

# Step 3: Determine whether development has any REAL content diff vs main.
#   - No diff  → all dev commits were squashed into main. Clean reset, no cherry-pick.
#   - Has diff → someone pushed to dev after the merge. Preserve commits NOT in the PR.
if [ -z "$(git diff origin/main..origin/development --stat)" ]; then
  echo "Development has no content diff vs main — phantom commits only. Will reset cleanly."
  NEW_COMMITS=""
else
  echo "Development has real content diff vs main. Identifying commits not in PR #${PR_NUMBER}."
  # Chronological list of commits on dev not reachable from main
  DEV_COMMITS=$(git log --reverse --format='%H' origin/main..origin/development)
  # Regex of commit SHAs included in the merged PR (phantoms after squash)
  PR_COMMITS_PATTERN=$(gh pr view "${PR_NUMBER}" --json commits \
    --jq '[.commits[].oid] | join("|")')
  # Keep dev commits NOT in the PR set — these are genuinely new
  NEW_COMMITS=$(echo "${DEV_COMMITS}" | grep -vE "^(${PR_COMMITS_PATTERN})$" || true)
  echo "Genuinely new commits to preserve:"
  echo "${NEW_COMMITS:-<none>}"
fi

# Step 4: Temporarily enable force-push on the protected branch
gh api --method PUT "repos/${REPO}/branches/development/protection" --input - <<JSON
{
  "required_status_checks": {"strict": true, "contexts": ${CHECKS_JSON}},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": true
}
JSON

# Step 5: Reset development to main's tip, cherry-pick any genuinely new commits
git reset --hard origin/main
if [ -n "${NEW_COMMITS}" ]; then
  git cherry-pick ${NEW_COMMITS}
fi

# Step 6: Force-push the clean development branch
git push origin development --force-with-lease

# Step 7: Restore branch protection (disable force-push)
gh api --method PUT "repos/${REPO}/branches/development/protection" --input - <<JSON
{
  "required_status_checks": {"strict": true, "contexts": ${CHECKS_JSON}},
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false
}
JSON

echo "Development synced with main. Force-push protection restored."
```

**Verify the result**: `git diff origin/main..origin/development --stat` should be empty when no new commits were preserved, or match the expected set of post-merge changes when cherry-picks happened. `git log --oneline -3` on development should show main's squash commit as the base.

**Why the HEREDOC uses unquoted `JSON`**: the heredoc needs to interpolate `${CHECKS_JSON}` and `${REPO}`. The body has no literal `$` characters that need escaping, so unquoted is safe.

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

- SPM package audit applied with /spm-package-audit ✅
  - Package.resolved removed from git (if present)
  - Sibling dependency pattern applied to intrusive-memory/* deps
  - All dependencies updated to latest published versions
  - Dependencies pinned with .upToNextMajor()
- Version bumped to X.Y.Z on development ✅
- Swift source formatted with make lint ✅
- Documentation organized with /organize-agent-docs ✅
  - AGENTS.md: Universal project documentation
  - CLAUDE.md: Claude-specific instructions only
  - GEMINI.md: Gemini-specific instructions only
- README.md updated (user-facing documentation) ✅
- CI workflows audited — all GitHub Actions on latest major (no Node 16 deprecation warnings) ✅
- CI checks passed ✅
- Pull Request #<NUMBER> merged to main (includes version bump + SPM audit + docs + workflow updates) ✅
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
3. **Run /spm-package-audit BEFORE version bump** - This automatically fixes Package.resolved tracking, adds/updates sibling dependency pattern for intrusive-memory/* deps, and updates versions to latest. Verify no local path references remain afterward.
4. **Run `make lint` before committing** - Format all Swift source files with swift format
5. **Organize docs with /organize-agent-docs** - Ensure proper separation of universal vs agent-specific documentation
6. **Audit CI workflows for stale GitHub Actions** - Every `uses:` reference in `.github/workflows/` must be on the latest major. Older majors run on Node 16 (deprecated) and trigger `Node.js 16 actions are deprecated` warnings; some have been fully decommissioned (e.g. `actions/upload-artifact@v3`). Reconcile any input/env-var changes that come with the new major.
7. **Wait for CI after version bump** - Don't merge until the new CI run passes
8. **Use --squash** - Keep main branch history clean with single commits per PR
9. **Don't delete development** - It's a long-lived branch
10. **Tag on main after merge** - The tag goes on the squash merge commit
11. **Rebase development after release** - Use the protected-branch rebase procedure (Step 10): temporarily enable force-push via `gh api`, check `git diff origin/main..origin/development --stat` for real content changes, reset to main, cherry-pick only commits not in the merged PR (NOT via `git cherry` — patch-ids don't match a squash merge), force-push, restore protection. Never use `git merge main` — it leaves phantom commits in the next PR.
12. **Create next cycle PR** - Always open a new development→main PR after release so the branch is ready for new work
13. **NEVER manually build or upload release tarballs** - The `release.yml` CI workflow owns binary production. Never run `make dist` as part of releasing, never pass local file paths to `gh release create`.
14. **NEVER manually edit the Homebrew formula** - CI dispatches a `formula-update` event to homebrew-tap after uploading the tarball. The tap updates itself. If it doesn't, investigate the CI workflow — do not patch the formula by hand.

## Correct Flow

```
development: [features] -> [version bump] -> [make lint] -> [/organize-agent-docs] -> [audit CI workflows] -> (CI passes) -> PR merged
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
