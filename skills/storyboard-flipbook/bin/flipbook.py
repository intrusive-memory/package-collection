#!/usr/bin/env python3
"""Build flipbook.html next to a storyboard plan's rendered frames and open it through its notes server.

    flipbook.py <plan.json> [--no-open]

Frames that haven't rendered yet appear as a labelled placeholder. Every frame has a notes box; notes
save to notes.json beside the frames, keyed by frame id. --no-open only builds the page.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
import zlib


def serve(folder, here):
    """A local notes server for this folder: reuse a running one, else start it detached."""
    port = 8770 + zlib.crc32(os.path.abspath(folder).encode()) % 200
    url = f"http://127.0.0.1:{port}/"
    try:
        urllib.request.urlopen(url + "api/notes", timeout=1)
        return url
    except OSError:
        pass
    subprocess.Popen([sys.executable, os.path.join(here, "flipbook_server.py"), folder, "--port", str(port)],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    for _ in range(20):
        try:
            urllib.request.urlopen(url + "api/notes", timeout=1)
            return url
        except OSError:
            time.sleep(0.25)
    sys.exit(f"the notes server did not start on {url}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    plan = json.load(open(sys.argv[1], encoding="utf-8"))
    gen = os.path.join(plan["project"], "characters", ".generations", "scenes", plan["slug"])
    frames = []
    for number, frame in enumerate(plan["frames"], 1):
        present = bool(frame.get("file")) and os.path.isfile(os.path.join(gen, frame["file"]))
        frames.append({
            "id": frame.get("id") or f"frame-{number:02d}",
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
        url = serve(gen, here)
        print(url)
        subprocess.run(["open", url])


if __name__ == "__main__":
    main()
