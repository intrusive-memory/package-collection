# Refine Command — refine / refine-atomicity / refine-priority / refine-parallelism / refine-questions

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

The `refine` command performs 4 refinement passes over an existing EXECUTION_PLAN.md to ensure it's ready for execution. Each pass can be run independently as a subcommand, or all passes run sequentially via the main `refine` command.

**Referenced by**: `skill.md` § Argument Parsing → `refine`, `refine-atomicity`, `refine-priority`, `refine-parallelism`, `refine-questions` commands.

---

## Pass 1: Atomicity and Testability (refine-atomicity)

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
   ## Pass 1: Atomicity & Testability Complete

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

## Pass 2: Prioritization (refine-priority)

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
   ## Pass 2: Prioritization Complete

   | Sortie | Name | Priority | Change |
   |--------|------|----------|--------|
   | 1 | <name> | <score> | was Sortie <old_N> / unchanged |

   Sorties reordered: <N>
   Layer adjustments: <N or "none">
   ```

---

## Pass 3: Parallelism (refine-parallelism)

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
   ## Pass 3: Parallelism Complete

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

## Pass 4: Open Questions and Vague Criteria (refine-questions)

**Purpose**: Identify vague criteria in sortie gates, missing documentation, or research needed that may affect scope.

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
    ## Pass 4: Open Questions & Vague Criteria Complete

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

## Main Refine Command (runs all 4 passes)

When `refine` is invoked (without a subcommand), execute all 4 passes sequentially:

1. **Run Pass 1**: Atomicity and testability
2. **Run Pass 2**: Prioritization
3. **Run Pass 3**: Parallelism
4. **Run Pass 4**: Open questions and vague criteria

5. **Declare plan ready for execution** if all passes succeed:
   - No oversized sorties (all fit in context budget)
   - No vague exit criteria (all machine-verifiable)
   - Clear dependency structure and priority order
   - Parallelism opportunities identified
   - No blocking open questions

6. **Output summary**:
   ```
   ## Refinement Complete — Plan is Ready to Execute

   ### Pass Results

   | Pass | Status | Changes |
   |------|--------|---------|
   | 1. Atomicity & Testability | ✓ PASS | <N> sorties split, <N> merged, <N> criteria fixed |
   | 2. Prioritization | ✓ PASS | <N> sorties reordered, priority scores added |
   | 3. Parallelism | ✓ PASS | <N> parallel groups, 1 supervising + <N> sub-agents |
   | 4. Open Questions & Vague Criteria | ✓ PASS / ✗ BLOCKED | <N> issues auto-fixed, <N> require manual review |

   <If all passes succeeded>:
   **VERDICT**: ✓ Plan is ready to execute

   ### Execution Summary
   - Total sorties: <N>
   - Average sortie size: <X> turns (budget: <max_turns>)
   - Critical path length: <N> sorties
   - Parallelism: 1 supervising agent + <N> sub-agents (up to 4)
   - Execution time estimate: <X> hours (assuming <Y> mins/sortie, <Z>% parallelism efficiency)

   **Next step**: /mission-supervisor start

   <If Pass 4 found blocking issues>:
   **VERDICT**: ✗ Plan NOT ready — <N> blocking issues require manual resolution

   Review "Open Questions & Missing Documentation" section in EXECUTION_PLAN.md, resolve issues, then re-run: /mission-supervisor refine
   ```
