---
type: docs
---

# Recon Command — recon

> **Terminology reminder**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission.

`recon` runs **before** `breakdown`. It extracts every claim the requirements make about code that *already exists*, verifies each one against the revision the build actually resolves — in this repo and in its dependencies' local checkouts — and writes `RECON_REPORT.md`. A false premise stops the pipeline here.

**Referenced by**: `skill.md` § Argument Parsing → `recon`. Gates `commands/breakdown.md` § 0.

---

## Why

A requirements author believes things about the codebase. Some are wrong: the API was renamed, the helper lives in a sibling package that hasn't shipped it, the target was deleted. Without recon that belief becomes a sortie's entry criteria and a sortie agent discovers it three dispatches deep — `REPLAN`, work unit `BLOCKED`, replan and re-refine. Recon is `REPLAN`'s cheap early counterpart.

The signature catch is **dependency drift**: an API that exists in your local checkout of a sibling library but not in the version this project resolves. Compiles here, fails in CI. Recon's whole discipline is separating *this exists* from *this exists in the version the build uses*.

---

## Signature

```
/mission-supervisor recon [path/to/requirements.md] [--search-root=DIR] [--max-agents=N] [--depth=N] [--accept-risk]
```

| Argument | Default | Meaning |
|----------|---------|---------|
| `path/to/requirements.md` | per skill.md § Locate Requirements Document | The document under audit |
| `--search-root=DIR` | `~/Projects` | Root of the local checkout search (Stage 2) |
| `--max-agents=N` | `4` | Parallel verification spokes. Never exceed 4 (skill-wide rule) |
| `--depth=N` | `4` | `find` maxdepth for the checkout index. Raise only if deps come back unresolved |
| `--accept-risk` | off | Convert blocking findings into Open Questions instead of stopping (Stage 5) |

`$PROJECT_ROOT` is the directory containing the requirements document, as in `breakdown`.

Recon is hub-and-spoke: the hub (you) reads, resolves, and adjudicates; read-only spokes verify and return cited findings. Spokes never talk to each other and never write.

---

## Stage 1 — Extract Assumptions

An **assumption** is any statement that presupposes something already exists or already behaves a certain way.

> A requirement to *build* something is not an assumption. "Add a `--dry-run` flag to `echada cast`" assumes `echada cast` exists; the flag is the work. Extract the presupposition, not the deliverable.

| Kind | Claim shape |
|------|-------------|
| `A-API` | A type, function, protocol, or CLI subcommand/flag exists with a given signature |
| `A-FILE` | A file, directory, target, scheme, or product exists at a path |
| `A-DEP` | A dependency is available and provides capability X |
| `A-BEHAVIOR` | Existing code behaves a specific way (returns X, throws on Y) |
| `A-CONFIG` | A build setting, Makefile target, env var, or CI workflow exists |
| `A-DATA` | A schema, fixture, file format, or on-disk layout exists |
| `A-INVARIANT` | A stated constraint about the codebase ("nothing else calls this") |

Record each one:

```
ID:       A-07
Kind:     A-API
Claim:    "SwiftProyecto exposes `Project.loadManifest(at:)` returning a `Manifest`"
Source:   REQUIREMENTS.md § Cast Pipeline, lines 88–91
Locus:    dep:intrusive-memory/SwiftProyecto
Check:    grep `func loadManifest` in Sources/; confirm return type and throwing-ness
Blocking: yes
```

**Locus** routes the assumption to a spoke, so assign it carefully:

- `repo` — verifiable inside `$PROJECT_ROOT`. `A-INVARIANT` claims are repo-wide greps, so they are `repo` even when the symbol lives in a dependency — the claim is about callers here.
- `dep:<owner>/<repo>` — verifiable only inside a dependency's source
- `toolchain` — language/Xcode version, CI runner image, installed CLI
- `external` — an off-disk service or published API. Almost always `UNVERIFIABLE`; say so rather than guessing.

