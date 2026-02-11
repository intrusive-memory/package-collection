---
name: podcast-audio-plan
description: Generate comprehensive sprint supervisor plans for podcast audio generation from Fountain screenplays. Use when asked to "create audio plan", "generate podcast plan", "plan audio generation", or when working with podcast projects that have PROJECT.md (with cast/voice URIs) and episodes/*.fountain files. Creates AUDIO_GENERATION_PLAN.md (detailed workflow) and AUDIO_SPRINT_TASKS.md (task breakdown) for sprint-supervisor execution.
---

# Podcast Audio Plan Generator

Generate comprehensive sprint supervisor plans for podcast audio generation from Fountain screenplay files.

## When to Use This Skill

Use this skill when:

- User asks to create an audio generation plan for a podcast
- Project has `PROJECT.md` with YAML front matter containing cast/voice URIs
- Project has episode scripts in Fountain format (`episodes/*.fountain`)
- User wants to prepare for audio generation sprint with sprint-supervisor
- User asks to "plan podcast audio", "generate audio plan", or similar

## What This Skill Does

Analyzes the podcast project structure and generates two plan files:

1. **AUDIO_GENERATION_PLAN.md** - Comprehensive step-by-step workflow covering:
   - Environment validation and setup
   - Voice URI validation
   - Script analysis and cost estimates
   - Audio generation pipeline
   - Post-processing and mixing
   - Quality assurance checks
   - Publishing and distribution

2. **AUDIO_SPRINT_TASKS.md** - Task breakdown optimized for sprint-supervisor:
   - Granular tasks organized by sprint
   - Dependencies and priorities
   - Success criteria for each task
   - Estimated durations
   - Rollback procedures

## Prerequisites

The podcast project must have:

- `PROJECT.md` with YAML front matter containing:
  - `cast` list with character names
  - Voice URIs in format: `PROVIDER://[lang/]voiceId` (lang is optional, defaults to "en")
  - Both ElevenLabs (primary) and Apple TTS (fallback) voices
- `episodes/` directory with `.fountain` screenplay files
- Standard Fountain format for all episode scripts

## Usage

### Step 1: Analyze Project Structure

First, analyze the PROJECT.md file to extract cast and voice information:

```bash
python3 scripts/analyze_project.py PROJECT.md > /tmp/project_data.json
```

This extracts:
- Project title
- Cast members with character names
- ElevenLabs voice URIs
- Apple TTS fallback voice URIs

### Step 2: Analyze Episode Scripts

Parse all Fountain files to extract dialogue and character usage:

```bash
for episode in episodes/*.fountain; do
  python3 scripts/parse_fountain.py "$episode" >> /tmp/episodes_data.json
done
```

This extracts:
- Characters present in each episode
- Dialogue line counts per character
- Word counts per character
- Episode-specific statistics

### Step 3: Generate Plan Files

Generate both plan files using the templates and collected data:

```bash
python3 scripts/generate_plans.py \
  /tmp/project_data.json \
  /tmp/episodes_data.json \
  assets/ \
  .
```

This creates:
- `AUDIO_GENERATION_PLAN.md` in the project root
- `AUDIO_SPRINT_TASKS.md` in the project root

Both files are ready for sprint-supervisor to discover and execute.

### Step 4: Update PROJECT.md with Notes (Important)

Check if PROJECT.md contains helpful production notes after the YAML front matter. If not, add them:

```bash
# Check if notes section exists
if ! grep -q "## Production Notes" PROJECT.md; then
  # Add notes section (see "Updating PROJECT.md with Helpful Notes" section below)
  echo "Adding production notes to PROJECT.md..."
fi
```

Include information about:
- Voice URI format explanation
- Voice casting decisions
- Key project files
- Related projects and dependencies

This documentation is invaluable for future reference and for anyone else working on the project.

### Step 5: Review & Customize (Optional)

Review the generated files and customize if needed:

- Adjust time estimates based on project specifics
- Add custom validation steps
- Modify post-processing pipeline
- Update success criteria

### Step 6: Execute with Sprint Supervisor

The generated files are designed for sprint-supervisor execution:

```bash
# User would run:
/sprint-supervisor
```

The sprint-supervisor will automatically discover and execute the tasks in AUDIO_SPRINT_TASKS.md.

## Voice URI Format

Voice URIs must follow this format (see `references/voice-uri-format.md` for details):

```
PROVIDER://[lang/]voiceId
```

The `lang` parameter is optional and defaults to `en` if not specified.

Examples:
- ElevenLabs with lang: `elevenlabs://en/Ya2J5uIa5Pq14DNPsbC1`
- ElevenLabs without lang: `elevenlabs://Ya2J5uIa5Pq14DNPsbC1` (defaults to "en")
- Apple TTS: `apple://en/com.apple.voice.premium.en-US.Ava`

**Invalid formats** (do not use):
- `hablare://provider/voiceId?lang=xx`
- `provider://voiceId?lang=xx`

## Audio Workflow Overview

For detailed workflow documentation, see `references/audio-workflow.md`. High-level phases:

1. **Validation** - Environment, voice URIs, project structure
2. **Analysis** - Parse scripts, estimate costs and duration
3. **Generation** - Synthesize audio for each dialogue line
4. **Post-Processing** - Assemble, mix, and export episodes
5. **Delivery** - Organize files, generate RSS feed, publish

## Tools & Dependencies

### Required

- **Python 3.8+** with `pyyaml` for parsing
- **SwiftHablare** - Voice generation library (ElevenLabs + Apple TTS)
- **SwiftOnce** - ElevenLabs API client
- **ffmpeg** - Audio processing

### Optional

- **sox** - Additional audio effects
- **Audacity** - Manual editing if needed

## Troubleshooting

### Script Parse Errors

If `analyze_project.py` fails to parse PROJECT.md:

- Verify YAML front matter is between `---` delimiters
- Check YAML syntax (indentation, colons, quotes)
- Ensure `cast` list exists with proper structure

### Voice URI Validation Failures

If voice URIs are invalid:

- Check format: `PROVIDER://[lang/]voiceId`
- Verify ElevenLabs voice IDs in your account
- Test Apple TTS voices with `say -v "VoiceName" "test"`

### Missing Episodes

If Fountain files aren't found:

- Verify files are in `episodes/` directory
- Check file extension is `.fountain` (not `.txt`)
- Ensure files use standard Fountain format

## Output Files

### AUDIO_GENERATION_PLAN.md

Comprehensive plan with:
- Cast & voice mapping table
- Phase-by-phase workflow (6 phases)
- Checklists for each step
- Tool requirements
- Success criteria
- Timeline estimates

### AUDIO_SPRINT_TASKS.md

Task breakdown with:
- 15 granular tasks organized by sprint
- Dependencies and priorities
- Bash commands for validation tasks
- Success criteria per task
- Estimated durations
- Critical path analysis

## Updating PROJECT.md with Helpful Notes

**IMPORTANT:** After generating the plans, always check if PROJECT.md contains helpful production notes in its non-front-matter content. If these notes are not present, add them to help future users understand the project structure and workflow.

The notes section should be added after the YAML front matter (after the closing `---`) and should include:

1. **Voice URI Format** - Explanation of the URI scheme used
2. **Voice Casting** - Summary of how voices were selected
3. **Key Files** - List of important project files and their purposes
4. **Related Projects** - Links to dependencies (SwiftHablare, SwiftOnce, etc.)
5. **Production Notes** - Any project-specific guidance for audio generation

### Example Notes Section to Add:

```markdown
## Production Notes

### Voice URI Format
Voice URIs follow the format: `PROVIDER://lang/voiceId`
- Example: `elevenlabs://en/C1npRmjB19a6yNkEucvx`
- The `lang` parameter is optional and defaults to `en`
- See SwiftOnce's `ElevenLabsDefaults.swift` for the canonical implementation

### Voice Casting
All [N] characters have been assigned:
- Primary voice: ElevenLabs (American accent)
- Fallback voice: Apple TTS
- [Character] and [Character] share the same voice (same character at different story points)

### Key Files
- `PROJECT.md` - Project configuration with cast list (YAML front matter)
- `episodes/*.fountain` - Fountain screenplays with character dialogue
- `AUDIO_GENERATION_PLAN.md` - Comprehensive production workflow
- `AUDIO_SPRINT_TASKS.md` - Granular task breakdown for execution

### Related Projects
- **SwiftHablare** (`~/Projects/SwiftHablare`) - Voice generation library
- **SwiftOnce** (`~/Projects/SwiftOnce`) - ElevenLabs API client
- **SwiftProyecto** - PROJECT.md parsing and CastMember model
```

**When to Add Notes:**
- If PROJECT.md only contains YAML front matter with no body content
- If the existing body content doesn't include production guidance
- If voice URI format or casting information is not documented

**When NOT to Add Notes:**
- If comprehensive notes already exist
- If the user explicitly asks not to modify PROJECT.md
- If the notes would duplicate information already present

The notes provide valuable context for anyone revisiting the project or using it as a reference for future podcast projects.

## Example Project Structure

```
podcast-lazarillo/
├── PROJECT.md              # Cast list with voice URIs (YAML front matter)
├── episodes/
│   ├── tratado-1.fountain
│   ├── tratado-2.fountain
│   └── ...
├── AUDIO_GENERATION_PLAN.md   # Generated by this skill
└── AUDIO_SPRINT_TASKS.md      # Generated by this skill
```

## Related Projects

- **SwiftHablare** (`~/Projects/SwiftHablare`) - Voice generation
- **SwiftOnce** (`~/Projects/SwiftOnce`) - ElevenLabs API client
- **SwiftProyecto** - PROJECT.md parsing

## Notes

- Script execution requires `chmod +x` on scripts
- Large projects may need API rate limiting adjustments
- Generation costs depend on total dialogue word count
- Plan templates use simple `{{variable}}` substitution
