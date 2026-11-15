---
name: create-pull-request
description: Finalize the pull request for the current branch — find the existing (usually draft) PR, regenerate its title and body from the branch's commits, fix the base branch if it's wrong, and mark it ready for review. Falls back to creating a new PR only when none exists. Use this skill whenever the user asks to "create a PR", "open a PR", "make a pull request", "PR this", "send it up", "mark it ready", "ready for review", "finalize the PR", or any variation that implies promoting the current branch into review — including casual phrasings like "now PR it" or "go ahead and ship the PR". The skill picks the base branch using the project's tiered convention (mission/* → development, development → main, everything else → development), enforces standard safety checks (clean working tree, not on main, push first), moves the repo's GitHub Actions CI to the Xcode 27 runner (macOS 27 / iOS 27 / Swift 6.4) if it is behind and commits that before pushing, and writes a Summary + Test plan body from the commits on the branch. Prefer this skill over running `gh pr create` / `gh pr ready` directly so the routing and safety rules apply consistently.
allowed-tools: Bash, Read, Edit, AskUserQuestion
type: skill
---

# Create Pull Request

Finalizes the PR for the current branch. The expected steady state is that a **draft PR already exists** (created earlier by tooling or by hand); this skill's primary job is to bring that PR to ready-for-review with a clean, current title and body. Creating a brand-new PR is the fallback path, not the default.

## When to use

Trigger on any phrasing that means "finish the PR" or "open a PR":

- "create a PR", "open a PR", "make a pull request"
- "PR this", "PR it", "send it up", "ship the PR"
- "mark it ready", "ready for review", "finalize the PR", "promote the PR"
- "merge to main" / "promote to main" (when the branch is `development`)
- After a successful commit + push, when the user says "now PR it" or similar

Don't trigger when the user is asking *about* PRs (listing, reviewing, commenting on existing PRs) — that's plain `gh pr` work, not this skill.

## Mental model

The workflow this skill serves looks like:

1. Branch is cut, tooling (or a prior agent run) opens a **draft PR** immediately.
2. Commits accumulate on the branch.
3. When the user says "PR this", they almost always mean *finalize* — update the draft's metadata to reflect the current commits, then flip it ready.

So the skill always **looks for an existing PR first**. Creating a new one is the fallback. Don't ask the user which they meant — figure it out from the branch state.

## How base branch is chosen

The routing rule is intentionally one line of branching logic because the user's mental model is "mission branches stack onto development, development stacks onto main." Match that.

| Current branch                | Base branch  | Why                                                        |
|-------------------------------|--------------|------------------------------------------------------------|
| `development`                 | `main`       | The dev→main promotion gate.                               |
| Anything containing `mission` | `development`| Mission branches always land on development first.         |
| Anything else                 | `development`| Feature/fix/chore branches also stack onto development.    |
| `main` (or repo default)      | **STOP**     | Never open a PR from the default branch — refuse loudly.   |

The `mission` rule uses substring match (`*mission*`), not just prefix — names like `mission/quartermaster-reshuffle/1` and `chore/mission-cleanup` both qualify.

The repo's default branch is whatever `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` returns — usually `main`, occasionally `master`. Compute it, don't hardcode.

If the user's message names a base branch explicitly ("PR into staging", "open a PR against release/0.11"), honor that and skip the routing table. Auto-routing is a default for the common case, not a constraint.

## Pre-flight checks

Run in this order. If any fails, **stop** and report — don't paper over with `--force` or auto-stash.

1. **Inside a git repo.** `git rev-parse --is-inside-work-tree` returns true.
2. **Not on the default branch.** If `git branch --show-current` equals the repo default, stop: *"You're on `<default>` — switch to a feature/development branch first."*
3. **Working tree clean.** `git status --porcelain` is empty. If not, list the dirty files and stop: *"Working tree has uncommitted changes — commit or stash before finalizing the PR."*
4. **Has commits ahead of base.** After picking the base, confirm `git rev-list --count origin/<base>..HEAD` is > 0. If 0, stop: *"Branch has no commits ahead of `<base>` — nothing to PR."*

## Step 1 — Inspect state

Run in parallel:

