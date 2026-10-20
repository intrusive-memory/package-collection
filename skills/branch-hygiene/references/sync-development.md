---
type: reference
---

# Sync Development onto Main (squash-merge procedure)

After a squash merge, development's original commits are not ancestors of the squash commit on main. A `git merge main` would make the code identical but leave those old commits visible in the next PR (tons of commits, zero diff).

## When to run this

**Normally: `/branch-hygiene` Step 1, immediately after the release merge, when the sync detector reports `squash`.** That is the designed slot. (Merge-commit repos never need this file — a plain `git merge origin/main` is correct there.)

**Also: as a preflight, before the release, when a previous cycle skipped it.** If `development` does not contain main's tip, the release PR will land `CONFLICTING` — and a conflicted PR produces **no CI at all**, because GitHub cannot build the merge ref that `pull_request` workflows run against. `gh pr checks` reports `no checks reported on the '<branch>' branch`, which looks like "CI hasn't started" and will hang a `--watch` indefinitely. Detect it with:

```bash
git merge-base --is-ancestor origin/main origin/development \
  && echo "OK: development descends from main" \
  || echo "DIVERGENT: rebase now, before touching the release PR"
```

This procedure is safe at either end of the cycle. The only difference is which commits count as "genuinely new" (see Step 4 below).

## Why not just `git rebase main`?

The phantom commits from the merged PR conflict with the squash commit during rebase, causing conflicts even though there is no real diff. On repos where `development` is protected with `allow_force_pushes: false`, a normal rebase is rejected outright. The solution is to reset development to main's tip, cherry-pick only *genuinely new* commits, and force-push — temporarily unlocking force-push **only if the branch is actually protected**.

## Why NOT `git cherry` for detecting new commits?

`git cherry` compares by patch-id. After a squash merge, the individual dev commits each have different patch-ids than the combined squash commit on main — so `git cherry` flags ALL of them as "+" (new) even though their content is already in main. Cherry-picking those phantoms produces duplicates or no-op conflicts. Use the **content diff** as the primary signal, and the **PR's own commit list** as the exclusion set.

## Procedure

```bash
# Step 1: Update local main and development
git checkout main && git pull origin main
git checkout development && git pull origin development

# Step 2: Back up the pre-rebase tip. This is a destructive, history-rewriting
# operation on a shared branch — always leave a recovery point.
BACKUP="backup/development-pre-rebase-v${RELEASED:-${VERSION:-unknown}}"
git branch "$BACKUP" origin/development
git push origin "$BACKUP"
echo "Backup pushed: ${BACKUP} (delete once the release is verified)"

# Step 3: Discover repo, and whether development is protected AT ALL.
# Protection is per-repo. Many repos protect only `main`, or nothing.
# `gh api .../protection` returns HTTP 404 "Branch not protected" when absent —
# that is a normal, expected answer, NOT an error to abort on.
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

if PROTECTION=$(gh api "repos/${REPO}/branches/development/protection" 2>/dev/null); then
  IS_PROTECTED=1
  # Save the protection EXACTLY as it is, and convert the GET shape into the PUT shape
  # once. Unlock and restore are both derived from this copy, so every setting —
  # strict, the PR-review requirement, admin enforcement, restrictions, linear
  # history, deletions — comes back as it was. Never hand-write a protection body:
  # an earlier version of this skill did, and silently dropped the PR requirement
  # and forced `strict: true` on every repo it touched.
  PROTECTION_FILE=$(mktemp -t protection-before)
  printf '%s' "$PROTECTION" > "$PROTECTION_FILE"
  PUT_BODY=$(jq -c '{
    required_status_checks: (if .required_status_checks then
      {strict: .required_status_checks.strict,
       contexts: [.required_status_checks.contexts[]?]} else null end),
    enforce_admins: (.enforce_admins.enabled // false),
    required_pull_request_reviews: (if .required_pull_request_reviews then
      {dismiss_stale_reviews: (.required_pull_request_reviews.dismiss_stale_reviews // false),
       require_code_owner_reviews: (.required_pull_request_reviews.require_code_owner_reviews // false),
       required_approving_review_count: (.required_pull_request_reviews.required_approving_review_count // 0),
       require_last_push_approval: (.required_pull_request_reviews.require_last_push_approval // false)}
      else null end),
    restrictions: (if .restrictions then
      {users: [.restrictions.users[]?.login], teams: [.restrictions.teams[]?.slug],
       apps: [.restrictions.apps[]?.slug]} else null end),
    required_linear_history: (.required_linear_history.enabled // false),
    allow_force_pushes: (.allow_force_pushes.enabled // false),
    allow_deletions: (.allow_deletions.enabled // false),
    block_creations: (.block_creations.enabled // false),
    required_conversation_resolution: (.required_conversation_resolution.enabled // false),
    lock_branch: (.lock_branch.enabled // false),
    allow_fork_syncing: (.allow_fork_syncing.enabled // false)
  }' <<<"$PROTECTION")
  echo "development IS protected. Saved to ${PROTECTION_FILE}."
else
  IS_PROTECTED=0
  echo "development is NOT protected — no toggle needed, force-push directly."
fi
```

