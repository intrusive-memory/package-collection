#!/usr/bin/env python3
"""Publish a storyboard flipbook to the Vinetas website as an unlisted page.

    publish_flipbook.py publish <project> <stem> [--site DIR] [--show SLUG] [--slug SLUG] [--credit TEXT]
                                [--slate-title T] [--slate-sub T] [--slate-end T]
    publish_flipbook.py check [--site DIR]      after `jekyll build`: every flipbook is complete and unlisted
    publish_flipbook.py live <show> <stem>      after the release: the page and its files answer on the internet

<project> holds storyboards/<stem>/flipbook.html, built by the project's scripts/build-flipbook.py.
Only frames, thumbnails, audio and captions are copied: never prompts, notes, takes or sidecars.
Writes flipbooks/<show>/<stem>/index.html and assets/flipbooks/<show>/<stem>/ in the site repo.
"""
import argparse, collections, glob, hashlib, html, json, os, re, shutil, subprocess, sys, urllib.request

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.expanduser("~/Projects/websites/vinetas.github.io")
LIVE = "https://vinetas.app"
CDN = "https://cdn.intrusive-memory.productions/vinetas"
MODEL_NAMES = {"gemini-nano-banana-2.1": "Gemini Nano Banana 2.1"}


def version(path):
    """A content hash on each URL, so a republish can't pair new captions with cached old audio."""
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:10]


def newer(a, b):
    return os.path.getmtime(a) > os.path.getmtime(b)


def sips(src, dst, *args):
    subprocess.run(["sips", *args, src, "--out", dst], check=True, capture_output=True)


def dimension(path, key):
    out = subprocess.run(["sips", "-g", key, path], check=True, capture_output=True, text=True).stdout
    return int(out.split()[-1])


def read_source(project, stem):
    src = os.path.join(project, "storyboards", stem)
    page = os.path.join(src, "flipbook.html")
    if not os.path.isfile(page):
        sys.exit(f"no {page}: build it with scripts/build-flipbook.py {stem}")
    text = open(page, encoding="utf-8").read()
    m = re.search(r"^const DATA = (\{.*\});$", text, re.M)
    if not m:
        sys.exit(f"{page} has no DATA block. Only audio flipbooks from build-flipbook.py can be published.")
    data = json.loads(m.group(1).replace("<\\/", "</"))
    return src, page, text, data


def check_fresh(project, stem, src, page, data):
    """Refuse a stale book: frames or captions that no longer match what the project holds."""
    rebuild = f"rebuild first: scripts/build-flipbook.py {stem}"
    if not data["frames"]:
        sys.exit("the flipbook has no frames")
    for f in data["frames"]:
        web, png = os.path.join(src, f["file"]), os.path.join(src, f["id"] + ".png")
        if not os.path.isfile(web):
            sys.exit(f"missing {web}: {rebuild}")
        if os.path.isfile(png) and newer(png, web):
            sys.exit(f"{f['id']}: the render is newer than its web image: {rebuild}")
    audio = os.path.join(project, "audio", stem + ".m4a")
    vtt = os.path.join(project, "audio", stem + ".vtt")
    silent = not data["frames"][0].get("start") and data["frames"][0].get("start") != 0
    if silent:
        return None
    for path in (audio, vtt):
        if not os.path.isfile(path):
            sys.exit(f"missing {path}")
        if newer(path, page):
            sys.exit(f"{os.path.basename(path)} is newer than the flipbook, so frames would drift: {rebuild}")
    return audio


def default_credit(src, frames):
    models = collections.Counter()
    for f in frames:
        side = os.path.join(src, f["id"] + ".json")
        if os.path.isfile(side):
            models[json.load(open(side, encoding="utf-8")).get("model")] += 1
    models.pop(None, None)
    if not models:
        return ""
    return "Frames rendered with " + ", ".join(MODEL_NAMES.get(m, m) for m, _ in models.most_common())


def slate_text(text, title):
    """Read the project's own slate wording, falling back to the book's title."""
    show, _, rest = title.partition(": ")
    big = re.search(r'id="slate"><b>(.*?)</b>', text)
    both = re.search(r'textContent = end \? "(.*?)" : "(.*?)"', text)
    return {"title": html.unescape(big.group(1)) if big else show,
            "sub": both.group(2) if both else rest.replace(", ", ": ", 1),
            "end": both.group(1) if both else ""}


