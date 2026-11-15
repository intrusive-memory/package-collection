---
type: skill
name: publish-flipbook
description: Publish a podcast or screenplay project's storyboard flipbook (the audio-synced sequence view from scripts/build-flipbook.py) to the private sequences site, sequences.vinetas.app, an R2 bucket behind Cloudflare Access that only approved viewers can sign in to. Use whenever the user asks to publish, deploy, upload, put up, share, update, republish or take down a flipbook, storyboard sequence or sequence view, or wants a link to one. Never publishes to vinetas.app. Not for rendering frames or building the flipbook locally; use storyboard-flipbook and the project's own scripts for those.
---

# Publish Flipbook

Stages a built flipbook as a self-contained folder, then uploads it to the private sequences site.

- Page: `https://sequences.vinetas.app/<show>/<slug>/index.html`
- Storage: R2 bucket `vinetas-sequences`, key `<show>/<slug>/{index.html,audio.m4a,frames/,thumbs/}`
- Gate: Cloudflare Access app "Vinetas Sequences". Sign-in is by emailed one-time code. Only the emails in the reusable policy "Allowed viewers" get in, and a session lasts 168 hours.
- Tools: the `cf` CLI only, never Wrangler. The script sets `CLOUDFLARE_ACCOUNT_ID` itself.

`S` below is this skill's folder. `P` is the project folder. `<stem>` is the episode, such as `episode-01`.

## Never vinetas.app

On 2026-11-05 the user said: "We only want to publish securely on cloudflare." All flipbooks were taken off vinetas.app (vinetas.github.io PR #19) and the CDN cache was purged. Never put a flipbook in the vinetas.github.io repo or on `cdn.intrusive-memory.productions`, even as an unlisted page. Unlisted pages there were public to anyone with the URL.

Only publish the books the user asks for. Mr Mr Charles and Granville wait "until they're farther along".

## What leaves the machine

The page drops the local flipbook's notes box, prompt editor and Regenerate button. The script copies only frames, thumbnails, audio and captions. It never copies prompts, notes, `.takes` or sidecar JSON. `stage` fails on any file the page doesn't ask for. Keep it that way.

The site is private, but anyone added as a viewer sees everything on it. Before a book's first upload, look through its frames and captions.

Don't write "Made with Vinetas" on a page unless the frames were rendered through Vinetas. Check `provider` in the frames' sidecar JSON: `gemini-api` means the Vinetas app wasn't involved. The header credit names the model from the sidecars, and `--credit` overrides it.

## Steps

### 1. Stage

```bash
python3 "$S/scripts/publish_flipbook.py" stage "$P" <stem>
```

This writes `~/Library/Caches/publish-flipbook/<show>/<slug>/` and checks it. `<show>` defaults to the project folder's name, and `<slug>` to the stem.

**Stale books:** the script refuses a render, audio file or transcript that is newer than the built flipbook, because the frames would be out of step. Rebuild with `scripts/build-flipbook.py <stem>` in the project, then stage again.

**Slate and credit:** read the printed slate and credit, and fix them with `--slate-title`, `--slate-sub`, `--slate-end` or `--credit`.

**URL names:** if the stem isn't lowercase-with-hyphens, name the URL with `--slug`. Pass the same `--slug` every time after that.

**Cache-busting:** each file URL in the page carries a content hash. A republish can't pair new captions with old audio from the browser cache.

Only audio flipbooks are supported.

### 2. Preview locally

Serve the stage with the command `stage` prints:

```bash
python3 -m http.server 4012 --directory ~/Library/Caches/publish-flipbook
```

Open `http://127.0.0.1:4012/<show>/<slug>/index.html` with the browser tools. Check these:
- The slate shows.
- Play starts the audio.
- Frames advance and captions appear.
- Clicking a thumbnail seeks.
- The page works at phone width.

Then stop the server.

### 3. Upload

```bash
python3 "$S/scripts/publish_flipbook.py" upload <show> <slug> --dry-run   # what would change
python3 "$S/scripts/publish_flipbook.py" upload <show> <slug>
```

The upload sends only files whose MD5 differs from the bucket's ETag, so a republish after a retime sends just the page and the changed frames.

It sends every file before the page, so the live page never names a file that isn't there yet. After the new page is up, it deletes objects the book no longer uses and purges them from the edge cache. Then it lists the bucket and fails unless every object matches the stage.

### 4. Verify

```bash
python3 "$S/scripts/publish_flipbook.py" live <show> <slug>
```

This checks two things:
- The bucket holds exactly the staged files.
- A request with no sign-in, to the page and to the audio, is redirected to the Access sign-in. If it isn't, the gate is open: **stop and tell the user.**

The script can't sign in, so the last check is by eye. Open the live URL in the browser, sign in if asked, and play it. Report the URL only once this passes.

### Other commands

- `list`: shows every book in the bucket.
- `takedown <show> <slug> --yes`: deletes the page first, then the book's files. Without `--yes` it only counts them.
- **Cache purge:** the custom domain caches `.jpg` and `.m4a` at Cloudflare's edge, keyed by full URL. Whenever `upload` or `takedown` deletes files, it first reads the live page from the bucket. It then purges each deleted file, both the bare URL and the `?v=` URL the page named. Overwritten files need no purge, because a new hash means a new URL, and HTML isn't cached by default.

## Adding a viewer

Add their email to the reusable Access policy "Allowed viewers" (id `ddb28b27-1f0a-4c6d-bfe0-2cd71cdcfff2`) with `cf`. Find the command with `cf cli search "update a reusable access policy"`, and preview it with `--dry-run`. Change only what the user asks for.

Never turn on `deny_unmatched_requests` in the Zero Trust org. It would block vinetas.app and every other proxied site that has no Access app.

## Not built yet

These are phase 2 in `~/Projects/websites/vinetas.github.io/docs/incomplete/REQUIREMENTS-sequences-site.md`:
- **Folder URLs:** there is no rewrite rule, so a folder URL without `index.html` doesn't load. Always give the full `index.html` URL.
- **Cache-control headers:** none are set, because `cf r2 objects put` can't set them.
- **Index page:** there is no index page or manifest. The header's "Vinetas" link goes to `/`, which has nothing.
- **iPhone playback:** audio seeking through Access on an iPhone is still untested.
