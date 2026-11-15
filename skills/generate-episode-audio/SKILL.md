---
type: skill
name: generate-episode-audio
description: Generate podcast episode audio from Fountain or Highland screenplays using Produciesta CLI (which now wraps intro/outro itself as part of export), and open in QuickTime Player. Use this skill whenever the user asks to "generate audio", "make audio", "produce episode audio", "create the audio", "generate episode", "render the episode", or any variation of turning a screenplay file into playable podcast audio. Also trigger when the user says "let's hear it", "play the episode", or references audio generation for any podcasts/* project. Works across all intrusive-memory.productions podcasts (confessions, mr-mr-charles, casting-software-spells, daily-dao, meditations, etc.).
---

# Generate Episode Audio

Turn a .fountain or .highland screenplay into a finished podcast episode.
`produciesta export` now does the **intro/outro wrapping itself** in one pass —
there is no separate hook and no manual ffmpeg step. Wrapping is driven entirely
by PROJECT.md settings (see Step 4).

> **What changed (read once).** Wrapping moved *into* Produciesta's generation
> cycle (the "bracket" feature, shipped on `Produciesta` `development`). As a
> result:
> - You **no longer run** `.produciesta-hooks/post-generation.sh`. Running it now
>   would **double-wrap** the episode — see Step 5.
> - The exported m4a has **no Intro/Episode/Outro chapter markers** anymore. The
>   m4a render path does not embed chapters (only the FCPXML path does). The
>   audio is still intro→body→outro; it just has no chapter track. If a project
>   genuinely needs chapter markers in the feed, that is a separate follow-up in
>   Produciesta — flag it, don't try to re-add them with the old hook.
> - The sidecar `.vtt` is emitted **already aligned** to the wrapped audio, so
>   `fix_transcript.py` is **obsolete** (kept only as a fallback for an
>   un-upgraded binary — see Step 5b).

## ⚠️ Editing Safety Protocol (READ FIRST)

This skill edits the screenplay text (punctuation fixes, phonetic hints, block
splitting). A prior run **swiss-cheesed the screenplay** — content silently went
missing during these edits. Every edit to a `.fountain`/`.highland`-derived file
MUST follow this protocol. No exceptions.

1. **Back up before touching the file.** Copy it first:
   ```bash
   cp episodes/episode_XX.fountain episodes/episode_XX.fountain.bak
   ```
2. **Surgical edits only.** Use the `Edit` tool on a single, exact, unique
   matched string per fix. **Never** use `Write` to recreate the file, never
   rewrite a whole section, and never delete a line you are not explicitly
   fixing. One flagged instance = one targeted Edit.
3. **Verify after every editing pass.** Diff against the backup and confirm that
   *only* the lines you intended to change actually changed — nothing was
   dropped:
   ```bash
   diff episodes/episode_XX.fountain.bak episodes/episode_XX.fountain
   # sanity-check the line count did not shrink unexpectedly:
   wc -l episodes/episode_XX.fountain.bak episodes/episode_XX.fountain
   ```
4. **Restore on any unexpected loss.** If the diff shows deletions you did not
   intend, restore from the backup and redo the edit more narrowly:
   ```bash
   cp episodes/episode_XX.fountain.bak episodes/episode_XX.fountain
   ```
5. **Delete the backup only after audio generation succeeds.**

When in doubt, prefer fewer edits. It is fine to leave a minor irregularity
unfixed; it is not fine to lose a line of the script.

## Workflow

### Step 1: Identify the Episode File

Determine the episode file. The user may specify it directly or you may need to find it:

```bash
ls episodes/episode_*.fountain episodes/episode_*.highland 2>/dev/null
```

### Step 2: Extract from Highland (if needed)

Highland files are zip archives (textbundles). **Treat the `.highland` bundle as
read-only source.** Round-tripping text in and out of the textbundle — editing
the extracted text then repacking it into the bundle — is error-prone and is a
known way to corrupt the script. So:

- Extract the Fountain screenplay **once** to a sibling `.fountain`. From that
  point on, the `.fountain` is the single file you edit and generate from.
- **Never write edits back into the `.highland` bundle.** Do not repack the
  textbundle. If the user wants the Highland source updated, tell them to do it
  in Highland.app — do not attempt it here.

```bash
unzip -p episodes/episode_XX.highland "*.textbundle/text.md" > episodes/episode_XX.fountain
```

Only extract if the source is `.highland` and no corresponding `.fountain`
exists. **If a `.fountain` already exists, do NOT re-extract over it** — that
would clobber any prior edits. Re-extract only if the user explicitly asks to
regenerate from the Highland source (and back up the existing `.fountain` first
per the safety protocol).

### Step 3: Pre-Generation Quality Check

Read the `.fountain` file and scan for two distinct classes of problems before
spending model time. Show the user any findings and get confirmation before
editing the file.

**Any edit made in this step MUST follow the Editing Safety Protocol above** —
back up, surgical Edits only, diff-and-verify, restore on loss. Apply the fixes
one flagged instance at a time; do not batch-rewrite paragraphs or the file.

#### 3a. TTS irregularity scan (automated)

These patterns destabilize VoxAlta / Qwen3-TTS generation in observed,
reproducible ways. Grep the file for each before running produciesta:

- **Doubled or stacked terminal punctuation** — `..`, `...`, `....`, `!!`,
  `??`, `,,`, `;;`. The model interprets these as ellipsis / extended pause
  and the cloned speaker conditioning has nothing to anchor the trail-off,
  so voice audibly drifts at the end of the utterance. **Deterministic
  failure** — fix every instance. (`...` is intentional ellipsis only if you
  truly want the trail-off effect; a literal typo like `unfold..` is not.)

  ```bash
  grep -nE '[.!?,;]{2,}' episodes/episode_XX.fountain
  ```

- **Code-switch trigger words inside an English utterance** — language names
  like `Chinese`, `Spanish`, `French`, `German`, `Japanese`, `Korean`,
  `Mandarin`, `Cantonese`, `Russian`, `Arabic` (and similar). Multilingual
  TTS models can steer their phoneme/voice prediction toward the cued
  language mid-sentence, especially when the cue is followed shortly by
  text in that language (e.g. an UNCLE FU Chinese line right after).
  **Stochastic failure** — sometimes drifts, sometimes doesn't — but the
  risk is real enough to flag.

  ```bash
  grep -niE '\b(chinese|spanish|french|german|japanese|korean|mandarin|cantonese|russian|arabic|hebrew|hindi|portuguese|italian)\b' episodes/episode_XX.fountain
  ```

  Mitigations, in order of preference: (1) reword to remove the cue
  ("Chinese source" → "the original"); (2) split the sentence into its
  own paragraph so it generates as a shorter, isolated utterance; (3)
  leave it and accept that some takes will drift.

- **Long single-utterance dialogue blocks** — anything > ~250 chars in one
  unbroken NARRATOR/character block (i.e. no blank line inside it). The
  cloned speaker conditioning weakens past ~code 70 of the generation, so
  very long blocks risk voice drift in the back half. Splitting at
  sentence boundaries (insert a blank line and re-cue the character) gives
  each chunk its own fresh speaker prompt.

- **Mixed-script lines** — English and CJK characters in the same dialogue
  block under one character cue. Route them to different cues (e.g. UNCLE
  FU for the Chinese line, NARRATOR for the English) so each is a separate
  TTS element.

#### 3b. Pronunciation (manual)

Words the TTS will mispronounce regardless of clean punctuation:

- **Spanish/Italian/Portuguese terms**: add phonetic spellings (e.g.,
  "Rodillo" → "ro-DEE-yo", "Espectro" → "es-PEK-tro")
- **Technical jargon**: unusual acronyms or tool names
- **Proper names**: especially non-Anglophone surnames

Edit inline with phonetic hints if needed — one targeted `Edit` per word, then
diff against the backup to confirm nothing else moved (see Editing Safety
Protocol).

### Step 4: Configure Intro/Outro Wrapping (PROJECT.md settings)

Wrapping is now **config-driven**: `produciesta export` looks at the project's
`PROJECT.md`, resolves the intro/outro "brackets", and composes
intro → episode body → outro onto one timeline during export. Before generating,
ensure PROJECT.md declares the brackets, or export will produce an **unwrapped**
body.

> **⚠️ Verified 2026-08-08:** bracket resolution ALSO searches the
> **screenplay's own directory** for `intro.*`/`outro.*` assets — removing the
> `introFile`/`outroFile` keys from PROJECT.md is NOT enough to get an
> unwrapped render if bracket audio/scripts sit next to the .fountain. To
> render deliberately bare pieces (e.g. multi-scene episodes assembled with
> ffmpeg), keep bracket assets in a directory that contains no screenplays
> (granville uses `brackets/`), and verify after export:
> - **Timeline-first binaries** (`produciesta export --help | grep -q -- --timeline-root`):
>   brackets carry no `.vtt` cue any more, so check the saved timeline instead —
>   `grep -q 'produciesta.kind" value="intro"' timelines/<piece>/v*.fcpxml`
>   (match ⇒ it got wrapped anyway). Check the newest `vNNN` the export reported.
> - **Older binaries:** `grep -q '^INTRO$' audio/<piece>.vtt` (match ⇒ wrapped).

How Produciesta resolves each bracket (`intro`, then `outro`), in order — paths
are resolved **relative to the PROJECT.md directory** (the project root here):

1. **Explicit key present and the audio exists** → use it as-is (render-once
   reuse, never regenerated). The keys are `introFile` / `outroFile` in the
   PROJECT.md YAML frontmatter:
   ```yaml
   introFile: audio/intro.m4a
   outroFile: audio/outro.m4a
   ```
2. **No audio yet, but a `intro.fountain` / `outro.fountain` sits next to
   PROJECT.md** → Produciesta renders that bracket screenplay **once**, writes
   the resulting audio name back into PROJECT.md, and reuses it thereafter.
3. **A key is declared but its audio file is missing and there is no script to
   bootstrap from** → export **fails fast** (`error: missing intro/outro`).
4. **Nothing declared and no script** → no wrapping (body only).

**These projects keep their intro/outro at `audio/intro.m4a` / `audio/outro.m4a`,
which is NOT the default location** (the bare default is `intro.m4a` at the
project root). So the explicit keys are required. Check and add them:

```bash
# Are the bracket keys present?
grep -nE '^(introFile|outroFile):' PROJECT.md || echo "NO BRACKET KEYS — add them"
# Confirm the audio actually exists where the keys point:
ls -la audio/intro.m4a audio/outro.m4a 2>/dev/null
```

If the keys are missing, add them to the PROJECT.md frontmatter (surgical Edit —
insert two top-level lines inside the `---` block; do not rewrite the file). Only
point a key at a file that exists, or supply a sibling `*.fountain` to bootstrap
from — otherwise export fails fast.

**Prerequisite — bracket-capable binary.** This in-cycle wrapping needs a
Produciesta built from `development` (or later). Confirm once:

```bash
produciesta export --help | grep -q -- --fade-out && echo "bracket-capable" \
  || echo "STALE binary — rebuild Produciesta from development (make)"
```

(The `--fade-out` flag ships in the same feature as bracket wrapping, so its
presence is a reliable capability probe.)

### Step 4b: Generate + Wrap (one command)

Use `produciesta export` to render the per-Element clips, compose them in screen
order, **and wrap with the configured intro/outro** — all in one step:

```bash
produciesta export episodes/episode_XX.fountain \
  --out audio/episode_XX.m4a \
  --project-md PROJECT.md \
  --voices-dir .
```

Optional: `--fade-out <seconds>` applies a master fade-out over the final N
seconds of the whole mix (a clean tail instead of a hard cut).

**Critical: `--project-md` and `--voices-dir` are almost always required.**
Produciesta's default cast lookup is a `PROJECT.md` *sibling of the screenplay*
(i.e. inside `episodes/`). In these projects `PROJECT.md` lives at the **project
root**, so without `--project-md PROJECT.md` every Element fails with
`error[no-voice-assigned]: <CHARACTER>` and no audio is produced. The voxalta
paths in the cast roster are relative to the roster's directory, which is the
project root (e.g. `characters/THE PRACTITIONER.dossier/voice/THE PRACTITIONER.vox`
on echada 3.0, or `voices/NARRATOR.vox` on an unmigrated project), so
`--voices-dir .` (project root) is needed to resolve them. Paths can contain
spaces; quote them in any command you build from one. Run from the project
root.

Key facts:
- Binary location: `~/.local/bin/produciesta`
- Subcommands: `parse`, `cast`, `generate`, `export`, `version`. **`export` is
  the one you want** — `generate` only renders clips into the cache and does NOT
  write a stitched `.m4a` to disk.
- There is **no `--episode` and no `--regenerate` flag.** Pass the screenplay as
  a positional path.
- **Timeline-first export** (binaries where
  `produciesta export --help | grep -q -- --timeline-root` matches): every export
  first saves the episode as a Final Cut Pro timeline,
  `timelines/<episode-stem>/vNNN.fcpxml` beside PROJECT.md, then renders the
  `.m4a` and `.vtt` **from that file**. stderr says `Timeline written: … (vN)`, or
  `Timeline unchanged: … (vN)` when nothing changed (no duplicate version).
  The timeline's clips are kept in `.produciesta/clips/` beside PROJECT.md, as
  lossless WAVs: open the `.fcpxml` in Final Cut Pro to edit by hand.
  **Before the first timeline-first export in a podcast repo, add
  `.produciesta/` to its `.gitignore`** (the WAVs get large); whether to commit
  `timelines/` is the user's call (open question Q3 in Produciesta's
  `Docs/REQUIREMENTS-timeline-first-output.md`). `--fcpxml` is gone: the timeline
  is always written. `--timeline-root <dir>` moves both folders elsewhere.
- **Clips are cached across runs, for every provider** (VoxAlta and ElevenLabs),
  in `~/Library/Caches/io.intrusive-memory.Produciesta/`. Each clip is filed under
  the exact request the model got: the text after sentence case and PROJECT.md
  respellings, the `.vox` file's bytes, the direction, settings, model and
  SwiftVoxAlta version, plus which repeat of that line it is. So:
  - re-exporting an unchanged script voices **nothing** (every line reports
    `cached`; the run takes about as long as the render, a minute or so);
  - editing one line re-voices that line; changing one respelling re-voices only
    the lines containing that word; re-casting one `.vox` re-voices only that
    character;
  - a take you have heard and approved stays that take in every later export
    until you change the line or force it;
  - a failed or killed export loses nothing: every clip is cached as it is made,
    so just run the same export again.
  stderr ends with `Clips: N from cache, M voiced, F failed.` — read it to confirm
  what was actually re-voiced.
- **Force a re-render of chosen lines** with `--rerender '<regex>'` (repeatable,
  case-insensitive, matched against `SPEAKER: text`):
  `--rerender 'cy-?mek'`, `--rerender 'VORIAN:'`, `--rerender 'VORIAN:.*father'`.
  The matches are voiced again and their cached takes replaced. `--no-cache`
  voices everything fresh and writes nothing (A/B listening, a suspect cache).
  Inspect or delete takes without exporting:
  `produciesta cache list --provider voxalta --match '<regex>' [--screenplay <path>]`,
  `produciesta cache clear --provider voxalta --match '<regex>'`.
- Capability probe for all of the above: `produciesta export --help | grep -q -- --rerender`.
  If it is absent, the installed binary predates the clip cache (rebuild it with
  `make cli` in Produciesta) and every export voices every line from scratch.
- Provider: VoxAlta is the CLI default — there is no `--provider` flag. Each
  character's voice is the `voices.voxalta` pointer in the cast roster (e.g.
  `voxalta: characters/NARRATOR.dossier/voice/NARRATOR.vox`, or the older
  `voxalta: voices/NARRATOR.vox`).
- Voice files: wherever the pointer says — **never assume `voices/`.** echada
  3.0 writes each `.vox` into the character record
  (`characters/<NAME>.dossier/voice/<NAME>.vox`, exact name with spaces);
  older projects keep `voices/<NAME>.vox`, and those pointers still resolve.
  `echada migrate voices` (dry run; `--apply` to move) migrates the old layout.
- Cast list: `CAST.md` beside `PROJECT.md` on current tooling; older shipped
  binaries read the legacy `cast:` block in `PROJECT.md`'s YAML frontmatter.
- To find a character's voice file:
  `grep -A2 'voxalta:' CAST.md` (paths relative to CAST.md).
- Output of `export` is the **finished, wrapped episode** (intro → body → outro)
  when the brackets are configured (Step 4). There is **no chapter track** — the
  m4a render path does not embed Intro/Episode/Outro markers. If the brackets are
  not configured, you get the body only.
- Add `--json` for NDJSON progress, or `--telemetry` to diagnose voice-routing
  (uncast Elements, narration voiced by a character).
- Generation is slow (full TTS). Run it as a background command and never run
  two Produciesta jobs in parallel.

### Step 5: Verify the Wrap (do NOT run the old hook)

`produciesta export` already wrapped the episode in Step 4b. There is **nothing
to run here** — just verify.

> **⚠️ Do NOT run `.produciesta-hooks/post-generation.sh`.** It is obsolete and
> now actively harmful. The old hook detected "already wrapped" by looking for an
> `Intro` **chapter marker** — but Produciesta's wrapped output has **no chapter
> markers**, so the hook would not recognize it as wrapped and would
> **double-wrap** it (intro + [intro+body+outro] + outro). If a project still has
> that hook file, leave it unrun; ideally delete it so nobody trips on it.

**Verify** the episode is wrapped by checking that the total duration accounts
for intro + body + outro (there are no chapters to inspect anymore):

```bash
# Wrapped duration ≈ intro + body + outro. Compare against the bracket sources.
ffprobe -v quiet -show_entries format=duration -of csv=p=0 audio/episode_XX.m4a
ffprobe -v quiet -show_entries format=duration -of csv=p=0 audio/intro.m4a
ffprobe -v quiet -show_entries format=duration -of csv=p=0 audio/outro.m4a
# Sanity: the wrapped file should be longer than (intro + outro) alone.
# (No chapters: `ffprobe -show_chapters` is now expected to be empty.)
```

**Re-wrapping (e.g. swapping in a new outro)** is trivial now: just change the
bracket source (`audio/outro.m4a` or the `outroFile` key / `outro.fountain`
script) and re-run `produciesta export`. Because resolution reuses existing
bracket audio (render-once), replace the audio file itself — or delete it and
let a sibling `outro.fountain` re-render it — then re-export.

### Step 5b: Transcript (now aligned natively — usually nothing to do)

`produciesta export` writes the WebVTT transcript (`audio/episode_XX.vtt`)
generated **over the wrapped timeline**, so the body cues are already shifted by
the intro length — the VTT lines up with the shipped m4a out of the box. The
old `fix_transcript.py` post-processing step is **obsolete**; do not run it on a
current binary.

**Verify** the transcript is already aligned:

```bash
# First cue should start at ~the intro length (not 00:00:00.000).
head -n 9 audio/episode_XX.vtt
```

**Fallback only.** If you confirmed in Step 4 that the binary is **stale**
(no `--fade-out`, i.e. it produced an unwrapped body that you had to wrap by
hand), and only then, the legacy fixer still exists for that case:

```bash
python3 "$CLAUDE_SKILL_DIR/fix_transcript.py" audio/episode_XX.m4a audio/episode_XX.vtt
# $CLAUDE_SKILL_DIR is this skill's directory; if unset:
# ~/.claude/skills/generate-episode-audio/fix_transcript.py
```

It is idempotent and a no-op against an already-aligned VTT, so it is harmless —
but with a current (bracket-capable) binary you should not need it.

### Step 5c: Drift QA pass + one `--rerender` pass (STANDARD — run on every generation)

Every rendered piece gets an automated audio-drift QA pass before it ships. The
analyzer lives in this skill directory: `qa_drift.py` (numpy-only, no librosa;
~1s per bumper, ~2min per full act).

```bash
python3 "$CLAUDE_SKILL_DIR/qa_drift.py" audio/episode_XX.m4a audio/episode_XX.vtt /path/to/report.json
# exit 0 = OK, exit 2 = significant drift (flags >= max(3, 5% of cues))
```

Per dialogue cue (speaker/timing/text from the sidecar VTT) it measures:
- **pitch_dev** — cue median F0 vs that speaker's own median across the piece
  (flags beyond ±4 semitones). Compares within-piece, NOT against the .vox
  design pitch (synthesis runs sharp of the reference; see memory).
- **trend** — second-half vs first-half F0 on long cues (flags > +2.5 st;
  catches the back-half drift where clone conditioning weakens).
- **rate_z** — robust z-score of chars/sec vs the piece distribution (flags
  |z| > 3.5; catches stretched trail-offs and runaway generations).

**Batch mode (multi-piece episodes): thread the QA behind the render queue.**
Run renders sequentially in one background job; run a second background daemon
that QAs each piece as soon as its `=== OK <piece>` line appears in the render
log, while the next piece renders. Never run QA'd re-renders in parallel with
the main render queue — produciesta stays single-instance.

**Triage the flags with judgment — do not fix blindly:**
- SKIP short emphatic exclamations ("We had no idea!", "MOM!"), sing-song
  deliveries, yells, stammers-as-performance. Big pitch deviation on a short
  line is usually acting, not drift.
- FIX long utterances with within-cue upward drift or sustained deviation:
  insert `[[<breath/>]]` at clause / prepositional-phrase boundaries, add
  Oxford commas to lists, and fix incidental typos the scan surfaces
  (mid-sentence capitals, lowercase "i", comma-vs-period misfits). Follow the
  Editing Safety Protocol — backup, surgical Edits, diff-verify.

**Then do ONE `--rerender` pass over the flagged lines and re-QA.** Do not
re-roll the whole piece: every unflagged line is cached, and its take is the one
that just passed QA, so it must stay. Lines you edited (breath tags, commas,
typos) are new requests and are voiced again on their own. For a flagged line
you did *not* edit, name it with `--rerender`, one pattern per line, anchored on
the speaker and a distinctive phrase:

```bash
produciesta export episodes/episode_XX.fountain --out audio/episode_XX.m4a \
  --project-md PROJECT.md --voices-dir . \
  --rerender 'VORIAN:.*the long way home' --rerender 'NARRATOR:.*harbor lights'
```

Check stderr: `Clips: … M voiced` should equal the number of flagged lines. Then
re-QA. **Max one `--rerender` pass per piece per session** — if lines still come
back significant, report the remaining flags to the user for an ear-check
instead of looping. Never "fix" drift by clearing the whole cache or running
`--no-cache`: that re-rolls every approved take.

### Step 6: Open in QuickTime (always, when rendered)

**Whenever the episode finishes rendering, open it in QuickTime Player** — this is
the standard final step of every run, so the user can immediately hear the
result. Run it on the wrapped `--out` file as soon as `produciesta export`
returns successfully:

```bash
open -a "QuickTime Player" audio/episode_XX.m4a
```

(Open the single episode you just rendered. For a batch render of many episodes,
open the last one rendered rather than launching a window per file.)

## Quick Reference

| Item | Value |
|------|-------|
| Produciesta binary | `~/.local/bin/produciesta` |
| Generate + wrap (one step) | `produciesta export <screenplay> --out <m4a> --project-md PROJECT.md --voices-dir .` |
| Capability probe | `produciesta export --help \| grep -q -- --fade-out` (present ⇒ bracket-capable) |
| Voice provider | `voxalta` (CLI default; no `--provider` flag) |
| Voice files | the `voices.voxalta` pointer in CAST.md (echada 3.0: `characters/<NAME>.dossier/voice/<NAME>.vox`; unmigrated: `voices/<NAME>.vox`) |
| Cast config | `CAST.md` beside `PROJECT.md` (legacy: `PROJECT.md` `cast:`) — at **project root**, pass `PROJECT.md` via `--project-md` |
| Clip cache | `~/Library/Caches/io.intrusive-memory.Produciesta/<provider>/` — persistent, every provider; re-export of unchanged lines voices nothing. `cache status\|list\|prune\|clear [--provider id] [--match re] [--screenplay path]`. VoxAlta: 10 GB LRU, no age limit (PROJECT.md `tts.cache.voxalta.*`) |
| Force lines | `--rerender '<regex>'` on `export` (repeatable, `SPEAKER: text`, case-insensitive); `--no-cache` = voice everything, cache nothing |
| Scratch store | `--cache-dir` is only the per-run working store (wiped each run), not the clip cache |
| Intro/outro settings | `introFile: audio/intro.m4a` / `outroFile: audio/outro.m4a` in PROJECT.md (relative to PROJECT.md dir) |
| Intro/outro audio | `audio/intro.m4a`, `audio/outro.m4a` (or `intro.fountain`/`outro.fountain` next to PROJECT.md to render-once) |
| Wrapping | **automatic inside `export`** — do NOT run `.produciesta-hooks/post-generation.sh` (double-wraps) |
| Master fade-out | `--fade-out <seconds>` (optional clean tail) |
| Chapter markers | **none** (m4a path embeds no Intro/Episode/Outro chapters) |
| Audio output | `audio/episode_XX.m4a` (wrapped) |
| Transcript output | `audio/episode_XX.vtt` (already aligned to the wrapped audio) |
| Drift QA (STANDARD) | `python3 $CLAUDE_SKILL_DIR/qa_drift.py <m4a> <vtt> <report.json>` — exit 2 ⇒ fix flagged lines (breath tags / Oxford commas), ONE `--rerender` pass over the flagged lines, re-QA (Step 5c) |

## Cross-Project Usage

This skill works on any `podcasts/*` project. The project path is the working directory or can be specified explicitly. Each project has its own:
- `PROJECT.md` with the `introFile`/`outroFile` bracket settings (Step 4)
- `CAST.md` with the cast list and voice assignments (legacy projects: the
  `cast:` block in `PROJECT.md`)
- `.vox` files at each member's `voices.voxalta` path — character records
  (`characters/<NAME>.dossier/voice/`) on echada 3.0, a `voices/` folder on
  projects that haven't run `echada migrate voices`
- `audio/intro.m4a` and `audio/outro.m4a` (the bracket audio the keys point at),
  or sibling `intro.fountain`/`outro.fountain` scripts to render-once

Wrapping is now entirely PROJECT.md-driven and happens **inside**
`produciesta export`:
- If a project declares `introFile`/`outroFile` (and the audio exists, or a
  bootstrap script does), export wraps it automatically.
- If a project declares **nothing**, export just produces the episode body —
  wrapping is silently skipped (no error). To enable wrapping for such a project,
  add the keys per Step 4.

Any project that still carries a `.produciesta-hooks/post-generation.sh` should
**not** run it (it double-wraps now); prefer deleting it. The `fix_transcript.py`
helper in this skill directory is retained only as a fallback for an
un-upgraded (non-bracket-capable) binary — on a current binary the VTT is
already aligned and it is unnecessary.
