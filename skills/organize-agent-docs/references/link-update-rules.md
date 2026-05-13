# Link Update Rules

When the skill moves a file, any markdown link in a FOUNDATIONAL file that pointed at the old location must be rewritten. This document defines what counts as a link, how to find them, and how to rewrite them safely.

---

## Scope

Links are scanned **only in FOUNDATIONAL files at the repo root** (AGENTS.md, CLAUDE.md, GEMINI.md, CURSOR.md, COPILOT.md, CODEX.md, README.md, CHANGELOG.md, plus any added to `.organize-agent-docs.foundational`).

Why only foundational? Because:

- Foundational files are the canonical entry points; broken links there mislead every reader.
- EXTRANEOUS files inside `docs/` may also have links, but they're not authoritative — fix them on demand, not during every sweep.
- MISSION files are usually self-contained; rewriting links inside them would mean walking back into history.

If a future need arises to update links in `docs/` files, expose a `--rewrite-extraneous` flag rather than expanding the default scope.

---

## What Counts as a Link

The skill detects these patterns in foundational files:

1. **Inline markdown links:**
   ```markdown
   [text](relative/path.md)
   [text](path/to/file.md#section)
   ```

2. **Reference-style links:**
   ```markdown
   [text][ref-id]

   [ref-id]: relative/path.md
   ```

3. **Image links (relative paths only):**
   ```markdown
   ![alt](images/diagram.png)
   ```
   These rarely point to markdown but can point to assets that this skill might one day move. Currently the skill leaves image links alone unless the asset moved during the run.

4. **Bare relative paths in code blocks?** No. The skill does not parse code blocks. If the user has `cat docs/EXECUTION_PLAN.md` inside a fenced block, that text is not a link and is left alone.

5. **Absolute URLs (`http://`, `https://`)?** No. These are not relative; do not touch.

6. **Anchors only (`#section`)?** No. Same-file anchors don't move.

7. **HTML `<a href="...">`?** Yes, if the href is relative. Markdown files often embed HTML for tables and callouts.

---

## How to Discover Links

Use `grep` to find candidates, then verify each match by reading context. Don't blanket-rewrite based on regex alone — false positives matter.

```bash
# Inline links with relative paths
grep -nE '\]\([^)#][^)]*\.md(\#[^)]*)?\)' AGENTS.md

# Reference link definitions
grep -nE '^\[[^]]+\]:[[:space:]]+[^h][^t][^)]+$' AGENTS.md
```

The skill maintains a `$MOVES` dict from the current run: `{old_path: new_path}`. For each foundational file:

1. Read the file.
2. For each `(old_path, new_path)` in `$MOVES`, search for the old path as a link target.
3. Replace with the new path.
4. If the path appears multiple times, replace all instances.
5. If a path appears outside a link (e.g., as plain text or inside a code fence), leave it alone — only link targets get rewritten.

---

## Rewriting Rules

### Relative path normalization

All foundational files live at the repo root, so relative paths from foundational files are relative to the root. If `EXECUTION_PLAN.md` moves from `EXECUTION_PLAN.md` (root) to `docs/complete/foo-01/EXECUTION_PLAN.md`:

```markdown
- [Plan](EXECUTION_PLAN.md)          →  [Plan](docs/complete/foo-01/EXECUTION_PLAN.md)
- [Plan](./EXECUTION_PLAN.md)         →  [Plan](docs/complete/foo-01/EXECUTION_PLAN.md)
- [Plan](EXECUTION_PLAN.md#section)   →  [Plan](docs/complete/foo-01/EXECUTION_PLAN.md#section)
```

Preserve anchors (`#section`) and query strings. Only the path portion is rewritten.

### Avoid relative-path drama

This skill never moves a foundational file (foundational files stay at root by definition), so all rewrites are root-relative. Do not generate `../` paths; do not generate paths starting with `/`. Just write the new location as it appears from the repo root.

### Reference-style link definitions

If a reference definition's target moved, rewrite the definition. Do not touch in-text `[text][ref-id]` usages — only the definition line:

```markdown
Before:
  See [the plan][plan].
  ...
  [plan]: EXECUTION_PLAN.md

After:
  See [the plan][plan].
  ...
  [plan]: docs/complete/foo-01/EXECUTION_PLAN.md
```

---

## Broken Links

If a link points to a file that:

- Was deleted during this run (user picked Delete on an ambiguous file).
- Was already missing before this run (the user had a stale link).

Do **not** silently drop it. Insert an HTML comment immediately above the line containing the link:

```markdown
<!-- BROKEN LINK (organize-agent-docs 2026-05-12): missing target was `docs/old-design.md` -->
- [Old design notes](docs/old-design.md)
```

This:

1. Surfaces the problem to the user in the next `git diff`.
2. Makes the link visible in `grep "BROKEN LINK"` audits.
3. Lets the user decide whether to remove the line entirely or repair the link.

Report broken links in the Step 9 summary.

---

## What the Skill Does Not Do

- **Does not rewrite inbound links from outside the repo** (other repos, websites, etc.).
- **Does not validate link text** ("Read the plan" → still says "Read the plan" even if the file moved to a different role).
- **Does not move section anchors** if a target's headings change. The skill rewrites the path; the user verifies anchors still resolve.
- **Does not deduplicate links** that point to the same place.

---

## Tracking Edited Foundational Files

For the `updated:` stamp logic in `commands/organize.md` § Step 7, the skill keeps `$EDITED_FOUNDATIONAL` — the set of foundational files whose contents were actually modified during this run.

A foundational file is added to `$EDITED_FOUNDATIONAL` if:

- One or more links were rewritten in it.
- An HTML "BROKEN LINK" comment was inserted into it.

Reading the file, finding zero links to rewrite, and writing nothing does **not** count as editing. The `updated:` field stays as-is in that case.
