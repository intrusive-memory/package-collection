---
type: reference
model: google-nano-banana-2.1
---

# Image provider

The `model:` line above picks the model for **Add a look** on the dossier pages. Change it here, or with the **Provider** menu in the Add a look form. Both use this file, and the setting applies to the next look you generate.

It only covers Add a look. Other image scripts in the project keep their own settings.

## Available models

Looks need at least 2 reference images, so the character stays on model.

| `model:` value | Name | Provider | Price | Reference images | Works for looks? |
|---|---|---|---|---|---|
| `google-nano-banana-2.1` | Nano Banana 2.1 | Google | ~$0.03–0.11/image | 10 | Yes, tested |
| `google-gemini-3.1-flash-image` | Gemini 3.1 Flash Image | Google | ~$0.07–0.15/image | 10 | Yes, tested |
| `google-gemini-3-pro-image` | Gemini 3 Pro Image | Google | ~$0.13–0.24/image | 6 | Yes |
| `openai-gpt-image-2.5-flare` | GPT Image 2.5 Flare | OpenAI | ~$0.03–0.25/image | 10 | Yes |
| `openai-gpt-image-2.5-sunburst` | GPT Image 2.5 Sunburst | OpenAI | ~$0.03–0.25/image | 10 | Yes |
| `klein4b` | FLUX.2 Klein 4B | On this Mac | Free | 3 | No: needs the Vinetas Pro unlock |
| `pixart-sigma` | PixArt-Sigma XL | On this Mac | Free | 0 | No: can't use references |
| `bfl-flux-2-pro` | FLUX.2 [pro] | Black Forest Labs | ~$0.03/MP | 0 | No: can't use references, no API key |
| `bfl-flux-2-flex` | FLUX.2 [flex] | Black Forest Labs | ~$0.06/MP | 0 | No: can't use references, no API key |
| `stability-core` | Stable Image Core | Stability AI | 3 credits/image | 0 | No: can't use references, no API key |
| `stability-ultra` | Stable Image Ultra | Stability AI | 8 credits/image | 0 | No: can't use references, no API key |

This table is a snapshot from 2026-11-01 of the compiled Vinetas build's `list --json`. The Provider menu reads that list live, so trust the menu if they differ.