def publish(a):
    project, stem = os.path.abspath(a.project), a.stem
    slug = a.slug or stem  # the URL's name, for a project whose episode names aren't URL-safe
    site = os.path.abspath(a.site)
    show = a.show or os.path.basename(project)
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", show) or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug):
        sys.exit("show and stem must be lowercase-with-hyphens: they become URLs")
    src, page, text, data = read_source(project, stem)
    audio = check_fresh(project, stem, src, page, data)

    rel = f"{show}/{slug}"
    assets = os.path.join(site, "assets", "flipbooks", show, slug)
    if os.path.isdir(assets):
        shutil.rmtree(assets)  # this book's folder only, so frames dropped from the book don't linger
    os.makedirs(os.path.join(assets, "frames"))
    os.makedirs(os.path.join(assets, "thumbs"))

    frames = []
    for f in data["frames"]:
        full, thumb = os.path.join(assets, "frames", f["id"] + ".jpg"), os.path.join(assets, "thumbs", f["id"] + ".jpg")
        shutil.copyfile(os.path.join(src, f["file"]), full)
        sips(full, thumb, "-s", "format", "jpeg", "-s", "formatOptions", "70", "-Z", "420")
        frames.append({"id": f["id"], "title": f["title"], "caption": f.get("caption", ""), "start": f.get("start"),
                       "file": f"frames/{f['id']}.jpg?v={version(full)}", "thumb": f"thumbs/{f['id']}.jpg?v={version(thumb)}"})

    audio_url = None
    if audio:
        shutil.copyfile(audio, os.path.join(assets, "audio.m4a"))
        audio_url = "audio.m4a?v=" + version(audio)

    first = os.path.join(assets, "frames", frames[0]["id"] + ".jpg")
    slate = slate_text(text, data["title"])
    slate.update({k: v for k, v in (("title", a.slate_title), ("sub", a.slate_sub), ("end", a.slate_end)) if v is not None})
    public = {"title": data["title"], "audio": audio_url, "frames": frames, "cues": data["cues"] if audio else [],
              "endSlate": data.get("endSlate"), "slate": slate,
              "credit": default_credit(src, data["frames"]) if a.credit is None else a.credit}

    blob = json.dumps(public, ensure_ascii=False).replace("</", "<\\/")
    if "{%" in blob:
        sys.exit("a caption contains '{%', which would break the page's Liquid raw block")
    out = open(os.path.join(HERE, "assets", "public-flipbook.html"), encoding="utf-8").read()
    # __DATA__ goes last, so text inside a caption can't be read as a placeholder.
    for key, value in (("__YAML_TITLE__", json.dumps(data["title"], ensure_ascii=False)),
                       ("__TITLE__", html.escape(data["title"])),
                       ("__DESCRIPTION__", html.escape(f"A storyboard sequence, {len(frames)} frames.")),
                       ("__PATH__", rel), ("__OG_IMAGE__", frames[0]["file"]),
                       ("__ASPECT__", f"{dimension(first, 'pixelWidth')}/{dimension(first, 'pixelHeight')}"),
                       ("__DATA__", blob)):
        out = out.replace(key, value)
    folder = os.path.join(site, "flipbooks", show, slug)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as f:
        f.write(out)

    size = sum(os.path.getsize(p) for p in glob.glob(os.path.join(assets, "**"), recursive=True) if os.path.isfile(p))
    print(f"{len(frames)} frames, {len(public['cues'])} captions, audio: {'yes' if audio else 'no'}, {size / 1e6:.1f} MB")
    print("credit:", public["credit"] or "(none)")
    print("slate:", json.dumps(slate, ensure_ascii=False))
    print(f"url after release: {LIVE}/flipbooks/{rel}/")


