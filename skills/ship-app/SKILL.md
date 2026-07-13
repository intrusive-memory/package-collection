---
type: skill
name: ship-app
description: Ship one or more iOS/macOS App Store apps from a single repo through development → main → TestFlight, then promote to the App Store by tagging a release candidate (v<version>-rc.<k>) on main and merging that tag into a release branch. Handles repos that ship several apps at once (e.g. an iOS app + a macOS app, each its own App Store Connect record/scheme). Orchestrates the development→main PR cycle (which auto-ships to TestFlight via Xcode Cloud), then the RC-tag → release promotion that uploads to App Store Connect, then submission. Xcode Cloud only builds/archives/uploads; GitHub CI owns all test gating. Use when asked to ship, release, cut a release candidate, promote to the App Store, run release QA, or push iOS/macOS apps to TestFlight or the App Store.
allowed-tools: Bash, Read, Grep, Glob, Edit, Skill
---

# Ship App Skill

This skill orchestrates the complete release cycle for one or more iOS/macOS apps
built from a single repo with Xcode and distributed via App Store Connect +
Xcode Cloud. A repo may ship several App Store apps at once — for example an iOS
app and a macOS app, each its own ASC record, bundle id, and scheme. The branch
model is identical; it just fans out across every app.

**Division of labor (load-bearing):**
- **Xcode Cloud** only *builds, archives, and uploads.* Its per-app workflow
  configuration is the sole authority for **what** ships at each stage — an app
  with no workflow for a stage simply isn't shipped there. Xcode Cloud **never
  runs tests** (its runners are Intel; parts of the suite are
  Apple-Silicon-specific — MLX/Metal/arm64).
- **GitHub CI** owns **all test gating** — the required PR gate into `main`, plus
  the optional `v*-rc.*` tag and final-tag/release gates — and gates the merge,
  tag, and release process. GitHub Actions runs on Apple Silicon, the only place
  the arm64 tests run faithfully.

**Read [`DEVELOPMENT_PATTERN.md`](DEVELOPMENT_PATTERN.md) first.** It defines the
branch model, the workflow expectations, and the invariants this skill enforces.
The phases below are the mechanics; that document is the doctrine. If something
here contradicts it, the doctrine wins.

The detailed QA procedure (tester groups, bug-filing conventions, sign-off
criteria, hotfix flow) lives in [`references/qa-process.md`](references/qa-process.md).

## The model in one breath

**The ref a commit lands on selects its Xcode Cloud destination:**

| Land code on… | Xcode Cloud does… | Result |
|---|---|---|
| `main` (merge) | `MAIN => TESTFLIGHT` — build + archive + upload | **TestFlight (beta)** |
| tag `v<version>-rc.<k>` on `main` (push) | `RC => RELEASE` — build + archive | release gate (no upload) |
| `release/<n>` (merge) | `RELEASE => APP STORE` — archive + upload | **App Store Connect** |

So **shipping to TestFlight = merging `development → main`.** Promoting to the
App Store = **tagging that `main` commit `v<version>-rc.<k>`** and **merging that
tag into the standing `release/<n>` branch.** There is **no candidate branch** and
**no manual uploads** — the release candidate is a *tag on `main`*, not a branch.

**Where the marketing version lives (load-bearing):** `development` always carries
the **next** version being worked on; `main` always carries the **current shipping**
version. The version advances **at the `development → main` merge** — that merge is
the only place `MARKETING_VERSION` changes. The RC tag and the `release/<n>` merge
carry whatever version is already on `main`; they never bump it.

## When to use this vs. ship-swift-library

| If the repo is… | Use |
|---|---|
| A Swift Package (root `Package.swift`, no `.xcodeproj`) | `/ship-swift-library` |
| An Xcode app (root `.xcodeproj` or `.xcworkspace`) shipping to App Store Connect | This skill |
| Several App Store apps from one repo (iOS + macOS, multiple schemes) | This skill — it loops every app |
| Both (an app repo that also vends a library) | This skill — the library lifecycle rides along with the app release |

## Multiple apps from one repo

Declare each shipping app in **`.asc.json`** under an `apps` array. Every per-app
operation (validation, version/build bumps, ship confirmation, submission) loops
this set.

