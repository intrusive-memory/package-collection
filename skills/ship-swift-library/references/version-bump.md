# Step 3: Bump Version, Update Dependencies, Audit Documentation, and Audit CI Workflows

This is the heaviest step in the ship flow. Four coupled sub-tasks (SPM audit, version edit + lint + docs, CI-action audit) all land in a **single commit on `development`** that ships as part of the PR merge.

Make sure you're on the `development` branch first:

```bash
git checkout development
git pull origin development
```

## 1. Run SPM Package Audit First

Before any manual changes, run the spm-package-audit skill to automatically fix common package hygiene issues:

```
/spm-package-audit
```

This will:
- Remove Package.resolved from git tracking (libraries should not check this in)
- Add/update the sibling dependency pattern for intrusive-memory/* dependencies
- Update intrusive-memory/* dependency versions to latest GitHub releases
- Validate the sibling helper function is correct

## 2. Edit the Version File and Strip Any `-dev` Suffix

Edit `Sources/<LibraryName>/<LibraryName>.swift` (or wherever the canonical version constant lives).

**Strip any `-dev` suffix.** If the source file currently reads `1.4.2-dev` (the post-release marker from the previous cycle), the new shipping version must be a clean semver string like `1.4.3` or `1.5.0` — never `1.4.3-dev`. Search the whole repo for the `-dev` marker and replace every occurrence with the new clean version, then re-grep to confirm nothing is left:

```bash
# Locate every file holding the old -dev version (escape the dot)
grep -rln --exclude-dir=.git --exclude-dir=.build "X\.Y\.Z-dev" .

# After editing all of them to the new clean version, verify nothing remains
grep -rln --exclude-dir=.git --exclude-dir=.build -- "-dev" . || echo "No -dev markers left."
```

Common locations: `Sources/<LibraryName>/<LibraryName>.swift`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`. Do NOT touch dependency version constraints in `Package.swift` — those are unrelated.

## 3. Verify All Dependencies in Package.swift

After running spm-package-audit, verify no issues remain:

1. **Verify no local file path references remain** — spm-package-audit should have caught these, but double-check:
   ```bash
   grep -n '\.path(' Package.swift
   ```
   If any `.path()` references exist for non-intrusive-memory dependencies, replace with GitHub URLs.

2. **For non-intrusive-memory dependencies**, verify they use `.upToNextMajor()`:
   ```bash
   grep -A2 'package(url:' Package.swift | grep -v intrusive-memory
   ```
   Update any that use exact versions to `.upToNextMajor(from: "X.Y.Z")`.

## 4. Run `make lint` to Format Swift Sources

```bash
make lint
```

This runs `swift format -i -r .` across the entire project. Any formatting changes will be included in the commit.

## 5. Organize and Update Project Documentation

Use the organize-agent-docs skill:

```
/organize-agent-docs
```

This will:
- Ensure AGENTS.md contains universal project documentation (architecture, APIs, dependencies)
- Ensure CLAUDE.md contains only Claude-specific instructions (tool preferences, build requirements)
- Ensure GEMINI.md contains only Gemini-specific instructions
- Update version numbers across all documentation
- Verify documentation structure follows best practices
- Check that agent-specific files properly reference AGENTS.md

**After running organize-agent-docs**, also update README.md:
- Update version numbers in installation examples
- Verify all code examples work with current API
- Add new features to feature list
- Update platform requirements (iOS/macOS/Swift/Xcode versions)
- Verify all doc links point to existing files

## 6. Audit CI Workflows for Outdated GitHub Actions

Older action versions still pinned to Node 16 emit `Node.js 16 actions are deprecated` warnings on every CI run, and Node 16 runners have been removed entirely from some GitHub-hosted images. Audit every workflow file in `.github/workflows/` and bump each `uses:` reference to the latest published major version.

### 6.1. List every action reference across all workflows

Covers `.yml` and `.yaml`, ignores commented-out lines:

```bash
grep -hE '^[[:space:]]*uses:[[:space:]]*[^#]' .github/workflows/*.y*ml 2>/dev/null \
  | sed -E 's/^[[:space:]]*uses:[[:space:]]*//' \
  | sort -u
```

### 6.2. Build the floor-version table dynamically — do NOT hard-code versions

Hard-coded floor versions go stale the moment GitHub publishes a new major. Instead, build a per-release audit table by querying `releases/latest` for every action this repo actually uses. The output of step 6.1 is the input here.

**Output target (illustrative shape only — values must come from live API calls):**

| Action | Currently pinned | Latest major | Latest tag | Action required |
|---|---|---|---|---|
| `<owner>/<repo>` | `<extracted from workflow>` | `<derived from gh api>` | `<derived from gh api>` | bump / OK |

**How to populate it**, one row per unique `<owner>/<repo>` discovered in step 6.1:

```bash
# Extract just the owner/repo (strip @ref) and dedupe
ACTIONS=$(grep -hE '^[[:space:]]*uses:[[:space:]]*[^#]' .github/workflows/*.y*ml 2>/dev/null \
  | sed -E 's/^[[:space:]]*uses:[[:space:]]*//; s/@.*$//' \
  | grep -v '^\./' \
  | sort -u)

