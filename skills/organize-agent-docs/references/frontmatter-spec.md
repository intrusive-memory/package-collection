# Frontmatter Specification

The skill reads and writes YAML frontmatter on FOUNDATIONAL and MISSION markdown files. This document is the authoritative spec.

---

## Format

Standard YAML frontmatter, fenced by `---` lines at the top of the file:

```yaml
---
state: current
updated: 2026-05-12
mission: steamroller-origami-01
---

# Document Title
...
```

The skill uses a minimal YAML parser (the Python `yaml` library in `scripts/classify_files.py`). It accepts:

- String values (no need to quote unless the value contains special characters).
- ISO 8601 date strings (`YYYY-MM-DD`).
- Lists with `- item` syntax.

It does **not** support:

- Multi-document YAML (`---` separators inside the document).
- Anchors and aliases (`&` / `*`).
- Complex types beyond strings, dates, and lists.

If a file's frontmatter fails to parse, the skill stops, reports the file and parse error, and asks the user to fix the YAML before continuing.

---

## FOUNDATIONAL Files

Required field: **`updated:`**

```yaml
---
updated: 2026-05-12
---
```

That's it. Anything else in the frontmatter is preserved untouched (the skill is non-destructive about existing fields it doesn't know).

**Format:** ISO date `YYYY-MM-DD`. Use the system's current local date.

**`LICENSE` and other non-`.md` foundational files:** No frontmatter. The skill never adds frontmatter to LICENSE — license-detection tools (GitHub's license API, OSI scanners) expect the raw text.

---

## MISSION Files

Required fields: **`state:`**, **`updated:`**, **`mission:`**

```yaml
---
state: current
updated: 2026-05-12
mission: steamroller-origami-01
---
```

### `state:` — Lifecycle

Valid values:

| Value | Meaning | Where the file lives |
|-------|---------|---------------------|
| `current` | On deck — part of an active mission | `$PROJECT_ROOT/<filename>` |
| `completed` | Mission finished; every work unit reached COMPLETED | `$PROJECT_ROOT/docs/complete/<mission>/<filename>` |
| `incomplete` | Mission ended without completing (abandoned, blocked, killed) | `$PROJECT_ROOT/docs/incomplete/<mission>/<filename>` |

The `state:` value is **authoritative**. If location and state disagree, move the file to match the state. (See `commands/organize.md` § Step 4.)

### `updated:` — Last Modification Date

ISO date `YYYY-MM-DD`. Bumped when the skill edits the file. See "Update Date Policy" below for the policy choice.

### `mission:` — Mission Slug

The mission this file belongs to. Format: `<operation-name-slug>-<NN>`.

- `<operation-name-slug>`: lowercase, hyphens, leading `operation-` prefix removed. `OPERATION STEAMROLLER ORIGAMI` → `steamroller-origami`.
- `<NN>`: two-digit iteration, zero-padded. First iteration is `01`.

Derivation: see `mission-artifacts.md`.

### Optional: `iteration:`

If you want the iteration number broken out separately for templates:

```yaml
---
state: completed
updated: 2026-05-12
mission: steamroller-origami-02
iteration: 2
---
```

The skill writes this when adding new frontmatter but doesn't require it.

---

## Update Date Policy

**Default: Only when actually modified.**

The skill bumps `updated:` only when it actually edited the file's content during the current run. A file that was read, classified, and left alone does not get an `updated:` bump.

**Rationale:** `updated:` should mean "this file's content was changed on this date", not "this file was looked at on this date". Bumping every run creates noise in git history and dishonest signal.

**Override:** If a project wants every-run stamping (e.g., to signal "this file was reviewed during the most recent cleanup"), create `.organize-agent-docs.config` at the repo root with:

```yaml
update_date_policy: always
```

The skill reads this at the start of every run. Valid values:

- `on-change` (default): bump only when content edits occur.
- `always`: bump on every run, regardless of edits.

---

## State Transition Authority

The skill **detects** state mismatches but does **not** decide on its own whether a mission is `completed` vs `incomplete`. Those state transitions are the domain of `mission-supervisor`:

- **`current` → `completed`** is set by `mission-supervisor/commands/completion.md` after final verification, or by `mission-supervisor/commands/brief.md` if every work unit in SUPERVISOR_STATE.md is COMPLETED.
- **`current` → `incomplete`** is set by `mission-supervisor/commands/brief.md` when the mission was abandoned, blocked, or stopped without completion.

This skill reads the `state:` field that mission-supervisor wrote and routes accordingly. It will never *change* `state:` from `current` to `completed` or vice versa without explicit user instruction.

**Exception:** When a mission file at root has *no* `state:` field, the skill adds `state: current` (consistent with its location). This is a no-op state change — the file is already where `current` files belong.

---

## Adding Frontmatter to a File That Has None

If a MISSION file has no frontmatter, prepend a minimal block:

```yaml
---
state: <derived from location: root → current, docs/complete/ → completed, docs/incomplete/ → incomplete>
updated: <today>
mission: <derived from parent dir or EXECUTION_PLAN.md, or prompted from user>
---
```

If frontmatter exists but is missing a required field, fill in the missing field; leave existing fields untouched.

If the existing frontmatter has conflicting values (e.g., `state: completed` but file is at root), `organize` will move the file to match `state:` and not mutate the state itself.

---

## Examples

### A clean foundational file

```yaml
---
updated: 2026-05-12
---

# Project README

...
```

### A foundational file with existing custom fields preserved

```yaml
---
title: "Project Documentation"
authors: ["Tom Stovall"]
updated: 2026-05-12
---

# AGENTS
...
```

The skill added `updated:` and left `title:` / `authors:` alone.

### An on-deck mission file

```yaml
---
state: current
updated: 2026-05-12
mission: steamroller-origami-01
---

# Execution Plan — OPERATION STEAMROLLER ORIGAMI

...
```

### An archived mission file

```yaml
---
state: completed
updated: 2026-04-30
mission: steamroller-origami-01
iteration: 1
---

# Iteration 01 Brief — OPERATION STEAMROLLER ORIGAMI

...
```

This file would live at `docs/complete/steamroller-origami-01/OPERATION_STEAMROLLER_ORIGAMI_01_BRIEF.md`.
