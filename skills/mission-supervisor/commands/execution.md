---
type: docs
---

# Execution Engine — start / resume

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

This document defines the operational engine for the `start` and `resume` commands. It covers startup protocol, the core event loop, verification, sortie dispatch, dependency gating, state management, and error recovery.

**Referenced by**: `skill.md` § Argument Parsing → `start` and `resume` commands.

---

## 1. Startup Protocol

On every invocation, execute these steps in order before taking any action:

### Step 1: Read the Execution Plan

Read `$PROJECT_ROOT/EXECUTION_PLAN.md`. This document defines **what** gets done. **skill.md** defines **how** the supervisor operates: state machine, dispatch mechanics, completion-event handling, error recovery, and shutdown procedures.

If EXECUTION_PLAN.md and skill.md ever conflict on operational behavior (dispatch, state management, error handling), **skill.md wins**.

### Step 2: Parse the Execution Plan (Dynamic Detection)

The supervisor does NOT assume a fixed plan structure. Instead, analyze the plan using these detection heuristics:

#### 2a. Detect Work Units

Scan for work unit definitions. Detection priority:

1. **Package/component table**: A table with columns like "Package", "Component", "Module", "Phase" listing multiple items with sortie counts → each row is a work unit.
2. **Section-per-unit headers**: Multiple `## <Name>` sections each containing sortie definitions → each section is a work unit.
3. **Single project**: If no multi-unit structure is detected, the entire plan is **one work unit** named after the project directory or the plan's `# Title`.

Record each work unit's name, directory (if specified), and total sortie count.

#### 2b. Detect Sorties

For each work unit, find its sortie definitions. Detection priority:

1. **`## Sortie N:` headers**: Sections matching `## Sortie \d+[a-z]?:` (or legacy `## Sprint \d+[a-z]?:`) → each is a sortie. Compound sorties like `2a`, `2b` are separate sorties with an ordering dependency (2a before 2b).
2. **Sortie table**: A table with columns like "Sortie", "Name", "Description" → each row is a sortie.
3. **Numbered task lists**: `### Task N.M:` patterns within a section → group by the first number as sorties.
4. **Checklist groups**: Groups of `- [ ]` items under headers → each header group is a sortie.

Record each sortie's number/ID, name, description summary, entry criteria, exit criteria, and task list.

#### 2c. Detect Dependencies

Scan for dependency information between work units. Detection priority:

1. **Layer table**: A table with a "Layer" or "Tier" column → work units in the same layer run in parallel; higher layers wait for lower layers.
2. **Dependency graph**: ASCII art, mermaid diagrams, or `depends on` / `requires` / `preconditions` text → parse the edges.
3. **Sequential ordering**: `## Sortie N` headers with preconditions referencing prior sorties → sorties are sequential within the work unit; no cross-unit dependencies.
4. **No dependencies detected**: All work units can start in parallel.

Record dependencies as: `work_unit_A.sortie_X` must complete before `work_unit_B.sortie_Y` can start.

#### 2d. Detect Entry/Exit Criteria

For each sortie, look for:

1. **Checklist items**: `- [ ]` items in "Exit Criteria", "Entry Criteria", "Preconditions", "Validation" sections.
2. **Fenced code blocks**: Commands to execute as verification (typically under "Validate", "Execute", "Expected" labels).
3. **Dedicated rules section**: A section titled "Entry Checks", "Exit Checks", "Rules", or "Constraints".

Record each criterion with its type:

| Type | Meaning | Checked by |
|------|---------|-----------|
| `command` | Executable check (exit code or expected output) | Supervisor, §3d |
| `assertion` | Boolean check on repo/file state | Supervisor, §3b–3d |
| `judgment` | Qualitative but decidable from the diff alone (e.g. "every thrown error names the offending file path", "new public API follows the existing `load(from:)` naming"). Marked `[judgment]` in the plan. | Independent verifier agent, §3f |
| `checklist` | Needs a human's senses or environment (listen to audio, look at a UI on device) | User — `manual` task type |

A `judgment` criterion must still be specific enough that two reviewers would agree. "Code is clean" is not a judgment criterion — it is a vague criterion, and `refine` Pass 5 should have rejected it.

#### 2e. Detect Dispatch Template

Look for an explicit prompt template to use when dispatching sortie agents:

1. **Appendix D** or a section titled "Dispatch Template", "Sortie Prompt Template", "Agent Prompt" → use it verbatim (filling in variables).
2. **Supervisor config section**: YAML or fenced block with `template:` key.
3. **Not found**: Use dynamic prompt construction (Approach B below).

If a template is found, record it as the dispatch template (Approach A).

#### 2f. Detect External File References

Scan the plan for references to files like `PROGRESS.md`, `TODO.md`, status files, config files. For each:

1. Check if the file exists at the referenced path (relative to `$PROJECT_ROOT`).
2. If it exists, add it to the list of files sortie agents should read.
3. If it doesn't exist, note it as "will be created" — don't fail.

#### 2g. Classify Task Types

For each sortie, classify it by the kind of work involved. The type affects how the sortie is dispatched and verified:

| Type | Indicators | Verification |
|------|-----------|-------------|
| `code` | "Write", "Create", "Implement", "Build", "Fix" + code artifacts | Git commit exists + build/test pass |
| `command` | "Run", "Execute", "Deploy", explicit shell commands | Command output matches expected |
| `background` | "Start", "Kick off", "nohup", "background", estimated duration > 1hr | Process confirmed running |
| `deferred` | "Wait for", "Monitor", "Check deployment", external dependency | Poll verification command until success |
| `manual` | "Listen", "Visit", "Check browser", "Spot-check", human judgment | Report to user, mark PARTIAL until user confirms |

Default to `code` if no indicators match.

### Step 3: Read Your State

