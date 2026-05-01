# Step 11: Mark Development Branch with `-dev` Version

After the rebase (Step 10), development is bit-identical to main and carries the just-shipped clean version (e.g. `1.4.3`). Stamp it with the `-dev` marker so the branch is unambiguously distinguishable from the release.

## Why this exists

`gh pr create` from a branch that has zero diff against base fails on some repos and silently no-ops on others (this is the "alternately failing and working" symptom). A real commit on development with the `-dev` bump guarantees there is always a non-empty diff for the next-cycle PR, regardless of repo configuration. It also makes "is this build a release or a dev snapshot?" answerable from the source itself.

## Choose the marker version

Use the version that was just released, with `-dev` appended:
- Just released `1.4.3` → development becomes `1.4.3-dev`
- Just released `2.0.0` → development becomes `2.0.0-dev`

The `-dev` suffix means "post-1.4.3 development, next release TBD." When the next ship cycle starts, step 3 will strip `-dev` and the user will pick the next clean version (`1.4.4`, `1.5.0`, `2.0.0`, etc.).

## Find every occurrence and replace it

The version string can live in multiple files. Locate them all, then update each:

```bash
RELEASED="X.Y.Z"            # the version you just released
DEV_MARKER="${RELEASED}-dev"

# List every file containing the released version (escape the dot for grep)
grep -rln --exclude-dir=.git --exclude-dir=.build "${RELEASED//./\\.}" .
```

Use the `Edit` tool to change each occurrence from `X.Y.Z` to `X.Y.Z-dev`. Typical locations:
- `Sources/<LibraryName>/<LibraryName>.swift` (the canonical version constant)
- `README.md` (installation snippets that show the version)
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` (any documented current version)

## Do NOT touch

- `Package.swift` dependency version constraints — those refer to *other* libraries' versions, not this one
- The CHANGELOG, release notes, or anything that records the historical release as `X.Y.Z`
- Any reference to other libraries' versions

## Verify, then commit and push

```bash
# Confirm every file holding the bare released version has been updated
grep -rln --exclude-dir=.git --exclude-dir=.build "${RELEASED//./\\.}" . | \
  xargs grep -L "${DEV_MARKER}" 2>/dev/null \
  || echo "All occurrences updated to ${DEV_MARKER}."

git add -A
git diff --cached --stat
git commit -m "Mark development as ${DEV_MARKER}

Post-release dev marker. The -dev suffix will be stripped at the
next ship cycle."
git push origin development
```
