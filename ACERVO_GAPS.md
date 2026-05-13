# ACERVO_GAPS.md — v2 API Compliance Gaps

**Reference**: [SwiftAcervo `USAGE.md`](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md) (manifest-first contract, v0.8.x)  
**Audited**: 2026-04-27  
**Auditor**: Claude Code  

Five libraries in this collection depend on `intrusive-memory/SwiftAcervo`. None are fully compliant with the v2 (0.8.x) manifest-first contract. No audits were archived. Gaps are listed below by library; existing per-repo `ACERVO_AUDIT.md` files are noted where they exist.

---

## Legend

| Severity | Meaning |
|---|---|
| **High** | Correctness bug — returns wrong results or pollutes real state |
| **Medium** | Contract violation — uses v0.7 escape-hatch pattern where manifest-first would work, or misses new API |
| **Low** | Ergonomics — partial error handling, missing docs |
| **Blocked** | Cannot be implemented until upstream SwiftAcervo adds a required API |

---

## SwiftBruja

**Repo**: `intrusive-memory/SwiftBruja` · **Version**: v1.6.0  
**SwiftAcervo pin**: `upToNextMajor(from: "0.8.2")` ✅  
**Existing audit**: None  
**Overall**: Nearly compliant. USAGE.md calls SwiftBruja the reference implementation and it earned that: `files: []`, Level 1/2 APIs, progress callbacks, `fetchManifest` for `--remote`. One narrow gap below.

| # | Severity | File | Gap |
|---|---|---|---|
| B-1 | Low | `Sources/bruja/BrujaCLI.swift:116,135` | Error handling catches only `AcervoError.manifestDownloadFailed` (the 404 case). USAGE.md §Error Handling recommends switching on all `AcervoError` cases: `modelNotFound`, `integrityCheckFailed`, `downloadSizeMismatch`, `fileNotInManifest`, `offlineModeActive` (added 0.8.1), `componentNotRegistered`. Currently any error other than a 404 manifest miss propagates as a raw Swift error to the CLI. |

---

## SwiftProyecto

**Repo**: `intrusive-memory/SwiftProyecto` · **Version**: 3.4.0  
**SwiftAcervo pin**: `from: "0.7.1"` (resolves `0.7.3`) ❌  
**Existing audit**: `Docs/missions/manifest-airdrop-2026-04/ACERVO_AUDIT.md` (written 2026-04-24, current)  
**Overall**: Two correctness bugs (P-1, P-2) that are wrong under any SwiftAcervo version. Four additional migration gaps.

| # | Severity | File | Gap |
|---|---|---|---|
| P-1 | **High** | `Sources/SwiftProyecto/Infrastructure/ModelManager.swift:143` | `isModelAvailable(_:)` passes `model.componentId` (`"phi3-mini-4k-4bit"`) to `Acervo.isModelAvailable(_:)`. That method requires an `org/repo` string; a string without a `/` throws `AcervoError.invalidModelId` internally, which is swallowed via `try?` — the method **always returns `false`** regardless of whether the model is on disk. Fix: pass `model.rawValue` (the repoId). |
| P-2 | **High** | `Sources/proyecto/ProyectoCLI.swift:98`, `Tests/…/ProjectGenerationIntegrationTest.swift:136` | Both sites do `Acervo.sharedModelsDirectory.appendingPathComponent(Acervo.slugify(componentId))`. `slugify("phi3-mini-4k-4bit")` produces `phi3-mini-4k-4bit` unchanged (no `/`), yielding a directory that does not exist. The model lives at `<shared>/mlx-community_Phi-3-mini-4k-instruct-4bit/`. Fix: `try Acervo.modelDirectory(for: Phi3ModelRepo.mini4bit.rawValue)`. |
| P-3 | Medium | `Package.swift:line with from: "0.7.1"` | Dependency pinned to `0.7.x`. Upgrade to `from: "0.8.0"` to access `hydrateComponent`, `fetchManifest`, `isComponentReadyAsync`, `customBaseDirectory`, `offlineModeActive`, and the bare `ComponentDescriptor` init. |
| P-4 | Medium | `Sources/SwiftProyecto/Infrastructure/ModelManager.swift:42–63` | `phi3RequiredFiles` declares 4 file paths with hard-coded SHA-256s and byte sizes. This is the v0.7-era pattern; 0.8 USAGE.md reframes it as an escape hatch. Concrete cost: (a) drift warnings on stderr when CDN regenerates, (b) SHA-256s maintained in four separate places. Fix: switch to bare `ComponentDescriptor(id:type:displayName:repoId:minimumMemoryBytes:metadata:)`. |
| P-5 | Medium | `Tests/…/AcervoDownloadIntegrationTests.swift:63–86` | Tests never set `Acervo.customBaseDirectory` despite the override being public since 0.7. Comment says "Can't actually reset Acervo's directory without private API" — outdated. Integration tests currently mutate the real `~/Library/Application Support/SwiftAcervo/SharedModels/` on the test host and leave a ~2.3 GB Phi-3 copy behind. Fix: set `Acervo.customBaseDirectory = tempDir` in `setUp`, restore `nil` in `tearDown`. |
| P-6 | Low | `Sources/proyecto/ProyectoCLI.swift:283` | `InitCommand` defaults `--model` to `Bruja.defaultModel` (Llama-3.2-1B), but `DownloadCommand` downloads Phi-3. Running `proyecto download` then `proyecto init` without `--model` attempts to load Llama, not Phi-3. Not a SwiftAcervo v2 issue per se, but surfaces during any migration pass. |

