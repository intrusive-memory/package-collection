---
type: doc
---

# QA process for App Store promotions

This is the detail behind the "a TestFlight build has passed QA and is ready for
production" step in `DEVELOPMENT_PATTERN.md` / SKILL.md Phase B. The skill points
an agent here when deciding whether a build is ready to promote.

In this model the release candidate is a **tag on `main`** (`v<version>-rc.<k>`),
not a branch, and it **doesn't upload to TestFlight** (the `RC => RELEASE`
workflow is build-and-archive only). **TestFlight QA happens against `main`
builds** — the same code you then promote, unchanged, by tagging that `main`
commit `v<version>-rc.<k>` and merging the tag into `release/<n>`. When QA on a
`main` build passes, you tag that exact `main` commit.

Everything here applies **per app**: a repo may ship several App Store apps (e.g.
an iOS app and a macOS app), each its own ASC record, TestFlight builds, and
beta groups.

## Roles

| Role | Who | Responsibility |
|---|---|---|
| **Release captain** | Owner of the release | Owns the release end-to-end. Decides when a `main` build has passed QA, tags release candidates, triages bugs, drives submission. |
| **QA testers** | Internal (and external) TestFlight groups | Install the `main` build, run the test plan, file bugs against the release milestone. |
| **Fix authors** | Whoever owns the affected area | Land fixes on `development` → `main` (which re-ships to TestFlight). A fresh `v<version>-rc.<k+1>` tag then carries the corrected `main` forward. **Never** merge `development` into `release/<n>`. See SKILL.md Phase C. |

## TestFlight distribution

TestFlight builds come from **merges to `main`** — each shipping app's
`MAIN => TESTFLIGHT` workflow uploads its build automatically. There are no
separate RC builds. Distribute the `main` build to whichever beta groups run QA
for each app:

| Source | TF group(s) | Audience |
|---|---|---|
| Merge to `main` | Daily/internal group | Developers, dogfood testers, bleeding edge |
| Merge to `main` | QA group(s) | The dedicated testers who run the QA test plan before a promotion |

Promotion to the App Store is the *deliberate, separate* act of tagging a
QA-passed `main` build `v<version>-rc.<k>` and merging that tag into
`release/<n>` — it is never an accident of a merge.

**Verify the build appeared in TestFlight before declaring it "ready for QA"** —
Apple processing can fail silently. Per app:

```bash
asc builds list --app "$APP_NAME" --limit 5
```

The build's `processingState` should be `VALID` and at least one beta group
should be attached (`/asc-testflight-orchestration` distributes it).

## Bug-filing convention

Every release has a GitHub **milestone** named `Release <version>` (e.g.
`Release 1.4.0`). Bugs found during QA are filed as GitHub issues with:

- **Milestone**: `Release <version>`
- **Labels**: `bug`, `release-qa`, plus **per-app area labels** (`ios`, `macos`,
  the affected app/scheme, `auth`, etc.) so multi-app coverage is visible.
- **Title**: `[<app>] <one-line description>` — the prefix tells the captain
  which app surfaced it.
- **Body**: steps to reproduce, expected vs actual, TestFlight build number,
  app, device/OS.

The release is ready to promote when the milestone has **zero open `release-qa`
issues** at a blocking severity, for every app being shipped. (Cosmetic issues
can ride the next release; the captain decides.)

## Test plan

The release captain runs the QA test plan against the candidate `main` build
before promoting. The full per-app test plan lives in `docs/qa/test-plan.md`
(create it if missing) — the skill **does not** maintain it; it's app-specific.

Cover every app the repo ships, on its real surfaces:

- **iOS app** — at least one iPhone + one iPad on the **minimum supported OS**.
- **macOS app** — macOS on the minimum supported OS.

Escalate scope as a release nears: smoke-test early `main` builds, then run the
full regression on the exact `main` build you intend to promote — treat it as if
nothing prior was tested, because that build ships unchanged.

## Promotion checklist

The captain runs this before tagging the candidate (SKILL.md Phase B), **per
app**:

- [ ] All `release-qa` issues at blocking severity are closed for every app.
- [ ] Full regression passed on the exact `main` build to be promoted — iPhone +
      iPad for the iOS app, macOS for the macOS app — on the minimum supported OS.
- [ ] App Store metadata finalized per app (`asc metadata pull` shows the
      intended release notes / what's new in every locale).
- [ ] Screenshots uploaded for each app's current marketing version.
- [ ] Subscription / IAP changes (if any) are `Ready to Submit` per app.
- [ ] No open `release-qa` issue lacks a "won't fix this release" label + captain
      sign-off.

When the checklist clears, promote: tag the QA-passed `main` commit
`v<version>-rc.<k>` (no bump — the version is already on `main`) and merge that
tag into `release/<n>`. See SKILL.md Phase B.

## After App Store submission

The release captain:

1. Confirms each app's `release/<n>` build reached App Store Connect and was
   submitted (`/asc-release-flow` per app).
2. Tags the accepted `release/<n>` commit — `v<version>` if apps shipped in
   lockstep, else per-app `<scheme>-v<version>` (SKILL.md D.2).
3. **Does not merge `release/<n>` back into `main`** (invariant 8). The shipping
   version is already on `main` (it arrived via `development → main`), and
   `release/<n>` holds only RC-merge bookkeeping — there is nothing to forward-port.
   After the release ships, bump `development` to the **next** version.
4. Closes the `Release <version>` milestone.
5. Leaves `release/<n>` in place — it's the standing branch for this release and
   the base for any hotfix.

## Hotfixes

A hotfix against an already-shipped release branches from its release tag and
runs a compressed Phase B→D against a new patch version:

```bash
git checkout -b hotfix/<version> "v<old-version>"   # or <scheme>-v<old-version>
# land the fix on main (carrying the patched version), then tag it
# v<patch-version>-rc.<k> and merge that tag into the next release/<n+1>,
# tagging the final v<patch-version> once accepted.
```

A hotfix is a tiny one-candidate release. The same skill phases apply, compressed
— the fix still flows through `main` first (and thus TestFlight) when feasible,
then a fresh `v<version>-rc.<k>` tag carries it to the App Store.
