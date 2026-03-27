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
