# EXECUTION_PLAN.md — Ship Swift Libraries (Batch Release)

Ship all Intrusive Memory Swift libraries that have open PRs from `development` to `main`. Each library is processed independently. If CI checks are still pending for a library, skip it and move on — do not wait.

---

## Work Units

| Work Unit | Directory | Sprints | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| SwiftBruja | intrusive-memory/SwiftBruja | 1 | 1 | none |
| SwiftCompartido | intrusive-memory/SwiftCompartido | 1 | 1 | none |
| SwiftEspeak | intrusive-memory/SwiftEspeak | 1 | 1 | none |
| SwiftFFMpeg | intrusive-memory/SwiftFFMpeg | 1 | 1 | none |
| SwiftFijos | intrusive-memory/SwiftFijos | 1 | 1 | none |
| SwiftHablare | intrusive-memory/SwiftHablare | 1 | 1 | none |
| SwiftProyecto | intrusive-memory/SwiftProyecto | 1 | 1 | none |
| SwiftPruebas | intrusive-memory/SwiftPruebas | 1 | 1 | none |
| SwiftSecuencia | intrusive-memory/SwiftSecuencia | 1 | 1 | none |
| SwiftEchada | intrusive-memory/SwiftEchada | 1 | 1 | none |
| mlx-audio-swift | intrusive-memory/mlx-audio-swift | 1 | 1 | none |
| SwiftOnce | intrusive-memory/SwiftOnce | 1 | 1 | none |

All work units are Layer 1 with no cross-dependencies. They run in parallel.

---

## Dispatch Template

For each work unit, dispatch the sprint agent with this prompt. Replace `{{REPO}}` with the GitHub repo slug (e.g. `intrusive-memory/SwiftBruja`), and `{{PACKAGE}}` with the package name (e.g. `SwiftBruja`).

---

## Sprint Definitions

Each work unit has one sprint with identical structure. The sprint logic is:

1. Check if an open PR exists
2. If no PR → done (nothing to ship)
3. If PR exists → check CI status
4. If CI pending → report "CI pending" and stop (do NOT wait)
5. If CI failing → report the failures and stop
6. If CI passing → execute the full ship-swift-library process

---

### SwiftBruja — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone or navigate to the repo: `gh repo clone intrusive-memory/SwiftBruja /tmp/ship-SwiftBruja` (or use `/tmp/ship-SwiftBruja` if already cloned)
2. Check for open PR from `development` to `main`:
   ```bash
   cd /tmp/ship-SwiftBruja && gh pr list --base main --head development --json number,title,state --jq '.[0]'
   ```
3. **If no PR exists**: Report "No open PR for SwiftBruja — nothing to ship" and stop. Sprint is complete.
4. **If PR exists**: Check CI status:
   ```bash
   gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftBruja
   ```
5. **If any checks are pending**: Report "SwiftBruja PR #N — CI checks still running, skipping" and stop. Sprint is complete (mark as PARTIAL so supervisor can retry later).
6. **If any checks are failing**: Report the failing checks and stop. Sprint is complete (mark as PARTIAL).
7. **If all checks pass**: Execute the `/ship-swift-library` release process:
   - Squash merge the PR: `gh pr merge <PR_NUMBER> --squash --delete-branch=false`
   - Checkout main and pull: `git checkout main && git pull origin main`
   - Find the version file and determine the appropriate version bump (patch for fixes, minor for features)
   - Bump the version in the source file
   - Commit the version bump
   - Cherry-pick the version bump to development and push both branches
   - Create annotated tag and push it
   - Create GitHub release with release notes derived from the PR description and commits
   - Verify the release

**Exit criteria**:
- [ ] `gh pr list --base main --head development --repo intrusive-memory/SwiftBruja` returns empty (PR merged) OR no PR existed OR CI was not ready (PARTIAL)
- [ ] If shipped: `gh release view --repo intrusive-memory/SwiftBruja --json tagName` returns the new version tag

---

### SwiftCompartido — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone or navigate to the repo: `gh repo clone intrusive-memory/SwiftCompartido /tmp/ship-SwiftCompartido`
2. Check for open PR from `development` to `main`:
   ```bash
   cd /tmp/ship-SwiftCompartido && gh pr list --base main --head development --json number,title,state --jq '.[0]'
   ```
