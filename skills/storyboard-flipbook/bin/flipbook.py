#!/usr/bin/env python3
"""Build flipbook.html next to a storyboard plan's rendered frames.

    flipbook.py <plan.json> [--no-open]

Frames that haven't rendered yet appear as a labelled placeholder.
"""
import json
import os
import subprocess
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    plan = json.load(open(sys.argv[1], encoding="utf-8"))
    gen = os.path.join(plan["project"], "characters", ".generations", "scenes", plan["slug"])
    frames = []
    for number, frame in enumerate(plan["frames"], 1):
        present = bool(frame.get("file")) and os.path.isfile(os.path.join(gen, frame["file"]))
        frames.append({
            "file": frame["file"] if present else None,
            "title": frame.get("title", f"Frame {number}"),
            "text": frame.get("caption", ""),
            "note": frame.get("note") or (None if present else "not rendered yet"),
        })
    here = os.path.dirname(os.path.abspath(__file__))
    page = open(os.path.join(here, "..", "assets", "flipbook.html"), encoding="utf-8").read()
    page = (page.replace("__TITLE__", plan.get("title", plan["slug"]))
                .replace("__SUBTITLE__", plan.get("subtitle", plan.get("source", "")))
                .replace("__ASPECT__", f"{plan.get('width', 2144)}/{plan.get('height', 1200)}")
                .replace("__FRAMES__", json.dumps(frames, indent=2)))
    out = os.path.join(gen, "flipbook.html")
    os.makedirs(gen, exist_ok=True)
    open(out, "w", encoding="utf-8").write(page)
    print(out)
    if "--no-open" not in sys.argv:
        subprocess.run(["open", out])


if __name__ == "__main__":
    main()