Read `$PROJECT_ROOT/SUPERVISOR_STATE.md` if it exists. This file contains your persistent state from previous invocations. If it does not exist, you are starting fresh.

### Step 4: Read Progress Files

For each work unit, read any progress/status files referenced in the plan (e.g., `PROGRESS.md`, `TODO.md`). Skip any that don't exist yet.

### Step 5: Reconcile State

Progress files and git state are ground truth. If SUPERVISOR_STATE.md disagrees with observed state, the observed state wins. Update your internal understanding accordingly.

### Step 6: Execute Command

- **`start`**: Begin from scratch. Execute the **MISSION INITIALIZATION SEQUENCE** in order:
  1. **Record Starting Point**: Capture current HEAD as the starting point commit: `git rev-parse HEAD`.
  2. **Detect Iteration Number**: Glob for `*_BRIEF.md` files in `$PROJECT_ROOT`. If found, extract the highest iteration number `NN` and set current iteration to `NN + 1`. Otherwise, iteration is `1`.
  3. **THE RITUAL**: Check for `feature_name` frontmatter in EXECUTION_PLAN.md. If missing, call `name-feature` to generate operation name and display ceremonial announcement.
  4. **Create Mission Branch**: Derive slug from operation name (lowercase, hyphens, drop "operation-" prefix). Create and switch to branch: `git checkout -b mission/<slug>/<NN>`. If the branch already exists (resuming from a previous partial start), switch to it without creating.
  5. **Update Frontmatter**: Add/update EXECUTION_PLAN.md frontmatter with `starting_point_commit`, `mission_branch`, and `iteration` fields. **Preserve the OKF `type: execution-plan` key** already present from `breakdown` (see skill.md § Mission Documents & OKF Types) — these additions must not drop it. If for any reason `type:` is absent, add `type: execution-plan`.
  6. **Initialize State**: Create SUPERVISOR_STATE.md with Mission Metadata section including starting point commit, mission branch, and iteration number.
  7. **Pre-Build Clean** (Swift/Xcode projects only): Remove the project's DerivedData and run its clean-build target once, before any sortie is dispatched, so every build-gate verification in this mission (see §3e, `code` task type) starts from a known-clean artifact state. This step does **not** touch the dependency graph. See *Pre-Build Clean* below for details, scoping rules, and the resume exception.
  8. **Dispatch**: Dispatch Sortie 1 for each work unit that has no unsatisfied dependencies.
