---
type: skill
name: storyboard-flipbook
description: Turn one or more vague scene prompts into a flipbook of N storyboard frames that tell the scene's story, using the characters' reference portraits so they stay on-model. The request says how many storyboards to make (default 3). Use whenever the user asks for a "storyboard flipbook", "flipbook", "storyboard this scene", "storyboards for the scene where…", "N storyboards of…", or wants a sequence of images of cast characters in a scene from a screenplay project. Works in any project with a CAST.md and `.dossier` character bundles (characters/<NAME>.dossier/manifest.json with a selected portrait; dossier-format). Every character in the scene must be in CAST.md and must already have a reference portrait; the skill stops and says who is missing otherwise.
---

# Storyboard Flipbook

Take the user's **vague scene prompts**, ground them in the project's script,
write **N related image prompts** that tell the scene's story in order,
render them as storyboard frames with the cast's reference portraits, and
build an HTML flipbook to step through them.

`S` below is this skill's folder. `P` is the project folder (the one holding
`CAST.md`).

## Input

- **Vague scene prompts:** one or more, in any form ("Archer orders a drink
  and Shane is bartending"). They can be one per frame, or one line for the
  whole scene.
- **How many storyboards:** the number in the request ("5 storyboards",
  `/storyboard-flipbook 5 …`). **The request decides the count.** If it gives
  none, make **3** and say so.
- Optional: "prompts only" (stop after step 4), a seed, a title.

Mapping prompts to frames: if there are as many prompts as frames, it's one
frame each. Fewer prompts than frames: split the action into more beats.
More prompts than frames: merge neighbours. Either way the N frames are one
continuous scene, in order, each a different moment.

## Hard rules

1. **Cast only.** Every person in every frame is a `character:` in `P/CAST.md`.
   No invented people and no background extras.
2. **Reference portraits must exist.** Every character in the scene has a
   record with a selected portrait. Run preflight (step 2). If anyone is
   missing, **stop**, name them and the reason, and build nothing. Don't
   substitute a described-only character.
3. **At most three reference images per frame.** That's two characters plus
   the empty room, or three characters and no room. A beat with four or more
   characters has to be split across frames or cut down; say so.
4. **The count is what was asked for.** Don't add or drop frames.
5. Results go in `P/characters/.generations/scenes/<slug>/` (untracked
   candidates). Never write into a character's `images/`.

## Workflow

### 1. Read the request

Work out N, the list of vague prompts, the characters named or implied, and
the place. Pick a short kebab-case `slug` for the scene.

### 2. Preflight the cast

```bash
python3 "$S/bin/preflight.py" "$P" SHANE ARCHER
```

Exit 0 prints each character's portrait and `CHARACTER.md`. Exit 1 lists who
is missing and why: stop there and tell the user. Building a missing
portrait is Personaje's job (its `docs/RUNBOOK.md`), not this skill's.

### 3. Ground the scene in the script

- Find the scene. Search `P/episodes/*.fountain` (in `PROJECT.md`
  `filePattern` order) for the characters and the place, and read the whole
  scene: action lines, parentheticals, what happens before and after.
- Read `P/locations/<place>.md` for the set.
- Read each character's `CHARACTER.md`: **Appearance** and **Wardrobe** are
  what they look like and wear; **Canon & Guardrails** are limits to obey.
- The script outranks the vague prompt on facts (who is there, what they
  hold, time of day). The vague prompt outranks the script on what to show.
  If they contradict each other, say so and follow the user's prompt.
- If the scene isn't in the script, say so, and build it from the vague
  prompts, the location file and the character records.

### 4. Write the plan

Break the scene into N beats, then write one prompt per beat following
[`reference/prompting.md`](reference/prompting.md). Read that file first: it
holds the wording that works and the failures it prevents. Save the plan as
`P/characters/.generations/scenes/<slug>/plan.json`:

```json
{
  "title": "Archer at the Bone-N-Brew",
  "subtitle": "episode_1_05…fountain:76–110 · ARCHER, SHANE",
  "slug": "bnb-archer-orders",
  "project": "/absolute/path/to/P",
  "count": 3,
  "plate": { "prompt": "The empty interior of …, with no people in it at all. …" },
  "frames": [
    {
      "title": "Archer walks in",
      "caption": "One or two plain sentences: what happens in this frame.",
      "characters": ["SHANE", "ARCHER"],
      "prompt": "… is the man from {ref:SHANE}, the bartender: … is the man from {ref:ARCHER}: … The room is the empty room shown in {ref:room} …"
    }
  ]
}
```

- `count` must equal the number of frames.
- `{ref:NAME}` and `{ref:room}` become "the first reference image" and so
  on at render time, in the order the frame lists its characters, room last.
  Always use the tokens; never write the ordinal yourself.
- `plate` is the empty room. Leave it out only for a scene with no fixed
  place. A frame can opt out with `"plate": false`.
- Optional per plan: `width`, `height` (default 2144×1200), `steps` (8),
  `model` (`klein4b`), `style`. Optional per frame and plate: `seed`.

Then **show the user the N prompts** (title, caption, prompt). If they asked
for prompts only, stop here.

### 5. Render

Tell the user how long it will take before starting. Measured on Klein 4B at
8 steps, 2144×1200, on a 32 GB machine: the plate takes about 4 minutes, a
frame with two reference images about 10, and a frame with three (two
characters plus the room) about 15. So three two-character frames with a
plate is roughly 50 minutes. Run it in the background.

```bash
python3 "$S/bin/render.py" "$PLAN" --only plate      # the empty room first
```

Look at the plate. It must have no people, pictures, signs or text, and
room for a person behind any counter. Every flaw in it is inherited by every
frame, so re-render it (`--only plate --seed <new>`) until it's clean.

```bash
python3 "$S/bin/render.py" "$PLAN"                   # all frames
python3 "$S/bin/render.py" "$PLAN" --only 2 --seed 41   # one frame again
python3 "$S/bin/render.py" "$PLAN" --dry-run         # print composed prompts only
```

Each result opens in Preview and is recorded in the plan.

### 6. Check every frame

Look at each rendered frame yourself and check:

- the head count is exactly the frame's characters, each appearing once
- every hand: count per person, fingers, nothing extra (watches, rings)
- everyone is where the prompt put them (behind the bar, in the doorway)
- no text, signs, pictures or labels
- props the beat needs are visible

Re-render a failed frame on a new seed, changing the prompt for the specific
failure (see the failure table in `reference/prompting.md`). **At most two
re-renders per frame**, then keep the best one and report what's still
wrong. Never claim a frame is clean that you haven't looked at.

### 7. Build the flipbook

```bash
python3 "$S/bin/flipbook.py" "$PLAN"
```

Writes and opens `flipbook.html` beside the frames. Re-run it after any
re-render. Frames that haven't rendered show as placeholders.

### 8. Report

Say where the flipbook is, then for each frame what's right and what's
still wrong, plainly. Include the script lines the scene came from.

## Requirements

- macOS on Apple Silicon, `python3`, and a signed Vinetas CLI whose
  `generate` accepts `--reference` (SwiftVinetas 0.21.0 or later).
  `render.py` finds one (`$VINETAS_CLI`, `/Applications/Vinetas.app`, then a
  DerivedData build) and stops with a message if none qualifies.
- The Vinetas Pro unlock for FLUX.2 models. If the CLI reports the unlock is
  invalid, stop and tell the user; don't work around it.
- The `vinetas-cli` skill's wrapper, if present, is used to launch the CLI.
