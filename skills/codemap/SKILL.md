---
name: codemap
description: "Generate or refresh a graphify knowledge-graph codemap of the current repo, gitignore the machine-specific/regenerable pieces, and commit only the portable map artifacts. Use whenever the user wants to build, update, refresh, regenerate, sync, or commit the codemap / graphify map / code graph for a project — phrases like 'update the codemap', 'refresh the graphify map', 'rebuild the code graph', 'commit the codemap', 'regenerate graphify-out', 'sync the codemap before I push', or any variation of keeping a checked-in graphify-out/ map current. Handles first-time generation and incremental updates, enforces the correct .gitignore split (absolute-path markers + cache + manifest.json stay out; graph.json/html/report stay in), untracks anything now-ignored, ensures AGENTS.md references the codemap, and makes one clean commit. Optionally pushes."
---

# /codemap

One command to keep a **checked-in, queryable codemap** current: regenerate the
graphify knowledge graph, enforce the gitignore split so machine-specific and
regenerable files never get committed, and commit only the portable map.

This wraps the `/graphify` skill (the graph engine) with the git hygiene needed to
safely version a `graphify-out/` directory in a shared repo.

## When to use

Invoke for any "keep the codemap current" request: `update the codemap`, `refresh
the graphify map`, `rebuild the code graph`, `commit the codemap`, `regenerate
graphify-out`, `sync the codemap`. Also run it after a significant code change when
the user wants the committed map to reflect reality.

To **query** an existing map (architecture questions), use `/graphify` instead —
that's the read path. `/codemap` is the write/commit path.

## Arguments

- `/codemap` — generate or incrementally update, then commit.
- `/codemap push` — also `git push` the current branch after committing.
- `/codemap full` — force a full rebuild (not incremental `--update`).

## Prerequisites

- `graphify` CLI installed and configured (it makes LLM calls; a full build of a
  ~70-file repo costs roughly ~270k input / ~120k output tokens — `--update` is far
  cheaper because it only re-extracts changed files).
- Run from the repo root (where you want `graphify-out/` to live).
- A git repository (`git rev-parse --git-dir` succeeds).

## The portable / scratch split (the whole point)

graphify writes both portable map data and machine-specific scratch into
`graphify-out/`. Only the portable data may be committed.

**COMMIT (portable — no absolute paths, reproducible meaning):**
- `graphify-out/graph.json` — the GraphRAG graph (node IDs, not paths)
- `graphify-out/graph.html` — interactive visualization
- `graphify-out/GRAPH_REPORT.md` — human-readable summary
- `graphify-out/cost.json` — build token stats
- `graphify-out/.graphify_labels.json` — community-id → label map
- any portable exports the user opted into: `graph.svg`, `graph.graphml`,
  `cypher.txt`, `wiki/`

**GITIGNORE (machine-specific OR regenerable — never commit):**
- `graphify-out/.graphify_python` — absolute path to THIS machine's interpreter
- `graphify-out/.graphify_root` — absolute path to THIS checkout
- `graphify-out/.graphify_detect.json` — scratch detection output
- `graphify-out/cache/` — regenerable semantic-embedding cache (large, churns)
- `graphify-out/manifest.json` — **keyed by absolute file paths** (`/Users/.../repo/...`);
  leaks the local path for every file and is regenerated each run. Excluded even
  though it looks like "map data."

> Why manifest.json is excluded: its top-level keys are absolute paths. Committing
> it bakes one contributor's home directory into the repo and produces a useless
> diff on every other machine. The queryable `graph.json` does not depend on it.

## Steps (do in order)

### Step 1 — Sanity: in a git repo, at its root

```bash
git rev-parse --show-toplevel
```

If this fails, stop and tell the user to run from inside a git repository. If the
toplevel differs from the current directory, `cd` to the toplevel so `graphify-out/`
lands at the repo root (do this inside one combined command to avoid a `cd`
permission prompt).

### Step 2 — Generate or update the graph

If `graphify-out/graph.json` already exists and the user did NOT pass `full`, do an
incremental update (cheap — only changed files re-extracted):

```bash
graphify . --update
```

Otherwise do a full build:

```bash
graphify .
```

Let graphify print its own progress. If `graphify` is missing, fall back to the
install logic documented in the `/graphify` skill (Step 1 there), then retry.

### Step 3 — Enforce the .gitignore block (idempotent)

Ensure the repo's root `.gitignore` contains the canonical block below. If a
`# graphify codemap` marker line is already present, leave it; otherwise append the
block verbatim. Do NOT duplicate it.

```gitignore
# graphify codemap: commit the portable graph artifacts, ignore machine-specific
# markers (absolute paths), the regenerable cache, and the absolute-path manifest.
graphify-out/.graphify_python
graphify-out/.graphify_root
graphify-out/.graphify_detect.json
graphify-out/cache/
graphify-out/manifest.json
```

