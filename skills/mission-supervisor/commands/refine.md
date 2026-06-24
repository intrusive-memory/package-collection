---
type: docs
---

# Refine Command — refine / refine-blockers / refine-atomicity / refine-priority / refine-parallelism / refine-questions

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

> **OKF type reminder**: Every "Rewrite plan" step below edits `EXECUTION_PLAN.md` in place. Preserve its `type: execution-plan` frontmatter key (and any `feature_name`/`starting_point_commit`/etc. already present) — rewriting sortie content must never drop the frontmatter. See skill.md § Mission Documents & OKF Types.

The `refine` command performs 5 refinement passes over an existing EXECUTION_PLAN.md to ensure it's ready for execution. Each pass can be run independently as a subcommand, or all passes run sequentially via the main `refine` command.

Pass 1 (`refine-blockers`) is a **hard-stop gate**: if any blocking open questions surfaced by `breakdown` remain unanswered, all subsequent passes are skipped until the user resolves them. Pass 5 (`refine-questions`) is the final cleanup pass for vague criteria and any lingering questions introduced by Passes 2–4.

**Referenced by**: `skill.md` § Argument Parsing → `refine`, `refine-blockers`, `refine-atomicity`, `refine-priority`, `refine-parallelism`, `refine-questions` commands.

---

## Pass 1: Blocking Open Questions (refine-blockers)

**Purpose**: Surface every open question left over from `breakdown` and **full stop** until the user resolves them. The mission cannot be refined further while the foundational scope is undecided.

**Why this runs first**: Atomicity, prioritization, and parallelism analyses are all wasted work if a core decision (technology choice, scope boundary, external dependency) is still open. Answering blockers first lets Passes 2–4 operate on a stable plan.

**Process**:

1. **Parse the plan**: Read EXECUTION_PLAN.md using detection heuristics from `commands/execution.md` § Parse the Execution Plan.

2. **Collect blocking open questions** — anything in the plan that prevents an agent from starting work:

   **Primary source — the `## Open Questions` section emitted by `breakdown`** (see `commands/breakdown.md` § Open Questions). Parse each `### OQ-<N>: <title>` entry and use its `Affects`, `Question`, `Source`, `Why blocking`, `Recommendation`, and `Rationale` fields directly. The recommendation and rationale are authored by `breakdown` — `refine-blockers` consumes them rather than regenerating them. If the section contains the sentinel line `_No blocking open questions identified during breakdown._`, treat it as zero structured blockers but still run the fallback scan below to catch anything `breakdown` missed.

   **Fallback scan** (use only if the `## Open Questions` section is absent, or to supplement the sentinel case):
   - **TBD/TODO/decide/clarify** markers in sortie descriptions, entry criteria, or exit criteria
   - **Forks without a decision**: "Option A vs Option B", "either X or Y", multiple competing approaches presented without a chosen one
   - **Undecided externals**: "which library?", "which API?", "which database?", "needs auth strategy"
   - **Undefined scope boundaries**: "decide whether to include feature X", "scope of migration TBD"

   For any blocker found via fallback scan (i.e., not already carrying a `breakdown`-authored recommendation), draft one inline using the same rules `breakdown` uses (see `commands/breakdown.md` § Capture Open Questions → "Drawing recommendations"). This is a degraded path — if it happens often, the requirements doc likely needs `/mission-supervisor breakdown` re-run.

   If the `## Open Questions` section is missing entirely, note this in the output (it means `breakdown` was run on an older version of the skill) and proceed via the fallback scan with inline recommendations.

   **Do not collect** vague exit criteria like "works correctly" or "tests pass" — those belong to Pass 5 (`refine-questions`).

3. **Sanity-check each recommendation** (light review, not regeneration): Skim the recommendation/rationale produced by `breakdown` against the current EXECUTION_PLAN.md. If a recommendation conflicts with a later sortie's tasks or contradicts a constraint elsewhere in the plan, flag it as `**Refine-flagged conflict**: <one-line reason>` in the blocker report so the user sees the issue alongside breakdown's recommendation. Do not silently overwrite breakdown's recommendation.

