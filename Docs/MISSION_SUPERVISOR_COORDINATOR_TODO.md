---
type: docs
updated: 2026-09-19
---

# mission-supervisor: Coordinator-Pattern Improvements

Targeted changes to `skills/mission-supervisor/` from comparing it to the hub-and-spoke coordinator pattern. Conclusion of that review: mission-supervisor already *is* hub-and-spoke (supervisor = hub, sorties = spokes, no spoke-to-spoke traffic). It keeps its own state-machine discipline and adopts only the coordinator ideas that close real gaps.

## In this change

- [x] **1. Reconcile the repo copy with the installed copy.** The installed `~/.claude/skills/mission-supervisor/` (Jul 29) replaced the preflight `/dependency-purge` with an artifact-only **Pre-Build Clean** after OPERATION BOOKEND STAMP. In that mission the automatic floor bump made the Produciesta `xcodeproj` unresolvable. The repo copy (Jun 23) still does the purge. Bring the repo up to date with the installed version.
- [x] **2. Replace polling with completion notifications.** Background agents notify the supervisor when they finish, so the `TaskOutput(block:false)` polling loop and the "10 empty polls → KillShell" rule just fill the hub's context. Make "wait for notification" the default. Keep polling only for `deferred` sorties, which wait on outside conditions the harness can't track.
- [x] **3. Add a `REPLAN` sortie outcome.** A sortie that finds the *plan* is wrong (a missing API, conflicting sorties, a premise that doesn't hold) can report it without it counting as a failed attempt. The work unit stops, and the supervisor brings the proposed plan change to the user. The plan still can't be edited during execution.
- [x] **4. Continue PARTIAL sorties in the same agent.** Use `SendMessage` to resume the agent that made partial progress so it keeps its context. BACKOFF retries still start a fresh agent on purpose, because a failed agent's context is often what made it fail.
- [x] **5. Independent verifier spoke for criteria that need judgment.** Criteria that need judgment but not a human (style match, clear error messages) go to a verifier agent that sees the diff but not the implementer's reasoning. This runs *after* the checks based on git and commands, never instead of them. Truly `manual` criteria still go to the user.
- [x] **6. Diagram agent lifetimes.** Add Mermaid sequence diagrams and a comparison table to `skills/mission-supervisor/README.md` § *Agent Lifetimes*, contrasting hub-and-spoke spokes (live for the session), the old sortie agents (live for one dispatch), and the new sortie agents (live for one sortie attempt, including its continuations).

- [x] **7. Add a pre-breakdown recon pass.** `recon` (`commands/recon.md`) is the new first step of the pre-execution pipeline. It extracts every assumption the requirements make about *existing* code, resolves each declared dependency to its authoritative local checkout by indexing git remotes under `~/Projects`, and fans out up to 4 read-only verification spokes that check each assumption against **the revision the build actually resolves** — not whatever happens to be on disk. Writes `RECON_REPORT.md` and gates `breakdown`. The headline catch is `CONFIRMED_LOCAL_ONLY`: an API that exists in a sibling checkout that is ahead of its pin, which compiles locally and fails in CI. This is `REPLAN`'s cheap early-detection counterpart — same defect class, caught before a single sortie is planned.

## Follow-ups (not in this change)

- [x] **Spike: run the execution loop as a Workflow script.** Done: prototype at `skills/mission-supervisor/workflows/execute-mission.js`, write-up in [MISSION_SUPERVISOR_WORKFLOW_SPIKE.md](MISSION_SUPERVISOR_WORKFLOW_SPIKE.md). Verdict: adopt as a hybrid (skill owns startup and human-in-the-loop steps, workflow owns the dispatch/verify/retry loop).
- [ ] **Wire the workflow engine into `start`/`resume`** per the spike recommendation: pin the parsed plan to `MISSION_PLAN.json`, rebuild `completedSorties` from state and `[unit sortie id]` commit prefixes, and exercise the untested paths (BACKOFF→FATAL, verifier FAIL, parallel sibling units, a real Swift build) before switching the default.
- [ ] **Simplify model selection.** The 1x/10x/30x cost ratios look stale, and the 5-dimension scoring rubric is arithmetic an LLM does inconsistently. Candidate rule: sonnet by default, opus for foundation work or retry ≥ 2, haiku for `command`/`background`.
- [ ] **Sync the installed copy after merge.** `~/.claude/skills/mission-supervisor/` is a copied directory, not a symlink, so it won't pick up these changes automatically.
