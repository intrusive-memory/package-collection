---
type: docs
---

# Mission Supervisor

Orchestrate multi-agent sortie execution with automatic verification, retry logic, and state management.

## Overview

The Mission Supervisor is an agentic orchestrator that breaks down complex projects into atomic sorties and dispatches background agents to execute them in parallel. It manages state, handles failures with automatic retry, and enforces dependency constraints.

**Key Features**:
- **Pre-execution pipeline**: Break down requirements, refine execution plans with 4 automated passes
- **Parallel execution**: Run independent work units simultaneously (up to 4 sub-agents)
- **Automatic verification**: Validate sortie completion via git state, exit criteria, and agent output
- **Fault tolerance**: Automatic retry with backoff, graceful degradation
- **State persistence**: Crash-safe state management across invocations
- **The Ritual**: Humorous military operation names generated at execution start

> **Terminology**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission. The Mission Supervisor orchestrates the mission by dispatching sorties. See skill.md for full definitions.

---

## Recommended Workflow

The recommended path is **breakdown** then **refine** then restart the context window with **start**.

```
┌─────────────────────────────────────────────────────────────┐
│                    REQUIREMENTS DOCUMENT                     │
│                  (PRD, SPEC, README, etc.)                   │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
                  ┌─────────────────────┐
                  │  /mission-supervisor │
                  │      breakdown      │
                  └──────────┬──────────┘
                             │
                             │ Generates
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                      EXECUTION_PLAN.md                       │
│  • Work units (packages/components/phases)                   │
│  • Sorties (3-7 atomic tasks each)                          │
│  • Dependencies (layers, prerequisites)                      │
│  • Entry/Exit criteria (machine-verifiable)                 │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
                  ┌─────────────────────┐
                  │  /mission-supervisor │
                  │       refine        │
                  └──────────┬──────────┘
                             │
                             │ Runs 4 passes sequentially
                             ▼
        ┌───────────────────────────────────┐
        │                                   │
        │  Pass 1: Atomicity & Testability  │
        │  (refine-atomicity)               │
        │  • Context fitness check          │
        │  • Sortie sizing (split/merge)    │
        │  • Machine-verifiable criteria    │
        │                                   │
        └───────────────┬───────────────────┘
                        │
                        ▼
        ┌───────────────────────────────────┐
        │                                   │
        │  Pass 2: Prioritization           │
        │  (refine-priority)                │
        │  • Dependency depth scoring       │
        │  • Foundation/risk/complexity     │
        │  • Priority-based reordering      │
        │                                   │
        └───────────────┬───────────────────┘
                        │
                        ▼
        ┌───────────────────────────────────┐
        │                                   │
        │  Pass 3: Parallelism              │
        │  (refine-parallelism)             │
        │  • Dependency graph analysis      │
        │  • Agent allocation (up to 4)     │
        │  • Builds: supervising agent only │
        │  • Critical path identification   │
        │                                   │
        └───────────────┬───────────────────┘
                        │
                        ▼
        ┌───────────────────────────────────┐
        │                                   │
        │  Pass 4: Open Questions           │
        │  (refine-questions)               │
        │  • TBD/TODO marker detection      │
        │  • Vague criteria replacement     │
        │  • Missing documentation flags    │
        │  • External dependency checks     │
        │                                   │
        └───────────────┬───────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│              EXECUTION_PLAN.md (refined)                     │
│  • Atomic sorties (right-sized for context budget)          │
│  • Machine-verifiable exit criteria                         │
│  • Optimal execution order (priority-based)                 │
│  • Parallelism annotations (agent allocation)               │
│  • Open questions resolved or flagged                       │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ ✦ RESTART CONTEXT WINDOW ✦
                        │ (fresh context for execution)
                        │
                        ▼
              ┌─────────────────────┐
              │  /mission-supervisor │
              │        start        │
              └──────────┬──────────┘
                         │
                         │ 1. THE RITUAL (name-feature)
                         │    Generates operation name
                         │ 2. Initializes state
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                   SUPERVISOR_STATE.md                        │
│  • Work unit states (NOT_STARTED → RUNNING → COMPLETED)    │
│  • Sortie states (PENDING → DISPATCHED → RUNNING)          │
│  • Active agents table (task IDs, output files)            │
│  • Attempt counters (for retry logic)                      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ Event Loop
                        ▼
        ┌───────────────────────────────────┐
        │                                   │
        │  1. Dispatch background agents    │
        │     (parallel for independent     │
        │      work units)                  │
        │                                   │
        │  2. Poll for completion           │
        │     (non-blocking TaskOutput)     │
        │                                   │
        │  3. Verify sortie outcome         │
        │     • Git commits                 │
        │     • Exit criteria commands      │
        │     • Agent output signals        │
        │                                   │
        │  4. Handle results                │
        │     • SUCCESS → next sortie       │
        │     • PARTIAL → continuation      │
        │     • FAILURE → retry (backoff)   │
        │     • FATAL → BLOCKED (manual)    │
        │                                   │
        │  5. Update state                  │
        │     (SUPERVISOR_STATE.md)         │
        │                                   │
        │  6. Check dependency gates        │
        │     (unlock new work units)       │
        │                                   │
        └───────────────┬───────────────────┘
                        │
                        │ Repeat until
                        ▼
        ┌───────────────────────────────────┐
        │   All work units COMPLETED        │
        │        — or —                     │
        │   All active work units BLOCKED   │
        └───────────────────────────────────┘
```