3. **If no PR exists**: Report and stop. Sprint complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftCompartido`
5. **If CI pending**: Report "CI still running, skipping" and stop (PARTIAL).
6. **If CI failing**: Report failures and stop (PARTIAL).
7. **If all checks pass**: Execute `/ship-swift-library` — merge PR, bump version, tag, release, verify.

**Exit criteria**:
- [ ] PR merged or no PR existed or CI not ready (PARTIAL)
- [ ] If shipped: new release tag exists on the repo

---

### SwiftEspeak — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftEspeak /tmp/ship-SwiftEspeak`
2. Check for open PR: `cd /tmp/ship-SwiftEspeak && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftEspeak`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftFFMpeg — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftFFMpeg /tmp/ship-SwiftFFMpeg`
2. Check for open PR: `cd /tmp/ship-SwiftFFMpeg && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftFFMpeg`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftFijos — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftFijos /tmp/ship-SwiftFijos`
2. Check for open PR: `cd /tmp/ship-SwiftFijos && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftFijos`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftHablare — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftHablare /tmp/ship-SwiftHablare`
2. Check for open PR: `cd /tmp/ship-SwiftHablare && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftHablare`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftProyecto — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftProyecto /tmp/ship-SwiftProyecto`
2. Check for open PR: `cd /tmp/ship-SwiftProyecto && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftProyecto`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftPruebas — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftPruebas /tmp/ship-SwiftPruebas`
2. Check for open PR: `cd /tmp/ship-SwiftPruebas && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftPruebas`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftSecuencia — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftSecuencia /tmp/ship-SwiftSecuencia`
2. Check for open PR: `cd /tmp/ship-SwiftSecuencia && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftSecuencia`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftEchada — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftEchada /tmp/ship-SwiftEchada`
2. Check for open PR: `cd /tmp/ship-SwiftEchada && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftEchada`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### mlx-audio-swift — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/mlx-audio-swift /tmp/ship-mlx-audio-swift`
2. Check for open PR: `cd /tmp/ship-mlx-audio-swift && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/mlx-audio-swift`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

### SwiftOnce — Sprint 1: Check and Ship

**Entry criteria**:
- [ ] First sprint — no prerequisites

**Tasks**:
1. Clone: `gh repo clone intrusive-memory/SwiftOnce /tmp/ship-SwiftOnce`
2. Check for open PR: `cd /tmp/ship-SwiftOnce && gh pr list --base main --head development --json number,title,state --jq '.[0]'`
3. **If no PR**: Report and stop. Complete.
4. **If PR exists**: Check CI: `gh pr checks <PR_NUMBER> --repo intrusive-memory/SwiftOnce`
5. **If CI pending**: Skip (PARTIAL). **If CI failing**: Report (PARTIAL).
6. **If all checks pass**: Execute `/ship-swift-library` — merge, bump, tag, release.

**Exit criteria**:
- [ ] PR merged or no PR or CI not ready
- [ ] If shipped: new release tag exists

---

## Supervisor Rules

### Outcome Classification

Each sprint agent will complete with one of these outcomes:

| Outcome | Meaning | Supervisor Action |
|---------|---------|-------------------|
| **No PR** | No open PR exists for this library | Mark COMPLETED — nothing to do |
| **Shipped** | PR merged, version bumped, tagged, release created | Mark COMPLETED |
| **CI Pending** | PR exists but CI checks are still running | Mark PARTIAL — retry later |
| **CI Failing** | PR exists but CI checks have failures | Mark PARTIAL — report to user |
| **Error** | Something went wrong during the ship process | Mark BACKOFF — retry |

### Ship Process Reference

The full `/ship-swift-library` process for each library (when CI passes):

1. Squash merge the PR (`gh pr merge --squash --delete-branch=false`)
2. Checkout main, pull the merge commit
3. Find version file in `Sources/`, determine bump level from PR content
4. Bump version, commit with Claude Code attribution
5. Cherry-pick version bump to development, push both branches
6. Create annotated tag (`vX.Y.Z`) and push
7. Create GitHub release with notes from PR
8. Verify release exists

### Critical Rules

- **Never bypass the PR** — always merge via `gh pr merge`, never `git merge development`
- **Use `--squash`** for clean main branch history
- **Do NOT delete the development branch** — it is long-lived
- **Do NOT wait on pending CI** — report status and move on. The supervisor will retry the work unit later.
- **Version bump goes to both branches** — main and development must stay in sync

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 12 |
| Total sprints | 12 |
| Dependency structure | parallel (all Layer 1, no dependencies) |
| Estimated max turns per sprint | 30 |
