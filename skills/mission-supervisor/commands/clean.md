# clean — Delegated to /organize-agent-docs

> **This command is a thin stub.** All cleanup logic now lives in the [organize-agent-docs](../../organize-agent-docs/) skill, which is the single owner of repo-level markdown organization. `clean` is preserved here as a compatibility entry point so existing flows (`brief` → `clean`) keep working.

---

## What `clean` Does Now

Invoke `/organize-agent-docs organize` against the project root containing the mission's `EXECUTION_PLAN.md`.

That skill enforces the same archival behavior `clean` used to perform directly:

- Files with `state: completed` at root → moved to `docs/complete/<mission-slug>/`.
- Files with `state: incomplete` at root → moved to `docs/incomplete/<mission-slug>/`.
- Files at root with no `state:` and a known MISSION pattern → default to `state: current` (no move).
- Foundational file links (`AGENTS.md`, `CLAUDE.md`, etc.) referencing any moved file → rewritten.
- `git mv` used for tracked files to preserve history.
- No commit. The user reviews `git status` and commits when ready.

For full mechanics see `organize-agent-docs/commands/organize.md` and `organize-agent-docs/references/mission-artifacts.md`.

---

## Command Signature

```
/mission-supervisor clean [path/to/EXECUTION_PLAN.md]
```

Resolution is unchanged: derive `$PROJECT_ROOT` from the location of `EXECUTION_PLAN.md` (or use the current directory if no plan exists). If no mission artifacts and no EXECUTION_PLAN.md exist, report the no-op and exit.

---

## Procedure

1. Resolve `$PROJECT_ROOT` per `skill.md` § Locate EXECUTION_PLAN.md.
2. If neither `EXECUTION_PLAN.md` nor `SUPERVISOR_STATE.md` exists at the resolved root, STOP:
   ```
   ERROR: Cannot clean — no mission found.
   There is no EXECUTION_PLAN.md or SUPERVISOR_STATE.md in this project root.
   ```
3. **Set MISSION state before invoking the organizer.** This is the one piece of logic that mission-supervisor retains, because state transitions are a mission-level decision (not a markdown-organization decision):
   - If every work unit in `SUPERVISOR_STATE.md` is `COMPLETED` → for every root-level MISSION file with `state: current` or no state, set `state: completed`.
   - Otherwise → set `state: incomplete`.
   - If `SUPERVISOR_STATE.md` does not exist → set `state: incomplete`.
4. Invoke `/organize-agent-docs organize $PROJECT_ROOT`. That skill performs the moves, link updates, and date stamping based on the `state:` values you just set.

---

## What Moved Out

The following used to live here; they now live in organize-agent-docs:

| Old logic | New home |
|-----------|----------|
| Mission-name derivation | `organize-agent-docs/references/mission-artifacts.md` § Deriving the Mission Slug |
| Artifact pattern list | `organize-agent-docs/references/mission-artifacts.md` § Artifact Patterns |
| Outcome (complete vs incomplete) | Retained here in Step 3, then handed off |
| `git mv` vs `mv` selection | `organize-agent-docs/commands/organize.md` § Step 4–5 |
| Destination path layout | `organize-agent-docs/references/mission-artifacts.md` § Archival Destination Layout |
| Collision handling | `organize-agent-docs/references/mission-artifacts.md` § Collision Handling |
| Report format | `organize-agent-docs/commands/organize.md` § Step 9 |

---

## What This Stub Still Owns

- Reading `SUPERVISOR_STATE.md` to decide complete vs incomplete (Step 3).
- Stamping `state:` on root-level MISSION files before the organizer runs.
- Being the entry point that `brief` auto-invokes after writing the brief file.

Everything else — moving files, updating links, stamping dates, building destination paths — is the organizer's job. Don't reintroduce that logic here.

---

## Invariant (Carried Forward)

`clean` (now via `/organize-agent-docs`) remains the only command in mission-supervisor that moves mission artifacts. No other command — `breakdown`, `refine`, `start`, `resume`, `status`, `stop`, `killall`, `completion.md`, `brief`, `name-feature` — may move, rename, archive, or delete mission artifacts. The chain is:

```
brief  →  set state: on each root MISSION file  →  /organize-agent-docs organize
```

If you find file-move logic anywhere else in mission-supervisor, delete it.
