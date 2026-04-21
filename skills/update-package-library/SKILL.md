---
name: update-package-library
description: Update collection.json with the latest published GitHub releases for tracked Swift packages. Use this skill whenever the user asks to refresh, update, sync, or regenerate the package collection, add or remove a package from the collection, check which packages are out of date, preview pending changes, refresh cross-package dependency information, or verify that every tracked repo has a valid release. Releases are the only source of truth — never falls back to tags. Sub-commands include update, update-deps, list, diff, verify, add-package, and remove-package.
allowed-tools: Bash, Read, Edit, AskUserQuestion
---

# update-package-library

Maintains `collection.json` for the Intrusive Memory Swift Package Collection. Every sub-command treats the **latest published GitHub release** as the only source of truth for a package's current version — tags without a release are ignored on purpose.

## When to use

- User asks to "update the collection", "refresh the manifests", "regenerate collection.json", "sync package versions", or similar.
- User wants to add a new Swift package to the collection or remove an existing one.
- User wants to preview what would change before running an update, or check which packages are out of date.
- User wants to verify every tracked repo still exists and has a release.

## Prerequisites

All sub-commands need:

- `gh` — authenticated against GitHub with read access to every tracked repo.
- `jq` — for JSON manipulation.
- `curl` — transitive dependency of `gh`.
- `bash` 4+ (the scripts use associative arrays). The shebang is `/opt/homebrew/bin/bash`; adjust if the user's bash lives elsewhere.

If `gh` auth is missing, stop and ask the user to run `gh auth login` rather than trying to work around it.

## Sub-commands

All scripts live in `scripts/` inside this skill. They auto-locate `collection.json` in the current directory or at the git repo root; set `COLLECTION_JSON=/path/to/collection.json` to override.

### update — refresh every manifest

```bash
bash scripts/update.sh               # refresh all packages
bash scripts/update.sh --only intrusive-memory/SwiftBruja   # one repo
bash scripts/update.sh --dry-run     # compute changes, don't write
```

For each package it reads `collection.json` → resolves `owner/repo` from the `url` → fetches the latest GitHub release → fetches `Package.swift` at that release tag → rebuilds the `versions` array **and** the `dependencies` dictionary (preserving `summary`, `keywords`, `readmeURL`, and `url`). If any package is missing a release, the run aborts and writes nothing — that's intentional: a partial update would produce a misleading `revision` bump.

On success it bumps `revision` and refreshes `generatedAt`.

### update-deps — refresh only the dependencies dictionary

```bash
bash scripts/update-deps.sh
bash scripts/update-deps.sh --only intrusive-memory/SwiftBruja
bash scripts/update-deps.sh --dry-run
```

Writes a `dependencies` dictionary onto each package entry, parsed from that package's `Package.swift` at its latest release tag. The dictionary maps the dependency repo identifier to the version spec declared in the manifest:

```json
"dependencies": {
  "intrusive-memory/SwiftEchada": "from: 0.1.0",
  "apple/swift-argument-parser": "upToNextMajor: 1.0.0"
}
```

Version-spec values preserve intent and include `from: X`, `exact: X`, `branch: X`, `revision: X`, `upToNextMajor: X`, `upToNextMinor: X`, or `unknown` if the declaration didn't match any recognized form. Local `.package(path: ...)` entries are skipped. Keys are `owner/name` for github.com URLs; otherwise the URL minus `.git`.

Note: `update.sh` already refreshes the dependencies dictionary as part of the full manifest refresh — run `update-deps.sh` standalone when you only want to touch dependency metadata (e.g. after editing the version-spec parser).

### list — show current vs. latest

```bash
bash scripts/list.sh
```

Prints a table of each package with its version in `collection.json`, the latest release on GitHub, and an `OUT OF DATE` / `NO RELEASE` flag. Exits non-zero if any package has no release — useful in CI.

### diff — preview pending changes

```bash
bash scripts/diff.sh
bash scripts/diff.sh --only intrusive-memory/SwiftBruja
```

Same data-gathering as `update.sh` but only prints a human-readable diff: version bumps, tools-version changes, added/removed products, added/removed targets, and platform version changes. Doesn't touch the file.

### verify — validate every repo

```bash
bash scripts/verify.sh
```

Checks (in order): the repo responds on the GitHub API, has at least one published release, and `Package.swift` at that release tag is fetchable and parses to a tools-version + package name. Non-zero exit if anything fails.

### add-package — insert a new repo

```bash
bash scripts/add-package.sh intrusive-memory/SwiftNew \
  --summary "One-line description." \
  --keywords "kw1,kw2,kw3"
```

Both flags are required — the summary and keywords are curated metadata that can't be derived from the repo. The script fails if the repo is already in the collection or has no release. New entries are inserted alphabetically by repo name (to match the existing file ordering).

### remove-package — drop a repo

```bash
bash scripts/remove-package.sh intrusive-memory/SwiftOld
bash scripts/remove-package.sh SwiftOld       # bare name also works if unambiguous
```

Bumps the revision and writes. Fails if the name matches zero or more than one package.

## Orchestration: the full "update the library" flow

When the user gives the unqualified request ("update the package library"), run the sub-commands in this order:

1. **list** — give the user a snapshot of current state so they see what's about to change.
2. **diff** — show the shape of the incoming changes (new targets, platform bumps, etc.).
3. Ask the user to confirm before applying, unless they explicitly said "just run it".
4. **update** — apply the refresh and bump `revision`.
5. Summarize: how many packages were refreshed, the new revision number, and whether any repos were skipped (they shouldn't be — `update` aborts on failure — but mention it if so).

Skip this choreography when the user asks for a single sub-command by name, or when they pass `--only` for a specific repo.

## Conventions

- **Releases only.** If a package has only tags, don't try to use them. Report the missing release and stop. This is deliberate — the user treats "published release" as a curation signal.
- **Preserve curated metadata.** `summary`, `keywords`, and `readmeURL` are hand-authored. `update.sh` never touches them; `add-package.sh` requires them as input.
- **One version entry.** `collection.json` currently stores only the latest version for each package (the `versions` array has length 1). Keep that shape — don't start appending history unless the user asks for it.
- **Alphabetical order.** The `packages` array is ordered alphabetically by repo name; `add-package.sh` maintains that invariant.

## Relationship to `generate-collection.sh`

The repo root contains an older `generate-collection.sh` that regenerates `collection.json` from scratch using a hardcoded repo list. This skill supersedes that script by driving updates from `collection.json` itself. Leave `generate-collection.sh` in place for now — it still works as a cold-start bootstrap if the JSON file is ever lost — but prefer this skill for ongoing maintenance.
