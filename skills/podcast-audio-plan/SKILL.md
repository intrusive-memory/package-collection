---
type: skill
name: podcast-audio-plan
description: Generate audio and transcripts for podcast episodes from Fountain screenplays using Produciesta CLI. When asked to "generate podcast audio", "create audio plan", "cast voices", "prepare transcripts", or working with podcast projects that have episodes/*.fountain files, this skill analyzes characters, assigns voices, writes the CAST.md cast roster (legacy PROJECT.md cast: on older echada binaries), generates audio, and prepares transcripts for web deployment.
---

# Podcast Audio Generation with Produciesta

Generate professional podcast audio from Fountain screenplay files using Claude-assisted voice casting and Produciesta CLI generation.

## When to Use This Skill

Use this skill when:

- User asks to generate audio for a podcast project
- Project has episode scripts in Fountain format (`episodes/*.fountain`)
- User wants to create or update a cast list in CAST.md (or the legacy
  `cast:` block in PROJECT.md when working with an older echada)
- User asks to "cast voices", "assign voices", "plan audio generation"
- User wants to generate audio from screenplays

## What This Skill Does

This skill provides a **Claude-assisted workflow** for podcast audio generation and web publishing:

1. **Analyze Fountain files** to extract character list
2. **Query available voices** from Apple TTS or ElevenLabs
3. **Match characters to voices** based on character traits and voice characteristics
4. **Write PROJECT.md** (project config) and **CAST.md** (the cast roster —
   see "Cast source" below; legacy binaries keep cast in PROJECT.md)
5. **Generate audio** using Produciesta CLI
6. **Commit audio to Git LFS** and verify CDN availability
7. **Copy transcripts** to website episodes directory
8. **Update website page** with CDN links, metadata, and RSS feed
9. **Validate deployment** (subscribe links, playback, transcripts)
10. **Deploy to production** via git push

## Prerequisites

### Required Tools

- **Produciesta CLI** at `~/Projects/Produciesta/produciesta-cli/`
- **Swift 6.2+** (for building Produciesta if needed)
- **Xcode 16+** (macOS only)
- **Apple TTS** (built-in macOS) or **ElevenLabs API key**

### Project Structure

**Podcast Source Repository (Produciesta project):**
```
~/podcast-daily-dao/
├── PROJECT.md              # Project configuration (Claude creates this)
├── CAST.md                 # Cast roster (capable echada; legacy binaries keep cast: in PROJECT.md)
├── episodes/               # Fountain screenplay files (source)
│   ├── chapter-01.fountain
│   ├── chapter-02.fountain
│   └── ...
├── audio/                  # Generated audio files (Git LFS)
│   ├── chapter-01.m4a
│   ├── chapter-02.m4a
│   └── ...
└── .gitattributes          # LFS configuration for *.m4a files
```

**Website Repository (intrusive-memory.github.com):**
```
~/Projects/intrusive-memory.github.com/podcasts/daily-dao/
├── index.html              # Podcast player page
├── feed.xml                # RSS feed
├── podcast-artwork.jpg     # Cover art (3000x3000)
├── favicon.ico
├── apple-touch-icon.png
├── episodes/               # Transcripts (copied from source)
│   ├── chapter-01.fountain
│   ├── chapter-02.fountain
│   └── ...
└── audio/                  # Placeholder or symlink (audio served from CDN)
```

**Critical Separation:**
- **Source repo**: Where audio is generated and stored (Git LFS)
- **Website repo**: Where podcast page lives and references CDN URLs
- **CDN**: Cloudflare R2 serves audio via `https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/`

## Cast source: CAST.md, with a probed PROJECT.md fallback

The cast roster lives in a standalone **`CAST.md`** (`type: cast` front
matter plus a `cast:` array — schema owned by SwiftReparto) that always sits
in the project directory beside `PROJECT.md`. `PROJECT.md` keeps only project
configuration (`title`, `episodesDir`, `filePattern`, `tts`, …). Older
`echada` binaries (≤ 0.17.0 — the Homebrew build, and the signed binary
embedded in shipped `Produciesta.app` bundles) predate CAST.md and still
read/write the legacy `cast:` block in `PROJECT.md`'s front matter.

**Always probe the installed binary before deciding where cast lives** —
check the major version, falling back to the verbs in the `SUBCOMMANDS:`
section of `echada --help` (`migrate` and `sample` mean 3.0). Do NOT rely on
the `verify` verb: only echada 1.x had it (2.0.0 removed it). Don't probe
with `echada <verb> --help` either; ArgumentParser prints root help and
exits 0 for any `--help`.

```bash
MAJOR="$(echada --version 2>/dev/null | head -n1 | grep -oE '^[0-9]+' || echo 0)"
VERBS="$(echada --help 2>/dev/null | awk '/^SUBCOMMANDS:/{f=1;next} f&&/^[^[:space:]]/{f=0} f&&NF{print $1}')"
V3=0; { [ "$MAJOR" -ge 3 ] || grep -qxE 'migrate|sample' <<<"$VERBS"; } && V3=1
if [ "$MAJOR" -ge 1 ] || [ "$V3" -eq 1 ]; then
  echo "CAST.md-capable (echada >= 1.0.0): cast roster is CAST.md"
  # echada 1.x seeds CAST.md from a legacy PROJECT.md cast: block and leaves
  # PROJECT.md alone.
  # echada >= 2.0.0: any generate stage MIGRATES a legacy project — roster
  # -> CAST.md, original -> PROJECT.md.bak, cast: block removed,
  # schemaVersion: 5. A Produciesta that still reads cast from PROJECT.md
  # then shows every character unassigned.
  # echada >= 3.0.0 ($V3): no character discovery (use `personaje
  # cast-discover`); .vox files live in character records (see "Where .vox
  # files live" below).
  # `--cast <filename>` renames the roster file (bare filename only).
else
  echo "legacy echada (< 1.0.0): cast lives in PROJECT.md's cast: front matter"
  # No CAST.md surface. Read/write the cast: block in PROJECT.md, exactly as
  # this skill's legacy examples show.
fi
```

Migration helpers: echada 1.x had explicit `echada verify cast` (report-only)
and `echada prune cast` (removes the legacy block once verify passes). echada
2.0.0 removed both; migration happens automatically, with `PROJECT.md.bak` as
the undo.

### Where .vox files live

**The member's `voices.voxalta` pointer in CAST.md is the authority** —
always read it, never assume a folder. Paths are relative to CAST.md's
directory and may contain spaces, so quote them.

- **echada ≥ 3.0.0:** beside the member's `manifest:`
  (`<bundle>/voice/<NAME>.vox`), else the existing `voices.voxalta` path
  (regenerated in place — never moved silently), else
  `characters/<NAME>.dossier/voice/<NAME>.vox`. The file name is the exact
  canonical name with spaces kept: `THE PRACTITIONER.vox`, not
  `THE_PRACTITIONER.vox`. A non-canonical name fails for that member; fix
  CAST.md with `reparto canonicalize`.
- **echada ≤ 2.x:** `<project>/voices/<NAME>.vox` (spaces → underscores).

Projects that haven't migrated keep working: their `voices/X.vox` pointers
still resolve. To move them into the character records:

```bash
echada migrate voices --project PROJECT.md           # dry run: the plan, plus unclaimed voices/ files
echada migrate voices --project PROJECT.md --apply   # copy + SHA-256 check, rewrite pointers, remove old files
```

`echada sample "<CHARACTER>"` (3.0) writes a playable
`<character dir>/voice/sample-neutral.m4a` from the `.vox`'s embedded sample;
`--variant <name>`, `--all-variants` and `--json` are also available.

## Voice Casting Workflow (using `echada`)

**IMPORTANT**: All casting (character extraction and voice generation) is done using the `echada` CLI tool. Do NOT use produciesta `--autocast` or manual Claude-assisted casting.

### Step 1: Extract Characters from Screenplays

```bash
# echada >= 3.0.0 (probe first — see "Cast source" above). echada no longer
# discovers characters; SwiftPersonaje does:
personaje cast-discover --project .            # add every speaking character → CAST.md
personaje cast-discover --project . --dry-run  # preview the members it would add
echada generate prompt --project PROJECT.md    # write voicePrompts into CAST.md

# echada 1.x / 2.x only (`generate cast` was removed in 3.0.0):
echada generate cast --project PROJECT.md      # discover characters → CAST.md

# Legacy echada (< 1.0.0):
echada extract --project PROJECT.md            # updates the cast: block in PROJECT.md
echada extract --project PROJECT.md --dry-run  # preview without modifying PROJECT.md
```

**What happens:**
- Reads all screenplay files matched by `filePattern` in PROJECT.md
- `personaje cast-discover` adds each speaking character's **name only**;
  it never changes, reorders or removes an existing member. `--project`
  takes the project **directory**.
- `echada generate prompt` uses a language model (on-device by default) to
  write each member's voicePrompt
- **Legacy `cast:` block, no CAST.md:** `personaje cast-discover` refuses to
  run. Migrate first with `echada cast --project PROJECT.md --dry-run` (the
  dry run still migrates the roster to CAST.md) or `reparto import`, then
  discover.
- Hand-edited names must be canonical for echada 3.0; run
  `reparto canonicalize` if they aren't

### Step 2: Generate Voice Files (.vox)

```bash
# Generate .vox files for all cast members
echada cast --project PROJECT.md

# Force regenerate all voices (even if .vox files exist)
echada cast --project PROJECT.md --force-regenerate

# Preview without writing files (3.0 stops on an empty roster with the
# `personaje cast-discover` advice)
echada cast --project PROJECT.md --dry-run
echada generate vox --project PROJECT.md --dry-run   # 3.0: prints each member's .vox destination
```

**What happens:**
- Reads cast entries from the roster (each with a `voicePrompt`) —
  CAST.md on a capable binary, PROJECT.md's `cast:` on a legacy one
- Uses VoxAlta + local LLM to generate custom .vox voice files
- Saves each .vox where "Where .vox files live" says (3.0: the character's
  `.dossier/voice/` folder or its existing pointer; ≤ 2.x: `voices/`) and
  records the path in the roster's `voices.voxalta` field
- For multi-model (1.7b + 0.6b) voices, use the `cast-voices` skill's driver

### Step 3: Generate Audio with Produciesta

```bash
# Generate audio using the cast roster and .vox voices
produciesta /path/to/project --provider voxalta --format m4a --verbose
```

**What happens:**
- Produciesta resolves the cast roster (current tooling reads CAST.md;
  older shipped produciesta binaries read PROJECT.md's `cast:` — keep the
  roster wherever your probed toolchain expects it)
- Resolves character voices via .vox files
- Parses Fountain files and generates audio for all episodes
- Saves M4A files to `audio/` directory

## Voice Providers

### VoxAlta with echada (Primary - On-Device Custom Voices)

**Advantages:**
- Fully on-device, no API key required
- Custom AI-generated voices tailored to each character
- Uses voicePrompts from the cast roster (CAST.md; legacy PROJECT.md `cast:`)
  to design unique voices
- .vox files are portable and reusable

**Best for:** Multi-character podcasts, custom voice design, privacy-sensitive projects

**Casting workflow:**
```bash
# Discover characters into CAST.md, then generate voicePrompts
# (echada 1.x/2.x: `echada generate cast` instead of personaje;
#  legacy < 1.0.0: `echada extract --project PROJECT.md`)
personaje cast-discover --project .
echada generate prompt --project PROJECT.md

# Generate .vox voice files
echada cast --project PROJECT.md

# Regenerate all voices from scratch
echada cast --project PROJECT.md --force-regenerate
```

**Voice file format:** `.vox` bundles at each member's `voices.voxalta`
path — `characters/<NAME>.dossier/voice/<NAME>.vox` on echada 3.0, `voices/`
on older binaries and unmigrated projects

### Apple Neural TTS (Free)

**Advantages:**
- No API key required
- Premium voices included with macOS
- Fast, local processing
- No per-character costs

**Best for:** Simple single-narrator podcasts, quick testing

**Query voices:**
```bash
say -v '?'
```

**Voice URI format:**
```
apple://com.apple.voice.premium.en-US.Aaron
```

### ElevenLabs (Paid)

**Advantages:**
- Extremely natural-sounding voices
- Multilingual support
- Professional quality
- Emotion control

**Best for:** Professional production, non-English podcasts, high-quality output

**Setup:**
```bash
export ELEVENLABS_API_KEY="your-key-here"
```

**Voice URI format:**
```
elevenlabs://21m00Tcm4TlvDq8ikWAM
```

**Popular voices:**
- `21m00Tcm4TlvDq8ikWAM` - Rachel (US female)
- `EXAVITQu4vr4xnSDxMaL` - Bella (US female)
- `pNInz6obpgDQGcFmaJgB` - Adam (US male)
- `ErXwobaYiN019PkySvjV` - Antoni (male, well-rounded)
- `MF3mGyEYCl7XYWbV9V6O` - Elli (young female)

## Complete End-to-End Publishing Workflow

This is the **complete workflow** from .fountain files to live podcast on intrusive-memory.productions.

### Prerequisites Checklist

Before starting, verify:
- [ ] Produciesta CLI built and working: `produciesta --version`
- [ ] Git LFS installed: `git lfs version`
- [ ] Website repo cloned: `~/Projects/intrusive-memory.github.com/`
- [ ] Podcast source repo exists (or create new)
- [ ] CDN URL known: `https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/`

### Scenario: Publishing Daily Dao Episodes 1-5

**Variables for this example:**
- **Source repo**: `~/podcast-daily-dao/`
- **Website repo**: `~/Projects/intrusive-memory.github.com/`
- **Podcast slug**: `daily-dao`
- **Audio path on CDN**: `daily-dao/` (matches slug)

---

### PHASE 1: Audio Generation (Source Repo)

**Step 1: Analyze Episodes and Extract Characters**

```bash
cd ~/podcast-daily-dao
ls episodes/*.fountain
# Output: chapter-01.fountain through chapter-05.fountain
```

Claude reads sample episodes and identifies:
- **NARRATOR** - Reads verses and commentary

**Step 2: Query Available Voices**

```bash
say -v '?'
```

Claude selects:
- **NARRATOR** → Aaron (mature, contemplative tone)

**Step 3: Create PROJECT.md and CAST.md**

`PROJECT.md` — project configuration only:

```yaml
---
type: project
title: Daily Dao - Tao De Jing Podcast
author: Tom Stovall
description: Daily readings from the Tao Te Ching with commentary
episodesDir: episodes
audioDir: audio
filePattern: "*.fountain"
exportFormat: m4a
---

## Production Notes

### Project Details
- Episodes 1-5 of the Tao Te Ching
- Each episode: ~4-6 minutes
```

`CAST.md` — the cast roster, beside PROJECT.md (`type: cast` and the `cast:`
array are BOTH required for the file to be accepted):

```yaml
---
type: cast
cast:
  - character: NARRATOR
    voices:
      - apple://com.apple.voice.premium.en-US.Aaron
---

## Voice Casting
- NARRATOR: Aaron - Mature, authoritative voice appropriate for philosophical content
```

**Legacy fallback:** if the capability probe (see "Cast source" above) shows
an older toolchain — echada < 1.0.0, or a shipped
`Produciesta.app` binary — put the same `cast:` array into `PROJECT.md`'s
front matter instead; those binaries only read cast from there.

**Step 4: Generate Audio Files**

```bash
produciesta . --format m4a --verbose
```

**Output:**
```
✓ Project directory: ~/podcast-daily-dao
✓ Found 5 episodes
✓ Cast list loaded: 1 character
✓ Starting generation...

Episode 1/5: chapter-01.fountain
  Parsing... ✓ 15 elements
  Generating... ✓ 100%
  Exporting... ✓ chapter-01.m4a (3.8 MB, 4m 45s)

[... episodes 2-4 ...]

Episode 5/5: chapter-05.fountain
  Parsing... ✓ 14 elements
  Generating... ✓ 100%
  Exporting... ✓ chapter-05.m4a (3.5 MB, 4m 22s)

✓ Generation complete!
  Processed: 5 episodes
  Duration: 23m 12s total
  Output: ~/podcast-daily-dao/audio/
```

**Step 5: Verify Generated Audio**

```bash
ls -lh audio/
# Should see: chapter-01.m4a through chapter-05.m4a

# Test playback of first episode
open audio/chapter-01.m4a
```

---

### PHASE 2: Git LFS Commit (Source Repo)

**Step 6: Configure Git LFS (if not already done)**

```bash
# Check if LFS is tracking .m4a files
cat .gitattributes | grep m4a

# If not present, configure it:
echo "*.m4a filter=lfs diff=lfs merge=lfs -text" >> .gitattributes
git lfs track "*.m4a"
```

**Step 7: Commit Audio Files to LFS**

```bash
git add audio/*.m4a
git add .gitattributes
git commit -m "Add audio for chapters 1-5

- Generated with Produciesta using Aaron (Apple TTS)
- Total duration: 23m 12s
- Episodes: chapter-01 through chapter-05

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git push origin main
```

**Step 8: Verify LFS Upload**

```bash
git lfs ls-files
# Should show: audio/chapter-01.m4a, chapter-02.m4a, etc.

# Verify files are uploaded to LFS (not stored as blobs)
git lfs status
```

**Step 9: Verify CDN Availability**

```bash
# Test that audio is accessible via CDN
curl -I https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/daily-dao/chapter-01.m4a

# Should return: HTTP/2 200
# Content-Type: audio/mp4
```

**If 404:** Wait a few minutes for LFS sync to CDN, or check CDN configuration.

---

### PHASE 3: Website Integration (Website Repo)

**Step 10: Copy Transcripts to Website**

```bash
cd ~/Projects/intrusive-memory.github.com

# Copy .fountain files to website episodes directory
cp ~/podcast-daily-dao/episodes/*.fountain \
   podcasts/daily-dao/episodes/

# Verify copy
ls podcasts/daily-dao/episodes/
# Should see: chapter-01.fountain through chapter-05.fountain
```

**Step 11: Update Website Metadata**

Open `podcasts/daily-dao/index.html` and verify:

**Check page title and description:**
```html
<div class="podcast-header">
    <h1>Daily Dao</h1>  <!-- ✓ Correct -->
    <p>81 Chapters of the Tao Te Ching</p>  <!-- ✓ Correct -->
```

**Check CDN URLs in JavaScript:**
```javascript
audioSource.src = '{{ site.audio_cdn }}/daily-dao/chapter-01.m4a';
//                                      ^^^^^^^^^ matches podcast slug
```

**Check subscribe links:**
```html
<a href="podcast://intrusive-memory.productions/podcasts/daily-dao/feed.xml" class="subscribe-link podcast-app">Subscribe in Podcast App</a>
<a href="/podcasts/daily-dao/feed.xml" class="subscribe-link rss">RSS Feed</a>
```

**Step 12: Update RSS Feed**

Open `podcasts/daily-dao/feed.xml` and add episodes:

```xml
<item>
    <title>Chapter 1 - The fundamental paradox of the Tao</title>
    <description>Chapter One introduces us to the fundamental paradox of the Tao...</description>
    <pubDate>Wed, 12 Feb 2025 00:00:00 -0500</pubDate>
    <enclosure url="https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/daily-dao/chapter-01.m4a"
               length="3980000"
               type="audio/mp4"/>
    <guid>https://intrusive-memory.productions/podcasts/daily-dao/chapter-01</guid>
    <itunes:duration>285</itunes:duration>
    <itunes:episodeType>full</itunes:episodeType>
</item>
```

**Get file size and duration:**
```bash
# File size (bytes)
stat -f%z ~/podcast-daily-dao/audio/chapter-01.m4a

# Duration (seconds) - use afinfo on macOS
afinfo ~/podcast-daily-dao/audio/chapter-01.m4a | grep "estimated duration"
```

**Step 13: Update Podcast Metadata**

Update `_data/podcasts.yml` if episode count changed:

```yaml
- slug: daily-dao
  name: Daily Dao - Tao De Jing Podcast
  episodes: 5  # ← Update this count
  status: in_progress  # or "complete" if all 81 done
  published: true  # Set to true when ready to go live
```

---

### PHASE 4: Validation & Testing

**Step 14: Test Locally with Jekyll**

```bash
cd ~/Projects/intrusive-memory.github.com

# Start Jekyll server
bundle exec jekyll serve

# Visit: http://localhost:4000/podcasts/daily-dao/
```

**Validate checklist:**
- [ ] Page loads without errors
- [ ] Title and subhead are correct
- [ ] Audio player loads first episode
- [ ] Audio plays from CDN (check network tab)
- [ ] Transcript loads and displays correctly
- [ ] Chapter buttons work (switch episodes)
- [ ] Subscribe links point to correct URLs
- [ ] RSS feed validates (use https://validator.w3.org/feed/)

**Step 15: Validate RSS Feed**

```bash
# Validate feed structure
curl http://localhost:4000/podcasts/daily-dao/feed.xml | xmllint --format -

# Or use online validator:
# https://validator.w3.org/feed/
```

**Check for:**
- [ ] All episode `<enclosure>` URLs point to CDN
- [ ] File sizes are accurate
- [ ] Durations are in seconds
- [ ] Pub dates are valid RFC-822 format

**Step 16: Test Transcripts**

In browser console:
```javascript
// Should load without errors
fetch('/podcasts/daily-dao/episodes/chapter-01.fountain')
  .then(r => r.text())
  .then(console.log);
```

**Verify:**
- [ ] .fountain files are accessible (not 404)
- [ ] Transcript content appears (no YAML/SSML tags)
- [ ] Switching episodes loads new transcripts

---

### PHASE 5: Deployment

**Step 17: Commit Website Changes**

```bash
cd ~/Projects/intrusive-memory.github.com

git add podcasts/daily-dao/episodes/*.fountain
git add podcasts/daily-dao/feed.xml
git add podcasts/daily-dao/index.html  # if modified
git add _data/podcasts.yml  # if modified

git commit -m "Publish Daily Dao episodes 1-5

- Add transcripts for chapters 1-5
- Update RSS feed with new episodes
- Update episode count in podcasts.yml
- CDN audio URLs verified and working

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

**Step 18: Push to Production**

```bash
git push origin master
```

**Step 19: Verify GitHub Pages Build**

```bash
# Check build status (if gh CLI installed)
gh run list --limit 1

# Or visit: https://github.com/intrusive-memory/intrusive-memory.github.com/actions
```

**Wait for:**
- ✅ GitHub Pages build completes (~1-2 minutes)
- ✅ Changes deploy to production

**Step 20: Final Production Validation**

Visit live site: `https://intrusive-memory.productions/podcasts/daily-dao/`

**Final checklist:**
- [ ] Page loads on production
- [ ] Audio plays from CDN
- [ ] Transcripts display correctly
- [ ] Subscribe links work
- [ ] RSS feed accessible at `/podcasts/daily-dao/feed.xml`
- [ ] Test subscribe in podcast app (Apple Podcasts, Overcast, etc.)

---

### Workflow Summary

```
┌─────────────────────────────────────────┐
│ PHASE 1: Audio Generation               │
│  - Analyze .fountain files              │
│  - Create PROJECT.md + CAST.md          │
│  - Generate audio with Produciesta      │
│  - Verify playback locally              │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│ PHASE 2: Git LFS Commit                 │
│  - Configure LFS for .m4a               │
│  - Commit audio files                   │
│  - Push to remote                       │
│  - Verify CDN availability              │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│ PHASE 3: Website Integration            │
│  - Copy transcripts to website          │
│  - Update index.html metadata           │
│  - Update RSS feed with episodes        │
│  - Update _data/podcasts.yml            │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│ PHASE 4: Validation & Testing           │
│  - Test locally with Jekyll             │
│  - Validate RSS feed                    │
│  - Check audio playback                 │
│  - Verify transcripts load              │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│ PHASE 5: Deployment                     │
│  - Commit website changes               │
│  - Push to production                   │
│  - Verify GitHub Pages build            │
│  - Final production validation          │
└─────────────────────────────────────────┘
```

**Time Estimate:**
- Audio generation: ~2-3 minutes per episode
- LFS commit & CDN verify: 5-10 minutes
- Website updates: 10-15 minutes
- Testing & validation: 10-15 minutes
- Deployment: 5-10 minutes
- **Total for 5 episodes: ~45-60 minutes**

## Character Analysis & Casting

Character extraction and voice generation are handled entirely by `echada`. Claude's role is:

1. **Probe the binary** (check `echada --version` is >= 1.0.0, and >= 3.0.0
   or a `migrate`/`sample` verb for 3.0 — see "Cast source" above) to learn
   whether the cast roster is CAST.md or the legacy PROJECT.md `cast:` block,
   and where `.vox` files go
2. **Ensure PROJECT.md exists** with correct `episodesDir`, `filePattern`, and `tts` settings
3. **Run the extraction stage** to populate the roster with characters and
   voicePrompts — `personaje cast-discover` + `echada generate prompt`
   (echada 3.0), `echada generate cast` + `echada generate prompt`
   (1.x/2.x), or `echada extract` (legacy)
4. **Review/edit voicePrompts** in the roster if the user wants adjustments
5. **Run `echada cast`** to generate .vox voice files from the prompts
6. **Run `produciesta`** to generate audio using the cast voices

### Manual voicePrompt Editing

If the user wants to refine a character's voice, edit the `voicePrompt` field in the cast roster (CAST.md; legacy PROJECT.md `cast:`) and re-run `echada cast --character "<NAME>" --force-regenerate` for that character. On echada 3.0 the voice is rebuilt at its existing `voices.voxalta` path; nothing moves.

## PROJECT.md + CAST.md Structure

### Minimal Configuration

`PROJECT.md`:

```yaml
---
type: project
title: Podcast Title
episodesDir: episodes
audioDir: audio
filePattern: "*.fountain"
exportFormat: m4a
---
```

`CAST.md` (beside PROJECT.md; on a legacy toolchain fold this `cast:` array
into PROJECT.md's front matter instead):

```yaml
---
type: cast
cast:
  - character: CHARACTER_NAME
    voices:
      - apple://voice.id
---
```

### Complete Configuration

`PROJECT.md`:

```yaml
---
type: project
title: Full Podcast Title
author: Author Name
description: Detailed podcast description
episodesDir: episodes
audioDir: audio
filePattern: "*.fountain"
exportFormat: m4a
---

## Production Notes

[Optional markdown content documenting the project]
```

`CAST.md`:

```yaml
---
type: cast
cast:
  - character: NARRATOR
    voicePrompt: "Mature, authoritative narrator. Calm and clear."
    voices:
      - apple://com.apple.voice.premium.en-US.Aaron   # Primary
      - apple://com.apple.voice.premium.en-GB.Daniel  # Fallback
  - character: CHARACTER_TWO
    voices:
      - elevenlabs://21m00Tcm4TlvDq8ikWAM
---

[Optional markdown body: character summaries — preserved byte-for-byte by echada]
```

### Required Fields — PROJECT.md

- `type: project` - Always required
- `title` - Podcast title
- `episodesDir` - Relative path to episodes (default: `episodes`)
- `audioDir` - Relative path for output (default: `audio`)
- `filePattern` - Glob pattern for episode files (default: `"*.fountain"`)
- `exportFormat` - Audio format: `m4a`, `aiff`, `wav`, `caf`, `mp3`

### Required Fields — CAST.md

- `type: cast` - Required; a `type:`-only file is not a valid roster
- `cast` - Array of character-to-voice mappings (`character` required per
  entry; `voicePrompt` — legacy alias `voiceDescription` — `actor`,
  `gender`, `language`, `voices`, `appearance`, `manifest` optional). Paths
  (`voices.voxalta`, `manifest`) are relative to the directory containing
  CAST.md. echada 3.0 requires `character` to be canonical
  (`reparto canonicalize`).

On a **legacy** toolchain there is no CAST.md: `cast` is instead a required
field of PROJECT.md's front matter.

### Optional Fields

- `author` - Creator name
- `description` - Podcast description

## Produciesta Generation Commands

### Basic Generation

```bash
# Generate all episodes
produciesta /path/to/project

# Generate with specific format
produciesta /path/to/project --format m4a

# Verbose output
produciesta /path/to/project --verbose
```

### Single Episode

```bash
# By name (relative to episodesDir)
produciesta /path/to/project --episode chapter-01.fountain

# By direct path
produciesta /path/to/project/episodes/chapter-01.fountain
```

### Batch Processing

```bash
# Skip existing audio files
produciesta /path/to/project --skip-existing

# Resume from episode N
produciesta /path/to/project --resume-from 50

# Force regenerate all
produciesta /path/to/project --regenerate
```

### Preview Mode

```bash
# Dry run (show plan without generating)
produciesta /path/to/project --dry-run
```

### Error Handling

```bash
# Stop on first error
produciesta /path/to/project --fail-fast

# Continue on voice resolution errors (use default voice)
produciesta /path/to/project --ignore-generation-errors
```

## Transcript Generation for Web Players

After generating audio, you can deploy .fountain files as transcripts for your podcast website. The web player JavaScript automatically parses and displays them under the audio player.

### Transcript Structure

The same .fountain files used for audio generation serve as transcripts:

**Example: chapter-01.fountain**
```fountain
---
title: Tao De Jing - Chapter 1
album: Tao De Jing Podcast
artist: Tao De Jing
track: 1
description: Chapter One introduces the fundamental paradox of the Tao.
---
===

Tao De Jing - Chapter 1

[[ slnc 1000 ]]

Chapter One introduces us to the fundamental paradox of the Tao.

[[ slnc 1000 ]]
[[rate 100]]

Speak it aloud, and it slips from your grasp...

[[ rset]]
```

### How Transcripts Are Displayed

The web player JavaScript (in each podcast's `index.html`):

1. **Fetches** the .fountain file from `episodes/` directory
2. **Parses** with `parseFountain()` function:
   - Removes YAML frontmatter (`---...---`)
   - Removes section markers (`===`)
   - Strips SSML tags (`[[ slnc 1000 ]]`, `[[rate 100]]`, `[[ rset]]`)
   - Splits into lines
3. **Displays** clean text in the transcript section

**Result:** Only the actual spoken content appears in the transcript.

### Preparing Transcripts for Website

#### Step 1: Copy Fountain Files to Website

```bash
# For a podcast at ~/Projects/intrusive-memory.github.com/podcasts/daily-dao/

# Copy all episodes to website episodes directory
cp ~/podcast-project/episodes/*.fountain \
   ~/Projects/intrusive-memory.github.com/podcasts/daily-dao/episodes/

# Or copy individual episodes
cp ~/podcast-project/episodes/chapter-01.fountain \
   ~/Projects/intrusive-memory.github.com/podcasts/daily-dao/episodes/
```

#### Step 2: Verify Transcript Section in index.html

Ensure the podcast's `index.html` includes the transcript section:

**CSS (in `<style>` block):**
```css
.transcript-section {
    background: rgba(0,0,0,0.4);
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 2rem;
    max-height: 300px;
    overflow-y: auto;
}
.transcript-content {
    font-family: 'Roboto', sans-serif;
    color: #e2e8f0;
    font-size: 1.1rem;
    line-height: 1.8;
}
.transcript-line {
    padding: 0.5rem 0;
    border-bottom: 1px solid rgba(255,255,255,0.05);
}
```

**HTML (before chapters section):**
```html
<div class="transcript-section">
    <h3>Transcript</h3>
    <div class="transcript-content" id="transcript-content">
        <p class="transcript-loading">Loading transcript...</p>
    </div>
</div>
```

**JavaScript functions:**
```javascript
function parseFountain(text) {
    let content = text.replace(/^---[\s\S]*?---\s*/m, '');
    content = content.replace(/^===\s*/m, '');
    content = content.replace(/\[\[\s*slnc\s+\d+\s*\]\]/gi, '');
    content = content.replace(/\[\[\s*rate\s+\d+\s*\]\]/gi, '');
    content = content.replace(/\[\[\s*rset\s*\]\]/gi, '');
    const lines = content.split('\n')
        .map(line => line.trim())
        .filter(line => line.length > 0);
    return lines;
}

