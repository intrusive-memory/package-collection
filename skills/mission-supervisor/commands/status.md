---
type: docs
---

# Status Reporting — status

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

**Referenced by**: `skill.md` § Argument Parsing → `status` command. Also used as the output format after each iteration of the event loop during execution.

---

## Per-Iteration Status Update

After each iteration of the event loop, output a status update to the user using **formal state names only**:

```
## Supervisor Status — <timestamp>
| Work Unit | Deps | State | Sortie | Sortie State | Type | Model | Attempt | Running Since | Watchdog |
|-----------|------|-------|--------|-------------|------|-------|---------|---------------|----------|
| <name> | <deps or —> | RUNNING | 3/7 | DISPATCHED | code | sonnet | 1/3 | <Dispatched At> | 0/3 |
| <name> | <deps or —> | RUNNING | 2/4 | VERIFYING | code | sonnet | 1/3 | <Dispatched At> | 1/3 |
| <name> | <deps or —> | NOT_STARTED | 0/5 | — | — | — | — | — | — |

Active agents: N (implementers: N, verifiers: N)
Blocked work units: 0
Next event: waiting for completion notifications
```

`Watchdog` is the agent's consecutive no-progress strikes. At 3/3 the watchdog kills it (see `commands/execution.md` § 7 *Stuck Agent Watchdog*). `Running Since` alone never triggers a kill; a long-running agent that keeps making progress stays at 0/3. Also show `Next watchdog check: <arm time + 20 min>`.

When invoked as the standalone `status` command, read SUPERVISOR_STATE.md and report. Do not poll agents to refresh it.

If any work unit is BLOCKED, add a prominent notice that says which kind:

```
BLOCKED: <work_unit> Sortie N — FATAL after 3 attempts. Run /mission-supervisor resume to retry.
BLOCKED: <work_unit> Sortie N — REPLAN: <one-line defect>. Amend EXECUTION_PLAN.md, then /mission-supervisor resume.
```

---

## Final Completion Summary

When all work units complete, output:

```
## Supervisor Complete
All <total> sorties executed across <count> work units.
All exit criteria verified.

### Model Usage Summary
| Model | Sorties | Relative Cost |
|-------|---------|---------------|
| haiku | <N> | <N>x |
| sonnet | <N> | <N * 10>x |
| opus | <N> | <N * 30>x |

Total relative cost: <sum>x (baseline: haiku = 1x)
```
