#!/usr/bin/env python3
"""Classify markdown files at the root of a project into the four buckets used
by /organize-agent-docs.

Usage:
    classify_files.py [PATH]

PATH defaults to the current working directory. Output is JSON on stdout:

    {
      "project_root": "/abs/path",
      "foundational": [{"path": "AGENTS.md", "kind": "agents", "has_frontmatter": true, "updated": "2026-05-12"}, ...],
      "mission":      [{"path": "EXECUTION_PLAN.md", "state": "current", "mission": "foo-01", "updated": "2026-05-12"}, ...],
      "extraneous":   [{"path": "notes.md"}, ...],
      "ambiguous":    [{"path": "ROADMAP.md", "reasons": ["..."]}, ...],
      "ignored":      [{"path": "LOCAL_NOTES.md", "matched_pattern": "LOCAL_*"}, ...]
    }

This script does NOT move, edit, or stage anything. It only reads files and
emits a classification proposal. The skill agent uses this as a starting point
and then performs file edits using its own tools.
"""

from __future__ import annotations

import fnmatch
import json
import os
import re
import sys
from pathlib import Path


FOUNDATIONAL_NAMES = {
    "AGENTS.md": "agents",
    "CLAUDE.md": "claude",
    "GEMINI.md": "gemini",
    "CURSOR.md": "cursor",
    "COPILOT.md": "copilot",
    "CODEX.md": "codex",
    "README.md": "readme",
    "CHANGELOG.md": "changelog",
    "LICENSE": "license",
    "LICENSE.md": "license",
    "LICENSE.txt": "license",
}

MISSION_NAME_PATTERNS = [
    "EXECUTION_PLAN.md",
    "SUPERVISOR_STATE.md",
    "COMPLETE_*.md",
    "*_BRIEF.md",
    "sortie-*.md",
    "sortie-*.txt",
    "sortie-*.fcpxml",
    "SORTIE-*.md",
]

PROJECT_META_NAMES = {
    "ROADMAP.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "SECURITY.md",
    "SUPPORT.md",
    "GOVERNANCE.md",
    "MAINTAINERS.md",
    "AUTHORS.md",
    "INSTALL.md",
    "BUILDING.md",
    "TESTING.md",
}

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
STATE_RE = re.compile(r"^state:\s*(current|completed|incomplete)\s*$", re.MULTILINE)
UPDATED_RE = re.compile(r"^updated:\s*(\S+)\s*$", re.MULTILINE)
MISSION_RE = re.compile(r"^mission:\s*(\S+)\s*$", re.MULTILINE)


def read_frontmatter(path: Path) -> dict | None:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None
    block = m.group(1)
    out = {}
    sm = STATE_RE.search(block)
    if sm:
        out["state"] = sm.group(1)
    um = UPDATED_RE.search(block)
    if um:
        out["updated"] = um.group(1)
    mm = MISSION_RE.search(block)
    if mm:
        out["mission"] = mm.group(1)
    return out


def matches_any(name: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(name, p) for p in patterns)


def load_extra_foundational(root: Path) -> set[str]:
    path = root / ".organize-agent-docs.foundational"
    if not path.is_file():
        return set()
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines()
        if line.strip() and not line.strip().startswith("#")
    }


def load_ignore_patterns(root: Path) -> list[str]:
    path = root / ".organize-agent-docs.ignore"
    if not path.is_file():
        return []
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def linked_from_foundational(root: Path, foundational_paths: list[Path]) -> set[str]:
    """Return the set of relative paths that appear as link targets in any
    foundational file. Used for the AMBIGUOUS heuristic."""
    link_re = re.compile(r"\]\(([^)#][^)]*\.md)(?:#[^)]*)?\)")
    targets = set()
    for fp in foundational_paths:
        try:
            text = fp.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for m in link_re.finditer(text):
            tgt = m.group(1).lstrip("./")
            targets.add(tgt)
    return targets


def classify(root: Path) -> dict:
    extra_foundational = load_extra_foundational(root)
    ignore_patterns = load_ignore_patterns(root)

    foundational_names_local = dict(FOUNDATIONAL_NAMES)
    for name in extra_foundational:
        foundational_names_local[name] = "custom"

    out = {
        "project_root": str(root),
        "foundational": [],
        "mission": [],
        "extraneous": [],
        "ambiguous": [],
        "ignored": [],
    }

    # Pass 1: collect root-level candidates.
    candidates = []
    for entry in sorted(root.iterdir()):
        if not entry.is_file():
            continue
        if entry.name.startswith("."):
            continue
        # Only markdown + known no-extension foundational names.
        if entry.suffix.lower() not in {".md"} and entry.name not in foundational_names_local:
            continue
        candidates.append(entry)

    # Pass 2: ignored / foundational / mission / extraneous / ambiguous.
    foundational_paths: list[Path] = []
    for entry in candidates:
        name = entry.name
        rel = name  # root level only

        # Ignored?
        matched_pat = next((p for p in ignore_patterns if fnmatch.fnmatchcase(rel, p)), None)
        if matched_pat:
            out["ignored"].append({"path": rel, "matched_pattern": matched_pat})
            continue

        # Foundational?
        if name in foundational_names_local:
            kind = foundational_names_local[name]
            fm = read_frontmatter(entry) or {}
            out["foundational"].append({
                "path": rel,
                "kind": kind,
                "has_frontmatter": bool(fm),
                "updated": fm.get("updated"),
            })
            foundational_paths.append(entry)
            continue

        # Mission by name pattern?
        fm = read_frontmatter(entry) or {}
        is_mission_name = matches_any(name, MISSION_NAME_PATTERNS)
        is_mission_state = fm.get("state") in {"current", "completed", "incomplete"}

        if is_mission_name or is_mission_state:
            entry_out = {
                "path": rel,
                "state": fm.get("state"),
                "mission": fm.get("mission"),
                "updated": fm.get("updated"),
            }
            # If filename pattern matches but no state, downstream skill defaults to "current".
            if not is_mission_name and is_mission_state:
                entry_out["reason"] = "frontmatter state present; filename not a known mission pattern"
                out["ambiguous"].append({
                    "path": rel,
                    "reasons": [entry_out["reason"]],
                    "hints": {"likely_category": "MISSION (custom)", "frontmatter": fm},
                })
                continue
            out["mission"].append(entry_out)
            continue

        # Ambiguous heuristics
        reasons = []
        if name in PROJECT_META_NAMES:
            reasons.append(
                f"Project-meta filename ({name}) — could be FOUNDATIONAL or EXTRANEOUS depending on team convention"
            )

        # Extraneous fallback (compute now; bump to ambiguous below if needed)
        if reasons:
            out["ambiguous"].append({"path": rel, "reasons": reasons})
        else:
            out["extraneous"].append({"path": rel})

    # Pass 3: bump extraneous to ambiguous if foundational files link to them.
    targets = linked_from_foundational(root, foundational_paths)
    if targets:
        bumped = []
        new_extraneous = []
        for ex in out["extraneous"]:
            if ex["path"] in targets:
                bumped.append({
                    "path": ex["path"],
                    "reasons": [
                        "Referenced as a link target from a FOUNDATIONAL file — user may treat as foundational"
                    ],
                })
            else:
                new_extraneous.append(ex)
        out["extraneous"] = new_extraneous
        out["ambiguous"].extend(bumped)

    return out


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    if not root.is_dir():
        print(json.dumps({"error": f"Not a directory: {root}"}), file=sys.stderr)
        return 2
    result = classify(root)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
