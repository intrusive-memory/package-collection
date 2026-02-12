#!/usr/bin/env python3
"""
Parse PROJECT.md YAML front matter and extract cast information.
"""

import sys
import yaml
import json
from pathlib import Path


def parse_project_yaml(project_path):
    """Extract YAML front matter from PROJECT.md."""
    with open(project_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Extract YAML front matter between --- delimiters
    if not content.startswith('---'):
        return None

    parts = content.split('---', 2)
    if len(parts) < 3:
        return None

    yaml_content = parts[1].strip()
    return yaml.safe_load(yaml_content)


def extract_cast_info(yaml_data):
    """Extract cast members with their voice URIs."""
    if not yaml_data or 'cast' not in yaml_data:
        return []

    cast_members = []
    for member in yaml_data['cast']:
        character = member.get('character', 'UNKNOWN')
        description = member.get('description', '')
        voices = member.get('voices', [])

        # Extract ElevenLabs and Apple voices from list
        # First voice is primary (ElevenLabs), second is fallback (Apple TTS)
        elevenlabs_voice = voices[0] if len(voices) > 0 else ''
        apple_voice = voices[1] if len(voices) > 1 else ''

        cast_members.append({
            'character': character,
            'description': description,
            'elevenlabs_voice': elevenlabs_voice,
            'apple_voice': apple_voice
        })

    return cast_members


def main():
    if len(sys.argv) < 2:
        print("Usage: analyze_project.py <path/to/PROJECT.md>", file=sys.stderr)
        sys.exit(1)

    project_path = Path(sys.argv[1])

    if not project_path.exists():
        print(f"Error: {project_path} not found", file=sys.stderr)
        sys.exit(1)

    yaml_data = parse_project_yaml(project_path)
    if not yaml_data:
        print("Error: Could not parse YAML front matter", file=sys.stderr)
        sys.exit(1)

    cast_info = extract_cast_info(yaml_data)

    # Output as JSON
    print(json.dumps({
        'title': yaml_data.get('title', 'Unknown'),
        'cast': cast_info
    }, indent=2))


if __name__ == '__main__':
    main()