### Step 4 — Untrack anything now-ignored

A previous run (or a careless `git add`) may have tracked files that now belong in
.gitignore. Remove them from the index without deleting them from disk:

```bash
git rm -r --cached --ignore-unmatch \
  graphify-out/.graphify_python \
  graphify-out/.graphify_root \
  graphify-out/.graphify_detect.json \
  graphify-out/cache \
  graphify-out/manifest.json
```

### Step 4.5 — Ensure AGENTS.md references the codemap

A checked-in codemap is useless if agents don't know to query it. Guarantee the
reference exists (don't merely suggest it):

```bash
test -f AGENTS.md && grep -q 'graphify-out' AGENTS.md && echo "HAS_REF" || echo "NEEDS_REF"
```

If `NEEDS_REF` and an `AGENTS.md` exists, add a short **"Queryable Codemap"** section
to it (prefer placing it just before the first "Deep Dives" / detailed-docs section,
else append). Use this template, filling the node/edge counts from
`graphify-out/GRAPH_REPORT.md`:

```markdown
## Queryable Codemap

A prebuilt [graphify](https://pypi.org/project/graphifyy/) knowledge graph of this
codebase lives in [`graphify-out/`](graphify-out/) (<N> nodes · <E> edges). **Prefer
querying it before grepping** for architecture or "what connects to what" questions:

` ` `bash
graphify query "How does X flow through the system?"
graphify path "TypeA" "TypeB"      # shortest path between two nodes
graphify explain "SomeType"        # plain-language node explanation
` ` `

Human-readable summary: [`graphify-out/GRAPH_REPORT.md`](graphify-out/GRAPH_REPORT.md).
Refresh after significant changes with `/codemap` (or `graphify . --update`).
```

(Collapse the escaped ``` ` ` ` ``` fences back to real triple backticks when you
write the file.) If the repo has no `AGENTS.md` at all, fall back to adding the same
section to `README.md`. Stage whichever file you touched so it lands in the codemap
commit. This step is idempotent — once the `graphify-out` reference is present, it
does nothing.

### Step 5 — Stage the portable map + gitignore

Because Step 3 made .gitignore exclude the scratch, a directory add stages only the
portable artifacts. Also stage the doc file if Step 4.5 added the codemap reference:

```bash
git add .gitignore graphify-out/ AGENTS.md README.md 2>/dev/null || git add .gitignore graphify-out/
```

Verify nothing machine-specific slipped in (must print the "OK" line):

```bash
# --diff-filter=ACM = added/copied/modified only; deletions of now-ignored files
# (e.g. untracking manifest.json) are EXPECTED and must not trip this.
git diff --cached --name-only --diff-filter=ACM | grep -E 'graphify-out/(\.graphify_(python|root|detect)|cache/|manifest\.json)' \
  && echo "ABORT: scratch staged — fix .gitignore" \
  || echo "OK: only portable map staged"
```

If it prints ABORT, stop and fix before committing. (A staged *deletion* of
`manifest.json` is correct — that's Step 4 untracking a prior leak.)

### Step 6 — Commit (skip cleanly if no changes)

If there is nothing staged, report "codemap already up to date" and stop — do NOT
create an empty commit:

```bash
git diff --cached --quiet && echo "NOCHANGE" || echo "CHANGED"
```

When CHANGED, read the node/edge counts from the `## Summary` line of
`graphify-out/GRAPH_REPORT.md` (e.g. `322 nodes · 524 edges · 14 communities`) and
commit with them in the subject:

```bash
git commit -F - <<'MSG'
chore(codemap): refresh graphify map (<N> nodes · <E> edges)

Regenerated graphify-out/ and committed the portable map artifacts
(graph.json, graph.html, GRAPH_REPORT.md, cost.json, labels). Machine-specific
markers, the semantic cache, and the absolute-path manifest.json stay ignored.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
MSG
```

### Step 7 — Push (only if asked)

If the user passed `push`, push the current branch. First refuse to push the default
branch directly — if `git branch --show-current` is `main` or `master`, tell the
user to branch first instead of pushing. Otherwise:

```bash
git push origin "$(git branch --show-current)"
```

If the user did not pass `push`, end by telling them the commit is local and how to
push.

## First-time setup in a repo (one-time, automatic)

The steps above are self-bootstrapping: Step 3 creates the .gitignore block and
Step 4 untracks any pre-existing leaks, so the first `/codemap` run in a repo both
introduces the map and fixes a previously over-committed `graphify-out/`. Mention in
your summary when you had to untrack files (it means the prior state leaked scratch).

## AGENTS.md reference

Ensuring the `graphify-out/` reference exists in AGENTS.md (or README.md) is handled
by **Step 4.5** above and committed alongside the map. It is idempotent — once the
reference is present, subsequent runs leave it untouched.
