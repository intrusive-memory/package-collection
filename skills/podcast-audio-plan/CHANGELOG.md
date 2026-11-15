---
type: doc
---

# Changelog - Podcast Audio Plan Skill

## [2.1.0] - 2026-08-03

### Cast roster moves to CAST.md (with probed legacy fallback)

- **Cast source**: the cast list now lives in a standalone `CAST.md` beside
  `PROJECT.md` (schema owned by SwiftReparto; `type: cast` + `cast:` array
  both required). `PROJECT.md` keeps project config only.
- **Runtime capability detection**: grep `echada --help` for the `verify`
  verb — present means CAST.md-capable (echada ≥ 1.0.0); absent means a
  legacy binary (≤ 0.17.0, incl. the signed binary embedded in shipped
  Produciesta.app) that still reads/writes `PROJECT.md`'s `cast:` block.
  (`echada verify cast --help` alone is NOT a valid probe — ArgumentParser
  exits 0 on `--help` even for unknown verbs.)
- **New commands documented**: `echada generate cast|prompt|vox`,
  `echada verify cast` (report-only divergence check), `echada prune cast`
  (explicit legacy-block removal), and the `--cast <filename>` override.
- All PROJECT.md-cast instructions in SKILL.md, README.md, and references/
  repointed to the roster with the documented PROJECT.md fallback.

## [2.0.0] - 2026-02-11

### 🎯 Major Rewrite: Claude-Assisted Casting

**BREAKING CHANGE**: Removed reliance on Produciesta's `--autocast` flag (currently not working).

### Added

- **Claude-assisted voice casting workflow**
  - Character extraction from Fountain files
  - Voice query from Apple TTS and ElevenLabs
  - Intelligent character-to-voice matching
  - Direct PROJECT.md writing

- **Comprehensive documentation**
  - Character analysis guidelines
  - Voice matching best practices
  - Complete workflow examples
  - Troubleshooting guides

- **Reference documents**
  - `produciesta-cli-reference.md` - Complete CLI documentation
  - `fountain-format-guide.md` - Fountain syntax for podcasts

### Changed

- **Workflow**: Claude handles casting, Produciesta handles audio generation
- **PROJECT.md creation**: Written by Claude instead of auto-generated
- **Voice assignment**: Based on Claude's analysis of character traits
- **Documentation**: Removed all `--autocast` references

### Removed

- Python scripts (`parse_fountain.py`, `analyze_project.py`, `generate_plans.py`)
- Template files (`AUDIO_GENERATION_PLAN.template.md`, `AUDIO_SPRINT_TASKS.template.md`)
- SwiftHablare/SwiftOnce coordination scripts
- `--autocast` workflow documentation

### Migration Guide

**From v1.0 (Python-based):**
1. Delete Python scripts and templates
2. Ask Claude to analyze your project and create PROJECT.md
3. Use `produciesta` for audio generation only

**From v2.0 beta (autocast-based):**
1. Do NOT use `--autocast` flag (not working)
2. Ask Claude to create cast list instead
3. Continue using `produciesta` for audio generation

### Technical Details

**Old approach:**
```bash
# This doesn't work currently
produciesta . --autocast --provider apple
```

**New approach:**
```bash
# Step 1: Ask Claude to analyze and create PROJECT.md
# (Claude reads episodes/*.fountain, queries voices, writes PROJECT.md)

# Step 2: Generate audio with Claude's cast list
produciesta /path/to/project --format m4a --verbose
```

---

## [1.0.0] - 2024

### Initial Release

- Python-based workflow
- Manual PROJECT.md parsing
- Separate SwiftHablare/SwiftOnce coordination
- Template-based plan generation