def check(a):
    """Inspect the built _site. Exits 1 on anything that would list a book or leak project files."""
    built = os.path.join(os.path.abspath(a.site), "_site")
    problems, pages = [], glob.glob(os.path.join(built, "flipbooks", "*", "*", "index.html"))
    if not pages:
        problems.append("no flipbook pages in _site: run jekyll build first")
    sitemap = open(os.path.join(built, "sitemap.xml"), encoding="utf-8").read()
    if "flipbooks" in sitemap:
        problems.append("sitemap.xml lists a flipbook")
    for path in glob.glob(os.path.join(built, "**", "*"), recursive=True):
        if path.endswith((".html", ".xml", ".js", ".css", ".txt", ".json")) and os.path.isfile(path) and "/flipbooks/" not in path.replace(built, ""):
            if "flipbooks" in open(path, encoding="utf-8", errors="ignore").read():
                problems.append(f"links to a flipbook: {os.path.relpath(path, built)}")
    for page in pages:
        rel = os.path.relpath(os.path.dirname(page), os.path.join(built, "flipbooks"))
        text = open(page, encoding="utf-8").read()
        if 'content="noindex, nofollow"' not in text:
            problems.append(f"{rel}: no noindex tag")
        if 'class="site-main"' in text or "{%" in text or "__" in re.sub(r"const DATA = .*", "", text):
            problems.append(f"{rel}: wrapped in the site layout or holds unrendered template text")
        data = json.loads(re.search(r"^const DATA = (\{.*\});$", text, re.M).group(1).replace("<\\/", "</"))
        files = [f[k] for f in data["frames"] for k in ("file", "thumb")] + ([data["audio"]] if data["audio"] else [])
        wanted = {u.split("?")[0] for u in files}
        have = {os.path.relpath(p, os.path.join(built, "assets", "flipbooks", rel))
                for p in glob.glob(os.path.join(built, "assets", "flipbooks", rel, "**"), recursive=True) if os.path.isfile(p)}
        for name in sorted(wanted - have):
            problems.append(f"{rel}: missing {name}")
        for name in sorted(have - wanted):
            problems.append(f"{rel}: extra file would be published: {name}")
        print(f"{rel}: {len(data['frames'])} frames, {len(have)} files")
    for p in problems:
        print("PROBLEM:", p)
    sys.exit(1 if problems else 0)


def live(a):
    """Fetch through the public URLs, using a Range request for the audio as browsers do when seeking."""
    rel = f"{a.show}/{a.stem}"
    req = urllib.request.Request(f"{LIVE}/flipbooks/{rel}/", headers={"User-Agent": "publish-flipbook"})
    text = urllib.request.urlopen(req, timeout=30).read().decode()
    data = json.loads(re.search(r"^const DATA = (\{.*\});$", text, re.M).group(1).replace("<\\/", "</"))
    base = re.search(r'^const BASE = "(.*)";$', text, re.M).group(1)
    urls = [f[k] for f in data["frames"] for k in ("file", "thumb")]
    bad = 0
    for u in urls + ([data["audio"]] if data["audio"] else []):
        headers = {"User-Agent": "publish-flipbook"}
        if u.startswith("audio"):
            headers["Range"] = "bytes=0-1023"
        try:
            r = urllib.request.urlopen(urllib.request.Request(base + u, headers=headers), timeout=30)
            kind = r.headers.get("Content-Type", "")
            ok = kind.startswith("image/") if not u.startswith("audio") else (r.status == 206 and kind.startswith(("audio/", "video/mp4")))
            if u.startswith("audio"):
                print(f"audio: {r.status} {kind}")
        except OSError as e:
            ok, kind = False, str(e)
        if not ok:
            bad += 1
            print("PROBLEM:", u, kind)
    print(f"page ok, {len(urls) + bool(data['audio']) - bad} of {len(urls) + bool(data['audio'])} files answer correctly from {base}")
    sys.exit(1 if bad else 0)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    pub = sub.add_parser("publish")
    pub.add_argument("project")
    pub.add_argument("stem")
    pub.add_argument("--site", default=SITE)
    pub.add_argument("--show", help="URL slug; defaults to the project's folder name")
    pub.add_argument("--slug", help="URL name of the book; defaults to the stem")
    pub.add_argument("--credit", help="header credit; defaults to the models named in the frames' sidecars; '' for none")
    pub.add_argument("--slate-title")
    pub.add_argument("--slate-sub")
    pub.add_argument("--slate-end")
    pub.set_defaults(fn=publish)
    chk = sub.add_parser("check")
    chk.add_argument("--site", default=SITE)
    chk.set_defaults(fn=check)
    liv = sub.add_parser("live")
    liv.add_argument("show")
    liv.add_argument("stem")
    liv.set_defaults(fn=live)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
