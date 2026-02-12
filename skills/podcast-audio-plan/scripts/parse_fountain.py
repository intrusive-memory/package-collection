#!/usr/bin/env python3
"""
Parse Fountain screenplay files and extract dialogue with character usage.
"""

import sys
import json
import re
from pathlib import Path
from collections import defaultdict


def parse_fountain(content):
    """Parse a Fountain file and extract dialogue by character."""
    lines = content.split('\n')

    dialogue_by_character = defaultdict(list)
    current_character = None
    current_dialogue = []

    for line in lines:
        # Character name (all caps, centered)
        if line.strip().isupper() and line.strip() and not line.startswith('INT.') and not line.startswith('EXT.'):
            # Save previous dialogue
            if current_character and current_dialogue:
                dialogue_by_character[current_character].append(' '.join(current_dialogue))
                current_dialogue = []

            # Start new character
            current_character = line.strip()
            continue

        # Dialogue (indented text after character name)
        if current_character and line.strip() and not line.startswith('('):
            current_dialogue.append(line.strip())

        # Empty line ends dialogue
        if not line.strip() and current_character and current_dialogue:
            dialogue_by_character[current_character].append(' '.join(current_dialogue))
            current_dialogue = []
            current_character = None

    # Save final dialogue
    if current_character and current_dialogue:
        dialogue_by_character[current_character].append(' '.join(current_dialogue))

    return dict(dialogue_by_character)


def analyze_character_usage(dialogue_by_character):
    """Generate statistics about character usage."""
    stats = {}
    for character, dialogues in dialogue_by_character.items():
        total_lines = len(dialogues)
        total_words = sum(len(d.split()) for d in dialogues)
        stats[character] = {
            'line_count': total_lines,
            'word_count': total_words
        }
    return stats


def main():
    if len(sys.argv) < 2:
        print("Usage: parse_fountain.py <path/to/episode.fountain>", file=sys.stderr)
        sys.exit(1)

    fountain_path = Path(sys.argv[1])

    if not fountain_path.exists():
        print(f"Error: {fountain_path} not found", file=sys.stderr)
        sys.exit(1)

    with open(fountain_path, 'r', encoding='utf-8') as f:
        content = f.read()

    dialogue_by_character = parse_fountain(content)
    stats = analyze_character_usage(dialogue_by_character)

    # Output as JSON
    print(json.dumps({
        'episode': fountain_path.stem,
        'characters': list(dialogue_by_character.keys()),
        'stats': stats
    }, indent=2))


if __name__ == '__main__':
    main()