Greenfield document with zero assumptions: say so and skip to Stage 4 with an empty table. Stage 2 still runs — the dependency map serves `breakdown` regardless.

---

## Stage 2 — Map Local Dependencies

For every declared dependency: find the authoritative local checkout, and determine whether it is the code the build will actually resolve.

### 2a. Manifests

| Ecosystem | Declaration (intent) | Resolution (truth) |
|-----------|----------------------|--------------------|
| Swift PM | `Package.swift` | `Package.resolved` (also under `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`) |
| Xcode | `project.pbxproj` → `XCRemoteSwiftPackageReference` | the workspace `Package.resolved` |
| Python | `pyproject.toml`, `requirements.txt` | `uv.lock`, `poetry.lock`, installed dist-info |
| Node | `package.json` | `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` |
| Rust | `Cargo.toml` | `Cargo.lock` |
| Go | `go.mod` | `go.sum` |

**The declaration is intent; the lock file is truth.** When they disagree, report both. A range with no lock entry means the resolved version is whatever the network hands you at build time — itself a finding.

Watch for the **sibling pattern** (see the `toggle-sibling-libraries` skill): a `sibling("Name", remote:…, from:…)` helper resolves to `../Name` when that directory exists, falling back to the remote pin otherwise. A package in sibling state already resolves to a local path — record it as the resolution and flag it, because CI and this machine are building different source.

### 2b. Identity

Normalize each git dependency's URL: `git@github.com:owner/Repo.git` and `https://github.com/owner/Repo.git` both become `github.com/owner/repo` (strip scheme and trailing `.git`, lowercase).

Match on the **normalized remote, never the directory name**. Names drift and get copied — `worktrees/SwiftEchada-cast-md`, `old/Produciesta`, `pre-trash/…` are all real and all misleading.

### 2c. Index the authoritative checkouts

```bash
SEARCH_ROOT="${SEARCH_ROOT:-$HOME/Projects}"
DEPTH="${DEPTH:-4}"

find "$SEARCH_ROOT" -maxdepth "$DEPTH" -name .git \
     -not -path '*/.build/*'        -not -path '*/DerivedData/*' \
     -not -path '*/SourcePackages/*' -not -path '*/node_modules/*' \
     -not -path '*/.swiftpm/*'      -not -path '*/site-packages/*' \
     -not -path '*/.venv/*' -print 2>/dev/null |
while read -r g; do
  d=$(dirname "$g")
  url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$url" "$d" \
    "$(git -C "$d" rev-parse HEAD 2>/dev/null)" \
    "$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
    "$(git -C "$d" status --porcelain 2>/dev/null | head -1 | sed 's/.*/dirty/')" \
    "$(git -C "$d" describe --tags --abbrev=0 2>/dev/null || echo none)"
done | sort -u
```

Write the index to the scratchpad, never the repo. `DEPTH=4` reaches `~/Projects/<group>/<pkg>/.git`. If a dependency comes back unresolved, retry that one at greater depth before declaring `NO_LOCAL_CHECKOUT`.

Excluded paths are **derived copies, not checkouts**. Also treat `old/`, `pre-trash/`, `*-old`, and `worktrees/` as non-authoritative: a worktree is a real checkout but is on a different branch by construction, so it surfaces as `AMBIGUOUS` rather than being chosen.

### 2d. Index the resolved copies

`.build/checkouts/<Dep>` is literally the source the last build used — the best verification target for "does this exist in the resolved version". Index it separately:

```bash
find "$PROJECT_ROOT" -maxdepth 6 -type d -name checkouts 2>/dev/null |
while read -r c; do
  for d in "$c"/*/; do
    d="${d%/}"; [ -d "$d" ] || continue
    rev=$(git -C "$d" rev-parse HEAD 2>/dev/null) || continue
    printf '%s\t%s\t%s\n' "$(basename "$d")" "$d" "$rev"
  done
done | sort -u
```

**Gotcha — a resolved copy's `origin` is not its upstream.** SwiftPM rewrites it to point at its own bare mirror:

```
$ git -C .build/checkouts/glosa-av remote get-url origin
/Users/…/pkg/SwiftEchada/.build/repositories/glosa-av-9d7a8c8e
```

So § 2b's URL matching applies to authoritative checkouts only. Join a resolved copy to its identity by **directory name plus revision**, cross-checked against the lock file:

```bash
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for p in d.get("pins") or d.get("object", {}).get("pins", []):
    st = p.get("state", {})
    print(p.get("identity"), p.get("location") or p.get("repositoryURL"),
          st.get("version") or st.get("branch"), (st.get("revision") or "")[:12], sep="\t")
' "$PROJECT_ROOT/Package.resolved"
```

A resolved copy is a valid target only when its `HEAD` equals the pinned revision. Otherwise `.build` is stale: read the authoritative checkout at the pinned revision (`git -C <local> show <sha>:<path>`) or mark the assumption `UNVERIFIABLE`.

### 2e. Classify

| Status | Meaning | Where to verify |
|--------|---------|-----------------|
| `LOCAL_MATCHES_PIN` | Checkout HEAD == resolved revision | The local checkout. Verdicts are trustworthy |
| `LOCAL_AHEAD` | Resolved revision is an ancestor of local HEAD | **The resolved copy.** Anything found only locally is `CONFIRMED_LOCAL_ONLY` |
| `LOCAL_BEHIND` | Local HEAD is an ancestor of the resolved revision | The resolved copy. Local is simply stale |
| `LOCAL_DIVERGED` | Neither is an ancestor of the other | The resolved copy; report both revisions |
| `LOCAL_DIRTY` | Uncommitted changes in the checkout | Anything resting on it is unreproducible → `CONFIRMED_LOCAL_ONLY` |
| `SIBLING_ACTIVE` | The build resolves this dep to a local path | This machine and CI build different source. Always report |
| `AMBIGUOUS` | Several non-derived checkouts share the remote | **Do not choose.** List every path and ask |
| `NO_LOCAL_CHECKOUT` | Only a resolved copy, or nothing | The resolved copy if present, else `UNVERIFIABLE` |
| `UNPINNED` | Declared as a range with no lock entry | Resolved version unknowable offline. Report as a finding |

Decide ancestry mechanically, never by comparing dates:

```bash
git -C "$LOCAL" merge-base --is-ancestor "$RESOLVED_SHA" HEAD && echo LOCAL_AHEAD
git -C "$LOCAL" merge-base --is-ancestor HEAD "$RESOLVED_SHA" && echo LOCAL_BEHIND
```

If `$RESOLVED_SHA` isn't in the local object store, `git -C "$LOCAL" fetch origin "$RESOLVED_SHA"`; failing that, record `LOCAL_DIVERGED` and note that ancestry couldn't be established offline.

Finish by naming, for each dependency, one **verification target path** and the **revision it represents**:

> **Verify against the source the build resolves. Use the local checkout only when it is identical to that source.**

---

## Stage 3 — Dispatch Verification Spokes

Group assumptions by locus; one spoke per locus, up to `--max-agents` (4) concurrent. More loci than agents means batching, never more than 4 at once.

**Spoke rules**: read-only (no edits, builds, installs, or network); one locus at one revision; lean context (its assumption records, its target path, its target revision — not the requirements document, not other loci). Model: `haiku` when the locus is all `A-FILE`/`A-API`/`A-CONFIG` (grep work), `sonnet` when it contains `A-BEHAVIOR` or `A-INVARIANT` (reading logic, reasoning about callers).

