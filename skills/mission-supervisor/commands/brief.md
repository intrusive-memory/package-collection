# Mission Brief — Post-Mission Review

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission. A *brief* is the post-mission review that harvests lessons before the next iteration.

This document defines the `brief` command — the mandatory post-mission review ritual. Every mission ends with a brief. No exceptions. This is the ward for the Rodillo Liso process.

**Referenced by**: `skill.md` § Argument Parsing → `brief` command.

---

## When to Run

- After a mission reaches `COMPLETED` (all work units done)
- After a mission is `ABANDONED` (user decides to stop and roll back)
- After a mission is `BLOCKED` with no intent to resume
- **Before any rollback.** If the user says "roll back" or "start over," run the brief first.

---

## Command Signature

```
/mission-supervisor brief [path/to/EXECUTION_PLAN.md]
```

Path resolution follows standard rules from `skill.md` § Locate EXECUTION_PLAN.md.

---

## Prerequisites

The brief requires:
1. `EXECUTION_PLAN.md` — the mission plan (must exist)
2. `SUPERVISOR_STATE.md` — the execution state (must exist, even if incomplete)
3. `COMPLETE_*.md` — the completion log (may not exist if mission was abandoned early)
4. Git history on the mission branch (for sortie accuracy analysis)
5. `TEST_CLEANUP_REPORT.md` — output from the test-cleanup pass (see `commands/test-cleanup.md`). May be absent if test-cleanup was skipped (no test files in mission diff) or failed; the brief must note the absence and factor it into the verdict.

If `SUPERVISOR_STATE.md` does not exist, STOP:
```
Cannot brief a mission that was never started.
There is no state to review.
```

---

## Output File

Generate: `<OPERATION_NAME>_<NN>_BRIEF.md`

Where:
- `<OPERATION_NAME>` is the operation name from EXECUTION_PLAN.md frontmatter `feature_name`, with spaces replaced by underscores. Example: `OPERATION STEAMROLLER ORIGAMI` → `OPERATION_STEAMROLLER_ORIGAMI`
- `<NN>` is the two-digit iteration number (zero-padded). First mission is `01`. If a previous brief exists with the same operation name, increment.

Detection:
1. Read `feature_name` from EXECUTION_PLAN.md frontmatter.
2. Glob for `<OPERATION_NAME>_*_BRIEF.md` in `$PROJECT_ROOT`.
3. Find the highest existing `NN`. New brief is `NN + 1`.
4. If no previous briefs exist, use `01`.

Example filenames:
- `OPERATION_STEAMROLLER_ORIGAMI_01_BRIEF.md`
- `OPERATION_STEAMROLLER_ORIGAMI_02_BRIEF.md`
- `OPERATION_STEAMROLLER_ORIGAMI_03_BRIEF.md`

---

## Brief Structure

### Header

```markdown
# Iteration <NN> Brief — <Operation Name>

**Mission:** <one sentence from EXECUTION_PLAN.md summary>
**Branch:** <current git branch>
**Starting Point Commit:** <the commit hash recorded in SUPERVISOR_STATE.md or EXECUTION_PLAN.md frontmatter>
**Sorties Planned:** <total from plan>
**Sorties Completed:** <count from COMPLETE_*.md or state>
**Sorties Failed/Blocked:** <count>
**Duration:** <wall clock or relative cost from COMPLETE_*.md>
**Outcome:** Complete | Incomplete | Abandoned
**Verdict:** `KEEP` | `ROLLBACK` | `PARTIAL_SALVAGE` — <one-sentence justification>
**Tests pruned:** <N from TEST_CLEANUP_REPORT.md, or "report missing">
**Tests flagged for review:** <N from TEST_CLEANUP_REPORT.md, or "report missing">
```

The `Verdict:` field is **mandatory** and **machine-readable** — it must be exactly one of the three tokens (`KEEP`, `ROLLBACK`, `PARTIAL_SALVAGE`) followed by a justification. Section 8 below requires the same token in a dedicated section. They must agree.

### Section 1: Hard Discoveries

Constraints, requirements, and behaviors that were **not known before the mission started** and were discovered through collision with reality. These are facts about the problem domain, the dependency APIs, the spec, or the toolchain.

For each discovery:

```markdown
### <N>. <Short Name>

**What happened:** <The collision. What broke, what failed, what surprised.>
**What was built to handle it:** <The code, the workaround, the fix.>
**Should we have known this?** <Yes/No. If yes, what research would have revealed it?>
**Carry forward:** <The constraint, stated as a requirement for the next iteration.>
```

