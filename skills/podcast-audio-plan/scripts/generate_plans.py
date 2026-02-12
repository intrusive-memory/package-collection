#!/usr/bin/env python3
"""
Generate AUDIO_GENERATION_PLAN.md and AUDIO_SPRINT_TASKS.md from templates.
"""

import sys
import json
from pathlib import Path
from datetime import datetime


def load_template(template_path):
    """Load a template file."""
    with open(template_path, 'r', encoding='utf-8') as f:
        return f.read()


def render_template(template, context):
    """Simple template rendering with {{variable}} syntax."""
    result = template
    for key, value in context.items():
        placeholder = f"{{{{{key}}}}}"
        result = result.replace(placeholder, str(value))
    return result


def generate_cast_table(cast_info):
    """Generate markdown table of cast members with voice URIs."""
    lines = [
        "| Character | Description | ElevenLabs Voice | Apple TTS Fallback |",
        "|-----------|-------------|------------------|-------------------|"
    ]

    for member in cast_info:
        char = member['character']
        desc = member['description'][:50] + "..." if len(member['description']) > 50 else member['description']
        el_voice = member['elevenlabs_voice']
        apple_voice = member['apple_voice']
        lines.append(f"| {char} | {desc} | `{el_voice}` | `{apple_voice}` |")

    return '\n'.join(lines)


def generate_episode_tasks(episodes):
    """Generate task list for each episode."""
    lines = []
    for i, episode in enumerate(episodes, 1):
        episode_name = episode['episode']
        char_count = len(episode['characters'])
        lines.append(f"{i}. **{episode_name}**")
        lines.append(f"   - Characters: {char_count}")
        lines.append(f"   - Characters: {', '.join(episode['characters'][:5])}")
        if len(episode['characters']) > 5:
            lines.append(f"     (and {len(episode['characters']) - 5} more)")
        lines.append("")

    return '\n'.join(lines)


def main():
    if len(sys.argv) < 5:
        print("Usage: generate_plans.py <project_json> <episodes_json> <template_dir> <output_dir>", file=sys.stderr)
        sys.exit(1)

    project_json = Path(sys.argv[1])
    episodes_json = Path(sys.argv[2])
    template_dir = Path(sys.argv[3])
    output_dir = Path(sys.argv[4])

    # Load data
    with open(project_json) as f:
        project_data = json.load(f)

    with open(episodes_json) as f:
        episodes_data = json.load(f)

    # Load templates
    gen_plan_template = load_template(template_dir / 'AUDIO_GENERATION_PLAN.template.md')
    sprint_tasks_template = load_template(template_dir / 'AUDIO_SPRINT_TASKS.template.md')

    # Prepare context
    context = {
        'project_title': project_data['title'],
        'date': datetime.now().strftime('%Y-%m-%d'),
        'episode_count': len(episodes_data),
        'cast_count': len(project_data['cast']),
        'cast_table': generate_cast_table(project_data['cast']),
        'episode_tasks': generate_episode_tasks(episodes_data)
    }

    # Render and save
    gen_plan = render_template(gen_plan_template, context)
    sprint_tasks = render_template(sprint_tasks_template, context)

    output_dir.mkdir(parents=True, exist_ok=True)

    (output_dir / 'AUDIO_GENERATION_PLAN.md').write_text(gen_plan, encoding='utf-8')
    (output_dir / 'AUDIO_SPRINT_TASKS.md').write_text(sprint_tasks, encoding='utf-8')

    print(f"✅ Generated AUDIO_GENERATION_PLAN.md")
    print(f"✅ Generated AUDIO_SPRINT_TASKS.md")
    print(f"📁 Output directory: {output_dir}")


if __name__ == '__main__':
    main()
