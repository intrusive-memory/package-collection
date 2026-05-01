# Step 10: Rebase Development onto Main

After a squash merge, development's original commits are not ancestors of the squash commit on main. A `git merge main` would make the code identical but leave those old commits visible in the next PR (tons of commits, zero diff).

## Why not just `git rebase main`?

The `development` branch is protected with `allow_force_pushes: false`. A normal rebase requires force-push, which gets rejected. Additionally, the phantom commits from the merged PR conflict with the squash commit during rebase, causing conflicts even though there is no real diff. The solution is to temporarily unlock force-push, reset development to main's tip, cherry-pick only *genuinely new* commits (those added after the PR was created), force-push, then restore the protection.

## Why NOT `git cherry` for detecting new commits?

`git cherry` compares by patch-id. After a squash merge, the individual dev commits each have different patch-ids than the combined squash commit on main — so `git cherry` flags ALL of them as "+" (new) even though their content is already in main. Cherry-picking those phantoms produces duplicates or no-op conflicts. Use the **content diff** as the primary signal, and the **PR's own commit list** as the exclusion set.

## Procedure

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

## Verification

`git diff origin/main..origin/development --stat` should be empty when no new commits were preserved, or match the expected set of post-merge changes when cherry-picks happened. `git log --oneline -3` on development should show main's squash commit as the base.

## Note on the HEREDOC

The HEREDOC uses unquoted `JSON` because the heredoc needs to interpolate `${CHECKS_JSON}` and `${REPO}`. The body has no literal `$` characters that need escaping, so unquoted is safe.
