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
| Work Unit | Deps | State | Sortie | Sortie State | Type | Model | Attempt |
|-----------|------|-------|--------|-------------|------|-------|---------|
| <name> | <deps or —> | RUNNING | 3/7 | DISPATCHED | code | sonnet | 1/3 |
| <name> | <deps or —> | NOT_STARTED | 0/5 | — | — | — | — |

Active agents: N
Blocked work units: 0
Next event: polling active agents
```

If any work unit is BLOCKED, add a prominent notice:

```
BLOCKED: <work_unit> Sortie N — FATAL after 3 attempts. Run /mission-supervisor resume to retry.
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
