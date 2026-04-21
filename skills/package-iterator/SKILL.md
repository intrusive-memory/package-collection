---
name: package-iterator
description: Fan out any skill across every library in a JSON package collection file (or a named subset) in dependency order — low-level libraries first, siblings at the same dep level run in parallel. Scope is limited to JSON collection files like `collection.json`; other formats are not supported. Use this skill whenever the user asks to apply a per-library operation to multiple packages in the collection, including phrasings like "ship all the libraries", "run ship-swift-library on everything", "iterate /foo across the collection", "batch <skill> over all packages", "update every library", "for each package in the collection", "fan out X to the libraries", or "do X on all the libraries". Also trigger when the user names a skill and multiple libraries in the same sentence, or references "the collection" / "all packages" as the target of a per-library action.
allowed-tools: Bash, Read, Agent, Skill
---

# package-iterator

Runs a nominated skill on each library in a **JSON package collection file**
(e.g. `collection.json`), in **dependency order** derived from the same
graph that [DEPENDENCIES.md](../../DEPENDENCIES.md) visualises. Libraries
at the same dependency level run in parallel.

## Scope: JSON collection files only

This skill operates on a JSON collection file with the schema used by
`collection.json` — a top-level `packages` array where each entry has a
`url` and an optional `dependencies` map keyed by `<org>/<repo>` strings.
Other package-manifest formats (YAML, TOML, Package.resolved, etc.) are
**not supported**. If the user points the iterator at a non-JSON file,
stop and ask them to convert or pick a different input.

The default collection path is `collection.json` resolved from the
current working directory or the git repo root.

## When to use this skill

