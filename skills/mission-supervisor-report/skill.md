# mission-supervisor-report

Generate a voiced mission debrief video composition for a podcast episode. Reads an EXECUTION_PLAN.md, scripts "The General" character narrating mission status, generates voice and audio with echada/diga, builds Motion title templates and compositions for Final Cut Pro.

## Arguments

```
/mission-supervisor-report <execution-plan-path> <podcast-path> <episode-number>
```

- `execution-plan-path` — Path to EXECUTION_PLAN.md (YAML frontmatter with `feature_name`, `iteration`, `mission_branch`)
- `podcast-path` — Path to podcast project directory (must have PROJECT.md)
- `episode-number` — Episode number (e.g., 1)

## Workflow

### Phase 1: Parse Mission Data

1. Read EXECUTION_PLAN.md frontmatter for operation name, branch, iteration
2. Parse sortie summary table for all sorties and their status
3. Determine sortie status from `- [x]` / `- [ ]` exit criteria checkboxes
4. If an ITERATION harvest document exists (e.g., `ITERATION_0_HARVEST.md` in the podcast path), parse key discoveries and process failures

### Phase 2: Script The General's Report

1. Load the character definition (see GENERAL_CHARACTER section below)
2. Generate chapter scripts based on mission data:
   - Opening (General introduces himself)
   - Mission Briefing (objective from EXECUTION_PLAN.md)
   - For each completed iteration: The Mess, Key Discoveries, Process Failures, What Worked, Verdict
   - For the current iteration: Requirements overview, Sortie breakdown, Current Status
   - Closing (reflection)
3. Write individual chapter text files to `<output-dir>/scripts/CH##-<name>.txt`
4. Write the full script to `<output-dir>/GENERAL_SCRIPT.md`

### Phase 3: Generate Voice

1. Check if THE_GENERAL.vox exists in `<output-dir>/voices/`
2. If not, create a PROJECT.md with the General's voice description
3. Run `echada cast --project PROJECT.md --character THE_GENERAL --tts-model 1.7b`
4. Verify .vox file was created

### Phase 4: Generate Audio

1. For each chapter script file:
   ```bash
   diga -v <vox-path> -f <script-file> -o <audio-dir>/CH##-<name>.m4a --file-format m4a
   ```
2. Run sequentially (GPU contention with parallel runs)
3. **Cooldown between generations**: After each chapter, sleep for 10% of the generated audio's duration. Use `afinfo` to read the duration:
   ```bash
   dur=$(afinfo "$outfile" | grep "estimated duration" | awk '{print $3}')
   cooldown=$(echo "$dur * 0.10" | bc)
   sleep "$cooldown"
   ```
   This prevents GPU thermal throttling across sequential generations.
4. Verify all .m4a files were generated

### Phase 5: Build FCP Assets

1. **Title template** (.moti) — Operation name title card with sortie status grid
   - Output to: `~/Movies/Motion Templates.localized/Titles.localized/casting-software-spells/EP##-M##-<Operation-Name>/`
2. **Composition** (.motn) — Full episode composition with chapter markers
   - Output to: `~/Movies/Motion Templates.localized/Compositions.localized/casting-software-spells/EP##-M##-<Operation-Name>/`
   - Audio files copied to `Media/` subfolder
   - Chapter markers at each phase
3. **Thumbnails** — Generated with AppKit (large.png 320x180, small.png 96x96)

### Phase 6: Generate Swift Script

Update or create `~/Projects/SwiftSecuencia/Scripts/generate-motion-titles.swift` with the latest chapter data so the composition can be regenerated.

## Output Directory Structure

```
/Volumes/brick/casting-software-spells/EP##/
├── PROJECT.md                 # Cast metadata
├── GENERAL_CHARACTER.md       # Character definition
├── GENERAL_SCRIPT.md          # Full script with all chapters
├── scripts/
│   ├── CH01-opening.txt
│   ├── CH02-mission-briefing.txt
│   └── ... (one per chapter)
├── audio/
│   ├── CH01-opening.m4a
│   ├── CH02-mission-briefing.m4a
│   └── ... (one per chapter)
└── voices/
    └── THE_GENERAL.vox
```

## THE GENERAL — Character Definition