```
You are a recon spoke. Verify claims against source. You are READ-ONLY:
make no edits, run no builds, install nothing, touch no network.

Target path:     <verification target path>
Target revision: <sha> (<tag-or-branch>) — the revision the build resolves
Locus:           <repo | dep:owner/name | toolchain>

Verify each claim independently. For each, return exactly:

  <ID> | <CONFIRMED|REFUTED|STALE|UNVERIFIABLE>
  evidence: <file>:<line>  OR  <command run> + a ≤3-line output excerpt
  actual:   <what is actually there, when it differs from the claim>

Rules:
- Every verdict REQUIRES a citation. No citation means UNVERIFIABLE, not CONFIRMED.
- CONFIRMED: found it, and its shape matches the claim exactly.
- STALE: it exists but its name, signature, or location changed. Give the current
  form in `actual:`.
- REFUTED: you searched where it would be and it is not there. Say where you looked.
- UNVERIFIABLE: undeterminable from this tree. Say what you'd need.
- Do not speculate about whether the claim *should* be true. Report what is.

Claims:
<the A-NN records for this locus>
```

**Hub adjudication** when spokes return:

1. **Strip uncited verdicts.** A `CONFIRMED` without a `file:line` or command+output becomes `UNVERIFIABLE`. Non-negotiable — an uncited confirmation is the exact failure recon exists to prevent.
2. **Apply the drift overlay.** If the dependency is `LOCAL_AHEAD`, `LOCAL_DIRTY`, `LOCAL_DIVERGED`, or `SIBLING_ACTIVE` and the spoke verified against the local checkout rather than the resolved copy, downgrade `CONFIRMED` → `CONFIRMED_LOCAL_ONLY`.
3. **Never overrule a spoke from the hub's own impression.** If a verdict looks wrong, dispatch a second spoke with a sharper claim.

| Verdict | Meaning | Gate |
|---------|---------|------|
| `CONFIRMED` | Verified against the resolved source, with a citation | pass |
| `CONFIRMED_LOCAL_ONLY` | True locally, **not** in the version the build resolves | **blocks** |
| `STALE` | Exists but changed shape; `actual:` gives the current form | **blocks** |
| `REFUTED` | Searched and not found | **blocks** |
| `UNVERIFIABLE` | Undeterminable offline | warns |

---

## Stage 4 — Write RECON_REPORT.md

Write `$PROJECT_ROOT/RECON_REPORT.md`. It is a mission artifact: OKF `type: recon-report`, archived by `clean` → `/organize-agent-docs` like the rest.

````markdown
---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: <sha256 of the requirements file>
project_head: <git rev-parse HEAD of $PROJECT_ROOT>
search_root: ~/Projects
generated: <YYYY-MM-DD>
verdict: CLEAR | BLOCKED
---

# RECON_REPORT.md — <Project Name>

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**<CLEAR | BLOCKED>** — <N> assumptions checked, <N> confirmed, <N> blocking.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `Project.loadManifest(at:)` exists | dep:intrusive-memory/SwiftProyecto | CONFIRMED | `Sources/SwiftProyecto/Project.swift:142` |
| A-07 | A-API | `VoiceRegistry.resolveAll()` exists | dep:intrusive-memory/SwiftReparto | CONFIRMED_LOCAL_ONLY | local `Sources/…:88`; absent at pinned v0.1.0 |

### Blocking findings

#### A-07 — CONFIRMED_LOCAL_ONLY
**Claim**: <verbatim>
**Source**: REQUIREMENTS.md § <heading>, lines <N>–<M>
**Found**: `~/Projects/package-collection/pkg/SwiftReparto/Sources/…:88` at HEAD (`abc1234`, 3 commits ahead of `v0.1.0`)
**Resolved version**: `v0.1.0` (`Package.resolved`) — symbol absent
**Impact**: Sorties resting on this compile here and fail in CI.
**Options**:
1. Publish SwiftReparto and bump the pin, then re-run recon *(recommended)*
2. Amend the requirements to use the API that exists at `v0.1.0`
3. Add the upstream change to mission scope as its own work unit

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| intrusive-memory/SwiftProyecto | `from: 4.8.1` | `4.8.1` (`d4e5f6…`) | `~/Projects/package-collection/pkg/SwiftProyecto` | `d4e5f6…` | LOCAL_MATCHES_PIN |
| intrusive-memory/SwiftReparto | `from: 0.1.0` | `0.1.0` (`9a8b7c…`) | `~/Projects/package-collection/pkg/SwiftReparto` | `abc1234` | LOCAL_AHEAD |
| apple/swift-argument-parser | `from: 1.7.1` | `1.7.1` | — | — | NO_LOCAL_CHECKOUT |

