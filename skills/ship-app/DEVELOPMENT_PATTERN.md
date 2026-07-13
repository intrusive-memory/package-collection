---
type: doc
---

# Ship-App Development Pattern

The doctrine document for how iOS/macOS apps ship to Apple's App Store from this
repo model. The `SKILL.md` orchestrates the mechanics; this document defines the
**invariants** that all of that mechanics serves.

If anything in `SKILL.md` contradicts this document, **this document wins** and
`SKILL.md` is wrong.

This pattern is for **Swift apps distributed through TestFlight and the App
Store via Xcode Cloud**. Xcode Cloud owns every distribution build; the branch a
commit lands on is what selects the destination.

**One repo, one or many apps.** A single repo may ship several App Store apps at
once — e.g. an iOS app and a macOS app, each its own App Store Connect record,
bundle id, and scheme. Everything below applies **per app**: each app has its
own Xcode Cloud workflow set, its own marketing version, and its own
(independently monotonic) build-number history. Apps are declared in
`.asc.json apps[]` (a single legacy `.app`/`.appId` is treated as a one-app
repo). **Xcode Cloud's workflow configuration is the authority for what ships:**
an app with no workflow for a given stage simply isn't shipped at that stage.

**Tests run in GitHub CI, never Xcode Cloud.** Xcode Cloud only
builds/archives/uploads. All test gating lives in GitHub Actions on Apple
Silicon (`runs-on: macos-26`+), because Xcode Cloud runners are Intel and parts
of the suite are Apple-Silicon-specific (MLX/Metal/arm64). GitHub CI gates the
merge, tag, and release process.

---

## The core idea: the ref you land on picks the destination

There are **no manual archive/upload** steps. Distribution is a function of *which
ref the code is on*, and Xcode Cloud workflows watch those refs — branches for
TestFlight and App Store, and a **tag** for the release-candidate gate:

```
merge to  main                   →  Xcode Cloud: build + archive → TESTFLIGHT (beta)
push tag  v<version>-rc.<k>       →  Xcode Cloud: build + archive  (release gate, no upload)
merge to  release/<n>            →  Xcode Cloud: archive          → APP STORE  (production)
```

So **getting code onto `main` ships it to TestFlight.** Promoting that same code
to the App Store means **tagging the `main` commit `v<version>-rc.<k>`** and
**merging that tag into the standing `release/<n>` branch.** The release candidate
is a *tag on `main`*, not a branch.

---

## Three branches + an RC tag

| Ref | Role | Lifetime |
|---|---|---|
| `development` | Daily integration trunk. All in-flight feature work merges here. Carries the **next** marketing version being worked on. | Long-lived. |
| `main` | Stable trunk **and the TestFlight/beta stage**. Carries the **current shipping** marketing version. Merging here uploads a beta build. | Long-lived. |
| tag `v<version>-rc.<k>` | **Release candidate.** A *tag* on the `main` commit being promoted. Pushing it fires the release-gate build; merging it into `release/<n>` ships to the App Store. Iterated (`-rc.1`, `-rc.2`, …) until a candidate is accepted. | A tag (permanent history), not a branch. |
| `release/<n>` | **Production / App Store stage.** One standing branch per shipped release, `<n>` = release sequence number (`release/1` ships the first version, `release/2` the next, …). Merging an RC tag into it uploads to App Store Connect. | Long-lived per release. |

### Numbering

- `release/<n>` — **release sequence integer**, `1, 2, 3, …`. One branch per
  App Store release. It does **not** encode the marketing version; the marketing
  version lives in the project file. `release/1` shipped `1.0.0`; `release/2`
  ships whatever the next release's marketing version is.
- `v<version>-rc.<k>` — the **RC counter `<k>`** is per-version, starting at `1`
  and incrementing on each re-roll of the *same* version (`v1.1.0-rc.1`,
  `v1.1.0-rc.2`, …). It **resets to 1** for the next version (`v1.2.0-rc.1`).
  Multiple RC tags feed one release: `v1.1.0-rc.1..3` all merge into `release/1`.

