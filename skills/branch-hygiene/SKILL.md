---
type: skill
name: branch-hygiene
description: Post-release branch hygiene for any repo with a long-lived `development` → `main` pair. Syncs `development` onto `main` (detecting squash-merge phantoms vs. plain merge commits and picking the right procedure), marks the next development cycle (libraries get `X.Y.Z-dev` + the sibling `Package.swift` pattern restored; apps get every `MARKETING_VERSION` bumped so `development` leads `main` again), and opens the draft `Development → Main` PR that collects the next cycle's work. Runs as the final step of `/ship-swift-library` and `/ship-app`, and standalone with `--sync-only` as a preflight whenever `development` has drifted behind `main`. Use when asked to "sync development with main", "start the next dev cycle", "open the next-cycle PR", "rebase development after the release", or "clean up the branches after shipping".
allowed-tools: Bash, Read, Grep, Glob, Edit, Skill
dependencies:
  - toggle-sibling-libraries
---

# Branch Hygiene

Every ship cycle ends the same way, whether the thing shipped is a Swift library
or an App Store app: `main` has moved, `development` has to catch up, the next
cycle has to be marked in source, and a draft PR has to be waiting to collect the
next cycle's work. This skill owns that tail so `/ship-swift-library` and
`/ship-app` end identically.

**Three outcomes, always in this order:**

1. **`development` contains `main`'s tip.** `git merge-base --is-ancestor origin/main origin/development` passes, with no phantom commits left over from a squash merge.
2. **`development` leads `main` by exactly one "next cycle" commit.** For a library that is the `X.Y.Z-dev` stamp plus the sibling `Package.swift` pattern; for an app it is the `MARKETING_VERSION` bump to the next version. Either way the branch is never bit-identical to `main`.
3. **A draft `Development → Main` PR is open.** It is the landing target for the next cycle. Draft means "not ready" — the next ship cycle marks it ready right before merging.

## Arguments

```
/branch-hygiene [<released-version>] [--pr <n>] [--next patch|minor|major|X.Y.Z] [--sync-only] [--unattended]
```

| Argument | Meaning |
|---|---|
| `<released-version>` | The clean semver that just shipped (`1.4.3`). Defaults to the newest `v*` tag reachable from `origin/main`. |
| `--pr <n>` | The `development → main` PR that was just merged. Used to tell squash phantoms apart from genuinely new work. Defaults to the most recently merged `development → main` PR. |
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

# The PR whose commits were just merged. Needed to recognize squash phantoms.
if [ -z "$PR_NUMBER" ]; then
  PR_NUMBER=$(gh pr list --base main --head development --state merged --limit 1 --json number --jq '.[0].number')
fi
echo "Last merged development → main PR: #${PR_NUMBER:-<none>}"
```

Use the ship skill's own variables when called from one: `/ship-swift-library` passes `$NEW_VERSION` and `$PR_NUMBER`; `/ship-app` passes the version on `main`.

## Step 1: Sync `development` onto `main` **[ref]**

The right procedure depends on **how the last PR was merged**, not on which skill called this one:

| Last merge was… | `development` state | Procedure |
|---|---|---|
| Already in sync | `origin/main` is an ancestor of `origin/development` | Nothing. Move on. |
| A **merge commit** (`--merge`, the `/ship-app` convention) | The PR's head commit *is* in `main`'s history | `git merge origin/main` into `development`, push. Fast-forwards when `development` has nothing new. No force-push, no protection toggle. |
| A **squash** (`--squash`, the `/ship-swift-library` convention) | The PR's head commit is *not* in `main`'s history; `development` carries phantom commits whose content already landed | Back up, reset `development` to `origin/main`, cherry-pick only commits that are **not** in the merged PR, force-push (toggling protection only if the branch is protected). |

Detect it:

```bash
if git merge-base --is-ancestor origin/main origin/development; then
  SYNC=none