### Drift and ambiguity notes

- **SwiftReparto is 3 commits ahead of its pin.** Local builds see code CI does not.
- **SwiftEchada is AMBIGUOUS**: two non-derived checkouts share this remote —
  `~/Projects/package-collection/pkg/SwiftEchada` (`development`) and
  `~/Projects/worktrees/SwiftEchada-cast-md` (`mission/cast-md-extraction/01`).
  Recon did not choose. Name the authoritative one.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-12 | "the CDN returns 404 for missing models" | external service, offline pass | one `curl` against the CDN |

## Handoff to breakdown

- `CONFIRMED` facts are safe as sortie entry criteria without re-checking.
- `UNVERIFIABLE` items become an `## Open Questions` entry or an explicit verification
  step in the first dependent sortie's entry criteria — never a silent assumption.
- The dependency map's local paths carry into EXECUTION_PLAN.md so sortie agents
  don't rediscover them.
````

---

## Stage 5 — The Gate

**`verdict: BLOCKED`** (any `REFUTED`, `STALE`, or `CONFIRMED_LOCAL_ONLY`): STOP. Do not run `breakdown`.

```
**RECON BLOCKED**: <N> assumptions in the requirements do not hold against the code.

<blocking findings, each with its numbered options>

Breakdown would plan sorties on top of these. Resolve them, then re-run:
  /mission-supervisor recon

Or re-run with `--accept-risk` to carry each blocking finding into the plan as a
blocking Open Question instead.
```

`--accept-risk` doesn't suppress findings — it converts each into an `OQ-<N>` record that `breakdown` copies into `## Open Questions`, where `refine-blockers` hard-stops on it anyway. The user chooses *where* to answer, not *whether*.

**`verdict: CLEAR`**:

```
## Recon Complete — CLEAR

Source: <requirements path>
Output: $PROJECT_ROOT/RECON_REPORT.md

| Metric | Count |
|--------|-------|
| Assumptions extracted | <N> |
| Confirmed | <N> |
| Stale / refuted | 0 |
| Unverifiable | <N> |
| Dependencies mapped | <N> |
| Local checkouts resolved | <N> |
| Drifted from pin | <N> |

Ground truth established. Next step: /mission-supervisor breakdown
```

---

## Freshness

The report is **fresh** for a `breakdown` run when all of:

1. `requirements_sha256` matches the requirements document's current hash
2. `project_head` matches the current `git rev-parse HEAD`, **or** the diff between them touches no manifest or lock file
3. Every dependency's resolved revision in the map still matches the lock file

Otherwise it is stale and `breakdown` re-runs recon. Condition 2 is deliberately loose: ordinary commits don't invalidate recon, but anything that moves the dependency graph does.

---

## What Recon Must NOT Do

- **Write any file but `RECON_REPORT.md`.** Recon does not fix what it finds — no pin bumps, no requirements edits, no `Package.swift` changes.
- **Run builds, tests, installers, or package resolution.** Reading `Package.resolved` is fine; `swift package resolve` mutates it and the finding disappears.
- **Reach the network.** An offline `UNVERIFIABLE` beats an online `CONFIRMED` against a version the build won't pick.
- **Confirm anything without a citation** (Stage 3 adjudication).
- **Pick between ambiguous checkouts.** Report every candidate and ask.
- **Verify against a local checkout that differs from the resolved revision** — the exact bug this pass exists to catch.
- **Generate sorties, work units, or priorities.** That is `breakdown`. Recon establishes ground truth and stops.
- **Search outside `--search-root`** without saying so.