### Why `main` is the TestFlight stage (and the RC is a tag, not a branch)

Every `development → main` merge is a beta build. There is no separate
release-candidate branch — TestFlight is continuous: the moment code is stable
enough for `main`, beta testers get it. The App Store gate is a *deliberate,
separate* promotion: you **tag** the exact `main` commit that passed QA
(`v<version>-rc.<k>`) and merge that tag into `release/<n>`. The candidate is a
tag rather than a branch because it carries **no unique work** — it's a pointer to
a `main` commit, so there's nothing to develop on it, only to promote. Production
shipping is therefore never an accident of a merge.

---

## Code flow

```
development ──┬── feature/* (PR-merged in)   [carries the NEXT marketing version]
              │
              ▼  [development → main PR gates:]
              ▼     • GitHub Actions: macOS unit/UI test gate  (required, Apple Silicon)
              ▼     • GitHub Actions: iOS unit/UI test gate    (optional)
              ▼     • Xcode Cloud: DEVELOPMENT => MAIN build-and-archive (build gate only, no tests)
              ●──────────────────────────────────────────────────────────► main
                the merge ADVANCES main's MARKETING_VERSION to the release version │
                          [Xcode Cloud: MAIN => TESTFLIGHT fires on push]   │
                          [build + archive + upload → TestFlight (beta)]    │
                                                                            │
                                          [App Store promotion declared]    │
                                                                            ▼
                          tag v<version>-rc.<k> on the main tip  (no bump — version already on main)
                                                                            │
                          push tag ─► Xcode Cloud RC => RELEASE
                                      (build + archive — gate only; tag condition v*-rc.*)
                                                                            │
                          merge tag v<version>-rc.<k> ──► release/<n>
                              [release manager pushes the merge; Xcode Cloud build is the gate]
                                                                            │
                          release/<n> ─► Xcode Cloud RELEASE => APP STORE
                                         (archive + upload → App Store Connect)
                                                                            │
                          [App Review rejects?] ─► fix on main, tag v<version>-rc.<k+1>, repeat
                                                                            │
                          [submitted & accepted] ─► tag v<version> on release/<n> tip
                                                    (no merge-back to main)
```

---

## Invariants

These are load-bearing. Violations break the model.

1. **`main` is append-only in spirit.** Code merged into `main` stays there
   until it's deliberately removed by a follow-up commit. No history rewriting.
2. **Merging to `main` is a TestFlight release.** Treat every `development → main`
   merge as a beta ship: it must be green and shippable, because Xcode Cloud will
   upload it to TestFlight automatically.
3. **App Store shipping only happens through `v<version>-rc.<k> → release/<n>`.**
   No App Store upload originates from `main`, from pushing the RC tag alone, or
   from a laptop. The only way to App Store Connect is merging an RC tag into a
   `release/<n>` branch.
4. **`MARKETING_VERSION` changes only at the `development → main` merge.**
   `development` always carries the **next** version being worked on; `main`
   always carries the **current shipping** version. The version advances when
   `development` merges to `main` — that is the *only* place it changes. The RC
   tag and the `release/<n>` merge never bump it; they ship whatever is on `main`.
   (Hard guard 2.)
5. **Build numbers are monotonic _per ASC app_.** Each app's TestFlight and App
   Store builds have a strictly increasing build number, climbing past *that
   app's* own latest build regardless of branch. App Store Connect rejects
   duplicates per app; apps do not share a build-number counter.
6. **Xcode Cloud is the canonical builder, and the authority for what ships.**
   Every TestFlight and App Store build comes from an Xcode Cloud workflow; we
   never `xcodebuild archive && asc builds upload` for distribution. The set of
   workflows configured per app decides which apps ship at which stage — an app
   without a stage's workflow simply isn't shipped there. (Local archives are
   fine for ad-hoc testing only.)
7. **Tests run in GitHub CI, never Xcode Cloud.** All test gating —
   `development → main` PRs plus the optional `v*-rc.*` tag and final-tag/release
   steps — lives in GitHub Actions on Apple-Silicon runners, because Xcode Cloud
   runners are Intel and the suite has Apple-Silicon-specific (MLX/Metal/arm64)
   tests. GitHub CI gates the merge, tag, and release. Xcode Cloud builds/archives
   /uploads only; its PR build is a *build* gate, not a test gate.
