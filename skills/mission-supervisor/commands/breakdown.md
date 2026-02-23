# Breakdown Command — breakdown

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

The `breakdown` command reads a requirements document and generates `EXECUTION_PLAN.md`. This is the first step in the pre-execution pipeline.

**Referenced by**: `skill.md` § Argument Parsing → `breakdown` command.

---

## 1. Read the Requirements Document

Read the file resolved by the argument parser (see skill.md § Locate Requirements Document). Accept any markdown format — PRDs, specs, READMEs, design docs, bullet lists, prose, or mixed formats.

## 2. Heuristic Requirement Detection

Scan the document for requirements using these heuristics, in priority order:

**Explicit requirements** (high confidence):
- Headings containing "Requirements", "Functional Requirements", "Non-Functional Requirements"
- Numbered or lettered lists under requirement-style headings
- RFC keywords: MUST, SHALL, SHOULD, MUST NOT, SHALL NOT, SHOULD NOT, MAY
- User stories: "As a [role], I want [goal], so that [reason]"
- Acceptance criteria sections

**Implicit requirements** (medium confidence):
- Task language: "implement", "create", "build", "add", "support", "enable", "integrate"
- Checklists (`- [ ]` items)
- Bullet lists under headings like "Features", "Deliverables", "Scope", "Tasks"

**Context signals** (supplementary — not requirements themselves, but inform decomposition):
- Goals / objectives sections
- Technical constraints (language, platform, framework, API compatibility)
- Architecture diagrams or descriptions
- Out-of-scope markers ("out of scope", "not included", "future work", "v2")
- Dependencies on external systems

Record each detected requirement with its source location (heading + line range) and confidence level.

## 3. Decompose into Atomic Tasks

Break each requirement into atomic tasks. An atomic task has:

- **Single concern**: Does exactly one thing
- **Clear artifact**: Produces a specific, nameable output (file, function, config, test suite)
- **Bounded scope**: Completable by a single agent in one sortie (≤50 turns)
- **Explicit inputs/outputs**: What it reads, what it produces

**Split rules** — apply when a requirement is NOT atomic:

| Signal | Split Strategy |
|--------|---------------|
| "and" conjunction joining distinct work | Split at the conjunction |
| Multiple files in different directories | One task per directory cluster |
| "Create X and integrate with Y" | Split into "Create X" and "Integrate X with Y" |
| "Add support for A, B, and C" | One task per item if they're independent; one task if they share implementation |
| Requirement spans >3 files | Split by logical grouping (types, logic, tests, config) |
| Implicit test work | Separate "Write tests for X" task unless trivial |

## 4. Identify Work Units

Group atomic tasks into work units based on document structure:

1. **Document sections**: If the requirements doc has clear `##` section divisions → each section is a candidate work unit.
2. **Directory references**: If tasks reference distinct directories or packages → each directory is a work unit.
3. **Dependency clusters**: Tasks that share inputs/outputs and must execute together → cluster into a work unit.
4. **Single-project default**: If no multi-unit structure is evident, the entire plan is one work unit named after the project directory.

Each work unit must have:
- A clear name
- A directory (or project root for single-unit plans)
- At least one sortie

## 5. Group Tasks into Sorties

Organize atomic tasks into sorties within each work unit. **Apply sergeant principles**: each sortie = one clear deliverable.

- **3-7 tasks per sortie**: Fewer than 3 suggests the sortie is too narrow; more than 7 risks context exhaustion.
- **One goal per sortie**: All tasks in a sortie should contribute to a single, coherent objective. Don't mix unrelated work.
- **Sequential dependencies within work unit**: If task B depends on task A's output, they go in the same sortie (A before B) or A's sortie comes first.
- **Logical cohesion**: Group tasks that operate on the same files or subsystem.
- **Foundation first**: Types, interfaces, and shared utilities go in Sortie 1. Implementations that depend on them follow.

## 6. Generate EXECUTION_PLAN.md

Write `$PROJECT_ROOT/EXECUTION_PLAN.md` in a format compatible with the existing parser (see `commands/execution.md` § Parse the Execution Plan). The generated plan MUST include:

### Mandatory Terminology Section

**IMPORTANT**: Every generated EXECUTION_PLAN.md MUST include the terminology definitions near the top of the document, immediately after the title. This ensures any reader understands the language:

```markdown
## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).
```

### Title
```markdown
# EXECUTION_PLAN.md — <Project Name>
```

### Work Units table (with Layer column for dependency gating)
```markdown
## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| <name> | <dir> | <count> | <N> | <deps or "none"> |
```

### Sortie definitions (one per sortie, using `### Sortie N:` headers)
```markdown
### Sortie <N>: <Sortie Name>

**Entry criteria**:
- [ ] <criterion — reference prior sortie exit criteria or "First sortie — no prerequisites">

**Tasks**:
1. <Task description with specific files/artifacts>
2. <Task description>
...

**Exit criteria**:
- [ ] <Machine-verifiable criterion (build succeeds, test passes, file exists)>
- [ ] <Machine-verifiable criterion>
```

### Summary table
```markdown
## Summary

| Metric | Value |
|--------|-------|
| Work units | <N> |
| Total sorties | <N> |
| Dependency structure | <layers \| sequential \| parallel> |
```

## 7. Do NOT Prioritize

The `breakdown` command arranges sorties in natural dependency order only. It does NOT analyze risk, complexity, or strategic priority. That is the job of the `refine` command.

## 8. Output Summary

After writing EXECUTION_PLAN.md, output:

```
## Breakdown Complete

Source: <requirements file path>
Output: $PROJECT_ROOT/EXECUTION_PLAN.md

| Metric | Count |
|--------|-------|
| Requirements detected | <N> |
| Atomic tasks | <N> |
| Work units | <N> |
| Sorties | <N> |

Next step: /mission-supervisor refine
```
