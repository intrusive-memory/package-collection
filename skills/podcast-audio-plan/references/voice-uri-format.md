# Voice URI Format Specification

## Format

Voice URIs use the following format:

```
PROVIDER://[lang/]voiceId
```

The `lang` component is **optional** and defaults to the podcast's language (typically `en` if not specified).

## Examples

- **ElevenLabs with lang**: `elevenlabs://en/Ya2J5uIa5Pq14DNPsbC1`
- **ElevenLabs without lang**: `elevenlabs://Ya2J5uIa5Pq14DNPsbC1` (defaults to `en`)
- **Apple TTS**: `apple://en/com.apple.voice.premium.en-US.Ava`

## Components

1. **PROVIDER**: The TTS provider (e.g., `elevenlabs`, `apple`)
2. **lang** (optional): ISO 639-1 language code (e.g., `en`, `es`, `fr`). Defaults to `en` if omitted.
3. **voiceId**: Provider-specific voice identifier

## Invalid Formats

The following formats are **incorrect** and should not be used:

- `hablare://provider/voiceId?lang=xx` (deprecated scheme)
- `provider://voiceId?lang=xx` (query parameter format)

## Source of Truth

The authoritative source for this format is `ElevenLabsDefaults.swift` in the SwiftOnce project.

## Related Projects

- **SwiftHablare**: Voice generation library (Apple TTS + ElevenLabs)
- **SwiftOnce**: ElevenLabs API client
- **SwiftProyecto**: PROJECT.md parsing, CastMember model