### Voice Prompt (for echada)
```
Deep gravelly American male baritone, late fifties, military bearing, authoritative and unhurried with dry sardonic wit, slight rasp, sounds like a veteran sergeant giving a debrief after a long campaign, measured pacing, lets pauses do work, occasional warmth cracking through the gruff exterior
```

### Personality
- **Battle-wizened**: Has seen every kind of mission failure. Nothing surprises him.
- **Sarcastic**: Deploys deadpan humor as a coping mechanism and teaching tool.
- **Honest**: Will tell you your plan was garbage, but also tell you exactly what you learned from it.
- **Pop culture**: References war movies, sci-fi, and 80s action films as genuine cognitive shortcuts.
- **Warm underneath**: Cares about the mission AND the people. Sarcasm is armor, not contempt.

### Inherited from mission-supervisor personality
- "Pfft... child!"
- "Agents don't take a dump without a plan"
- "Sit tight, soldier"
- "Even commandos follow the chain of command"
- "This is the way" (when patterns work)
- "Game over, man!" (for FATAL states)

### Pop Culture Pool
- Apocalypse Now, A Few Good Men, Aliens, Blade Runner, Star Wars, The Mandalorian

### Script Generation Rules
1. The General speaks in first person, addressing the audience directly
2. Technical details are accurate but delivered conversationally
3. Each chapter opens with a clear statement of what's being covered
4. Sarcasm is used to highlight failures, warmth for what worked
5. Pop culture references emerge naturally, not forced
6. Closing always reflects on methodology, not just results
7. The General quotes directly from harvest documents when citing specific findings
8. **TTS-friendly writing** — Scripts must be optimized for neural text-to-speech:
   - Spell out acronyms: "FCPXML" → "Final Cut Pro XML", "DTD" → "document type definition", "UUID" → "unique ID", "CI" → "CI" or "continuous integration", "CLI" → "command line"
   - Expand compound identifiers: "XMLDocument" → "XML Document", "ResourceMap" → "Resource Map", "FileAssetProvider" → "File Asset Provider", "SwiftData" → "Swift Data"
   - Write numbers as words when spoken: "R-1, R-2" → "R one, R two", "24,000" → "twenty-four thousand", "Lines 143-193" → "Lines one forty-three through one ninety-three"
   - Avoid stacked punctuation: "Regex. On. XML." → "Regular expressions, on XML."
   - Use commas instead of em dashes for natural speech pauses
   - CamelCase type names should be space-separated: "PipelineNeo.Timeline" → "Pipeline Neo dot Timeline"
   - Technical terms that sound natural when spoken can stay: "metadata", "adapter", "exporter", "timecodes"

## Chapter Template

The standard chapter structure adapts based on mission data:

### For Completed Iterations (The Mess)
- Opening, Mission Briefing, The Mess overview
- One chapter per major discovery (from harvest document)
- Process failures summary
- What worked summary
- Verdict (Rodillo Liso — roll it flat)

### For Current Iteration (The Clean Pass)
- Clean slate overview
- Sortie 0 (research/exploration) highlight
- Sorties 1-N summary
- Current status with sortie grid
- Closing reflection

## Dependencies

**CRITICAL: Use locally-built binaries, NOT homebrew installs.**

- `echada` — Voice generation CLI
  - Source: `~/Projects/SwiftEchada/`
  - Binary: `~/Projects/SwiftEchada/bin/echada`
  - Build: `cd ~/Projects/SwiftEchada && make install`
- `diga` — Text-to-speech CLI
  - Source: `~/Projects/SwiftVoxAlta/`
  - Binary: `~/Projects/SwiftVoxAlta/bin/diga`
  - Build: `cd ~/Projects/SwiftVoxAlta && make install`
- Swift runtime — For generate-motion-titles.swift
- /Volumes/brick — External storage for media assets
- Apple Motion templates directory — ~/Movies/Motion Templates.localized/

**Before running**: Always rebuild from source to ensure latest binaries:
```bash
cd ~/Projects/SwiftEchada && make install
cd ~/Projects/SwiftVoxAlta && make install
```

## Reuse

This skill is designed for repeated use across episodes. Each episode gets:
- A new operation name from its EXECUTION_PLAN.md
- Fresh chapter scripts reflecting that episode's mission data
- Reuses THE_GENERAL.vox (voice only generated once)
- Versioned folder names: EP##-M##-<Operation-Name>
