---
type: docs
---

# Shutdown Escalation — stop

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

The `stop` command follows a three-phase escalation modeled after supervisord's SIGTERM → wait → SIGKILL pattern.

**Referenced by**: `skill.md` § Argument Parsing → `stop` command.

---

## Phase 1: Drain (no new dispatches)

1. Set all `RUNNING` work units to `STOPPING`.
2. Do NOT dispatch any new sorties. Leave sorties in `PENDING` or `BACKOFF` state as-is for resume.
3. Update SUPERVISOR_STATE.md with the new states.
4. Output: `Supervisor entering graceful shutdown. Waiting for N active agents to finish.`

## Phase 2: Wait for active agents

1. Poll each active agent with `TaskOutput(block: false, timeout: 5000)`.
2. As each agent completes, process its result normally (run verification, set sortie state).
3. After processing, set the work unit state from `STOPPING` to `STOPPED`.
4. After each completion, output a brief status update.
5. **Timeout**: After 10 poll cycles with no agent completing, escalate to Phase 3.

## Phase 3: Force-terminate remaining agents

1. For any agents still running after the timeout:
   - Use `KillShell(shell_id: <task_id>)` to terminate them.
   - Set their sortie state to `BACKOFF` (preserving the attempt counter for resume).
   - Set their work unit state to `KILLED`.
   - Log in Decisions Log: `Sortie N force-terminated during graceful shutdown`.
2. Check for uncommitted work (same as Kill All Step 4 in `commands/killall.md`).
3. Update SUPERVISOR_STATE.md.
4. Output final status report (same format as Kill All Step 6 in `commands/killall.md`).

---

## Resuming After Stop

On `resume`, the supervisor reads SUPERVISOR_STATE.md:
- `STOPPED` work units → set to `RUNNING`, their current sortie remains at its last state (likely `PENDING` or `COMPLETED`).
- `KILLED` work units → set to `RUNNING`, sortie state set to `PENDING` (re-dispatch the interrupted sortie, preserving attempt counter).
