# Shared Models Audit & Standardization Plan

## The Problem

Multiple libraries each define their own subfolder under `~/Library/Caches/intrusive-memory/Models/`,
and mlx-audio-swift also triggers downloads to `~/.cache/huggingface/hub/`. A model downloaded by one
library is invisible to another because each looks only in its own subdirectory. Qwen3-TTS models
currently appear in **both** `TTS/` and `Audio/`, wasting ~10 GB of disk space on duplicates.

**Target**: Standardize all projects to use **`~/Library/SharedModels/`** as the single canonical
location for all HuggingFace models, with no type-based subdirectories.

---

## Current State (on disk)

| Cache Location | Size | Contents |
|---|---|---|
| `~/Library/Caches/intrusive-memory/Models/LLM/` | 6.0 GB | `mlx-community_Phi-3-mini-4k-instruct-4bit`, `mlx-community_Qwen2.5-7B-Instruct-4bit` |
| `~/Library/Caches/intrusive-memory/Models/TTS/` | 10 GB | `mlx-community_Qwen3-TTS-12Hz-0.6B-Base-bf16`, `mlx-community_Qwen3-TTS-12Hz-1.7B-Base-bf16`, `mlx-community_Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` |
| `~/Library/Caches/intrusive-memory/Models/Audio/` | 7.4 MB | 12 models incl. duplicates of all 3 TTS models above, plus GLMASR, orpheus, pocket-tts, snac, Soprano, VyvoTTS |
| `~/Library/Caches/intrusive-memory/Models/VLM/` | 0 B | Empty |
| `~/.cache/huggingface/hub/` | 683 MB | 12 HuggingFace Hub-format model dirs (metadata/refs only; blobs pruned) |
| **Total** | **~17 GB** | Many duplicated across locations |

---

## Hardcoded Paths Per Project

### 1. SwiftBruja (LLM inference)

| File | Line(s) | Hardcoded Path | Configurable? |
|---|---|---|---|
| `Sources/SwiftBruja/Core/BrujaModelManager.swift` | 19-23 | `~/Library/Caches/intrusive-memory/Models/LLM` | No (CLI `--destination` overrides for single download) |
| `Sources/SwiftBruja/Core/BrujaModelManager.swift` | 38-41 | Model subdir: `{org}_{repo}` (slash to underscore) | No |
| `Sources/bruja/BrujaCLI.swift` | 16, 41, 62, 131, 178, 191, 242 | Help text references same path | N/A (docs) |

**Downloads**: `config.json`, `tokenizer.json`, `tokenizer_config.json`, `model.safetensors` directly from `https://huggingface.co/{modelId}/resolve/main/`

**Naming**: `mlx-community/Qwen2.5-7B-Instruct-4bit` -> `mlx-community_Qwen2.5-7B-Instruct-4bit/`

---

### 2. Produciesta (main app)

| File | Line(s) | Hardcoded Path | Configurable? |
|---|---|---|---|
| `Produciesta/Models/MLXModelDownloader.swift` | 19-26 | `~/Library/Caches/intrusive-memory/Models/LLM/{model}` | No |
| `Produciesta/Models/MLXModelManager.swift` | 43-55 | Uses `MLXModelDownloader.shared.modelDirectory` | No |

**Note**: Duplicates SwiftBruja's path logic independently rather than using SwiftBruja's `BrujaModelManager`.

---

### 3. SwiftVoxAlta (Qwen3-TTS voice design)

| File | Line(s) | Hardcoded Path | Configurable? |
|---|---|---|---|
| `Sources/diga/DigaModelManager.swift` | 35-73 | `~/Library/Caches/intrusive-memory/Models/TTS/` | No |
| `Sources/SwiftVoxAlta/VoxAltaModelManager.swift` | 128-131 | Delegates to `TTSModelUtils.loadModel(modelRepo:)` which uses Audio/ path | No |

**Problem**: `DigaModelManager` looks in `TTS/` but `VoxAltaModelManager` delegates to mlx-audio-swift which uses `Audio/`. Same models, different directories.

---

### 4. mlx-audio-swift (TTS/STT inference engine)

