# Mission Artifacts — Patterns and Derivation

How to recognize a MISSION file and how to derive its `mission:` slug. This document captures rules previously owned by `mission-supervisor/commands/clean.md`.

---

## Artifact Patterns

A file is a MISSION artifact if its filename matches any of these patterns (case-sensitive unless noted):

| Pattern | What it is |
|---------|-----------|
| `EXECUTION_PLAN.md` | The mission plan |
| `SUPERVISOR_STATE.md` | Sortie execution state |
| `COMPLETE_*.md` | Completion log (e.g., `COMPLETE_PROYECTO.md`) |
| `*_BRIEF.md` | Post-mission brief (uppercase operation name + iteration) |
| `sortie-*.md` | Sortie deliverable (markdown) |
| `sortie-*.txt` | Sortie deliverable (plain text) |
| `sortie-*.fcpxml` | Sortie deliverable (FCPXML) |
| `SORTIE-*.md` | Sortie deliverable (uppercase) |

A file is also a MISSION artifact if its frontmatter has `state:` set to one of `current`, `completed`, `incomplete` — regardless of filename. This catches custom artifact types declared in EXECUTION_PLAN.md's optional `clean_patterns:` array.

---

## Deriving the Mission Slug

The `mission:` frontmatter field has the form `<operation-name-slug>-<NN>` (e.g., `steamroller-origami-01`).

### Source priority for the slug

1. **The file's own frontmatter `mission:`** — if present, trust it.

2. **The parent directory name** when the file is already inside an archive:

   - `docs/complete/<slug>/<file>` → `mission: <slug>`
   - `docs/incomplete/<slug>/<file>` → `mission: <slug>`

3. **EXECUTION_PLAN.md at the same root** — read its `feature_name` and `iteration` from frontmatter:

   ```yaml
   feature_name: OPERATION STEAMROLLER ORIGAMI
   iteration: 1
   ```

   Compute:

   - Lowercase `feature_name`.
   - Replace whitespace with hyphens.
   - Drop a leading `operation-` prefix.
   - Append `-<NN>` where `<NN>` is `iteration` zero-padded to 2 digits.

   Result: `steamroller-origami-01`.

   If `iteration` is missing, default to `01`.

4. **Filename pattern** — for `*_BRIEF.md` files, the operation name and iteration are embedded in the filename:

   - `OPERATION_STEAMROLLER_ORIGAMI_03_BRIEF.md`
   - Split on `_`, drop `OPERATION` prefix, drop `BRIEF.md` suffix.
   - The last segment before `BRIEF` is the iteration; the rest is the operation name.
   - Lowercase and join with hyphens: `steamroller-origami-03`.

5. **User prompt** — if none of the above resolves, prompt with `AskUserQuestion`:

   ```
   File <filename> is a mission artifact but I can't determine which mission it belongs to.
   Please provide the mission slug (e.g., "steamroller-origami-01"):
   ```

   Once the user answers, write the slug into the file's frontmatter so the next run doesn't ask again.

---

## Deriving State from Location

Used when a MISSION file has no `state:` frontmatter.

| Location | Derived state |
|----------|---------------|
| `$PROJECT_ROOT/<filename>` | `current` |
| `$PROJECT_ROOT/docs/complete/<slug>/<filename>` | `completed` |
| `$PROJECT_ROOT/docs/incomplete/<slug>/<filename>` | `incomplete` |
| Anywhere else | Prompt the user. Don't guess. |

If a MISSION file is found somewhere unexpected (e.g., `docs/<filename>` directly, no mission subdirectory), treat it as AMBIGUOUS and ask the user whether to:

- Move it to `docs/complete/<slug>/` or `docs/incomplete/<slug>/` (need slug — derive or prompt).
- Treat it as EXTRANEOUS (it lost its mission affiliation).
- Leave in place (add to `.organize-agent-docs.ignore`).

---

## Determining Outcome (complete vs incomplete)

For a fresh archival (file at root with `state: current`, mission has just ended and needs archiving):

1. Read `SUPERVISOR_STATE.md` from the project root, if it exists.
2. If **every** work unit's state is `COMPLETED` → outcome is `complete`.
3. Otherwise (any NOT_STARTED, RUNNING, STOPPING, STOPPED, BLOCKED, KILLED) → outcome is `incomplete`.
4. If `SUPERVISOR_STATE.md` does not exist (mission was never started) → outcome is `incomplete`.

This logic is identical to the old `mission-supervisor/commands/clean.md` § Step 1, preserved here for continuity.

**Important:** This skill does not *transition* `state:` from `current` to `completed`/`incomplete` automatically. That transition is owned by `mission-supervisor/commands/brief.md` (which writes the final state values before invoking this skill for archival). The skill only routes files based on the `state:` value mission-supervisor already wrote.

---

## Archival Destination Layout

For a mission with slug `steamroller-origami-01`:

```
docs/
├── complete/                              # if outcome == complete
│   └── steamroller-origami-01/
│       ├── EXECUTION_PLAN.md
│       ├── SUPERVISOR_STATE.md
│       ├── COMPLETE_PROYECTO.md
│       ├── OPERATION_STEAMROLLER_ORIGAMI_01_BRIEF.md
│       ├── sortie-1-foo.md
│       └── sortie-2-bar.md
└── incomplete/                            # if outcome == incomplete
    └── steamroller-origami-01/
        └── ...
```

Inside the mission directory, original filenames are preserved. The mission name lives in the directory, not the filename.

---

## Collision Handling

If a destination filename already exists (e.g., re-running `organize` after a partial move was interrupted):

1. Append `.dup-<UTC-timestamp>` to the destination filename.
2. Warn the user in the final report.
3. Never overwrite.

Example: `EXECUTION_PLAN.md.dup-20260512T143022Z`.

---

## What This Skill Does NOT Decide

This skill is a *router*, not a *judge*. It does not:

- Decide whether a mission was successful (that's `mission-supervisor`'s job via `brief`).
- Generate `COMPLETE_*.md` files (that's `mission-supervisor/commands/completion.md`).
- Write `*_BRIEF.md` files (that's `mission-supervisor/commands/brief.md`).
- Commit moves (the user reviews and commits).
- Delete files (only on explicit user confirmation during AMBIGUOUS resolution).
- Touch anything already inside `docs/` *except* to enforce the state ↔ location invariant on existing MISSION files.

If you find yourself extending this skill to do any of those things, stop. They belong in `mission-supervisor`.