else
  HEAD_OID=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid' 2>/dev/null || true)
  if [ -n "$HEAD_OID" ] && git merge-base --is-ancestor "$HEAD_OID" origin/main; then
    SYNC=merge
  elif [ -z "$(git diff origin/main..origin/development --stat)" ]; then
    SYNC=squash      # no content diff but not an ancestor: phantoms only
  elif [ -n "$HEAD_OID" ]; then
    SYNC=squash      # phantoms plus genuinely new work; the reference separates them
  else
    echo "ABORT: development has diverged from main and no merged PR is known to classify the divergence."
    echo "       Pass --pr <n> for the PR that was last merged into main."
    exit 1
  fi
fi
echo "Sync procedure: ${SYNC}"
```

- `SYNC=merge`:

  ```bash
  git checkout development && git pull origin development
  git merge origin/main --no-edit      # fast-forward when possible
  git push origin development
  ```

- `SYNC=squash`: **read `references/sync-development.md`** and follow it. It covers the backup branch, protection detection (a 404 from the protection API is a normal answer), why `git cherry` cannot be trusted after a squash, the expected version-bump conflict when run as a preflight, and the byte-identical-tree check before force-pushing.

Verify, whichever path ran:

```bash
git fetch origin -q
git merge-base --is-ancestor origin/main origin/development \
  && echo "OK: development contains main's tip." \
  || { echo "ABORT: development still does not contain main."; exit 1; }
```

If `--sync-only`, report and stop here.

## Step 2: Mark the next development cycle **[ref]**

`development` is now at or just ahead of `main`. Put the one commit on it that says "this is the next cycle" — the commit that guarantees the draft PR in Step 3 has a non-empty diff and that makes "release or dev snapshot?" answerable from source.

- **Library** — **read `references/library-dev-marker.md`.** Stamp every occurrence of the released version in source and docs as `X.Y.Z-dev`, then run `/toggle-sibling-libraries --to sibling` so `Package.swift` routes `intrusive-memory/*` deps through `../<name>` checkouts again. One commit. The next ship cycle strips `-dev` and picks the actual next version then; this skill never decides it.

- **App** — **read `references/app-next-version.md`.** For every app declared in `.asc.json apps[]`, advance `MARKETING_VERSION` in that app's `xcconfig` (or plist) by `--next` (default `patch`). Build numbers are **not** touched. This is the doctrine's invariant 4: `development` carries the *next* version, `main` the *current shipping* one, and the version advances only at the `development → main` merge. A `-dev` suffix is never used for apps — `MARKETING_VERSION` must stay clean numeric or App Store Connect rejects the build. One commit.

Push the commit to `development`:

```bash
git push origin development
```

If the push is rejected because `development` requires pull requests, do not fight the protection: branch `chore/next-dev-cycle-${RELEASED}` from `development`, push it, open a PR **into `development`** titled `Start next development cycle after v${RELEASED}`, and say so in the report. Step 3 still runs; the draft PR will show the diff once that chore PR merges.

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

1. Sync procedure used (`none` / `merge` / `squash`), the backup branch name if one was pushed, and whether branch protection was toggled.
2. The next-cycle marker: files changed, the commit SHA, and whether it landed on `development` directly or via a chore PR.
3. The draft PR URL, or the existing PR that was found and left alone.

Report no-ops honestly. "Already in sync — nothing to merge" is a valid, complete result for outcome 1.

## Critical rules

1. **Never `git merge main` after a squash merge.** It leaves the squashed commits visible in the next PR (huge commit list, zero diff) and is exactly what produces a `CONFLICTING` release PR with no CI the following cycle. Detect the merge style; do not assume it.
2. **Never force-push `main`.** The only branch this skill rewrites is `development`, and only in the squash case, and only after pushing a backup branch.
3. **Never leave `development` bit-identical to `main`.** The next-cycle commit is not optional. A zero-diff PR fails to create on some repos and silently no-ops on others.
4. **Libraries get `-dev`; apps get a real version bump.** Never put a `-dev` suffix in an app's `MARKETING_VERSION`, and never leave a library's `development` carrying the bare released version.
5. **Libraries also get the sibling pattern back.** Shipping flipped `Package.swift` to remote-only; cross-library development is impossible until `/toggle-sibling-libraries --to sibling` runs.
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
