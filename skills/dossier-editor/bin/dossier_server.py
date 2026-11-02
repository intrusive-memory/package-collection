#!/usr/bin/env python3
"""Serve the dossier pages locally, with controls to add and delete a character's looks.

    python3 <skill>/bin/dossier_server.py [--project <dir>] [--port 8767]

The project is the folder holding CAST.md, and defaults to the current one. See SKILL.md for what it needs.

Then open http://127.0.0.1:8767/. Describe a look in the text box and it goes to the compiled Vinetas
CLI, with the character's face and portrait as references, on the model set in IMAGE_PROVIDER.md (or the
Provider menu in the form). A new look is rebuilt into the .dossier: image, manifest and page. Cloud models
bill for each image.

The editor exists only in the page this server sends. DOSSIER-FORMAT §11 forbids a script that makes a
request in the bundle's own page, so the file on disk, which Escribir shows, lists the looks read-only.

The Voice section's prompt is also editable there. Editing it makes TAKES new voices on this Mac, each speaking
the character's sample line, in .generations/<NAME>/voice-takes/. Nothing else changes until you pick one. Using
a take finishes its .vox, replaces the voice, renders the samples again and writes the prompt to CAST.md. The
replaced voice goes to .generations/<NAME>/voice-history/ and can be restored. Episodes already rendered keep
the old voice until they're rendered again.

Looks are stored as `view` assets with a look-* variant, because v2 retired the `wardrobe` kind. Their
sources are characters/.generations/<NAME>/view-look-*-r<n>.{png,json}, which assemble picks up. Deleting
moves the source to .generations/<NAME>/deleted-looks/, so a paid-for image can be recovered by hand.

Listens on this machine only. API keys come from the environment or the keychain, go only into the CLI's
environment, and are never logged.
"""
import argparse
import base64
import datetime
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote, unquote

_early = argparse.ArgumentParser(add_help=False)
_early.add_argument("--project", type=Path, default=Path.cwd())
PROJECT = _early.parse_known_args()[0].project.resolve()
if not (PROJECT / "tools/build_dossiers.py").exists() or not (PROJECT / "tools/render_dossier_pages.py").exists():
    sys.exit(f"{PROJECT} has no tools/build_dossiers.py and tools/render_dossier_pages.py. See SKILL.md, Requirements.")
sys.path.insert(0, str(PROJECT / "tools"))
import build_dossiers as bd  # noqa: E402

sys.path.insert(0, str(Path.home() / "Projects/apps/Personaje/tools"))
import dossier_update  # noqa: E402

ROOT = bd.ROOT
CHARS = bd.CHARS
GEN = bd.GEN
PERSONAJE = Path.home() / "Projects/apps/Personaje"
WRAPPER = Path.home() / ".claude/skills/vinetas-cli/bin/vinetas"
CONFIG = ROOT / "IMAGE_PROVIDER.md"  # the model: line picks the model for new looks
TAKES = 3
MAX_HISTORY = 10
REFERENCES_NEEDED = 2  # the face and the portrait; fewer and the character drifts
DEFAULT_FRAMING = "The whole figure is in frame from head to toe, on the same plain flat background color as the portrait, in the same art style."
PROVIDER_KEYS = {"google": "GEMINI_API_KEY", "openai": "OPENAI_API_KEY", "bfl": "BFL_API_KEY", "stability": "STABILITY_API_KEY"}
MAX_DESCRIPTION = 2000
MAX_BODY = 16 * 1024
ASSETS = Path(__file__).resolve().parent.parent / "assets"
EDITOR = ASSETS / "dossier_editor.html"
STOP = {"a", "an", "and", "the", "of", "with", "in", "on", "for", "to", "that", "very", "slightly", "her", "his", "their"}

jobs = {}
jobs_lock = threading.Lock()
pool = ThreadPoolExecutor(max_workers=3)
voice_pool = ThreadPoolExecutor(max_workers=1)  # on-device models; one at a time
locks = {}


def name_lock(name):
    with jobs_lock:
        return locks.setdefault(name, threading.RLock())


def characters():
    return sorted(p.name[:-len(".dossier")] for p in CHARS.glob("*.dossier"))