4. **Render the blocker report** in the chat (do NOT modify EXECUTION_PLAN.md yet):

   ```
   ## Pass 1: Blocking Open Questions — <N> blockers found

   ### Blocker 1 — Sortie <N>: <short title>
   **Question**: <verbatim from plan, or paraphrased if scattered>
   **Recommendation**: <specific choice>
   **Rationale**: <one or two sentences citing the signal used>

   ### Blocker 2 — ...
   ```

5. **Hard stop and request user input**:
   - If **N > 0** blockers exist: STOP. Do not run Pass 2. Output:
     ```
     **BLOCKED**: <N> open questions must be resolved before refinement can continue.

     For each blocker above, reply with one of:
       - "accept <N>" to use the recommendation
       - "accept all" to use every recommendation
       - "<N>: <your decision>" to override a specific blocker

     Once decisions are recorded, re-run: /mission-supervisor refine
     ```
   - If **N == 0**: Output `## Pass 1: No blocking open questions — proceeding to Pass 2` and continue.

6. **On user response (next invocation)**: Apply each accepted/overridden decision by editing the relevant sortie in EXECUTION_PLAN.md — replace the open question with the chosen answer, update entry/exit criteria as needed, and delete the now-resolved "Open Questions" entry. Then re-enter the refinement flow at Pass 2.

7. **Output (after decisions applied)**:
   ```
   ## Pass 1: Blocking Open Questions Resolved

   | # | Sortie | Decision | Source |
   |---|--------|----------|--------|
   | 1 | <N> | <chosen answer> | recommendation / user override |

   Plan updated. Continuing to Pass 2.
   ```

---

## Pass 2: Atomicity and Testability (refine-atomicity)

**Purpose**: Ensure every task is small, testable, and won't exhaust the context window.

**Process**:

1. **Parse the plan**: Read EXECUTION_PLAN.md using detection heuristics from `commands/execution.md` § Parse the Execution Plan.
2. **Context budget**: Use `--max-turns` from arguments (default 50). Calibrate: ~15-20 productive actions per 50 turns.

3. **Atomicity Check** - for each sortie, verify:
   - **Single concern**: All tasks relate to one subsystem or feature
   - **Clear artifact**: Sortie produces named, specific outputs
   - **Bounded scope**: Estimated effort fits within context budget
   - **Explicit inputs/outputs**: Entry criteria name specific artifacts; exit criteria name specific verifiable outcomes

4. **Testability Check** - for each sortie, verify:
   - **At least one machine-verifiable criterion**: Build command, test command, file-exists check, or grep check
   - **No vague language**: No "works correctly", "properly handles", "is complete"
   - **Coverage**: Exit criteria address all tasks in the sortie

5. **Context Fitness Check** - estimate turns required:
   ```
   estimated_turns = R + (C * 2) + (M * 2) + B + ceil(L / 75) + V + 5
   ```
   Where: R=files to read, C=files to create, M=files to modify, B=build steps, L=total LoC, V=verification steps

   | Verdict | Condition |
   |---------|-----------|
   | **Oversized** | `estimated_turns > context_budget * 0.80` |
   | **Right-sized** | Between 15% and 80% of budget |
   | **Undersized** | `estimated_turns < context_budget * 0.15` |

6. **Auto-fix issues**:
   - **Oversized sortie**: Split into two sorties at natural halfway point
   - **Undersized sortie**: Merge with adjacent sortie
   - **Non-atomic (multiple concerns)**: Split by concern
   - **Missing exit criteria**: Add machine-verifiable criteria (file-exists, build, test commands)
   - **Vague exit criteria**: Replace with specific checks

7. **Rewrite plan**: Update EXECUTION_PLAN.md with fixes, renumber sorties, update cross-references.

