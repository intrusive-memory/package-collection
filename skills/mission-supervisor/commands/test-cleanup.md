# Test Cleanup — Prune Non-CI-Safe Tests Before Brief

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission. **Test cleanup** is an automated post-mission pass that removes tests added during the mission which cannot reliably run in CI.

This command runs after the last planned sortie completes and before `brief`. Its only job is to prune tests added during the mission that are demonstrably unsafe for CI execution. CI is the primary build mechanism for these projects, so anything that depends on a developer's local machine is dead weight.

**Referenced by**: `commands/completion.md` § Step 6.5 (auto-invoked); `skill.md` § Argument Parsing → `test-cleanup` command.

---

## Why This Pass Exists

Sortie agents under time pressure write tests that pass on their machine and never run anywhere else. Hardcoded `/Users/<name>/...` paths, unmocked network calls, `Date.now()` assertions, sleeps timed for a fast laptop, dependencies on local services or env vars CI doesn't have. These tests fail intermittently in CI, get marked `skip`, then rot.

Pruning them now — while the mission's git history is fresh and the brief is about to be written — is cheaper than triaging them six weeks later when they've started blocking deploys.

**This pass is conservative.** It deletes tests with high-confidence CI-failure patterns. Anything ambiguous goes into `TEST_CLEANUP_REPORT.md` for human review during the brief. The default bias is "leave it and report it," not "delete it and hope."

---

## When to Run

- Automatically: invoked by `completion.md` immediately after final verification, before the brief prompt.
- Manually: `/mission-supervisor test-cleanup [path/to/EXECUTION_PLAN.md]` to re-run on an already-completed mission.

If `SUPERVISOR_STATE.md` shows any work unit not in `COMPLETED` state, STOP:
```
Cannot run test-cleanup — mission is not complete.
Work units still active: <list>
Test cleanup runs only after all sorties complete.
```

---

## Command Signature

```
/mission-supervisor test-cleanup [path/to/EXECUTION_PLAN.md]
```

Path resolution follows standard rules from `skill.md` § Locate EXECUTION_PLAN.md.

---

## Prerequisites

1. `EXECUTION_PLAN.md` exists.
2. `SUPERVISOR_STATE.md` exists with `starting_point_commit` recorded.
3. Working tree is clean (no uncommitted changes). If dirty, STOP and report — the cleanup commits its own changes and cannot operate on top of unrelated work.
4. Current branch is the mission branch recorded in `SUPERVISOR_STATE.md`.

---

## Procedure

### Step 1: Identify Mission Diff

Read `starting_point_commit` from `SUPERVISOR_STATE.md` (or EXECUTION_PLAN.md frontmatter). Compute the set of files changed by the mission:

```bash
git diff --name-only <starting_point_commit>..HEAD
```

Filter to test files. Detection by path/name (project-aware):
- Swift: paths matching `Tests/`, `*Tests.swift`, `*Test.swift`
- JS/TS: `*.test.ts`, `*.test.tsx`, `*.test.js`, `*.spec.*`, `__tests__/`
- Python: `test_*.py`, `*_test.py`, `tests/`
- Go: `*_test.go`
- Rust: `tests/`, `#[test]` blocks in src
- Generic fallback: any file with `test` or `spec` in its path

If no test files were added or modified, output:
```
No test files added or modified during this mission. Nothing to clean up.
```
Skip remaining steps and return.

### Step 2: Dispatch a Cleanup Sortie

This is a code-modification task, so it follows the supervisor's normal pattern: **dispatch an agent, do not write code yourself.** Use a single sortie with the model selected by codebase size:

| Test files changed | Model |
|--------------------|-------|
| 1–10               | haiku |
| 11–40              | sonnet |
| 41+                | sonnet (with explicit chunking instructions) |

Never use opus for this — the work is mechanical pattern-matching, not reasoning.

**Dispatch template** (fill `<>` placeholders):

```
You are running test-cleanup for mission <OPERATION_NAME>.

OBJECTIVE
Remove or quarantine tests added during this mission that cannot reliably run in CI. CI is the primary build mechanism — any test that requires a developer's local machine is dead weight.

INPUTS
- Mission branch: <mission_branch>
- Starting commit: <starting_point_commit>
- Test files in scope (added or modified during this mission):
  <newline-separated list from Step 1>

WHAT TO DELETE (high-confidence CI failures — delete the test, commit with reason)
1. Hardcoded local filesystem paths: `/Users/`, `/home/<name>/`, `C:\Users\`, `~/Desktop`, `~/Downloads`, etc. that are not parameterized by env var or fixture path.
2. Unmocked network calls to non-localhost hosts: `http://` / `https://` to public domains, real API endpoints, package registries.
3. Tests that spawn or depend on local-only services not declared in the project's CI config (e.g., a running Postgres on `localhost:5432` when CI has no such service).
4. Tests gated by env vars that CI does not set, with no skip-on-missing fallback (e.g., `OPENAI_API_KEY`, `STRIPE_SECRET`).
5. Tests that read from `~/.config`, `~/Library`, `%APPDATA%`, or other user-profile paths without isolation.
6. Sleep-based timing assertions with margins under 100ms (e.g., `assert duration < 50ms` after `sleep 30ms`) — these always flake on a loaded CI runner.
7. Tests asserting on `Date.now()`, `time.time()`, `Date()` without freezing time.
8. Tests asserting on iteration order of an unordered collection (`Dictionary`, `Set`, `HashMap`) without sorting first.
9. Tests using unseeded randomness (`Math.random()`, `random.random()`, `Int.random(in:)`) without a fixed seed.
10. Tests already marked `@skip("flaky")`, `xit`, `it.skip`, `t.Skip("flaky")`, `#[ignore]` with a flakiness reason — delete instead of leaving rotting.
11. Empty test bodies, `pass`-only tests, tests with no assertions.
12. Exact duplicates: two tests with identical bodies and identical assertions in the same file.