Hard discoveries are **not opinions**. They are facts. "The DTD requires r-prefixed IDs" is a hard discovery. "We should have used a different pattern" is a process discovery.

**How to find hard discoveries:**
1. Search git log for commits containing "fix", "compliance", "DTD", "invalid", "error", "workaround".
2. Search SUPERVISOR_STATE.md Decisions Log for BACKOFF and FATAL entries.
3. Search COMPLETE_*.md for sorties with attempts > 1.
4. Read agent output for sorties that failed — the failure messages reveal the constraint.
5. Read `TEST_CLEANUP_REPORT.md`. Patterns the cleanup pass had to remove (unmocked network, hardcoded paths, time races) often point to a hard discovery about the test environment or CI that was never written down — capture it here so the next iteration's plan accounts for it.

### Section 2: Process Discoveries

Lessons about **how the work was organized, sized, and executed**. Split into three categories:

#### What the Agents Did Right
Patterns, code, architectural decisions worth preserving.

#### What the Agents Did Wrong
Wasted work, wrong turns, over-engineering, unnecessary files.

#### What the Planner Did Wrong
Bad sizing, missing research, wrong assumptions, over/under-planning.

For each discovery:

```markdown
### <N>. <Short Name>

**What happened:** <The process decision and its outcome.>
**Right or wrong?** <Was this the right call? Did it help or hurt?>
**Evidence:** <Concrete — commit counts, context overruns, wasted files, time spent.>
**Carry forward:** <The process change for the next iteration.>
```

**How to find process discoveries:**
1. Compare planned sortie count vs actual. Over-planned? Under-planned?
2. Check COMPLETE_*.md cadence analysis — which sorties overran context budget?
3. Count commits per sortie. Sorties with 5+ commits may have been too large.
4. Identify files created that were later deleted or made irrelevant by subsequent sorties.
5. Check model selection accuracy — were haiku sorties upgraded to sonnet/opus on retry?

### Section 3: Open Decisions

Questions that **must be answered before the next iteration starts**. Blockers, not nice-to-haves.

```markdown
### <N>. <The Question>

**Why it matters:** <What goes wrong if you don't decide.>
**Options:** <A, B, C — with tradeoffs.>
**Recommendation:** <Your current best guess, if you have one.>
```

**How to find open decisions:**
1. Any BLOCKED work unit — what blocked it? Is the blocker a design question?
2. Any regex/workaround in the code — is there a better approach?
3. Any functional gap (features that were dropped or deferred) — is the gap acceptable?
4. Any upstream dependency issue — file a PR, fork, or accept?

### Section 4: Sortie Accuracy

A table assessing each sortie's accuracy. Not every sortie needs detailed notes — focus on notably accurate or notably wasteful ones.

```markdown
| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
```

**Accuracy definition:** A sortie is accurate if its output survived into the final state without significant rework. A sortie is inaccurate if its output was later overwritten, deleted, or rendered moot by a subsequent discovery.

**How to assess accuracy:**
1. For each completed sortie, check if its commits were later reverted or substantially modified by a subsequent sortie.
2. Check if any files created by the sortie were deleted in a later sortie.
3. A sortie that required 3 attempts is less accurate than one that completed on the first attempt, regardless of final outcome.

### Section 5: Harvest Summary

One paragraph. What do you now know that you didn't know before? What is the single most important thing that changes about the next iteration?

If `TEST_CLEANUP_REPORT.md` exists, summarize it in one or two sentences here: how many tests were pruned, how many flagged, and whether the pattern of failures suggests systemic issues (e.g., "agents repeatedly wrote sleep-based timing tests" → planning lesson about prompt instructions).

### Section 6: Files

Two tables:

**Preserve (read-only reference for next iteration):**
```markdown
| File | Branch | Why |
|------|--------|-----|
```

**Discard (will not exist after rollback):**
```markdown
| File | Why it's safe to lose |
|------|----------------------|
```

### Section 7: Iteration Metadata

```markdown
## Iteration Metadata

**Starting point commit:** `<hash>` (`<short description>`)
**Mission branch:** `<branch_name>`
**Final commit on mission branch:** `<hash>`
**Rollback target:** `<hash>` (same as starting point commit)
**Next iteration branch:** `mission/<operation_name_slug>/<NN+1>`
```