8. **Output**:
   ```
   ## Pass 2: Atomicity & Testability Complete

   | Check | Passed | Issues Found | Auto-Fixed |
   |-------|--------|-------------|------------|
   | Atomicity | <N> | <N> | <N> |
   | Testability | <N> | <N> | <N> |
   | Context Fitness | <N> | <N> | <N> |

   Sorties before: <N> | Sorties after: <N>
   Splits: <N> | Merges: <N>

   Context budget: <max_turns> turns per sortie
   ```

---

## Pass 3: Prioritization (refine-priority)

**Purpose**: Determine what needs to go first and what can wait. Establish dependencies and execution order.

**Process**:

1. **Parse the plan**: Read EXECUTION_PLAN.md using detection heuristics from `commands/execution.md` § Parse the Execution Plan.

2. **Score each sortie** on four dimensions:

   | Dimension | How to Measure | Weight |
   |-----------|---------------|--------|
   | **Dependency depth** | Count sorties transitively blocked by this sortie | 3x |
   | **Foundation score** | Establishes types/interfaces/patterns reused by 2+ sorties? (0=no, 1=yes) | 2x |
   | **Risk level** | External API (3), new tech (3), complex algorithms (2), file I/O (2), simple CRUD (1) | 1x |
   | **Complexity** | Average of: task count score, files touched score, verification complexity score | 0.5x |

3. **Compute composite priority**:
   ```
   priority = (dependency_depth * 3) + (foundation_score * 2) + (risk_level * 1) + (complexity * 0.5)
   ```
   Higher score = higher priority = execute earlier.

4. **Reorder within hard constraints**:
   - Dependency order: Sortie cannot move before any sortie it depends on
   - Work unit coherence: Maintain relative order unless dependencies allow reordering
   - Layer integrity: Layer N cannot start before Layer N-1 completes

5. **Add priority annotations** to each sortie:
   ```markdown
   ### Sortie <N>: <Sortie Name>

   **Priority**: <score> — <justification>

   **Entry criteria**:
   ...
   ```

6. **Update dependency structure**: Adjust layers if priority analysis reveals better layering.

7. **Rewrite plan**: Update EXECUTION_PLAN.md with reordered sorties, renumber, update cross-references.

8. **Output**:
   ```
   ## Pass 3: Prioritization Complete

   | Sortie | Name | Priority | Change |
   |--------|------|----------|--------|
   | 1 | <name> | <score> | was Sortie <old_N> / unchanged |

   Sorties reordered: <N>
   Layer adjustments: <N or "none">
   ```

---

## Pass 4: Parallelism (refine-parallelism)

**Purpose**: Identify what work can be done in parallel. Add up to 4 sub-agents for concurrent execution. **CRITICAL**: Sub-agents do NOT do builds — only the supervising agent builds.

**Process**:

1. **Parse the plan**: Read EXECUTION_PLAN.md using detection heuristics from `commands/execution.md` § Parse the Execution Plan.

2. **Build dependency graph** across all work units and sorties:
   - **Intra-work-unit dependencies**: Sortie N → Sortie N+1 within each work unit
   - **Inter-work-unit dependencies**: Work unit A → Work unit B based on layer/explicit dependencies
   - **Implicit dependencies**: Sortie X creates artifact used by Sortie Y

3. **Identify parallelizable clusters**:
   - **Same-layer work units**: Work units in same layer with no shared dependencies
   - **Independent sorties**: Sorties within a work unit that don't share file dependencies
   - **Concurrent vs sequential**: Work that's unnecessarily serialized

4. **Calculate parallelism metrics**:
   - **Critical path**: Longest dependency chain from start to finish
   - **Maximum parallelism**: How many agents could run simultaneously
   - **Current parallelism**: Based on layer structure
   - **Missed opportunities**: Sorties that could be reordered for better parallelism

5. **Add agent allocation annotations**:
   - **Up to 4 sub-agents** for parallel work
   - Annotate each parallelizable cluster with agent assignment
   - **ENFORCE**: Mark sorties with builds as "supervising agent only"
   - **ENFORCE**: Mark sub-agent sorties as "no build operations"

