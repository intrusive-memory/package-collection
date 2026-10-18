---
type: skill
name: ship-swift-library
description: Ship and release Swift library versions by bumping the version on development, merging the PR once CI passes, then tagging and creating a GitHub release from main. Accepts an optional version-bump argument (`patch`/`minor`/`major`) or explicit semver (`1.2.3`) to run unattended.
allowed-tools: Bash, Read, Grep, Glob, Edit, Skill
dependencies:
  - organize-agent-docs
  - codemap
---

# Ship Swift Library Skill

This skill handles the complete release process for Swift libraries.

**CRITICAL RULE**: Bump the version on `development` BEFORE merging the PR. The version bump ships as part of the PR merge to `main`. NEVER merge development directly to main when a PR exists.

## Invocation Modes

The skill runs in one of two modes, decided by whether an argument was supplied:

| Argument | Mode | Behavior |
|---|---|---|
| *(none)* | **Interactive** | Ask the user for the new version (Step 2) and whether to create the PR if one is missing (Step 1). |
| `patch` / `minor` / `major` | **Unattended** | Derive the new version from the last git tag + the requested bump component. Auto-create the PR if missing. Never prompt. |
| `X.Y.Z` (explicit semver) | **Unattended** | Use the literal version. Must be clean semver (no `-dev`, no leading `v`) and strictly greater than the last tag. Auto-create the PR if missing. Never prompt. |

**Unattended mode contract:**
- Never ask the user a question. If a decision can't be made automatically (ambiguous repo state, dirty tree, divergent branches, CI failure, missing `development` branch, audit-step abort), stop immediately and surface the blocker — do **not** fall through to interactive prompts.
- The hard guards in Steps 8 and 9 (`-dev` refusal, semver shape) still apply. Argument validation does not bypass them.
- Set `UNATTENDED=1` for downstream steps to branch on.

### Argument parsing (run first, before the Applicability Gate)

```bash
ARG="${1:-}"   # the raw argument string passed to /ship-swift-library
UNATTENDED=0
BUMP_KIND=""
EXPLICIT_VERSION=""

case "$ARG" in
  "")
    UNATTENDED=0
    ;;
  patch|minor|major)
    UNATTENDED=1
    BUMP_KIND="$ARG"
    ;;
  [0-9]*.[0-9]*.[0-9]*)
    case "$ARG" in
      *-dev*|v*) echo "ABORT: explicit version must be clean semver (no '-dev', no leading 'v'). Got: $ARG"; exit 1 ;;
    esac
    UNATTENDED=1
    EXPLICIT_VERSION="$ARG"
    ;;
  *)
    echo "ABORT: unrecognized argument '$ARG'. Expected one of: (none), patch, minor, major, X.Y.Z"
    exit 1
    ;;
esac
```

In unattended mode, also verify the working tree is clean and the local `development` is up-to-date with origin before doing anything destructive — bail loudly otherwise.

## Applicability Gate

Before doing anything else, verify this skill applies to the current repo:

```bash
# Must have a Package.swift at the root (it's a Swift package)
test -f Package.swift || { echo "NOT a Swift package — abort"; exit 1; }

# Must have a long-lived development branch
git ls-remote --heads origin development | grep -q development \
  || { echo "No development branch — this may be a main-only repo"; exit 1; }
```

If either check fails, stop and ask the user. **A missing `development` branch is not confined to data repos** — genuine Swift libraries in the org are main-only too (confirmed: `glosa-tools`, `SwiftAprendiendo`). Do not create a `development` branch to satisfy the gate, and do not fall back to releasing straight off `main`: that skips the bump-before-merge invariant the whole flow rests on.

This gate is **structural, not name-based**. The naming tables in the reference are hints; `Package.swift` + a `development` branch is the actual test. For the conventions and the repos this skill explicitly does NOT apply to (data repos, collaboration forks, CLI tools/apps) — see `references/applicability.md`.

## Process Overview

16 steps (0–15) in order. Steps marked **[ref]** load a reference file before executing.

### 0. Preflight: Confirm Development Is a Clean Descendant of Main