```json
{
  "apps": [
    { "name": "MyApp iOS",   "appId": "111", "bundleId": "com.x.app",
      "platform": "IOS",    "scheme": "MyApp-iOS",   "xcconfig": "Config/Version-iOS.xcconfig" },
    { "name": "MyApp macOS", "appId": "222", "bundleId": "com.x.app.mac",
      "platform": "MAC_OS", "scheme": "MyApp-macOS", "xcconfig": "Config/Version-macOS.xcconfig" }
  ]
}
```

- **`xcconfig`** (recommended) names the file holding that app's
  `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` — the clean way to version
  independent targets. Per-app fallbacks: `infoPlist` (PlistBuddy
  `CFBundleShortVersionString` / `CFBundleVersion`), or `agvtool` only for a
  single-app repo with neither.
- **Backward compatible:** a single top-level `.app`/`.appId` (or `ASC_APP_ID`
  env, or `--app`) is treated as a one-element `apps[]`. Existing single-app
  repos need no changes.
- **Xcode Cloud gates what ships.** Each app has its own Xcode Cloud workflow set
  (TestFlight / candidate / release). If an app has no workflow for a stage, it
  simply doesn't ship at that stage — validation reports that as an
  informational skip for that app, not a failure.
- **Per-app versioning.** Marketing version and build number are tracked
  **independently per app** — each app's build number must climb past *that ASC
  app's* own latest build (App Store Connect tracks build numbers per app).
- Scope any phase to one app with `--app "<name|appId|bundleId|scheme>"`.

## Phases at a glance

The skill is organized by **phase**, not as a linear script. Pick the phase that
matches the current state. Run the validation phase first whenever you're unsure.

| Phase | When | Outcome |
|---|---|---|
| **0. Validate CI** | First time / before any release work | Confirms Xcode Cloud + GitHub Actions are wired correctly. |
| **A. Land development → main (ship TestFlight)** | A development cycle has accumulated changes ready for beta | PR opened, CI clears, PR merged. `main` advances and Xcode Cloud auto-ships the build to TestFlight. |
| **B. Promote to App Store** | A TestFlight build has passed QA and is ready for production | The `main` commit is tagged `v<version>-rc.<k>` and that tag is merged into the standing `release/<n>` branch; the merge triggers the App Store archive + upload. |
| **C. Re-roll a candidate** | App Review or final QA rejected the current candidate | A fix lands on `main` (→ TestFlight), then a fresh `v<version>-rc.<k+1>` tag carries it into the same `release/<n>`. |
| **D. Submit & finalize** | The App Store build is processed and ready | Drive App Review submission, tag `v<version>` on the accepted `release/<n>` commit, close out. |
| **E. Hotfix** | A bug surfaced in a shipped version that can't wait | Hotfix branch off `v<version>`, compressed B→D. |

---

## Phase 0: Validate CI

**Run this first.** It runs individual checks that verify GitHub Actions +
Xcode Cloud are wired correctly, and that recent triggers actually fired.
Without this, the shipping mechanism is unverified.

```bash
# Validates every app declared in .asc.json apps[] (loops them automatically):
~/.claude/skills/ship-app/validate-ci.sh
# Scope to one app (by name / appId / bundleId / scheme):
~/.claude/skills/ship-app/validate-ci.sh --app "MyApp macOS"
```

Each check is a standalone script in [`checks/`](checks/) that exits `0` (pass) /
`1` (fail) / `2` (skip — precondition missing). The orchestrator runs them in lex
order and prints a summary table.

### Single-check debugging

When the orchestrator reports a failure, re-run that one check directly with
`--verbose` to see raw output (e.g., dumped workflow JSON):

```bash
~/.claude/skills/ship-app/checks/12-xcc-testflight-workflow.sh --app MyApp --verbose
```

Or filter the orchestrator:

```bash
~/.claude/skills/ship-app/validate-ci.sh --only 12,13,14 --verbose
```

### The checks

