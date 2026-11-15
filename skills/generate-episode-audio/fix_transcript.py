#!/usr/bin/env python3
"""Build the COMPLETE WebVTT transcript for a WRAPPED episode.

Produciesta's `export` writes a BODY-ONLY VTT next to the audio: cues are
relative to the unwrapped body (first cue ~00:00:00) and it carries a trailing
"FADE OUT." cue. After the intro/outro wrap, the shipped m4a is

    intro + body + outro          (chapters: Intro / Episode / Outro)

so a *complete* transcript — one that covers the whole wrapped file, including
the spoken intro and outro — must:

  1. Prepend the INTRO cues (audio/intro.vtt) at the Intro chapter (offset 0).
  2. Shift the BODY cues by the Intro chapter length (Episode chapter start).
  3. Append the OUTRO cues (audio/outro.vtt) at the Outro chapter start.
  4. Drop any "FADE OUT." cue, sort by start time, and renumber.

The intro/outro VTTs must already exist next to their .m4a — they come from the
same `produciesta export` that produced audio/intro.m4a / audio/outro.m4a. If
the episode is wrapped but a transcript is MISSING, this script EXITS NONZERO
with a clear flag (`error[missing-intro-outro-vtt]`) so they get regenerated. It
will NOT silently ship a transcript that omits the intro/outro text.

All offsets are read from the wrapped m4a's chapters (ffprobe), so they adapt to
any intro/outro length and to projects with different intros.

IDEMPOTENT: a merged VTT carries a `NOTE produciesta-wrapped` marker in its
header; re-running detects it and makes no change. A fresh `produciesta export`
clobbers the VTT back to body-only (no marker), so the next run re-merges.

Usage:
    python3 fix_transcript.py <wrapped.m4a> <body_transcript.vtt>
"""

import os
import re
import subprocess
import sys

TS_RE = re.compile(r"(\d{2}:\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}:\d{2}\.\d{3})")
MARKER = "NOTE produciesta-wrapped"


def to_ms(ts):
    h, m, rest = ts.split(":")
    s, ms = rest.split(".")
    return ((int(h) * 60 + int(m)) * 60 + int(s)) * 1000 + int(ms)


def to_ts(ms):
    ms = max(0, ms)
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"


def chapters(m4a):
    """Return {title_lower: (start_ms, end_ms)} from the wrapped m4a."""
    out = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "csv",
         "-show_chapters", m4a],
        capture_output=True, text=True,
    ).stdout
    ch = {}
    for line in out.splitlines():
        f = line.split(",")
        # csv: chapter,id,timebase,start,start_time,end,end_time,title
        if len(f) >= 8 and f[0] == "chapter":
            title = f[-1].strip().lower()
            start = int(round(float(f[4]) * 1000))
            end = int(round(float(f[6]) * 1000))
            ch[title] = (start, end)
    return ch


def read_cues(path):
    """Parse a VTT into [(start_ms, end_ms, [text_lines]), ...].

    Drops cue indices (renumbered later) and any "FADE OUT" cue.
    """
    with open(path) as f:
        text = f.read()
    cues = []
    for block in text.split("\n\n"):
        if "-->" not in block:
            continue
        start = end = None
        body = []
        for ln in block.strip("\n").splitlines():
            mobj = TS_RE.search(ln)
            if mobj:
                start, end = to_ms(mobj.group(1)), to_ms(mobj.group(2))
            elif re.fullmatch(r"\d+", ln.strip()):
                continue  # old cue index — renumber below
            else:
                body.append(ln)
        if start is None:
            continue
        if any("fade out" in t.lower() for t in body):
            continue
        cues.append((start, end, body))
    return cues


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: fix_transcript.py <wrapped.m4a> <body_transcript.vtt>")
    m4a, vtt = sys.argv[1], sys.argv[2]

    ch = chapters(m4a)
    if "intro" not in ch:
        print(f"skip: {m4a} has no Intro chapter (not wrapped) — leaving {vtt} as-is")
        return

    # Idempotency: a previously-merged VTT carries the marker.
    with open(vtt) as f:
        existing = f.read()
    if MARKER in existing:
        print(f"already merged: {vtt} — no change")
        return

    audio_dir = os.path.dirname(os.path.abspath(m4a))
    intro_vtt = os.path.join(audio_dir, "intro.vtt")
    outro_vtt = os.path.join(audio_dir, "outro.vtt")
    has_outro = "outro" in ch

    intro_end = ch["intro"][1]                       # Intro END == Episode START
    outro_start = ch["outro"][0] if has_outro else None  # Outro START

    # Merge whatever transcripts are present. The skill workflow regenerates any
    # missing intro/outro .vtt (from its screenplay) *before* calling this, so by
    # the time we run they should both exist. If one is still absent we degrade
    # quietly — merge what we have and note the gap — rather than failing the wrap.
    have_intro = os.path.isfile(intro_vtt)
    have_outro = has_outro and os.path.isfile(outro_vtt)
    skipped = []
    if not have_intro:
        skipped.append(os.path.basename(intro_vtt))
    if has_outro and not have_outro:
        skipped.append(os.path.basename(outro_vtt))

    intro_cues = read_cues(intro_vtt) if have_intro else []
    body_cues = read_cues(vtt)
    outro_cues = read_cues(outro_vtt) if (have_outro and outro_start is not None) else []

    merged = []
    merged += [(s, e, t) for (s, e, t) in intro_cues]                          # offset 0
    merged += [(s + intro_end, e + intro_end, t) for (s, e, t) in body_cues]
    merged += [(s + outro_start, e + outro_start, t) for (s, e, t) in outro_cues]

    merged.sort(key=lambda c: c[0])

    lines = ["WEBVTT", "",
             f"{MARKER}: intro + body + outro merged, chapter-aligned", ""]
    for i, (s, e, t) in enumerate(merged, 1):
        lines.append(str(i))
        lines.append(f"{to_ts(s)} --> {to_ts(e)}")
        lines.extend(t)
        lines.append("")
    result = "\n".join(lines).rstrip() + "\n"
    with open(vtt, "w") as f:
        f.write(result)

    print(
        f"merged {vtt}: {len(merged)} cues "
        f"(intro {len(intro_cues)}, "
        f"body {len(body_cues)} +{intro_end}ms, "
        f"outro {len(outro_cues)}"
        + (f" +{outro_start}ms" if outro_start is not None else "")
        + ")"
        + (f"  [note: {', '.join(skipped)} absent — regenerate for full coverage]"
           if skipped else "")
    )


if __name__ == "__main__":
    main()
