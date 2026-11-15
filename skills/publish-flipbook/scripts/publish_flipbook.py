#!/usr/bin/env python3
"""Publish a storyboard flipbook to the private sequences site, sequences.vinetas.app.

    publish_flipbook.py stage <project> <stem> [--show SLUG] [--slug SLUG] [--credit TEXT]
                              [--slate-title T] [--slate-sub T] [--slate-end T]
    publish_flipbook.py upload <show> <slug> [--dry-run]   send the staged book to R2, page last
    publish_flipbook.py live <show> <slug>                 bucket matches the staged book; the gate is closed
    publish_flipbook.py list                               every book in the bucket
    publish_flipbook.py takedown <show> <slug> [--yes]     delete a book from the bucket

<project> holds storyboards/<stem>/flipbook.html, built by the project's scripts/build-flipbook.py.
`stage` writes a self-contained folder (index.html, frames/, thumbs/, audio.m4a) under STAGE/<show>/<slug>/.
Only frames, thumbnails, audio and captions are copied: never prompts, notes, takes or sidecars.
The site is R2 bucket vinetas-sequences behind Cloudflare Access. Everything goes through the cf CLI.
"""
import argparse, collections, glob, hashlib, html, json, os, re, shutil, subprocess, sys, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE = os.path.expanduser("~/Library/Caches/publish-flipbook")
BUCKET = "vinetas-sequences"
LIVE = "https://sequences.vinetas.app"
ACCESS = "vinetas.cloudflareaccess.com"
ZONE = "vinetas.app"
ACCOUNT = "853adb869a81bae75f2eac0ce54bc661"  # an id, not a credential
MODEL_NAMES = {"gemini-nano-banana-2.1": "Gemini Nano Banana 2.1"}
TYPES = {".html": "text/html; charset=utf-8", ".jpg": "image/jpeg", ".m4a": "audio/mp4"}
SLUG = re.compile(r"[a-z0-9][a-z0-9-]*")


def version(path):
    """A content hash on each URL, so a republish can't pair new captions with cached old audio."""
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:10]


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def newer(a, b):
    return os.path.getmtime(a) > os.path.getmtime(b)


def sips(src, dst, *args):
    subprocess.run(["sips", *args, src, "--out", dst], check=True, capture_output=True)


def dimension(path, key):
    out = subprocess.run(["sips", "-g", key, path], check=True, capture_output=True, text=True).stdout
    return int(out.split()[-1])


def page_data(text, where):
    m = re.search(r"^const DATA = (\{.*\});$", text, re.M)
    if not m:
        sys.exit(f"{where} has no DATA block. Only audio flipbooks from build-flipbook.py can be published.")
    return json.loads(m.group(1).replace("<\\/", "</"))


def folder(show, slug):
    if not SLUG.fullmatch(show) or not SLUG.fullmatch(slug):
        sys.exit("show and slug must be lowercase-with-hyphens: they become URLs")
    return os.path.join(STAGE, show, slug)


# ---- cf -------------------------------------------------------------------------------------------

def cf(*args, capture=True):
    env = dict(os.environ)
    env.setdefault("CLOUDFLARE_ACCOUNT_ID", ACCOUNT)
    r = subprocess.run(["cf", *args], env=env, capture_output=capture, text=True)
    if r.returncode:
        sys.exit(f"cf {' '.join(args[:3])} failed: {(r.stderr or '').strip()[:400]}")
    return r


def remote(prefix):
    """{key: (etag, size)} for every object under prefix."""
    out, cursor = {}, None
    while True:
        args = ["r2", "objects", "list", "--bucket-name", BUCKET, "--prefix", prefix, "--per-page", "1000"]
        if cursor:
            args += ["--cursor", cursor]
        d = json.loads(cf(*args).stdout or "[]")
        items = d if isinstance(d, list) else d.get("result", [])
        for o in items:
            out[o["key"]] = (o.get("etag", "").strip('"'), o.get("size"))
        cursor = None if isinstance(d, list) else (d.get("result_info") or {}).get("cursor")
        if not cursor or not items:
            return out