This section records the git state needed to:
- Reference this iteration's work (the branch is preserved locally)
- Roll back to the starting point
- Create the next iteration's branch

### Section 8: Rollback Verdict

This section is **mandatory** and **load-bearing**. It is the single decision the brief must render. Everything above is evidence; this is the call.

```markdown
## Rollback Verdict

**Verdict:** `KEEP` | `ROLLBACK` | `PARTIAL_SALVAGE`

**Reasoning:** <2-4 sentences. Tie back to specific evidence in Sections 1–6.>

**Recommended action:**
- If `KEEP`: Merge the mission branch. List any follow-up tickets needed for flagged tests or open decisions.
- If `ROLLBACK`: Run the rollback ritual (see "The Rollback Ritual" below). State the top 1-3 things the next iteration must do differently. These become inputs to the next `breakdown` or `refine` pass.
- If `PARTIAL_SALVAGE`: List the specific commits, files, or sorties to cherry-pick onto a fresh branch from the starting point. Everything not on the cherry-pick list is discarded.
```

**How to render the verdict:**

| Signal | Lean toward |
|--------|-------------|
| All work units COMPLETED, low retry rate, ≤1 hard discovery, test cleanup removed <10% of mission tests | `KEEP` |
| Multiple BLOCKED or FATAL sorties, fundamental misunderstanding of the spec discovered mid-mission, test cleanup removed >30% of mission tests, planner-wrong outweighs agents-right | `ROLLBACK` |
| Foundation work is sound but later sorties went sideways, or one work unit succeeded while another failed irrecoverably | `PARTIAL_SALVAGE` |

**Honest defaults:** When in doubt between `KEEP` and `ROLLBACK`, err toward `ROLLBACK` for early iterations (1–2) where the cost of accumulating bad foundation is high, and toward `KEEP` for late iterations (3+) where the team has already spent meaningfully and incremental fixes are cheaper than another full pass.

The verdict token in this section MUST match the `Verdict:` field in the header. If they disagree, the brief is malformed — fix it before continuing.

---

## Trigger `clean` Automatically

Immediately after the brief file is written, the `brief` command **must** invoke `clean` (see `commands/clean.md`). This is mandatory and not user-prompted — the brief is the authoritative post-mission record, and the workspace must return to a pre-mission state before any rollback ritual or next-iteration work begins.

`clean` is now a thin stub that delegates archival to the [organize-agent-docs](../../organize-agent-docs/) skill. The single piece of state-transition logic that lives in mission-supervisor is: deciding the final `state:` value (`completed` vs `incomplete`) and writing it to each root-level mission file's frontmatter. After that, organize-agent-docs performs the actual moves, link updates in foundational files (AGENTS.md, CLAUDE.md, etc.), and date stamping.

Procedure:

1. Verify the brief file exists at `$PROJECT_ROOT/<OPERATION_NAME>_<NN>_BRIEF.md`.
2. Invoke `clean` against the same `$PROJECT_ROOT`. `clean` will:
   - Read SUPERVISOR_STATE.md.
   - Set `state: completed` on every root-level mission file if all work units are COMPLETED; otherwise `state: incomplete`.
   - Invoke `/organize-agent-docs organize $PROJECT_ROOT`, which moves files to `docs/complete/<slug>-<NN>/` or `docs/incomplete/<slug>-<NN>/` according to the `state:` field, rewrites links in foundational files, and stamps `updated:` dates on any foundational file it edited.
   - Report what was moved.
3. After the organizer reports success, the brief now lives at:
   ```
   docs/<outcome>/<slug>-<NN>/<OPERATION_NAME>_<NN>_BRIEF.md
   ```
   Use this path for any subsequent step (rollback ritual, references in user output).

Do **not** reintroduce archival logic into `brief.md` or `clean.md`. If the organizer fails, surface the error and stop — do not proceed to the rollback ritual with a half-archived workspace.

---

## The Rollback Ritual

Run only if the brief's Section 8 verdict is `ROLLBACK` (or `PARTIAL_SALVAGE` with cherry-pick instructions). For `KEEP`, skip this section entirely and report success.

After `clean` completes, for `ROLLBACK`:

