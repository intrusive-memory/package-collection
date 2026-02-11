# Audio Sprint Tasks: {{project_title}}

**Generated:** {{date}}
**Episodes:** {{episode_count}}
**Cast Members:** {{cast_count}}

## Task Breakdown for Sprint Supervisor

This file provides a task breakdown optimized for execution by the sprint-supervisor agent.

---

## Sprint 1: Validation & Environment Setup

### Task 1.1: Validate Environment Variables

**Priority:** Critical
**Dependencies:** None
**Estimated Duration:** 5 minutes

```bash
# Check ElevenLabs API key
test -n "$ELEVENLABS_API_KEY" && echo "✅ ElevenLabs API key set" || echo "❌ Missing ELEVENLABS_API_KEY"

# Check Apple TTS availability
command -v say >/dev/null && echo "✅ Apple TTS available" || echo "❌ Apple TTS not found"
```

**Success Criteria:**
- ElevenLabs API key is set and valid
- Apple TTS `say` command is available

---

### Task 1.2: Validate Project Structure

**Priority:** Critical
**Dependencies:** None
**Estimated Duration:** 5 minutes

```bash
# Check PROJECT.md exists
test -f PROJECT.md && echo "✅ PROJECT.md found" || echo "❌ PROJECT.md missing"

# Check episodes directory
test -d episodes && echo "✅ episodes/ directory found" || echo "❌ episodes/ directory missing"

# Count fountain files
FOUNTAIN_COUNT=$(find episodes -name "*.fountain" | wc -l)
echo "📄 Found $FOUNTAIN_COUNT Fountain files"
```

**Success Criteria:**
- PROJECT.md exists with YAML front matter
- episodes/ directory exists
- All expected .fountain files are present

---

### Task 1.3: Validate Voice URIs

**Priority:** Critical
**Dependencies:** Task 1.1, Task 1.2
**Estimated Duration:** 10 minutes

Parse PROJECT.md and validate all voice URIs:

1. Extract YAML front matter from PROJECT.md
2. Parse cast list with voice URIs
3. Validate URI format: `PROVIDER://lang/voiceId`
4. Test ElevenLabs API connectivity
5. Verify voice IDs exist in ElevenLabs account

**Success Criteria:**
- All voice URIs follow correct format
- All ElevenLabs voice IDs are valid and accessible
- All Apple TTS voices are available

---

## Sprint 2: Script Analysis

### Task 2.1: Parse Fountain Scripts

**Priority:** High
**Dependencies:** Task 1.2
**Estimated Duration:** 15 minutes

For each episode:

1. Parse Fountain screenplay file
2. Extract dialogue lines with character attribution
3. Count lines and words per character
4. Generate character usage statistics

**Episodes to Process:**

{{episode_tasks}}

**Success Criteria:**
- All episodes parsed successfully
- Dialogue extraction complete
- Character statistics generated

---

### Task 2.2: Generate Cost Estimates

**Priority:** Medium
**Dependencies:** Task 2.1
**Estimated Duration:** 10 minutes

Calculate:

1. Total word count across all episodes
2. Estimated ElevenLabs API cost (characters × $0.18/1000)
3. Estimated audio duration (words ÷ 150 wpm)
4. Identify longest episodes and characters

**Success Criteria:**
- Cost estimate generated
- Duration estimate calculated
- Resource requirements documented

---

## Sprint 3: Audio Generation

### Task 3.1: Generate Audio for Episode 1

**Priority:** High
**Dependencies:** Task 1.3, Task 2.1
**Estimated Duration:** 30-60 minutes

For the first episode:

1. Parse Fountain screenplay
2. Extract all dialogue lines
3. For each line:
   - Lookup character's voice URI
   - Generate audio using ElevenLabs
   - Fallback to Apple TTS if needed
   - Save audio file: `{episode}_line_{num}_{character}.mp3`
4. Log all successes and failures

**Success Criteria:**
- All dialogue lines have audio files
- < 5% fallback to Apple TTS
- Generation log is complete

---

### Task 3.2: Generate Audio for Remaining Episodes

**Priority:** High
**Dependencies:** Task 3.1
**Estimated Duration:** 2-4 hours

Repeat Task 3.1 process for all remaining episodes.

**Optimization:**
- Process episodes in parallel if API rate limits allow
- Implement exponential backoff for rate limiting
- Save progress after each episode
- Enable resume for interrupted runs