async function loadTranscript(filename) {
    const url = '{{ site.baseurl }}/podcasts/podcast-name/episodes/' + filename;

    transcriptContent.innerHTML = '<p class="transcript-loading">Loading transcript...</p>';

    try {
        const response = await fetch(url);
        if (!response.ok) throw new Error('Failed to load');
        const text = await response.text();
        const lines = parseFountain(text);

        transcriptContent.innerHTML = lines.map((line, index) => {
            return '<div class="transcript-line" data-line="' + index + '">' + line + '</div>';
        }).join('');
    } catch (error) {
        transcriptContent.innerHTML = '<p class="transcript-loading">Transcript not available</p>';
    }
}
```

**Call on chapter change:**
```javascript
function playChapter(chapterNum) {
    // ... audio loading code ...
    loadTranscript('chapter-' + padNumber(chapterNum) + '.fountain');
}
```

#### Step 3: Deploy and Test

```bash
# Commit to git
cd ~/Projects/intrusive-memory.github.com
git add podcasts/podcast-name/episodes/*.fountain
git add podcasts/podcast-name/index.html
git commit -m "Add transcripts for podcast episodes"
git push

# Test locally (if using Jekyll)
bundle exec jekyll serve
# Visit: http://localhost:4000/podcasts/podcast-name/
```

### Transcript File Naming Conventions

Match the naming pattern used by your audio files:

**Daily Dao (numbered chapters):**
```
chapter-01.fountain
chapter-02.fountain
...
chapter-81.fountain
```

**Meditations (Julian day + date):**
```
001_january_01.fountain
002_january_02.fountain
...
365_december_31.fountain
```

**Custom naming (YNTSWYD):**
```
Chapter 1.fountain
Chapter 2.fountain
Epilogue.fountain
```

**Critical:** The filename must match what the JavaScript `loadTranscript()` function constructs.

### Workflow Integration

When generating audio with this skill:

1. **Generate audio** with Produciesta
2. **Copy .fountain files** to website `episodes/` directory
3. **Verify** transcript section exists in `index.html`
4. **Test** locally that transcripts load correctly
5. **Deploy** to production

### Complete Workflow Reference

For the full end-to-end workflow including:
- Audio generation
- Git LFS commit and CDN verification
- Transcript deployment
- RSS feed updates
- Validation and testing
- Production deployment

**See: "Complete End-to-End Publishing Workflow" section above.**

That section provides a step-by-step walkthrough with all commands, validation steps, and troubleshooting guidance.

### Troubleshooting Transcripts

**Transcript shows "Transcript not available":**
- Verify .fountain file exists in `episodes/` directory
- Check filename matches what JavaScript constructs
- Inspect browser console for 404 errors
- Verify file permissions (should be readable)

**Transcript shows SSML tags like `[[ slnc 1000 ]]`:**
- Update `parseFountain()` function to strip all SSML tags
- See reference implementation in Daily Dao or Meditations

**Transcript shows YAML frontmatter:**
- Verify regex in `parseFountain()` correctly removes frontmatter
- Pattern should be: `/^---[\s\S]*?---\s*/m`

**Lines are concatenated (not separated):**
- Check that `split('\n')` is being used
- Verify lines are wrapped in `<div class="transcript-line">` tags

## Troubleshooting

### Error: "Character not found in cast list"

**Cause:** Fountain file contains a character not in the cast roster
(CAST.md; legacy PROJECT.md `cast:`).

**Solution 1:** Add the character to the roster
```yaml
cast:
  - character: MISSING_CHARACTER
    voices:
      - apple://com.apple.voice.premium.en-US.Aaron
