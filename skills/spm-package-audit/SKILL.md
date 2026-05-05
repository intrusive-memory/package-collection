---
name: spm-package-audit
description: Audits and automatically fixes Swift Package Manager library packages. Removes Package.resolved from git tracking, ensures the sibling dependency pattern is in place via /toggle-sibling-libraries, and bumps every intrusive-memory/* dep to its latest published release. Explicitly invoked only — does not auto-trigger.
allowed-tools: Bash, Read, Edit, Skill
---

# SPM Package Audit

Run on a Swift Package Manager library on the **development** branch when you want to refresh package hygiene before continued work or before invoking `/ship-swift-library`. Two responsibilities:

1. **Package.resolved tracking** — libraries should not check this in. If it is tracked, remove it and add to `.gitignore`.
2. **intrusive-memory/* version currency** — bump every `intrusive-memory/*` dep currently in the sibling pattern to its latest published GitHub release.

The **state of the sibling pattern itself** (helper functions, `useLocalSiblings`, sibling vs. direct `.package(url:)` calls) is delegated to `/toggle-sibling-libraries`. This skill no longer rewrites that scaffolding directly — keeping a single source of truth for the toggle prevents the two skills from drifting.

## When to use

- Tidy up a development branch before `/ship-swift-library`.
- Pull in newly-released intrusive-memory deps without going through a full ship cycle.
- Restore `Package.swift` to the canonical sibling shape after manual edits.

**Do not use for**: Xcode app projects, non-Swift packages, or packages with no `intrusive-memory/*` dependencies.

## Procedure

Run these in order. Each is idempotent.

### 1. Confirm we're in an SPM library

```bash
test -f Package.swift || { echo "ABORT: not in an SPM package directory"; exit 1; }
```

If `Package.swift` declares only `.executable` products and no `.library`, this skill does not apply (executables ship Package.resolved on purpose). Surface that and ask the user before continuing.

### 2. Package.resolved audit

```bash
if [ -f Package.resolved ] && git ls-files --error-unmatch Package.resolved >/dev/null 2>&1; then
  git rm --cached Package.resolved
  grep -qxF 'Package.resolved' .gitignore 2>/dev/null \
    || printf '\nPackage.resolved\n' >> .gitignore
  echo "Removed Package.resolved from git tracking, added to .gitignore."
else
  echo "Package.resolved not tracked — nothing to do."
fi
```

The Package.resolved file is still useful locally (SPM keeps writing it); we just don't want it under version control for libraries because consumers should resolve their own pins.

### 3. Ensure Package.swift is in sibling mode

Hand off to the dedicated toggle skill — it owns the helper-function + scaffolding rewrite and is byte-stable / idempotent:

```
/toggle-sibling-libraries --to sibling
```

What this guarantees on return:
- `import Foundation` and `import PackageDescription` present in the canonical order.
- The `useLocalSiblings` constant and both `sibling(...)` helper functions present in their canonical form.
- Every `.package(url: "https://github.com/intrusive-memory/<repo>.git", .upToNextMajor(from: "X.Y.Z"))` rewritten to `sibling("<repo>", remote: "...", from: "X.Y.Z")`.
- Non-intrusive-memory deps untouched.

If `Package.swift` was already in sibling state, the toggle reports a no-op and returns success.

### 4. Bump intrusive-memory/* versions to latest

For each `sibling("<Repo>", remote: "https://github.com/intrusive-memory/<Repo>.git", from: "X.Y.Z")` call in `Package.swift`, look up the latest released tag and edit `from:` if it differs:

```bash
# Extract the repo names that are currently in sibling form
REPOS=$(grep -oE 'sibling\("[A-Za-z0-9_-]+",' Package.swift | sed -E 's/sibling\("([^"]+)",/\1/' | sort -u)

for repo in $REPOS; do
  latest=$(gh api "repos/intrusive-memory/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null | sed 's/^v//')
  if [ -z "$latest" ]; then
    # Fall back to most recent vX.Y.Z tag
    latest=$(gh api "repos/intrusive-memory/${repo}/tags" \
      --jq '[.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0]' 2>/dev/null | sed 's/^v//')
  fi
  if [ -z "$latest" ] || [ "$latest" = "null" ]; then
    echo "WARNING: no published release for intrusive-memory/${repo} — leaving version as-is"
    continue
  fi
  echo "intrusive-memory/${repo} -> ${latest}"
done
```

For each repo whose latest version differs from what `Package.swift` currently has, use the `Edit` tool to change just that `from:` line. Pattern (the `sibling(` block spans multiple lines):

```
sibling(
  "<Repo>",
  remote: "https://github.com/intrusive-memory/<Repo>.git",
  from: "<old>")
```

→ change `<old>` to `<latest>`. Don't rewrite the surrounding lines or whitespace; the toggle in step 3 already produced canonical formatting.

### 5. Verify and report

```bash
swift package resolve 2>&1 | tail -5
```

If resolve fails, surface the error. Otherwise emit a short summary:

```
## SPM Package Audit Complete

### Package.resolved
- Status: [removed | already clean | not present]

### Package.swift sibling pattern
- Status: [restored | already in sibling mode]

### Versions bumped
| Dependency  | Old    | New    |
|-------------|--------|--------|
| SwiftBruja  | 1.6.1  | 1.7.0  |
| SwiftAcervo | 0.11.0 | 0.11.1 |

(or "All intrusive-memory/* deps already at latest published versions.")
```

Do **not** commit on the user's behalf — the audit's output usually rolls into a larger commit (either a routine dev-branch tidy or as part of `/ship-swift-library` Step 3). The user controls when to commit.

## Error handling

- **No `intrusive-memory/*` deps**: skip steps 3 and 4, run only the Package.resolved audit, and note that nothing else applied.
- **`gh` not authenticated or offline**: report and skip step 4 (the version bump). Do NOT skip step 3 — the toggle's `--to sibling` direction does not need network access (it doesn't resolve versions, just preserves the existing `from:` values).
- **`gh api` returns no releases for a repo**: leave that dep at its current version and warn. The user may need to publish a release for that upstream first.

## Notes

- The sibling pattern lets local `../SwiftBruja`, `../SwiftAcervo`, etc. checkouts override the remote pin during development; CI always uses the pin because `useLocalSiblings` is `false` when `CI=true`.
- The toggle skill (`/toggle-sibling-libraries`) is the single source of truth for the helper-function shape — if the canonical form ever changes, update that skill rather than this one.
- Steps in this skill are deliberately **not** parallelized into subagents; the work is small and sequential dependencies (toggle must run before version bumps so the regex in step 4 finds the `sibling(` blocks) make subagent orchestration overkill.
