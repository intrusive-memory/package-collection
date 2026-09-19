export const meta = {
  name: 'mission-execute',
  description: 'SPIKE: execute a mission-supervisor EXECUTION_PLAN.md as a deterministic workflow (dependency DAG, retries, verifier, REPLAN)',
  whenToUse: 'Experimental alternative to the prose event loop in commands/execution.md. Args: {projectRoot, planPath?, plan?, completedSorties?, maxRetries?, maxVerifierRounds?, maxContinuations?}',
  phases: [
    { title: 'Parse', detail: 'EXECUTION_PLAN.md -> structured plan (skipped if args.plan given)' },
    { title: 'Execute', detail: 'work units run as a dependency DAG; sorties sequential within a unit' },
  ],
}

// ---------------------------------------------------------------------------
// Spike notes (see Docs/MISSION_SUPERVISOR_WORKFLOW_SPIKE.md for the write-up)
//
// - The script has no filesystem access, so it cannot read EXECUTION_PLAN.md or
//   write SUPERVISOR_STATE.md itself. A parse agent reads the plan; the script
//   RETURNS the final state and the calling supervisor writes SUPERVISOR_STATE.md.
// - Cross-session resume: pass args.completedSorties (["<unit>/<sortieId>", ...])
//   rebuilt from SUPERVISOR_STATE.md + git. Same-session resume uses the
//   Workflow tool's resumeFromRunId (cached agent results).
// - agent() always spawns a fresh agent. There is no SendMessage from inside a
//   workflow, so PARTIAL continuations are fresh agents that re-orient from git.
// - The script cannot run shell commands, so mechanical verification is a
//   separate low-effort "checker" agent. That makes it independent of the
//   implementer (an improvement), at the cost of one extra agent per attempt.
// - Human-in-the-loop states (REPLAN, FATAL, manual) end that work unit's run
//   and are returned; the human acts between workflow runs.
// ---------------------------------------------------------------------------

const A = args || {}
const ROOT = A.projectRoot
if (!ROOT) throw new Error('args.projectRoot is required')
const PLAN_PATH = A.planPath || `${ROOT}/EXECUTION_PLAN.md`
const MAX_RETRIES = A.maxRetries || 3
const MAX_VERIFIER_ROUNDS = A.maxVerifierRounds || 2
const MAX_CONTINUATIONS = A.maxContinuations || 3
const ALREADY_DONE = new Set(A.completedSorties || [])

// ---------------------------------------------------------------- schemas
const STR = { type: 'string' }
const STRS = { type: 'array', items: STR }

const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    workUnits: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: STR,
          directory: STR,
          dependsOn: STRS,
          sorties: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                id: STR,
                name: STR,
                type: { type: 'string', enum: ['code', 'command', 'background', 'deferred', 'manual'] },
                definition: { type: 'string', description: 'The full sortie definition from the plan, verbatim (tasks, notes, commands).' },
                entryCriteria: STRS,
                exitCriteria: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      text: STR,
                      kind: { type: 'string', enum: ['command', 'assertion', 'judgment', 'checklist'] },
                      command: { type: 'string', description: 'Shell command to run from the project root, for kind=command.' },
                    },
                    required: ['text', 'kind'],
                  },
                },
                foundation: { type: 'boolean', description: 'True if this sortie establishes patterns 2+ later sorties depend on.' },
                model: { type: 'string', enum: ['haiku', 'sonnet', 'opus'], description: 'Only if the plan pins a model.' },
              },
              required: ['id', 'name', 'type', 'definition', 'exitCriteria'],
            },
          },
        },
        required: ['name', 'sorties'],
      },
    },
  },
  required: ['workUnits'],
}

const IMPL_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'partial', 'failed', 'replan'] },
    startCommit: { type: 'string', description: 'Output of `git rev-parse HEAD` taken BEFORE you changed anything.' },
    summary: STR,
    remaining: STRS,
    replan: {
      type: 'object',
      properties: { defect: STR, evidence: STR, proposedChange: STR, affectedSorties: STRS },
      required: ['defect', 'evidence', 'proposedChange', 'affectedSorties'],
    },
  },
  required: ['status', 'startCommit', 'summary'],
}

