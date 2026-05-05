---
name: clean
description: Move every mission artifact in the project root into docs/<complete|incomplete>/<mission name>/.
---

# Mission Clean — Archive Mission Artifacts

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission. *Clean* sweeps all root-level mission artifacts into a structured archive so the workspace returns to a pre-mission state.

This document defines the `clean` command — the single, authoritative archival step for the Mission Supervisor. It is the only place file moves should happen.

**Referenced by**: `skill.md` § Argument Parsing → `clean` command, `commands/brief.md` (auto-triggered after brief is written).

---

## When to Run

- Automatically — invoked by `brief` after the brief file is written.
- Manually — `/mission-supervisor clean` after a mission ends, even if `brief` was skipped.
- Idempotent — if no mission artifacts exist in the root, `clean` is a no-op and reports nothing was found.

---

## Command Signature

```
/mission-supervisor clean [path/to/EXECUTION_PLAN.md]
```

Path resolution follows standard rules from `skill.md` § Locate EXECUTION_PLAN.md.

If neither EXECUTION_PLAN.md nor SUPERVISOR_STATE.md exists at the resolved root, STOP:
```
ERROR: Cannot clean — no mission found.
There is no EXECUTION_PLAN.md or SUPERVISOR_STATE.md in this project root.
```

---

## Step 1 — Determine Outcome

Decide the destination bucket: `complete` vs `incomplete`.

1. Read SUPERVISOR_STATE.md (if it exists).
2. If **every** work unit's state is `COMPLETED` → outcome is `complete`.
3. Otherwise (any work unit `NOT_STARTED`, `RUNNING`, `STOPPING`, `STOPPED`, `BLOCKED`, `KILLED`) → outcome is `incomplete`.
4. If SUPERVISOR_STATE.md does not exist (mission was never started) → outcome is `incomplete`.

Store as `$OUTCOME` ∈ {`complete`, `incomplete`}.

---

## Step 2 — Derive Mission Name

Read `feature_name` from EXECUTION_PLAN.md frontmatter, then build the mission directory name:

1. Lowercase the feature name.
2. Replace whitespace with hyphens.
3. Drop the leading `operation-` prefix.
4. Append `-<NN>` where `<NN>` is the two-digit `iteration` from frontmatter (default `01` if missing).

Example: `OPERATION STEAMROLLER ORIGAMI`, iteration 1 → `steamroller-origami-01`.

Store as `$MISSION_NAME`.

If EXECUTION_PLAN.md is missing or has no `feature_name`, fall back to `unknown-mission-<timestamp>` and warn the user.

---

## Step 3 — Build Destination

```
$DEST = $PROJECT_ROOT/docs/$OUTCOME/$MISSION_NAME/
```

Create it: `mkdir -p $DEST`.

---

## Step 4 — Identify Mission Artifacts

Scan `$PROJECT_ROOT` (top level only — never recurse) for files matching these patterns:

| Pattern | Description |
|---------|-------------|
| `EXECUTION_PLAN.md` | The mission plan |
| `SUPERVISOR_STATE.md` | The execution state |
| `COMPLETE_*.md` | Completion logs |
| `*_BRIEF.md` | Iteration briefs (e.g., `OPERATION_STEAMROLLER_ORIGAMI_01_BRIEF.md`) |
| `sortie-*.md` | Sortie deliverables (markdown) |
| `sortie-*.txt` | Sortie deliverables (text) |
| `sortie-*.fcpxml` | Sortie deliverables (FCPXML) |
| `SORTIE-*.md` | Sortie deliverables (uppercase variant) |

If a mission's plan uses additional artifact patterns documented in EXECUTION_PLAN.md frontmatter under `clean_patterns:` (optional list of globs), include those too.

Build the list as `$ARTIFACTS`. If empty, jump to Step 7 (no-op report).

---

## Step 5 — Move Each Artifact

For each file in `$ARTIFACTS`:

1. If the file is tracked by git:
   ```
   git mv <file> $DEST<file>
   ```
   This preserves history. Use `git ls-files --error-unmatch <file>` to test trackedness.
2. If the file is not tracked:
   ```
   mv <file> $DEST<file>
   ```
3. If a file with the same name already exists at the destination (e.g., re-running clean after a partial move), append `.dup-<timestamp>` to the destination filename and warn the user. Do not overwrite.

Keep the original filenames inside `$DEST`. Do **not** rename, compress, or transform contents. The mission name lives in the directory, not the filename.

---

## Step 6 — Do Not Commit

`clean` stages moves (when git mv was used) but does **not** create a commit. The user reviews `git status` and commits when ready. This keeps the user in control of the final commit message and prevents `clean` from polluting history when run mid-investigation.

If the user wants automatic commits, they invoke `clean` and then commit themselves, or wire a wrapper script.

---

## Step 7 — Report

On success:

```
Mission cleanup complete.
Outcome:     <complete | incomplete>
Mission:     <MISSION_NAME>
Destination: docs/<OUTCOME>/<MISSION_NAME>/

Moved (<N>):
  - EXECUTION_PLAN.md
  - SUPERVISOR_STATE.md
  - COMPLETE_<PROJECT_NAME>.md
  - <OPERATION_NAME>_<NN>_BRIEF.md
  - sortie-1-foo.md
  - sortie-2-bar.md
  ...

Review with `git status` and commit when ready.
```

If nothing was found:
```
Nothing to clean. No mission artifacts found in <PROJECT_ROOT>.
```

If the destination already had collisions:
```
Warning: <N> file(s) already existed at the destination and were renamed with .dup-<timestamp> suffixes:
  - <file>
```

---

## What `clean` Does NOT Do

- It does **not** generate the brief — run `brief` first (or let `brief` auto-trigger `clean`).
- It does **not** delete files. Everything goes into `docs/`.
- It does **not** commit. The user commits.
- It does **not** perform the rollback ritual. That stays in `brief.md` and runs after `clean` if the verdict is "discard and iterate".
- It does **not** touch anything already inside `docs/`.
- It does **not** recurse into subdirectories of `$PROJECT_ROOT` looking for mission artifacts. Only top-level files.

---

## Interaction With Other Commands

- **`brief`**: Always invokes `clean` automatically as its final step (before any optional rollback ritual). The user does not need to run `clean` separately after `brief`.
- **`completion.md`**: Performs final verification and writes to `COMPLETE_<PROJECT_NAME>.md` in place. It does **not** move or delete files. It triggers `brief`, which in turn triggers `clean`. So the order at mission completion is: completion log → brief → clean.
- **Rollback ritual** in `brief.md`: After `clean`, the brief lives at `docs/<bucket>/<MISSION_NAME>/<OPERATION_NAME>_<NN>_BRIEF.md`. The rollback ritual checks out the brief from that path on the mission branch.

## Invariant

**`clean` is the only command in this skill that moves or deletes files.** No other command — `breakdown`, `refine`, `start`, `resume`, `status`, `stop`, `killall`, `completion.md`, `brief`, `name-feature` — may move, rename, archive, or delete mission artifacts. If you are reading this skill and find file-move logic anywhere outside `commands/clean.md`, delete it.
