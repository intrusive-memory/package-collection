# Package Collection — Agent Instructions

This document is the canonical source of project context for all AI agents (Claude, Gemini, Codex, etc.).

---

## Project Overview

This is a Swift Package Collection for the **Intrusive Memory** organization. It aggregates multiple Swift packages into a single discoverable collection.

---

## Icon Generation Style Guide

All package icons share a consistent Mid-Century Modern visual language:

- **Subject**: Wooden articulated artist drawing mannequin (figure model)
- **Style**: 1950s-1960s Mid-Century Modern illustration
- **Background**: Atomic-age geometric room divider pattern — rounded rectangles/squares on vertical lines
- **Color palette**: Dusty blue, seafoam, cream white, warm honey wood tones
- **Floor**: Warm honey-toned wood plank floor
- **Texture**: Hand-painted look with subtle brushstrokes, grainy vintage paper overlay
- **Format**: Square (1:1 aspect ratio), suitable for app icons and podcast covers
- **Text**: Generally none (exceptions noted per icon)
- **Faces**: Blank (no facial features on mannequins)
- **Resolution**: High-resolution, minimum 2048x2048

### Base Prompt Template

```
A high-resolution square podcast cover art in a 1950s Midcentury Modern illustration style.
Subject: A single wooden articulated artist mannequin [POSE/ACTION].
Environment: [FLOOR/SETTING].
Background: An atomic-age geometric room divider pattern of rounded cream squares and
rectangles on thin vertical lines.
Atmosphere: A soft gradient of dusty blue and seafoam sky visible through the screen.
Texture: Hand-painted look with subtle brushstrokes and a grainy vintage paper overlay.
Vibe: [MOOD]. No text. 1:1 Aspect Ratio.
```

### Refinement Tips

- If figures don't look wooden enough, add: `"articulated wooden drawing mannequin, jointed limbs, smooth wood grain texture"`
- If style isn't matching, reference: `"in the style of vintage travel posters"` or `"Googie architecture aesthetic"`
- For exact blue tones: specify `"dusty blue, seafoam, cream"`
- For back views, add `"back view only"` or `"faceless"` if AI adds faces
- For minimal backgrounds: `"minimalist screen divider"` or `"George Nelson style aesthetic"`

---

## Icon Inventory

| Package | Repo | Icon File | Status |
|---------|------|-----------|--------|
| SwiftAcervo | `intrusive-memory/SwiftAcervo` | — | Missing |
| SwiftBruja | `intrusive-memory/SwiftBruja` | `SwiftBruja.jpg` | Done |
| SwiftCompartido | `intrusive-memory/SwiftCompartido` | `SwiftCompartido.jpg` | Done |
| SwiftEchada | `intrusive-memory/SwiftEchada` | — | Missing |
| SwiftFFMpeg | `intrusive-memory/SwiftFFMpeg` | `SwiftFFmpeg.jpg` | Done |
| SwiftFijos | `intrusive-memory/SwiftFijos` | `SwiftFijos.jpg` | Done |
| SwiftHablare | `intrusive-memory/SwiftHablare` | `SwiftHablare.jpg` | Done |
| SwiftOnce | `intrusive-memory/SwiftOnce` | — | Missing |
| SwiftProyecto | `intrusive-memory/SwiftProyecto` | `SwiftProyecto.jpg` | Done |
| SwiftSecuencia | `intrusive-memory/SwiftSecuencia` | `SwiftSecuencia.jpg` | Done |
| SwiftTuberia | `intrusive-memory/SwiftTuberia` | — | Missing |
| SwiftVinetas | `intrusive-memory/SwiftVinetas` | — | Missing |
| SwiftVoxAlta | `intrusive-memory/SwiftVoxAlta` | — | Missing |
| flux-2-swift-mlx | `intrusive-memory/flux-2-swift-mlx` | — | Missing |
| mlx-audio-swift | `intrusive-memory/mlx-audio-swift` | — | Missing |
| pixart-swift-mlx | `intrusive-memory/pixart-swift-mlx` | — | Missing |