```bash
git rev-parse --is-inside-work-tree
git status --porcelain
git branch --show-current
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
```

Then look for an existing PR for the current branch:

```bash
gh pr list --head "$CURRENT" --state open --json number,title,baseRefName,isDraft,url
```

If the list is non-empty: **finalize path** (Step 2). Otherwise: **create path** (Step 3). Either way, run the CI audit (Step 1b) first.

Edge case — multiple open PRs from the same branch: rare, but possible if the user manually opened one against a non-default base. Pick the one whose `baseRefName` matches the routed base. If none match, tell the user what you found and ask which to finalize rather than guessing.

## Step 1b — Audit CI for macOS 27 / iOS 27 / Swift 6.4

Runs on every invocation, before anything is pushed, so the PR's own CI run uses the current toolchain. The target is GitHub's **`xcode-27`** runner image: macOS 27, Xcode 27, iOS 27 simulator runtimes, Swift 6.4, Apple Silicon only. GitHub has **no `macos-27` label**: from Xcode 27 on, macOS images are named by Xcode version.

Scope is `.github/workflows/*.yml` and `*.yaml`. If the directory doesn't exist, skip this step and say so in the report.

### Find what's out of date

```bash
grep -nE 'runs-on:|macos-|xcode-select|setup-xcode|xcode-version|setup-swift|swift-version|OS=[0-9]' .github/workflows/*.y*ml
```

Also check `matrix:` blocks, since `runs-on: ${{ matrix.os }}` takes its runner from there.

### Rewrite rules

| Found | Change to |
|-------|-----------|
| `macos-<N>` or `macos-latest` (in `runs-on:` or a matrix value) | `xcode-27` |
| `macos-<N>-xlarge` | `xcode-27-xlarge` |
| `macos-<N>-large` (Intel) | **Stop and ask.** The Xcode 27 image has no Intel runner, so the job's architecture would change. |
| `sudo xcode-select -s /Applications/Xcode<anything>.app` that picks an older Xcode | Delete the step. The image's default Xcode is 27. |
| `maxim-lobanov/setup-xcode` (or similar) pinning Xcode < 27 | Delete the step. |
| `swift-actions/setup-swift` / `swift-version` < 6.4 on a macOS job | Delete it on macOS jobs (Xcode supplies Swift). On Linux jobs set it to `6.4`. |
| iOS destination with a pinned runtime, e.g. `OS=26.2` | `OS=latest` |
| No step that prints the toolchain in a test job | Add one right after checkout: `xcodebuild -version` and `swift --version`. The run log then shows which compiler CI actually used. |

Leave alone:
- `ubuntu-*` / `windows-*` runners (except the Linux `swift-version` row above).
- Simulator **device names** (`iPhone 17`, `iPad Pro 11-inch (M5)`). Change one only if a run fails to resolve it, and then resolve the simulator by UDID as `~/.claude/CLAUDE.md` describes.
- `swift-tools-version` in `Package.swift`, and deployment targets (`platforms:`, `IPHONEOS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`). They set the floor for consumers, not the CI toolchain. Raising them breaks downstream users.
- Job `name:` values. If you have to rename one, update branch protection's `required_status_checks.contexts` in the same run (see `~/.claude/CLAUDE.md`).
- Xcode Cloud configuration. This audit covers only GitHub Actions.

### Commit

If the audit changed nothing, say "CI already on `xcode-27`" in the report and move on.

Otherwise commit only the workflow files as their own commit, staged by path, then continue to the push step:

```bash
git add .github/workflows/<changed files>
git commit -m "Move CI to the Xcode 27 runner (macOS 27, iOS 27, Swift 6.4)"
```

Include the commit attribution trailer the session asks for. This commit is why pre-flight #3 (clean tree) still holds when the push runs.

Report each file and rule that changed. Also tell the user that CI no longer compiles with the older toolchain (Swift 6.3.x / Xcode 26). For an app whose release builds come from Xcode Cloud on an older Xcode, or a library whose consumers still use one, a compile failure on the older toolchain would now show up only there.

## Step 2 — Finalize an existing PR (primary path)