---

## Commands

### Pre-execution Commands

| Command | Purpose | Input | Output |
|---------|---------|-------|--------|
| `breakdown` | Generate execution plan from requirements | Requirements doc | EXECUTION_PLAN.md |
| `refine` | Run all 4 refinement passes sequentially | EXECUTION_PLAN.md | EXECUTION_PLAN.md (refined) |
| `refine-atomicity` | Pass 1: Check sortie sizing and testability | EXECUTION_PLAN.md | EXECUTION_PLAN.md (modified) |
| `refine-priority` | Pass 2: Score and reorder by priority | EXECUTION_PLAN.md | EXECUTION_PLAN.md (modified) |
| `refine-parallelism` | Pass 3: Identify parallel work, allocate agents | EXECUTION_PLAN.md | EXECUTION_PLAN.md (modified) |
| `refine-questions` | Pass 4: Flag vague criteria and open questions | EXECUTION_PLAN.md | EXECUTION_PLAN.md (modified) |

### The Ritual

| Command | Purpose |
|---------|---------|
| `name-feature` | Generate humorous military operation name (called automatically by `start`) |

### Execution Commands

| Command | Purpose | State Required |
|---------|---------|----------------|
| `start` | Begin execution from scratch | EXECUTION_PLAN.md |
| `resume` | Continue after stop/failure | SUPERVISOR_STATE.md |
| `status` | Report current progress | SUPERVISOR_STATE.md |
| `stop` | Graceful shutdown (drain → wait → kill) | SUPERVISOR_STATE.md |
| `killall` | Emergency stop (immediate termination) | SUPERVISOR_STATE.md |

---

## Execution Plan Format

The Mission Supervisor uses dynamic plan detection — it adapts to various formats. However, the recommended structure includes:

### Minimal Plan Structure

```markdown
# EXECUTION_PLAN.md — Project Name

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| Core      | src/core  | 3       | 1     | none        |
| API       | src/api   | 2       | 2     | Core        |

## Sorties

### Sortie 1: Foundation Types

**Entry criteria**:
- [ ] First sortie — no prerequisites

**Tasks**:
1. Create User model in `src/core/models/User.swift`
2. Create Session protocol in `src/core/protocols/Session.swift`
3. Add unit tests for User model

**Exit criteria**:
- [ ] Files exist: `User.swift`, `Session.swift`, `UserTests.swift`
- [ ] Build passes: `swift build`
- [ ] Tests pass: `swift test`

### Sortie 2: Authentication Service

**Entry criteria**:
- [ ] Sortie 1 complete (types exist)

**Tasks**:
1. Implement AuthService in `src/core/services/AuthService.swift`
2. Implement credential validation
3. Add auth tests

**Exit criteria**:
- [ ] File exists: `AuthService.swift`
- [ ] Build passes: `swift build`
- [ ] All tests pass: `swift test`

### Sortie 3: API Endpoints

**Entry criteria**:
- [ ] Sortie 2 complete (auth service exists)

**Tasks**:
1. Create login endpoint in `src/api/routes/auth.swift`
2. Create logout endpoint
3. Add integration tests

**Exit criteria**:
- [ ] File exists: `auth.swift`
- [ ] Server starts: `swift run`
- [ ] Integration tests pass: `swift test --filter APITests`

## Summary

| Metric | Value |
|--------|-------|
| Work units | 2 |
| Total sorties | 3 |
| Dependency structure | layers |
```