**Run this before anything else.** If the *previous* ship cycle skipped Step 11, `development` still carries phantom commits whose content was squashed onto `main`. Replaying them conflicts, the release PR lands in `CONFLICTING` state, and — the part that wastes the most time — **GitHub cannot build a merge ref for a conflicted PR, so the `pull_request` workflow never fires at all.** `gh pr checks` then reports `no checks reported on the 'development' branch`, which reads like "CI hasn't started yet" and will hang a `--watch` or a polling monitor indefinitely.

```bash
git fetch origin --tags -q

# Is main's tip already an ancestor of development? If not, development is stale
# or divergent and the release PR will conflict.
if git merge-base --is-ancestor origin/main origin/development; then
  echo "OK: development descends cleanly from main."
else
  echo "DIVERGENT: development does not contain main's tip."
  echo "  main:        $(git log -1 --format='%h %s' origin/main)"
  echo "  development: $(git log -1 --format='%h %s' origin/development)"
  echo "  main-only commits: $(git rev-list --count origin/development..origin/main)"
  echo ""
  echo "Run the Step 11 rebase procedure (references/rebase-development.md) NOW,"
  echo "before creating or updating the release PR. Do NOT 'git merge main' —"
  echo "that is what produced this state in the first place."
fi
```

If divergent, run `references/rebase-development.md` **up front**. That reference is written to be safe at either end of the cycle. Only continue to Step 1 once `merge-base --is-ancestor` passes.

### 1. Check for Open Pull Request

```bash
gh pr list --base main --head development --json number,title,isDraft
```

If a PR exists, proceed.

**Interactive mode**: if none exists, ask the user whether to create one.

**Unattended mode**: if none exists, auto-create a draft PR with a placeholder title — Step 5 will rewrite the title and body once the new version is known and the diff has settled:

```bash
gh pr create \
  --draft \
  --base main \
  --head development \
  --title "Release (auto-created by /ship-swift-library)" \
  --body "Auto-created by /ship-swift-library in unattended mode. Title and body will be rewritten in Step 5 once the version bump lands."
```

Then re-read the PR number for use in subsequent steps:

```bash
PR_NUMBER=$(gh pr list --base main --head development --json number --jq '.[0].number')
test -n "$PR_NUMBER" || { echo "ABORT: PR creation succeeded but no PR is listed"; exit 1; }
```

### 2. Determine Version Number

**The version in source code is NOT authoritative.** Derive the current version from git tags:

```bash
git fetch --tags
LAST_TAG=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
LAST_VERSION="${LAST_TAG#v}"
LAST_VERSION="${LAST_VERSION:-0.0.0}"
echo "Last released version: ${LAST_VERSION}"
```

If no tags exist, treat as `0.0.0`.

Source files between releases carry an `X.Y.Z-dev` marker (set by step 12 of the previous cycle). Strip the `-dev` suffix before comparing:
- Source `1.4.2-dev` + tag `v1.4.2` → equivalent, in post-1.4.2 dev cycle.
- Source `1.4.2-dev` + tag `v1.4.1` → discrepancy, investigate.
- Source has no `-dev` suffix → flag it.

**Bump semantics:**
- **Patch** (x.y.Z): Bug fixes, small improvements
- **Minor** (x.Y.0): New features, non-breaking changes
- **Major** (X.0.0): Breaking changes

#### Interactive mode

Ask the user for the new version, presenting `LAST_VERSION` as baseline.

#### Unattended mode

Compute the new version automatically from `$LAST_VERSION` and `$BUMP_KIND` / `$EXPLICIT_VERSION`:

