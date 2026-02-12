# Intrusive Memory Swift Package Collection

A [Swift Package Collection](https://swift.org/blog/package-collections/) for all libraries in the **intrusive-memory** organization. This collection powers the Produciesta ecosystem for transforming screenplays into audio performances.

## Included Packages

| Package | Description |
|---------|-------------|
| SwiftBruja | On-device LLM inference via MLX |
| SwiftCompartido | Screenplay parsing, SwiftData models, SwiftUI components |
| SwiftFFMpeg | FFmpeg audio/video processing |
| SwiftFijos | Test fixture file discovery |
| SwiftHablare | Voice generation (Apple TTS, ElevenLabs, Qwen) |
| SwiftProyecto | Project metadata and file discovery |
| SwiftPruebas | Shared test utilities |
| SwiftSecuencia | FCPXML timeline generation for Final Cut Pro |

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