6. **Add parallelism metadata** to plan:
   ```markdown
   ## Parallelism Structure

   **Critical Path**: Sortie 1 → Sortie 3 → Sortie 7 → Sortie 12 (length: N sorties)

   **Parallel Execution Groups**:
   - **Group 1** (can run in parallel):
     - Work Unit A: Sortie 1-3 (Agent 1)
     - Work Unit B: Sortie 1-2 (Agent 2)
   - **Group 2** (sequential, depends on Group 1):
     - Work Unit A: Sortie 4 (Agent 1) — **SUPERVISING AGENT ONLY** (has build step)
     - Work Unit C: Sortie 1 (Agent 3) — **NO BUILD** (sub-agent)

   **Agent Constraints**:
   - **Supervising agent**: Handles all sorties with build/compile steps
   - **Sub-agents (up to 4)**: Handle work without build steps (research, file creation, documentation)
   ```

7. **Rewrite plan**: Add parallelism annotations to EXECUTION_PLAN.md.

8. **Output**:
   ```
   ## Pass 4: Parallelism Complete

   **Critical Path**: Sortie 1 → Sortie 3 → Sortie 7 → Sortie 12 (<N> sorties)

   **Parallelism**:
   - Current: <N> work units can run simultaneously
   - Maximum: <N> agents could run simultaneously
   - Agent allocation: 1 supervising + <N> sub-agents (max 4 sub-agents)

   **Parallel Groups**: <N>
   **Build Constraints**: <N> sorties restricted to supervising agent

   **Missed Opportunities**:
   - <List sorties that could be parallelized>
   ```

---

## Pass 5: Vague Criteria and Lingering Questions (refine-questions)

**Purpose**: Final cleanup pass. Catch vague criteria in sortie gates, missing documentation, or any lingering open questions that surfaced during Passes 2–4 (atomicity splits, reorderings, or parallelism analysis may have introduced new ambiguity). Blocking open questions from `breakdown` are handled earlier by Pass 1 (`refine-blockers`).

**Process**:

1. **Parse the plan**: Read EXECUTION_PLAN.md using detection heuristics from `commands/execution.md` § Parse the Execution Plan.

2. **Scan for open questions** that would block execution:
   - **TBD markers**: "TBD", "TODO", "determine later", "decide", "clarify"
   - **Alternative approaches**: Multiple options presented without a decision
   - **Missing specifics**: Vague references like "appropriate library", "suitable approach", "standard method"
   - **External dependencies**: References to systems/APIs without documented interfaces

3. **Scan for vague criteria**:
   - **Entry criteria**:
     - References to "previous work" without specifics
     - "Setup is complete" without defining setup
   - **Exit criteria**:
     - "Works correctly", "properly handles", "is complete"
     - "Tests pass" without naming specific tests
     - "Build succeeds" without specifying build command

4. **Identify missing documentation**:
   - Sortie references files that don't exist
   - Sortie references APIs without documented endpoints
   - Sortie requires knowledge not present in the plan

5. **Classify each issue**:
   | Type | Description | Blocking Impact |
   |------|-------------|----------------|
   | **Open question** | Unresolved technical decision | High - sortie agent can't proceed |
   | **Vague criterion** | Exit criterion not machine-verifiable | Medium - verification will be ambiguous |
   | **Missing doc** | Referenced artifact doesn't exist | High - sortie agent lacks context |
   | **External dependency** | Undocumented external system | High - sortie agent can't integrate |

6. **Add clarity annotations** to plan:
   ```markdown
   ## Open Questions & Missing Documentation

   ### Unresolved Items (must address before execution)

   | Sortie | Issue Type | Description | Recommendation |
   |--------|-----------|-------------|----------------|
   | Sortie 3 | Open question | "Choose appropriate caching strategy" — no decision made | Research task: Compare Redis vs in-memory caching, document decision |
   | Sortie 5 | Vague criterion | Exit: "API integration works correctly" | Replace with: "API integration tests pass: `swift test --filter APIIntegrationTests`" |
   | Sortie 7 | Missing doc | References `API_SPEC.md` which doesn't exist | Create API_SPEC.md before Sortie 7 or add research task to Sortie 6 |
   ```

