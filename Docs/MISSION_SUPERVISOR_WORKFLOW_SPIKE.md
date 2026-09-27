---
type: docs
updated: 2026-09-19
---

# Spike: mission-supervisor execution loop as a Workflow script

**Question:** Should the `start`/`resume` event loop in `skills/mission-supervisor/commands/execution.md` run as a Workflow script instead of an LLM following prose?

**Answer:** Yes, as a hybrid. The skill keeps the steps that need a person or judgment: startup, the ritual, the pre-build clean, REPLAN/FATAL conversations, and writing `SUPERVISOR_STATE.md`. It hands only the dispatch → verify → retry → gate loop to the workflow. The prototype worked end to end, including a REPLAN followed by a resume in a new run. It costs more tokens per sortie and loses same-agent continuation, and those trade-offs are real. The details are below.

Prototype: [`skills/mission-supervisor/workflows/execute-mission.js`](../skills/mission-supervisor/workflows/execute-mission.js). It is not wired into the skill.

## What the prototype does

| Concern | Prose engine (`execution.md`) | Workflow prototype |
|---|---|---|
| Plan parsing | Hub reads the plan using detection heuristics | One parse agent → JSON schema. Skipped when `args.plan` is passed |
| Dependency gating | Hub checks gates after each completion | Each work unit's promise awaits its dependencies' promises. The script rejects cycles and unknown deps before running anything |
| Sortie state machine | LLM follows transition rules | Plain JS loop: PARTIAL / VERIFYING / BACKOFF / FATAL / REPLAN, with counters |
| Mechanical verification | Hub runs git and exit commands inline | A separate low-effort **checker agent**. The script can't run shell commands |
| `[judgment]` criteria | Verifier agent (PR #10) | The same, as a sonnet verifier that sees only the diff |
| REPLAN | Hub checks the evidence | A **replan-check agent** checks the evidence independently |
| PARTIAL continuation | Same agent via SendMessage (PR #10) | **A fresh agent** that re-reads `git diff startCommit..HEAD`. A workflow can't use SendMessage |
| Waiting on agents | Completion notifications | `await agent()`. The hub isn't involved at all |
| State persistence | `SUPERVISOR_STATE.md` written after every event | Journal inside the run. The final state is **returned**, and the caller writes `SUPERVISOR_STATE.md` |
| Resume, same session | `resume` re-reads the state file | `resumeFromRunId` replays cached agent results |
| Resume, new session | `resume` re-reads the state file | A new run with `args.completedSorties` (keys like `core/1`) |
| Model selection | 5-dimension score | Simplified rule: sonnet by default, opus for foundation work or attempt ≥ 3, haiku for command/background/deferred |

## Test runs

A throwaway repo in the session scratchpad. Two work units, `cli` depends on `core`. core Sortie 1 has a `[judgment]` criterion. cli Sortie 1 depends on a `core/farewell.sh` that no sortie creates, a deliberate plan defect.

| Run | What happened | Agents | Subagent tokens | Wall clock |
|---|---|---|---|---|
| 1: fresh start | Parse → core/1 implement → check → verifier PASS → **COMPLETED**. cli/1 waited for core, then implement → **REPLAN**. The replan-check accepted it with independently gathered evidence. The cli agent committed nothing. | 6 | ~253k | 99 s |
| *(human step)* | Amended the plan as the REPLAN proposed: added core Sortie 2 `farewell.sh` and fixed cli's entry criterion. | — | — | — |
| 2: new run, `completedSorties: ["core/1"]` | Re-parsed the amended plan, **skipped** core/1, core/2 → **COMPLETED**, then cli unblocked → cli/1 → **COMPLETED**. | 5 | ~207k | 76 s |

The final repo state was checked by hand, not taken from agent reports. There are 3 sortie commits with the correct `[unit sortie id]` prefixes and a clean working tree. `greet.sh` and `farewell.sh` both print usage to stderr and exit 1 when called with no arguments. `farewell-all.sh Ada Bob` prints both goodbyes.

**Not exercised:** BACKOFF retries, FATAL, PARTIAL continuations, verifier FAIL loops, deferred and manual sorties, work units running in parallel, and a real Swift build. These paths exist in the script, but none of them ran.

## Findings

### What works better than the prose engine

1. **The state machine runs as code.** Retry counters, verifier rounds, and dependency gates can't drift or be skipped by an LLM having an off day. In both runs the transitions were exactly right on the first try.
2. **The hub's context stays flat.** The main session saw two tool results for the whole mission. The prose engine grows with every event, and that growth is what forces compaction on long missions.
3. **The checker is independent.** Because the script can't run commands, a separate agent verifies exit criteria. The implementer never grades its own work, which the prose engine only achieves for `[judgment]` criteria.
4. **REPLAN worked cleanly.** It fired on the planted defect, the independent check agreed, nothing was committed, and the amend-then-resume cycle finished the mission. The plan stayed under human control throughout.
5. **Dependency gating is real concurrency.** Independent work units run at the same time with no polling. This wasn't tested because the test plan was a chain.

### What's worse or missing

1. **No same-agent continuation.** `agent()` always spawns a fresh agent, so PR #10's SendMessage continuation for PARTIAL can't be done inside a workflow. Continuations re-orient from `git diff`, which is the old behavior.
2. **The LLM parse step isn't deterministic.** The first run made up the sortie ID `core-1` where the plan says `1`. This is fixed by pinning IDs to the plan text, and run 2 came out right. The same sortie was also marked `foundation: false` in run 1 and `true` in run 2, which silently changes model selection (sonnet → opus). The parser also **writes the exit-criteria commands itself**: "prints exactly `hello, Ada`" became `test "$(bash core/greet.sh Ada)" = "hello, Ada"`. Those translations were right here, but no human reviewed them.
3. **No state file during the run.** If the session dies mid-workflow, `SUPERVISOR_STATE.md` doesn't show anything the workflow finished. Git does, though: every sortie commit carries `[unit sortie id]`, so `completedSorties` can be rebuilt from `git log`. That should become the documented recovery path.
4. **Higher token cost per sortie.** Every agent pays roughly 40k tokens of fixed startup context. A plain sortie costs 2 agents (implementer + checker), a `[judgment]` sortie 3, a REPLAN 2. The prose engine verifies inside the hub, which costs fewer tokens but grows the hub's context. The workflow buys reliability and a flat hub with extra agents.
5. **Parallel work units share one working tree.** The prose engine has the same issue, so this isn't new. `isolation: 'worktree'` would fix collisions but break the one-mission-branch model, since each work unit's branch would then need merging.
6. **The stuck-agent watchdog can't reach inside a workflow.** The prose engine kills one stalled agent after three 20-minute no-progress checks. A workflow script can't sleep or kill its own agents, and the main session can only stop the *whole* workflow. The best the hybrid can do: the skill runs the same 20-minute timer, checks the workflow journal and repo for progress, and on the third strike stops the workflow and relaunches it. Completed sorties are skipped via `completedSorties`, and the stalled sortie goes to BACKOFF. Healthy sibling agents get killed along with the hung one, which is an accepted cost that should be logged.
7. **Opt-in isn't a blocker after all.** The Workflow tool requires explicit opt-in, but a user-invoked skill whose instructions call Workflow counts as opt-in. `/mission-supervisor start` could call it directly. This corrects the earlier "needs opt-in every run" concern.

## Recommendation

Adopt it as a **hybrid** in a follow-up PR, keeping the prose engine as a fallback until one real mission has run on it:

1. **Parse once, then pin the result.** `start` parses the plan and writes the structured plan to `MISSION_PLAN.json` next to the state file, so a human can review the generated exit commands before anything is dispatched. Later runs pass it as `args.plan`, and the plan is re-parsed only when `EXECUTION_PLAN.md` changes, such as after a REPLAN amendment. This fixes finding 2.
2. **The skill owns everything with a person in it.** Startup protocol, ritual, pre-build clean, and mission branch stay in the skill. So do handling of `needsUser` results (REPLAN/FATAL/manual) and writing `SUPERVISOR_STATE.md` from the returned state.
3. **`resume` rebuilds `completedSorties` from `SUPERVISOR_STATE.md` plus the `[unit sortie id]` commit prefixes in `git log`**, which covers a session that died mid-run (finding 3). Use `resumeFromRunId` only within the same session.
4. **Accept losing same-agent continuation**, or keep the prose path for missions where PARTIAL sorties are expected to be common. A fresh agent with a precise remaining-work list and the diff did well in the prose engine for a long time.
5. **Implement the whole-workflow watchdog** from finding 6.
6. **Before switching the default,** run the untested paths on purpose: a sortie with an unachievable criterion (BACKOFF → FATAL), a verifier FAIL, two sibling work units running in parallel, and one real Swift package mission with a build gate.