8. **RC tags merge *into* the release branch; nothing merges *out* of it back to
   `main`.** After a version ships, we tag the `release/<n>` tip and stop. The
   shipping version already lives on `main` (it arrived via `development → main`),
   and `release/<n>` holds only RC-merge bookkeeping — no unique product code to
   flow back.
9. **One active release branch advances at a time.** Don't run two `release/<n>`
   promotions concurrently. Hotfixes to an already-shipped version branch from
   its release tag (see Phase E).

---

## Tag formats

| Purpose | Format | Example | Created on |
|---|---|---|---|
| **Release candidate** | `v<version>-rc.<k>` | `v1.1.0-rc.1`, `v1.1.0-rc.2` | The `main` commit being promoted (the RC gate + release-merge source) |
| Shipped release (apps in lockstep) | `v<version>` | `v1.0.0`, `v1.1.0` | The `release/<n>` commit that App Review accepted |
| Shipped release (apps at divergent versions) | `<scheme>-v<version>` | `MyApp-iOS-v1.2.0`, `MyApp-macOS-v1.1.0` | The same `release/<n>` commit, one tag per app |

The **RC tag** `v<version>-rc.<k>` is the release candidate: `<k>` starts at `1`
and increments per re-roll of the same version, resetting to `1` for the next
version. Pushing it fires the Xcode Cloud RC build gate (tag start condition
`v*-rc.*`); merging it into `release/<n>` ships to the App Store.

The **shipped-release tag** `v<version>` is clean semver (`MAJOR.MINOR.PATCH`, no
`-dev`, no pre-release suffix). When all apps in the repo ship the same version,
use a single `v<version>` tag; when they ship at different versions, tag **per
app** using the app's scheme as a prefix so every shipped version is recorded on
the accepted commit.

---

## Xcode Cloud workflows expected

Xcode Cloud only **builds, archives, and uploads** — it runs **no tests**. Each
shipping app has its **own set** of these workflows; an app missing a stage's
workflow simply isn't shipped at that stage (that's the gate on *what* builds).
The skill's validation checks verify these exist and are wired correctly, **per
app**. Workflow names can vary; checks match by **start-condition shape**, not by
name. (The Vinetas reference names are shown for orientation.)

| Convention | Reference name | Start condition | Action | Destination |
|---|---|---|---|---|
| PR build gate | `DEVELOPMENT => MAIN` | Pull request → `main` | Build + archive (no tests) | — (none) |
| TestFlight | `MAIN => TESTFLIGHT` | Branch push → `main` | Build + archive + upload | TestFlight (beta) |
| Release gate | `RC => RELEASE` | **Tag push** → `v*-rc.*` | Build + archive | — (gate only) |
| App Store | `RELEASE => APP STORE` | Branch push → `release/*` | Archive + upload | App Store Connect |

- Check 12 looks for each app's **TestFlight** workflow (branch condition `main`); ≥1 app required.
- Check 13 looks for each app's **Release gate** workflow (**tag** condition `v*-rc.*`).
- Check 14 looks for each app's **App Store** workflow (branch condition `release/*`).
- Check 15 looks for each app's **PR build gate** (pull-request condition on `main`) — informational, a *build* gate only (never a test gate).

---

## GitHub Actions workflows expected

**All test gating lives here, on Apple Silicon.** Xcode Cloud runners are Intel
and parts of the suite are Apple-Silicon-specific (MLX/Metal need real arm64
hardware), so GitHub Actions is the only place those tests run faithfully — and
GitHub CI is what gates the merge, tag, and release. The one **required** test
gate is into `main` (the development → main merge). Two further gates are
**optional**: on the `v*-rc.*` RC-tag push (the App Store promotion) and on the
final tag/release event — both optional because the RC tag points at `main` code
already cleared by the `main` gate.

