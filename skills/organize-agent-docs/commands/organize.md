# organize — Full Repo Markdown Sweep

The headline command. Walk the repo root, classify every markdown file, route misplaced files to their correct location, update links in FOUNDATIONAL files, and stamp `updated:` dates where content changed.

**Referenced by**: `SKILL.md` § Commands. Invoked directly by `mission-supervisor/commands/brief.md` after a mission completes.

---

## Command Signature

```
/organize-agent-docs organize [path/to/project_root]
```

If `path` is omitted, use the current working directory. Derive `$PROJECT_ROOT` from that. Bail with a clear error if the path is not a git repository (this skill is destructive enough that `git mv` history matters).

---

## Step 1 — Scan

Enumerate every markdown file (`*.md`, `*.MD`) and every well-known no-extension foundational file (`LICENSE`, `LICENSE.txt`) at the repo root, top level only. Do **not** recurse into `docs/`, `node_modules/`, `.git/`, or any subdirectory — this skill's scope is the root.

Build `$ROOT_FILES`.

Also enumerate the contents of `docs/complete/` and `docs/incomplete/` one level deep. These hold archived mission directories; the skill needs to know about them to enforce the `state:` invariant (Step 4).

You can run `scripts/classify_files.py $PROJECT_ROOT` to get a deterministic JSON proposal:

```json
{
  "foundational": [{"path": "AGENTS.md", "kind": "agents"}, ...],
  "mission":      [{"path": "EXECUTION_PLAN.md", "state": "current", "mission": "foo-01"}, ...],
  "extraneous":   [{"path": "notes.md"}, ...],
  "ambiguous":    [{"path": "ROADMAP.md", "reason": "Could be foundational or extraneous"}]
}
```

Use the script's output as a starting proposal; verify by reading files when the classification is non-obvious.

---

## Step 2 — Classify

Apply the rules in `references/file-categories.md` to assign each file a category.

The standard names map deterministically:

- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CURSOR.md`, `COPILOT.md`, `CODEX.md`, `README.md`, `CHANGELOG.md`, `LICENSE*` → **FOUNDATIONAL**
- `EXECUTION_PLAN.md`, `SUPERVISOR_STATE.md`, `COMPLETE_*.md`, `*_BRIEF.md`, `sortie-*.*`, `SORTIE-*.md` → **MISSION**
- Files declared in EXECUTION_PLAN.md's optional `clean_patterns:` frontmatter list → **MISSION**

Anything else at root is **either EXTRANEOUS or ambiguous**. The classifier flags ambiguity when:

- The filename suggests project-level intent (e.g., `ROADMAP.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`) — these might be foundational in the user's mind.
- The file already has a `state:` field but isn't named like a known mission artifact.
- The file is referenced as a target from any FOUNDATIONAL file's links (suggesting the user treats it as foundational regardless of name).

Collect ambiguous files into `$AMBIGUOUS`. Continue with the unambiguous ones first.

---

## Step 3 — Resolve Ambiguity

If `$AMBIGUOUS` is non-empty, prompt the user with `AskUserQuestion`. Batch all ambiguous files into a single prompt (one question per file, or one multi-select question if many) with these choices:

- **Foundational** — Keep at root, treat as foundational going forward (add to the known-names list in `references/file-categories.md` as a follow-up).
- **Mission** — Treat as mission artifact. Ask follow-up: which state and which mission slug? (Default to `current` if file is at root with no state field.)
- **Extraneous** — Move to `docs/`.
- **Leave in place** — Do not move. Record this decision so the next run doesn't ask again (add to `.organize-agent-docs.ignore` at repo root).
- **Delete** — Remove the file. Use `git rm` if tracked. Confirm before doing this.

If the user picks "Leave in place" for a file, append its path to `.organize-agent-docs.ignore` (one path per line, gitignore-style globs welcome). The skill reads this file at Step 1 of every future run and silently skips matched paths.

---

## Step 4 — Enforce MISSION state ↔ location

For every MISSION file (both at root and inside `docs/complete/` / `docs/incomplete/`):

1. Read its `state:` frontmatter.
2. Compute its expected location:
   - `current`    → `$PROJECT_ROOT/<filename>` (root)
   - `completed`  → `$PROJECT_ROOT/docs/complete/<mission>/<filename>`
   - `incomplete` → `$PROJECT_ROOT/docs/incomplete/<mission>/<filename>`
3. If the actual location does not match the expected one, **move the file** to match. The `state:` field is authoritative.

Use `git mv` when the file is tracked (test with `git ls-files --error-unmatch <file>`), `mv` otherwise. If the destination filename already exists, append `.dup-<timestamp>` and warn — never overwrite.

If a mission file at root has **no** `state:` field, default to `current` (it's at root, so this is consistent) and add the field. Also add `updated:` and `mission:` if missing. Derive `mission:` from the parent directory if the file is in `docs/complete/<mission>/`, or from the EXECUTION_PLAN.md frontmatter if you can locate it; otherwise prompt the user.

Mission name derivation rules: `references/mission-artifacts.md`.

---

## Step 5 — Move EXTRANEOUS files into `docs/`

For each file classified EXTRANEOUS:

1. Ensure `$PROJECT_ROOT/docs/` exists. Create it if not (`mkdir -p`).
2. Move the file: `git mv <file> docs/<file>` (or `mv` if untracked).
3. If `docs/<file>` already exists, append `.dup-<timestamp>` and warn.

Do **not** organize files already inside `docs/`. This skill's source is the root only.

---

## Step 6 — Update Links in FOUNDATIONAL files

Every move in Steps 4 and 5 may have broken a link in a FOUNDATIONAL file. For each FOUNDATIONAL file at root:

1. Read it.
2. Find every relative markdown link (`[text](relative/path.md)`) and every relative reference image / asset link.
3. If the linked path was moved during this run, rewrite the link to the new path.
4. If the linked path no longer exists anywhere (was deleted), warn — leave a `<!-- BROKEN LINK: <old-path> -->` comment immediately above the original link rather than silently dropping it. Surface this to the user at the end.

Full discovery + rewrite rules: `references/link-update-rules.md`.

Track which FOUNDATIONAL files you actually edited in `$EDITED_FOUNDATIONAL`.

---

## Step 7 — Stamp `updated:` on Modified FOUNDATIONAL Files

For each file in `$EDITED_FOUNDATIONAL`:

1. If the file already has frontmatter, update or insert `updated: <today>` (ISO date, e.g., `2026-05-12`).
2. If the file has no frontmatter, prepend a minimal block:

   ```yaml
   ---
   updated: 2026-05-12
   ---
   ```

3. `LICENSE` and other non-markdown FOUNDATIONAL files are exempt from frontmatter — skip them silently.

Files **not** in `$EDITED_FOUNDATIONAL` are not touched. This keeps `updated:` honest: it means "this file was edited on this date", not "this file was reviewed on this date".

To change this policy, see `references/frontmatter-spec.md` § Update Date Policy.

---

## Step 8 — Do Not Commit

Stage moves (when `git mv` was used) but do not create a commit. The user reviews `git status` and commits when ready. This mirrors the old mission-supervisor `clean` behavior and prevents this skill from polluting history when run mid-investigation.

---

## Step 9 — Report

Output a structured summary:

```
Repo markdown sweep complete.
Project root: <path>

Moved (<N>):
  EXTRANEOUS → docs/:
    - notes.md           → docs/notes.md
    - ideas.md           → docs/ideas.md
  MISSION state correction:
    - EXECUTION_PLAN.md  → docs/complete/foo-01/EXECUTION_PLAN.md  (state: completed)
  MISSION new at root:
    - sortie-7-bar.md    (state: current, mission: foo-02)

FOUNDATIONAL files edited (<N>):
  - AGENTS.md           (3 links rewritten, updated: 2026-05-12)
  - README.md           (1 link rewritten, updated: 2026-05-12)

Frontmatter added/updated (<N>):
  - sortie-7-bar.md     (state, updated, mission)

Ambiguous, asked user (<N>):
  - ROADMAP.md          → EXTRANEOUS

Skipped via .organize-agent-docs.ignore (<N>):
  - LOCAL_NOTES.md

Warnings:
  - 1 broken link in AGENTS.md → see HTML comment near line 42.

Review with `git status` and commit when ready.
```

If nothing needed moving:

```
Nothing to organize. All <N> markdown files are in their correct locations.
```

---

## Idempotence

Running `organize` twice in a row with no intervening changes is a no-op. The skill must:

- Re-classify and re-check `state:` ↔ location on every run.
- Skip moves whose source == destination.
- Not bump `updated:` if no content was edited.
- Not re-prompt for files listed in `.organize-agent-docs.ignore`.

If the second run reports any moves or edits, that's a bug — file it.