| # | Check | What it verifies |
|---|---|---|
| 01 | `git-repo` | Inside a git repo |
| 02 | `github-remote` | `origin` is github.com |
| 03 | `tooling` | `gh`, `asc`, `jq` on PATH |
| 04 | `gh-auth` | `gh` authenticated |
| 05 | `asc-auth` | `asc doctor` passes |
| 06 | `app-id` | At least one app resolvable; lists every app from `.asc.json apps[]` (or `--app`/`ASC_APP_ID`/`.app`) |
| 07 | `branch-development` | `origin/development` exists |
| 08 | `branch-main` | `origin/main` exists |
| 09 | `gha-macos-test-gate` | GitHub Actions runs macOS unit/UI tests on PR → main (required) |
| 10 | `gha-ios-test-gate` *(optional)* | GitHub Actions iOS test gate on PR → main; SKIPs if absent (some repos can't run iOS sim tests reliably on CI). Xcode Cloud is **not** a substitute — it runs no tests |
| 11 | `gha-last-pr-passed` | Most recent merged `development → main` PR had no failed checks |
| 12 | `xcc-testflight-workflow` | **Per app:** Xcode Cloud workflow with a **branch** start condition on `main` (→ TestFlight). ≥1 app required |
| 13 | `xcc-candidate-workflow` | **Per app:** Xcode Cloud workflow with a **tag** start condition matching `v*-rc.*` (RC release gate) |
| 14 | `xcc-appstore-workflow` | **Per app:** Xcode Cloud workflow with a **branch** start condition on `release/*` (→ App Store) |
| 15 | `xcc-pr-gate-workflow` *(optional)* | **Per app:** Xcode Cloud **pull-request** workflow on `main` — a *build* gate only, never a test gate |
| 16 | `xcc-recent-main-run` | **Per app:** latest commit on `main` has a corresponding TestFlight build run |
| 17 | `xcc-recent-release-run` | **Per app:** latest `release/*` branch or `v*-rc.*` tag (if any) has a corresponding build run |
| 18 | `tf-build-from-main-distributed` | **Per app:** latest main-sourced build reached TestFlight (attached to a beta group) |
| 19 | `appstore-build-from-release` | **Per app:** latest `release/*` build (if any) produced an App Store Connect version/build |
| 20 | `gha-candidate-test-gate` *(optional)* | GitHub Actions runs tests on the `v*-rc.*` tag push (the App Store promotion gate); SKIPs if absent — the RC tag points at `main` code already cleared by the dev → main test gate (check 09) |
| 21 | `gha-release-tag-gate` *(optional)* | GitHub Actions runs tests on a `v*` tag push / release event; SKIPs if absent |

### Known fragile checks (debug-as-you-go)

- **18** (build → beta-group attachment): the `asc` subcommand to list beta
  groups for a build is tried in several forms. If all fail, the check SKIPs.
  Refine the command list as needed.
- **19** (release → App Store): depends on an `appStoreVersions`/builds relation
  for the release-sourced build. SKIPs when no `release/*` branch exists yet.
- **16, 17** (commit-to-run matching): depends on Xcode Cloud populating
  `sourceCommit.commitSha` in build-run metadata. Falls back to branch-name match
  if the SHA path is empty.

### Phase 0 contract

The skill **refuses to run phases B/C/D** if `validate-ci.sh` has not returned
exit 0 in the current session. Run it. Read the summary. Fix or document each
failure before proceeding. (Phase A — shipping to TestFlight — is the routine
development cycle and only needs checks 01–11 green.)

---

## Phase A: Land `development → main` (ship to TestFlight)

Routine: take whatever's accumulated on `development` and merge it to `main`
through a PR that gets the full CI cycle. **The merge to `main` is the TestFlight
ship** — Xcode Cloud's `MAIN => TESTFLIGHT` workflow builds and uploads
automatically.

### A.1 — Open / find the PR

```bash
gh pr list --base main --head development --json number,title,isDraft,state
```

If none exists, create one:

```bash
gh pr create --base main --head development \
  --title "Development → Main" \
  --body "Accumulating changes for the next beta build."
```

### A.2 — Update PR title and body from the diff

This repo merges `development → main` with **merge commits** (not squash), so the
PR's commit history is preserved on `main`. Give the PR a clear, themed title.

```bash
LAST_RELEASE_TAG=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
git log "${LAST_RELEASE_TAG:-origin/main}..origin/development" --pretty=format:'- %s'
git diff "${LAST_RELEASE_TAG:-origin/main}...origin/development" --stat
```

Edit the PR with a one-line title (`Merge development: <theme>`) and a
categorized body (Features / Fixes / Tests / Docs).

> **Match the repo's merge style.** Inspect recent history
> (`git log origin/main -5`). If past `development → main` PRs are merge commits
> (`Merge pull request #N`), use `--merge`. Only use `--squash` if that's the
> established convention.

### A.3 — Wait for CI

The required gates must all pass (reference: Vinetas):

```bash
gh pr checks "$PR_NUMBER" --watch --interval 30
```

This covers the **GitHub Actions test gates** (`Test macOS`, `UI Tests` — the
authoritative tests, on Apple Silicon) **and** the Xcode Cloud
`DEVELOPMENT => MAIN` *build* gate (compile/archive only, no tests). If any
fails, **stop** and surface the failure. Do not merge.

### A.4 — Merge

```bash
gh pr merge "$PR_NUMBER" --merge --delete-branch=false   # match repo convention
git checkout main && git pull origin main
```

Never delete `development` — it's long-lived.

### A.5 — Confirm Xcode Cloud shipped each app to TestFlight

The merge commit on `main` triggers each app's `MAIN => TESTFLIGHT` workflow
automatically. Confirm, **for every app that ships to TestFlight**, a build run
sourced from the merge commit appears. Loop the apps from `.asc.json`:

```bash
MERGE_SHA=$(git rev-parse origin/main)
for APP_ID in $(jq -r '(.apps // [{appId:(.app//.appId)}])[].appId' .asc.json); do
  echo "── app $APP_ID ──"
  TF_WF=$(asc xcode-cloud workflows list --app "$APP_ID" --output json \
    | jq -r '.data[] | select((.attributes.branchStartCondition // {}) | tostring | test("\"main\"";"i")) | .id' | head -1)
  [ -z "$TF_WF" ] && { echo "  (no main workflow — app not shipped to TestFlight)"; continue; }
  asc xcode-cloud build-runs list --workflow-id "$TF_WF" --limit 5 --sort "-number" --output json \
    | jq -r --arg sha "$MERGE_SHA" '.data[] | "  #\(.attributes.number) \(.attributes.executionProgress) sha=\(.attributes.sourceCommit.commitSha[0:9])"'
done
```

A run sourced from the merge commit SHA should appear for each shipping app
within a minute or two. If one doesn't, that app's branch start condition is
misconfigured — re-run check 12. (An app with no `main` workflow is intentionally
not shipped to TestFlight — that's Xcode Cloud gating what it builds.)

### A.6 — Wait for TestFlight processing (per app)

```bash
for APP in $(jq -r '(.apps // [{name:(.app//.appId)}])[].name' .asc.json); do
  echo "── $APP ──"; asc builds list --app "$APP" --limit 5
done
```

Each app's build `processingState` should reach `VALID`. **Watch for build-number
collisions** (invariant 5): if a `processingState` goes `INVALID` with a
duplicate build-number error, bump that app's `CURRENT_PROJECT_VERSION` and
re-ship. Notify beta testers once builds are `VALID`.

**Phase A is complete** when every shipping app's build is in TestFlight with
`processingState=VALID`.

---

## Phase B: Promote to App Store

A TestFlight build (from `main`) has passed QA and is ready for production. Tag
that exact `main` commit `v<version>-rc.<k>` and merge the tag into the standing
`release/<n>` branch. Merging into `release/<n>` triggers the App Store archive +
upload. **No version is bumped here** — `main` already carries the shipping
marketing version (it advanced at the `development → main` merge).

### B.1 — Confirm the version on `main` and pick the release number

The marketing version that ships is **whatever is already on `main`** — it does
not get decided or bumped in this phase. Read it back and confirm it's the
intended release version; if `main` still carries the previous version, the
version bump was never merged from `development` → **stop** and land that first
(Phase A). With **multiple apps**, read each app's version from its `xcconfig`
(or plist).

```bash
git checkout main && git pull origin main
git fetch --tags

# The version already on main (per app, from its xcconfig — adjust the key path):
VERSION=$(grep -E '^\s*MARKETING_VERSION' Config/Version.xcconfig | sed -E 's/.*=\s*//' | tr -d ' ')
echo "Version on main (ships as-is): $VERSION"

# Highest existing release sequence number
LAST_RELEASE_N=$(git branch -a | grep -oE 'release/[0-9]+' | grep -oE '[0-9]+$' | sort -n | tail -1)
echo "Last release branch: release/${LAST_RELEASE_N:-none}"
```

The **release number `<n>` is repo-wide** (one release branch carries all apps):
- If this release's `release/<n>` already exists, reuse it.
- Otherwise `<n> = LAST_RELEASE_N + 1` (first release ever → `release/1`).

```bash
RELEASE_N=1            # the release sequence number (repo-wide)
RELEASE_BRANCH="release/$RELEASE_N"
```

### B.2 — Ensure the `release/<n>` branch exists (off `main`)

The RC tag merges *into* this branch, so it must exist first. The cleanest first
cut is to branch it **at the RC tag** (B.3) — but if you create it ahead of time,
branch it from `main`:

```bash
git checkout main && git pull origin main
if ! git ls-remote --exit-code origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
  git checkout -b "$RELEASE_BRANCH"
  git push -u origin "$RELEASE_BRANCH"
  git checkout main
fi
```

### B.3 — Tag the release candidate on `main`

`<k>` is the RC counter **for this version**, starting at `1` and incrementing on
each re-roll of the *same* version (`v1.1.0-rc.1`, `v1.1.0-rc.2`, …). It resets to
`1` for the next version. The tag is placed on the current `main` tip — the exact
commit that passed TestFlight QA. **Nothing is bumped**; this is a marker, not a
commit.

```bash
git checkout main && git pull origin main

# next RC counter for THIS version
LAST_K=$(git tag --list "v${VERSION}-rc.*" | sed -E "s/.*-rc\.//" | sort -n | tail -1)
K=$(( ${LAST_K:-0} + 1 ))
RC_TAG="v${VERSION}-rc.${K}"

git tag -a "$RC_TAG" -m "Release candidate $K for $VERSION → $RELEASE_BRANCH"
git push origin "$RC_TAG"
```

Pushing the `v*-rc.*` tag triggers each app's `RC => RELEASE` workflow (build +
archive — a gate, not an upload; Xcode Cloud tag start condition `v*-rc.*`).
Confirm they ran clean before merging into the release branch. Tests are **not**
run here — they ran in GitHub CI on the `development → main` PR that produced this
commit.

> **Build numbers.** The RC tag does not touch build numbers. Each app's build
> number must still climb past *that ASC app's* own latest build (hard guard 3) —
> arrange this either via **Xcode Cloud's automatic build-number increment**
> (recommended), or by bumping `CURRENT_PROJECT_VERSION` on `development` so it
> lands on `main` with the `development → main` merge. Never bump it on the RC tag.

### B.4 — Merge the RC tag into `release/<n>` (triggers the App Store upload)

You cannot open a GitHub PR from a tag, and the test gating already happened at
the `development → main` merge — so the RC tag is merged into `release/<n>`
**directly** by the release manager. (This is why `release/*` branch protection
must allow the release manager to push this merge — see the branch-protection
note in `DEVELOPMENT_PATTERN.md`; the App Store gate is Xcode Cloud on
`release/*`, not a GitHub PR.)

```bash
# First release for this release/<n>: branch it at the RC tag.
if ! git ls-remote --exit-code origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
  git checkout -b "$RELEASE_BRANCH" "$RC_TAG"
  git push -u origin "$RELEASE_BRANCH"
else
  # Re-roll / subsequent RC: merge the new tag into the existing release branch.
  git checkout "$RELEASE_BRANCH" && git pull origin "$RELEASE_BRANCH"
  git merge --no-ff "$RC_TAG" -m "Merge $RC_TAG into $RELEASE_BRANCH"
  git push origin "$RELEASE_BRANCH"
fi
```

### B.5 — Confirm the App Store upload (per app)

Landing the RC tag on `release/<n>` triggers each shipping app's
`RELEASE => APP STORE` workflow (archive + upload to App Store Connect). Confirm
and wait, **per app**:

```bash
jq -c '(.apps // [{name:(.app//.appId), appId:(.app//.appId)}])[]' .asc.json \
| while IFS= read -r app; do
    NAME=$(echo "$app" | jq -r '.name'); APP_ID=$(echo "$app" | jq -r '.appId')
    echo "── $NAME ──"
    AS_WF=$(asc xcode-cloud workflows list --app "$APP_ID" --output json \
      | jq -r '.data[] | select((.attributes.branchStartCondition // {}) | tostring | test("release/";"i")) | .id' | head -1)
    [ -z "$AS_WF" ] && { echo "  (no release workflow — app not shipped to App Store)"; continue; }
    asc xcode-cloud build-runs list --workflow-id "$AS_WF" --limit 3 --sort "-number" --output json \
      | jq -r '.data[] | "  #\(.attributes.number) \(.attributes.executionProgress) \(.attributes.completionStatus // "—")"'
    asc builds list --app "$NAME" --limit 5
  done
```

If an optional GitHub CI test gate runs on the `v*-rc.*` tag push (check 20),
confirm it's green too; if it fails, **stop** → Phase C (re-roll). **Phase B is
complete** when every shipping app's `release/<n>` build is in App Store Connect
with `processingState=VALID`. Proceed to Phase D to submit.

---

## Phase C: Re-roll a candidate

App Review rejected the build, or final QA on the candidate found a bug. The fix
must reach production through a **fresh RC tag** — never by editing the release
branch directly or merging `development` into it.

### C.1 — Land the fix on `main` first (ships to TestFlight)

Fixes flow through the normal path so beta testers get them too:

```bash
# fix on development → PR → main  (Phase A), OR for an urgent isolated fix,
# land via a small PR per repo rules (no direct pushes to main).
```

The fix is now on `main` and on its way to TestFlight. The marketing version is
unchanged (a re-roll keeps the same `<version>`), so no version bump is involved.

### C.2 — Tag the next RC off the corrected `main`

```bash
git checkout main && git pull origin main
VERSION=$(grep -E '^\s*MARKETING_VERSION' Config/Version.xcconfig | sed -E 's/.*=\s*//' | tr -d ' ')

LAST_K=$(git tag --list "v${VERSION}-rc.*" | sed -E "s/.*-rc\.//" | sort -n | tail -1)
K=$(( ${LAST_K:-0} + 1 ))          # next RC counter for this version
RC_TAG="v${VERSION}-rc.${K}"

git tag -a "$RC_TAG" -m "Release candidate $K re-roll for $VERSION → $RELEASE_BRANCH"
git push origin "$RC_TAG"
```

Pushing the tag re-fires the `RC => RELEASE` build gate. Build numbers still climb
per ASC app (via Xcode Cloud auto-increment, or the bump that already landed on
`main`) — see B.3.

### C.3 — Merge the new RC tag into the same `release/<n>`

Same as B.4–B.5, targeting the same `release/<n>` (the re-roll branch already
exists, so it's the `git merge --no-ff "$RC_TAG"` path). Update the GitHub
issue(s) that motivated the re-roll: "Fixed in $RC_TAG → $RELEASE_BRANCH."

---

## Phase D: Submit & finalize

The `release/<n>` build is processed and `VALID` in App Store Connect.

### D.1 — Submit each app to App Review

Each app's `RELEASE => APP STORE` workflow uploads its build; it does not
necessarily submit it for review. Drive the submission **per app**:

> Run **`/asc-release-flow`** once per app (pass the app via its arg/`--app`) to
> drive the final submission — app-store-version creation, build attachment,
> metadata validation, and the submission API call. Use
> **`/asc-submission-health`** first for a per-app preflight.

### D.2 — Tag the accepted release commit

Once App Review accepts the builds (or once you've submitted and are confident),
tag the `release/<n>` tip with the **final** clean-semver tag `v<version>` (the
RC tags `v<version>-rc.<k>` remain as history). **No merge-back to `main`** — the
shipping version is already on `main` (it arrived via `development → main`), and
`release/<n>` carries only release bookkeeping (the RC-tag merge commits), no
unique product code. After the release ships, bump `development` to the **next**
version so `development` again leads `main`.

```bash
git fetch origin "$RELEASE_BRANCH"
RELEASE_SHA=$(git rev-parse "origin/$RELEASE_BRANCH")
```

- **Apps shipping in lockstep (same version):** one clean-semver tag.

  ```bash
  VERSION="1.0.0"
  case "$VERSION" in *-*) echo "ABORT: tag must be clean semver"; exit 1 ;; esac
  git tag -a "v$VERSION" "$RELEASE_SHA" -m "Release v$VERSION (shipped from $RELEASE_BRANCH)"
  git push origin "v$VERSION"
  ```

- **Apps at divergent versions:** tag **per app** so each version is recorded,
  using the app's scheme as a prefix:

  ```bash
  # e.g. MyApp-iOS-v1.2.0, MyApp-macOS-v1.1.0 — one tag per app at its own version
  git tag -a "MyApp-iOS-v1.2.0"   "$RELEASE_SHA" -m "Release MyApp iOS 1.2.0 from $RELEASE_BRANCH"
  git tag -a "MyApp-macOS-v1.1.0" "$RELEASE_SHA" -m "Release MyApp macOS 1.1.0 from $RELEASE_BRANCH"
  git push origin --tags
  ```

### D.3 — Close out

- Close the `Release <version>` GitHub milestone if one was opened for QA.
- Leave `release/<n>` in place (it's the standing branch for this release).
- Report (see D.4).

### D.4 — Summary report

Report (**per app**, plus the shared facts):
- The RC tag (`v<version>-rc.<k>`) that shipped this release
- For each app: released marketing version + App Store Connect build number that shipped
- The tag(s) created (`v<version>` for lockstep, or per-app `<scheme>-v<version>`) + any GitHub release URLs
- Per-app App Store Connect submission ID
- Apps in the repo that were **not** shipped this cycle (no Xcode Cloud workflow for the stage) — call these out so coverage is explicit
- Open follow-ups (e.g., deferred QA issues)

---

## Phase E: Hotfix

A bug surfaced in a shipped version (`v1.0.0`) and can't wait for the next
planned release. See [`references/qa-process.md#hotfixes`](references/qa-process.md)
for the procedure — branch from the `v<version>` tag, land the fix, and run a
compressed B→D against a new patch version (e.g. `v1.0.1`): the fix reaches `main`
(carrying the patched version), gets tagged `v1.0.1-rc.<k>`, and that tag merges
into the next `release/<n>`.

---

## Hard guards (NEVER violate)

1. **App Store uploads originate only from a `release/<n>` merge.** Never from
   `main`, a tag, or a laptop. (Invariant 3.)
2. **`MARKETING_VERSION` changes only at the `development → main` merge.**
   `development` carries the **next** version; `main` carries the **current
   shipping** version. The RC tag and the `release/<n>` merge never bump it — they
   ship whatever is already on `main`. (Invariant 4; step B.1.)
3. **Build numbers are strictly monotonic _per ASC app_.** Each app's build
   climbs past its own latest build in App Store Connect, independently of the
   other apps — via Xcode Cloud auto-increment or a `CURRENT_PROJECT_VERSION`
   bump on `development`. (Invariant 5.)
4. **The release candidate is a tag on `main`, not a branch.** Format
   `v<version>-rc.<k>` (`<k>` per-version, starting at 1, resets each version).
   There are **no `candidate/*` branches.** (Steps B.3 / C.2.)
5. **Final release tags are clean semver**, placed on the accepted `release/<n>`
   commit — `v<version>` when apps ship in lockstep, else per-app
   `<scheme>-v<version>`. (Step D.2.)
6. **No manual upload to TestFlight or App Store.** Xcode Cloud owns distribution
   builds. (Invariant 6.)
7. **Xcode Cloud never gates on tests; GitHub CI does.** All test gating lives in
   GitHub CI — Xcode Cloud runners are Intel and can't run the Apple-Silicon
   suite. The `main` (development → main) test gate is **required**; the optional
   `v*-rc.*` tag and final-tag/release test gates are **optional** (the RC tag
   points at main code already tested at the dev → main gate). Xcode Cloud only
   builds/archives/uploads, and its workflow set per app decides what ships.
8. **No `development` merged into a `release/<n>` branch.** Fixes reach production
   via `main` → a fresh RC tag. (Phase C.)
9. **RC counters are per-version and monotonic within a version; never reused.**
10. **No force-pushing `main` or `release/*`.** Always commit forward. `release/*`
    branch protection must permit the release manager to push the RC-tag merge
    (there is no PR from a tag); the App Store gate is Xcode Cloud on `release/*`.
11. **Phase 0 must pass before B/C/D.** Run `validate-ci.sh` and confirm exit 0.

## Failure handling

When a step fails: stop, surface the exact failure (command + output), and
propose a fix. Do not proceed past a failed CI check, a missing Xcode Cloud run,
or an unsigned/invalid build.

In unattended mode (called from another orchestrator): exit non-zero on any guard
violation or CI failure. Do not prompt.

## Dependencies

This skill orchestrates and calls others as needed:
- `/asc-release-flow` — App Store submission mechanics (Phase D.1)
- `/asc-submission-health` — preflight checks before submission
- `/asc-build-lifecycle` — locate builds, wait on processing
- `/asc-testflight-orchestration` — distribute TestFlight builds to tester groups
- `/organize-agent-docs` — at Phase D close-out, normalize repo docs
