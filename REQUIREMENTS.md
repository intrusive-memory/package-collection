# Package Collection — Outstanding Requirements

Tracks dependency mismatches, missing siblings, and curation gaps across the
Intrusive Memory Swift Package Collection. Items here are surfaced from
`update-package-library` analysis passes and should be resolved upstream so
that `collection.json` can converge on stable, version-pinned releases.

Last refreshed: 2026-04-21 (collection revision 17)

---

## 1. Branch-pinned internal dependencies

These packages still pin intrusive-memory siblings to a branch instead of a
released version. Migrate each entry to a version spec (`from:`,
`upToNextMajor:`, etc.) so consumers of the collection can resolve to a
stable release.

| Consumer | Dependency | Current spec | Notes |
|---|---|---|---|
| SwiftCompartido | intrusive-memory/SwiftFijos | `branch: main` | |
| SwiftEchada | intrusive-memory/SwiftProyecto | `branch: main` | |
| SwiftEchada | intrusive-memory/SwiftVoxAlta | `branch: main` | |
| SwiftEchada | intrusive-memory/mlx-audio-swift | `branch: main` | |
| SwiftEchada | ml-explore/mlx-swift-lm | `branch: main` | upstream — cannot bump locally |
| SwiftEchada | intrusive-memory/vox-format | `branch: main` | |
| SwiftHablare | intrusive-memory/SwiftFijos | `branch: main` | |
| SwiftHablare | intrusive-memory/SwiftCompartido | `branch: main` | |
| SwiftHablare | intrusive-memory/SwiftProyecto | `branch: main` | |
| SwiftHablare | intrusive-memory/SwiftOnce | `branch: main` | |
| SwiftSecuencia | intrusive-memory/SwiftCompartido | `branch: main` | |
| SwiftSecuencia | intrusive-memory/SwiftFijos | `branch: main` | |
| SwiftSecuencia | intrusive-memory/pipeline-neo | `branch: development` | repo not in collection |

## 2. Version mismatches against shipped releases

Dependency declarations point at versions that don't exist or have already
shipped past the requested floor.

| Consumer | Dependency | Requested | Latest released | Action |
|---|---|---|---|---|
| SwiftVoxAlta | intrusive-memory/SwiftHablare | `upToNextMajor: 5.7.5` | 5.7.2 | Awaiting Hablare 5.7.5 release |
| SwiftVoxAlta | intrusive-memory/mlx-audio-swift | `upToNextMajor: 0.3.5` | 0.4.0 | OK once collection tracks mlx-audio-swift |
| SwiftVoxAlta | intrusive-memory/SwiftAcervo | `upToNextMajor: 0.7.1` | 0.7.2 | Resolves automatically (upToNextMajor) |

## 3. mlx-swift-lm 3.31.3 migration (in flight)

Several packages need to migrate to `ml-explore/mlx-swift-lm: upToNextMajor: 3.31.3`.

| Package | Current spec |
|---|---|
| SwiftBruja | `upToNextMajor: 3.31.3` ✅ already migrated |
| mlx-audio-swift | `upToNextMajor: 3.31.3` ✅ already migrated |
| SwiftEchada | `branch: main` — needs version pin |

## 4. Untracked intrusive-memory siblings referenced as deps

Repos referenced from inside the collection that are not yet curated as
package entries.

| Repo | Referenced by | Status |
|---|---|---|
| intrusive-memory/mlx-audio-swift | SwiftEchada, SwiftVoxAlta | **added in revision 12** |
| intrusive-memory/vox-format | SwiftEchada, SwiftVoxAlta | **added in revision 13** |
| intrusive-memory/SwiftTuberia | SwiftVoxAlta | **added in revision 14** |
| intrusive-memory/pipeline-neo | SwiftSecuencia | not yet added |