This is where the skill spends most of its time. The PR already exists; you're bringing it current.

### 2a. Sync the local view of the base

```bash
git fetch origin "$BASE"
```

So commit-range queries below are accurate.

### 2b. Push any local-only commits

```bash
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/$CURRENT" 2>/dev/null || echo none)"
# If REMOTE == "none" OR LOCAL != REMOTE: git push -u origin "$CURRENT"
```

The PR can't reflect commits the remote hasn't seen. Auto-pushing here is safe — the user already committed; refusing on a dirty tree (pre-flight #3) guarantees we're not pushing half-finished work.

### 2c. Fix the base branch if it's wrong

If the existing PR's `baseRefName` differs from the base you'd route to, change it:

```bash
gh pr edit "$PR_NUMBER" --base "$BASE"
```

A draft PR with the wrong base is a common artifact of branch-creation tooling that defaults everything to `main`. Quietly correcting it is the right move; don't ask first.

### 2d. Regenerate the title and body

Compose the title and body from the branch's commit log (see "Title" and "Body" below), then:

```bash
gh pr edit "$PR_NUMBER" --title "$TITLE" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Always overwrite — don't try to merge with the existing body. The branch's commit log is the source of truth.

### 2e. Mark ready for review

If `isDraft` is true:

```bash
gh pr ready "$PR_NUMBER"
```

If it's already non-draft, skip this — no need to "re-ready" it.

### 2f. Confirm CI started

Do this check after every finalize and every create (Step 3 ends here too), unless the PR is staying a draft.

**Why:** repos that use the draft-PR CI gate (`if: !github.event.pull_request.draft` on jobs, plus `concurrency: cancel-in-progress` on the PR ref) can lose the ready run to a race. Two PR events fire seconds apart: a push or create on the draft, then `ready_for_review`. If the draft event's run registers *after* the ready event's run, it cancels the real run, and then skips every job because its payload says draft. The PR ends up with no test run and nothing failed.

Wait about 60 seconds for the runs to register, then look at the runs for the PR's head commit:

```bash
HEAD_SHA="$(gh pr view "$PR_NUMBER" --json headRefOid -q .headRefOid)"
gh run list --commit "$HEAD_SHA" --event pull_request --json databaseId,status,conclusion,createdAt
# per run:
gh run view <id> --json jobs -q '.jobs[] | "\(.name): \(.status)/\(.conclusion)"'
```

Read the result:

| What you see | Meaning | Action |
|--------------|---------|--------|
| A run with jobs `queued`, `in_progress` or finished with real results | CI is running | None |
| One run `cancelled` with real jobs cancelled, and a newer run whose jobs are all `skipped` | The race | `gh run rerun <cancelled run id>`. A rerun keeps its original non-draft payload, so its jobs run and attach to the PR. |
| No runs at all after about 2 minutes | No trigger fired (workflow filters, or the runs haven't registered yet) | Report it. Don't use `workflow_dispatch`: a dispatched run on the head SHA doesn't satisfy a PR's required checks. Push a new commit or ask the user. |
| Runs ended in `startup_failure` | Usually Actions billing or quota, not the YAML | Report it; don't rerun in a loop. |

Tell the user which case you found and what you did.

### 2f′. Queue auto-merge (base `development` only)

When the base is `development` and the PR is ready for review (not staying a draft), queue GitHub auto-merge so it lands once the required checks pass, with no session needed:

```bash
gh pr merge "$PR_NUMBER" --auto --merge
# If it fails with "Auto merge is not allowed for this repository":
gh repo edit "$(gh repo view --json nameWithOwner -q .nameWithOwner)" --enable-auto-merge
gh pr merge "$PR_NUMBER" --auto --merge
```

Never do this when the base is `main` (or the repo default): a human merges those (`~/.claude/CLAUDE.md` § Merging PRs). For any other base, leave it alone. Say in the report that auto-merge is queued.

### 2g. Report

Return the PR URL to the user verbatim. They will click through.

## Step 3 — Create a new PR (fallback path)

Only when Step 1 found no existing PR.

### 3a. Push if needed (same logic as 2b)

```bash
git push -u origin "$CURRENT"  # if remote is missing or behind
```

### 3b. Create it ready for review (or as a draft, if asked)

```bash
gh pr create --base "$BASE" --head "$CURRENT" --title "$TITLE" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Create the PR ready for review in one step. **Don't create it as a draft and then `gh pr ready` it.** That fires two PR events seconds apart, and on repos with the draft-PR CI gate the draft event's run can cancel the ready run and then skip every job (see 2f).

If the user said "draft" or "as a draft", add `--draft` and stop there. Never follow it with `gh pr ready`.

### 3c. Confirm CI started

Run Step 2f, then 2f′, then report (2g).

## Title

Pattern depends on the base:

| Base          | Title pattern                                                 |
|---------------|---------------------------------------------------------------|
| `main`        | `Development → Main`                                          |
| `development` | First-line subject of the most recent commit on the branch    |

For `development → main`, use the literal arrow `→` (U+2192), not `->`. The repo's history (`git log --oneline`) uses the arrow form — match it so squash-merge titles stay consistent.

For branches landing on `development`, prefer the most recent commit subject since it's usually a high-signal summary the user just wrote. If the branch has only one commit, that subject *is* the natural PR title.

Get the latest commit subject with:

```bash
git log -1 --format='%s'
```

## Body

Always use this template, filled from the branch's commit log:

```markdown
## Summary
- <commit subject 1>
- <commit subject 2>
- ...

## Test plan
- [ ] <inferred test step>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Get the commit list with:

```bash
git log --reverse --format='%s' "origin/$BASE..HEAD"
```

Strip `Co-Authored-By:` lines and any trailing whitespace. Deduplicate consecutive identical subjects.

For the test plan, peek at what changed (`git diff --stat "origin/$BASE..HEAD"`) and write 1–3 specific checks. Examples:

- "Run `make test` on macOS"
- "Open `diga --version` and confirm it reports 0.10.11"
- "Verify Package.swift resolves with `make resolve`"
- "Smoke-test the iOS build on simulator at `iPhone 17, OS=latest`"

If you genuinely can't infer anything useful, fall back to a single placeholder: `- [ ] Manual verification`.

## What this skill does not do

- It does not merge the PR itself. For a `development` base it queues GitHub auto-merge (2f′). It never merges or auto-merges into `main`; a human does that.
- It does not push to `main` directly. Pre-flight refuses if you're on the default branch.
- It does not run tests or builds before finalizing. The user runs those — the PR is the artifact, not the verification gate.
- It does not amend existing commit history. Use `git rebase` / `git commit --amend` for that.
- It does not edit anything except CI workflow files (Step 1b). Source, `Package.swift`, project files and deployment targets are never touched.

## Why the rules are shaped this way

- **Finalize-first, create-fallback**: the user's workflow opens draft PRs early. Defaulting to create-new would either produce duplicate PRs or require an extra confirmation step every time. Finalize-first matches the steady state.
- **Auto-push, refuse on dirty**: push is recoverable; opening a PR with uncommitted local changes leaves the diff in a half-stated condition and loses the audit trail of what was actually being tested.
- **Refuse on default branch**: protects against the most common accidental footgun (`main → main` etc.). Costs nothing — the user will never legitimately PR from the default branch.
- **Always overwrite title/body on finalize**: the commit log is the source of truth. Trying to preserve manual edits in the description leads to drift; if the user has notes they care about, they'll re-add them after seeing the regenerated body.
- **Create ready in one step, then confirm CI started**: draft-then-ready fires two PR events. With `cancel-in-progress` concurrency and draft-skipping jobs, the draft event can win the race, so the PR ends up with a cancelled real run and a skipped draft run, and no failure to notice. One event avoids the race on create. The 2f check catches it on finalize, where a push to a draft followed by `gh pr ready` can still race.
- **CI audit before push**: the PR's first CI run is the one that counts. Moving the runner after the PR is up costs a second run, and a PR that passed on an old image proves nothing about the current toolchain.
- **Substring match on `mission`**: mission branches in this user's workflow live under multiple prefixes (`mission/quartermaster-reshuffle/1`, sometimes with `feature/` prepended). A substring rule is robust to those variations.