```

**Solution 2:** Use default voice
```bash
produciesta /path/to/project \
  --default-voice "apple://com.apple.voice.premium.en-US.Aaron"
```

**Solution 3:** Re-analyze with Claude
Ask Claude to re-read Fountain files and update the cast roster.

### Error: "Voice provider unavailable"

**For ElevenLabs:**
```bash
# Check API key is set
echo $ELEVENLABS_API_KEY

# Set if missing
export ELEVENLABS_API_KEY="your-key-here"
```

**For Apple TTS:**
- Premium voices require download: System Settings → Accessibility → Spoken Content
- Voice ID must be exact (case-sensitive)

### Error: "No episodes found"

**Check file pattern:**
```bash
# List files
ls episodes/*.fountain

# Update filePattern in PROJECT.md if needed
filePattern: "*.fountain"  # or "chapter-*.fountain", etc.
```

### Audio Quality Issues

**Voice too fast/slow:**
- Apple TTS: No direct speed control
- ElevenLabs: Has stability/similarity controls

**Wrong voice:**
- Update voice URI in the cast roster (CAST.md; legacy PROJECT.md `cast:`)
- Regenerate: `produciesta /path/to/project --regenerate`

## Advanced: Hooks for Automation (macOS Only)

Produciesta supports pre/post-generation hooks for automation:

### Create Hooks

```bash
mkdir -p /path/to/project/.produciesta-hooks

# Pre-generation hook
cat > /path/to/project/.produciesta-hooks/pre-generation.sh << 'EOF'
#!/bin/bash
echo "🎙️  Starting audio generation at $(date)"
# Validation, setup, notifications
EOF

# Post-generation hook
cat > /path/to/project/.produciesta-hooks/post-generation.sh << 'EOF'
#!/bin/bash
echo "✅ Completed audio generation at $(date)"
# Upload to R2, update RSS feed, deploy to website
EOF

chmod +x /path/to/project/.produciesta-hooks/*.sh
```

### Disable Hooks

```bash
produciesta /path/to/project --skip-hooks
```

## Creating Execution Plans

When the user asks to "create an audio plan", generate a planning document:

### Plan Template

```markdown
# Audio Generation Plan: [Project Title]

## Project Overview
- **Location**: /path/to/project
- **Episodes**: [N] .fountain files
- **Characters**: [N] unique characters
- **Format**: M4A
- **Provider**: Apple TTS / ElevenLabs

## Step 1: Character Analysis

[Claude analyzes Fountain files]

Characters identified:
- NARRATOR: 150 lines, authoritative narrator voice
- ALICE: 45 lines, young female protagonist
- BOB: 32 lines, supporting male character

## Step 2: Voice Assignment

[Claude matches voices]

Recommended casting:
- NARRATOR → Aaron (mature, clear, authoritative)
- ALICE → Ava (young female, expressive)
- BOB → Daniel (British accent, professional)

## Step 3: PROJECT.md + CAST.md Creation

[Claude creates/updates PROJECT.md (config) and the cast roster — CAST.md,
or PROJECT.md's cast: block if the probe found a legacy toolchain]

## Step 4: Audio Generation

```bash
cd /path/to/project
produciesta . --format m4a --verbose
```

## Step 5: Quality Check

- [ ] Listen to first episode
- [ ] Verify voice assignments appropriate
- [ ] Check audio quality
- [ ] Validate file sizes

## Timeline Estimate

- Character analysis: 5 minutes
- Voice matching: 5 minutes
- PROJECT.md + CAST.md creation: 2 minutes
- Audio generation: ~2 minutes per episode
- Quality check: 10 minutes
- **Total**: [Estimated based on episode count]
```

## Best Practices

1. **Always analyze all episodes** before assigning voices (characters may appear later)
2. **Document casting rationale** in CAST.md's markdown body (echada preserves it verbatim)
3. **Test with one episode first** before batch processing
4. **Use premium voices for primary characters** (more dialogue = more important)
5. **Consider voice distinctiveness** to avoid confusion between characters
6. **Commit PROJECT.md and CAST.md to git** for version control and team collaboration
7. **Use dry-run mode** to validate configuration before generating

## Related Tools and Resources

- **Produciesta CLI**: `~/Projects/Produciesta/produciesta-cli/`
- **ProduciestaCore**: Audio generation engine
- **Apple TTS**: Built-in macOS voices
- **ElevenLabs**: Premium voice synthesis API
- **Fountain Format**: https://fountain.io/
- **ElevenLabs Voice Library**: https://elevenlabs.io/voice-library

## Quick Reference: Common Commands

### Audio Generation
```bash
# Generate all episodes
produciesta /path/to/project --format m4a --verbose

# Generate single episode
produciesta /path/to/project --episode chapter-01.fountain

# Dry run (preview without generating)
produciesta /path/to/project --dry-run

# Skip existing files
produciesta /path/to/project --skip-existing
```

### Git LFS Management
```bash
# Configure LFS for audio files
git lfs track "*.m4a"
echo "*.m4a filter=lfs diff=lfs merge=lfs -text" >> .gitattributes

# Check LFS status
git lfs ls-files
git lfs status

# Verify file is in LFS (not regular git)
git lfs ls-files | grep chapter-01.m4a
```

### CDN Verification
```bash
# Test audio availability on CDN
curl -I https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/podcast-slug/chapter-01.m4a

# Should return: HTTP/2 200
```

### Transcript Deployment
```bash
# Copy transcripts from source to website
cp ~/podcast-source/episodes/*.fountain \
   ~/Projects/intrusive-memory.github.com/podcasts/podcast-slug/episodes/

# Verify copy
ls -la ~/Projects/intrusive-memory.github.com/podcasts/podcast-slug/episodes/
```

### Get Audio Metadata
```bash
# File size (bytes) for RSS feed
stat -f%z audio/chapter-01.m4a

# Duration (seconds) for RSS feed
afinfo audio/chapter-01.m4a | grep "estimated duration"

# Or use ffprobe
ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 audio/chapter-01.m4a
```

### Jekyll Testing
```bash
cd ~/Projects/intrusive-memory.github.com

# Start local server
bundle exec jekyll serve

# Visit: http://localhost:4000/podcasts/podcast-slug/

# Stop server: Ctrl+C
```

### RSS Feed Validation
```bash
# Validate feed locally
curl http://localhost:4000/podcasts/podcast-slug/feed.xml | xmllint --format -

# Or use online validator:
# https://validator.w3.org/feed/
```

## Pre-Flight Validation Checklist

Before starting audio generation:

**Source Repository:**
- [ ] Produciesta CLI installed and working: `produciesta --version`
- [ ] All .fountain files present in `episodes/`
- [ ] PROJECT.md exists (project config)
- [ ] Cast roster present — CAST.md, or the legacy PROJECT.md `cast:` block
      if `echada --version` is below 1.0.0 (older binary)
- [ ] Git LFS configured: `git lfs version`
- [ ] `.gitattributes` has `*.m4a` LFS tracking

**Website Repository:**
- [ ] Podcast page exists at `podcasts/<slug>/`
- [ ] `index.html` has transcript section (CSS, HTML, JavaScript)
- [ ] `feed.xml` template ready
- [ ] `_data/podcasts.yml` has podcast entry

**Environment:**
- [ ] Jekyll works: `bundle exec jekyll serve`
- [ ] Git authentication configured
- [ ] CDN URL known

## Post-Deployment Validation Checklist

After pushing to production:

**Production Site:**
- [ ] Page loads: `https://intrusive-memory.productions/podcasts/<slug>/`
- [ ] Audio plays from CDN (check Network tab in browser DevTools)
- [ ] Transcripts load and display correctly
- [ ] Chapter/episode switching works
- [ ] Subscribe links are correct
- [ ] RSS feed accessible: `https://intrusive-memory.productions/podcasts/<slug>/feed.xml`

**RSS Feed:**
- [ ] Feed validates: https://validator.w3.org/feed/
- [ ] All episodes have `<enclosure>` tags with CDN URLs
- [ ] File sizes match actual audio file sizes
- [ ] Durations are accurate (in seconds)
- [ ] Pub dates are valid RFC-822 format
- [ ] Test subscribe in podcast app (Apple Podcasts, Overcast, etc.)

**GitHub:**
- [ ] GitHub Pages build succeeded
- [ ] No build errors in Actions tab
- [ ] LFS files uploaded successfully

## Common Troubleshooting

### Issue: Audio generation fails with "Character not found"

**Cause:** Fountain file has a character missing from the cast roster (CAST.md; legacy PROJECT.md `cast:`).

**Solution:**
```bash
# Re-analyze fountain files
grep "^[A-Z][A-Z ]*$" episodes/*.fountain | sort -u

# Add missing characters to the cast roster (CAST.md; legacy PROJECT.md cast:)
```

### Issue: CDN returns 404 for audio files

**Cause:** LFS files not synced to CDN yet.

**Solutions:**
1. Wait 5-10 minutes for sync
2. Verify LFS upload: `git lfs ls-files`
3. Check file is actually in LFS: `git lfs ls-files | grep filename`
4. Verify CDN URL path matches podcast slug

### Issue: Transcripts show "Transcript not available"

**Cause:** .fountain files not copied to website or filename mismatch.

**Solutions:**
1. Verify files copied: `ls podcasts/<slug>/episodes/*.fountain`
2. Check browser console for 404 errors
3. Verify filename matches JavaScript `loadTranscript()` call
4. Check file permissions: `chmod 644 episodes/*.fountain`

### Issue: RSS feed validation fails

**Common errors and fixes:**
- **Invalid date format:** Use RFC-822 format: `Wed, 12 Feb 2025 00:00:00 -0500`
- **Invalid enclosure URL:** Must be full CDN URL with https://
- **Missing duration:** Add `<itunes:duration>285</itunes:duration>` (in seconds)
- **Invalid file size:** Get actual size with `stat -f%z audio/file.m4a`

### Issue: Jekyll build fails

**Common causes:**
- YAML syntax error in frontmatter
- Invalid HTML in index.html
- Missing required files (favicon, artwork)

**Debug:**
```bash
bundle exec jekyll build --verbose
# Read error message carefully
# Fix syntax errors in indicated files
```

### Issue: GitHub Pages not updating

**Solutions:**
1. Check build status: `gh run list --limit 1`
2. View build logs in Actions tab
3. Hard refresh browser: Cmd+Shift+R (macOS) or Ctrl+Shift+R (Windows)
4. Clear browser cache
5. Wait 2-3 minutes for CDN cache invalidation

## Notes

- **Use `personaje` + `echada` for all casting** - character discovery (`personaje cast-discover` on echada 3.0; `echada generate cast` on 1.x/2.x; `echada extract` on legacy binaries), voicePrompts (`echada generate prompt`) and voice generation (`echada cast`)
- **Cast lives in CAST.md** (SwiftReparto schema) on echada ≥ 1.0.0; probe `echada --version` (>= 1.0.0) and fall back to PROJECT.md's `cast:` block on older binaries
- **`.vox` paths come from CAST.md `voices.voxalta`**, never from a folder convention. echada 3.0 writes them into character records (`characters/<NAME>.dossier/voice/`); `echada migrate voices` moves an old `voices/` layout
- **Do NOT use produciesta `--autocast`** - it is deprecated in favor of echada
- Produciesta handles audio generation only - echada handles all casting
- Error logs saved to `GENERATION_ERRORS.md` in project root
- **Audio files are in Git LFS** - not regular git blobs
- **CDN serves audio** - website only references CDN URLs
- **Transcripts are .fountain files** - copied from source repo to website
- **RSS feeds must be manually updated** - no auto-generation yet