### Detection Heuristics

The supervisor detects plan structure using these patterns:

#### Work Units

1. **Table with columns**: `Work Unit`, `Package`, `Component`, `Module` → each row is a work unit
2. **Section headers**: Multiple `## <Name>` sections with sortie definitions → each section is a work unit
3. **Single project**: No multi-unit structure detected → entire plan is one work unit

#### Sorties

1. **Sortie headers**: `## Sortie N:` or `### Sortie N:` → each header is a sortie
2. **Sortie table**: Columns like `Sortie`, `Name`, `Description` → each row is a sortie
3. **Compound sorties**: `Sortie 2a`, `Sortie 2b` → sequential sub-sorties

#### Dependencies

1. **Layer column**: Work units with `Layer` values → higher layers wait for lower layers
2. **Dependencies column**: Explicit `depends on` or `requires` → cross-unit dependencies
3. **Entry criteria**: References to prior sorties → sequential dependencies

#### Entry/Exit Criteria

1. **Checklist items**: `- [ ]` under "Entry Criteria" or "Exit Criteria" headings
2. **Fenced code blocks**: Shell commands to execute for verification
3. **Assertions**: Boolean checks on state

### Task Types

The supervisor classifies sorties by task type to determine dispatch and verification strategy:

| Type | Indicators | Verification Strategy |
|------|-----------|----------------------|
| `code` | "Write", "Create", "Implement", "Build", "Fix" + code artifacts | Git commit + build/test pass |
| `command` | "Run", "Execute", "Deploy", explicit shell commands | Command output matches expected |
| `background` | "Start", "Kick off", "nohup", estimated duration > 1hr | Process confirmed running |
| `deferred` | "Wait for", "Monitor", external dependency | Poll verification until success |
| `manual` | "Listen", "Visit", "Check browser", human judgment | Report findings, user confirms |

### Best Practices

**Atomic sorties**:
- 3-7 tasks per sortie (not too narrow, not too broad)
- Single concern (one subsystem or feature)
- Clear artifact (named, specific outputs)
- Bounded scope (fits within context budget, default 50 turns)

**Machine-verifiable exit criteria**:
- At least one command-based check (`swift build`, `swift test`, `test -f path`)
- Avoid vague language ("works correctly" → "tests pass: `swift test`")
- Cover all tasks (every task has corresponding exit criterion)

**Dependency clarity**:
- Explicit entry criteria referencing prior sortie outputs
- Layer-based grouping for cross-unit dependencies
- Foundation work in early sorties (types, interfaces, shared utilities)

**Priority-optimized order**:
- High-risk sorties early (new technology, external APIs)
- Foundation sorties before dependent sorties
- Bottleneck sorties as early as dependencies allow

---

## Usage Examples

### Generate plan from requirements

```bash
/mission-supervisor breakdown /path/to/PRD.md
```

**Output**: `EXECUTION_PLAN.md` with work units, sorties, entry/exit criteria

### Refine the plan (all 4 passes)

```bash
/mission-supervisor refine
```

**Output**: Refined `EXECUTION_PLAN.md` with:
- Pass 1: Atomicity & Testability (sortie sizing, machine-verifiable criteria)
- Pass 2: Prioritization (dependency-aware priority scoring and reordering)
- Pass 3: Parallelism (agent allocation, critical path, build constraints)
- Pass 4: Open Questions (vague criteria, missing docs, TBD markers)

### Run individual refinement passes

```bash
# Pass 1 only: Check sortie sizing and testability
/mission-supervisor refine-atomicity

# Pass 2 only: Score and reorder sorties by priority
/mission-supervisor refine-priority

# Pass 3 only: Analyze parallelism opportunities
/mission-supervisor refine-parallelism

# Pass 4 only: Flag open questions and vague criteria
/mission-supervisor refine-questions
```

### Execute the plan

```bash
# ✦ Start a fresh context window first ✦

# Start from scratch (generates operation name via THE RITUAL)
/mission-supervisor start

# Check status (non-blocking)
/mission-supervisor status

# Graceful shutdown (drain → wait → kill)
/mission-supervisor stop

# Resume after stop or failure
/mission-supervisor resume

# Emergency stop (immediate kill all agents)
/mission-supervisor killall
```

### Typical workflow