def locate_cli():
    """$VINETAS_CLI, else the newest compiled build of the main checkout. The installed app can lag behind
    and older builds refuse reference images on cloud models."""
    env = os.environ.get("VINETAS_CLI")
    if env:
        return env
    best = None
    for d in (Path.home() / "Library/Developer/Xcode/DerivedData").glob("Vinetas-*"):
        wp = subprocess.run(["plutil", "-extract", "WorkspacePath", "raw", str(d / "info.plist")], capture_output=True, text=True).stdout
        if "/worktrees/" in wp or not wp.strip().endswith("Vinetas.xcodeproj"):
            continue
        for cfg in ("Release", "Debug"):
            c = d / f"Build/Products/{cfg}/Vinetas.app/Contents/MacOS/VinetasCLI"
            if c.exists() and (best is None or c.stat().st_mtime > best.stat().st_mtime):
                best = c
    if not best:
        raise RuntimeError("no compiled Vinetas build found; set VINETAS_CLI")
    return str(best)


def cli_env():
    """The CLI only sees keys in its environment, so hand it the ones saved in Vinetas's keychain item."""
    env = dict(os.environ, VINETAS_CLI=locate_cli())
    for provider, var in PROVIDER_KEYS.items():
        if not env.get(var):
            r = subprocess.run(["security", "find-generic-password", "-s", bd.KEYCHAIN_SERVICE, "-a", provider, "-w"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                env[var] = r.stdout.strip()
    return env


def current_model():
    return re.search(r"^model:\s*(\S+)\s*$", CONFIG.read_text(encoding="utf-8"), re.M)[1]


def available_models():
    r = subprocess.run([str(WRAPPER), "list", "--json"], capture_output=True, text=True, env=cli_env(), check=True)
    data = json.loads(r.stdout)
    out = []
    for m in data if isinstance(data, list) else data["models"]:
        refs = m.get("maxReferenceImages", 0)
        why = ""
        if refs < REFERENCES_NEEDED:
            why = "can't use reference images"
        elif m.get("cloud") and not m.get("configured"):
            why = "no API key"
        elif not m.get("cloud") and m.get("requiresPro") and not m.get("isUnlocked"):
            why = "needs the Vinetas Pro unlock"
        elif not m.get("cloud") and not m.get("isDownloaded"):
            why = "not downloaded"
        out.append({"model": m["model"], "name": m["name"], "provider": m.get("provider", "on this Mac"),
                    "price": m.get("pricingHint", "free" if not m.get("cloud") else ""), "usable": not why, "why": why})
    return out


def set_model(model):
    with jobs_lock:
        text = CONFIG.read_text(encoding="utf-8")
        CONFIG.write_text(re.sub(r"^model:.*$", f"model: {model}", text, count=1, flags=re.M), encoding="utf-8")


def slug_for(name, description):
    words = [w for w in re.findall(r"[a-z0-9]+", description.lower()) if w not in STOP][:4] or ["look"]
    base = "-".join(words)
    taken = {p.stem for p in (GEN / name).glob("view-look-*")} | {p.stem for p in (GEN / name / "deleted-looks").glob("view-look-*")}
    slug, n = base, 2
    while f"view-look-{slug}-r1" in taken:
        slug, n = f"{base}-{n}", n + 1
    return slug


def compose(name, description):
    subject = bd.PICKS[name]["subject"]
    refs = [(p, role) for p, role in ((bd.face_path(name), "face"), (bd.portrait_path(name), "portrait")) if p.exists()]
    which = ("The first image is a close-up of this " + subject + "'s face; the second is the full portrait, for reference only."
             if len(refs) == 2 else "The image is this " + subject + "'s full portrait, for reference only.")
    prompt = (f"Edit this image. {which} Keep the same {subject} exactly: the same face, features, skin, hair and build. Dress them in this "
              f"look, replacing whatever they wear in the reference and keeping nothing of it: {description} {framing_for(name)} {bd.NO_MARKS}")
    return f"{style_for(name)}. {prompt}", prompt, refs


def style_for(name):
    """The project's `style_for(name)` if it has one, so a character's own art style wins, else its STYLE."""
    return bd.style_for(name) if hasattr(bd, "style_for") else bd.STYLE


def framing_for(name):
    """The project's LOOK_FRAMING if it has one. References differ by project: a look can't assume how they're shot."""
    return getattr(bd, "LOOK_FRAMING", DEFAULT_FRAMING)


def rebuild(name, label):
    """Re-assemble the bundle and its page, holding the update marker so Escribir reloads."""
    py = PERSONAJE / ".venv/bin/python"
    script = (f'"{py}" "{ROOT}/tools/build_dossiers.py" assemble "$1" && "{py}" "{ROOT}/tools/render_dossier_pages.py" "$1"')
    r = subprocess.run([str(py), str(PERSONAJE / "tools/dossier_update.py"), "run", str(CHARS / f"{name}.dossier"), "--label", label, "--",
                        "bash", "-c", script, "rebuild", name], capture_output=True, text=True, cwd=ROOT)
    if r.returncode:
        raise RuntimeError(f"rebuild failed: {(r.stderr or r.stdout).strip()[-300:]}")


def generate(job_id, name, description, model):
    set_job(job_id, state="generating")
    try:
        composed, prompt, refs = compose(name, description)
        env = cli_env()
        io_dir = subprocess.run([str(WRAPPER), "info", "--print-io-dir"], capture_output=True, text=True, check=True, env=env).stdout.strip()
        work = Path(io_dir) / f"look-{job_id}"
        work.mkdir(parents=True)
        try:
            cmd = [str(WRAPPER), "generate", composed, "-o", str(work / "look.png"), "--model", model, "--aspect", "portrait"]
            for i, (path, _) in enumerate(refs):
                staged = work / f"ref{i}.png"
                shutil.copy2(path, staged)
                cmd += ["-r", str(staged)]
            started = time.time()
            r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=300)
            if r.returncode or not (work / "look.png").exists():
                why = {65: "The provider's filter refused this description. Reword it and try again.", 78: f"No API key reached the CLI for {model}.",
                       69: "The provider's service failed. Try again later."}.get(r.returncode, (r.stderr or r.stdout).strip()[-300:])
                raise RuntimeError(why)
            meta = json.loads((work / "look.json").read_text())
            with name_lock(name):
                slug = slug_for(name, description)
                out = GEN / name / f"view-look-{slug}-r1.png"
                shutil.copy2(work / "look.png", out)
                out.with_suffix(".json").write_text(json.dumps({
                    "kind": "view", "variant": f"look-{slug}", "description": description, "prompt": prompt, "composedPrompt": composed,
                    "provider": "vinetas", "model": meta.get("model", model), "engine": meta.get("engine"), "aspect": "9:16",
                    "width": meta.get("width"), "height": meta.get("height"), "createdAt": meta.get("generatedAt") or bd.now(),
                    "durationSeconds": round(time.time() - started, 1),
                    "references": [{"file": str(Path(p).relative_to(GEN)), "role": role, "sha256": bd.sha256(p)} for p, role in refs],
                }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
                set_job(job_id, state="adding")
                rebuild(name, f"Adding look {slug}")
            set_job(job_id, state="done", variant=f"look-{slug}")
        finally:
            shutil.rmtree(work, ignore_errors=True)
    except Exception as e:  # shown to the user in the page
        set_job(job_id, state="failed", error=str(e))


def write_voice_prompt(name, prompt):
    path = ROOT / "CAST.md"
    text = path.read_text(encoding="utf-8")
    new, n = re.subn(rf"(^- character: '?{re.escape(name)}'?\n(?:(?!^- character:).*\n)*?  voicePrompt: ).*$",
                     lambda m: m[1] + json.dumps(prompt, ensure_ascii=False), text, count=1, flags=re.M)
    if n != 1:
        raise RuntimeError(f"no voicePrompt for {name} in CAST.md")
    path.write_text(new, encoding="utf-8")


def takes_dir(name):
    return GEN / name / "voice-takes"


def history_dir(name):
    return GEN / name / "voice-history"


def audio_uri(path):
    # Inline, like the bundle's page: Safari won't play audio over HTTP without byte-range support.
    return "data:audio/mp4;base64," + base64.b64encode(path.read_bytes()).decode()


def design(prompt, out, voice, size):
    r = subprocess.run(["echada", "voice", prompt, "--output", str(out), "--name", voice, "--tts-model", size],
                       capture_output=True, text=True, timeout=600)
    if r.returncode or not out.exists():
        raise RuntimeError((r.stderr or r.stdout).strip()[-300:] or f"echada failed on {size}")


def diga_import(vox):
    r = subprocess.run([str(bd.DIGA), "--import-vox", str(vox)], capture_output=True, text=True)  # replaces diga's stored copy
    if r.returncode:
        raise RuntimeError(f"diga could not import the voice: {r.stderr.strip()[-200:]}")


def generate_takes(job_id, name, prompt):
    voice = bd.voice_name(name)
    line = bd.front_matter_value(name, "sampleLine")
    source = bd.source_vox(name)
    work = GEN / name / f".takes-{job_id}"
    work.mkdir(parents=True)
    try:
        takes = []
        for i in range(1, TAKES + 1):
            set_job(job_id, state=f"making take {i} of {TAKES}")
            vox, audio = work / f"take-{i}.vox", work / f"take-{i}.m4a"
            design(prompt, vox, voice, "1.7b")
            diga_import(vox)  # diga speaks stored voices by name, so this briefly stands in for the real one
            r = subprocess.run([str(bd.DIGA), "-v", voice, "--model", "1.7b", "-o", str(audio), line], capture_output=True, text=True)
            if r.returncode or not audio.exists():
                raise RuntimeError(f"take {i} could not speak: {r.stderr.strip()[-200:]}")
            if name in bd.FX:
                wav = audio.with_suffix(".fx.wav")
                subprocess.run(["bash", str(ROOT / "tools/voicefx.sh"), name, str(audio), str(wav)], check=True, capture_output=True)
                subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "aac", "-b:a", "128k", str(audio)], check=True)
                wav.unlink()
            takes.append(i)
        (work / "takes.json").write_text(json.dumps({"id": job_id, "prompt": prompt, "line": line, "takes": takes}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        shutil.rmtree(takes_dir(name), ignore_errors=True)
        os.replace(work, takes_dir(name))
        set_job(job_id, state="done")
    except Exception as e:  # shown to the user in the page
        shutil.rmtree(work, ignore_errors=True)
        set_job(job_id, state="failed", error=str(e))
    finally:
        try:
            diga_import(source)  # the real voice back in diga's store, whatever happened
        except Exception as e:
            set_job(job_id, state="failed", error=f"The real voice is safe, but diga's copy wasn't restored: {e}")


def install_voice(job_id, name, vox, prompt, kept_samples=None, cleanup=None):
    """Replace the voice with this .vox. The current one is archived first, once.

    The marker is up from before the first file changes until the page is rendered: the .vox is often
    inside the bundle, and rendering the samples takes minutes, so a reader mustn't see the gap.
    """
    with dossier_update.updating(CHARS / f"{name}.dossier", label="Replacing the voice"):
        source = bd.source_vox(name)
        history = history_dir(name)
        history.mkdir(parents=True, exist_ok=True)
        digest = bd.sha256(source)
        if not any(bd.sha256(f) == digest for f in history.glob("*.vox")):
            stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
            shutil.copy2(source, history / f"{stamp}.vox")
            (history / f"{stamp}.txt").write_text((bd.cast_member(name)[0] or "") + "\n", encoding="utf-8")
            if bd.samples_dir(name).exists():
                shutil.copytree(bd.samples_dir(name), history / f"{stamp}-samples")
        shutil.rmtree(bd.samples_dir(name), ignore_errors=True)
        if kept_samples and kept_samples.exists():
            shutil.copytree(kept_samples, bd.samples_dir(name))
        shutil.copy2(vox, source)
        if cleanup:
            cleanup()
        diga_import(source)
        set_job(job_id, state="rendering the samples")
        bd.samples([name])  # only the ones that are missing
        missing = [bd.sample_file(s) for s in bd.spec_for(name) if not (bd.samples_dir(name) / bd.sample_file(s)).exists()]
        if missing:
            raise RuntimeError(f"samples failed: {', '.join(missing)}. The new voice is in place; pick it again to retry.")
        set_job(job_id, state="adding to the dossier")
        with name_lock(name):
            write_voice_prompt(name, prompt)
            rebuild(name, "Replacing the voice")


def use_take(job_id, name, take):
    try:
        folder = takes_dir(name)
        info = json.loads((folder / "takes.json").read_text(encoding="utf-8"))
        vox = folder / f"take-{take}.vox"
        set_job(job_id, state="finishing the take (0.6b)")
        design(info["prompt"], vox, bd.voice_name(name), "0.6b")  # takes hold 1.7b only; this adds the other model
        install_voice(job_id, name, vox, info["prompt"], cleanup=lambda: shutil.rmtree(folder, ignore_errors=True))
        set_job(job_id, state="done")
    except Exception as e:  # shown to the user in the page
        set_job(job_id, state="failed", error=str(e))


def restore_voice(job_id, name, stamp):
    try:
        history = history_dir(name)
        prompt = (history / f"{stamp}.txt").read_text(encoding="utf-8").strip()
        install_voice(job_id, name, history / f"{stamp}.vox", prompt, kept_samples=history / f"{stamp}-samples")
        set_job(job_id, state="done")
    except Exception as e:  # shown to the user in the page
        set_job(job_id, state="failed", error=str(e))


def voice_state(name):
    takes = None
    info_path = takes_dir(name) / "takes.json"
    if info_path.exists():
        info = json.loads(info_path.read_text(encoding="utf-8"))
        takes = dict(info, takes=[{"take": i, "audio": audio_uri(takes_dir(name) / f"take-{i}.m4a")} for i in info["takes"]])
    current = bd.sha256(bd.source_vox(name)) if bd.source_vox(name).exists() else None
    history = []
    for vox in sorted(history_dir(name).glob("*.vox"), reverse=True):
        if bd.sha256(vox) == current:
            continue
        sample = history_dir(name) / f"{vox.stem}-samples" / "sample-neutral.m4a"
        history.append({"stamp": vox.stem, "prompt": vox.with_suffix(".txt").read_text(encoding="utf-8").strip(),
                        "audio": audio_uri(sample) if sample.exists() else None})
    neutral = bd.samples_dir(name) / "sample-neutral.m4a"
    return {"takes": takes, "history": history[:MAX_HISTORY], "current": audio_uri(neutral) if neutral.exists() else None}


def start_voice_job(name, kind, work, *args):
    """One voice job at a time, across every character: they use the on-device models."""
    with jobs_lock:
        if any(j.get("type") == "voice" and j["state"] not in ("done", "failed", "dismissed") for j in jobs.values()):
            return None
        job_id = uuid.uuid4().hex[:12]
        jobs[job_id] = {"name": name, "type": "voice", "kind": kind, "state": "queued"}
    voice_pool.submit(work, job_id, name, *args)
    return job_id


def set_job(job_id, **fields):
    with jobs_lock:
        jobs[job_id].update(fields)


def looks(name):
    out = []
    for side in sorted((GEN / name).glob("view-look-*-r*.json")):
        m = json.loads(side.read_text(encoding="utf-8"))
        title = m["variant"].removeprefix("look-").replace("-", " ").capitalize()
        out.append({"variant": m["variant"], "title": title, "description": m.get("description", ""),
                    "image": f"/look-image/{quote(name)}/{quote(side.with_suffix('.png').name)}"})
    return out


def delete_look(name, variant):
    with name_lock(name):
        sides = [s for s in (GEN / name).glob("view-look-*-r*.json") if json.loads(s.read_text(encoding="utf-8"))["variant"] == variant]
        if not sides:
            return False
        trash = GEN / name / "deleted-looks"
        trash.mkdir(exist_ok=True)
        for side in sides:
            for f in (side, side.with_suffix(".png")):
                os.replace(f, trash / f.name)
        rebuild(name, f"Deleting {variant}")
    return True


class Handler(BaseHTTPRequestHandler):
    def local_only(self):
        """Refuse requests a web page on another site could send to this port; a POST here spends money."""
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0]
        origin = self.headers.get("Origin")
        ok_origin = origin is None or re.match(r"^http://(127\.0\.0\.1|localhost)(:\d+)?$", origin)
        return host in ("127.0.0.1", "localhost") and ok_origin

    def send_body(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, code, payload):
        self.send_body(code, json.dumps(payload, ensure_ascii=False).encode(), "application/json; charset=utf-8")

    def character(self, raw):
        name = unquote(raw)
        return name if name in characters() and name in bd.PICKS else None

    def do_GET(self):
        if not self.local_only():
            return self.send_error(403)
        path = self.path.split("?")[0]
        if path == "/":
            items = "".join(f'<li><a href="/{quote(n)}">{html.escape(n)}</a></li>' for n in characters())
            return self.send_body(200, f'<!doctype html><meta charset="utf-8"><title>Dossiers</title><h1>Dossiers</h1><ul>{items}</ul>'.encode(), "text/html; charset=utf-8")
        if path == "/api/models":
            return self.send_json(200, {"current": current_model(), "models": available_models()})
        if m := re.fullmatch(r"/api/([^/]+)/looks", path):
            name = self.character(m[1])
            if not name:
                return self.send_error(404)
            with jobs_lock:
                active = [dict(j, id=k) for k, j in jobs.items() if j["name"] == name and j.get("type") != "voice" and j["state"] not in ("done", "dismissed")]
            return self.send_json(200, {"looks": looks(name), "jobs": active})
        if m := re.fullmatch(r"/api/([^/]+)/voice", path):
            name = self.character(m[1])
            if not name:
                return self.send_error(404)
            with jobs_lock:
                job = next((dict(j, id=k) for k, j in reversed(list(jobs.items())) if j["name"] == name and j.get("type") == "voice" and j["state"] != "dismissed"), None)
            return self.send_json(200, {"prompt": bd.cast_member(name)[0], "editable": name in bd.SAMPLES, "job": job,
                                       **(voice_state(name) if name in bd.SAMPLES else {})})
        if m := re.fullmatch(r"/look-image/([^/]+)/(view-look-[^/]+\.png)", path):
            name, file = self.character(m[1]), unquote(m[2])
            if not name or "/" in file or not (GEN / name / file).exists():
                return self.send_error(404)
            # A display copy: the originals are 6 MB each.
            jpeg = subprocess.run(["magick", str(GEN / name / file), "-resize", "720x1280", "-quality", "80", "JPEG:-"], capture_output=True, check=True).stdout
            return self.send_body(200, jpeg, "image/jpeg")
        if m := re.fullmatch(r"/([^/]+)", path):
            name = unquote(m[1])
            if name not in characters():
                return self.send_error(404)
            with name_lock(name):
                page = (CHARS / f"{name}.dossier" / f"{name}-dossier.html").read_text(encoding="utf-8")
            if name not in bd.PICKS:
                return self.send_body(200, page.encode(), "text/html; charset=utf-8")
            editor = EDITOR.read_text(encoding="utf-8").replace("__CHARACTER__", json.dumps(name))
            assert page.count("</body>") == 1
            return self.send_body(200, page.replace("</body>", editor + "</body>").encode(), "text/html; charset=utf-8")
        return self.send_error(404)

    def do_POST(self):
        if not self.local_only():
            return self.send_error(403)
        voice = re.fullmatch(r"/api/([^/]+)/voice(?:/(use|restore))?", self.path)
        m = voice or re.fullmatch(r"/api/([^/]+)/looks", self.path)
        name = self.character(m[1]) if m else None
        if not name:
            return self.send_error(404)
        # JSON only: a cross-site form can't send this without the Origin check seeing it.
        if (self.headers.get("Content-Type") or "").split(";")[0].strip() != "application/json":
            return self.send_error(415)
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= MAX_BODY:
            return self.send_error(413)
        try:
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError
        except ValueError:
            return self.send_error(400)
        if voice:
            return self.voice_action(name, voice[2], body)
        description = body.get("description")
        if not isinstance(description, str):
            return self.send_error(400)
        description = description.strip()
        if not description or len(description) > MAX_DESCRIPTION:
            return self.send_json(400, {"error": f"Describe the look in 1 to {MAX_DESCRIPTION} characters."})
        job_id = uuid.uuid4().hex[:12]
        with jobs_lock:
            jobs[job_id] = {"name": name, "description": description, "state": "queued"}
        pool.submit(generate, job_id, name, description, current_model())
        self.send_json(202, {"id": job_id})

    def voice_action(self, name, action, body):
        if name not in bd.SAMPLES:
            return self.send_json(400, {"error": f"{name} has no sample lines yet."})
        if action == "use":
            take = body.get("take")
            info = takes_dir(name) / "takes.json"
            if not isinstance(take, int) or not info.exists() or take not in json.loads(info.read_text(encoding="utf-8"))["takes"]:
                return self.send_json(400, {"error": "That take no longer exists."})
            job = start_voice_job(name, "install", use_take, take)
        elif action == "restore":
            stamp = body.get("stamp")
            if not isinstance(stamp, str) or not re.fullmatch(r"\d{8}-\d{6}", stamp) or not (history_dir(name) / f"{stamp}.vox").exists():
                return self.send_json(400, {"error": "That voice is no longer in the history."})
            job = start_voice_job(name, "install", restore_voice, stamp)
        else:
            prompt = body.get("prompt")
            prompt = " ".join(prompt.split()) if isinstance(prompt, str) else ""
            if not prompt or len(prompt) > MAX_DESCRIPTION:
                return self.send_json(400, {"error": f"Write the prompt in 1 to {MAX_DESCRIPTION} characters."})
            job = start_voice_job(name, "takes", generate_takes, prompt)
        if not job:
            return self.send_json(409, {"error": "Another voice job is running. Wait for it to finish."})
        self.send_json(202, {"id": job})

    def do_PUT(self):
        if not self.local_only():
            return self.send_error(403)
        if self.path != "/api/models":
            return self.send_error(404)
        if (self.headers.get("Content-Type") or "").split(";")[0].strip() != "application/json":
            return self.send_error(415)
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= MAX_BODY:
            return self.send_error(413)
        try:
            model = json.loads(self.rfile.read(length))["model"]
        except (ValueError, KeyError, TypeError):
            return self.send_error(400)
        found = next((m for m in available_models() if m["model"] == model), None)
        if not found or not found["usable"]:
            return self.send_json(400, {"error": f"{model} can't be used for looks: {found['why'] if found else 'unknown model'}."})
        set_model(model)
        self.send_json(200, {"current": model})

    def do_DELETE(self):
        if not self.local_only():
            return self.send_error(403)
        if m := re.fullmatch(r"/api/([^/]+)/voice/takes", self.path):
            name = self.character(m[1])
            if not name:
                return self.send_error(404)
            shutil.rmtree(takes_dir(name), ignore_errors=True)
            return self.send_json(200, {"ok": True})
        if m := re.fullmatch(r"/api/jobs/([0-9a-f]{12})", self.path):
            with jobs_lock:
                if m[1] in jobs and jobs[m[1]]["state"] == "failed":
                    jobs[m[1]]["state"] = "dismissed"
            return self.send_json(200, {"ok": True})
        m = re.fullmatch(r"/api/([^/]+)/looks/(look-[a-z0-9-]+)", self.path)
        name = self.character(m[1]) if m else None
        if not name:
            return self.send_error(404)
        try:
            found = delete_look(name, m[2])
        except RuntimeError as e:
            return self.send_json(500, {"error": str(e)})
        self.send_json(200 if found else 404, {"ok": found})

    def log_message(self, *args):
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", type=Path, default=Path.cwd(), help="the folder holding CAST.md")
    ap.add_argument("--port", type=int, default=8767)
    args = ap.parse_args()
    if not CONFIG.exists():
        shutil.copy2(ASSETS / "IMAGE_PROVIDER.md", CONFIG)
    print(f"http://127.0.0.1:{args.port}/  Vinetas: {locate_cli()}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
