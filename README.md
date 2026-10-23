# Intrusive Memory Swift Package Collection

A [Swift Package Collection](https://swift.org/blog/package-collections/) for the libraries in the **intrusive-memory** organization: Swift packages for turning screenplays into voices, images and timelines on Apple Silicon — parsing and editing scripts, casting and generating voices, generating storyboard images, and assembling the results.

## Visibility

Every package in this organization is public (MIT unless noted). The
applications that integrate them are private and are not described here. See
[AGENTS.md](AGENTS.md#repository-visibility).

## Included Packages

Packages with a published GitHub release. These are the entries in
`collection.json`.

| Package | What it is | The problem it solves |
|---------|------------|------------------------|
| [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) | Manifest-driven discovery, download and verification of shared AI models, with a CLI | Every library downloaded and cached its own copy of multi-gigabyte models in its own place; Acervo gives them one shared, checksummed location |
| [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) | On-device LLM inference via MLX — one-line queries with automatic model download, plus a CLI | Running a local language model took per-project model plumbing; Bruja makes it one call, with no server and no API key |
| [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) | Screenplay parsing (Fountain, FDX, PDF, Highland), SwiftData models and SwiftUI display components | Every screenplay tool needed its own importers and data model for the same handful of formats |
| [SwiftEchada](https://github.com/intrusive-memory/SwiftEchada) | Cast management: designs on-device voices from character descriptions and records them in CAST.md; the `echada` CLI | Casting a script meant hand-designing a voice per character and keeping the cast notes in sync by hand |
| [SwiftEscribo](https://github.com/intrusive-memory/SwiftEscribo) | A stylized SwiftUI text editor for Markdown and Fountain, and the collection's canonical Fountain scanner | Each tool parsed Fountain its own way and they drifted; one scanner drives the editor, previews and every other consumer identically |
| [SwiftFFMpeg](https://github.com/intrusive-memory/SwiftFFMpeg) | Swift wrapper for the FFmpeg API | FFmpeg's C API is awkward and unsafe to call from Swift, but audio and video conversion needs it |
| [SwiftFijos](https://github.com/intrusive-memory/SwiftFijos) | Test-fixture file discovery | Swift packages and Xcode projects locate test fixtures differently; Fijos finds them the same way in both |
| [SwiftHablare](https://github.com/intrusive-memory/SwiftHablare) | Provider-agnostic text-to-speech: text + voice ID → audio, with Apple TTS built in | Apps needed one speech API regardless of which engine renders the voice |
| [SwiftOnce](https://github.com/intrusive-memory/SwiftOnce) | Swift 6 client for the ElevenLabs API: voices, voice design, streaming, caching | No concurrency-safe Swift client existed for ElevenLabs, and repeated renders re-paid for the same audio |
| [SwiftProyecto](https://github.com/intrusive-memory/SwiftProyecto) | PROJECT.md parsing, project metadata and episode file discovery | Screenplay projects needed one file describing the project, its episodes and its voice settings that every tool reads the same way |
| [SwiftReparto](https://github.com/intrusive-memory/SwiftReparto) | The CAST.md schema, parser and serializer; the `reparto` CLI | Tools that rewrote the cast file lost whatever people had written in it by hand; Reparto guarantees nothing hand-written disappears |
| [SwiftRepositorio](https://github.com/intrusive-memory/SwiftRepositorio) | A Swift API over libgit2 — clone, status, commit, fetch, push, branches, credentials | Sandboxed apps cannot shell out to `git`, and the native libgit2 / libssh2 / OpenSSL stack needs one owner to keep it patched |
| [SwiftSecuencia](https://github.com/intrusive-memory/SwiftSecuencia) | FCPXML timeline generation and audio export | Generated audio had to be assembled into an editable Final Cut Pro timeline by hand |
| [SwiftTuberia](https://github.com/intrusive-memory/SwiftTuberia) | Typed pipeline parts (encoders, schedulers, backbones, decoders) for MLX diffusion | Each diffusion model port re-implemented the same stages; Tuberia makes them shared, swappable components |
| [SwiftVinetas](https://github.com/intrusive-memory/SwiftVinetas) | Storyboard and comic-panel generation from text, on-device (FLUX.2, PixArt-Sigma) or with cloud models and reference images; SwiftUI prompt panel and `vinetas` CLI | Turning a written shot into a consistent panel meant juggling model-specific tools; Vinetas gives one API and CLI over local and cloud engines |
| [SwiftVoxAlta](https://github.com/intrusive-memory/SwiftVoxAlta) | On-device Qwen3-TTS voice design and cloning; the `diga` CLI | Distinct, consistent character voices without per-character fees or uploading audio to a service |
| [flux-2-swift-mlx](https://github.com/intrusive-memory/flux-2-swift-mlx) | Native Swift/MLX port of the FLUX.2 image model | FLUX.2 shipped for Python only; Swift apps need it natively on Apple Silicon |
| [glosa-av](https://github.com/intrusive-memory/glosa-av) | GLOSA, a performance and storyboard notation written in screenplay notes, and the Foundation-only compiler that reads it | A screenplay had no way to tell a voice or image generator how to perform or frame a moment without leaving the script |
| [glosa-tools](https://github.com/intrusive-memory/glosa-tools) | The `glosa` CLI and Stage Director tooling on top of glosa-av | Annotating a whole script by hand is slow; the tools draft and check GLOSA annotations |
| [mlx-audio-swift](https://github.com/intrusive-memory/mlx-audio-swift) | On-device text-to-speech, speech-to-text and speech-to-speech via MLX | Running audio models from Swift without a Python runtime |
| [pixart-swift-mlx](https://github.com/intrusive-memory/pixart-swift-mlx) | PixArt-Sigma backbone plugin for SwiftTuberia | A smaller, faster image model than FLUX.2 for machines with less memory |
| [vox-format](https://github.com/intrusive-memory/vox-format) | VOX, an open file format (CC0) for a voice identity | A designed voice was locked to the engine that made it; a `.vox` file carries it across engines |

## In Development

Public packages without a published release yet. They are not in
`collection.json` until their first release.

| Package | What it is | The problem it solves |
|---------|------------|------------------------|
| [SwiftAmbiente](https://github.com/intrusive-memory/SwiftAmbiente) | Ambience and foley background beds generated on Apple Silicon (scaffold) | Dialogue rendered on its own sounds dead; scenes need room tone and foley generated to match |
| [SwiftApoderado](https://github.com/intrusive-memory/SwiftApoderado) | An agentic coder backed by local models; the `apoderado` CLI | Coding-agent workflows without sending source code to a hosted model |
| [SwiftDossier](https://github.com/intrusive-memory/SwiftDossier) | The Swift implementation of dossier-format and the `dossier` CLI (requirements only) | A character's description, images and voice were scattered across tools; one validated bundle holds them |
| [SwiftHablareOnce](https://github.com/intrusive-memory/SwiftHablareOnce) | The ElevenLabs voice provider for SwiftHablare, built on SwiftOnce | Keeps SwiftHablare free of cloud dependencies; ElevenLabs becomes an opt-in package |
| [SwiftPersonaje](https://github.com/intrusive-memory/SwiftPersonaje) | One command per step from a name in a screenplay to a finished character dossier (requirements only) | Building a character took many manual steps across tools, with no record of how each piece was made |
| [SwiftSemblanzas](https://github.com/intrusive-memory/SwiftSemblanzas) | Character-consistent storyboard sequences from a trained character identity (pre-alpha) | A generated character drifts from panel to panel; a trained identity keeps them recognisable |
| [mlx-model](https://github.com/intrusive-memory/mlx-model) | The `.mlx` bundle format and a minimal Swift library | MLX models ship as loose files with no inventory; a bundle makes a model one verifiable unit |
| [swift-xet](https://github.com/intrusive-memory/swift-xet) | A Swift implementation of Hugging Face's Xet download protocol | Hugging Face moved large files to Xet storage, which Swift clients could not download |

## Related Public Repositories

Not Swift packages, but part of the same toolchain.

| Repo | What it is | The problem it solves |
|------|------------|------------------------|
| [dossier-format](https://github.com/intrusive-memory/dossier-format) | An open, language-agnostic format for a dramatic character: one `.dossier` bundle with a manifest, description, images, voice and an HTML page | Character material had no portable home that any tool could read and validate |
| [acervo-manifests](https://github.com/intrusive-memory/acervo-manifests) | A git-backed mirror of SwiftAcervo's CDN model manifests (no weights) | Model resolution failed whenever the CDN was unreachable |
| [PyProyecto](https://github.com/intrusive-memory/PyProyecto) | Read and write SwiftProyecto's PROJECT.md from Python | Python tooling needed the same project file the Swift tools use |

## Excluded Repos

| Repo | Reason |
|------|--------|
| SwiftEspeak | Archived, replaced by SwiftVoxAlta |
| SwiftGuion | Archived, superseded by SwiftCompartido |
| SwiftDrupal | Archived; outside this collection's scope |
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
| [branch-hygiene](skills/branch-hygiene/) | Post-release tail shared by the ship skills — sync `development` onto `main` (squash-aware), mark the next cycle (`-dev` for libraries, version bump for apps), open the draft next-cycle PR |
| [create-pull-request](skills/create-pull-request/) | Finalize the current branch's draft PR — regenerate title/body from commits, fix the base branch, mark ready for review (creates a new PR only when none exists) |
| [dependency-purge](skills/dependency-purge/) | Nuclear Xcode/SPM clean — wipes DerivedData, the global SPM cache, and `Package.resolved`, then bumps every `intrusive-memory/*` dep's floor in `Package.swift` to the latest published release before resolution |
| [fix-code-signing](skills/fix-code-signing/) | Diagnose and fix XCTest bundle code-signing for hardened-runtime macOS apps |
| [generate-episode-audio](skills/generate-episode-audio/) | Render a podcast episode's audio from a Fountain or Highland screenplay, wrap with intro/outro, open in QuickTime |
| [macos-say](skills/macos-say/) | Speak text aloud via the macOS `say` command |
| [mission-supervisor](skills/mission-supervisor/) | Plan and execute multi-sortie missions — `breakdown` → 5-pass `refine` → `start`/`resume`/`status`/`stop`/`killall`. On `start` (Swift/Xcode projects), preflights `/dependency-purge` so every build-gate sortie resolves clean |
| [mission-supervisor-report](skills/mission-supervisor-report/) | Generate a voiced "General" mission-debrief video composition for Final Cut Pro |
| [organize-agent-docs](skills/organize-agent-docs/) | Sort every markdown file into FOUNDATIONAL / MISSION / EXTRANEOUS buckets, maintain cross-links, stamp `updated:` dates |
| [package-iterator](skills/package-iterator/) | Fan out any skill across every library in `collection.json` in dependency order — same-level siblings run in parallel |
| [podcast-audio-plan](skills/podcast-audio-plan/) | Cast voices, generate audio, and prepare transcripts for Fountain-screenplay podcasts |
| [podcast-validate](skills/podcast-validate/) | Validate podcast CDN links and site integrity for intrusive-memory.productions |
| [release](skills/release/) | Tag and create a GitHub release for a merged PR |
| [ship-app](skills/ship-app/) | Ship iOS/macOS apps through `development → main` (TestFlight), `<version>-rc<n>` → `release/<version>` (App Store), and submission; ends with `/branch-hygiene` |
| [ship-swift-library](skills/ship-swift-library/) | Bump, merge, tag, and release a Swift library version end-to-end (accepts `patch`/`minor`/`major` or explicit semver for unattended runs) |
| [shortcuts-helper](skills/shortcuts-helper/) | Create, run, and understand macOS Shortcuts (CLI, URL schemes, App Intents) |
| [spm-package-audit](skills/spm-package-audit/) | Audit and auto-fix SPM library packages — untrack `Package.resolved`, apply the sibling-dependency pattern via `/toggle-sibling-libraries`, bump every `intrusive-memory/*` dep |
| [storyboard-flipbook](skills/storyboard-flipbook/) | Scene prompts → N on-model storyboard frames from the cast's `.dossier` reference portraits, bound into an HTML flipbook |
| [toggle-sibling-libraries](skills/toggle-sibling-libraries/) | Flip `Package.swift` between the local-sibling dev pattern and the remote-only release pattern (only `intrusive-memory/*` deps participate) |
| [ui-ux-pro-max](skills/ui-ux-pro-max/) | UI/UX design intelligence — styles, palettes, font pairings, charts, and framework stacks |
| [update-package-library](skills/update-package-library/) | Refresh `collection.json` against the latest published GitHub releases for every tracked package (sub-commands: `update`, `update-deps`, `list`, `diff`, `verify`, `add-package`, `remove-package`) |
| [xcode-fix-arches](skills/xcode-fix-arches/) | Force arm64 — replace `$(ARCHS_STANDARD)` in pbxproj files and enforce arm64-only builds in xcconfig |