1. **Verify the brief file exists at its archived path** (`docs/<outcome>/<slug>-<NN>/<OPERATION_NAME>_<NN>_BRIEF.md`).
2. **Verify the mission branch has all commits.**
3. **Confirm with the user:**
   ```
   Brief written and archived: docs/<outcome>/<slug>-<NN>/<OPERATION_NAME>_<NN>_BRIEF.md
   Mission branch preserved: <branch_name>

   Ready to roll back to starting point commit <hash>?
   This will create a new branch: mission/<slug>/<NN+1>
   The current branch (<branch_name>) will be preserved locally for reference.

   Proceed? [Y/N]
   ```
4. **On confirmation:**
   - Create new branch from the starting point commit:
     ```bash
     git checkout -b mission/<slug>/<NN+1> <starting_point_commit>
     ```
   - Carry the brief forward by checking it out from the mission branch at its archived path:
     ```bash
     git checkout <mission_branch> -- docs/<outcome>/<slug>-<NN>/<OPERATION_NAME>_<NN>_BRIEF.md
     git add docs/<outcome>/<slug>-<NN>/<OPERATION_NAME>_<NN>_BRIEF.md
     git commit -m "Carry iteration <NN> brief forward for reference"
     ```
   - Report:
     ```
     Rollback complete.
     Now on branch: mission/<slug>/<NN+1>
     Starting point: <hash>
     Previous iteration preserved on: <old_branch>
     Brief carried forward: docs/<outcome>/<slug>-<NN>/<OPERATION_NAME>_<NN>_BRIEF.md

     Resolve the open decisions in the brief before starting the next iteration.
     ```

---

## Integration with Mission Supervisor

### At `start` time — Record Starting Point

When the `start` command initializes a mission, it must:

1. Record the current HEAD commit as the **starting point commit**.
2. Create a mission branch if not already on one.
3. Store both in EXECUTION_PLAN.md frontmatter and SUPERVISOR_STATE.md.

**Frontmatter additions:**
```yaml
---
feature_name: OPERATION STEAMROLLER ORIGAMI
starting_point_commit: abc1234
mission_branch: mission/steamroller-origami/01
iteration: 1
---
```

**SUPERVISOR_STATE.md additions:**
```markdown
## Mission Metadata
- Starting point commit: `abc1234`
- Mission branch: `mission/steamroller-origami/01`
- Iteration: 1
```

### Branch Naming Convention

```
mission/<operation-name-slug>/<NN>
```

Where:
- `<operation-name-slug>` is the operation name (lowercase, hyphens, no "operation-" prefix). Example: `OPERATION STEAMROLLER ORIGAMI` → `steamroller-origami`
- `<NN>` is the two-digit iteration number

Examples:
- `mission/steamroller-origami/01`
- `mission/steamroller-origami/02`
- `mission/steamroller-origami/03`

### At completion time — Trigger Brief

When the completion handler (completion.md) finishes its final verification:

1. Output to user:
   ```
   Mission complete. Running post-mission brief...
   ```
2. Automatically invoke the `brief` command.

The user can also invoke `brief` manually at any time during or after the mission.

### At `resume` time — Detect Previous Iterations

When `resume` starts, check for existing brief files:

1. Glob for `*_BRIEF.md` in `$PROJECT_ROOT`.
2. If found, report:
   ```
   Previous iteration briefs found:
   - OPERATION_STEAMROLLER_ORIGAMI_01_BRIEF.md (Iteration 1)

   Current iteration: 2
   Starting point: <hash>
   ```
3. The agent should read previous briefs to understand what was learned.

---

## Archive

Archival is handled by the [organize-agent-docs](../../organize-agent-docs/) skill, invoked through the `clean` stub. See `commands/clean.md` for the delegation contract.

`brief` invokes `clean` automatically as its final step (see "Trigger `clean` Automatically" above). The brief and all other mission artifacts end up at `docs/<complete|incomplete>/<slug>-<NN>/`. Links in `AGENTS.md`, `CLAUDE.md`, and other foundational files that reference the moved files are rewritten automatically; the foundational files get an `updated:` frontmatter stamp.

---

## Personality

The brief is **honest, not diplomatic**. It names what went wrong without hedging. It credits what went right without false modesty. The tone is a post-flight debrief, not a retrospective ceremony.

- Don't say "there were some challenges with..." Say "the DTD validation failed because we didn't read the spec."
- Don't say "we could consider improving..." Say "this was wrong. Here's what to do instead."
- Don't pad. If a sortie was wasted work, say so. If the planner over-planned, say so.

The brief exists to make the next iteration better. Softening the truth makes the next iteration worse.
