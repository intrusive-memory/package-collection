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

Read `$PROJECT_ROOT/EXECUTION_PLAN.md`. This document defines **what** gets done. **skill.md** defines **how** the supervisor operates: state machine, dispatch mechanics, polling, error recovery, and shutdown procedures.

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

Record each criterion with its type: `checklist` (human-verifiable), `command` (machine-verifiable), or `assertion` (boolean check on state).

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
  7. **Pre-Build Dependency Purge** (Swift/Xcode projects only): Run [/dependency-purge](../../dependency-purge/skill.md) once, without `--rebuild`, before any sortie is dispatched. This guarantees every build-gate verification in this mission (see §3e, `code` task type) runs against a freshly resolved dep tree with `intrusive-memory/*` floors bumped to latest releases. See *Pre-Build Dependency Purge* below for details, scoping rules, and the resume exception.
  8. **Dispatch**: Dispatch Sortie 1 for each work unit that has no unsatisfied dependencies.
- **`resume`**: Pick up where the last supervisor left off. Read state, determine what sorties need dispatching, continue. **Do not re-run the pre-build dependency purge on resume** — see *Pre-Build Dependency Purge* below.

---

## 1a. Pre-Build Dependency Purge

The supervisor runs **one** [/dependency-purge](../../dependency-purge/skill.md) at mission start, before any sortie dispatch, so that every build-gate verification (§3e, `code` task type) and every cross-work-unit build check (§5) in this mission resolves against a clean dep tree with `intrusive-memory/*` floors bumped to their latest published releases.

### When it runs

- **`start` only.** Never on `resume`. Resuming means earlier sorties already committed against a particular resolved graph; purging mid-mission would invalidate that graph and force every remaining build-gate sortie to re-resolve from scratch.
- **Swift/Xcode projects only.** Detect by presence of `Package.swift` or any `*.xcodeproj` at the work-unit directory (or `$PROJECT_ROOT` for single-unit missions). For multi-work-unit missions where some units are Swift and some aren't, purge once per Swift work-unit directory.
- **Skip silently** if neither marker is present. Do not error, do not log noise. Most non-Swift missions should see zero overhead from this step.

### What it does

Invokes `/dependency-purge` (without `--rebuild` — the sorties themselves will trigger builds via their exit criteria):

1. Removes DerivedData for the project.
2. Clears the global SPM cache.
3. Deletes `Package.resolved` (root and Xcode locations).
4. Bumps every `intrusive-memory/*` dependency's floor in `Package.swift` to the latest published GitHub release **before** SPM ever resolves. See [/dependency-purge skill.md](../../dependency-purge/skill.md) Step 5 for supported patterns.

### Cost and trade-offs

- **Adds 1–5 minutes** to mission start (network-bound: fresh dep download).
- **Affects other Swift projects on this machine** — the SPM cache is global, so any other project will re-download its deps the next time it builds. This is a real cost; tell the user if they're cost-sensitive.
- **Mid-mission `Package.swift` changes are NOT re-purged.** If a sortie adds or removes an `intrusive-memory/*` dep, that new dep's floor is not auto-bumped. The build gate will still pass against the floor declared in the source — but if the resolver picks an older release than the user expected, the failure-recovery purge in §7 catches it.

### Failure handling

- If `/dependency-purge` itself fails (e.g., `gh` is not authenticated and at least one `intrusive-memory/*` dep needs a release lookup), log the failure to `SUPERVISOR_STATE.md` Decisions Log, **proceed with mission dispatch anyway**, and warn the user. A failed preflight purge is not fatal — the build-gate sorties may still pass against whatever floors are already declared. Treat it as a downgrade in confidence, not a stop.
- If the purge succeeds but rewrites `Package.swift`, leave the changes uncommitted. The first build-gate sortie that touches the dep tree will either commit them as part of its own change set, or `clean` at end of mission will surface them in the brief.

### Recording in state

Add to `SUPERVISOR_STATE.md` Mission Metadata at the end of initialization:

```markdown
- Pre-build dependency purge: <run|skipped (non-Swift)|failed>
- Purge ran at: <ISO-8601 timestamp>
- intrusive-memory floors bumped: <N of M> (if purge ran)
```

### Relationship to failure-recovery purge

This preflight purge is **additive** to the failure-recovery purge described in [/dependency-purge skill.md](../../dependency-purge/skill.md) § "Integration with Mission Supervisor". If a sortie fails mid-mission with a known cache-fixable pattern, the failure-recovery purge still runs as before. The preflight reduces how often that recovery path fires; it does not replace it.

