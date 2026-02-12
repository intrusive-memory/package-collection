# Audio Generation Plan: {{project_title}}

**Generated:** {{date}}
**Episodes:** {{episode_count}}
**Cast Members:** {{cast_count}}

## Overview

This plan outlines the process for generating audio for the {{project_title}} podcast using character voices from ElevenLabs and Apple TTS fallbacks.

## Cast & Voice Mapping

{{cast_table}}

## Phase 1: Validation & Setup

### 1.1 Environment Validation

- [ ] Verify ElevenLabs API key is set (`ELEVENLABS_API_KEY`)
- [ ] Confirm Apple TTS is available (macOS `say` command)
- [ ] Check SwiftHablare installation and configuration
- [ ] Verify SwiftOnce ElevenLabs client is configured

### 1.2 Voice URI Validation

- [ ] Parse all voice URIs from PROJECT.md cast list
- [ ] Validate URI format: `PROVIDER://lang/voiceId`
- [ ] Test ElevenLabs API connectivity
- [ ] Verify all ElevenLabs voice IDs exist in account
- [ ] Test Apple TTS fallback voices

### 1.3 Project Structure Check

- [ ] Confirm PROJECT.md exists with valid YAML front matter
- [ ] Verify all episode .fountain files exist in `episodes/`
- [ ] Check that all characters in scripts have voice assignments
- [ ] Validate Fountain screenplay syntax

## Phase 2: Analysis & Planning

### 2.1 Script Analysis

For each episode:

- [ ] Parse Fountain screenplay
- [ ] Extract dialogue by character
- [ ] Count lines and words per character
- [ ] Identify speaking characters

### 2.2 Cost & Duration Estimates

- [ ] Calculate total word count across all episodes
- [ ] Estimate ElevenLabs API cost (characters × rate)
- [ ] Estimate total audio duration (words ÷ speaking rate)
- [ ] Identify longest episodes and characters

### 2.3 Resource Planning

- [ ] Allocate disk space for intermediate audio files
- [ ] Plan API rate limiting strategy
- [ ] Schedule generation time windows
- [ ] Set up error logging and monitoring

## Phase 3: Audio Generation

### 3.1 Episode Processing Order

{{episode_tasks}}

### 3.2 Voice Synthesis Pipeline

For each dialogue line:

1. **Extract** line text and character attribution
2. **Lookup** character's voice URI from cast mapping
3. **Generate** audio using ElevenLabs (primary)
   - Apply voice settings (stability, similarity_boost)
   - Handle rate limiting with exponential backoff
   - Retry on transient failures
4. **Fallback** to Apple TTS if ElevenLabs fails
5. **Save** audio file with naming: `{episode}_{line_num}_{character}.mp3`
6. **Log** success/failure with timestamps

### 3.3 Error Handling & Recovery

- [ ] Log all failed lines to `generation_errors.log`
- [ ] Save generation progress after each line
- [ ] Implement resume capability for interrupted runs
- [ ] Create fallback audio for all failed lines

## Phase 4: Post-Processing

### 4.1 Audio Assembly

For each episode:

- [ ] Load all line audio files in screenplay order
- [ ] Insert silence/pauses between lines (0.5-1.0 seconds)
- [ ] Concatenate into single episode audio file
- [ ] Normalize audio levels (-16 LUFS target)

### 4.2 Mixing & Effects

- [ ] Apply EQ to enhance voice clarity
- [ ] Apply gentle compression (2:1 ratio)
- [ ] Apply limiting to prevent clipping (-1 dB ceiling)
- [ ] Add intro/outro music (if applicable)

### 4.3 Export & Encoding

- [ ] Export as MP3 (192 kbps, 44.1 kHz)
- [ ] Export as AAC (128 kbps, 44.1 kHz) for podcast feeds
- [ ] Generate waveform visualization
- [ ] Create audio fingerprint for deduplication

## Phase 5: Quality Assurance

### 5.1 Audio Quality Checks

For each episode:

- [ ] Verify audio duration matches estimate (±10%)
- [ ] Check for clipping or distortion
- [ ] Validate audio file integrity (can be opened/played)
- [ ] Spot-check 3-5 random dialogue lines for quality

### 5.2 Content Validation

- [ ] Verify all dialogue lines are present
- [ ] Check character voice consistency
- [ ] Validate episode ordering and numbering
- [ ] Review metadata accuracy

## Phase 6: Delivery & Distribution

### 6.1 File Organization

- [ ] Move completed episodes to `output/episodes/`
- [ ] Archive intermediate files to `archive/`
- [ ] Clean up temporary audio files
- [ ] Generate episode manifest JSON

### 6.2 Metadata & Feed

- [ ] Create episode metadata (title, description, duration)
- [ ] Generate RSS feed items
- [ ] Update podcast manifest with new episodes
- [ ] Create show notes and transcripts

### 6.3 Publishing

- [ ] Upload episodes to podcast hosting
- [ ] Update RSS feed XML
- [ ] Validate feed with podcast validators
- [ ] Submit to podcast directories (if new show)
- [ ] Notify subscribers of new episodes

## Tools & Dependencies

### Required

- **SwiftHablare** (`~/Projects/SwiftHablare`) - Voice generation library
- **SwiftOnce** (`~/Projects/SwiftOnce`) - ElevenLabs API client
- **ffmpeg** - Audio processing and conversion
- **Python 3.8+** with `pyyaml` - Script parsing

### Optional

- **sox** - Additional audio effects
- **Audacity** - Manual audio editing
- **Podcast validators** - RSS feed validation

## Success Criteria

- [ ] All {{episode_count}} episodes have generated audio
- [ ] All dialogue lines are present and in correct order
- [ ] Audio quality meets podcast standards (no clipping, clear voices)
- [ ] ElevenLabs fallback success rate < 5%
- [ ] Episode durations within expected ranges
- [ ] RSS feed validates successfully
- [ ] All episodes uploaded and accessible

## Rollback Plan

If generation fails or quality is poor:

1. Review `generation_errors.log` for failure patterns
2. Re-generate failed episodes with adjusted voice settings
3. Use Apple TTS fallback for problematic characters
4. Manually edit audio in Audacity if needed
5. Restore from `archive/` if needed

## Timeline Estimate

Based on {{episode_count}} episodes:

- **Validation & Setup:** 30-60 minutes
- **Analysis:** 15-30 minutes
- **Audio Generation:** 2-4 hours (depends on API rate limits)
- **Post-Processing:** 1-2 hours
- **QA & Publishing:** 30-60 minutes

**Total:** 4-8 hours