const CHECK_SCHEMA = {
  type: 'object',
  properties: {
    results: {
      type: 'array',
      items: {
        type: 'object',
        properties: { criterion: STR, passed: { type: 'boolean' }, evidence: STR },
        required: ['criterion', 'passed', 'evidence'],
      },
    },
    allPassed: { type: 'boolean' },
    progressSinceStart: { type: 'boolean', description: 'True if there are commits or uncommitted changes in scope since startCommit.' },
    commits: STRS,
  },
  required: ['results', 'allPassed', 'progressSinceStart', 'commits'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    criteria: {
      type: 'array',
      items: {
        type: 'object',
        properties: { criterion: STR, pass: { type: 'boolean' }, finding: STR },
        required: ['criterion', 'pass', 'finding'],
      },
    },
    verdict: { type: 'string', enum: ['PASS', 'FAIL'] },
  },
  required: ['criteria', 'verdict'],
}

const REPLAN_CHECK_SCHEMA = {
  type: 'object',
  properties: {
    accepted: { type: 'boolean', description: 'True only if the evidence holds AND it shows a defect in the plan, not a fixable bug.' },
    reason: STR,
  },
  required: ['accepted', 'reason'],
}

// ---------------------------------------------------------------- helpers
const decisions = []
function note(unit, sortie, decision, why) {
  decisions.push({ unit, sortie, decision, why: why || '' })
  log(`${unit} · ${sortie}: ${decision}${why ? ` (${why})` : ''}`)
}

// Simplified model rule (candidate replacement for the 5-dimension score).
function pickModel(s, attempt) {
  if (s.model) return s.model
  if (attempt >= 3) return 'opus' // 2+ prior failures
  if (s.foundation) return 'opus'
  if (s.type === 'command' || s.type === 'background' || s.type === 'deferred') return 'haiku'
  return 'sonnet'
}

const bullets = (xs) => (xs && xs.length ? xs.map((x) => `- ${x}`).join('\n') : '- (none)')
const machineCriteria = (s) => s.exitCriteria.filter((c) => c.kind === 'command' || c.kind === 'assertion')
const judgmentCriteria = (s) => s.exitCriteria.filter((c) => c.kind === 'judgment')
const humanCriteria = (s) => s.exitCriteria.filter((c) => c.kind === 'checklist')
const fmtCriterion = (c) => (c.kind === 'command' && c.command ? `${c.text}\n    command: ${c.command}` : c.text)

function implementerPrompt(u, s, mode) {
  const dir = u.directory ? `${ROOT}/${u.directory}` : ROOT
  const header = `You are a sortie agent executing ONE sortie of a mission. Project root: ${ROOT}. Work unit: ${u.name} (${dir}).
Reference plan (read only what you need): ${PLAN_PATH}

You are executing Sortie ${s.id}: ${s.name}  [type: ${s.type}]

${s.definition}

ENTRY CRITERIA (verify before starting):
${bullets(s.entryCriteria)}

EXIT CRITERIA (verify before declaring done):
${bullets(s.exitCriteria.filter((c) => c.kind !== 'judgment').map(fmtCriterion))}
${judgmentCriteria(s).length ? `\nREVIEW CRITERIA (an independent reviewer will judge these from your diff):\n${bullets(judgmentCriteria(s).map((c) => c.text))}\n` : ''}`

  let situation = ''
  if (mode.kind === 'continue') {
    situation = `\nCONTINUATION: A previous agent already made progress on this sortie. Before doing anything else, review its work:
  git -C ${ROOT} log --oneline ${mode.startCommit}..HEAD
  git -C ${ROOT} diff ${mode.startCommit}..HEAD
Complete ONLY this remaining work:
${bullets(mode.remaining)}
Report startCommit as ${mode.startCommit}.\n`
  } else if (mode.kind === 'retry') {
    situation = `\nRETRY: A previous attempt at this sortie failed. What went wrong:
${mode.failure}
Inspect the repository state first (git status, git log). Fix the issues, then complete the sortie.\n`
  }

  const rules = `
RULES:
- Before changing anything, run \`git -C ${ROOT} rev-parse HEAD\` and report it as startCommit${mode.kind === 'continue' ? ' (for a continuation, report the value given above)' : ''}.
- Commit your work with messages starting "[${u.name} sortie ${s.id}]".
- Do NOT start the next sortie. Do NOT modify ${PLAN_PATH}.
${s.type === 'background' ? '- This sortie is complete once the process is confirmed running. Do NOT wait for it to finish.\n' : ''}${s.type === 'deferred' ? '- Wait for the condition with ONE shell loop (up to 20 checks, sleep between checks). If it is still not met, report status "partial".\n' : ''}
IF THE PLAN ITSELF IS WRONG (a premise is false, a file/API it references does not exist, it conflicts with committed work from an earlier sortie, or its exit criteria contradict each other): stop, commit nothing further, and report status "replan" with defect, evidence (paths / command output), the smallest proposed change to the plan, and affected sorties. A bug in your own code or a hard problem is NOT a plan defect.

Report status "done" only after you have verified every exit criterion yourself.`

  return header + situation + rules
}

