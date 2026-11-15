---
type: skill
name: branch-hygiene
description: Post-release branch hygiene for any repo with a long-lived `development` → `main` pair. Syncs `development` onto `main` and marks the next development cycle (libraries get `X.Y.Z-dev`, with `Package.swift` left remote-only; apps get every `MARKETING_VERSION` bumped so `development` leads `main` again), all through a PR into `development` (never a direct or force push), then opens the draft `Development → Main` PR that collects the next cycle's work. Runs as the final step of `/ship-swift-library` and `/ship-app`, and standalone with `--sync-only` as a preflight whenever `development` has drifted behind `main`. Use when asked to "sync development with main", "start the next dev cycle", "open the next-cycle PR", "rebase development after the release", or "clean up the branches after shipping".
allowed-tools: Bash, Read, Grep, Glob, Edit, Skill
dependencies: []
---

# Branch Hygiene

Every ship cycle ends the same way, whether the thing shipped is a Swift library
or an App Store app: `main` has moved, `development` has to catch up, the next
cycle has to be marked in source, and a draft PR has to be waiting to collect the
next cycle's work. This skill owns that tail so `/ship-swift-library` and
`/ship-app` end identically.

**Three outcomes, always in this order:**

1. **`development` contains `main`'s tip.** `git merge-base --is-ancestor origin/main origin/development` passes.
2. **`development` leads `main` by exactly one "next cycle" commit.** For a library that is the `X.Y.Z-dev` stamp (`Package.swift` stays remote-only; the sibling pattern is retired); for an app it is the `MARKETING_VERSION` bump to the next version. Either way the branch is never bit-identical to `main`.
3. **A draft `Development → Main` PR is open.** It is the landing target for the next cycle. Draft means "not ready" — the next ship cycle marks it ready right before merging.

## Arguments

```
/branch-hygiene [<released-version>] [--pr <n>] [--next patch|minor|major|X.Y.Z] [--sync-only] [--unattended]
```

| Argument | Meaning |
|---|---|
| `<released-version>` | The clean semver that just shipped (`1.4.3`). Defaults to the newest `v*` tag reachable from `origin/main`. |
| `--pr <n>` | The `development → main` PR that was just merged. Reported for traceability. Defaults to the most recently merged `development → main` PR. |
| `--next` | **Apps only.** Which component of `MARKETING_VERSION` to advance on `development`. Default `patch`. Ignored for libraries, whose next version is chosen at the *next* ship, not now. |
| `--sync-only` | Stop after outcome 1. This is the preflight mode `/ship-swift-library` Step 0 uses when `development` has drifted behind `main`. |
| `--unattended` | Never prompt. Also implied when `UNATTENDED=1` is in the environment (set by the ship skills). Any ambiguity is an abort with a non-zero exit, never a question. |

```bash
RELEASED=""; PR_NUMBER=""; NEXT_BUMP="patch"; SYNC_ONLY=0
UNATTENDED="${UNATTENDED:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) PR_NUMBER="$2"; shift 2 ;;
    --next) NEXT_BUMP="$2"; shift 2 ;;
    --sync-only) SYNC_ONLY=1; shift ;;
    --unattended) UNATTENDED=1; shift ;;
    [0-9]*.[0-9]*.[0-9]*) RELEASED="$1"; shift ;;
    *) echo "ABORT: unrecognized argument '$1'"; exit 1 ;;
  esac
done
export UNATTENDED
```

## Step 0: Classify the repo and gate

```bash
git fetch origin --tags --prune -q

git ls-remote --heads origin development | grep -q development \
  || { echo "ABORT: no development branch — nothing to sync. Main-only repos do not use this skill."; exit 1; }
git ls-remote --heads origin main | grep -q main \
  || { echo "ABORT: no main branch."; exit 1; }

# App beats library: an app repo that also vends a library ships as an app.
if ls -d *.xcodeproj *.xcworkspace >/dev/null 2>&1 || [ -f .asc.json ]; then
  KIND=app
elif [ -f Package.swift ]; then
  KIND=library
else
  echo "ABORT: neither Package.swift nor an Xcode project at the repo root."; exit 1
fi
echo "Repo kind: ${KIND}"

[ -z "$(git status --porcelain)" ] || { echo "ABORT: working tree is dirty."; exit 1; }

# Released version: argument, else newest clean v-tag on main.
if [ -z "$RELEASED" ]; then
  RELEASED=$(git tag --merged origin/main --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
  RELEASED="${RELEASED#v}"
fi
case "$RELEASED" in
  [0-9]*.[0-9]*.[0-9]*) echo "Released version: ${RELEASED}" ;;
  *) [ "$SYNC_ONLY" = 1 ] || { echo "ABORT: could not determine the released version; pass it explicitly."; exit 1; } ;;
esac

# The PR that was just merged (reported in Step 4).
if [ -z "$PR_NUMBER" ]; then
  PR_NUMBER=$(gh pr list --base main --head development --state merged --limit 1 --json number --jq '.[0].number')
fi
echo "Last merged development → main PR: #${PR_NUMBER:-<none>}"
```

