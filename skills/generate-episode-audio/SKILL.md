---
name: generate-episode-audio
description: Generate podcast episode audio from Fountain or Highland screenplays using Produciesta CLI, wrap with intro/outro, and open in QuickTime Player. Use this skill whenever the user asks to "generate audio", "make audio", "produce episode audio", "create the audio", "generate episode", "render the episode", or any variation of turning a screenplay file into playable podcast audio. Also trigger when the user says "let's hear it", "play the episode", or references audio generation for any podcast-* project. Works across all intrusive-memory.productions podcasts (confessions, mr-mr-charles, casting-software-spells, daily-dao, meditations, etc.).
---

# Generate Episode Audio

Turn a .fountain or .highland screenplay into wrapped podcast audio with intro/outro and chapter markers.

## Workflow

### Step 1: Identify the Episode File

Determine the episode file. The user may specify it directly or you may need to find it:

```bash
ls episodes/episode_*.fountain episodes/episode_*.highland 2>/dev/null
```

### Step 2: Extract from Highland (if needed)

Highland files are zip archives. Extract the Fountain screenplay before generating audio:

```bash
unzip -p episodes/episode_XX.highland "*.textbundle/text.md" > episodes/episode_XX.fountain
```

Only do this if the source is `.highland` and no corresponding `.fountain` exists (or the user wants to regenerate from the highland source).

### Step 3: Check Pronunciation

Read the .fountain file and scan for words that TTS will mispronounce. Common issues:

- **Spanish terms**: Add phonetic spellings (e.g., "Rodillo" → "ro-DEE-yo", "Espectro" → "es-PEK-tro")
- **Technical jargon**: Unusual acronyms or tool names
- **Foreign names or phrases**: Any non-English words

If pronunciation issues are found, edit the .fountain file to add phonetic hints inline before generating. Show the user what you're changing and get confirmation.

### Step 4: Generate Audio

Run Produciesta to generate the episode audio:

```bash
produciesta generate --provider voxalta --episode episode_XX.fountain --regenerate /path/to/project
```

Key facts:
- Binary location: `/Users/stovak/.local/bin/produciesta`
- Voice provider: `voxalta` (uses .vox files in `voices/` directory)
- Cast list: defined in `PROJECT.md` YAML frontmatter
- The `--regenerate` flag forces regeneration even if audio already exists
- For single episodes, use `--episode <filename>` (filename only, not full path)

### Step 5: Intro/Outro Wrapping (Automatic)

The post-generation hook at `.produciesta-hooks/post-generation.sh` runs automatically after Produciesta finishes. It:

1. Concatenates `audio/intro.m4a` + episode audio + `audio/outro.m4a` using ffmpeg
2. Embeds chapter markers (Intro / Episode / Outro) in the M4A metadata
3. Skips files already wrapped (detected by checking for existing chapter markers)
4. Replaces the original episode file with the wrapped version

If wrapping doesn't happen automatically (no hook, or hook is missing), wrap manually:

```bash
# Create concat list
cat > /tmp/concat.txt <<EOF
file 'audio/intro.m4a'
file 'audio/episode_XX.m4a'
file 'audio/outro.m4a'
EOF

# Create chapter metadata (get durations with ffprobe)
INTRO_MS=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 audio/intro.m4a | awk '{printf "%.0f", $1 * 1000}')
EPISODE_MS=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 audio/episode_XX.m4a | awk '{printf "%.0f", $1 * 1000}')
OUTRO_MS=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 audio/outro.m4a | awk '{printf "%.0f", $1 * 1000}')

cat > /tmp/chapters.txt <<EOF
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=${INTRO_MS}
title=Intro

[CHAPTER]
TIMEBASE=1/1000
START=${INTRO_MS}
END=$((INTRO_MS + EPISODE_MS))
title=Episode

[CHAPTER]
TIMEBASE=1/1000
START=$((INTRO_MS + EPISODE_MS))
END=$((INTRO_MS + EPISODE_MS + OUTRO_MS))
title=Outro
EOF

# Concatenate and apply chapters
ffmpeg -y -f concat -safe 0 -i /tmp/concat.txt -i /tmp/chapters.txt -map_metadata 1 -c copy audio/episode_XX_wrapped.m4a
mv audio/episode_XX_wrapped.m4a audio/episode_XX.m4a
```

### Step 6: Play in QuickTime

Open the final wrapped audio for review:

```bash
open -a "QuickTime Player" audio/episode_XX.m4a
```

## Quick Reference

| Item | Value |
|------|-------|
| Produciesta binary | `/Users/stovak/.local/bin/produciesta` |
| Voice provider | `voxalta` |
| Voice files | `voices/*.vox` |
| Cast config | `PROJECT.md` (YAML frontmatter) |
| Intro/outro | `audio/intro.m4a`, `audio/outro.m4a` |
| Post-gen hook | `.produciesta-hooks/post-generation.sh` |
| Audio output | `audio/episode_XX.m4a` |

## Cross-Project Usage

This skill works on any `podcast-*` project. The project path is the working directory or can be specified explicitly. Each project has its own:
- `PROJECT.md` with cast list and voice assignments
- `voices/` directory with .vox files
- `audio/intro.m4a` and `audio/outro.m4a` (if wrapping is desired)
- `.produciesta-hooks/post-generation.sh` (if auto-wrapping is configured)

Not all projects have intro/outro files. If they're missing, skip the wrapping step — Produciesta will still generate the episode audio.