---

## SwiftTuberia

**Repo**: `intrusive-memory/SwiftTuberia` · **Version**: v0.5.0  
**SwiftAcervo pin**: `upToNextMajor(from: "0.7.3")` ❌  
**Existing audit**: None  
**Overall**: Clean architecture (protocol seam, progress callback wired, `ensureComponentReady` used correctly). Primary gap is the version pin and the declared file lists.

| # | Severity | File | Gap |
|---|---|---|---|
| T-1 | Medium | `Package.swift` | Pinned to `0.7.3`. Upgrade to `upToNextMajor(from: "0.8.0")` to access bare `ComponentDescriptor`, `hydrateComponent`, `fetchManifest`, `isComponentReadyAsync`, and `ACERVO_OFFLINE` test support. |
| T-2 | Medium | `Sources/TuberiaCatalog/Registration/CatalogRegistration.swift` | Two descriptors (`t5XXLEncoderComponentDescriptor`, `sdxlVAEDecoderComponentDescriptor`) declare explicit file lists (`files: t5XXLEncoderRequiredFiles`, 9 files; `files: sdxlVAEDecoderRequiredFiles`, 2 files) with `nil` checksums and `nil` sizes. These are stable model repos and the explicit lists add no value — the manifest would drive an identical download. Preferred pattern (after T-1 bump): bare `ComponentDescriptor` with no `files:` argument. |
| T-3 | Low | `Sources/TuberiaCatalog/Registration/CatalogRegistration.swift:ensureComponentReady` | Public `ensureComponentReady(_:)` propagates `AcervoError` as-is to callers with no discrimination or wrapping. Not wrong, but callers can't distinguish download failure from integrity failure without importing `SwiftAcervo` directly. |

---

## SwiftVoxAlta

**Repo**: `intrusive-memory/SwiftVoxAlta` · **Version**: v0.9.8  
**SwiftAcervo pin**: `upToNextMajor(from: "0.8.2")` ✅  
**Existing audit**: `ACERVO_AUDIT.md` at repo root (written 2026-04-23, updated 2026-04-26 — current)  
**Overall**: Pin is correct, `ensureComponentReady` is used correctly. Four open findings from the existing audit are summarized here. See `ACERVO_AUDIT.md` for the full analysis.

| # | Severity | File | Gap |
|---|---|---|---|
| V-1 | Medium | `Sources/SwiftVoxAlta/VoxAltaModelManager.swift:130–143` | All 7 `ComponentDescriptor`s declare the same 12-file `qwen3TTSRequiredFiles` list. USAGE.md v0.8: this is the v0.7 escape-hatch pattern. Since every variant declares the full Qwen3-TTS file set, the declared list duplicates what the manifest will authoritatively say. Fix: drop `files:` and `estimatedSizeBytes` from all 7 descriptors; use bare init. Delete the `qwen3TTSRequiredFiles` array. Update 3 test assertions in `ComponentDescriptorRegistrationTests.swift` that assert on `files.count >= 12` and `estimatedSizeBytes`. |
| V-2 | Medium / **Blocked** | `Sources/SwiftVoxAlta/VoxAltaModelManager.swift:319–351` | `withComponentAccess` closure is empty (`()`); `TTSModelUtils.loadModel(modelRepo:)` is called **outside** the access scope. This creates a TOCTOU window: another task could call `Acervo.deleteModel` between the closure exit and the load. Cannot be fixed in VoxAlta alone — `withComponentAccess` takes a synchronous closure; `TTSModelUtils.loadModel` is `async`. Blocked on SwiftAcervo adding an async-closure overload of `withComponentAccess` and `withModelAccess`. |
| V-3 | Low | `Sources/SwiftVoxAlta/VoxAltaModelManager.swift:_loadModelWithComponentValidation` | All `AcervoError` cases collapse into a single `VoxAltaError.modelNotAvailable(stringified-error)`. Switch on `AcervoError` at the SwiftAcervo boundary; include `.offlineModeActive` (added 0.8.1) and `.componentNotHydrated` (0.8.0). |
| V-4 | Low (library), Medium (docs) | `AGENTS.md` | App Group entitlement (`group.intrusive-memory.models`) is required on every signed app target that imports SwiftVoxAlta. USAGE.md step 2 calls this out explicitly. Neither `AGENTS.md` nor the README mentions it. Add a short "Integrating into an app target" section. |