Use the ship skill's own variables when called from one: `/ship-swift-library` passes `$NEW_VERSION` and `$PR_NUMBER`; `/ship-app` passes the version on `main`.

## Steps 1–2: Sync and mark the next cycle on a chore branch, land it by PR **[ref]**

**Never push to `development` and never force-push it.** Both outcomes 1 and 2 are built on one `chore/next-cycle-v<released>` branch, and that branch reaches `development` through a PR opened by `/create-pull-request`. Branch protection gates the merge exactly as it does for any feature PR. Admin bypass, protection toggling, backup branches and `reset --hard` are all gone from this skill.

```bash
git checkout development && git pull --ff-only origin development
if [ "$SYNC_ONLY" = 1 ]; then
  CHORE_BRANCH="chore/sync-main-$(git rev-parse --short origin/main)"
else
  CHORE_BRANCH="chore/next-cycle-v${RELEASED}"
fi
git checkout -b "$CHORE_BRANCH"
```

### Step 1: Merge `main` into the chore branch

```bash
if git merge-base --is-ancestor origin/main HEAD; then
  echo "Sync: none — development already contains main's tip."
  SYNCED=0
else
  git merge origin/main --no-edit || echo "CONFLICTS — resolve per references/sync-development.md, then git commit --no-edit"
  SYNCED=1
fi
```

The release PR merged with `--merge` (both ship skills now use merge commits), so this is an ordinary merge, usually conflict-free. A repo whose last release was **squash-merged** (the old `/ship-swift-library` convention) conflicts here on the version files. **Read `references/sync-development.md`** for how to resolve that one-time case without rewriting history.

If `--sync-only`, skip Step 2. If nothing needed syncing (`SYNCED=0`) either, there is nothing to PR: report "already in sync" and stop.

### Step 2: Commit the next-cycle marker **[ref]**

`development` is now at or just ahead of `main` on the chore branch. Put the one commit on it that says "this is the next cycle." It guarantees the draft PR in Step 3 has a non-empty diff, and it makes "release or dev snapshot?" answerable from source.

- **Library** — **read `references/library-dev-marker.md`.** Stamp every occurrence of the released version in source and docs as `X.Y.Z-dev`. **Do not** run `/toggle-sibling-libraries --to sibling`: `Package.swift` stays remote-only (`.upToNextMajor(from:)` pins) on every branch. One commit. The next ship cycle strips `-dev` and picks the actual next version then; this skill never decides it.

- **App** — **read `references/app-next-version.md`.** For every app declared in `.asc.json apps[]`, advance `MARKETING_VERSION` in that app's `xcconfig` (or plist) by `--next` (default `patch`). Build numbers are **not** touched. This is the doctrine's invariant 4: `development` carries the *next* version, `main` the *current shipping* one, and the version advances only at the `development → main` merge. A `-dev` suffix is never used for apps — `MARKETING_VERSION` must stay clean numeric or App Store Connect rejects the build. One commit.

### Land the chore branch

Open the PR with `/create-pull-request`. Do not hand-roll `gh pr create`. That skill pushes the branch, routes `chore/*` to `development`, creates the PR ready for review, confirms CI started, and queues auto-merge.

```
/create-pull-request
```

Then wait for the merge. Step 3 needs the marker on `development`, or the draft PR has an empty diff.