| File | Line(s) | Hardcoded Path | Configurable? |
|---|---|---|---|
| `Sources/MLXAudioCore/ModelUtils.swift` | 114-115 | `~/Library/Caches/intrusive-memory/Models/Audio/{model}` | No |
| `Sources/MLXAudioSTT/Models/GLMASR/GLMASR.swift` | (resolveOrDownloadModel) | Same Audio/ path | No |
| `Sources/MLXAudioTTS/Models/PocketTTS/PocketTTSModel.swift` | (resolveOrDownloadModel) | Same Audio/ path | No |
| `Sources/MLXAudioTTS/Models/Qwen3/Qwen3.swift` | (resolveOrDownloadModel) | Same Audio/ path | No |
| `Sources/MLXAudioTTS/Models/Soprano/Soprano.swift` | (resolveOrDownloadModel) | Same Audio/ path | No |
| `Sources/MLXAudioTTS/Models/Llama/LlamaTTS.swift` | (resolveOrDownloadModel) | Same Audio/ path | No |
| `Sources/MLXAudioCodecs/SNAC/SNACDecoder.swift` | (resolveOrDownloadModel) | Same Audio/ path | No |
| `Sources/MLXAudioTTS/Models/Marvis/MarvisTTSModel.swift` | (resolveOrDownloadModel) | Same Audio/ path + `prompt_cache` subdir | No |

**Note**: The `resolveOrDownloadModel()` logic is copy-pasted into 8 separate files. Also downloads via `HubClient` which writes to `~/.cache/huggingface/hub/` first, then copies to the Audio/ path.

---

### 5. swift-huggingface (Hub library, transitive dependency)

| File | Line(s) | Path | Configurable? |
|---|---|---|---|
| `Sources/HuggingFace/Shared/CacheLocationProvider.swift` | 162-189 | `~/.cache/huggingface/hub/` | Yes: `HF_HUB_CACHE` or `HF_HOME` env vars |

**Note**: This is the *upstream* HuggingFace Swift library. All projects that use `HubClient` trigger downloads here first. Setting `HF_HUB_CACHE` can redirect this, but each project then copies to its own subfolder anyway.

---

### 6. SwiftEchada (CLI utilities)

| File | Line(s) | Path | Configurable? |
|---|---|---|---|
| `Sources/echada/DownloadCommand.swift` | 24-25 | Delegates to `Bruja.download()` | Via SwiftBruja |

**No independent path logic** - passes through to SwiftBruja.

---

### 7. SwiftProyecto (project management CLI)

| File | Line(s) | Path | Configurable? |
|---|---|---|---|
| `Sources/proyecto/ProyectoCLI.swift` | 48-49, 61, 75 | Help text and CLI display referencing `Bruja.defaultModelsDirectory` | Via SwiftBruja |

**No independent path logic** - passes through to SwiftBruja.

---

### 8. SwiftHablare (voice generation)

**No model storage yet**. QwenTTSEngine is planned but not implemented. When it ships, it will need to use the shared path.

---

### Projects with NO model references

- **SwiftCompartido** - Screenplay parsing, document-scoped file storage only
- **SwiftSecuencia** - FCPXML generation
- **SwiftOnce** - ElevenLabs API client (remote API, no local models)
- **SwiftVerificar** - PDF validation
- **SwiftPruebas** - Test utilities
- **SwiftFijos** - Test fixture discovery
- **SwiftEspeak** - eSpeak-NG wrapper
- **SwiftFFMpeg** - FFmpeg wrapper

---

## Identified Duplications

| Model | In LLM/ | In TTS/ | In Audio/ | In ~/.cache/hf/ |
|---|---|---|---|---|
| Qwen3-TTS-12Hz-0.6B-Base-bf16 | | X | X | X (refs) |
| Qwen3-TTS-12Hz-1.7B-Base-bf16 | | X | X | X (refs) |
| Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16 | | X | X | X (refs) |
| Qwen2.5-7B-Instruct-4bit | X | | | |
| Phi-3-mini-4k-instruct-4bit | X | | | |
| GLMASR, orpheus, pocket-tts, etc. | | | X | X (refs) |

The 3 Qwen3-TTS models exist in both `TTS/` and `Audio/` -- this is the exact "missing model" problem.

---

## Proposed Changes

### New canonical path: `~/Library/SharedModels/{org}_{repo}/`

**No type subdirectories.** All models live flat under `~/Library/SharedModels/` with the existing `org_repo` naming convention (slash to underscore).

### Files to modify

#### SwiftBruja (2 files)
- [ ] `Sources/SwiftBruja/Core/BrujaModelManager.swift:19-23` - Change `modelsDirectory` from `cachesDirectory + "intrusive-memory/Models/LLM"` to `homeDirectory + "Library/SharedModels"`
- [ ] `Sources/bruja/BrujaCLI.swift` - Update 7 help text references

