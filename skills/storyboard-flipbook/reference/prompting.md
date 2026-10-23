---
type: reference
title: Writing storyboard prompts for Vinetas
---

# Writing storyboard prompts for Vinetas (FLUX.2 Klein 4B)

What follows was learned on Granville's Bone-N-Brew and kitchen scenes,
2026-10-03/04. The model follows a prompt loosely: it is good at people and
rooms and unreliable at counts, hands and "no X". The rules below raise the
odds; they don't guarantee anything, which is why every frame gets looked at.

## Shape of a frame prompt

Write plain declarative sentences in this order. Share the room, character
and closing blocks word for word across all N frames so only the action
changes.

1. **Room.** One paragraph describing the place, taken from
   `locations/<place>.md`, ending with the photographic style ("Photorealistic,
   35mm, shallow depth of field."). Start it with the head count: "just two
   people in the whole room and no one else".
2. **Room reference.** "The room is the empty room shown in {ref:room}, now
   with these two men in it."
3. **Camera.** One sentence: the shot size and where the camera stands
   ("A wide shot down the length of the room, taken from the customer side
   of the bar.").
4. **Each person**, one at a time: where they are, "the man from
   {ref:NAME}", a physical description, what they wear, then what each of
   their hands is doing.
5. **Props** the beat needs, each with a stated place.
6. **Closing block:** the anatomy line, the head count again, the no-text
   line.

## People

- **Describe them and reference them.** Use `{ref:NAME}` *and* a written
  description from CHARACTER.md's Appearance (age, build, hair, beard,
  skin). The reference carries the face; the words carry everything else.
- **Clothed, in their recorded wardrobe.** Reference portraits are shirtless
  by convention; a scene shows the Wardrobe section's everyday clothes
  unless the script says otherwise.
- **Say each person once.** Never describe a character in two places in one
  prompt ("further down the bar stands…" after an earlier mention): that is
  how a second copy of them appears.
- **Distinguishing marks need a fence.** If one character is tattooed and
  another isn't, give the bare one "bare, untattooed forearms" where their
  arms are described, and close with "Only <role> has tattoos." Tattoos
  bleed across people otherwise. Describe tattoos as texture, with "no
  faces, no figures, no lettering".
- **A small background figure gets no reference.** If a character is only a
  distant, out-of-focus figure in a frame, leave them out of that frame's
  `characters` and describe them in a clause ("far away at the other end of
  the bar, small and out of focus, … seen only once"). Passing their
  portrait makes the model draw them large.
- **Ages run young.** Klein draws a stated "25" as a teenager. Aim the
  prompt a few years older than the record.

## Hands and arms

- **Give every hand one simple job and say it.** "His right hand presses the
  folded towel flat against the bar top; his left hand rests flat on the
  bar." Hands the prompt doesn't place are the ones that come out wrong or
  multiplied.
- **Never split one object between two hand descriptions** ("holds the strap
  at his chest" plus a bag "at his hip" produced a third hand). One hand per
  object: "His left hand grips the top of the bag at his hip. His right arm
  hangs at his side with the hand empty and open."
- **Close with the anatomy line:** "Each man has exactly two arms and two
  hands; each hand has five fingers with natural proportions, and the wrists
  and forearms join naturally. No extra fingers, no extra hands, no extra
  arms, no wristwatch, no rings."
- **Hide hands you don't need.** An over-the-shoulder or closer shot that
  crops a person's hands out is more reliable than describing them.
- More steps did not help: 12 steps gave worse hands than 8 and took twice
  as long. Stay at 8.

## Staging

- **Pin people to furniture by construction.** "Behind the bar" alone puts
  the bartender on the customer side about half the time. Write: "standing
  behind the bar, on the far side of the counter, between the bar and the
  back-bar shelves, with the counter hiding him from the waist down".
- **Name the camera's side of things** ("taken from the customer side").
- If the plate shows a closed door and the beat needs it open, say so in the
  frame.

## The room

- **Render the room empty first** (the plate) and pass it as `{ref:room}` to
  every frame. This is what keeps the set the same across the sequence.
- **Never pass a finished frame as a reference.** The model reproduces the
  whole picture, people and poses included, and ignores the new action.
- **The plate's flaws are inherited.** A framed picture in the plate is in
  every frame. Fix the plate, not the frames.
- **Bans that work, bans that don't.** `--negative` is ignored entirely, so
  absences go in the prompt. Removing the cause works better than banning
  the effect: say the shelves hold "only rows of clean drinking glasses"
  rather than "bottles with no labels"; say walls are "completely bare from
  floor to ceiling, plain clean brick and nothing else on them". Then still
  close with the no-text line: "No bottles, no pictures, no picture frames,
  no signs, no posters, no chalkboards, no labels, no text or lettering
  anywhere in the image."
- **Anything that could carry writing** (a notebook page, a sign, a label)
  needs its content stated: "its page showing a simple pencil drawing of two
  otters and no words".

## Telling the story across frames

- Each frame is a different moment with a different action; don't restage
  the same pose.
- Carry props forward by name and state ("his worn olive canvas messenger
  bag, closed, on the stool beside him" → "lies open with the flap thrown
  back"). Use the same descriptive phrase for a prop in every frame.
- Vary the camera to suit the beat: wide to arrive, medium to talk, close on
  the detail that matters.
- Keep expressions specific to the beat and to the character's Personality
  section.

## Failure table

| What you see | Change |
|---|---|
| Extra person, or a character twice | Describe each person once; remove the reference for a background figure; restate "Exactly two people in the image: X and Y." |
| Three hands on someone | Find the object or action split across two hand descriptions and give it to one hand; or crop the hands out with the camera |
| Bartender on the wrong side of the bar | The "far side of the counter… hiding him from the waist down" wording; or an over-the-shoulder shot from the customer |
| One character's tattoos on another | "bare, untattooed forearms" at the arms; "Only <role> has tattoos." |
| Pictures or signs on walls | Fix the plate; name each banned thing |
| Labels and pseudo-text on bottles | Take the bottles out of the room description |
| Frame looks like a copy of another frame | A finished frame was used as a reference; use the plate |
| A stray watch, ring or wristband | Add it to the anatomy line by name |
| Render dies with a Metal "Impacting Interactivity" error | macOS killed it for GPU contention; `render.py` retries once. Re-run when the machine is quieter. |
| Hair or eye colour drifts from the record | Known and not fixed by wording (grey for chestnut, hazel for brown). Report it. |
