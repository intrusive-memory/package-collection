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

If either check fails, stop and ask the user. A missing `development` branch usually means a main-only repo (like `package-collection`) and a different release flow applies.

For the full repo naming-convention table — which repos this skill applies to (`Swift<Word>`, `<kebab>-swift`, `<domain>-format`) and which it does NOT (`package-collection`, collaboration forks, CLI tools/apps) — see `references/applicability.md`.

## Process Overview

15 steps in order. Steps marked **[ref]** load a reference file before executing.

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

The version-bump push triggers a new CI run. Wait for it:

```bash
gh pr checks <PR_NUMBER> --watch
```

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

### 9. Create GitHub Release (metadata only — NO tarball upload)

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

### 10. Verify Release and Wait for CI

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

### 11. Rebase Development onto Main **[ref]**

After a squash merge, development carries phantom commits whose patch-ids no longer match the squash on main. A naive `git merge main` leaves those phantoms visible in the next PR (huge commit list, zero diff).

The fix: temporarily unlock force-push, reset development to main's tip, cherry-pick only *genuinely new* commits (those added after the PR was created), force-push, then restore protection.

**Read `references/rebase-development.md` for the full procedure** — including the protection toggle, why `git cherry` fails on squash merges, and the verification step.

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

### 14. Verify the Released Version Is Installed via Homebrew

Once Step 10 has confirmed the homebrew-tap formula was bumped to `vX.Y.Z`, pull it onto this machine and confirm the installed CLI binary reports the version you just shipped. This is the end-to-end proof that a user running `brew upgrade` today gets this release.

**Applicability:** this step only makes sense if the package ships an **executable product** installed by the formula (a CLI binary). A pure library with no executable has nothing to run — skip the binary check, note "N/A (no executable product)" in the summary, and move on.

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
  echo "   Homebrew bottle/tap propagation can lag a few minutes behind the formula-update commit."
  echo "   Re-run 'brew update && brew upgrade' shortly, or inspect the tap if it persists."
fi
```

A mismatch is **not** fatal — the release itself already succeeded at Step 9, and bottle builds / tap propagation legitimately lag a few minutes behind the `formula-update` commit that Step 10 confirmed. In unattended mode, surface a mismatch as a warning in the summary rather than aborting.

### 15. Summary Report

Provide a final summary covering: SPM audit applied, version bumped, lint, docs organized, README updated, codemap refreshed and committed, CI workflows audited, CI passed, PR title/description updated, PR merged, tag created, GitHub release published, CI release workflow triggered, Homebrew formula updated, installed version verified via `brew upgrade` (or N/A for pure libraries), local branches updated, development synced and stamped `-dev`, draft next-cycle PR opened.

Include the release URL and the next-cycle PR URL.

## Critical Rules (NEVER VIOLATE)

1. **Derive version from git tags, not source code** — Run `git tag --sort=-v:refname` to find the last released version. The `version` string in source is informational and may be stale.
2. **Bump version BEFORE merging** — The version bump must be part of the PR.
3. **Run /spm-package-audit BEFORE version bump** — Auto-fixes Package.resolved tracking, sibling-dep pattern for intrusive-memory/*, and updates versions to latest. Verify no local `.path()` references remain.
4. **Run /toggle-sibling-libraries --to remote BEFORE the version edit** — The shipped `Package.swift` must be plain `.package(url:..., .upToNextMajor(from: ...))` calls only. The `sibling(...)` helper and `useLocalSiblings` constant are developmental scaffolding that has no business in a tagged release. Symmetric: at Step 12, run `--to sibling` to restore them for the new dev cycle.
5. **Run `make lint` before committing** — Format Swift sources with swift format.
6. **Organize docs with /organize-agent-docs** — Separate universal vs agent-specific documentation.
7. **Audit CI workflows for stale GitHub Actions** — Every `uses:` in `.github/workflows/` must be on the latest major. Older majors run on Node 16 (deprecated) and trigger warnings; some are decommissioned (e.g. `actions/upload-artifact@v3`).
8. **Wait for CI after version bump** — Don't merge until the new CI run passes.
9. **Update the PR title and description before merge** — The squash merge inherits the PR title as the commit message on `main`, so it becomes permanent git history. Draft `Release vX.Y.Z: <summary>` and a categorized body from `git log "${LAST_TAG}..HEAD"` and reuse the body for the GitHub release notes.
10. **Use --squash** — Single commit per PR on main.
11. **Don't delete development** — It's a long-lived branch.
12. **Tag on main after merge** — Tag goes on the squash merge commit.
13. **Rebase development after release using the protected-branch procedure** — See `references/rebase-development.md`. Never `git merge main` (leaves phantom commits).
14. **Mark development as `-dev` after release AND restore the sibling pattern** — See `references/dev-marker.md`. Never leave development bit-identical to main, and never leave Package.swift in remote-only mode after release (cross-library dev workflows depend on the sibling helpers).
15. **NEVER tag, release, or publish a `-dev` version** — Steps 8 and 9 carry hard `case` guards. Do not bypass them.
16. **Create next cycle PR in DRAFT mode** — `gh pr create --draft`.
17. **NEVER manually build or upload release tarballs** — `release.yml` owns binary production. Never run `make dist`, never pass local file paths to `gh release create`.
18. **NEVER manually edit the Homebrew formula** — CI dispatches `formula-update` to homebrew-tap. If it doesn't, investigate the workflow.
19. **Verify the installed version after the formula updates** — Once Step 10 confirms the tap bump, run `brew update && brew upgrade` and `<binary> --version` to prove `brew` now serves the released version. Skip for pure libraries with no executable product. A version mismatch is a warning (propagation lag), not an abort — the release already succeeded at Step 9.

## Correct Flow

```
development: [features on X.Y.Z-dev] -> [strip -dev, bump to A.B.C] -> [make lint] -> [/organize-agent-docs] -> [/codemap] -> [audit CI workflows] -> (CI passes) -> [update PR title/body] -> PR merged
main:        -----------------------------------------------------------------------------> [squash commit] -> [tag vA.B.C] -> [release (metadata only)]
CI:          -------------------------------------------------------------------------------------^-- [build tarball] -> [upload to release] -> [dispatch formula-update to homebrew-tap]
homebrew-tap:--------------------------------------------------------------------------------^-- (auto-updated by formula-update event)
local brew:  ------------------------------------------------------------------------------------------^-- [brew update && brew upgrade] -> [<binary> --version == vA.B.C]
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