7. **Auto-fix where possible**:
   - **Vague criteria**: Replace with machine-verifiable equivalents where obvious
   - **Missing docs**: Add research tasks to preceding sorties to create the docs

8. **Flag unresolvable issues** for manual review.

9. **Rewrite plan**: Add clarity annotations, auto-fixed criteria, and research tasks.

10. **Output**:
    ```
    ## Pass 5: Vague Criteria & Lingering Questions Complete

    **Issues Found**: <N>
    - Open questions: <N>
    - Vague criteria: <N>
    - Missing documentation: <N>
    - External dependencies: <N>

    **Auto-Fixed**: <N>
    **Requires Manual Review**: <N>

    <If manual review needed>:
    **BLOCKED**: <N> issues require manual resolution before execution can start.
    Review EXECUTION_PLAN.md "Open Questions & Missing Documentation" section.
    ```

---

## Main Refine Command (runs all 5 passes)

When `refine` is invoked (without a subcommand), execute the passes sequentially. **Pass 1 is a hard-stop gate** — if it surfaces blockers, stop immediately and wait for user decisions before continuing.

1. **Run Pass 1**: Blocking open questions (`refine-blockers`)
   - If blockers found: STOP. Render recommendations, request user decisions, do not run Passes 2–5.
   - If no blockers (or after decisions are applied on re-invocation): continue.
2. **Run Pass 2**: Atomicity and testability
3. **Run Pass 3**: Prioritization
4. **Run Pass 4**: Parallelism
5. **Run Pass 5**: Vague criteria and lingering questions

6. **Declare plan ready for execution** if all passes succeed:
   - No unresolved blocking open questions
   - No oversized sorties (all fit in context budget)
   - No vague exit criteria (all machine-verifiable)
   - Clear dependency structure and priority order
   - Parallelism opportunities identified

7. **Output summary**:
   ```
   ## Refinement Complete — Plan is Ready to Execute

   ### Pass Results

   | Pass | Status | Changes |
   |------|--------|---------|
   | 1. Blocking Open Questions | ✓ PASS / ✗ BLOCKED | <N> blockers resolved (recommendations: <N>, overrides: <N>) |
   | 2. Atomicity & Testability | ✓ PASS | <N> sorties split, <N> merged, <N> criteria fixed |
   | 3. Prioritization | ✓ PASS | <N> sorties reordered, priority scores added |
   | 4. Parallelism | ✓ PASS | <N> parallel groups, 1 supervising + <N> sub-agents |
   | 5. Vague Criteria & Lingering Questions | ✓ PASS / ✗ BLOCKED | <N> issues auto-fixed, <N> require manual review |

   <If all passes succeeded>:
   **VERDICT**: ✓ Plan is ready to execute

   ### Execution Summary
   - Total sorties: <N>
   - Average sortie size: <X> turns (budget: <max_turns>)
   - Critical path length: <N> sorties
   - Parallelism: 1 supervising agent + <N> sub-agents (up to 4)
   - Execution time estimate: <X> hours (assuming <Y> mins/sortie, <Z>% parallelism efficiency)

   **Next step**: /mission-supervisor start

   <If Pass 1 found unresolved blockers>:
   **VERDICT**: ✗ Plan NOT ready — <N> blocking open questions require user decisions

   See the blocker report above. Reply with `accept <N>`, `accept all`, or `<N>: <override>`, then re-run: /mission-supervisor refine

   <If Pass 5 found blocking issues>:
   **VERDICT**: ✗ Plan NOT ready — <N> issues require manual resolution

   Review "Open Questions & Missing Documentation" section in EXECUTION_PLAN.md, resolve issues, then re-run: /mission-supervisor refine
   ```