```bash
IFS=. read -r MAJ MIN PAT <<< "$LAST_VERSION"

if [ -n "$EXPLICIT_VERSION" ]; then
  NEW_VERSION="$EXPLICIT_VERSION"
else
  case "$BUMP_KIND" in
    patch) NEW_VERSION="${MAJ}.${MIN}.$((PAT + 1))" ;;
    minor) NEW_VERSION="${MAJ}.$((MIN + 1)).0" ;;
    major) NEW_VERSION="$((MAJ + 1)).0.0" ;;
    *) echo "ABORT: BUMP_KIND='$BUMP_KIND' is invalid in unattended mode"; exit 1 ;;
  esac
fi

# Sanity guards
case "$NEW_VERSION" in
  *-dev*) echo "ABORT: computed version '$NEW_VERSION' contains '-dev'"; exit 1 ;;
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "ABORT: computed version '$NEW_VERSION' is not clean semver"; exit 1 ;;
esac

# Strict monotonic check against the last tag
if [ "$(printf '%s\n%s\n' "$LAST_VERSION" "$NEW_VERSION" | sort -V | tail -1)" != "$NEW_VERSION" ] \
   || [ "$NEW_VERSION" = "$LAST_VERSION" ]; then
  echo "ABORT: new version '$NEW_VERSION' must be strictly greater than last tag '$LAST_VERSION'"
  exit 1
fi

echo "Unattended: bumping ${LAST_VERSION} → ${NEW_VERSION} (${BUMP_KIND:-explicit})"
```

**The new version MUST NOT contain `-dev`.** Tag and release are always clean semver. The hard guards in Steps 8 and 9 will refuse a `-dev` version regardless of mode.

### 3. Bump Version, Update Dependencies, Flip Package.swift to Remote-Only, Audit Documentation, and Audit CI Workflows **[ref]**

This is the heaviest step — five coupled sub-tasks that all land in a **single commit on `development`**:

1. Run `/spm-package-audit` to fix Package.resolved tracking and update intrusive-memory/* deps.
2. Run `/toggle-sibling-libraries --to remote` to strip the `sibling(...)` helpers and pin every intrusive-memory/* dep to its latest published `.upToNextMajor(from: ...)` release. The shipped `Package.swift` must NOT carry the dev-only sibling scaffolding.
3. Edit version files, **stripping any `-dev` suffix**. The new version is clean semver.
4. Run `make lint` to format Swift sources.
5. Run `/organize-agent-docs`, update README.md, then run `/codemap` to refresh the
   checked-in graphify codemap (regenerates `graphify-out/`, ensures AGENTS.md
   references it, and commits the portable map as its own `chore(codemap)` commit).
6. Audit `.github/workflows/` and bump every action `uses:` reference to its latest major.
7. Commit the rest together and push to `development` (the push also carries the codemap commit).

**Read `references/version-bump.md` for the full procedure** — including the toggle invocation and verification, the `-dev` strip recipe, dependency verification, the dynamic CI-action audit table, and the canonical commit message.

### 4. Verify CI Checks Pass

The version-bump push triggers a new CI run.

**Check mergeability BEFORE waiting on checks.** A `CONFLICTING` PR produces zero checks — not failing checks, *no* checks — because GitHub never builds the merge ref that `pull_request`-triggered workflows run against. Waiting on that state never terminates:

```bash
MERGEABLE=$(gh pr view "$PR_NUMBER" --json mergeable --jq '.mergeable')
case "$MERGEABLE" in
  MERGEABLE) ;;
  CONFLICTING)
    echo "ABORT: PR #${PR_NUMBER} is CONFLICTING — no CI will run until this is resolved."
    echo "Almost always means development was never rebased after the last release."
    echo "Run references/rebase-development.md, then re-check."
    exit 1 ;;
  UNKNOWN)
    echo "Mergeability still computing; re-poll in a few seconds before proceeding."
    exit 1 ;;
esac
```

Then wait for the checks:

```bash
gh pr checks "$PR_NUMBER" --watch
```

If `gh pr checks` prints `no checks reported on the '<branch>' branch` **while the PR is MERGEABLE**, the workflow's trigger does not cover this PR — inspect `on:` in `.github/workflows/tests.yml` (it should include `pull_request: branches: [main, development]`) rather than continuing to wait.

If checks fail, stop and surface the failure.

### 5. Update Pull Request Title and Description

The squash merge inherits the PR title as the commit message on `main`, so the title becomes permanent git history. Update title and body to reflect what's actually shipping — the body also seeds the GitHub release notes in step 9.

Synthesize a summary from the commits and diff in this PR:

```bash
LAST_TAG=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
git log "${LAST_TAG}..HEAD" --pretty=format:'- %s'
git diff "${LAST_TAG}...HEAD" --stat
```

Group commits into **New Features / Bug Fixes / Testing / Documentation** by reading commit subjects. Draft a title in the format `Release vX.Y.Z: <one-line summary>` — this is what lands on `main`'s history forever.

Apply the update:

```bash
gh pr edit <PR_NUMBER> \
  --title "Release vX.Y.Z: <one-line summary>" \
  --body "$(cat <<'EOF'
# Release vX.Y.Z

## Summary
<2-3 sentence description of what this release delivers>

### New Features
- ...

### Bug Fixes
- ...

### Testing
- ...

### Documentation
- ...
EOF
)"
```

Verify:

```bash
gh pr view <PR_NUMBER> --json title,body
```

**Save the body text** — Step 9 reuses it as the GitHub release notes (prefixed with the library name and suffixed with the Full Changelog link).

### 6. Merge Pull Request

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch=false
```

Use `--squash` (clean single commit on main). Do NOT delete the `development` branch (it's long-lived).

### 7. Pull Merge Commit to Local Main

```bash
git checkout main
git pull origin main
git log --oneline -1   # Verify you're on the squash merge commit
```

### 8. Create Annotated Tag on Main

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
# Match a -dev VERSION SUFFIX (1.2.3-dev), not the bare substring.
# A bare `-dev` grep produces false positives on ordinary English —
# "on-device", "re-development", "dev-dependencies" — and will abort a
# perfectly valid release. Anchor to semver.
grep -REn -- '[0-9]+\.[0-9]+\.[0-9]+-dev' Sources/ README.md AGENTS.md CLAUDE.md GEMINI.md 2>/dev/null \
  && { echo "ABORT: '-dev' version marker still present. Re-run step 3."; exit 1; } \
  || echo "No -dev version markers. Safe to tag."
```

Then tag:

```bash
git tag -a "v${VERSION}" -m "Release v${VERSION}: <Short description>

<Detailed release notes>"

git push origin "v${VERSION}"
```

### 9. Create GitHub Release (metadata only — NO tarball upload)

The `release.yml` CI workflow fires on `release: published`, builds the canonical tarball, and uploads it to the release. **Do NOT upload any tarball or binary assets** and **never run `make dist`** as part of releasing.

> **Homebrew is no longer part of this step.** Source repos used to dispatch a `formula-update` event to `intrusive-memory/homebrew-tap`. That path is dead — the org `DEPLOY_TOKEN` PAT expired in July 2026 and was deleted, so the dispatch step referenced a nonexistent secret and failed on every release run. It has been removed from `release.yml`. The tap now **pulls** instead. See Step 10.

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

### 10. Verify the Release Workflow (and optionally nudge Homebrew)

```bash
gh release view vX.Y.Z --json tagName,targetCommitish,url
gh run list --workflow=release.yml --limit=3
```

Wait for the `vX.Y.Z` run to show `completed / success`. The workflow builds the release binary and uploads the tarball to the GitHub release. **That is all it does** — it does not touch Homebrew.

#### How the tap updates now (pull-based, scheduled)

`intrusive-memory/homebrew-tap` runs `reconcile-formulas.yml` on a **6-hour cron**. It walks every formula, compares it against its source repo's latest stable release, and commits any drift. It needs no cross-repo credential: the source repos are public and the only write is to the tap itself, covered by the built-in `GITHUB_TOKEN`.

This is strictly more reliable than the old dispatch, which failed silently — when the PAT expired, three formulas went stale for a week with no signal anywhere. Reconciliation self-heals drift regardless of cause.

**Consequences for this skill:**

- **Do not wait for the tap in the release flow.** Up to 6 hours may pass before the formula moves. Blocking here would stall every release.
- **Do not look for a `formula-update` dispatch.** There isn't one. `update-formula.yml` still exists in the tap but is now reachable only via manual `workflow_dispatch`.
- **A stale formula immediately after release is expected, not a failure.**

If you want the formula updated now rather than within 6 hours, trigger the reconcile manually:

```bash
# Optional fast path — not required for the release to be complete
gh workflow run reconcile-formulas.yml --repo intrusive-memory/homebrew-tap
gh run list --workflow=reconcile-formulas.yml --repo intrusive-memory/homebrew-tap --limit 1
```

Dry-run first if you want to see drift without committing:

```bash
gh workflow run reconcile-formulas.yml --repo intrusive-memory/homebrew-tap -f dry_run=true
```

**Never manually edit a formula.** If reconciliation genuinely isn't picking a release up, investigate `scripts/reconcile-formulas.sh` in the tap — do not hand-patch the `.rb`.

#### Repos with no formula at all

Not every library has one. A library-only package that ships no executable has no formula by design (e.g. SwiftHablare went library-only at v6.1.0; its formula is intentionally absent from the tap). For those, this whole section and Step 14 are **N/A** — say so in the summary rather than reporting a phantom failure.

### 11. Rebase Development onto Main **[ref]**

After a squash merge, development carries phantom commits whose patch-ids no longer match the squash on main. A naive `git merge main` leaves those phantoms visible in the next PR (huge commit list, zero diff).

The fix: back up the current tip, reset development to main's tip, cherry-pick only *genuinely new* commits (those added after the PR was created), then force-push — temporarily unlocking force-push **only if `development` is actually protected**, and restoring it afterward. Protection is per-repo; plenty of repos have none, in which case `gh api .../branches/development/protection` returns a 404 that is a normal answer rather than an error.

**Skipping this step is not free.** It is what leaves the *next* cycle's release PR in `CONFLICTING` state with no CI — see Step 0.

**Read `references/rebase-development.md` for the full procedure** — including protection detection, why `git cherry` fails on squash merges, the expected version-bump conflict, and the byte-identical-tree verification.

### 12. Mark Development Branch with `-dev` Version and Restore Sibling Pattern **[ref]**

After the rebase, development is bit-identical to main and carries a remote-only `Package.swift` (because Step 3 flipped it for shipping). Two things happen here:

1. Stamp source with `X.Y.Z-dev` (where `X.Y.Z` is what you just released) so:
   - `gh pr create` for the next-cycle PR has a non-empty diff and works reliably.
   - "Release vs. dev snapshot?" is answerable from source.
2. Run `/toggle-sibling-libraries --to sibling` to restore the `sibling(...)` helpers and route intrusive-memory/* deps back through `../<name>` checkouts when present. Without this, coordinated cross-library development on the new dev cycle is impossible.

**Read `references/dev-marker.md` for the full procedure** — including which files to touch, which NOT to touch, and how the toggle and `-dev` stamp combine into a single commit.

### 13. Create Next Development Cycle PR (Draft)

The `-dev` bump in step 12 guarantees a non-empty diff, so PR creation will succeed reliably. Draft mode signals the PR is a landing target for future work, not ready for review or merge:

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

### 14. (Optional, non-blocking) Verify the Released Version Is Installed via Homebrew

**This step no longer gates the release.** Under the pull-based tap (Step 10), reconciliation runs on a 6-hour cron, so in the common case the formula has *not* moved yet when you reach this step. A mismatch here is the expected state immediately after a release, not a defect.

Run it only when one of these is true:
- You manually triggered `reconcile-formulas.yml` in Step 10 and watched it complete.
- Enough time has passed (≥6h) that reconciliation should have run.
- You are specifically investigating a formula suspected of being stale.

Otherwise, record **"deferred — tap reconciles within 6h"** in the summary and finish. Do not poll, and never block the release on it.

**Applicability:** this only makes sense if the package ships an **executable product** installed by a formula (a CLI binary). A pure library with no executable has nothing to run, and a library-only package has no formula at all — note "N/A (no executable product)" in the summary and move on.

**Resolve the binary name per library — do NOT hardcode it.** Different libraries ship differently-named binaries, so derive the executable name from *this* package's manifest. Prefer the declared executable product; fall back to what the formula installs:

```bash
# Primary: read the executable product name straight from Package.swift.
BINARY="$(swift package dump-package 2>/dev/null \
  | jq -r '.products[] | select(.type | has("executable")) | .name' \
  | head -1)"

# Fallback: whatever the tap formula installs via `bin.install`.
if [ -z "$BINARY" ] || [ "$BINARY" = "null" ]; then
  BINARY="$(git -C <path-to-homebrew-tap> grep -hoE 'bin\.install .*"([^"]+)"' -- '*.rb' 2>/dev/null \
    | grep -oE '"[^"]+"' | tr -d '"' | tail -1)"
fi

# No executable anywhere → pure library, nothing to run.
if [ -z "$BINARY" ] || [ "$BINARY" = "null" ]; then
  echo "No executable product — pure library. Skipping brew binary verification (mark N/A in summary)."
else
  echo "Resolved binary for this library: ${BINARY}"
fi
```

If a binary was resolved, update Homebrew and query it:

```bash
brew update && brew upgrade

INSTALLED_VERSION="$("$BINARY" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
echo "Installed: ${INSTALLED_VERSION:-<none>} — expected: ${NEW_VERSION}"

if [ "$INSTALLED_VERSION" = "$NEW_VERSION" ]; then
  echo "✅ Homebrew is serving v${NEW_VERSION} — release verified end-to-end."
else
  echo "⚠️ Installed version '${INSTALLED_VERSION:-<none>}' does not match released 'v${NEW_VERSION}'."
  echo "   Expected inside the release window: the tap reconciles on a 6-hour cron."
  echo "   Trigger it now with: gh workflow run reconcile-formulas.yml --repo intrusive-memory/homebrew-tap"
fi
```

A mismatch is **not** fatal and is the *expected* result inside the release window — the release itself already succeeded at Step 9, and the tap reconciles on a 6-hour cron. In unattended mode, surface a mismatch as an informational note in the summary, never as a warning that implies something went wrong, and never abort on it.

### 15. Summary Report

Provide a final summary covering: preflight branch-divergence check, SPM audit applied (or noted as a no-op), version bumped, lint, docs organized, README updated, codemap refreshed and committed, CI workflows audited, CI passed, PR title/description updated, PR merged, tag created, GitHub release published, release workflow completed, development rebased and stamped `-dev`, draft next-cycle PR opened.

**Report honestly, including no-ops and N/As.** Several steps legitimately do nothing on a given repo — a package with no `intrusive-memory/*` dependencies has nothing for `/spm-package-audit` or the sibling toggle to do; a library with no executable has no Homebrew formula; Step 14 is deferred by design. Say "no-op — no intrusive-memory deps" or "deferred — tap reconciles within 6h" rather than listing them as completed work. A summary that claims a step ran when it didn't is worse than one that admits the step was inapplicable.

Include the release URL and the next-cycle PR URL.

## Critical Rules (NEVER VIOLATE)

1. **Derive version from git tags, not source code** — Run `git tag --sort=-v:refname` to find the last released version. The `version` string in source is informational and may be stale.
2. **Bump version BEFORE merging** — The version bump must be part of the PR.
3. **Run /spm-package-audit BEFORE version bump** — Auto-fixes Package.resolved tracking, sibling-dep pattern for intrusive-memory/*, and updates versions to latest. Verify no local `.path()` references remain.
4. **Run /toggle-sibling-libraries --to remote BEFORE the version edit** — The shipped `Package.swift` must be plain `.package(url:..., .upToNextMajor(from: ...))` calls only. The `sibling(...)` helper and `useLocalSiblings` constant are developmental scaffolding that has no business in a tagged release. Symmetric: at Step 12, run `--to sibling` to restore them for the new dev cycle.
5. **Run `make lint` before committing** — Format Swift sources with swift format.
6. **Organize docs with /organize-agent-docs** — Separate universal vs agent-specific documentation.
7. **Audit CI workflows for stale GitHub Actions** — Every `uses:` in `.github/workflows/` must be on the latest major. Older majors run on Node 16 (deprecated) and trigger warnings; some are decommissioned (e.g. `actions/upload-artifact@v3`).
8. **Wait for CI after version bump — but check `mergeable` first** — Don't merge until the new CI run passes. A `CONFLICTING` PR yields *zero* checks rather than failing ones, because GitHub never builds the merge ref; waiting on it hangs forever. Verify `gh pr view --json mergeable` is `MERGEABLE` before any `--watch` or polling loop.
9. **Update the PR title and description before merge** — The squash merge inherits the PR title as the commit message on `main`, so it becomes permanent git history. Draft `Release vX.Y.Z: <summary>` and a categorized body from `git log "${LAST_TAG}..HEAD"` and reuse the body for the GitHub release notes.
10. **Use --squash** — Single commit per PR on main.
11. **Don't delete development** — It's a long-lived branch.
12. **Tag on main after merge** — Tag goes on the squash merge commit.
13. **Rebase development after release** — See `references/rebase-development.md`. Never `git merge main` (leaves phantom commits). The procedure detects whether `development` is actually protected and only toggles force-push when it is; **protection is per-repo and many repos do not have it**, so never assume either way. Skipping this step is what causes the next cycle's release PR to land `CONFLICTING` — see Step 0.
14. **Mark development as `-dev` after release AND restore the sibling pattern** — See `references/dev-marker.md`. Never leave development bit-identical to main, and never leave Package.swift in remote-only mode after release (cross-library dev workflows depend on the sibling helpers).
15. **NEVER tag, release, or publish a `-dev` version** — Steps 8 and 9 carry hard `case` guards. Do not bypass them.
16. **Create next cycle PR in DRAFT mode** — `gh pr create --draft`.
17. **NEVER manually build or upload release tarballs** — `release.yml` owns binary production. Never run `make dist`, never pass local file paths to `gh release create`.
18. **NEVER manually edit the Homebrew formula** — The tap **pulls**: `reconcile-formulas.yml` in `intrusive-memory/homebrew-tap` compares every formula against its source repo's latest release on a 6-hour cron. Source repos do NOT dispatch `formula-update` any more (the `DEPLOY_TOKEN` PAT expired and was deleted in July 2026; the step was removed from `release.yml`). Do not add a dispatch step back, and do not hand-patch a `.rb` — if a formula is genuinely stuck, fix `scripts/reconcile-formulas.sh` in the tap.
19. **Never block a release on Homebrew** — Reconciliation runs on a 6-hour cron, so the formula almost always lags the release you just cut. That lag is correct behavior, not a failure. Step 14 is optional and deferred; record it as such. `gh workflow run reconcile-formulas.yml --repo intrusive-memory/homebrew-tap` is the fast path if you need it now.

## Correct Flow

```
preflight:   [merge-base --is-ancestor origin/main origin/development] -- divergent? rebase FIRST (Step 11 ref)
development: [features on X.Y.Z-dev] -> [strip -dev, bump to A.B.C] -> [make lint] -> [/organize-agent-docs] -> [/codemap] -> [audit CI workflows] -> (mergeable? -> CI passes) -> [update PR title/body] -> PR merged
main:        -----------------------------------------------------------------------------> [squash commit] -> [tag vA.B.C] -> [release (metadata only)]
CI:          -------------------------------------------------------------------------------------^-- [build binary] -> [upload tarball to release]  (NO homebrew dispatch)
homebrew-tap:------------------------------------------------------------------------------------------ (independent 6h cron reconciles formulas; may lag hours)
development: [rebase onto main] -> [force-push] -> [stamp A.B.C-dev, commit, push] -> [draft PR to main]
```

## Error Handling

If any step fails:
1. Stop immediately
2. Explain what failed and why
3. Provide fix guidance
4. Do not proceed

In **unattended mode** (`UNATTENDED=1`), failures must exit non-zero so callers like `/package-iterator` can detect them. Do not degrade to interactive prompts on failure — surface the blocker and stop. The caller decides whether to retry, skip, or escalate.

## Notes

- Requires GitHub CLI (`gh`) authenticated
- Requires git configured with merge permissions