- User asks to apply a per-library operation to multiple packages at once
  ("ship every library", "run X on all the packages", "iterate /foo across
  the collection").
- User names a skill and a set of libraries — even informally ("do the
  release thing on SwiftFijos, SwiftCompartido, and SwiftHablare").
- User wants the collection's batch operation to respect dependency order
  without having to manage it themselves.

Do **not** use this for:
- Running a skill on a single library (just invoke the skill directly).
- Operations that don't naturally apply per-library (e.g., editing
  `collection.json` itself — that's `update-package-library`).

## Core guarantees

1. **Dependency order is respected.** Libraries are layered from
   `collection.json`: layer 0 has no intra-org deps, layer N depends only on
   layers `< N`. Execution proceeds layer by layer.
2. **Within a layer, runs are parallel.** Siblings at the same level have
   no ordering constraints, so they run concurrently via subagents — one
   `Agent` tool call per library, all dispatched in the same turn.
3. **Between layers, runs are gated.** Layer N+1 begins only after every
   library in layer N has completed. This matters for version-bumping
   skills: a dependent needs its upstream's new release before its own run
   can produce a correct PR.
4. **Failures escalate, then flag-and-skip.** See [Failure handling](#failure-handling) below.

## Inputs

| Argument | Required | Default | Purpose |
|---|---|---|---|
| `skill` | yes | — | The skill to invoke on each library (e.g. `ship-swift-library`). |
| `packages` | no | *all* | Comma- or space-separated subset. Defaults to every package in `collection.json`. |
| `with-dependents` | no | `false` | If set, expand the subset to include everything downstream. Turn on for version-bumping skills (shipping, releasing); leave off for analysis skills (lint, audit). |
| `args` | no | — | Extra arguments passed verbatim to the target skill's invocation. |

If the user hasn't specified `with-dependents` and the target skill name
contains `ship`, `release`, `publish`, or `bump`, warn them that a subset
without dependent expansion may produce stale-pin PRs downstream, then ask
whether to enable it.

## How to run

### Step 1 — Compute the execution plan

```bash
python scripts/compute_layers.py \
  --collection ../../collection.json \
  [--packages SwiftFijos,SwiftCompartido] \
  [--with-dependents]
```

The script emits JSON:

```json
{
  "layers": [
    ["SwiftAcervo", "SwiftFFMpeg", "SwiftFijos", "SwiftOnce", "vox-format"],
    ["SwiftBruja", "SwiftCompartido", "SwiftTuberia", "mlx-audio-swift"],
    ["SwiftProyecto", "SwiftSecuencia"],
    ["SwiftHablare"],
    ["SwiftVoxAlta"],
    ["SwiftEchada"]
  ],
  "library_paths": {
    "SwiftAcervo": "/Users/stovak/Projects/SwiftAcervo",
    ...
  },
  "reverse_deps": {
    "SwiftFijos": ["SwiftCompartido", "SwiftHablare", "SwiftSecuencia"],
    ...
  }
}
```

Show the plan to the user. Confirm before executing if any of the following
apply:
- More than 5 libraries in the plan.
- Target skill is anything that ships, publishes, releases, or modifies
  remote state (opens PRs, pushes tags, creates releases).
- Any library path in `library_paths` does not exist on disk — stop and
  surface that to the user instead of guessing.

### Step 2 — Execute layer by layer

For each layer in the plan, in order:

1. For each library in the layer, build a subagent prompt from the
   [template below](#subagent-prompt-template) and spawn the subagent via
   the `Agent` tool with `subagent_type: "general-purpose"`.
2. Dispatch **all libraries in the layer in the same tool-use turn** so
   they run concurrently. Do not send them one at a time.
3. Wait for every subagent in the layer to return. Record each result as
   `PASS`, `FAIL`, or `SKIPPED` along with the one-paragraph summary the
   subagent returns.
4. Before starting the next layer, apply [failure handling](#failure-handling)
   to filter out any library whose upstream just failed.

### Step 3 — Final report

After the last layer (or after halting), print a summary table to the user:

```
Skill:        <skill-name>
Plan source:  collection.json revision <N>
Total layers: <N>
Total libs:   <N>  (passed: <X>, failed: <Y>, skipped: <Z>)

Layer 0  SwiftAcervo       PASS   Shipped 0.7.2 → 0.7.3
Layer 0  SwiftFijos        PASS   Shipped 1.4.1 → 1.4.2
Layer 1  SwiftCompartido   FAIL   CI red, diagnostic unable to resolve; follow-up required
Layer 1  SwiftBruja        PASS   Shipped 1.5.1 → 1.5.2
Layer 2  SwiftProyecto     SKIPPED Depends on SwiftCompartido (failed above)
...
```

For every `FAIL`, include:
- The library path.
- The last action the skill attempted.
- What the diagnostic agent tried.
- The verbatim error the diagnostic agent could not resolve.
- A concrete suggestion for the user's next step.

## Failure handling

When a subagent returns `FAIL` on a library, do not immediately accept the
failure. Execute this escalation sequence before marking the mission
failed:

### Diagnostic escalation

Spawn a **high-capability diagnostic agent** — `Agent` with
`subagent_type: "general-purpose"` and `model: "opus"` — with a prompt
structured like:

```
You are the diagnostic agent for a failed package-iterator mission.

Library:        <absolute-path>
Target skill:   <skill-name>
Skill args:     <args or "none">
Prior attempt:  <subagent summary>
Error details:  <verbatim error output>

Your job:
1. Diagnose the root cause. Read the error, look at recent commits, check
   CI status, look for broken configuration. Do not guess.
2. Attempt a fix that a competent engineer would make — version-bumping
   mistakes, missing entries in Package.swift, stale branch, failing
   lint, unresolved merge conflicts, etc. Prefer non-destructive fixes.
3. Re-run the target skill once the fix is in place.
4. Report PASS with a summary of what you fixed, or FAIL with:
   - What you tried and why it didn't work.
   - What the user should check themselves to move forward.
   - Whether the problem is local (this library) or systemic (affects
     other libraries too).

Do not attempt destructive recovery (force push, hard reset to remote,
deleting tags or releases). If a fix would require that, stop and report.
```

- If the diagnostic agent returns **PASS**, treat the mission as passed
  and continue normally. Note in the final report that the diagnostic
  agent recovered it, and include a one-line summary of the fix.
- If the diagnostic agent returns **FAIL**, mark the mission failed and
  apply downstream-skip:
  - Using `reverse_deps` from the execution plan, skip every direct and
    transitive dependent of the failed library in later layers.
  - Continue executing other libraries in the current and subsequent
    layers that don't depend on the failure.
- Do **not** retry the diagnostic agent on the same library within the
  same run.

### Flag failures for user follow-up

A failed mission is not a fatal error for the whole run — it is a flagged
item requiring user attention. The final report must make every failure
easy to act on: list the library, the original error, what the diagnostic
agent attempted, and the recommended user action.

If the whole run completed with zero failures, say so plainly.

## Subagent prompt template

Each per-library subagent receives a self-contained prompt. Use this
template and substitute the placeholders:

```
You are running the `<skill-name>` skill on one library as part of a
package-iterator run.

Library:       <absolute-path-to-library>
Target skill:  <skill-name>
Skill args:    <args-or-"none">

Steps:
1. cd to the library directory.
2. Verify the working tree is clean (git status --porcelain). If dirty,
   stop and report FAIL with the dirty paths — do not attempt to stash
   or discard.
3. Invoke the `<skill-name>` skill via the Skill tool. Pass the skill
   args listed above, if any.
4. When the skill completes:
   - If it succeeded, report PASS with a one-paragraph summary of what
     changed (version bumped, PR opened/merged, tag pushed, etc.).
   - If it failed, report FAIL with the verbatim error and the last
     action attempted. Do not attempt recovery — the caller will handle
     escalation.

Do not invoke destructive git operations (force push, hard reset,
branch -D) unless the target skill explicitly calls for them.
Do not touch other libraries — your scope is only this one path.
```

## Scope: libraries vs. apps

`collection.json` curates **libraries**. Produciesta and SwiftVinetas (the
apps shown at the bottom of [DEPENDENCIES.md](../../DEPENDENCIES.md)) are
not in the plan by default. If the user explicitly names them in
`packages`, locate them at `../Produciesta` and `../Vinetas` (note the
bare `Vinetas` sibling, not `SwiftVinetas` — verify which exists) and run
the skill as if they were libraries. Warn the user first that library-flow
skills like `ship-swift-library` are typically wrong for apps, which ship
via App Store Connect flows instead.

## Common pitfalls

- **Subagents that cannot invoke `Skill`.** If the environment denies
  subagents the `Skill` tool, the per-library runs will error
  immediately. When this happens, fall back to sequential execution
  from the main agent: same layer order, same failure handling, but no
  in-layer parallelism. Tell the user about the degradation.
- **Library directory missing.** If `../<pkg>` doesn't exist for a
  library in the plan, stop and report — do not silently skip. The user
  may need to clone it.
- **Dirty working tree.** Each subagent checks for a clean tree before
  invoking the target skill. This avoids mixing in-progress edits with
  automated version bumps.
- **Over-eager `--with-dependents`.** Expanding the subset is the right
  default for shipping but wrong for cheap read-only skills. Confirm with
  the user when the skill name doesn't make intent obvious.
- **Stale DEPENDENCIES.md.** The script reads `collection.json` directly;
  it does not consult `DEPENDENCIES.md`. If the collection has changed
  since the last graph refresh, the layers will be correct but the docs
  may be stale — suggest running `/update-package-library` and
  regenerating `DEPENDENCIES.md` after major runs.