| Trigger | Gate | Validates |
|---|---|---|
| `pull_request: branches: [main]` | **macOS unit/UI test gate** *(required)* | `runs-on: macos-26`+ (Apple Silicon) + `platform=macOS,arch=arm64` + `xcodebuild test` |
| `pull_request: branches: [main]` | **iOS unit/UI test gate** *(optional)* | `platform=iOS Simulator` destination + `xcodebuild test` |
| `push: tags: ['v*-rc*']` | **RC-tag test gate** *(optional)* | Full test suite on the App Store promotion candidate (Apple Silicon) — redundant with the `main` gate the RC tag already cleared |
| `push: tags: ['v*']` or `release:` | **tag/release test gate** *(optional)* | Test suite re-run as the release is finalized |
| `pull_request: branches: [development]` *(optional)* | Lighter pre-integration checks | — |

The iOS test gate is optional because some projects can't reliably run iOS
UI/simulator tests on CI runners (they hang); those projects gate on the
required macOS suite only. **Xcode Cloud is not a substitute for any of these —
it runs no tests.** Its per-app PR build catches compile/link breaks, nothing
more.

Check 09 looks for the macOS gate (required); check 10 looks for the iOS gate
and **SKIPs** when absent. Check 11 verifies the most-recent merged
`development → main` PR had its gates pass. Check 20 looks for the optional
`v*-rc.*` tag test gate and **SKIPs** when absent; check 21 looks for the optional
final-tag/release gate and **SKIPs** when absent.

### Required status checks (reference: Vinetas)

- **`main`**: `Test macOS`, `UI Tests` (GitHub Actions) + the Xcode Cloud
  `DEVELOPMENT => MAIN` *build* — strict, branch must be up to date.
- **`release/*`**: the Xcode Cloud `RELEASE => APP STORE` build is the gate. Since
  the RC is a **tag** (you can't open a PR from a tag), `release/*` protection must
  **allow the release manager to push the RC-tag merge directly** — e.g. a bypass
  allowance for the release manager, or "require PRs" left off for `release/*`. An
  optional GitHub Actions test suite on the `v*-rc.*` tag push (Apple Silicon) is
  usually omitted — the RC tag points at `main` code already cleared by the `main`
  test gate.

---

## QA process

See `references/qa-process.md` for the full procedure: tester groups, sign-off
criteria, bug-filing conventions (labels and milestones), and the App Store
submission gate. In this model, **TestFlight QA happens against `main` builds**,
and the App Store promotion is gated on that QA having passed.

---

## Discipline

The pattern depends on people behaving. The mechanism doesn't enforce these:

- **Keep `main` shippable.** Because every merge to `main` ships to TestFlight,
  don't merge half-finished work expecting to "fix it before release." There is
  no pre-release staging between `main` and TestFlight.
- **Don't merge `development` into a `release/<n>` branch.** The candidate is a
  tag on `main`, merged into the release branch. If a fix is needed, it lands on
  `development` → `main` first (and thus TestFlight), then a fresh
  `v<version>-rc.<k+1>` tag carries it forward — including for a release already
  in App Review.
- **One release branch advances at a time.** No overlapping App Store
  promotions.

---

## Anti-patterns (don't do these)

- **Uploading to the App Store from anything but a `release/<n>` merge.** Breaks
  invariant 3.
- **Creating a `candidate/*` branch, or bumping `MARKETING_VERSION` on a tag or
  the release branch.** The candidate is a *tag on `main`*; the version changes
  only at `development → main`. Breaks invariant 4.
- **Force-pushing `main`, a `v*` tag, or a `release/<n>` branch.** Breaks
  invariant 1 and confuses Xcode Cloud's ref-triggered runs. Always commit forward.
- **Building and uploading to TestFlight / App Store from a laptop.** Breaks
  invariant 6. Distribution builds are reproducible only when CI owns them.
- **Reusing a `v<version>-rc.<k>` tag** (moving or re-pushing it). RC tags are
  immutable; a re-roll gets the next `<k>`.
- **Merging a `release/<n>` branch back into `main`.** Breaks invariant 8.