function checkerPrompt(u, s, startCommit) {
  return `You are an independent checker. Do NOT modify any files and do NOT commit.
Project root: ${ROOT}. Work unit directory: ${u.directory || '(project root)'}.
Sortie ${u.name}/${s.id} started at commit ${startCommit}.

1. Run \`git -C ${ROOT} log --oneline ${startCommit}..HEAD\` and \`git -C ${ROOT} status --porcelain\`. List the commits; set progressSinceStart if there are commits or uncommitted changes in scope.
2. Check each criterion below from the project root. For command criteria run the command and pass only on exit code 0 and any expected output. Record evidence (trimmed output).

${bullets(machineCriteria(s).map(fmtCriterion))}

allPassed is true only if every criterion passed.`
}

function verifierPrompt(u, s, startCommit) {
  return `You are an independent reviewer. Do NOT modify any files.
Read the change with:
  git -C ${ROOT} diff ${startCommit}..HEAD${u.directory ? ` -- ${u.directory}` : ''}
For each criterion decide PASS or FAIL from the diff alone. For every FAIL, cite file and line and state the concrete change that would make it pass. verdict is PASS only if every criterion passes.

CRITERIA:
${bullets(judgmentCriteria(s).map((c) => c.text))}`
}

function replanCheckPrompt(u, s, r) {
  return `A sortie agent claims the mission plan is defective. Check the claim. Do NOT modify any files.
Project root: ${ROOT}. Plan: ${PLAN_PATH}. Sortie: ${u.name}/${s.id} — ${s.name}.

Claimed defect: ${r.replan.defect}
Claimed evidence: ${r.replan.evidence}
Proposed plan change: ${r.replan.proposedChange}

Verify the evidence yourself (run the commands, open the paths). Accept only if the evidence holds AND it shows the plan cannot be executed as written. Reject if the evidence is missing or wrong, or if it shows an ordinary bug the agent could have fixed.`
}

