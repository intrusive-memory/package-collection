# Intrusive Memory Swift Package Collection

A [Swift Package Collection](https://swift.org/blog/package-collections/) for all libraries in the **intrusive-memory** organization. This collection powers the Produciesta ecosystem for transforming screenplays into audio performances.

## Included Packages

| Package | Description |
|---------|-------------|
| SwiftAcervo | AI model discovery and management for HuggingFace models |
| SwiftBruja | On-device LLM inference via MLX |
| SwiftCompartido | Screenplay parsing, SwiftData models, SwiftUI components |
| SwiftEchada | Shared Swift utilities and extensions |
| SwiftFFMpeg | FFmpeg audio/video processing |
| SwiftFijos | Test fixture file discovery |
| SwiftHablare | Voice generation (Apple TTS, ElevenLabs, Qwen) |
| SwiftOnce | ElevenLabs TTS REST API wrapper |
| SwiftProyecto | Project metadata and file discovery |
| SwiftSecuencia | FCPXML timeline generation for Final Cut Pro |
| SwiftTuberia | MLX diffusion pipeline infrastructure |
| SwiftVinetas | Image generation with FLUX.2 and PixArt-Sigma |
| SwiftVoxAlta | On-device Qwen3-TTS voice design and cloning |
| flux-2-swift-mlx | FLUX.2 text-to-image generation via MLX |
| mlx-audio-swift | Audio TTS/STT/STS inference via MLX |
| pixart-swift-mlx | PixArt-Sigma DiT backbone plugin |

## Excluded Repos

| Repo | Reason |
|------|--------|
| SwiftEspeak | Deprecated/archived, replaced by SwiftVoxAlta |
| SwiftPruebas | Xcode project only, no Package.swift |
| SwiftVerificar | Multi-sub-package structure, no top-level Package.swift yet |
| mlx-image-swift | Research/docs only, not a Swift package |

## Adding the Collection

### In Xcode

1. Open Xcode
2. Go to **File > Add Package Collections...**
3. Click the **+** button
4. Enter the URL: `https://raw.githubusercontent.com/intrusive-memory/package-collection/main/collection.json`
5. Click **Add**

### Using Swift CLI

```bash
swift package-collection add https://raw.githubusercontent.com/intrusive-memory/package-collection/main/collection.json
```

To search packages in the collection:

```bash
swift package-collection search --keywords screenplay
```

## Automatic Updates

A GitHub Actions workflow runs daily at midnight UTC to check all repos for new releases. When a new version is detected, `collection.json` is automatically regenerated and committed. You can also trigger an update manually via the workflow_dispatch event.

## Bundled Skills

This repo also ships a set of [Claude Code](https://docs.claude.com/en/docs/claude-code) skills under `skills/`. Install them into any project with `cp -r skills/<name> .claude/skills/` or symlink the whole `skills/` directory. See [AGENTS.md](AGENTS.md) for installation details and longer descriptions.

| Skill | Summary |
|-------|---------|
| [create-pull-request](skills/create-pull-request/) | Finalize the current branch's draft PR — regenerate title/body from commits, fix the base branch, mark ready for review (creates a new PR only when none exists) |
| [dependency-purge](skills/dependency-purge/) | Nuclear Xcode/SPM clean — wipes DerivedData, the global SPM cache, and `Package.resolved`, then bumps every `intrusive-memory/*` dep's floor in `Package.swift` to the latest published release before resolution |
| [fix-code-signing](skills/fix-code-signing/) | Diagnose and fix XCTest bundle code-signing for hardened-runtime macOS apps |
| [generate-episode-audio](skills/generate-episode-audio/) | Render a podcast episode from a Fountain or Highland screenplay with Produciesta, wrap with intro/outro, open in QuickTime |
| [macos-say](skills/macos-say/) | Speak text aloud via the macOS `say` command |
| [mission-supervisor](skills/mission-supervisor/) | Plan and execute multi-sortie missions — `breakdown` → 5-pass `refine` → `start`/`resume`/`status`/`stop`/`killall`. On `start` (Swift/Xcode projects), preflights `/dependency-purge` so every build-gate sortie resolves clean |
| [mission-supervisor-report](skills/mission-supervisor-report/) | Generate a voiced "General" mission-debrief video composition for Final Cut Pro |
| [organize-agent-docs](skills/organize-agent-docs/) | Sort every markdown file into FOUNDATIONAL / MISSION / EXTRANEOUS buckets, maintain cross-links, stamp `updated:` dates |
| [package-iterator](skills/package-iterator/) | Fan out any skill across every library in `collection.json` in dependency order — same-level siblings run in parallel |
| [podcast-audio-plan](skills/podcast-audio-plan/) | Cast voices, generate audio, and prepare transcripts for Fountain-screenplay podcasts |
| [podcast-validate](skills/podcast-validate/) | Validate podcast CDN links and site integrity for intrusive-memory.productions |
| [release](skills/release/) | Tag and create a GitHub release for a merged PR |
| [ship-swift-library](skills/ship-swift-library/) | Bump, merge, tag, and release a Swift library version end-to-end (accepts `patch`/`minor`/`major` or explicit semver for unattended runs) |
| [shortcuts-helper](skills/shortcuts-helper/) | Create, run, and understand macOS Shortcuts (CLI, URL schemes, App Intents) |
| [spm-package-audit](skills/spm-package-audit/) | Audit and auto-fix SPM library packages — untrack `Package.resolved`, apply the sibling-dependency pattern via `/toggle-sibling-libraries`, bump every `intrusive-memory/*` dep |
| [toggle-sibling-libraries](skills/toggle-sibling-libraries/) | Flip `Package.swift` between the local-sibling dev pattern and the remote-only release pattern (only `intrusive-memory/*` deps participate) |
| [ui-ux-pro-max](skills/ui-ux-pro-max/) | UI/UX design intelligence — styles, palettes, font pairings, charts, and framework stacks |
| [update-package-library](skills/update-package-library/) | Refresh `collection.json` against the latest published GitHub releases for every tracked package (sub-commands: `update`, `update-deps`, `list`, `diff`, `verify`, `add-package`, `remove-package`) |
| [xcode-fix-arches](skills/xcode-fix-arches/) | Force arm64 — replace `$(ARCHS_STANDARD)` in pbxproj files and enforce arm64-only builds in xcconfig |
