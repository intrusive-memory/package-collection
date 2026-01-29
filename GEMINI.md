# Intrusive Memory Icon Generation — Gemini Sessions

This document captures the prompts, iterations, and style guide used to generate the Mid-Century Modern figure model icons for the Intrusive Memory Swift package collection using Google Gemini (Nano Banana Pro).

---

## Style Guide

All icons share a consistent visual language:

- **Subject**: Wooden articulated artist drawing mannequin (figure model)
- **Style**: 1950s–1960s Mid-Century Modern illustration
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

### Refinement Tips (from sessions)

- If figures don't look wooden enough, add: `"articulated wooden drawing mannequin, jointed limbs, smooth wood grain texture"`
- If style isn't matching, reference: `"in the style of vintage travel posters"` or `"Googie architecture aesthetic"`
- For exact blue tones: specify `"dusty blue, seafoam, cream"`
- For back views, add `"back view only"` or `"faceless"` if AI adds faces
- For minimal backgrounds: `"minimalist screen divider"` or `"George Nelson style aesthetic"`

---

## Generated Icons

### SwiftBruja (Bruja / Witch)

- **File**: `SwiftBruja/SwiftBruja.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Model**: Gemini Pro
- **Description**: Mannequin seated in lotus meditation pose, viewed from behind, wearing a witch hat, holding a magic wand with stars emanating from the wand's swipe
- **Iterations**:
  1. Started with lotus meditation pose (no hat, no wand)
  2. Added text "BRUJA / WITCH / WICCEN"
  3. Removed text, added witch hat and magic wand with emanating stars
- **Final prompt direction**: Remove text, witch hat on figure model, magic wand in hand with "magic" stars emanating from the swipe of the wand

### SwiftProyecto (Project)

- **File**: `SwiftProyecto/SwiftProyecto.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Model**: Gemini Pro
- **Description**: Mannequin standing with witch hat and magic wand, the wand revealing the word "PROJECT" in sparkles
- **Prompt direction**: Same witch hat, standing pose with magic wand, the magic wand is revealing the word PROJECT
- **Note**: One of the few icons that includes text (the word "PROJECT" as part of the magical effect)

### SwiftHablare (Voice/Speech)

- **File**: `SwiftHablare/SwiftHablare.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Model**: Gemini Pro
- **Description**: Close-up of mannequin's head and upper body with wide-brim hat, hands cupped together with magic/voice energy emanating from cupped hands, "HABLARE" text at top
- **Prompt direction**: Closeup of the figure model's head with hands cupping the voice and magic coming from the figure model's cupped hands as if it was a voice

### SwiftCompartido (Shared/Toolbox)

- **File**: `SwiftCompartido/SwiftCompartido.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Model**: Gemini Pro
- **Description**: 3/4 shot of mannequin (no hat) holding a toolbox, representing "fixtures"/shared components
- **Prompt direction**: Plain figure model without a hat in a 3/4 shot holding a toolbox. Represents "fixtures" without using the word

### SwiftFijos (Fixtures/Plumbing)

- **File**: `SwiftFijos/SwiftFijos.jpg`
- **Gemini session**: [6caf20f683bd](https://gemini.google.com/share/6caf20f683bd)
- **Model**: Gemini Pro
- **Description**: 3/4 shot of mannequin wearing a plumber-style trucker cap, using a wrench to adjust an unseen pipe on the wall
- **Prompt direction**: Figure model using a wrench to adjust some unseen pipe on the wall, 3/4 shot, wearing a plumber-style trucker cap

---

## Other Sessions (Podcast Art / Non-Package Icons)

### Session 1 — Simon & Simon Pose (5967b5fb63d9)

- **Link**: [5967b5fb63d9](https://gemini.google.com/share/5967b5fb63d9)
- **Model**: Gemini Pro
- **Purpose**: Two figure models in a back-to-back arms-folded pose (inspired by Simon and Simon TV show)
- **Iterations**:
  1. Initial request with reference image from Simon and Simon
  2. Clarification: wooden figures must be generic, no text, Simon and Simon only for pose reference
- **Note**: This appears to be for a podcast cover, not a package icon

### Session 2 — Lotus Pose Reformatting & Palm Springs (a0e8452ec1fc)

- **Link**: [a0e8452ec1fc](https://gemini.google.com/share/a0e8452ec1fc)
- **Model**: Gemini Fast
- **Purpose**: Reformatting a lotus-pose mannequin into square icon format, plus Palm Springs podcast art
- **Iterations**:
  1. Reformat existing illustration to square icon
  2. Rework to 2048x2048
  3. Enlarge and crop closer to figure
  4. Separate prompt for Palm Springs podcast art — two mannequins in conspiratorial pose on steam room bench, palm tree, neon "WELCOME TO PALM SPRINGS" sign blending into background on black pole
- **Style notes for Palm Springs variant**: "warm Palm Springs desert color palette: turquoise, burnt orange, sand beige, warm wood tones. Dark comedy noir mood despite cheerful retro style"

### Session 3 — Prompt Refinement (efa865b4c2fb)

- **Link**: [efa865b4c2fb](https://gemini.google.com/share/efa865b4c2fb)
- **Model**: Gemini Fast
- **Purpose**: Developing and refining the base MCM prompt template
- **Key contribution**: This session produced the definitive base prompt template used for all subsequent icons (documented in Style Guide above)
- **Note**: Gemini Fast could not generate images at the time; this session focused on prompt engineering and was then executed in the Pro session (6caf20f683bd)

---

## Packages Missing Icons

The following packages in the collection do not yet have a Mid-Century Modern figure model icon:

| Package | Purpose | Suggested Theme |
|---------|---------|-----------------|
| **SwiftEspeak** | eSpeak-NG TTS wrapper | Mannequin speaking into a vintage microphone |
| **SwiftFFMpeg** | FFmpeg audio/video wrapper | Mannequin operating a vintage film projector or reel-to-reel |
| **SwiftPruebas** | Shared test utilities | Mannequin with safety goggles holding a clipboard with checkmarks |
| **SwiftSecuencia** | FCPXML timeline / Final Cut Pro | Mannequin arranging film strips or a clapperboard |

### Suggested Prompts for Missing Icons

**SwiftEspeak**:
```
A high-resolution square icon in a 1950s Midcentury Modern illustration style.
Subject: A single wooden articulated artist mannequin standing at a vintage
ribbon microphone, mouth area positioned near the mic, one hand gesturing
expressively. Environment: Warm honey-toned wood plank floor. Background:
Atomic-age geometric room divider pattern of rounded cream squares and
rectangles on thin vertical lines. Atmosphere: Dusty blue and seafoam gradient.
Texture: Hand-painted with subtle brushstrokes and vintage paper overlay.
No text. 1:1 Aspect Ratio.
```

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

**SwiftPruebas**:
```
A high-resolution square icon in a 1950s Midcentury Modern illustration style.
Subject: A single wooden articulated artist mannequin wearing safety goggles
pushed up on forehead, holding a clipboard with checkmarks in one hand and
a magnifying glass in the other. 3/4 shot. Environment: Warm honey-toned
wood plank floor. Background: Atomic-age geometric room divider pattern of
rounded cream squares and rectangles on thin vertical lines. Atmosphere:
Dusty blue and seafoam gradient. Texture: Hand-painted with subtle
brushstrokes and vintage paper overlay. No text. 1:1 Aspect Ratio.
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
