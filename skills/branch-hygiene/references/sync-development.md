---
type: reference
---

# Sync Development onto Main (merge, by PR)

`/branch-hygiene` syncs `development` by merging `origin/main` into a `chore/*` branch cut from `development`. That branch lands through a PR opened with `/create-pull-request`. Nothing is ever pushed or force-pushed to `development`, and branch protection is never touched.

## The normal case: last release was a merge commit

Both `/ship-swift-library` and `/ship-app` merge the release PR with `--merge`. `main`'s new tip is then a merge commit whose second parent is `development`'s tip, so `git merge origin/main` on the chore branch is trivial: there are no conflicts, and the merge only adds `main`'s merge commit to `development`'s history.

## The one-time case: last release was a squash (legacy)

`/ship-swift-library` used to merge with `--squash`. In a repo whose most recent release went out that way, `development`'s commits are not ancestors of the squash commit on `main`. Merging `main` in then conflicts wherever the release bump touched the same lines as later work, which is typically the version constant, README install snippets and doc version strings.

Resolve it **without rewriting history**:

```bash
git merge origin/main --no-edit       # stops on conflicts
git diff --name-only --diff-filter=U  # the conflicted files
```

- **Version strings:** take `main`'s side (`git checkout --theirs <file>`). It carries the clean released version, and Step 2's `-dev` marker stamps it next.
- **Anything else:** take `development`'s side (`git checkout --ours <file>`) when the change on `development` is genuinely newer work, and keep both sides by hand when both are real. If the right side isn't obvious, stop and ask. In unattended mode, abort with the file list.

```bash
git add <resolved files>
git commit --no-edit
```

**Verify that only the intended content changed.** Every file in this diff must be one you resolved on purpose, or something `main` legitimately added:

```bash
git diff origin/development HEAD --stat
```

The squash's phantom commits stay in `development`'s history, and the next release PR's commit list shows them once. That cost is cosmetic. Once that release merges with `--merge`, they become ancestors of `main` and never appear again. A history rewrite to hide them is not worth a force-push to a protected branch.

## Then

Continue with Step 2 (the next-cycle marker) on the same chore branch, and land both through one PR. The chore PR runs the full required CI gate like any other PR into `development`. Do not merge around a red or missing check.