---

## Generated Icon Details

### SwiftBruja (Bruja / Witch)

- **File**: `SwiftBruja/SwiftBruja.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Description**: Mannequin seated in lotus meditation pose, viewed from behind, wearing a witch hat, holding a magic wand with stars emanating from the wand's swipe
- **Iterations**:
  1. Started with lotus meditation pose (no hat, no wand)
  2. Added text "BRUJA / WITCH / WICCEN"
  3. Removed text, added witch hat and magic wand with emanating stars

### SwiftProyecto (Project)

- **File**: `SwiftProyecto/SwiftProyecto.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Description**: Mannequin standing with witch hat and magic wand, the wand revealing the word "PROJECT" in sparkles
- **Note**: One of the few icons that includes text (the word "PROJECT" as part of the magical effect)

### SwiftHablare (Voice/Speech)

- **File**: `SwiftHablare/SwiftHablare.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Description**: Close-up of mannequin's head and upper body with wide-brim hat, hands cupped together with magic/voice energy emanating from cupped hands, "HABLARE" text at top

### SwiftCompartido (Shared/Toolbox)

- **File**: `SwiftCompartido/SwiftCompartido.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Description**: 3/4 shot of mannequin (no hat) holding a toolbox, representing "fixtures"/shared components

### SwiftFijos (Fixtures/Plumbing)

- **File**: `SwiftFijos/SwiftFijos.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Description**: 3/4 shot of mannequin wearing a plumber-style trucker cap, using a wrench to adjust an unseen pipe on the wall

---

## Other Sessions (Podcast Art / Non-Package Icons)

### Session 1 — Simon & Simon Pose (5967b5fb63d9)

- **Link**: [5967b5fb63d9](https://gemini.google.com/share/5967b5fb63d9)
- **Purpose**: Two figure models in a back-to-back arms-folded pose (inspired by Simon and Simon TV show)

### Session 2 — Lotus Pose Reformatting & Palm Springs (a0e8452ec1fc)

- **Link**: [a0e8452ec1fc](https://gemini.google.com/share/a0e8452ec1fc)
- **Purpose**: Reformatting a lotus-pose mannequin into square icon format, plus Palm Springs podcast art
- **Style notes for Palm Springs variant**: "warm Palm Springs desert color palette: turquoise, burnt orange, sand beige, warm wood tones. Dark comedy noir mood despite cheerful retro style"

### Session 3 — Prompt Refinement (efa865b4c2fb)

- **Link**: [efa865b4c2fb](https://gemini.google.com/share/efa865b4c2fb)
- **Purpose**: Developing and refining the base MCM prompt template. This session produced the definitive base prompt template used for all subsequent icons.

---

## Packages Missing Icons

| Package | Purpose | Suggested Theme |
|---------|---------|-----------------|
| **SwiftAcervo** | AI model discovery/management | Mannequin browsing a card catalog or filing cabinet of models |
| **SwiftEchada** | Shared utilities/extensions | Mannequin with a Swiss army knife or multi-tool |
| **SwiftFFMpeg** | FFmpeg audio/video wrapper | Mannequin operating a vintage film projector or reel-to-reel |
| **SwiftOnce** | ElevenLabs TTS API wrapper | Mannequin speaking into a vintage telephone or radio mic |
| **SwiftSecuencia** | FCPXML timeline / Final Cut Pro | Mannequin arranging film strips or a clapperboard |
| **SwiftTuberia** | Diffusion pipeline infrastructure | Mannequin assembling copper pipes or plumbing fixtures |
| **SwiftVinetas** | Image generation orchestration | Mannequin painting on an easel with colorful splashes |
| **SwiftVoxAlta** | On-device voice design/cloning | Mannequin at a mixing console with sound waves |
| **flux-2-swift-mlx** | FLUX.2 text-to-image | Mannequin with glowing blueprint or technical drawing |
| **mlx-audio-swift** | MLX audio inference | Mannequin wearing headphones at a reel-to-reel |
| **pixart-swift-mlx** | PixArt-Sigma backbone | Mannequin examining pixels through a loupe |

### Suggested Prompts for Missing Icons

**SwiftFFMpeg**:
```
A high-resolution square icon in a 1950s Midcentury Modern illustration style.
Subject: A single wooden articulated artist mannequin operating a vintage
reel-to-reel tape recorder, hands adjusting the reels. 3/4 shot.
Environment: Warm honey-toned wood plank floor. Background: Atomic-age
geometric room divider pattern of rounded cream squares and rectangles on
thin vertical lines. Atmosphere: Dusty blue and seafoam gradient. Texture:
Hand-painted with subtle brushstrokes and vintage paper overlay. No text.
1:1 Aspect Ratio.
```

**SwiftSecuencia**:
```
A high-resolution square icon in a 1950s Midcentury Modern illustration style.
Subject: A single wooden articulated artist mannequin holding a vintage film
clapperboard in one hand and arranging a strip of film cells with the other.
3/4 shot. Environment: Warm honey-toned wood plank floor. Background:
Atomic-age geometric room divider pattern of rounded cream squares and
rectangles on thin vertical lines. Atmosphere: Dusty blue and seafoam gradient.
Texture: Hand-painted with subtle brushstrokes and vintage paper overlay.
No text. 1:1 Aspect Ratio.
```

---

## Skills Inventory

Reusable Claude Code skills are stored in the `skills/` directory. To install a skill into a project, copy its directory into the project's `.claude/skills/` folder (or symlink it).

### Installation

```bash
# Install a single skill into the current project
cp -r skills/<skill-name> .claude/skills/

