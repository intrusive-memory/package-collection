# File Categories — Full Taxonomy

The three categories every markdown (and a few non-markdown) file in a repository's root falls into. Read this when you need to classify edge-case files or extend the rules.

---

## FOUNDATIONAL

**What:** Project-level documentation that lives at the repo root because every contributor and every agent expects to find it there.

**Canonical list** (case-insensitive; the file must exist at the root):

| Name | Purpose | Frontmatter? |
|------|---------|--------------|
| `AGENTS.md` | Universal agent instructions | yes |
| `CLAUDE.md` | Claude-specific instructions | yes |
| `GEMINI.md` | Gemini-specific instructions | yes |
| `CURSOR.md` | Cursor-specific instructions | yes |
| `COPILOT.md` | GitHub Copilot-specific instructions | yes |
| `CODEX.md` | Codex-specific instructions | yes |
| `README.md` | Human-facing project intro | yes |
| `CHANGELOG.md` | Version history | yes |
| `LICENSE` | Legal license text (no extension) | no |
| `LICENSE.md` / `LICENSE.txt` | Same, with extension | no |

**Rules:**

- FOUNDATIONAL files must live at the repo root. Never under `docs/`.
- All `.md` foundational files get an `updated:` frontmatter field, bumped only when the skill actually edits the file (see `frontmatter-spec.md`).
- `LICENSE` is exempt from frontmatter — it must remain machine-readable for license-detection tools.
- The skill never edits LICENSE content. It can rename `LICENSE.txt` ↔ `LICENSE.md` only if the user explicitly asks.

**Extending the list:**

If a project consistently treats another file as foundational (e.g., `STYLEGUIDE.md` for a writing-heavy repo), append it to the project's `.organize-agent-docs.foundational` file (one filename per line). The skill reads this on every run and merges it with the canonical list.

---

## MISSION

**What:** Files created by Mission Supervisor (formerly Sprint Supervisor) during a specific mission. They have a lifecycle: created at root → archived to `docs/<bucket>/<mission>/` when the mission ends.

**Canonical name patterns:**

| Pattern | What it is |
|---------|-----------|
| `EXECUTION_PLAN.md` | The mission plan |
| `SUPERVISOR_STATE.md` | Per-sortie execution state |
| `COMPLETE_*.md` | Final completion log (e.g., `COMPLETE_PROYECTO.md`) |
| `*_BRIEF.md` | Post-mission briefs (e.g., `OPERATION_STEAMROLLER_ORIGAMI_01_BRIEF.md`) |
| `sortie-*.md` | Sortie deliverables (lowercase) |
| `sortie-*.txt` | Sortie deliverables (plain text) |
| `sortie-*.fcpxml` | Sortie deliverables (FCPXML output) |
| `SORTIE-*.md` | Sortie deliverables (uppercase variant) |

In addition, any file listed in `EXECUTION_PLAN.md`'s optional `clean_patterns:` frontmatter array is treated as MISSION.

**Lifecycle:**

```
┌──────────────────┐
│  state: current  │  → file lives in $PROJECT_ROOT (on deck)
└──────────────────┘
         │
         │  (mission finishes; all work units COMPLETED)
         ▼
┌──────────────────┐
│ state: completed │  → file lives in docs/complete/<mission>/
└──────────────────┘

         OR

         │  (mission abandoned, blocked, or interrupted)
         ▼
┌──────────────────┐
│ state: incomplete│  → file lives in docs/incomplete/<mission>/
└──────────────────┘
```

The skill enforces this invariant: a MISSION file's `state:` MUST match its location. If they disagree, the `state:` is authoritative and the file is moved to match.

**Mission name derivation:** see `mission-artifacts.md`.

---

## EXTRANEOUS

**What:** Any other markdown file at the root. Notes, drafts, design docs, scratch files, anything that isn't FOUNDATIONAL and isn't tied to a Mission Supervisor mission.

**Default action:** Move to `docs/`.

**Examples:**

- `notes.md`, `ideas.md`, `scratch.md`
- `old-design.md`, `meeting-2026-04-12.md`
- `proposal-draft.md`

The skill does **not** sort within `docs/` — once a file lands there, it's the user's to organize further. (`docs/complete/` and `docs/incomplete/` are exceptions: they're reserved for archived MISSION files.)

---

## AMBIGUOUS

**What:** Files that don't fit cleanly. Flagged for user confirmation during `organize`.

**Heuristics that trigger AMBIGUOUS:**

1. **Project-meta filenames** — `ROADMAP.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `GOVERNANCE.md`, `MAINTAINERS.md`, `AUTHORS.md`, `INSTALL.md`, `BUILDING.md`, `TESTING.md`. These are commonly foundational but not universal — some teams keep them at root, others under `docs/`.

2. **Custom mission artifacts** — File has frontmatter `state:` set to a valid value (`current`/`completed`/`incomplete`) but its filename doesn't match a known mission pattern. The user may have a custom artifact type the skill doesn't know about.

3. **Referenced from a FOUNDATIONAL file** — A FOUNDATIONAL file links to this file with a relative path. The user evidently treats it as a top-level reference, even if its name isn't on the canonical list.

4. **Conflicting signals** — File matches a mission pattern AND lives under `docs/` (orphaned archive?), or matches a foundational name AND has a `state:` field.

**Resolution:** Batch all AMBIGUOUS files into one `AskUserQuestion` prompt with options Foundational / Mission / Extraneous / Leave-in-place / Delete. See `commands/organize.md` § Step 3.

After the user resolves, optionally persist the decision:

- "Treat ROADMAP.md as foundational" → add `ROADMAP.md` to `.organize-agent-docs.foundational`.
- "Leave LOCAL_NOTES.md alone" → add `LOCAL_NOTES.md` to `.organize-agent-docs.ignore`.

---

## IGNORED

Not a real category — just a way to express "user told me to leave this alone".

**Source:** A file matches a pattern in `.organize-agent-docs.ignore` (gitignore-style globs, one per line, at the repo root).

**Behavior:** The skill silently skips these files during classification and routing. Use sparingly — anything in this file is a sign the rules need tightening.

---

## Configuration Files

The skill recognizes two optional configuration files at the repo root:

| File | Format | Purpose |
|------|--------|---------|
| `.organize-agent-docs.foundational` | One filename per line | Extend the FOUNDATIONAL list with project-specific names. |
| `.organize-agent-docs.ignore` | Gitignore-style globs | Files to skip during classification. |

Both are optional. Neither is created automatically; the skill writes to them only when the user explicitly answers "Treat as foundational" or "Leave in place" during an AMBIGUOUS prompt.
