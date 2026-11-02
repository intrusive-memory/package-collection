---
type: skill
name: dossier-editor
description: Serve a project's .dossier character pages on a local address with editing controls. Add or delete a character's looks by describing them, on a switchable image provider (Nano Banana by default), and click a voice prompt to edit it, generate 3 voice takes, compare them with the current voice and pick one. Use when the user asks to "edit a dossier", "add a look", "add an outfit", "delete a look", "change the image provider", "edit a voice prompt", "regenerate a voice", "audition voices" or "pick a new voice", or says a character's voice doesn't match. Works in a podcast project with CAST.md and characters/<NAME>.dossier bundles that has tools/build_dossiers.py and tools/render_dossier_pages.py.
---

# Dossier editor

A local server that shows a project's dossier pages with editing controls added. `S` below is this skill's folder and `P` is the project folder, the one holding `CAST.md`.

```bash
python3 "$S/bin/dossier_server.py" --project "$P"      # http://127.0.0.1:8767/
```

Run it in the background, then give the user the address for the character, such as `http://127.0.0.1:8767/SERENA`. A name with a space is URL-encoded (`/LORD%20BLAUD`).

## Read-only hosts stay read-only

The controls exist only in the page this server sends. The `<NAME>-dossier.html` file in the bundle has none, because the format forbids a request from a dossier's own page. Escribir shows that file, so **it shows the results but never the controls**. If the user can't find a control, first check they're on the local address.

Never write the controls into the bundle's page.

## Looks

In the Look section, under **More looks**:

- **Add a look** opens a text box. **Generate** sends the description to Vinetas CLI with the character's face and portrait as references, on the model in `P/IMAGE_PROVIDER.md`. Cloud models bill per image, so say so before generating in bulk.
- **Delete** asks for confirmation. The bundle loses the look, and its source moves to `.generations/<NAME>/deleted-looks/`.
- The form's **Provider** menu writes `P/IMAGE_PROVIDER.md`. The file is created on first run. A model needs at least 2 reference images and a usable key.

Looks are stored as `kind: view` with a `look-<slug>` variant, because format v2 retired `wardrobe`. Their sources are `.generations/<NAME>/view-look-*-r<n>.{png,json}`.

## Voices

The voice prompt is a plain paragraph under the samples:

1. Click the paragraph and type. Esc or **Cancel** puts it back.
2. **Generate 3 takes** runs on this Mac for free, about 2 minutes in total. Takes go to `.generations/<NAME>/voice-takes/`. **Nothing else changes.**
3. **Current** and **Take 1–3** appear, all speaking the character's `sampleLine`.
4. **Use this voice** adds the 0.6b model, replaces the `.vox`, renders the samples again and writes the prompt to `CAST.md`, about 2 minutes. **Try again** replaces the takes. **Discard takes** removes them.
5. **Previous voices** can be played and restored exactly. They live in `.generations/<NAME>/voice-history/`.

Only one voice job runs at a time, across all characters.

Tell the user:

- **You can't judge the voice.** The user decides by ear. Measuring pitch is fine, but don't call a voice right.
- **Episodes keep the old voice** until they're rendered again. Suggest one re-render after the whole voice pass, not after each change. Don't re-render unasked.
- **The 0.6b version is designed separately,** so it may not sound like the take. The project's `tts.model` says which one episodes use.
- **`CHARACTER.md` isn't updated.** Its Voice & Speech section may go out of date.

## Vinetas

The server uses `$VINETAS_CLI`, else the newest compiled build of the main Vinetas checkout, through the `vinetas-cli` wrapper. It skips the installed app on purpose: an older build fails with "Engine 'cloud-google' does not support reference images". API keys come from the environment or the Vinetas keychain item, and are only passed to the CLI. Never print them.

## Requirements

The project supplies the part that knows its bundles. This is the current limit of the skill, so check for these first and tell the user if they're missing:

- **`P/tools/build_dossiers.py`**, importable, with: `ROOT`, `CHARS`, `GEN`, `DIGA`, `STYLE`, `NO_MARKS`, `KEYCHAIN_SERVICE`, `PICKS`, `SAMPLES`, `FX`, `face_path`, `portrait_path`, `source_vox`, `samples_dir`, `sample_file`, `spec_for`, `samples`, `voice_name`, `cast_member`, `front_matter_value`, `sha256`, `now`, and an `assemble <NAME>` command that rebuilds a bundle from `.generations/`.
- **Optional in `build_dossiers.py`:** `style_for(name)`, a character's own art style, otherwise `STYLE` is used; and `LOOK_FRAMING`, a sentence saying how a look is framed and lit, otherwise a head-to-toe figure on the portrait's flat background. Set `LOOK_FRAMING` for any project whose references aren't flat-background art.
- **`P/tools/render_dossier_pages.py <NAME>`**, which writes the page and gives looks a `[data-looks]` block containing `<h3>` and `.looks`. The editor creates the block if it's missing.
- **`P/tools/voicefx.sh`**, for characters listed in `FX`.
- **Tools:** `echada`, `diga`, `magick`, `ffmpeg`, Personaje's `.venv` and `tools/dossier_update.py`, and a compiled Vinetas build.

The Synchronized Worlds and Granville have the project scripts today. Granville's `assemble` only adds what the editor produced; it derives picks from the manifests and never rebuilds a bundle. Once SwiftDossier ships, its rebuild and render should replace them.

## Files

- `bin/dossier_server.py`: the server and API. It listens on `127.0.0.1` only, and refuses other origins and non-JSON writes, because a request here can spend money.
- `assets/dossier_editor.html`: the controls added to each served page.
- `assets/IMAGE_PROVIDER.md`: the starting provider file and model list.