```bash
CHORE_PR=$(gh pr list --head "$CHORE_BRANCH" --base development --state all --json number --jq '.[0].number')
test -n "$CHORE_PR" || { echo "ABORT: /create-pull-request opened no PR for ${CHORE_BRANCH}"; exit 1; }
gh pr checks "$CHORE_PR" --watch --fail-fast \
  || { echo "ABORT: chore PR #${CHORE_PR} checks failed. Fix on ${CHORE_BRANCH}; do not bypass."; exit 1; }
for i in $(seq 1 40); do
  STATE=$(gh pr view "$CHORE_PR" --json state --jq '.state')
  [ "$STATE" = MERGED ] && break
  [ "$STATE" = CLOSED ] && { echo "ABORT: chore PR #${CHORE_PR} closed without merging."; exit 1; }
  sleep 30
done
[ "$STATE" = MERGED ] || { echo "ABORT: chore PR #${CHORE_PR} is green but not merged — check mergeStateStatus/reviewDecision."; exit 1; }

git checkout development && git pull --ff-only origin development
git merge-base --is-ancestor origin/main origin/development \
  && echo "OK: development contains main's tip." \
  || { echo "ABORT: development still does not contain main."; exit 1; }
```

If `--sync-only`, report and stop here.

## Step 3: Open the draft next-cycle PR

```bash
EXISTING=$(gh pr list --base main --head development --state open --json number,isDraft --jq '.[0]')
if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
  echo "Open development → main PR already exists: $EXISTING — leaving it alone."
else
  if [ "$KIND" = library ]; then MARKER="marked \`${RELEASED}-dev\`"; else MARKER="bumped to the next marketing version"; fi
  gh pr create \
    --draft \
    --base main \
    --head development \
    --title "Development → Main" \
    --body "$(cat <<PRBODY
## Next Development Cycle

Development branch is synced with main after the v${RELEASED} release and ${MARKER}.

This PR is in draft mode and collects changes for the next release. The next ship cycle rewrites the title and body, marks it ready, and merges it.
PRBODY
)"
fi
gh pr list --base main --head development --json number,isDraft,title,url
```

An existing open PR is left as-is even if it is not a draft: someone made that choice deliberately, and flipping it back would discard it. Report its state instead.

## Step 4: Report

State, in this order, what happened at each outcome:

1. Whether a sync was needed, and whether it hit the one-time squash-legacy conflict.
2. The next-cycle marker: files changed, the commit SHA, and the chore PR that landed it.
3. The draft PR URL, or the existing PR that was found and left alone.

Report no-ops honestly. "Already in sync — nothing to merge" is a valid, complete result for outcome 1.

## Critical rules

1. **Never push to `development`, never force-push it, never toggle its protection.** Everything lands through the chore PR, opened with `/create-pull-request`.
2. **Never rewrite history.** No `reset --hard`, no cherry-pick replays, no force-push on any long-lived branch. Syncing is an ordinary `git merge origin/main` on the chore branch.
3. **Never leave `development` bit-identical to `main`.** The next-cycle commit is not optional. A zero-diff PR fails to create on some repos and silently no-ops on others.
4. **Libraries get `-dev`; apps get a real version bump.** Never put a `-dev` suffix in an app's `MARKETING_VERSION`, and never leave a library's `development` carrying the bare released version.
5. **Libraries never get the sibling pattern back.** Retired 2026-11-04. `Package.swift` stays remote-only on `development`; cross-library work goes through tagged releases.
6. **Build numbers are never touched here.** `CURRENT_PROJECT_VERSION` climbs via Xcode Cloud auto-increment or a deliberate bump on `development`; this skill does neither.
7. **The next-cycle PR is a draft.** `gh pr create --draft`, always. The ship skills mark it ready immediately before merging.
8. **Unattended means unattended.** With `UNATTENDED=1` or `--unattended`, every ambiguity is a non-zero exit with a stated blocker. `/package-iterator` depends on that.

## Who calls this

| Caller | When | Invocation |
|---|---|---|
| `/ship-swift-library` | Step 11, after the GitHub release is published | `/branch-hygiene $NEW_VERSION --pr $PR_NUMBER` |
| `/ship-swift-library` | Step 0 preflight, when `development` does not contain `main`'s tip | `/branch-hygiene --sync-only` |
| `/ship-app` | Phase D close-out, after the `v<version>` tag is pushed | `/branch-hygiene $VERSION --next patch` |
| You | Any time `development` has drifted behind `main` or the next-cycle PR is missing | `/branch-hygiene` |
