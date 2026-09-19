---
type: docs
updated: 2026-09-19
---

# mission-supervisor: Coordinator-Pattern Improvements

Targeted changes to `skills/mission-supervisor/` from comparing it to the hub-and-spoke coordinator pattern. Conclusion of that review: mission-supervisor already *is* hub-and-spoke (supervisor = hub, sorties = spokes, no spoke-to-spoke traffic). It keeps its own state-machine discipline and adopts only the coordinator ideas that close real gaps.

## In this change

- [ ] **1. Reconcile the repo copy with the installed copy.** The installed `~/.claude/skills/mission-supervisor/` (Jul 29) replaced the preflight `/dependency-purge` with an artifact-only **Pre-Build Clean** after OPERATION BOOKEND STAMP. In that mission the automatic floor bump made the Produciesta `xcodeproj` unresolvable. The repo copy (Jun 23) still does the purge. Bring the repo up to date with the installed version.
- [ ] **2. Replace polling with completion notifications.** Background agents notify the supervisor when they finish, so the `TaskOutput(block:false)` polling loop and the "10 empty polls → KillShell" rule just fill the hub's context. Make "wait for notification" the default. Keep polling only for `deferred` sorties, which wait on outside conditions the harness can't track.
- [ ] **3. Add a `REPLAN` sortie outcome.** A sortie that finds the *plan* is wrong (a missing API, conflicting sorties, a premise that doesn't hold) can report it without it counting as a failed attempt. The work unit stops, and the supervisor brings the proposed plan change to the user. The plan still can't be edited during execution.
- [ ] **4. Continue PARTIAL sorties in the same agent.** Use `SendMessage` to resume the agent that made partial progress so it keeps its context. BACKOFF retries still start a fresh agent on purpose, because a failed agent's context is often what made it fail.
- [ ] **5. Independent verifier spoke for criteria that need judgment.** Criteria that need judgment but not a human (style match, clear error messages) go to a verifier agent that sees the diff but not the implementer's reasoning. This runs *after* the checks based on git and commands, never instead of them. Truly `manual` criteria still go to the user.

## Follow-ups (not in this change)

- [ ] **Spike: run the execution loop as a Workflow script.** The event loop is a deterministic state machine that an LLM currently simulates by hand. A Workflow script would run it for real and keep the hub's context clear. Trade-offs: the conversational "sergeant" leaves the loop, and each run needs explicit opt-in. Evaluate before investing further in the prose engine.
- [ ] **Simplify model selection.** The 1x/10x/30x cost ratios look stale, and the 5-dimension scoring rubric is arithmetic an LLM does inconsistently. Candidate rule: sonnet by default, opus for foundation work or retry ≥ 2, haiku for `command`/`background`.
- [ ] **Sync the installed copy after merge.** `~/.claude/skills/mission-supervisor/` is a copied directory, not a symlink, so it won't pick up these changes automatically.