# Or install all skills
cp -r skills/* .claude/skills/

# Or symlink for automatic updates
ln -s "$(pwd)/skills/<skill-name>" .claude/skills/<skill-name>
```

### Available Skills

| Skill | Invocation | Description |
|-------|-----------|-------------|
| **fix-code-signing** | `/fix-code-signing` | Diagnoses and fixes code signing configuration issues for XCTest bundles in hardened runtime macOS apps |
| **macos-say** | `/macos-say` | Use macOS text-to-speech via the `say` command for voice feedback, audio narration, and spoken output |
| **release** | `/release` | Release a merged PR by tagging and creating a GitHub release |
| **ship-ios-app** | `/ship-ios-app` | Ships new versions of iOS/macOS apps via App Store Connect |
| **ship-swift-library** | `/ship-swift-library` | Ship and release Swift library versions — merge PR, bump version, tag, create GitHub release |
| **shortcuts-helper** | `/shortcuts-helper` | Create, run, and understand macOS Shortcuts workflows with CLI, URL schemes, and App Intents |
| **mission-supervisor** | `/mission-supervisor` | Plan and execute missions — `breakdown` generates a plan from requirements, `refine` performs 4 passes (atomicity, priority, parallelism, open questions), then restart context and `start/resume/status/stop/killall` orchestrate sortie agents |
| **ui-ux-pro-max** | `/ui-ux-pro-max` | UI/UX design intelligence — 50 styles, 21 palettes, 50 font pairings, 20 charts, 8 framework stacks |

### Skill Structure

Each skill follows the standard Claude Code skill format:

```
skills/<skill-name>/
├── SKILL.md          # Skill definition (frontmatter + instructions)
├── README.md         # Optional user-facing documentation
├── data/             # Optional data files (CSV, JSON, etc.)
├── reference/        # Optional reference materials
└── scripts/          # Optional helper scripts
```

The `SKILL.md` frontmatter defines metadata:

```yaml
---
name: skill-name
description: What the skill does
allowed-tools: Bash, Read, Edit, ...
---
```
