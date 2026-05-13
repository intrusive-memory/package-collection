# split-agent-docs — Separate Universal vs Agent-Specific Content

Split a monolithic `AGENTS.md` (or `CLAUDE.md`) into universal (`AGENTS.md`) and agent-specific (`CLAUDE.md`, `GEMINI.md`, `CURSOR.md`, etc.) files. This is the original feature of this skill, preserved as a sub-command of the broader `organize` workflow.

**Referenced by**: `SKILL.md` § Commands.

---

## When to Run

- A project has a single `AGENTS.md` mixing universal info (architecture, testing) with agent-specific tooling (MCP servers, Claude-only build prefs).
- A project is onboarding a new agent (Gemini, Cursor, Copilot) and the existing CLAUDE.md or AGENTS.md is duplicated as a starting point.
- The user says "split agent docs", "separate agent instructions", "restructure AGENTS.md", or "create CLAUDE.md / GEMINI.md from AGENTS.md".

---

## The Pattern

After split:

| File | Owns |
|------|------|
| `AGENTS.md` | Universal: product, persona, architecture, testing, common tasks, universal critical rules |
| `CLAUDE.md` | Claude-specific: MCP servers (XcodeBuildMCP, ASC MCP, etc.), Claude build prefs, references to `~/.claude/CLAUDE.md` |
| `GEMINI.md` | Gemini-specific: standard CLI alternatives, Code Assist patterns |
| `CURSOR.md` / `COPILOT.md` / etc. | As needed |

Every agent-specific file starts with a prominent pointer:

```markdown
**⚠️ Read [AGENTS.md](AGENTS.md) first** for universal project documentation.
```

No content is duplicated between files. Agent-specific files reference back to AGENTS.md instead of restating shared rules.

---

## Workflow

### 1. Read existing agent docs

```bash
ls AGENTS.md CLAUDE.md GEMINI.md 2>/dev/null
```

Read whichever exist. Identify which content blocks are universal vs agent-specific using the categorization guide below.

### 2. Categorize content blocks

**Always universal:**
- Product overview, target user persona, pain points
- Architecture patterns and design decisions
- Testing requirements (applies to all agents)
- Git workflow, branching strategy, version management
- Documentation index, common agent tasks
- Critical rules that apply equally to every agent (e.g., "never commit to main", "always read before editing")

**Claude-specific:**
- MCP server configuration and usage (XcodeBuildMCP, App Store Connect MCP, etc.)
- Build tool preferences that mention MCP (`prefer XcodeBuildMCP over swift build`)
- References to `~/.claude/CLAUDE.md` global rules
- Anything that says "Claude" or "this agent"

**Gemini-specific:**
- Gemini API integration patterns
- Gemini Code Assist workflows
- "No-MCP" CLI alternatives written specifically for Gemini

**Other agent-specific:**
- Tool integrations tied to a specific agent
- Vendor-specific limitations or workflows

### 3. Rewrite `AGENTS.md`

Keep universal content. Remove agent-specific content. Add a clear cross-reference section:

```markdown
## Agent-Specific Tools

Detailed instructions for individual agents live in their own files:

- **Claude Code** → [CLAUDE.md](CLAUDE.md) (XcodeBuildMCP, App Store Connect MCP)
- **Gemini** → [GEMINI.md](GEMINI.md) (standard CLI tools)
```

Add to the critical-rules list:

```markdown
- Follow agent-specific instructions in your agent's file (see above).
```

### 4. Create or update agent-specific files

For each agent, write a file that:

1. Opens with the AGENTS.md pointer.
2. States only what is specific to this agent.
3. Links back to AGENTS.md for shared rules.

Skeleton:

```markdown
# <Agent>-Specific Instructions

**⚠️ Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to <Agent>.

## <Agent>-Specific Configuration
[tools, integrations, build preferences]

## <Agent>-Specific Critical Rules
1. <rule>
2. <rule>

## References
- Universal project rules: [AGENTS.md](AGENTS.md)
- Global <Agent> settings: <path or link>
```

### 5. Verify

```bash
# All expected files exist
ls AGENTS.md CLAUDE.md GEMINI.md

# Agent files reference AGENTS.md prominently
head -5 CLAUDE.md GEMINI.md

# No agent-specific terms leak into AGENTS.md (sanity check, adjust per project)
grep -i 'mcp\|xcodebuildmcp' AGENTS.md
```

If any agent-specific terms appear in AGENTS.md outside the cross-reference block, move them.

### 6. Stamp `updated:` on every file you edited

This step is shared with `organize`. See `commands/organize.md` § Step 7 — same logic applies: bump `updated:` only when content actually changed.

### 7. Do not commit

Stage changes; let the user commit when they're satisfied.

---

## Examples

### Example 1: Produciesta (real project)

**Before:**
- `AGENTS.md` (643 lines) mixed universal + Claude MCP + Gemini hints
- `CLAUDE.md` (27 lines) redirected to AGENTS.md
- `GEMINI.md` (27 lines) redirected to AGENTS.md

**After:**
- `AGENTS.md` (637 lines): product, CLI, architecture, testing, universal rules
- `CLAUDE.md` (135 lines): MCP servers, Claude build prefs, Claude-only rules
- `GEMINI.md` (44 lines): standard CLI tools, future Gemini-API placeholder

**Extracted from AGENTS.md to CLAUDE.md:**
- Section: XcodeBuildMCP Tools
- Critical Rule: ALWAYS use XcodeBuildMCP tools
- Critical Rule: NEVER use `swift build` / `swift test`

### Example 2: Swift Library

**AGENTS.md (universal):** library architecture, API design, DocC generation, release process (tags, GitHub releases), SPM test requirements.

**CLAUDE.md:** XcodeBuildMCP for swift_package_test; ASC MCP for TestFlight (if applicable); xcodebuild over swift build.

**GEMINI.md:** Standard `swift test` commands; CI workflow patterns; DocC with standard tools.

---

## Troubleshooting

**Circular references** — `AGENTS.md` should never say "see CLAUDE.md first". Foundation flows downhill: AGENTS.md → agent-specific files, never the reverse.

**Duplication** — If the same content shows up in two files, pick one home. Universal → AGENTS.md; agent-specific → that agent's file. Always reference, never duplicate.

**Too many agent files** — If an agent needs <10 lines, leave a stub or skip the file. Only create dedicated files for agents with 30+ lines of unique content. Five empty agent files are worse than one well-organized AGENTS.md.

---

## Best Practices

1. Start with AGENTS.md (universal).
2. Agent files are extensions, never replacements.
3. One source of truth; never duplicate.
4. Explicit cross-references: "Read [AGENTS.md](AGENTS.md) first".
5. Stamp `updated:` only when you actually edited.
6. Only add agent files when there's substantial content (30+ lines).
