#!/usr/bin/env python3
"""Check that every character in a scene is in CAST.md and has a selected
reference portrait. Prints JSON; exits 1 if anyone is missing.

    preflight.py <project-dir> NAME [NAME ...]
"""
import json
import os
import re
import sys


def cast_members(project):
    """{NAME: {key: value}} from CAST.md's front matter (no YAML dependency)."""
    path = os.path.join(project, "CAST.md")
    if not os.path.isfile(path):
        sys.exit(f"no CAST.md in {project}")
    members, current = {}, None
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^- character:\s*(.+?)\s*$", line)
        if m:
            current = members.setdefault(m.group(1).strip("'\""), {})
            continue
        m = re.match(r"^  (\w+):\s*(.*?)\s*$", line)
        if m and current is not None:
            current[m.group(1)] = m.group(2).strip("'\"")
    return members


def check(project, names):
    members = cast_members(project)
    ok, missing = [], []
    for name in names:
        member = members.get(name)
        if member is None:
            missing.append({"character": name, "reason": "not in CAST.md"})
            continue
        rel = member.get("manifest")
        if not rel:
            missing.append({"character": name, "reason": "CAST.md entry has no manifest: (no character record yet)"})
            continue
        manifest = os.path.join(project, rel)
        if not os.path.isfile(manifest):
            missing.append({"character": name, "reason": f"manifest not found: {rel}"})
            continue
        assets = json.load(open(manifest, encoding="utf-8")).get("assets", [])
        selected = [a for a in assets if a.get("kind") == "portrait" and a.get("status") == "selected"]
        cdir = os.path.dirname(manifest)
        portrait = os.path.join(cdir, selected[0]["path"]) if selected else None
        if not portrait or not os.path.isfile(portrait):
            missing.append({"character": name, "reason": "no selected reference portrait"})
            continue
        description = os.path.join(cdir, "CHARACTER.md")
        ok.append({
            "character": name,
            "portrait": portrait,
            "description": description if os.path.isfile(description) else None,
        })
    return {"project": os.path.abspath(project), "ok": ok, "missing": missing}


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    result = check(sys.argv[1], sys.argv[2:])
    print(json.dumps(result, indent=2))
    sys.exit(1 if result["missing"] else 0)
