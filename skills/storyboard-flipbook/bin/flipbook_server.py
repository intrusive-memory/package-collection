#!/usr/bin/env python3
"""Serve a storyboard flipbook locally and save per-panel notes into the project.

    python3 flipbook_server.py <flipbook-dir>
    python3 flipbook_server.py <flipbook-dir> --port 8766 --notes <path/to/notes.json>

Then open http://127.0.0.1:8765/. The folder holds index.html or flipbook.html. Notes are written to
notes.json (or the --notes file), keyed by panel id, so they survive rebuilding the flipbook and re-rendering panels. It goes
next to a folder named `flipbook`, and otherwise inside the folder served:

    {"t05": {"note": "Make the temple feel bigger.", "updatedAt": "2026-11-01T18:00:00Z"}}

Listens on this machine only. An empty note removes the entry. Pages and images are sent with
Cache-Control: no-cache, and audio supports Range requests so the audio sequence view can seek.
"""
import argparse
import datetime
import functools
import json
import os
import re
import tempfile
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
MAX_BODY = 64 * 1024
lock = threading.Lock()


def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def save_note(path, panel, text):
    with lock:
        notes = load(path)
        if text.strip():
            notes[panel] = {"note": text, "updatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        else:
            notes.pop(panel, None)
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".notes-", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(notes, f, indent=2, sort_keys=True, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, path)


class Handler(SimpleHTTPRequestHandler):
    notes_path = None
    page = "index.html"

    def end_headers(self):
        # Re-rendered panels keep their file names, so make the browser check for a new copy every time.
        if not self.path.startswith("/api/"):
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def local_only(self):
        """Refuse requests a web page on another site could send to this port."""
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0]
        origin = self.headers.get("Origin")
        ok_origin = origin is None or re.match(r"^http://(127\.0\.0\.1|localhost)(:\d+)?$", origin)
        return host in ("127.0.0.1", "localhost") and ok_origin

    def send_json(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.local_only():
            return self.send_error(403)
        if self.path == "/api/notes":
            return self.send_json(200, load(self.notes_path))
        wanted = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range") or "")
        path = self.translate_path(self.path)
        if wanted and os.path.isfile(path):  # browsers need this to seek in audio
            size = os.path.getsize(path)
            start = int(wanted.group(1))
            end = min(int(wanted.group(2)), size - 1) if wanted.group(2) else size - 1
            if start > end:
                return self.send_error(416)
            self.send_response(206)
            self.send_header("Content-Type", self.guess_type(path))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.send_header("Content-Length", str(end - start + 1))
            self.end_headers()
            with open(path, "rb") as f:
                f.seek(start)
                left = end - start + 1
                while left > 0:
                    chunk = f.read(min(1 << 20, left))
                    if not chunk:
                        break
                    try:
                        self.wfile.write(chunk)
                    except (BrokenPipeError, ConnectionResetError):
                        return None
                    left -= len(chunk)
            return None
        if self.path == "/" and self.page != "index.html":
            self.path = "/" + self.page
        return super().do_GET()

    def do_POST(self):
        if not self.local_only():
            return self.send_error(403)
        if self.path != "/api/notes":
            return self.send_error(404)
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= MAX_BODY:
            return self.send_error(413)
        try:
            data = json.loads(self.rfile.read(length))
            panel, note = data["id"], data["note"]
        except (ValueError, KeyError, TypeError):
            return self.send_error(400)
        if not isinstance(note, str) or not isinstance(panel, str) or not ID_RE.match(panel):
            return self.send_error(400)
        save_note(self.notes_path, panel, note)
        self.send_json(200, {"ok": True})

    def log_message(self, *args):
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("flipbook", type=Path)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--notes", type=Path, help="notes file, when it isn't beside the flipbook")
    args = ap.parse_args()
    root = args.flipbook.resolve()
    pages = [p for p in ("index.html", "flipbook.html") if (root / p).exists()]
    if not pages:
        raise SystemExit(f"no index.html or flipbook.html in {root}")
    Handler.page = pages[0]
    Handler.notes_path = args.notes.resolve() if args.notes else (root.parent if root.name == "flipbook" else root) / "notes.json"
    server = ThreadingHTTPServer(("127.0.0.1", args.port), functools.partial(Handler, directory=str(root)))
    print(f"http://127.0.0.1:{args.port}/  notes: {Handler.notes_path}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
