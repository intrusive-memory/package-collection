# classify — Dry-Run Classification

Categorize a single file or every root-level markdown file without moving anything. Useful for previewing what `organize` would do, or for triaging a single file the user is unsure about.

**Referenced by**: `SKILL.md` § Commands.

---

## Command Signature

```
/organize-agent-docs classify [path]
```

- If `path` points to a single file → classify just that file and print the category + reasoning.
- If `path` points to a directory (or is omitted, defaulting to cwd) → classify every root-level markdown file and print a table.
- This command **never** moves, edits, or stages files. It's read-only.

---

## Single-File Mode

```
$ /organize-agent-docs classify ROADMAP.md

ROADMAP.md
  Category:  AMBIGUOUS
  Reasons:
    - Filename suggests project-level intent (could be foundational)
    - No frontmatter `state:` field (not mission)
    - Not a known foundational name (AGENTS/CLAUDE/GEMINI/README/CHANGELOG/LICENSE)
  Suggested:
    - If your project treats ROADMAP.md as a top-level artifact, classify as FOUNDATIONAL
      and add `roadmap` to the foundational-name list in references/file-categories.md.
    - Otherwise, EXTRANEOUS → docs/.
```

---

## Repo-Wide Mode

```
$ /organize-agent-docs classify

Repo: /Users/x/project (root only)

| File                | Category     | Current location | Expected location                          |
|---------------------|--------------|------------------|--------------------------------------------|
| AGENTS.md           | FOUNDATIONAL | root             | root  (ok)                                 |
| CLAUDE.md           | FOUNDATIONAL | root             | root  (ok)                                 |
| README.md           | FOUNDATIONAL | root             | root  (ok)                                 |
| EXECUTION_PLAN.md   | MISSION      | root             | root  (state: current, ok)                 |
| sortie-3-foo.md     | MISSION      | root             | root  (state: current, ok)                 |
| ROADMAP.md          | AMBIGUOUS    | root             | (user must decide)                         |
| notes.md            | EXTRANEOUS   | root             | docs/notes.md                              |
| old-design.md       | EXTRANEOUS   | root             | docs/old-design.md                         |

Summary: 8 files. 5 ok. 2 would move. 1 ambiguous.

Run `/organize-agent-docs organize` to apply.
```

---

## Classification Rules

The same rules `organize` uses (see `references/file-categories.md`):

1. **FOUNDATIONAL** — Name matches the known list (case-insensitive): `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CURSOR.md`, `COPILOT.md`, `CODEX.md`, `README.md`, `CHANGELOG.md`, `LICENSE`, `LICENSE.md`, `LICENSE.txt`.

2. **MISSION** — One of:
   - Filename matches a mission-artifact pattern (`EXECUTION_PLAN.md`, `SUPERVISOR_STATE.md`, `COMPLETE_*.md`, `*_BRIEF.md`, `sortie-*.{md,txt,fcpxml}`, `SORTIE-*.md`).
   - Frontmatter contains `state:` with value `current`, `completed`, or `incomplete`.
   - Listed in EXECUTION_PLAN.md's optional `clean_patterns:` array.

3. **EXTRANEOUS** — Any other markdown file at the root that doesn't trigger the AMBIGUOUS heuristics below.

4. **AMBIGUOUS** — Any of:
   - Filename suggests project-level intent: `ROADMAP.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `GOVERNANCE.md`, `MAINTAINERS.md`, `AUTHORS.md`.
   - File has `state:` field but filename is not a known mission pattern (custom mission artifact).
   - File is the target of a link from a FOUNDATIONAL file (the user evidently treats it as a top-level reference).
   - Filename has a `.md` extension but contains characters or case suggesting it's auto-generated (e.g., `_internal_*.md`, `.tmp.md`).

Files listed in `.organize-agent-docs.ignore` are classified as **IGNORED** and skipped.

---

## Output

Single-file mode: human-readable summary with category, reasons, and suggested action.

Repo-wide mode: markdown table; the calling agent can render it directly to the user.

If `--json` flag is passed, emit JSON instead — same structure as `scripts/classify_files.py` output:

```json
{
  "foundational": [...],
  "mission":      [...],
  "extraneous":   [...],
  "ambiguous":    [{"path": "ROADMAP.md", "reasons": [...]}],
  "ignored":      [...]
}
```