- **`resume`**: Pick up where the last supervisor left off. Read state, determine what sorties need dispatching, continue. Reset any `FATAL` or `REPLAN` sortie to `PENDING` and its work unit to `RUNNING` (for REPLAN, confirm EXECUTION_PLAN.md has changed since the REPLAN was logged — if it hasn't, say so and leave the work unit BLOCKED). Agents from a previous supervisor session can't be reached, so a `PARTIAL` sortie continues with a fresh agent (§4g), and any agent still listed as active is re-checked with a single `TaskOutput` and otherwise treated as lost. **Do not re-run the pre-build clean on resume** — see *Pre-Build Clean* below.

---

## 1a. Pre-Build Clean

The supervisor performs **one** artifact clean at mission start, before any sortie dispatch, so that every build-gate verification (§3e, `code` task type) and every cross-work-unit build check (§5) starts from a known-clean artifact state rather than inheriting stale objects from whatever the developer was last doing.

**This step is deliberately scoped to build artifacts. It does not touch the dependency graph.** See *Why this is not a dependency purge* below — that boundary is load-bearing and must not be relaxed.

### When it runs

- **`start` only.** Never on `resume`. Resuming means earlier sorties already committed against a particular resolved graph and a particular set of build products; wiping artifacts mid-mission just forces every remaining build-gate sortie to pay a full rebuild for no benefit.
- **Swift/Xcode projects only.** Detect by presence of `Package.swift` or any `*.xcodeproj` at the work-unit directory (or `$PROJECT_ROOT` for single-unit missions). For multi-work-unit missions where some units are Swift and some aren't, clean once per Swift work-unit directory.
- **Skip silently** if neither marker is present. Do not error, do not log noise. Most non-Swift missions should see zero overhead from this step.

### What it does

Exactly two things:

1. **Remove the project's DerivedData.**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*
   ```
   `${PROJECT_NAME}` is the `.xcodeproj` directory name with the suffix stripped. The glob matches Xcode's hash-suffixed directories.

2. **Run the project's clean-build target.** Prefer a `make` target if one exists (`make clean`, then `make help` to discover the project's own naming). Fall back to the project's XcodeBuildMCP clean action. Never invoke `swift build` or `swift test`.

That is the whole step. Do not add anything to it.

### What it explicitly does NOT do

| Not done | Why |
|----------|-----|
| Clear the global SPM cache (`~/Library/Caches/org.swift.swiftpm`) | It is global. Wiping it forces every other Swift project on the machine to re-download its dependencies. A mission on one repo must not impose a rebuild tax on unrelated repos. |
| Delete `Package.resolved` | The resolved graph is the reproducibility record. Deleting it re-rolls every transitive version at mission start — the mission then builds against a graph nobody chose and CI never validated. |
| Bump `intrusive-memory/*` floors in `Package.swift` | **This is a dependency decision, not build hygiene.** See below. |

### Why this is not a dependency purge

An earlier version of this step invoked `/dependency-purge`, which additionally bumped every `intrusive-memory/*` floor to its latest published release. **That was removed because it caused a mission-stopping failure.**

Raising a floor does not merely "prefer newer" — it **removes the resolver's room to backtrack**. On a package graph containing an unstable transitive dependency, deleting the backtrack path converts a solvable graph into an unsolvable one. In OPERATION BOOKEND STAMP (Produciesta, 2026-06-28) the preflight bump of SwiftProyecto 4.0.0→4.1.0 made the app `xcodeproj` unresolvable, because 4.x dragged in an unstable SwiftAcervo 0.x. CI stayed green throughout, because CI builds from the base manifest with the original floor. The mission stalled on a failure the supervisor had introduced, and the fix was to revert the bump.

The general rule this encodes:

> **An automatic preflight step must never make a dependency decision.** Bumping a floor changes what the project builds against, is invisible to CI until it fails, and deserves a human and a pull request. Build hygiene is disposable and reversible; dependency resolution is neither.

If a mission genuinely needs newer dependency floors, that belongs in a sortie with its own exit criteria and its own commit — not in a preflight step that runs before anyone is watching.

### Cost and trade-offs

- **Adds seconds to a couple of minutes** at mission start — a local artifact wipe and clean, no network.
- **Does not affect other projects on this machine.** This is the main improvement over the old purge.
- **Does not change dependency resolution at all**, so the mission builds against exactly the graph CI validates.

### Failure handling

- If the DerivedData removal fails (permissions, path not found), log it to the `SUPERVISOR_STATE.md` Decisions Log and **proceed with mission dispatch**. A missing DerivedData directory is the desired end state anyway.
- If the clean target fails, log it, warn the user, and **proceed**. A failed clean is a downgrade in confidence, not a stop — the build-gate sorties will surface any real breakage through their own exit criteria.
- Never let this step block dispatch. It is hygiene, not a gate.

### Recording in state

Add to `SUPERVISOR_STATE.md` Mission Metadata at the end of initialization:

```markdown
- Pre-build clean: <run|skipped (non-Swift)|failed>
- Clean ran at: <ISO-8601 timestamp>
- Dependency graph: untouched (no floor bumps, no Package.resolved deletion, no SPM cache clear)
```

### Relationship to the failure-recovery purge

`/dependency-purge` is **still available as a mid-mission recovery tool** when a sortie fails with a known cache-fixable pattern (see [/dependency-purge skill.md](../../dependency-purge/skill.md) § "Integration with Mission Supervisor"). It is no longer run preemptively.

**Carry the same caution into recovery.** That skill's Step 5 still bumps `intrusive-memory/*` floors, and it is just as capable of breaking resolution during recovery as it was during preflight — arguably worse, since it fires when something is already wrong. When invoking it to recover a failed sortie:

1. Prefer the artifact-only remedies first (DerivedData, clean), which is what this preflight step now does.
2. If you escalate to a full `/dependency-purge` and it rewrites `Package.swift`, **verify resolution succeeds before dispatching the retry.** If resolution breaks, revert the floor changes and log it.
3. Never let a recovery purge silently change floors in the mission's final diff. Surface any `Package.swift` change in the brief.

---

## 2. Core Loop — Event-at-a-Time Processing

Once startup is complete (for `start` or `resume`), the supervisor operates as an **event processor**, not a monolithic scanner. Each iteration handles exactly one event, updates state, and determines the next action.

### Phase 1: Initial Dispatch

Identify all work units in `RUNNING` state with sortie state `PENDING`. Dispatch their next sortie as background agents (all eligible work units in parallel). Update SUPERVISOR_STATE.md. Output a status update.

### Phase 2: Event Loop

The loop is **driven by completion notifications, not polling.** Background agents run detached, and the harness re-invokes the supervisor with a notification when each one finishes. Between events the supervisor does nothing — it does not call `TaskOutput` in a loop, sleep, or "check in". Every poll result that says "still running" is context the supervisor pays for and learns nothing from, and on a long mission that waste is what forces compaction.

Repeat until all work units are `COMPLETED` or all active work units are `BLOCKED`/`STOPPED`:

```
1. WAIT: End the turn. The next event is one of:
   - a completion notification for one agent (a sortie agent or a verifier agent), or
   - the watchdog timer firing (WATCHDOG_TICK, every 20 minutes — §7 *Stuck Agent Watchdog*).
   Never poll between events to find out.
2. IDENTIFY: If the event is WATCHDOG_TICK, run the watchdog check (§7), then go to step 4
   (a kill puts a sortie in BACKOFF, which step 4 re-dispatches). Otherwise match the
   notification's agent ID to a row in the Active Agents table.
3. PROCESS the completed agent — exactly one of these outcomes:
   a. SUCCESS: Mechanical verification (§3a–3e) confirms sortie done.
      → If the sortie has [judgment] criteria: set sortie state to VERIFYING and
        dispatch the verifier (§3f). Stop processing this event here.
      → Otherwise: set sortie state to COMPLETED.
        → If more sorties remain: set next sortie to PENDING.
        → If no more sorties: set work unit state to COMPLETED.
   b. VERIFIER RESULT (the completed agent was a verifier):
      → PASS: sortie state → COMPLETED (then as in 3a).
      → FAIL, verifier rounds remain: sortie state → PARTIAL; the verifier's
        findings become the continuation's remaining work.
      → FAIL, verifier rounds exhausted: treat as FAILURE (3d).
   c. PARTIAL: Verification shows partial progress.
      → Set sortie state to PARTIAL.
      → Will be continued in step 4.
   d. FAILURE: Agent exited without completing, or verification failing.
      → Increment attempt counter.
      → If attempts < max_retries: set sortie state to BACKOFF.
      → If attempts >= max_retries: set sortie state to FATAL, work unit state to BLOCKED.
      → Log failure details in Decisions Log.
   e. REPLAN: Agent output contains a REPLAN report (§4d Part 4).
      → Set sortie state to REPLAN, work unit state to BLOCKED.
      → Do NOT increment the attempt counter.
      → Log the report in the Decisions Log and surface it to the user (§7).
   f. CONTEXT EXHAUSTION: Agent hit its turn/context limit without completing.
      → Run verification checks to assess state.
      → Treat as FAILURE (increment attempt) or PARTIAL (if progress was made).
4. DISPATCH: For each work unit in RUNNING state with sortie in PENDING, PARTIAL, or BACKOFF:
   → PENDING / BACKOFF: run model selection, log it, dispatch a NEW background agent.
     For BACKOFF, use the augmented prompt referencing the previous failure.
   → PARTIAL: continue the SAME agent with SendMessage when eligible (§4g);
     otherwise dispatch a new continuation agent.
   → Update sortie state to DISPATCHED.
5. GATE CHECK: After any work unit reaches COMPLETED, check dependency gates:
   → For each NOT_STARTED work unit, check if all its dependencies are now COMPLETED.
   → Newly eligible work units: set to RUNNING, first sortie to PENDING.
6. STATE WRITE: Update SUPERVISOR_STATE.md with all changes from this iteration.
7. STATUS: Output a status update to the user.
8. TERMINATION CHECK:
   → All work units COMPLETED → output final summary.
   → All active work units BLOCKED (FATAL or REPLAN) → report to user, wait for intervention.
   → Otherwise → return to step 1.
```

### Key Principles

- **Process one event at a time.** Don't batch decisions. Complete one agent's result processing before moving to the next. If several notifications arrive together, process them one after another.
- **State transitions drive dispatch.** The supervisor never "decides" to dispatch — it reacts to state changes. A sortie enters PENDING → it gets dispatched. A work unit enters RUNNING → its first sortie enters PENDING.
- **Write state before dispatching.** Always update SUPERVISOR_STATE.md with the result of processing BEFORE dispatching the next agent. This ensures crash-safety.
- **Silence alone is not a signal; stalled progress is.** An agent that has not notified is assumed to be working — builds and test suites legitimately run long. The watchdog (§7) kills an agent only after three consecutive 20-minute checks show *no progress at all*, not merely because it is still running.

---

## 3. Verification

When a sortie agent completes, determine its outcome using a **verification cascade**. Check each source in order; use the first source that provides a definitive answer:

### 3a. Agent Output

Read the agent's final report from the completion notification. (Use `TaskOutput` only if the notification did not include the result — once, not in a loop.) Look for:
- Explicit success signals: "completed", "all checks pass", "committed", "done"
- Explicit failure signals: "failed", "error", "blocked", "could not"
- Partial signals: "partial", "incomplete", "remaining", "continued in next"
- **REPLAN report**: a block beginning `REPLAN:` (format in §4d Part 4). A REPLAN report ends the cascade — do not keep checking git or progress files to "find" a success. The agent has told you the plan cannot be carried out as written.

### 3b. Git State

Check the work unit's directory (or project root for single-unit plans):
```bash
git log --oneline -3 --since="1 hour ago" -- <work_unit_dir>
git status --porcelain -- <work_unit_dir>
```
- New commits since dispatch → indicates progress
- Uncommitted changes → partial work or in-progress

### 3c. Progress Files

Read any progress/status files the plan references (PROGRESS.md, TODO.md, etc.):
- Any format is accepted — look for sortie completion markers, status keywords, checklist items
- `(partial)`, `incomplete`, `in progress` → PARTIAL
- `complete`, `done`, `passing` → SUCCESS

### 3d. Exit Criteria Commands

If the plan specifies executable exit criteria for this sortie (detected in Step 2d), run them:
- Commands that return exit code 0 → criterion passes
- Commands whose output matches expected text → criterion passes
- Any failing criterion → NOT yet complete

### 3e. Task-Type-Specific Checks

Based on the sortie's task type (from Step 2g):

| Type | Verification |
|------|-------------|
| `code` | Git commit exists for this sortie's scope + build/test commands pass (if specified) |
| `command` | Command output captured in agent output matches expected output from the plan |
| `background` | Process is running (`ps aux \| grep` or similar from plan) |
| `deferred` | Run the verification command from the plan as a background wait (§7 *Deferred Sortie Handling*); success = done, still failing = still waiting |
| `manual` | Report findings to user; mark PARTIAL until user explicitly confirms via resume |

### 3f. Independent Verifier (judgment criteria only)

Runs **only after §3a–3e all pass**, and only for sorties whose exit criteria include `[judgment]` items. It is an extra gate on top of the mechanical checks, never a replacement for them: a verifier cannot mark a sortie COMPLETED whose build or tests fail.

**Why a separate agent**: the implementing agent grading its own work is the weakest check available — it wrote the code believing it met the criteria. The verifier gets the diff and the criteria and nothing else, so it reads the change the way a reviewer would.

**Dispatch** (background, via the Agent tool):
- **Model**: `sonnet`. Judging a diff against a short list of specific criteria is not opus-level work; escalate to `opus` only if a previous verifier round returned an unclear verdict.
- **Context**: the `[judgment]` criteria for this sortie, verbatim, and the diff range (`git diff <sortie_start_commit>..HEAD -- <work_unit_dir>`). Do **not** include the implementer's report, reasoning, or the rest of the execution plan.
- **Prompt**:
  ```
  You are an independent reviewer. Read the diff with:
    git -C $PROJECT_ROOT diff <sortie_start_commit>..HEAD -- <work_unit_dir>
  For each criterion below, decide PASS or FAIL from the diff alone.
  For every FAIL, cite the file and line and state the concrete change that would make it pass.
  Do NOT modify any files.

  CRITERIA:
  <[judgment] criteria verbatim>

  End your reply with exactly one line: VERDICT: PASS  or  VERDICT: FAIL
  ```
- Record `<sortie_start_commit>` in the Active Agents row when the sortie is first dispatched so the diff range is stable across continuations.

**Processing the verdict** (event loop step 3b):
- `VERDICT: PASS` → COMPLETED.
- `VERDICT: FAIL` → PARTIAL, with the verifier's cited findings as the continuation's remaining work. Increment the sortie's verifier round counter.
- Missing or malformed verdict → treat as FAIL with the finding "verifier returned no verdict", and escalate the next verifier to `opus`.
- Verifier FAIL after `max_verifier_rounds` (default 2) → FAILURE: sortie → BACKOFF, attempt counter increments.

The verifier never edits files and never talks to the implementer. Its findings go through the supervisor.

### Verification Decision

- If **any source** gives definitive SUCCESS and no source contradicts it → COMPLETED (or VERIFYING, if `[judgment]` criteria exist)
- If the agent filed a REPLAN report → REPLAN
- If progress was made but work remains → PARTIAL
- If no progress and agent exited → FAILURE
- If ambiguous → favor PARTIAL over FAILURE (preserve work)

---

## 4. Sortie Dispatch — Background Agents

### 4a. Model Selection

Before dispatching a sortie, select the appropriate Claude model based on task characteristics. **Sergeant principle: right tool for the job.** Don't waste expensive models on simple tasks. The model choice balances cost against task complexity — when in doubt, start cheaper and upgrade on retry if needed.

#### Model Capabilities & Cost

| Model | Use Case | Relative Cost |
|-------|----------|---------------|
| `haiku` | Simple, well-defined tasks with clear requirements | 1x (cheapest) |
| `sonnet` | Standard tasks requiring balanced capability and cost | 10x |
| `opus` | Complex, ambiguous, or architecturally critical tasks | 30x (most expensive) |

#### Selection Criteria

Evaluate each sortie on these dimensions to compute a complexity score:

**1. Task Complexity (0-10 points)**
- Estimated turns from context fitness check:
  - <10 turns: 1 point
  - 10-20 turns: 3 points
  - 21-35 turns: 5 points
  - 36-50 turns: 8 points
  - >50 turns: 10 points
- Files to create or modify:
  - 1-2 files: +0 points
  - 3-5 files: +2 points
  - 6-10 files: +4 points
  - 11+ files: +6 points

**2. Task Ambiguity (0-5 points)**
- Exit criteria quality:
  - All machine-verifiable, specific commands: 0 points
  - Mix of machine/manual verification: 2 points
  - Vague criteria ("works correctly", "properly handles"): 5 points
- Task description clarity:
  - Explicit file paths, function names, clear steps: 0 points
  - High-level goals without implementation details: 3 points
  - Open-ended ("improve", "optimize", "enhance"): 5 points

**3. Foundation Importance (0-5 points)**
- Foundation score = 0 (leaf sortie): 0 points
- Foundation score = 1 (establishes patterns for 2+ sorties): 5 points
- Dependency depth:
  - 0-1 dependents: 0 points
  - 2-5 dependents: 2 points
  - 6+ dependents: 5 points

**4. Risk Level (0-5 points)**
- Simple CRUD or config: 1 point
- File I/O or system calls: 2 points
- Complex algorithms: 3 points
- New technology/unfamiliar patterns: 4 points
- External API calls or integrations: 5 points

**5. Task Type Modifier**
- `code` type: Base score (no modifier)
- `command` type: -3 points (well-defined, deterministic)
- `background` type: -3 points (just needs to start process)
- `deferred` type: -2 points (polling is straightforward)
- `manual` type: -1 point (reporting findings is simple)

#### Model Selection Algorithm

Compute the complexity score (sum of all dimensions above), then select the model:

```
complexity_score = task_complexity + task_ambiguity + foundation_importance + risk_level + task_type_modifier
```

| Complexity Score | Model | Rationale |
|-----------------|-------|-----------|
| ≤ 5 | `haiku` | Simple, well-defined task. Haiku is sufficient and most cost-effective. |
| 6-12 | `sonnet` | Standard complexity. Sonnet balances capability and cost. |
| ≥ 13 | `opus` | High complexity, ambiguity, or critical foundation work. Opus provides maximum capability. |

#### Override Conditions

**Force Opus** (regardless of score):
- Sortie is in BACKOFF state with 2+ prior failures (previous model wasn't sufficient)
- Sortie establishes core architectural patterns (foundation_score = 1 AND dependency_depth ≥ 5)
- Sortie has open questions or TBDs detected during completeness analysis

**Force Sonnet** (minimum model):
- Sortie is in PARTIAL state (continuation from partial work — maintain consistency with prior model or upgrade)
- Sortie is in first attempt but has vague exit criteria (need capable model for self-verification)

#### Log Model Selection

Record the model selection decision in the Decisions Log:

```markdown
## Decisions Log
| Timestamp | Work Unit | Sortie | Decision | Rationale |
|-----------|-----------|--------|----------|-----------|
| <ISO 8601> | <name> | <N> | Model: opus | Complexity score 15 (high risk, new technology, 6 dependents) |
```

### 4b. Dispatch Parameters

When dispatching a sortie, use the **Agent tool** (named `Task` in older harnesses) with these parameters:

```
subagent_type: "general-purpose"
model: <selected_model>  # "haiku", "sonnet", or "opus" from model selection
run_in_background: true  # only on harnesses that expose it; current harnesses run subagents in the background by default
max_turns: 50            # only on harnesses that expose it
name: <work_unit>-s<ID>  # a stable, addressable name so the agent can be continued with SendMessage (§4g)
```

### 4c. Approach A: Explicit Template (if detected in Step 2e)

Use the dispatch template from the plan, filling in variables:
- Work unit name, directory, sortie number/ID, sortie name
- Section references, file paths, any other template variables
- Replace ALL hardcoded paths with `$PROJECT_ROOT`-relative paths

### 4d. Approach B: Dynamic Prompt Construction (if no template found)

Construct the prompt from four parts. **Remember: sergeant principles apply.** Give the agent ONE clear goal, lean context, and measurable success criteria.

**Part 1 — Context** (files to read, ONLY what's needed):
```
You are working on <work_unit_name> in $PROJECT_ROOT/<work_unit_dir>/.

FIRST, read these files in order:
1. $PROJECT_ROOT/EXECUTION_PLAN.md
<for each referenced file that exists:>
N. $PROJECT_ROOT/<file_path>
```

**Part 2 — Assignment** (verbatim sortie definition):
```
You are executing Sortie <ID>: <sortie_name>.

<Paste the sortie's full definition from the execution plan verbatim, including all tasks, commands, expected outputs, and notes.>
```

**Part 3 — Checks** (entry/exit criteria):
```
ENTRY CRITERIA (verify before starting):
<list entry criteria from the plan, or "None — this is the first sortie" if applicable>

EXIT CRITERIA (verify before declaring done):
<list exit criteria from the plan>
```

**Part 4 — Boundaries** (scope limits):
```
IMPORTANT:
- Do NOT start the next sortie. Your scope ends after this sortie.
- Do NOT modify EXECUTION_PLAN.md.
<For background tasks:>
- This sortie is complete once the process is confirmed running. Do NOT wait for it to finish.
<For deferred tasks:>
- Check the specified condition. If not met, report what you found and stop.
<For manual tasks:>
- Perform the checks described and report your findings. Do NOT mark this as complete — the user will verify.

IF THE PLAN ITSELF IS WRONG:
If you find that this sortie cannot be completed as written because the plan is
wrong — a premise is false, a file/API/tool it references does not exist, it
conflicts with an earlier sortie's committed work, or its exit criteria contradict
each other — STOP. Do not improvise a different design, and do not report failure.
Commit nothing further, and end your reply with:

REPLAN:
- Defect: <what in the plan is wrong, one sentence>
- Evidence: <file paths, command output, or doc references that prove it>
- Proposed change: <the smallest edit to EXECUTION_PLAN.md that would fix it>
- Affected sorties: <this sortie and any later sorties the change touches>

Use REPLAN only for plan defects. A bug in your own code, a failing test you can
fix, or a hard problem is NOT a plan defect — keep working or report failure.
```

**REPLAN is a narrow escape hatch.** Agents under pressure will reach for it to avoid hard work. The supervisor checks the evidence before accepting it (§7 *REPLAN Handling*); a REPLAN without concrete evidence is processed as a FAILURE.

### 4e. Tracking Background Agents

When a background agent is dispatched, the tool returns its agent ID (and, on some harnesses, an `output_file` path). Record these in SUPERVISOR_STATE.md:

```markdown
## Active Agents
| Work Unit | Sortie | Role | Sortie State | Attempt | Verifier Round | Model | Complexity Score | Agent ID / Name | Sortie Start Commit | Output File | Dispatched At | Watchdog Strikes | Last Snapshot |
|-----------|--------|------|-------------|---------|----------------|-------|-----------------|-----------------|---------------------|-------------|---------------|------------------|---------------|
| <name> | <N> | implementer | DISPATCHED | 1/3 | 0/2 | sonnet | 8 | <id> / <work_unit>-s<N> | <sha> | <path or —> | <timestamp> | 0/3 | <output size, HEAD, status hash> |
| <name> | <N> | verifier | VERIFYING | 1/3 | 1/2 | sonnet | — | <id> | <sha> | <path or —> | <timestamp> | 0/3 | <…> |

## Watchdog
- Timer task ID: <id or "disarmed">
- Armed at: <timestamp>
```

- **Role**: `implementer` (the sortie agent) or `verifier` (§3f).
- **Sortie State**: Must be one of `DISPATCHED`, `RUNNING`, `VERIFYING`, `BACKOFF`, `PARTIAL`. Use the formal sortie states defined in the State Machine section of skill.md.
- **Agent ID / Name**: Needed to match completion notifications to rows and to continue the agent with SendMessage (§4g).
- **Sortie Start Commit**: `git rev-parse HEAD` at the sortie's *first* dispatch. Fixed for the life of the sortie; the verifier diffs against it.
- **Watchdog Strikes / Last Snapshot**: consecutive no-progress checks and the progress snapshot from the last check (§7 *Stuck Agent Watchdog*).
- **Attempt**: `<current>/<max_retries>`. Increments each time a sortie is re-dispatched due to failure.
- **Model**: The Claude model used for this sortie (`haiku`, `sonnet`, or `opus`).
- **Complexity Score**: The computed score from model selection for auditability.

When a completion notification arrives, run verification (Section 3) to confirm the sortie outcome.

### 4f. Completion Notifications (no polling)

- After dispatching, write SUPERVISOR_STATE.md, output a status update, and **end the turn**. The harness re-invokes the supervisor when an agent completes.
- Do not call `TaskOutput` to check whether an agent is done. Use it only to fetch a finished agent's result if the notification did not carry it.
- Two legitimate timed waits exist, and both run as single background shell commands whose exit is the event — never as a supervisor loop:
  - a `deferred` sortie's external condition, which the harness cannot see (§7 *Deferred Sortie Handling*);
  - the stuck-agent watchdog timer, every 20 minutes (§7 *Stuck Agent Watchdog*).
- On harnesses that do not deliver completion notifications (older Claude Code), fall back to a blocking `TaskOutput(block: true)` on one agent at a time. Still never spin on `block: false`.

### 4g. Continuing a PARTIAL Sortie in the Same Agent

A PARTIAL sortie's agent has already read the plan, explored the code, and built a working picture of the problem. A fresh continuation agent pays for all of that again and often gets it slightly different. So PARTIAL continues the **same** agent via `SendMessage` when it is eligible:

| Condition | Continue same agent (SendMessage) | Dispatch fresh agent |
|-----------|:---:|:---:|
| PARTIAL from normal verification or a verifier FAIL | ✓ | |
| PARTIAL because the agent hit its turn/context limit | | ✓ — its context is full; that is why it stopped |
| Previous model was `haiku` (below the PARTIAL minimum of `sonnet`) | | ✓ on `sonnet` |
| Agent is no longer addressable (supervisor restarted via `resume` in a new session, SendMessage errors) | | ✓ |
| BACKOFF (a failure, not partial progress) | | ✓ — always fresh |

**Why BACKOFF is always fresh**: a failed agent's context usually contains the wrong turn that made it fail — a misread requirement, a dead-end approach it is attached to. Continuing it tends to repeat the failure. A clean agent, on a stronger model when attempts ≥ 2, is the better retry.

**Continuation message** (sent with SendMessage to the recorded agent name/ID):
```
Sortie <ID> is not finished. Remaining work:
<unmet exit criteria, or the verifier's cited findings, verbatim>

Complete only this remaining work, re-run the exit criteria, and report as before.
The boundaries from your original orders still apply.
```

If SendMessage fails, log it in the Decisions Log and fall back to a fresh continuation agent with the §4d prompt plus the remaining-work list. Either way the attempt counter does not change.

---

## 5. Dependency Gating

After any work unit's sortie completes, check if the completion unlocks other work:

### Within a Work Unit
Sorties are sequential. Sortie N+1 cannot start until Sortie N is COMPLETED. Compound sorties (e.g., 2a, 2b) are sequential sub-sorties: 2a must complete before 2b starts.

### Across Work Units
Use the dependency graph detected in Step 2c:

1. When a work unit reaches COMPLETED, scan all NOT_STARTED work units.
2. For each NOT_STARTED work unit, check if ALL its dependencies are now COMPLETED.
3. If all dependencies are satisfied:
   - Set the work unit to RUNNING.
   - Set its first sortie to PENDING.
   - If the plan specifies verification commands for the dependency (e.g., build checks), run them before dispatching.
4. If dependency verification fails, log the failure and leave the work unit as NOT_STARTED. Report to user.

### No Dependencies Detected
If no dependency structure was found in the plan, all work units start in parallel at `start` time.

---

## 6. State Management

After EVERY action (dispatch, completion event, status check, decision), update `$PROJECT_ROOT/SUPERVISOR_STATE.md`.

### Per-Work-Unit State Block

Each work unit section in SUPERVISOR_STATE.md must include:

```markdown
### <WorkUnitName>
- Work unit state: NOT_STARTED | RUNNING | COMPLETED | STOPPING | STOPPED | BLOCKED | KILLED
- Current sortie: <ID> of <total>
- Sortie state: PENDING | DISPATCHED | RUNNING | VERIFYING | COMPLETED | PARTIAL | BACKOFF | FATAL | REPLAN
- Sortie type: code | command | background | deferred | manual
- Model: haiku | sonnet | opus
- Complexity score: <N> (from model selection)
- Attempt: <current> of <max_retries>
- Verifier round: <current> of <max_verifier_rounds> (only for sorties with [judgment] criteria)
- Agent: <agent ID / name of the current implementer, for SendMessage continuation>
- Last verified: <what was confirmed>
- Notes: <any issues>
```

**Use the formal state names from the State Machine section in skill.md. Do not invent new state names.**

### Fields to Keep Current

- Per-work-unit state block (above)
- Active Agents table (task IDs, sortie states, attempt counters, output files)
- Decisions Log (table of significant decisions, errors, and resolutions)
- Overall status summary

**Write state early and often.** The supervisor may be interrupted or exhaust its context at any time. Every piece of state that is not in SUPERVISOR_STATE.md is lost.

### Plan Metadata

At the top of SUPERVISOR_STATE.md, record the plan structure detected in Step 2:

```markdown
## Plan Summary
- Work units: <count>
- Total sorties: <count>
- Dependency structure: <layers|sequential|parallel|none>
- Dispatch mode: <template|dynamic>

## Work Units
| Name | Directory | Sorties | Dependencies |
|------|-----------|---------|-------------|
| <name> | <dir> | <count> | <deps or "none"> |
```

---

## 7. Error Recovery

All error recovery follows the state machine. The supervisor does not invent ad-hoc recovery — it transitions sortie/work unit states and lets the event loop react.

### Sortie Agent Completes Successfully
Sortie state: RUNNING → COMPLETED. Normal path. Verification confirms sortie done. Next sortie (if any) enters PENDING. Event loop dispatches it.

### Sortie Agent Commits Partial Work
Sortie state: RUNNING → PARTIAL. Verification shows partial progress. The event loop continues the sortie per §4g:
- **Same agent when eligible**: SendMessage the remaining work to the agent that made the progress. It keeps its context and its model.
- **Fresh agent otherwise** (context exhausted, previous model was haiku, agent unreachable): use the same model as the previous attempt or upgrade to `sonnet` (minimum model for PARTIAL).
- **Continuation prompt**: List only the remaining work from the exit criteria that wasn't completed (or the verifier's findings).
- **No attempt increment**: Partial work is progress, not failure. The attempt counter stays the same.

### Sortie Agent Fails
Sortie state: RUNNING → BACKOFF (attempt counter increments). The event loop dispatches a **new** retry agent (never a SendMessage continuation — see §4g) with:
- **Model selection re-run**: Re-evaluate model. If attempt ≥ 2, the override condition forces `opus` (previous model was insufficient). **This is where you upgrade** — start cheap, learn from failure, send a stronger model.
- **Augmented prompt**: "Sortie N failed on attempt M. Here is what went wrong: <details from agent output>. Fix the issues, then complete the sortie."

If attempt counter reaches `max_retries`: sortie state → FATAL, work unit state → BLOCKED. No further automatic dispatch. Report to user.

### Sortie Agent Exhausts Context Without Completing
Check verification cascade (Section 3):
- If partial progress detected: sortie state → PARTIAL.
- If no progress: sortie state → BACKOFF (attempt counter increments).

### Sortie Agent Exceeds max_turns
On harnesses with a turn cap, the agent returns when it hits the cap (50 turns). Run verification:
- If completed: treat as SUCCESS (sortie state → COMPLETED).
- If partial: treat as PARTIAL.
- If nothing: treat as context exhaustion (above).

### FATAL / BLOCKED Recovery
When a sortie enters FATAL:
1. Work unit state → BLOCKED immediately.
2. Log in Decisions Log: sortie number, all attempt details, failure reasons.
3. Output to user:
   ```
   BLOCKED: <work_unit> Sortie N failed after <max_retries> attempts.
   Last failure: <brief description>
   To retry: /mission-supervisor resume
   (resume resets the sortie to PENDING and the work unit to RUNNING)
   ```
4. The supervisor continues operating other non-blocked work units normally.

### REPLAN Handling
When a sortie agent files a REPLAN report (§4d Part 4):
1. **Check the evidence.** Run or read what the report cites. If the evidence is missing, vague, or does not show a *plan* defect (it shows a bug the agent could have fixed), process the result as a FAILURE instead and log `REPLAN rejected: <reason>`.
2. If the evidence holds: sortie state → REPLAN, work unit state → BLOCKED. The attempt counter does **not** change.
3. Log the full report in the Decisions Log.
4. Output to user:
   ```
   REPLAN: <work_unit> Sortie N — the plan cannot be executed as written.
   Defect: <defect>
   Evidence: <evidence>
   Proposed change: <proposed change>
   Affected sorties: <list>
   To proceed: edit EXECUTION_PLAN.md (or run /mission-supervisor refine), then /mission-supervisor resume
   ```
5. **Do not edit EXECUTION_PLAN.md yourself**, even when the proposed change looks obviously right. The plan is the human's document during execution.
6. The supervisor continues operating other non-blocked work units normally — unless the affected-sorties list reaches into them, in which case stop dispatching those work units too and say so.

On `resume`, a REPLAN sortie is reset to PENDING and re-dispatched fresh against the amended plan.

### Stuck Agent Watchdog
Missions run unattended (overnight), so a hung agent must not wait for a human. The watchdog checks every active agent every **20 minutes** and kills an agent on its **third consecutive check with no progress**. Worst case, a hung agent is killed about 60 minutes after it stopped doing anything.

**The timer.** Completion notifications give the supervisor no clock, so the watchdog makes one: a single background shell command whose exit is the event.
```bash
# Bash tool, run_in_background: true
sleep 1200; echo WATCHDOG_TICK
```
- **Arm** it when the first agent is dispatched and no timer is armed. Record the timer's task ID and arm time in SUPERVISOR_STATE.md (`## Watchdog`).
- **Re-arm** it after each tick if any agent is still active. Never run more than one timer.
- **Disarm** it (TaskStop the timer) when no agents are active, and in `stop` Phase 3 and `killall`.
- `deferred` wait shells are not agents and are not watched; they have their own 20-check budget.

**The check** (on each WATCHDOG_TICK, for every row in Active Agents — implementers and verifiers):
1. Take a progress snapshot:
   - **Agent output**: size and mtime of the agent's `Output File`. If the harness gave no output file, one `TaskOutput(block: false)` call per agent per tick is allowed; compare the output length.
   - **Repo activity** in the work unit's directory: `git rev-parse HEAD` and a hash of `git status --porcelain -- <work_unit_dir>`.
2. Compare with the snapshot stored from the previous tick.
   - **Anything changed** → progress. Set the agent's `Watchdog Strikes` to 0.
   - **Nothing changed** → increment `Watchdog Strikes`.
   - First check after dispatch has no previous snapshot → store it, strikes stay 0.
3. Store the new snapshot in the Active Agents row.
4. **Strikes reach 3 → kill.**
   - Terminate with **TaskStop** (KillShell on older harnesses).
   - **Implementer**: sortie → BACKOFF, attempt counter **increments** (a stall is a failure). If attempts are exhausted → FATAL, work unit → BLOCKED. The retry prompt says: "The previous agent stalled with no progress for ~60 minutes and was terminated. Check `git status` for its uncommitted work before continuing." Do not commit or discard that work — the retry agent decides.
   - **Verifier**: treat as a verifier FAIL with the finding "verifier stalled and was terminated" (§3f), so it uses up a verifier round, and escalate the next verifier to `opus`.
   - Log `WATCHDOG KILL: <work_unit> Sortie N (<role>) — no progress for 3 checks` in the Decisions Log.
5. Write SUPERVISOR_STATE.md, output a status update, re-arm the timer if agents remain.

**Resume.** Timers and agents from a previous session are gone. `resume` arms a fresh timer if it dispatches anything, and resets every strike count to 0.

**Tuning.** `watchdog_interval_minutes` (default 20) and `watchdog_max_strikes` (default 3) live in SUPERVISOR_STATE.md `## Configuration`. To make it a hard runtime cap instead of a no-progress detector, skip step 2's comparison and increment strikes every tick.

### Deferred Sortie Handling
For sorties classified as `deferred` (waiting on external conditions like deployments or long processes), the harness cannot notify on the condition — so turn the wait into something it *can* notify on: one background shell command that exits when the condition is met or the check budget runs out.

```bash
# Bash tool, run_in_background: true
for i in $(seq 1 20); do
  <verification command from the plan> && { echo "DEFERRED_MET after $i checks"; exit 0; }
  sleep <interval from the plan, default 60>
done
echo "DEFERRED_NOT_MET after 20 checks"; exit 1
```

- The command's exit is the event. Its notification is processed like any other in the event loop.
- **Waiting does NOT increment the attempt counter.** Waiting is not failure.
- `DEFERRED_MET` → sortie state → COMPLETED.
- `DEFERRED_NOT_MET` → report to user: `<work_unit> Sortie N is waiting on <condition>. Still not met after 20 checks. Continue waiting or intervene?` If the user says continue, launch another wait.
- Do NOT escalate to FATAL for deferred waits. Only user `stop` or explicit failure (e.g., deployment errored) triggers FATAL.
