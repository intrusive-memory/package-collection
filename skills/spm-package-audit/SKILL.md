---
name: spm-package-audit
description: Audits and automatically fixes Swift Package Manager library packages. Removes Package.resolved from git tracking, ensures every intrusive-memory/* dep is a plain remote `.upToNextMajor(from:)` pin (the sibling pattern is retired), and raises each floor to its latest published release within the current major. Explicitly invoked only — does not auto-trigger.
allowed-tools: Bash, Read, Edit, Skill
---

# SPM Package Audit

Run on a Swift Package Manager library on the **development** branch when you want to refresh package hygiene before continued work or before invoking `/ship-swift-library`. Two responsibilities:

1. **Package.resolved tracking** — libraries should not check this in. If it is tracked, remove it and add to `.gitignore`.
2. **intrusive-memory/* version currency** — raise every `intrusive-memory/*` floor to its latest published GitHub release within the current major.

**The sibling pattern is retired (2026-11-04).** Every intrusive-memory/* dependency is a plain `.package(url:, .upToNextMajor(from:))` on every branch. If any `sibling(...)` scaffolding is found, strip it with `/toggle-sibling-libraries --to remote`. Never run `--to sibling`.

## When to use

- Tidy up a development branch before `/ship-swift-library`.
- Pull in newly-released intrusive-memory deps without going through a full ship cycle.
- Strip leftover `sibling(...)` scaffolding, `branch:` pins, or `.package(path:)` refs to intrusive-memory/* deps.

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

### 3. Ensure Package.swift is remote-only

```bash
grep -qE 'func sibling\(|useLocalSiblings' Package.swift && echo "sibling scaffolding present"
```

If present, strip it, keeping the existing floors (step 4 raises them):

```
/toggle-sibling-libraries --to remote --no-resolve
```

Then convert any remaining intrusive-memory/* `branch:`, `exact:`, `revision:`, `.upToNextMinor` or
`.package(path:)` declarations to `.upToNextMajor(from: "<latest release>")`. A `branch:` pin may be
carrying unreleased upstream code; warn loudly when converting one. Note that SwiftPM refuses to resolve
a version-pinned package whose own `Package.swift` uses a `branch:` dependency ("depends on an
unstable-version package"), so a library shipped with branch pins is unusable downstream.

### 4. Raise intrusive-memory/* floors (within the current major)

```bash
grep -oE 'intrusive-memory/[A-Za-z0-9_.-]+' Package.swift | sed 's|intrusive-memory/||; s|\.git$||' | sort -u |
while read -r repo; do
  latest=$(gh api "repos/intrusive-memory/${repo}/releases/latest" --jq '.tag_name' 2>/dev/null | sed 's/^v//')
  [ -z "$latest" ] && latest=$(gh api "repos/intrusive-memory/${repo}/tags" \
      --jq '[.[].name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))][0]' 2>/dev/null | sed 's/^v//')
  echo "intrusive-memory/${repo} -> ${latest:-NO RELEASE}"
done
```

For each dep whose latest release is newer than its `from:` value **and has the same major**, edit just
that `from:` value. When the latest release is a **new major** (e.g. `6.3.0` → `7.0.0`), do not bump:
that is porting work. List it in the report under "Cross-major updates available".

Floors are not cosmetic: `make resolve` here can pass while a consumer with an older lock fails, when
this package uses an API newer than its stated floor. If a build needs a newer transitive version
(third-party included), raise that floor too.

### 5. Verify and report

```bash
make resolve 2>&1 | tail -5   # never `swift package resolve`
```

If resolve fails, surface the error. Otherwise emit a short summary:

```
## SPM Package Audit Complete

### Package.resolved
- Status: [removed | already clean | not present]

### Package.swift remote-only
- Status: [sibling scaffolding stripped | already remote-only]

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
- **`gh` not authenticated or offline**: report and skip step 4. Step 3 still runs (`--no-resolve` needs no network).
- **`gh api` returns no releases for a repo**: leave that dep at its current version and warn. The user may need to publish a release for that upstream first.

## Notes

- The sibling pattern was retired 2026-11-04 because it made this machine and CI build different source and hid floor bugs. Cross-library work goes through tagged releases.
