---
type: skill
name: publish-flipbook
description: Publish a podcast or screenplay project's storyboard flipbook (the audio-synced sequence view from scripts/build-flipbook.py) to the Vinetas website at vinetas.app as an unlisted page, with its art and audio on the CDN, so it can be shown to people by direct URL. Use whenever the user asks to publish, deploy, put up, share, update or republish a flipbook, storyboard sequence or sequence view on the Vinetas site, or wants a shareable link to a flipbook. Not for rendering frames or building the flipbook locally; use storyboard-flipbook and the project's own scripts for those.
---

# Publish Flipbook

Copies a built flipbook into the Vinetas site repo as a read-only page and releases it.

- Page: `https://vinetas.app/flipbooks/<show>/<stem>/`
- Art and audio: `assets/flipbooks/<show>/<stem>/`, served from `{{ site.cdn_url }}/flipbooks/...`
- Site repo: `~/Projects/websites/vinetas.github.io`. Read its `AGENTS.md`.

`S` below is this skill's folder. `P` is the project folder. `<stem>` is the episode, such as `01-reciprocal-prostitution`.

## Unlisted is the rule

Flipbooks are shown to people by direct URL. Nothing on the site links to them. Don't add a link, nav entry, sitemap entry or index page unless the user changes this.

`publish` writes the page with `noindex` and `sitemap: false`, and `check` fails if anything lists it. Unlisted is not private: anyone with the URL can open the page and the CDN files. Say so if someone treats a book as confidential.

## What goes public

The page drops the local flipbook's notes box, prompt editor and Regenerate button. The script copies only frames, thumbnails, audio and captions. It never copies prompts, notes, `.takes` or sidecar JSON, because those hold working notes and the full prompt text. Keep it that way.

Look at every frame and search the captions before a book's first release, because this is the app's marketing domain. Montage `storyboards/<stem>/web/*.jpg` into a contact sheet in the scratchpad. If anything looks risky, ask before publishing.

Don't write "Made with Vinetas" on a page unless the frames were rendered through Vinetas. Check `provider` in the frames' sidecar JSON: `gemini-api` means the Vinetas app wasn't involved. The header credit names the model from the sidecars, and `--credit` overrides it.

## Steps

### 1. Prepare the site repo

Work on `development` in the site repo, and pull first. Run `bundle update`. The site's `AGENTS.md` requires this before every ship.

### 2. Publish into the repo

```bash
python3 "$S/scripts/publish_flipbook.py" publish "$P" <stem>
```

The script refuses a stale book: a render, audio file or transcript newer than the built flipbook, which would put frames out of step. Rebuild with `scripts/build-flipbook.py <stem>` in the project and run it again. Read the printed slate and credit. Fix them with `--slate-title`, `--slate-sub`, `--slate-end` or `--credit`. If the stem isn't lowercase-with-hyphens, such as `episode_1_01_cold_open`, name the URL with `--slug`. Pass the same `--slug` on every republish, and use the slug as `<stem>` in the `live` step.

Publishing again replaces that book's asset folder. Each URL carries a content hash, so viewers don't get new captions with cached old audio.

Only audio flipbooks are supported. The scene flipbooks from `storyboard-flipbook` have a different format, and the script says so.

### 3. Build and check

```bash
bundle exec jekyll build --strict_front_matter
python3 "$S/scripts/publish_flipbook.py" check
```

### 4. See it work before release

The new files aren't on the CDN until after release, so build against the local copy:

```bash
printf 'cdn_url: "/assets"\n' > "$SCRATCH/local.yml"
bundle exec jekyll serve --config _config.yml,"$SCRATCH/local.yml" --port 4011 --no-watch
```

Open `http://127.0.0.1:4011/flipbooks/<show>/<stem>/` with the Safari tools. Confirm the slate shows, play starts audio, frames advance, captions appear, and clicking a thumbnail seeks. Check a phone-width viewport. Stop the server, then rebuild without the override so `_site` isn't left pointing at `/assets`.

### 5. Release

Commit on `development` with only the book's two folders, using explicit paths. Push, then open a `development` → `main` PR. Before merging, list what else the merge would ship with `git log origin/main..origin/development`. Tell the user about anything that isn't the flipbook. If they don't want it live yet, branch from `main` and ship only the flipbook. Merge once `Jekyll Build Test` passes. A merge to `main` publishes the site and starts `Upload Assets to CDN`.

### 6. Verify live

Wait for the Pages build and the CDN workflow to finish (`gh run list`), then:

```bash
python3 "$S/scripts/publish_flipbook.py" live <show> <stem>
```

It fetches the page and every file from the public URLs, and sends the audio a Range request because seeking depends on one. Then load the live URL in Safari and play it. Report the URL to the user only once this passes.

To take a book down, delete its two folders and release the same way. The CDN workflow syncs with `--delete`, so the files go too.