```bash
# Step 4: Determine whether development has any REAL content diff vs main.
#   - No diff  → all dev commits were squashed into main. Clean reset, no cherry-pick.
#   - Has diff → real work exists on dev. Preserve only the commits that carry it.
if [ -z "$(git diff origin/main..origin/development --stat)" ]; then
  echo "Development has no content diff vs main — phantom commits only. Will reset cleanly."
  NEW_COMMITS=""
else
  echo "Development has real content diff vs main. Identifying genuinely new commits."
  DEV_COMMITS=$(git log --reverse --format='%H' origin/main..origin/development)

  # Post-release: exclude the commits that were squashed by the PR just merged.
  if [ -n "${PR_NUMBER:-}" ]; then
    PR_COMMITS_PATTERN=$(gh pr view "${PR_NUMBER}" --json commits --jq '[.commits[].oid] | join("|")')
    NEW_COMMITS=$(echo "${DEV_COMMITS}" | grep -vE "^(${PR_COMMITS_PATTERN})$" || true)
  else
    NEW_COMMITS="${DEV_COMMITS}"
  fi

  echo "Candidate commits to preserve:"
  git log --oneline --reverse origin/main..origin/development
fi
```

**Verify the candidate set by content, not by trusting the exclusion list.** Print the true net diff and confirm every file in it is accounted for by a commit you intend to keep:

```bash
git diff origin/main..origin/development --stat   # the ONLY changes that must survive
for c in ${NEW_COMMITS}; do
  echo "--- $c $(git log -1 --format=%s $c)"
  git show --stat --format="" "$c" | tail -5
done
```

Anything in the net diff not produced by a kept commit means your set is wrong — widen it before proceeding.

```bash
# Step 5: Unlock force-push — ONLY if the branch is protected.
# Same body as saved, with exactly one change: allow_force_pushes = true.
# From here on, Step 8 (restore) MUST run even if a later step fails.
if [ "$IS_PROTECTED" = "1" ]; then
  jq -c '.allow_force_pushes = true' <<<"$PUT_BODY" |
    gh api --method PUT "repos/${REPO}/branches/development/protection" --input -
fi

# Step 6: Reset development to main's tip, cherry-pick any genuinely new commits
git reset --hard origin/main
if [ -n "${NEW_COMMITS}" ]; then
  git cherry-pick ${NEW_COMMITS}
fi
```

### Expected conflict: the version-bump commit

When running this **as a preflight** (before the release), the version-bump commit will conflict. It was authored against a base carrying `X.Y.Z-dev`, but `main` carries the clean `X.Y.Z`:

```
<<<<<<< HEAD
let libVersion = "0.24.1"        # from main
=======
let libVersion = "0.25.0"        # what the bump commit wants
>>>>>>> e86383c (chore(release): bump version to 0.25.0)
```

Always resolve to the **incoming** side (the new version). Then:

```bash
git add <resolved files> && git cherry-pick --continue --no-edit
```

### Verify the rebase preserved the tree exactly

Before force-pushing, prove the rebased tree is byte-identical to what you started with. This is the single most important check in the procedure:

```bash
git diff <pre-rebase-dev-tip-sha> HEAD --stat   # MUST be empty
```

Empty output means the rebase changed history but not content. Non-empty means you dropped or mangled a commit — reset to the backup branch and redo. Also re-run the test suite and a build before pushing.

```bash
# Step 7: Force-push the clean development branch
git push origin development --force-with-lease

# Step 8: Restore branch protection — ONLY if you unlocked it in Step 5.
# Run this even if Steps 6–7 failed. Restore the saved body unchanged, then prove it.
if [ "$IS_PROTECTED" = "1" ]; then
  printf '%s' "$PUT_BODY" |
    gh api --method PUT "repos/${REPO}/branches/development/protection" --input -
  NORMALIZE='del(.. | .url?, .contexts_url?) | del(.required_status_checks.checks)'
  if diff <(jq -S "$NORMALIZE" "$PROTECTION_FILE") \
          <(gh api "repos/${REPO}/branches/development/protection" | jq -S "$NORMALIZE"); then
    echo "Protection restored exactly as saved."
  else
    echo "PROTECTION DIFFERS FROM THE SAVED STATE — stop and report; do not continue." >&2
    exit 1
  fi
else
  echo "Branch was never protected — nothing to restore."
fi
```

## Verification

- `git diff origin/main..origin/development --stat` should be empty when no new commits were preserved, or match the expected set of post-merge changes when cherry-picks happened.
- `git log --oneline -3` on development should show main's squash commit as the base.
- When run as a preflight, re-check the PR: `gh pr view "$PR_NUMBER" --json mergeable --jq '.mergeable'` should now report `MERGEABLE`, and CI should start within a minute.
- Delete the backup branch once the release is verified: `git push origin --delete "$BACKUP"`.

## Note on the HEREDOC

The HEREDOC uses unquoted `JSON` because it needs to interpolate `${CHECKS_JSON}`. The body has no literal `$` characters that need escaping, so unquoted is safe.