# For each, fetch the latest release tag and derive the major
for action in $ACTIONS; do
  latest_tag=$(gh api "repos/${action}/releases/latest" --jq '.tag_name' 2>/dev/null)
  if [ -z "$latest_tag" ]; then
    # Fallback: some actions only publish tags (e.g. `v3`), no GitHub Releases.
    latest_tag=$(gh api "repos/${action}/tags" --jq '[.[].name | select(test("^v[0-9]+(\\.[0-9]+){0,2}$"))][0]' 2>/dev/null)
  fi
  latest_major=$(printf '%s\n' "$latest_tag" | sed -E 's/^(v?[0-9]+).*/\1/')
  printf '%-40s  latest_major=%s  latest_tag=%s\n' "$action" "$latest_major" "$latest_tag"
done
```

**Reading the result:**
- `latest_major` is the value to pin to (e.g. `v4`, `v5`). Float on the major rather than the exact tag — actions follow GitHub's "v-major points at the latest patch within that major" convention, which mirrors how the user has the rest of this repo's deps pinned (`.upToNextMajor`).
- If the workflow is already on the latest major, mark **OK** and move on.
- If the workflow is on an older major, mark **bump** and proceed to step 6.3.
- If `releases/latest` returned empty AND no semver tags exist (rare — usually a custom internal action), flag it for manual review rather than guessing.

**Sanity check on the way out:** any row where `latest_major` does not match the pinned major is a mandatory bump. There are no exceptions for "stable enough" — the deprecation warnings only quiet down once every action is on its latest major.

Capture this table in your working scratch (or paste it into the PR description) so the reviewer can see, per release, which actions you bumped and to what.

### 6.3. Update each workflow file and reconcile inputs/env vars for the new major

Whenever an action crosses a major boundary, GitHub Actions treats it as a contract change — inputs may rename, become required, or stop being inferred. **Always read the action's release notes for the major you are jumping to** before pushing the bump. Pull them on demand:

```bash
# Release notes for the latest major of <owner>/<repo>
gh release view --repo <owner>/<repo> "$latest_tag" --json body --jq '.body'

# Or the full changelog between the currently pinned tag and latest
gh api "repos/<owner>/<repo>/compare/<old_tag>...<latest_tag>" --jq '.commits[].commit.message'
```

Categories of breaking change to look for in those notes (verify each against the action's actual release notes — do not assume):
- **Required vs. inferred inputs**: did an input that used to be optional become mandatory? Common offenders are auth tokens (`token:` / `GITHUB_TOKEN` env), cache keys, and artifact names.
- **Renamed or removed inputs**: `with:` blocks that compiled fine on the old major may now reference dead inputs.
- **Uniqueness / scoping rules**: artifact actions in particular have tightened uniqueness rules across majors (per-job, per-run, per-matrix). If the workflow has matrix jobs sharing a name, that's the place to look.
- **Default behaviour changes**: cross-run artifact downloads, cache key fallbacks, and shallow-clone defaults have all flipped at major boundaries.
- **Runtime / Node version**: the whole reason for this audit. The release notes will say which Node runtime the action now requires.

For each `with:` and `env:` block in your workflow, cross-check it against the new major's documented inputs. If you cannot find a definitive answer in the release notes, link the workflow line in the PR description and ask the reviewer to sanity-check rather than guessing.

### 6.4. Verify the workflows still parse before committing

```bash
# Preferred — actionlint catches version-specific input errors
command -v actionlint >/dev/null && actionlint .github/workflows/*.y*ml \
  || echo "actionlint not installed — skipping (install: brew install actionlint)"
```

Also run a YAML sanity check:

```bash
for f in .github/workflows/*.y*ml; do
  python3 -c "import yaml,sys; yaml.safe_load(open('$f'))" || echo "FAIL: $f"
done
```

### 6.5. Re-confirm the `release.yml` workflow specifically

It owns tarball production and the Homebrew dispatch (Step 8 of the main flow). If its actions were stale, the next release will fire on the updated workflow, so make sure it still uploads to the correct release and dispatches `formula-update` to homebrew-tap.

## 7. Single Commit and Push

Commit everything together — version bump + SPM audit fixes + lint fixes + doc updates + workflow updates — in a single commit:

```bash
git add Package.swift .gitignore Sources/<LibraryName>/<LibraryName>.swift README.md AGENTS.md CLAUDE.md GEMINI.md .github/workflows/
git commit -m "Bump version to X.Y.Z, update dependencies, docs, and CI actions

SPM package audit applied:
- Package.resolved removed from git tracking (if present)
- Sibling dependency pattern added/updated for intrusive-memory/* deps
- All dependencies updated to latest published versions
- Dependencies pinned to next major version boundary

CI workflows updated:
- All GitHub Actions bumped to latest major (eliminates Node 16/20 deprecation warnings)
- Action inputs/env vars reconciled for new majors"
git push origin development
```

**Important**: The version bump, SPM audit fixes, doc changes, and CI workflow updates are now part of the PR diff and will be included when the PR is merged.