```bash
# 1. Generate plan from requirements
/mission-supervisor breakdown requirements.md

# 2. Refine plan (all 4 passes)
/mission-supervisor refine

# 3. ✦ RESTART CONTEXT WINDOW ✦
#    (fresh context = more budget for execution)

# 4. Execute
/mission-supervisor start

# 5. Monitor (in another session or periodically)
/mission-supervisor status

# 6. If issues arise
/mission-supervisor stop      # graceful shutdown
# ... fix issues manually ...
/mission-supervisor resume    # continue execution
```

---

## State Machine

### Work Unit States

```
NOT_STARTED ──(start)──► RUNNING ──(all sorties done)──► COMPLETED
                           │
                           ├──(stop)──► STOPPING ──(agents finish)──► STOPPED
                           │
                           ├──(sortie FATAL)──► BLOCKED
                           │
                           └──(killall)──► KILLED

STOPPED ──(resume)──► RUNNING
BLOCKED ──(resume)──► RUNNING
KILLED ──(resume)──► RUNNING
```

### Sortie States

```
PENDING ──(dispatch)──► DISPATCHED ──(agent starts)──► RUNNING
                                                          │
                          ┌───────────────────────────────┤
                          │                               │
                          ▼                               ▼
                      COMPLETED                       PARTIAL
                                                          │
                                                          └──(continuation)──► DISPATCHED

RUNNING ──(failure)──► BACKOFF ──(retry)──► DISPATCHED
                         │
                         └──(max retries)──► FATAL
```

---

## Verification Cascade

When a sortie agent completes, the supervisor determines the outcome using these sources (in order):

1. **Agent output**: Explicit success/failure/partial signals
2. **Git state**: New commits, uncommitted changes
3. **Progress files**: PROGRESS.md, TODO.md status markers
4. **Exit criteria commands**: Execute and check return codes
5. **Task-type-specific checks**: Based on sortie classification

**Verdict**:
- SUCCESS: Any source shows definitive success, no contradictions → sortie COMPLETED
- PARTIAL: Progress made but work remains → sortie PARTIAL (continuation)
- FAILURE: No progress, agent exited → sortie BACKOFF (retry)
- FATAL: Max retries exhausted → sortie FATAL, work unit BLOCKED

---

## Error Recovery

All recovery follows the state machine — no ad-hoc fixes:

| Scenario | State Transition | Action |
|----------|------------------|--------|
| Sortie succeeds | RUNNING → COMPLETED | Dispatch next sortie (if any) |
| Sortie partial | RUNNING → PARTIAL | Dispatch continuation with remaining work |
| Sortie fails | RUNNING → BACKOFF | Increment attempt, dispatch retry with failure context |
| Max retries hit | BACKOFF → FATAL | Work unit → BLOCKED, report to user |
| Context exhaustion | RUNNING → PARTIAL or BACKOFF | Verify progress, dispatch continuation or retry |
| Agent unresponsive | (after 10 empty polls) → BACKOFF | Terminate agent, increment attempt |
| Deferred wait | (poll until condition met) → COMPLETED | Do not increment attempt (waiting ≠ failure) |

---

## Skill File Structure

```
mission-supervisor/
├── skill.md                          # Root: terminology, state machine, argument parsing, constraints
├── commands/
│   ├── execution.md                  # start/resume: startup, core loop, verification, dispatch, state, error recovery
│   ├── breakdown.md                  # breakdown: requirements → EXECUTION_PLAN.md
│   ├── refine.md                     # refine: 4 passes (atomicity, priority, parallelism, questions)
│   ├── completion.md                 # COMPLETE_*.md management: audit trail + final verification
│   ├── status.md                     # status: read-only progress report
│   ├── stop.md                       # stop: 3-phase graceful shutdown
│   └── killall.md                    # killall: emergency termination
├── sub-skills/
│   └── name-feature.md              # name-feature: THE RITUAL (operation name generation)
├── PERSONALITY_GUIDELINES.md         # Voice, tone, key phrases
├── OPERATION_NAME_EXAMPLES.md        # Pattern examples for name generation
└── README.md                         # This file
```

## Files Generated During Execution

| File | Created By | Purpose |
|------|-----------|---------|
| `EXECUTION_PLAN.md` | `breakdown`, `refine` | Work units, sorties, entry/exit criteria, parallelism annotations |
| `SUPERVISOR_STATE.md` | `start` | Persistent state (work unit/sortie states, active agents, attempt counters) |
| `COMPLETE_<PROJECT>.md` | execution engine | Additive completion log with timing, verification, cadence analysis |

---

## Configuration

### Context Budget

Default: 50 turns per sortie agent

Set with `--max-turns=N` flag:

```bash
/mission-supervisor refine --max-turns=100
/mission-supervisor refine-atomicity --max-turns=100
```

Calibration: ~15-20 productive actions per 50 turns (rest is overhead)

### Max Retries

Default: 3 attempts per sortie

Configured in `SUPERVISOR_STATE.md`:

```markdown
## Configuration
- max_retries: 3
```

### Polling Cadence

- Poll interval: Non-blocking checks with `timeout: 5000ms`
- Unresponsive threshold: 10 consecutive empty polls → terminate agent
- Deferred wait threshold: 20 unsuccessful polls → report to user

---

## Advanced Features

### Parallel Execution

Work units in the same layer with no shared dependencies execute in parallel:

```markdown
| Work Unit | Layer | Dependencies |
|-----------|-------|-------------|
| Core      | 1     | none        |
| Utils     | 1     | none        |  ← Both execute in parallel
| API       | 2     | Core        |
```

### Agent Allocation

The `refine-parallelism` pass allocates up to 4 sub-agents for concurrent execution:

- **Supervising agent**: Handles all sorties with build/compile steps
- **Sub-agents (up to 4)**: Handle work without build steps (code generation, documentation, research)

### Compound Sorties

Sequential sub-sorties for complex work:

```markdown
### Sortie 2a: API Client
...

### Sortie 2b: API Integration
**Entry criteria**:
- [ ] Sortie 2a complete
...
```

Sortie 2a must complete before 2b starts.

### Background Tasks

Sorties that launch long-running processes:

```markdown
**Exit criteria**:
- [ ] Process is running: `pgrep -f "server.py"`
```

Sortie completes once process starts — does not wait for process to finish.

### Deferred Tasks

Sorties waiting on external conditions:

```markdown
**Exit criteria**:
- [ ] Deployment succeeded: `curl https://api.example.com/health`
```

Supervisor polls verification command until success — does not fail after retries.

---

## Model Selection

The supervisor selects the cheapest appropriate model for each sortie:

| Model | Cost | Use When |
|-------|------|----------|
| haiku | 1x | Simple, well-defined tasks (file creation, config changes) |
| sonnet | 10x | Standard complexity (feature implementation, test writing) |
| opus | 30x | Complex, ambiguous, or critical work (architecture, debugging) |

---

## Troubleshooting

### Plan won't parse

- Ensure work units have distinct names
- Verify sortie numbering (1, 2, 3 or 1a, 1b, 2a)
- Check entry/exit criteria formatting (`- [ ]` checkboxes)

### Sortie keeps failing

- Check `SUPERVISOR_STATE.md` Decisions Log for failure details
- Review agent output files (paths in Active Agents table)
- Verify entry criteria are met before sortie starts
- Ensure exit criteria are achievable (not too strict)

### Work unit stuck in BLOCKED

- Sortie hit FATAL after max retries
- Manual intervention needed
- Fix underlying issue, then run `/mission-supervisor resume`

### Execution too slow

- Check if work units are serialized unnecessarily (layer structure)
- Run `/mission-supervisor refine-parallelism` to optimize parallelism
- Run `/mission-supervisor refine-priority` to optimize order

### Context exhaustion

- Sorties are too large (too many tasks/files)
- Run `/mission-supervisor refine-atomicity` to identify and split oversized sorties
- Or increase context budget: `--max-turns=100`

---

## Architecture

The Mission Supervisor is a **state machine orchestrator**, not a code generator:

**What it does**:
- Parse execution plans (any markdown format)
- Dispatch background agents (one per sortie)
- Poll for completion (non-blocking)
- Verify outcomes (git state, exit criteria, agent output)
- Manage state transitions (deterministic state machine)
- Handle errors (retry with backoff, escalate to FATAL)

**What it doesn't do**:
- Write production code (agents do this)
- Write tests (agents do this)
- Override dependencies (enforces plan constraints)
- Skip verification (always validates sortie completion)
- Modify execution plan during execution (plan is immutable during `start`/`resume`)

**Design principles**:
- **Event-at-a-time processing**: Handle one completion event, update state, dispatch next
- **State transitions drive dispatch**: Reactive, not imperative (sortie enters PENDING → gets dispatched)
- **Write state before dispatching**: Crash-safe (state never lost)
- **Verification cascade**: Multiple sources of truth (agent output, git, files, commands)
- **Graceful degradation**: PARTIAL → continuation, FAILURE → retry, FATAL → BLOCKED