**Success Criteria:**
- All {{episode_count}} episodes have generated audio
- Fallback rate < 5%
- All audio files validated

---

## Sprint 4: Post-Processing

### Task 4.1: Assemble Episode Audio

**Priority:** High
**Dependencies:** Task 3.2
**Estimated Duration:** 30 minutes

For each episode:

1. Load all line audio files in order
2. Insert 0.5-1.0 second silence between lines
3. Concatenate into single episode file
4. Normalize audio levels (-16 LUFS)

**Success Criteria:**
- All episodes assembled into single files
- Audio levels normalized
- No clipping or distortion

---

### Task 4.2: Apply Audio Effects & Mixing

**Priority:** Medium
**Dependencies:** Task 4.1
**Estimated Duration:** 45 minutes

For each episode:

1. Apply EQ for voice clarity (high-pass at 80 Hz)
2. Apply gentle compression (2:1 ratio, -20 dB threshold)
3. Apply limiting to prevent clipping (-1 dB ceiling)
4. Export as MP3 (192 kbps, 44.1 kHz)

**Success Criteria:**
- Audio effects applied consistently
- Final episodes exported as MP3
- Quality meets podcast standards

---

### Task 4.3: Generate Episode Metadata

**Priority:** Medium
**Dependencies:** Task 4.2
**Estimated Duration:** 15 minutes

For each episode:

1. Extract title from Fountain file
2. Calculate audio duration
3. Generate description/summary
4. Create episode metadata JSON
5. Generate RSS feed item

**Success Criteria:**
- All episodes have metadata
- RSS feed items created
- Podcast manifest updated

---

## Sprint 5: Quality Assurance

### Task 5.1: Audio Quality Validation

**Priority:** High
**Dependencies:** Task 4.2
**Estimated Duration:** 30 minutes

For each episode:

1. Verify file integrity (can be opened/played)
2. Check audio duration matches estimate (±10%)
3. Scan for clipping or distortion
4. Spot-check 3-5 random dialogue lines

**Success Criteria:**
- All episodes pass quality checks
- No clipping or distortion detected
- Duration matches estimates

---

### Task 5.2: Content Validation

**Priority:** High
**Dependencies:** Task 4.1
**Estimated Duration:** 20 minutes

For each episode:

1. Verify all dialogue lines are present
2. Check character voice consistency
3. Validate episode ordering
4. Review metadata accuracy

**Success Criteria:**
- All dialogue present and correct
- Voice consistency maintained
- Metadata accurate

---

## Sprint 6: Delivery & Publishing

### Task 6.1: Organize Output Files

**Priority:** Medium
**Dependencies:** Task 5.2
**Estimated Duration:** 10 minutes

1. Move completed episodes to `output/episodes/`
2. Archive intermediate files to `archive/`
3. Clean up temporary audio files
4. Generate file manifest

**Success Criteria:**
- Files organized in output directory
- Intermediate files archived
- Temp files cleaned up

---

### Task 6.2: Generate RSS Feed

**Priority:** High
**Dependencies:** Task 4.3, Task 6.1
**Estimated Duration:** 15 minutes

1. Generate RSS feed XML with all episodes
2. Include episode metadata and enclosures
3. Validate feed with podcast validators
4. Test feed in podcast client

**Success Criteria:**
- RSS feed generated and valid
- All episodes included
- Feed validates successfully

---

### Task 6.3: Upload & Publish

**Priority:** High
**Dependencies:** Task 6.2
**Estimated Duration:** 20 minutes

1. Upload episodes to podcast hosting
2. Upload RSS feed
3. Verify episodes are accessible
4. Update podcast directories (if applicable)

**Success Criteria:**
- All episodes uploaded successfully
- RSS feed accessible
- Episodes playable in podcast clients

---

## Summary

**Total Tasks:** 15
**Estimated Total Duration:** 5-8 hours
**Critical Path:** Tasks 1.1 → 1.2 → 1.3 → 2.1 → 3.1 → 3.2 → 4.1 → 4.2 → 5.1 → 5.2 → 6.2 → 6.3

**Risk Factors:**
- ElevenLabs API rate limiting may extend Task 3.2
- Voice quality issues may require re-generation
- Audio processing may reveal unexpected issues

**Rollback Plan:**
- Archive intermediate files at each sprint
- Enable resume capability for interrupted runs
- Maintain generation logs for debugging