// ---------------------------------------------------------------- sortie engine
async function runSortie(u, s) {
  const tag = `${u.name}·${s.id}`
  let attempt = 1
  let verifierRound = 0
  let continuations = 0
  let startCommit = null
  let mode = { kind: 'fresh' }
  const models = []

  const failOrRetry = (why) => {
    attempt++
    if (attempt > MAX_RETRIES) {
      note(u.name, s.id, 'FATAL', `max retries exhausted: ${why}`)
      return { done: true, result: { state: 'FATAL', attempts: attempt - 1, lastFailure: why, models, startCommit } }
    }
    note(u.name, s.id, 'BACKOFF', `attempt ${attempt}/${MAX_RETRIES} next: ${why}`)
    mode = { kind: 'retry', failure: why }
    return { done: false }
  }

  while (true) {
    const model = mode.kind === 'continue' && models.length && models[models.length - 1] !== 'haiku'
      ? models[models.length - 1]
      : (mode.kind === 'continue' ? 'sonnet' : pickModel(s, attempt))
    models.push(model)
    const label = `${tag} impl a${attempt}${mode.kind === 'continue' ? `c${continuations}` : ''} (${model})`
    const r = await agent(implementerPrompt(u, s, { ...mode, startCommit }), {
      label, phase: 'Execute', schema: IMPL_SCHEMA, model,
    })

    if (!r) {
      const step = failOrRetry('implementer agent died or was skipped')
      if (step.done) return step.result
      continue
    }
    if (!startCommit) startCommit = r.startCommit

    if (s.type === 'manual') {
      note(u.name, s.id, 'PARTIAL', 'manual sortie: awaiting user confirmation')
      return { state: 'PARTIAL', awaitingUser: true, report: r.summary, models, startCommit }
    }

    if (r.status === 'replan' && r.replan) {
      const chk = await agent(replanCheckPrompt(u, s, r), {
        label: `${tag} replan-check`, phase: 'Execute', schema: REPLAN_CHECK_SCHEMA, effort: 'low',
      })
      if (chk && chk.accepted) {
        note(u.name, s.id, 'REPLAN', r.replan.defect)
        return { state: 'REPLAN', replan: r.replan, replanCheck: chk.reason, attempts: attempt, models, startCommit }
      }
      const step = failOrRetry(`REPLAN rejected: ${chk ? chk.reason : 'replan checker died'}`)
      if (step.done) return step.result
      continue
    }

    const v = await agent(checkerPrompt(u, s, startCommit), {
      label: `${tag} check a${attempt}`, phase: 'Execute', schema: CHECK_SCHEMA, effort: 'low',
    })
    if (!v) {
      const step = failOrRetry('checker agent died')
      if (step.done) return step.result
      continue
    }
    const unmet = v.results.filter((x) => !x.passed).map((x) => `${x.criterion} — ${x.evidence}`)

    if (v.allPassed) {
      if (!judgmentCriteria(s).length) {
        note(u.name, s.id, 'COMPLETED', `${v.commits.length} commit(s)`)
        return { state: 'COMPLETED', attempts: attempt, models, startCommit, commits: v.commits, needsHuman: humanCriteria(s).map((c) => c.text) }
      }
      verifierRound++
      note(u.name, s.id, 'VERIFYING', `verifier round ${verifierRound}/${MAX_VERIFIER_ROUNDS}`)
      const jv = await agent(verifierPrompt(u, s, startCommit), {
        label: `${tag} verify r${verifierRound}`, phase: 'Execute', schema: VERDICT_SCHEMA, model: 'sonnet',
      })
      if (jv && jv.verdict === 'PASS') {
        note(u.name, s.id, 'COMPLETED', `verifier PASS, ${v.commits.length} commit(s)`)
        return { state: 'COMPLETED', attempts: attempt, verifierRounds: verifierRound, models, startCommit, commits: v.commits, needsHuman: humanCriteria(s).map((c) => c.text) }
      }
      const findings = jv ? jv.criteria.filter((c) => !c.pass).map((c) => `${c.criterion} — ${c.finding}`) : ['verifier returned no verdict']
      if (verifierRound < MAX_VERIFIER_ROUNDS) {
        continuations++
        note(u.name, s.id, 'PARTIAL', 'verifier FAIL; continuing with findings')
        mode = { kind: 'continue', remaining: findings }
        continue
      }
      const step = failOrRetry(`verifier FAIL after ${verifierRound} rounds: ${findings.join('; ')}`)
      if (step.done) return step.result
      continue
    }

    if (v.progressSinceStart && r.status !== 'failed' && continuations < MAX_CONTINUATIONS) {
      continuations++
      note(u.name, s.id, 'PARTIAL', `${unmet.length} criterion/criteria unmet`)
      mode = { kind: 'continue', remaining: unmet.length ? unmet : (r.remaining || []) }
      continue
    }

    const step = failOrRetry(unmet.length ? unmet.join('; ') : r.summary)
    if (step.done) return step.result
  }
}