WHAT TO REPORT BUT NOT DELETE (borderline — log to TEST_CLEANUP_REPORT.md)
- Tests over 200 lines (possibly too large but may be legitimate integration tests).
- Tests using real timestamps as test data without time-freezing (may be safe if assertions are range-based).
- Tests with `setTimeout`/`DispatchQueue.asyncAfter` over 100ms (may be legitimate async behavior).
- Tests that hit `localhost` on a non-standard port (may be a test fixture spun up in setUp).
- Tests with names suggesting flakiness (`testRetryEventually`, `testFlaky*`) but no skip marker.
- Tests that import `XCTSkip`, `unittest.skip`, etc. conditionally — verify the condition is CI-safe before flagging.

WHAT TO LEAVE ALONE
- Anything not in the in-scope file list above. Do not touch tests written before this mission.
- Tests that use proper mocking, fixtures, or hermetic test doubles.
- Tests that test time-related code by injecting a clock — these are correct, not flaky.

DELIVERABLES
1. Delete the qualifying tests (whole `func test*` block or its language equivalent — never leave dangling braces).
2. If a file becomes empty after deletions, delete the file.
3. After all deletions, run the project's test target if a Makefile target exists (`make test`, `make test-unit`). If no Makefile target exists, skip this — do NOT run `swift test` or `swift build` directly.
4. Write `TEST_CLEANUP_REPORT.md` at the project root with:
   - Section "Removed": table of `file:test_name` | reason | confidence
   - Section "Flagged for Review": table of `file:test_name` | concern | recommended action
   - Section "Build Verification": result of the test run, or "skipped (no Makefile target)"
5. Commit the deletions (one commit) with message:
   ```
   test-cleanup: prune <N> non-CI-safe tests added during <OPERATION_NAME>

   Removed tests with high-confidence CI-failure patterns. See TEST_CLEANUP_REPORT.md
   for the full list and borderline cases flagged for human review.
   ```

EXIT CRITERIA
- Every removal has a one-line reason in TEST_CLEANUP_REPORT.md.
- The "Removed" table cites the specific pattern (one of the 12 above).
- If the test target exists and was run: it passes. If it fails because a deleted test was load-bearing, restore it and re-flag for review instead.
- TEST_CLEANUP_REPORT.md exists at the project root.
- Cleanup commit exists on the mission branch.

CONSTRAINTS
- Be conservative. When in doubt, flag for review — do not delete.
- Never delete a non-test source file. Only `*.test.*`, `*Tests.swift`, `test_*.py`, etc.
- Never modify test logic to "fix" it. Either delete the test wholesale or leave it.
- Never use `--no-verify` to bypass pre-commit hooks. If a hook fails, fix the underlying issue.
```

### Step 3: Verify the Cleanup Sortie

After the cleanup agent reports done:

1. Confirm `TEST_CLEANUP_REPORT.md` exists at `$PROJECT_ROOT`.
2. Confirm a new commit exists on the mission branch since dispatch.
3. Read the report's summary counts.
4. If the agent reported "build verification: failed" and did not restore the load-bearing test, mark this sortie BACKOFF and re-dispatch once with explicit instructions to restore-and-flag instead of delete.

If the cleanup sortie reaches FATAL: do **not** block the mission. Output a warning, leave any partial deletions in place uncommitted (the user can `git checkout .` if they want to discard), and proceed to brief. The brief will surface the failure as an open decision.

### Step 4: Append to Completion Log

Append to `COMPLETE_<PROJECT_NAME>.md`:

```markdown
### ✓ Test Cleanup (post-mission)
- **Status**: COMPLETED (or FAILED — see warning above)
- **Tests removed**: <N>
- **Tests flagged for review**: <N>
- **Build verification**: <pass | fail | skipped>
- **Report**: TEST_CLEANUP_REPORT.md
- **Commit**: <hash>

---
```

### Step 5: Hand Off to Brief

Output to user:

```
Test cleanup complete.
- Removed: <N> tests with high-confidence CI-failure patterns
- Flagged for review: <N> tests (see TEST_CLEANUP_REPORT.md)
- Build verification: <pass | fail | skipped>

Proceeding to post-mission brief. The brief will:
- Read TEST_CLEANUP_REPORT.md to inform the rollback verdict
- Issue an explicit verdict: ROLLBACK | KEEP | PARTIAL_SALVAGE
- Auto-invoke clean → /organize-agent-docs to archive all mission artifacts
```

Then invoke `/mission-supervisor brief` (see `commands/brief.md`).

---

## What This Command Does NOT Do

- Does **not** modify pre-mission tests. Only files in the mission diff are in scope.
- Does **not** "fix" tests. It deletes or flags. Repair is a job for the next iteration.
- Does **not** delete production code. Test files only.
- Does **not** bypass `brief` or `clean`. It is a step *between* completion and brief.
- Does **not** block the mission from proceeding to brief on failure. A failed cleanup becomes an input to the brief's verdict, not a hard stop.

---

## Failure Modes

| Failure | Behavior |
|---------|----------|
| Working tree dirty | STOP before dispatching. User must commit or stash first. |
| No test files in mission diff | Skip the dispatch entirely; output one-line confirmation. |
| Cleanup sortie hits FATAL | Warn, append failure to COMPLETE_*.md, proceed to brief anyway. |
| Test target fails after cleanup | Cleanup agent must restore the load-bearing test and flag it instead of deleting. |
| Mission branch missing | STOP. Report "Cannot run test-cleanup outside mission branch." |