def put(key, path):
    cf("r2", "objects", "put", key, "--bucket-name", BUCKET, "--file", path,
       "--content-type", TYPES[os.path.splitext(path)[1]])


def served_urls(prefix):
    """{key: [urls]} for the book's page as it is now in the bucket, with each file's ?v= version.
    Read before the page is replaced, because the edge cache holds the versioned URLs it named."""
    r = subprocess.run(["cf", "r2", "objects", "get", prefix + "index.html", "--bucket-name", BUCKET],
                       env={**os.environ, "CLOUDFLARE_ACCOUNT_ID": os.environ.get("CLOUDFLARE_ACCOUNT_ID", ACCOUNT)},
                       capture_output=True, text=True)
    urls = collections.defaultdict(list)
    if r.returncode or "const DATA" not in r.stdout:
        return urls
    data = page_data(r.stdout, prefix + "index.html")
    for u in [f[k] for f in data["frames"] for k in ("file", "thumb")] + ([data["audio"]] if data["audio"] else []):
        urls[prefix + u.split("?")[0]].append(f"{LIVE}/{prefix}{u}")
    return urls


def purge(keys, versioned):
    """Drop deleted files from Cloudflare's cache, which an R2 custom domain uses for .jpg and .m4a.
    The cache is keyed by full URL, so purge each bare URL and every versioned one the page named."""
    urls = [u for k in keys for u in [f"{LIVE}/{k}", *versioned.get(k, [])]]
    for i in range(0, len(urls), 30):
        r = cf("cache", "purge", "--zone", ZONE, "--body", json.dumps({"files": urls[i:i + 30]}), "--force")
        if "Aborted" in (r.stderr or ""):
            sys.exit("cache purge was aborted")
    print(f"purged {len(urls)} URLs from the edge cache")


def delete(key):
    r = cf("r2", "objects", "delete", key, "--bucket-name", BUCKET, "--force")
    if "Aborted" in (r.stderr or ""):  # an aborted delete still exits 0
        sys.exit(f"delete of {key} was aborted")


# ---- stage ----------------------------------------------------------------------------------------

def read_source(project, stem):
    src = os.path.join(project, "storyboards", stem)
    page = os.path.join(src, "flipbook.html")
    if not os.path.isfile(page):
        sys.exit(f"no {page}: build it with scripts/build-flipbook.py {stem}")
    text = open(page, encoding="utf-8").read()
    return src, page, text, page_data(text, page)


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
    first = data["frames"][0].get("start")
    if first is None:
        return None  # a silent book
    audio = os.path.join(project, "audio", stem + ".m4a")
    vtt = os.path.join(project, "audio", stem + ".vtt")
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


