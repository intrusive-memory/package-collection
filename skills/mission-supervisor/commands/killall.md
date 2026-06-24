---
type: docs
---

# Kill All Procedure — killall

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

When `killall` is invoked, execute these steps in exact order. This skips the graceful drain/wait phases — it is an emergency stop.

**Referenced by**: `skill.md` § Argument Parsing → `killall` command.

---

## Step 1: Identify All Active Agents

Read SUPERVISOR_STATE.md and collect every entry from the `## Active Agents` table. Each row has a Task ID.

## Step 2: Terminate Every Agent

For each active agent, use the **KillShell** tool with the task ID to terminate it immediately. Do this for ALL agents — do not skip any.

```
For each agent in Active Agents table:
  → KillShell(shell_id: <task_id>)
```

If KillShell fails for a specific agent (already finished, invalid ID), log it and continue to the next one. Do not stop the killall process because one kill failed.

## Step 3: Assess Work Unit State

After all agents are terminated, check each work unit's state using the verification cascade (see `commands/execution.md` § Verification):

- If the last sortie completed successfully: work unit state → `KILLED`, sortie state → `COMPLETED`. Clean state.
- If the last sortie was in-progress and did NOT complete: work unit state → `KILLED`, sortie state → `BACKOFF` (preserve attempt counter).
- If no progress files exist: work unit state → `NOT_STARTED`.

## Step 4: Check For Uncommitted Work

For each work unit directory, run:
```bash
git status --porcelain -- <work_unit_dir>
```

If there are uncommitted changes from a killed agent:
- Do NOT commit them. They may be incomplete or broken.
- Do NOT discard them. The user may want to inspect them.
- Record in SUPERVISOR_STATE.md: `<work_unit>: has uncommitted work from killed Sortie N`

## Step 5: Update SUPERVISOR_STATE.md

Clear the Active Agents table. Update each work unit status. Set the overall status to `killed`. Write the file.

```markdown
## Overall Status
Status: killed
Kill reason: user invoked killall
Kill timestamp: <ISO 8601>

## Active Agents
(none — all agents terminated)
```

## Step 6: Report to User

Output a summary:

```
## Kill All Complete

Agents terminated: N
Work units with uncommitted work: <list or "none">

Work unit states after kill:
| Work Unit | Last Completed Sortie | Uncommitted Work | Action Needed |
|-----------|----------------------|------------------|---------------|
| <name> | Sortie N | yes/no | resume from N+1 / restart N |
| ... | ... | ... | ... |

To resume: /mission-supervisor resume
To discard uncommitted work and resume cleanly:
  cd <work-unit-dir> && git checkout -- . && git clean -fd
  Then: /mission-supervisor resume
```