---

## 2. Core Loop — Event-at-a-Time Processing

Once startup is complete (for `start` or `resume`), the supervisor operates as an **event processor**, not a monolithic scanner. Each iteration handles exactly one event, updates state, and determines the next action.

### Phase 1: Initial Dispatch

Identify all work units in `RUNNING` state with sortie state `PENDING`. Dispatch their next sortie as background agents (all eligible work units in parallel). Update SUPERVISOR_STATE.md. Output a status update.

### Phase 2: Event Loop

Repeat until all work units are `COMPLETED` or all active work units are `BLOCKED`/`STOPPED`:

```
1. POLL: Check each active agent with TaskOutput(block: false, timeout: 5000).
2. DETECT: Identify the first agent that has completed (or all, if multiple finished).
3. PROCESS each completed agent — exactly one of these outcomes:
   a. SUCCESS: Verification confirms sortie done.
      → Set sortie state to COMPLETED.
      → If more sorties remain: set next sortie to PENDING.
      → If no more sorties: set work unit state to COMPLETED.
   b. PARTIAL: Verification shows partial progress.
      → Set sortie state to PARTIAL.
      → Will be re-dispatched as continuation in step 4.
   c. FAILURE: Agent exited without completing, or verification failing.
      → Increment attempt counter.
      → If attempts < max_retries: set sortie state to BACKOFF.
      → If attempts >= max_retries: set sortie state to FATAL, work unit state to BLOCKED.
      → Log failure details in Decisions Log.
   d. CONTEXT EXHAUSTION: Agent hit max_turns without completing.
      → Run verification checks to assess state.
      → Treat as FAILURE (increment attempt) or PARTIAL (if progress was made).
4. DISPATCH: For each work unit in RUNNING state with sortie in PENDING, PARTIAL, or BACKOFF:
   → Run model selection to choose haiku, sonnet, or opus.
   → Log model selection decision in Decisions Log.
   → Dispatch a new background agent with selected model.
   → For PARTIAL: use continuation prompt listing remaining work.
   → For BACKOFF: use augmented prompt referencing previous failure.
   → Update sortie state to DISPATCHED.
5. GATE CHECK: After any work unit reaches COMPLETED, check dependency gates:
   → For each NOT_STARTED work unit, check if all its dependencies are now COMPLETED.
   → Newly eligible work units: set to RUNNING, first sortie to PENDING.
6. STATE WRITE: Update SUPERVISOR_STATE.md with all changes from this iteration.
7. STATUS: Output a status update to the user.
8. TERMINATION CHECK:
   → All work units COMPLETED → output final summary.
   → All active work units BLOCKED → report to user, wait for intervention.
   → Otherwise → return to step 1.
```

### Key Principles

- **Process one event at a time.** Don't batch decisions. Complete one agent's result processing before moving to the next.
- **State transitions drive dispatch.** The supervisor never "decides" to dispatch — it reacts to state changes. A sortie enters PENDING → it gets dispatched. A work unit enters RUNNING → its first sortie enters PENDING.
- **Write state before dispatching.** Always update SUPERVISOR_STATE.md with the result of processing BEFORE dispatching the next agent. This ensures crash-safety.

---

## 3. Verification

When a sortie agent completes, determine its outcome using a **verification cascade**. Check each source in order; use the first source that provides a definitive answer:

### 3a. Agent Output

Read the agent's output via TaskOutput. Look for:
- Explicit success signals: "completed", "all checks pass", "committed", "done"
- Explicit failure signals: "failed", "error", "blocked", "could not"
- Partial signals: "partial", "incomplete", "remaining", "continued in next"

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
| `deferred` | Poll the verification command from the plan; success = done, failure = still waiting |
| `manual` | Report findings to user; mark PARTIAL until user explicitly confirms via resume |

### Verification Decision

- If **any source** gives definitive SUCCESS and no source contradicts it → COMPLETED
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

When dispatching a sortie, use the **Task tool** with these parameters:

```
subagent_type: "general-purpose"
run_in_background: true
max_turns: 50
model: <selected_model>  # "haiku", "sonnet", or "opus" from model selection
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
```

### 4e. Tracking Background Agents

When a background Task is dispatched, the tool returns an `output_file` path. Record this in SUPERVISOR_STATE.md:

```markdown
## Active Agents
| Work Unit | Sortie | Sortie State | Attempt | Model | Complexity Score | Task ID | Output File | Dispatched At |
|-----------|--------|-------------|---------|-------|-----------------|---------|-------------|---------------|
| <name> | <N> | DISPATCHED | 1/3 | sonnet | 8 | <id> | <path> | <timestamp> |
```

- **Sortie State**: Must be one of `DISPATCHED`, `RUNNING`, `BACKOFF`, `PARTIAL`. Use the formal sortie states defined in the State Machine section of skill.md.
- **Attempt**: `<current>/<max_retries>`. Increments each time a sortie is re-dispatched due to failure.
- **Model**: The Claude model used for this sortie (`haiku`, `sonnet`, or `opus`).
- **Complexity Score**: The computed score from model selection for auditability.

To check on an agent, use `TaskOutput` with `block: false` to get a non-blocking status check. If the agent is still running, move on and check again later. If it's complete, run verification (Section 3) to confirm the sortie outcome.

### 4f. Polling Cadence

- After dispatching background agents, wait briefly then begin polling.
- Use `TaskOutput` with `block: false` and `timeout: 5000` for non-blocking checks.
- Poll each active agent. When one completes, immediately process its result and dispatch the next sortie for that work unit.
- Between poll cycles, update SUPERVISOR_STATE.md so state is never lost.

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

After EVERY action (dispatch, poll, status check, decision), update `$PROJECT_ROOT/SUPERVISOR_STATE.md`.

### Per-Work-Unit State Block

Each work unit section in SUPERVISOR_STATE.md must include:

```markdown
### <WorkUnitName>
- Work unit state: NOT_STARTED | RUNNING | COMPLETED | STOPPING | STOPPED | BLOCKED | KILLED
- Current sortie: <ID> of <total>
- Sortie state: PENDING | DISPATCHED | RUNNING | COMPLETED | PARTIAL | BACKOFF | FATAL
- Sortie type: code | command | background | deferred | manual
- Model: haiku | sonnet | opus
- Complexity score: <N> (from model selection)
- Attempt: <current> of <max_retries>
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
Sortie state: RUNNING → PARTIAL. Verification shows partial progress. The event loop dispatches a continuation agent with:
- **Model selection**: Use the same model as the previous attempt or upgrade to `sonnet` (minimum model for PARTIAL state to ensure continuation quality).
- **Continuation prompt**: List only the remaining work from the exit criteria that wasn't completed.
- **No attempt increment**: Partial work is progress, not failure. The attempt counter stays the same.

### Sortie Agent Fails
Sortie state: RUNNING → BACKOFF (attempt counter increments). The event loop dispatches a retry agent with:
- **Model selection re-run**: Re-evaluate model. If attempt ≥ 2, the override condition forces `opus` (previous model was insufficient). **This is where you upgrade** — start cheap, learn from failure, send a stronger model.
- **Augmented prompt**: "Sortie N failed on attempt M. Here is what went wrong: <details from agent output>. Fix the issues, then complete the sortie."

If attempt counter reaches `max_retries`: sortie state → FATAL, work unit state → BLOCKED. No further automatic dispatch. Report to user.

### Sortie Agent Exhausts Context Without Completing
Check verification cascade (Section 3):
- If partial progress detected: sortie state → PARTIAL.
- If no progress: sortie state → BACKOFF (attempt counter increments).

### Sortie Agent Exceeds max_turns
The Task tool returns after 50 turns. Run verification:
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

### Background Agent Becomes Unresponsive
If a TaskOutput poll returns no new output after 5 consecutive poll cycles:
1. Log in Decisions Log: `<work_unit> Sortie N agent may be unresponsive`.
2. Continue polling — do NOT auto-kill. The agent may be doing long-running work.
3. After 10 consecutive empty polls: terminate the agent with KillShell. Sortie state → BACKOFF (attempt counter increments).

### Deferred Sortie Handling
For sorties classified as `deferred` (waiting on external conditions like deployments or long processes):
- **Polling does NOT increment the attempt counter.** Waiting is not failure.
- Each poll checks the verification condition from the plan.
- If the condition is met → sortie state → COMPLETED.
- If the condition is not met → log the poll result, continue waiting.
- After 20 unsuccessful polls → report to user: `<work_unit> Sortie N is waiting on <condition>. Still not met after 20 checks. Continue waiting or intervene?`
- Do NOT escalate to FATAL for deferred waits. Only user `stop` or explicit failure (e.g., deployment errored) triggers FATAL.