def stage(a):
    project, stem = os.path.abspath(a.project), a.stem
    show, slug = a.show or os.path.basename(project), a.slug or stem
    out = folder(show, slug)
    src, page, text, data = read_source(project, stem)
    audio = check_fresh(project, stem, src, page, data)

    if os.path.isdir(out):
        shutil.rmtree(out)  # this book only, so frames dropped from the book don't linger
    os.makedirs(os.path.join(out, "frames"))
    os.makedirs(os.path.join(out, "thumbs"))

    frames = []
    for f in data["frames"]:
        full, thumb = os.path.join(out, "frames", f["id"] + ".jpg"), os.path.join(out, "thumbs", f["id"] + ".jpg")
        shutil.copyfile(os.path.join(src, f["file"]), full)
        sips(full, thumb, "-s", "format", "jpeg", "-s", "formatOptions", "70", "-Z", "420")
        frames.append({"id": f["id"], "title": f["title"], "caption": f.get("caption", ""), "start": f.get("start"),
                       "file": f"frames/{f['id']}.jpg?v={version(full)}", "thumb": f"thumbs/{f['id']}.jpg?v={version(thumb)}"})

    audio_url = None
    if audio:
        shutil.copyfile(audio, os.path.join(out, "audio.m4a"))
        audio_url = "audio.m4a?v=" + version(audio)

    first = os.path.join(out, "frames", frames[0]["id"] + ".jpg")
    slate = slate_text(text, data["title"])
    slate.update({k: v for k, v in (("title", a.slate_title), ("sub", a.slate_sub), ("end", a.slate_end)) if v is not None})
    public = {"title": data["title"], "audio": audio_url, "frames": frames, "cues": data["cues"] if audio else [],
              "endSlate": data.get("endSlate"), "slate": slate,
              "credit": default_credit(src, data["frames"]) if a.credit is None else a.credit}

    blob = json.dumps(public, ensure_ascii=False).replace("</", "<\\/")
    doc = open(os.path.join(HERE, "assets", "private-flipbook.html"), encoding="utf-8").read()
    # __DATA__ goes last, so text inside a caption can't be read as a placeholder.
    for key, value in (("__TITLE__", html.escape(data["title"])),
                       ("__DESCRIPTION__", html.escape(f"A storyboard sequence, {len(frames)} frames.")),
                       ("__PATH__", f"{show}/{slug}"), ("__OG_IMAGE__", frames[0]["file"]),
                       ("__ASPECT__", f"{dimension(first, 'pixelWidth')}/{dimension(first, 'pixelHeight')}"),
                       ("__DATA__", blob)):
        doc = doc.replace(key, value)
    with open(os.path.join(out, "index.html"), "w", encoding="utf-8") as f:
        f.write(doc)

    problems = check_stage(out)
    for p in problems:
        print("PROBLEM:", p)
    if problems:
        sys.exit(1)
    size = sum(os.path.getsize(p) for p in local_files(out).values())
    print(f"staged {out}")
    print(f"{len(frames)} frames, {len(public['cues'])} captions, audio: {'yes' if audio else 'no'}, {size / 1e6:.1f} MB")
    print("credit:", public["credit"] or "(none)")
    print("slate:", json.dumps(slate, ensure_ascii=False))
    print(f"preview: python3 -m http.server 4012 --directory {STAGE}  ->  http://127.0.0.1:4012/{show}/{slug}/index.html")


def local_files(out):
    return {os.path.relpath(p, out): p for p in glob.glob(os.path.join(out, "**"), recursive=True) if os.path.isfile(p)}


def check_stage(out):
    """Every file the page asks for is staged, nothing else is, and no template text is left."""
    page = os.path.join(out, "index.html")
    if not os.path.isfile(page):
        return [f"nothing staged at {out}"]
    text = open(page, encoding="utf-8").read()
    problems = []
    if 'content="noindex, nofollow"' not in text:
        problems.append("no noindex tag")
    if "{{" in text or "{%" in text or "__" in re.sub(r"const DATA = .*", "", text):
        problems.append("the page holds unrendered template text")
    data = page_data(text, page)
    wanted = {u.split("?")[0] for u in [f[k] for f in data["frames"] for k in ("file", "thumb")]
              + ([data["audio"]] if data["audio"] else [])} | {"index.html"}
    have = set(local_files(out))
    problems += [f"missing {n}" for n in sorted(wanted - have)]
    problems += [f"extra file would be published: {n}" for n in sorted(have - wanted)]
    problems += [f"not an allowed file type: {n}" for n in sorted(have) if os.path.splitext(n)[1] not in TYPES]
    return problems


# ---- upload, live, list, takedown -----------------------------------------------------------------

def upload(a):
    out, prefix = folder(a.show, a.slug), f"{a.show}/{a.slug}/"
    problems = check_stage(out)
    if problems:
        sys.exit("stage it again first:\n  " + "\n  ".join(problems))
    files = local_files(out)
    have = remote(prefix)
    send = [n for n, p in files.items() if have.get(prefix + n, ("", None))[0] != md5(p)]
    stale = sorted(k for k in have if k[len(prefix):] not in files)
    body = [n for n in send if n != "index.html"]
    old = served_urls(prefix) if stale and not a.dry_run else {}
    print(f"{len(files)} files staged, {len(have)} in the bucket: {len(send)} to send, {len(stale)} to delete")
    if a.dry_run:
        for n in sorted(send):
            print("  put", prefix + n)
        for k in stale:
            print("  delete", k)
        return
    # Files first and the page last, so the live page never names a file that isn't there yet.
    with ThreadPoolExecutor(6) as pool:
        list(pool.map(lambda n: put(prefix + n, files[n]), body))
    if "index.html" in send:
        put(prefix + "index.html", files["index.html"])
    for k in stale:  # after the new page is up, nothing points at these any more
        delete(k)
    if stale:
        purge(stale, old)
    after = remote(prefix)
    wrong = [n for n, p in files.items() if after.get(prefix + n, ("", None))[0] != md5(p)]
    if wrong or len(after) != len(files):
        sys.exit(f"bucket doesn't match the stage: {len(wrong)} wrong, {len(after)} objects for {len(files)} files")
    print(f"uploaded. {len(after)} objects match the stage. {LIVE}/{prefix}index.html")