#### Produciesta (1 file)
- [ ] `Produciesta/Models/MLXModelDownloader.swift:19-26` - Change `modelDirectory` to use `~/Library/SharedModels/{model}`
- [ ] *Consider*: Delete `MLXModelDownloader.swift` entirely and use `BrujaModelManager.shared` from SwiftBruja instead of duplicating the logic

#### SwiftVoxAlta (1 file)
- [ ] `Sources/diga/DigaModelManager.swift:35-73` - Change `modelsDirectory` from `cachesDirectory + "intrusive-memory/Models/TTS"` to `homeDirectory + "Library/SharedModels"`

#### mlx-audio-swift (8 files)
- [ ] `Sources/MLXAudioCore/ModelUtils.swift:114-115` - Change from `intrusive-memory/Models/Audio` to `Library/SharedModels`
- [ ] `Sources/MLXAudioSTT/Models/GLMASR/GLMASR.swift` - Same change in `resolveOrDownloadModel()`
- [ ] `Sources/MLXAudioTTS/Models/PocketTTS/PocketTTSModel.swift` - Same
- [ ] `Sources/MLXAudioTTS/Models/Qwen3/Qwen3.swift` - Same
- [ ] `Sources/MLXAudioTTS/Models/Soprano/Soprano.swift` - Same
- [ ] `Sources/MLXAudioTTS/Models/Llama/LlamaTTS.swift` - Same
- [ ] `Sources/MLXAudioCodecs/SNAC/SNACDecoder.swift` - Same
- [ ] `Sources/MLXAudioTTS/Models/Marvis/MarvisTTSModel.swift` - Same
- [ ] *Consider*: Extract shared path logic into a single `SharedModelPaths` utility to eliminate the 8-file duplication

#### Environment / HuggingFace Hub
- [ ] Set `HF_HUB_CACHE=~/Library/SharedModels` in shell profile or launchd so the HuggingFace Hub library also writes directly to the shared location (eliminates the double-download)

### Migration
- [ ] Create `~/Library/SharedModels/` directory
- [ ] Move existing models from `~/Library/Caches/intrusive-memory/Models/*/` to `~/Library/SharedModels/`
- [ ] Remove `~/Library/Caches/intrusive-memory/Models/` after confirming
- [ ] Decide whether to symlink old paths for backwards compatibility during transition

### Tests to update

#### SwiftBruja
- [ ] `Tests/SwiftBrujaTests/SwiftBrujaTests.swift` - Update `testBrujaDefaultModelsDirectory()`, `testModelsDirectory()` to expect `SharedModels` instead of `Caches/intrusive-memory/Models/LLM`

---

## Benefits

1. **No more missing models** - Every library looks in the same flat directory
2. **No duplicates** - TTS models won't exist in both `TTS/` and `Audio/`
3. **Persistent storage** - `~/Library/SharedModels/` won't be purged by macOS (unlike `~/Library/Caches/`)
4. **Simpler mental model** - One place to look, one place to clean up
5. **Disk savings** - Eliminates ~10 GB of current duplicates

## Risks

1. **Breaking change** - Existing downloaded models won't be found until migrated
2. **mlx-audio-swift is a fork** - Changes there affect upstream mergeability
3. **HF_HUB_CACHE env var** - Affects all HuggingFace tools on the system (Python included), which may or may not be desired
4. **Caches vs Library** - `~/Library/Caches/` can be purged by macOS disk management; `~/Library/` is persistent. This is a feature (models survive cleanup) but also means manual cleanup is required

---

## Decision Points for Review

1. **Flat vs. typed subdirectories?** The proposal above uses flat `~/Library/SharedModels/{org}_{repo}/`. Alternative: keep `LLM/`, `TTS/`, `Audio/` subdirs but all under `SharedModels/`. Flat is recommended to prevent the original problem from recurring.

2. **Should Produciesta keep its own `MLXModelDownloader`?** It duplicates SwiftBruja's logic. Consider deleting it and using `BrujaModelManager.shared` directly.

3. **Should mlx-audio-swift's 8 duplicated `resolveOrDownloadModel()` functions be consolidated?** Strong yes -- extract to a shared utility.

4. **Set `HF_HUB_CACHE` globally?** This redirects ALL HuggingFace downloads (including Python tools) to `~/Library/SharedModels/`. If Python HF tools should keep their own cache, skip this and accept the small duplication in `~/.cache/huggingface/`.

5. **Migration script or manual?** A shell script to `mv` model folders and create `~/Library/SharedModels/` is straightforward. Should it be included in each project's next release notes?