// ---------------------------------------------------------------- plan
let plan = A.plan
if (!plan) {
  phase('Parse')
  plan = await agent(`Read the mission execution plan at ${PLAN_PATH} and convert it to the structured form.
- A work unit is each package/component/phase the plan defines; if it defines none, the whole plan is one work unit named after its title.
- dependsOn lists work-unit names that must complete first (from layer tables, dependency graphs, or "depends on" text).
- Sortie id: the sortie's number EXACTLY as written in its heading ("Sortie 2a: ..." -> "2a"). No prefixes, no renumbering. Resume keys on "<work unit>/<id>", so ids must be stable across re-parses of an amended plan.
- Copy each sortie's definition VERBATIM.
- Exit criteria: kind=command for anything with a runnable command (put the command in "command"); kind=judgment for items marked [judgment]; kind=checklist for anything needing a human's senses; otherwise kind=assertion.
Do not modify any files.`, { label: 'parse-plan', schema: PLAN_SCHEMA, effort: 'low' })
  if (!plan) throw new Error('plan parse failed')
}

const units = new Map(plan.workUnits.map((u) => [u.name, u]))
for (const u of plan.workUnits) {
  for (const d of u.dependsOn || []) if (!units.has(d)) throw new Error(`work unit "${u.name}" depends on unknown unit "${d}"`)
}
// cycle check (plain code — a cycle would deadlock the DAG below)
const visiting = new Set(), visited = new Set()
function dfs(n, path) {
  if (visiting.has(n)) throw new Error(`dependency cycle: ${[...path, n].join(' -> ')}`)
  if (visited.has(n)) return
  visiting.add(n)
  for (const d of units.get(n).dependsOn || []) dfs(d, [...path, n])
  visiting.delete(n); visited.add(n)
}
for (const n of units.keys()) dfs(n, [])

log(`Plan: ${units.size} work unit(s), ${plan.workUnits.reduce((a, u) => a + u.sorties.length, 0)} sortie(s)` +
  (ALREADY_DONE.size ? `, ${ALREADY_DONE.size} already completed (skipped)` : ''))

// ---------------------------------------------------------------- execute (dependency DAG)
phase('Execute')
const sortieResults = {}
const unitRuns = {}
function runUnit(name) {
  if (!unitRuns[name]) {
    unitRuns[name] = (async () => {
      const u = units.get(name)
      const deps = await Promise.all((u.dependsOn || []).map(runUnit))
      const unmet = deps.filter((d) => d.state !== 'COMPLETED').map((d) => d.name)
      if (unmet.length) {
        note(name, '-', 'NOT_STARTED', `waiting on ${unmet.join(', ')}`)
        return { name, state: 'NOT_STARTED', waitingOn: unmet }
      }
      for (const s of u.sorties) {
        const key = `${name}/${s.id}`
        if (ALREADY_DONE.has(key)) { sortieResults[key] = { state: 'COMPLETED', skipped: true }; continue }
        const res = await runSortie(u, s)
        sortieResults[key] = res
        if (res.state !== 'COMPLETED') return { name, state: 'BLOCKED', blockedOn: s.id, reason: res.state }
      }
      return { name, state: 'COMPLETED' }
    })()
  }
  return unitRuns[name]
}
const unitStates = await Promise.all([...units.keys()].map(runUnit))

return {
  plan, // pass back as args.plan on resume when the plan has not changed (skips the parse agent)
  workUnits: unitStates,
  sorties: sortieResults,
  decisions,
  completedSorties: Object.entries(sortieResults).filter(([, r]) => r.state === 'COMPLETED').map(([k]) => k),
  needsUser: Object.entries(sortieResults)
    .filter(([, r]) => r.state === 'REPLAN' || r.state === 'FATAL' || r.awaitingUser)
    .map(([k, r]) => ({ sortie: k, state: r.state, detail: r.replan || r.lastFailure || r.report })),
}