def live(a):
    """The bucket holds exactly the staged book, and a request with no sign-in is sent to Access."""
    out, prefix = folder(a.show, a.slug), f"{a.show}/{a.slug}/"
    files, have = local_files(out), remote(prefix)
    wrong = sorted(n for n, p in files.items() if have.get(prefix + n, ("", None))[0] != md5(p))
    extra = sorted(k for k in have if k[len(prefix):] not in files)
    for n in wrong:
        print("PROBLEM: missing or different in the bucket:", n)
    for k in extra:
        print("PROBLEM: in the bucket but not staged:", k)
    bad = bool(wrong or extra)
    for path in ("index.html", "audio.m4a" if "audio.m4a" in files else None):
        if not path:
            continue
        url = f"{LIVE}/{prefix}{path}"

        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kw):
                return None
        try:
            r = urllib.request.build_opener(NoRedirect).open(urllib.request.Request(url, headers={"User-Agent": "publish-flipbook"}), timeout=30)
            status, where = r.status, ""
        except urllib.error.HTTPError as e:
            status, where = e.code, e.headers.get("Location", "")
        gated = status in (302, 303) and ACCESS in where
        print(f"{path} without sign-in: {status} {'-> Access sign-in' if gated else where[:80]}")
        bad |= not gated
    print(f"{len(files) - len(wrong)} of {len(files)} files match in the bucket")
    sys.exit(1 if bad else 0)


def list_books(a):
    books = collections.Counter()
    for k in remote(""):
        parts = k.split("/")
        books["/".join(parts[:2]) if len(parts) > 2 else k] += 1
    for b, n in sorted(books.items()):
        print(f"{b}  {n} objects  {LIVE}/{b}/index.html")


def takedown(a):
    prefix = f"{a.show}/{a.slug}/"
    folder(a.show, a.slug)
    keys = sorted(remote(prefix), key=lambda k: not k.endswith("index.html"))  # the page goes first
    if not keys:
        sys.exit(f"nothing in the bucket under {prefix}")
    if not a.yes:
        sys.exit(f"{len(keys)} objects under {prefix}. Run again with --yes to delete them.")
    old = served_urls(prefix)
    if keys[0].endswith("index.html"):
        delete(keys[0])
    with ThreadPoolExecutor(6) as pool:
        list(pool.map(delete, [k for k in keys if not k.endswith("index.html")]))
    purge(keys, old)
    left = remote(prefix)
    print(f"deleted {len(keys) - len(left)} objects; {len(left)} left under {prefix}")
    sys.exit(1 if left else 0)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stage")
    s.add_argument("project")
    s.add_argument("stem")
    s.add_argument("--show", help="URL slug; defaults to the project's folder name")
    s.add_argument("--slug", help="URL name of the book; defaults to the stem")
    s.add_argument("--credit", help="header credit; defaults to the models named in the frames' sidecars; '' for none")
    s.add_argument("--slate-title")
    s.add_argument("--slate-sub")
    s.add_argument("--slate-end")
    s.set_defaults(fn=stage)
    for name, fn in (("upload", upload), ("live", live), ("takedown", takedown)):
        c = sub.add_parser(name)
        c.add_argument("show")
        c.add_argument("slug")
        if name == "upload":
            c.add_argument("--dry-run", action="store_true")
        if name == "takedown":
            c.add_argument("--yes", action="store_true")
        c.set_defaults(fn=fn)
    sub.add_parser("list").set_defaults(fn=list_books)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
