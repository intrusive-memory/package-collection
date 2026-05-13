---
name: organize-agent-docs
description: Gold-standard markdown organization for any repository. Sorts every markdown file into one of three buckets — FOUNDATIONAL (AGENTS.md/CLAUDE.md/GEMINI.md/README.md/CHANGELOG.md/LICENSE at root), MISSION (mission-supervisor artifacts; lifecycle tracked via frontmatter `state:` and routed to root, docs/complete/, or docs/incomplete/), or EXTRANEOUS (everything else → docs/). Maintains links in FOUNDATIONAL files after moves and stamps an `updated:` date when content changes. Use when the user asks to "organize agent docs", "clean up markdown", "tidy the repo", "archive mission files", "separate agent instructions", "restructure AGENTS.md", "sort docs", or whenever a project's markdown files are mixed between root and docs/. This skill is the single owner of repo-level markdown moves; mission-supervisor delegates its `clean` step here.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep, AskUserQuestion
argument-hint: "[organize|split-agent-docs|classify] [path]"
---

# Organize Agent Docs

This skill is the single source of truth for organizing markdown files in a repository. It owns three responsibilities:

1. **Categorize** every markdown file in a repo into `FOUNDATIONAL`, `MISSION`, or `EXTRANEOUS`.
2. **Route** each file to its correct location (root, `docs/<bucket>/<mission>/`, or `docs/`), updating any links in FOUNDATIONAL files that reference moved files.
3. **Stamp** an `updated:` date on FOUNDATIONAL files whose content the skill actually modified.

Mission-supervisor's old `clean` command delegates here. Sortie *creation* during an active mission still belongs to mission-supervisor; *archival* is owned by this skill.

---

## The Three Categories

| Category | What it is | Where it lives |
|----------|------------|----------------|
| **FOUNDATIONAL** | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CURSOR.md`, `COPILOT.md`, `CODEX.md`, `README.md`, `CHANGELOG.md`, `LICENSE`, `LICENSE.md` | Project root only |
| **MISSION** | Files Mission Supervisor creates (`EXECUTION_PLAN.md`, `SUPERVISOR_STATE.md`, `COMPLETE_*.md`, `*_BRIEF.md`, `sortie-*.{md,txt,fcpxml}`, `SORTIE-*.md`) | Root if `state: current`; `docs/complete/<mission>/` if `state: completed`; `docs/incomplete/<mission>/` if `state: incomplete` |
| **EXTRANEOUS** | Any other markdown file at the repo root (notes, design docs, ROADMAP.md, etc.) | `docs/` |

Full classification rules and ambiguity handling: `references/file-categories.md`.

---

## Frontmatter Contract

Every MISSION file carries a `state:` field and an inheritable `mission:` slug. FOUNDATIONAL `.md` files carry an `updated:` field that the skill bumps only when it actually edits the file.

```yaml
# MISSION file
---
state: current        # current | completed | incomplete
updated: 2026-05-12
mission: steamroller-origami-01
---

# FOUNDATIONAL file
---
updated: 2026-05-12
---
```

The location of a mission file MUST match its `state`. The skill enforces this invariant on every run. `LICENSE` and other non-markdown FOUNDATIONAL files do not get frontmatter.

Full spec: `references/frontmatter-spec.md`.

---

## Commands

Parse the first word of `$ARGUMENTS` as the command. Default is `organize`.

| Command | File | Purpose |
|---------|------|---------|
| `organize` | `commands/organize.md` | Full repo sweep: classify every markdown file, move misplaced files, update links, stamp dates. The headline command. |
| `split-agent-docs` | `commands/split-agent-docs.md` | Split a monolithic `AGENTS.md` (or `CLAUDE.md`) into universal + agent-specific files. Sub-feature, runs independently. |
| `classify` | `commands/classify.md` | Categorize a single file or list ambiguous files in the repo without moving anything. Dry-run mode. |

If no command is given and the project has obvious uncategorized files at root → run `organize`. If the project has a monolithic agent doc with mixed content → suggest `split-agent-docs` first.

---

## When To Use This Skill

- User says: "organize agent docs", "clean up markdown", "tidy the repo", "archive mission files", "sort docs", "where should this file go".
- Mission Supervisor `brief` completes and triggers archival.
- Adding a new agent (Cursor, Copilot, etc.) and the existing CLAUDE.md mixes universal + Claude-specific content.
- Repo root has accumulated >5 markdown files and the user wants a sweep.

---

## Invariants

These hold across every command. If you find code that violates them, fix the code.

1. **This skill is the only owner of cross-category markdown moves.** Other skills that need to archive or relocate markdown delegate here.
2. **FOUNDATIONAL files live at root.** Never under `docs/`.
3. **A MISSION file's location matches its `state:`.** If they disagree, the `state:` field is authoritative — move the file to match.
4. **Links in FOUNDATIONAL files are kept current after moves.** If `AGENTS.md` links to `EXECUTION_PLAN.md` and that file moves to `docs/complete/foo-01/EXECUTION_PLAN.md`, the link in `AGENTS.md` is rewritten.
5. **`updated:` is bumped only when content is actually modified.** No churn from dry passes. (Override this default in `references/frontmatter-spec.md` if your team wants every-run stamping.)
6. **Files inside `docs/` are not re-sorted recursively.** This skill operates on the repo root; `docs/` is a destination, not a source.

---

## Sub-skill Etiquette

This SKILL.md is intentionally lean. Decision rules, edge-case handling, and patterns live in `commands/` and `references/`. Read those files when you need detail:

- Categorization rules + ambiguity prompt → `references/file-categories.md`
- Frontmatter format + state transitions → `references/frontmatter-spec.md`
- Link discovery + rewrite rules → `references/link-update-rules.md`
- Mission name derivation + artifact patterns → `references/mission-artifacts.md`

The `scripts/classify_files.py` helper scans a repo and emits a JSON proposal — useful when you want a deterministic first pass before doing edits.

---

## Related Skills

- **mission-supervisor** — Creates mission artifacts during a sortie. Delegates archival to this skill (see `mission-supervisor/commands/clean.md`, which is now a stub pointer).
- **skill-creator** — The meta-skill for writing skills. This skill follows its conventions: short SKILL.md, detail in references, clear command dispatch.