---

## mlx-audio-swift

**Repo**: `intrusive-memory/mlx-audio-swift` · **Version**: v0.5.0  
**SwiftAcervo pin**: `upToNextMajor(from: "0.7.2")` ❌  
**Existing audit**: None  
**Overall**: `loadWithAcervoStrict` (P1 path) correctly uses `withComponentAccess` with the load inside the scope. P2 path uses the older `loadWithAcervo` which has a TOCTOU window and HuggingFace fallback paths still in place. 15 declared file lists need review — some are legitimate escape-hatch, others can go manifest-first.

| # | Severity | File | Gap |
|---|---|---|---|
| M-1 | **High** | `Package.swift` | Pinned to `0.7.2`. This is the oldest pin in the collection; 0.8.x APIs (`hydrateComponent`, `fetchManifest`, `isComponentReadyAsync`, bare `ComponentDescriptor`, `ACERVO_OFFLINE`) are all unavailable. Upgrade to `upToNextMajor(from: "0.8.0")`. |
| M-2 | Medium | `Sources/MLXAudioCore/AudioModelManager.swift:211–213` | Mimi descriptor pins `ComponentFile(relativePath: "tokenizer-e351c8d8-checkpoint125.safetensors")` — a checkpoint-hash filename specific to one CDN upload. When the CDN publishes an updated Mimi checkpoint under a different name, this will throw `AcervoError.fileNotInManifest` before any download starts. Fix: either use manifest-first (bare descriptor, `files: []`) or update the filename on each CDN regeneration. The former is safer. |
| M-3 | Medium | `Sources/MLXAudioCore/AudioModelManager.swift` | Codec and simple TTS models (SNAC, Encodec 24/48, DAC, VyvoTTS, Orpheus, Soprano, MarvisTTS, PocketTTS) declare file lists where manifest-first would work. These repos are stable and Intrusive Memory–controlled, which is exactly the case USAGE.md says to prefer `files: []` for. **Legitimate escape-hatch exceptions** (keep declared): `qwen3ASR_0_6B_4bitRequiredFiles` intentionally omits `tokenizer.json` (auto-generated at runtime); all three `qwen3TTS12Hz` variants intentionally omit `tokenizer.json` (same reason). |
| M-4 | Medium | `Sources/MLXAudioCore/AudioModelManager.swift:751–763` | `loadWithAcervo` calls `ensureModelReady` then `Acervo.modelDirectory(for:)` **outside** `withComponentAccess`. For P2 models this is the active code path (P1 uses `loadWithAcervoStrict` correctly). Same TOCTOU exposure as V-2 in SwiftVoxAlta; unlike V-2, this one is not blocked upstream — `load` in `loadWithAcervoStrict` is already a sync closure, so the pattern that works for P1 applies to P2 too. Fix: migrate P2 models to `loadWithAcervoStrict`. |
| M-5 | Medium | Comments in `AudioModelManager.swift:636` | P2 models are noted as "🚧 IN PROGRESS: Registered but still use HF fallback." The HuggingFace fallback paths in individual model loaders (e.g., `TTSModelUtils.swift`, individual `*ModelManager.swift` files) are still active. These bypass Acervo's integrity verification entirely. Resolve by routing all P2 loads through `loadWithAcervoStrict` and removing the HF fallback branches. |

---

## Summary Table

| Library | SwiftAcervo Pin | Correctness Bugs | Compliance Gaps | Full Audit? |
|---|---|---|---|---|
| SwiftBruja | 0.8.2 ✅ | 0 | B-1 (Low) | No |
| SwiftProyecto | 0.7.3 ❌ | P-1, P-2 (High) | P-3 through P-6 | `Docs/missions/manifest-airdrop-2026-04/ACERVO_AUDIT.md` |
| SwiftTuberia | 0.7.3 ❌ | 0 | T-1 through T-3 | No |
| SwiftVoxAlta | 0.8.2 ✅ | 0 | V-1 through V-4 | `ACERVO_AUDIT.md` (root) |
| mlx-audio-swift | 0.7.2 ❌ | 0 | M-1 through M-5 | No |

### Recommended fix order

1. **Fix SwiftProyecto P-1 and P-2** — these are real bugs in released code (wrong return value, wrong path printed).
2. **Bump version pins** on SwiftProyecto, SwiftTuberia, and mlx-audio-swift to `0.8.0+`.
3. **Migrate P2 models in mlx-audio-swift** to `loadWithAcervoStrict` and remove the HF fallback (M-4, M-5).
4. **Adopt bare descriptors** in SwiftVoxAlta (V-1) and SwiftTuberia (T-2) — mechanical, non-breaking.
5. **Add App Group entitlement docs** (V-4) and discriminate `AcervoError` at boundaries (B-1, V-3, T-3).
6. **File M-2** (Mimi checkpoint filename) — low urgency until the CDN regenerates Mimi.
