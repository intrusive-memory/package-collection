# Applicability & Naming Convention

This skill applies to Swift libraries in the `intrusive-memory` GitHub organization that follow the standard `development → PR → main → tag` release flow. The repository name is your first signal of what kind of project you're looking at.

## `Swift<PascalCaseWord>` — in-house Swift library (skill applies)

The suffix is typically a Spanish noun or verb that hints at the library's purpose. These are native in-house libraries and always use this skill's flow.

| Repo | Word origin | Purpose |
|---|---|---|
| SwiftAcervo | Spanish: collection/archive | Shared model registry for HuggingFace models |
| SwiftBruja | Spanish: witch | On-device LLM inference via MLX |
| SwiftCompartido | Spanish: shared | Screenplay parsing & SwiftData models |
| SwiftEchada | Spanish: cast/thrown | Utilities & extensions for the ecosystem |
| SwiftFijos | Spanish: fixed (plural) | Test fixture discovery |
| SwiftHablare | Spanish: will speak | TTS voice generation |
| SwiftOnce | Spanish: eleven | ElevenLabs TTS REST API wrapper |
| SwiftProyecto | Spanish: project | Project metadata & PROJECT.md parsing |
| SwiftSecuencia | Spanish: sequence | FCPXML timeline generation |
| SwiftTuberia | Spanish: piping | Componentized MLX generation pipelines |
| SwiftVoxAlta | Latin/Spanish: high voice | Qwen3-TTS voice cloning |

**Exceptions to the Spanish-word pattern:** the suffix may be an English/tech name when wrapping a known upstream tech (e.g. `SwiftFFMpeg` for the FFmpeg wrapper).

## `<kebab-case>-swift` — Swift port or independent fork (skill applies)

Swift libraries that started as ports or independent forks of upstream projects. Naming follows upstream rather than the Spanish-noun convention, but releases belong to us and the flow is identical to in-house libraries.

| Repo | Notes |
|---|---|
| mlx-audio-swift | Independent fork of `Blaizzy/mlx-audio-swift`; our own release train |

## `<domain>-format` — file format library (skill applies)

Libraries that define and implement a file format, typically shipping a Swift reader/writer plus a CLI. These are ancillary in scope but are still releasable Swift libraries with their own tags, Homebrew formulae (where applicable), and dependency graphs.

| Repo | Format |
|---|---|
| vox-format | VOX open voice identity file format |

## `<kebab-case>` data/source-of-truth repo (skill does NOT apply)

Single-file or data-driven repos where the "release" is the file itself, not a tagged library version.

| Repo | What it is | Release flow |
|---|---|---|
| package-collection | Swift Package Collection JSON | **main-only, no development branch** |

## Collaboration fork — local copy for upstreaming (skill does NOT apply)

A repo we maintain as a fork solely to offer pull requests back to an external primary maintainer. We do not cut our own releases — the upstream does. Never run this skill against one of these.

| Repo | Upstream / collaborator |
|---|---|
| pipeline-neo | Maintained to send PRs to the primary maintainer |

## `<PascalCaseWord>` with no `Swift` prefix — CLI tool or app (skill does NOT apply)

Standalone CLI tools or apps. Apps have their own per-app `ship-<app-name>` skill that embeds the App Store Connect references for that specific app — there is no generalized app-shipping skill.

| Repo | Kind |
|---|---|
| Produciesta | Podcast audio CLI (SwiftSecuencia-based) |
