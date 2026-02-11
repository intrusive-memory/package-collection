# Audio Generation Workflow

## Overview

The audio generation workflow transforms Fountain screenplay files into podcast audio using character voices from ElevenLabs and Apple TTS.

## Phases

### Phase 1: Validation

1. **Environment Check**
   - Verify ElevenLabs API key is set
   - Confirm Apple TTS is available
   - Check SwiftHablare is installed and configured

2. **Voice URI Validation**
   - Parse all voice URIs from PROJECT.md
   - Validate URI format (PROVIDER://lang/voiceId)
   - Test connectivity to ElevenLabs API
   - Verify voice IDs exist in ElevenLabs account

3. **Project Structure Check**
   - Confirm PROJECT.md exists with YAML front matter
   - Verify episodes/*.fountain files exist
   - Check cast list completeness (all characters have voices)

### Phase 2: Analysis

1. **Parse PROJECT.md**
   - Extract YAML front matter
   - Build character-to-voice mapping
   - Identify primary (ElevenLabs) and fallback (Apple) voices

2. **Parse Fountain Scripts**
   - Extract dialogue by character for each episode
   - Count lines and words per character
   - Identify speaking characters per episode

3. **Generate Estimates**
   - Estimate audio duration based on word count
   - Calculate API cost (ElevenLabs character usage)
   - Identify longest episodes and characters

### Phase 3: Audio Generation

1. **Per-Episode Processing**
   - Parse Fountain screenplay
   - Extract dialogue lines with character attribution
   - Generate audio for each line using character's voice
   - Save individual line audio files

2. **Voice Synthesis**
   - Use ElevenLabs for primary voice generation
   - Fall back to Apple TTS if ElevenLabs fails
   - Apply voice settings (stability, similarity_boost, etc.)
   - Handle rate limiting and retries

3. **Error Handling**
   - Log failed lines with character and text
   - Save partially completed episodes
   - Provide resume capability for interrupted generations

### Phase 4: Post-Processing

1. **Audio Assembly**
   - Concatenate line audio files in screenplay order
   - Add silence/pauses between lines
   - Normalize audio levels

2. **Mixing & Export**
   - Apply audio effects (EQ, compression, limiting)
   - Export final episode audio (MP3/AAC)
   - Generate waveform/spectrogram visualizations

3. **Quality Checks**
   - Verify audio duration matches estimate
   - Check for clipping or distortion
   - Validate audio file integrity

### Phase 5: Delivery

1. **File Organization**
   - Move completed episodes to output directory
   - Archive intermediate files
   - Clean up temporary audio files

2. **Metadata Generation**
   - Create episode metadata JSON
   - Generate RSS feed items
   - Update podcast manifest

3. **Distribution**
   - Upload to podcast hosting
   - Update RSS feed
   - Notify subscribers

## Tools & Dependencies

- **SwiftHablare**: Voice generation library
- **SwiftOnce**: ElevenLabs API client
- **SwiftProyecto**: PROJECT.md parsing
- **ffmpeg**: Audio processing and conversion
- **sox**: Audio effects and manipulation

## Configuration Files

- `PROJECT.md`: Cast list with voice URIs (YAML front matter)
- `episodes/*.fountain`: Fountain screenplay files
- `.env`: API keys and environment variables
- `AUDIO_GENERATION_PLAN.md`: Generated plan (this skill creates it)
- `AUDIO_SPRINT_TASKS.md`: Task breakdown for sprint-supervisor
