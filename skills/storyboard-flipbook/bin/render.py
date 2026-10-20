#!/usr/bin/env python3
"""Render a storyboard plan with the signed Vinetas CLI.

    render.py <plan.json> [--only plate|N[,N...]] [--seed S] [--dry-run] [--no-open]

Renders the empty-room plate (if the plan has one and it isn't rendered yet),
then each frame, using the characters' selected portraits and the plate as
reference images. Results land in
<project>/characters/.generations/scenes/<slug>/ and the plan is updated with
the file names. See SKILL.md for the plan format.
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import preflight  # noqa: E402

GROUP = "group.intrusive-memory.models"
STAGING = os.path.expanduser(f"~/Library/Group Containers/{GROUP}/vinetas-out")
WRAPPER = os.path.expanduser("~/.claude/skills/vinetas-cli/bin/vinetas")
ORDINALS = ["first", "second", "third"]


def find_cli():
    """A signed VinetasCLI whose `generate` takes --reference."""
    candidates = []
    if os.environ.get("VINETAS_CLI"):
        candidates.append(os.environ["VINETAS_CLI"])
    candidates.append("/Applications/Vinetas.app/Contents/MacOS/VinetasCLI")
    base = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
    for config in ("Release", "Debug"):
        candidates += sorted(glob.glob(f"{base}/Vinetas-*/Build/Products/{config}/Vinetas.app/Contents/MacOS/VinetasCLI"))
    for binary in candidates:
        if not os.access(binary, os.X_OK):
            continue
        help_text = subprocess.run([binary, "generate", "--help"], capture_output=True, text=True).stdout
        if "--reference" in help_text:
            return binary
    sys.exit("No VinetasCLI with reference-image support (generate --reference) was found.\n"
             "Install a Vinetas build based on SwiftVinetas 0.21.0 or later, or set VINETAS_CLI.")


def generate(binary, prompt, refs, out, plan, seed, log):
    env = dict(os.environ, VINETAS_CLI=binary, ACERVO_APP_GROUP_ID=GROUP)
    env.pop("ACERVO_MODELS_DIR", None)
    command = [WRAPPER] if os.access(WRAPPER, os.X_OK) else [binary]
    command += ["generate", prompt]
    for ref in refs:
        command += ["-r", ref]
    if plan.get("style"):
        command += ["-s", plan["style"]]
    command += ["--width", str(plan.get("width", 2144)), "--height", str(plan.get("height", 1200)),
                "--steps", str(plan.get("steps", 8)), "--seed", str(seed),
                "--model", plan.get("model", "klein4b"), "-o", out]
    for attempt in (1, 2):  # one retry: macOS can kill a render for hogging the GPU
        with open(log, "w") as handle:
            code = subprocess.run(command, env=env, stdout=handle, stderr=subprocess.STDOUT).returncode
        if code == 0 and os.path.isfile(out):
            return True
        print(f"  attempt {attempt} failed (exit {code}); see {log}")
    return False


def compose(prompt, order):
    """Replace {ref:NAME} and {ref:room} with 'the first reference image' etc."""
    def swap(match):
        key = match.group(1)
        if key not in order:
            sys.exit(f"prompt uses {{ref:{key}}} but that reference isn't attached to this frame "
                     f"(attached: {', '.join(order) or 'none'})")
        return f"the {ORDINALS[order.index(key)]} reference image"
    return re.sub(r"\{ref:([^}]+)\}", swap, prompt)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("plan")
    parser.add_argument("--only", help="'plate', or frame numbers like 2 or 1,3")
    parser.add_argument("--seed", type=int, help="override the seed for the selected renders (and save it)")
    parser.add_argument("--dry-run", action="store_true", help="print the composed prompts; render nothing")
    parser.add_argument("--no-open", action="store_true", help="don't open results in Preview")
    args = parser.parse_args()

    plan_path = os.path.abspath(args.plan)
    plan = json.load(open(plan_path, encoding="utf-8"))
    frames = plan["frames"]
    if plan.get("count") != len(frames):
        sys.exit(f"plan says count={plan.get('count')} but has {len(frames)} frames")
    project, slug = plan["project"], plan["slug"]
    gen = os.path.join(project, "characters", ".generations", "scenes", slug)
    stage = os.path.join(STAGING, slug)

    names = sorted({name for frame in frames for name in frame.get("characters", [])})
    cast = preflight.check(project, names)
    if cast["missing"]:
        for entry in cast["missing"]:
            print(f"BLOCKED  {entry['character']}: {entry['reason']}")
        sys.exit(1)
    portraits = {entry["character"]: entry["portrait"] for entry in cast["ok"]}

    want_plate = args.only in (None, "plate")
    want_frames = [] if args.only == "plate" else (
        [int(n) for n in args.only.split(",")] if args.only else list(range(1, len(frames) + 1)))

    binary = None if args.dry_run else find_cli()
    if not args.dry_run:
        os.makedirs(gen, exist_ok=True)
        os.makedirs(stage, exist_ok=True)
        for name, portrait in portraits.items():
            shutil.copyfile(portrait, os.path.join(stage, f"{name.replace(' ', '_')}.png"))

    def finish(name, staged):
        final = os.path.join(gen, name + ".png")
        shutil.move(staged, final)
        sidecar = staged[:-4] + ".json"
        if os.path.isfile(sidecar):
            shutil.move(sidecar, os.path.join(gen, name + ".json"))
        if not args.no_open:
            subprocess.run(["open", "-a", "Preview", final])
        return name + ".png"

    failed = []
    plate = plan.get("plate")
    plate_file = os.path.join(gen, plate["file"]) if plate and plate.get("file") else None
    plate_missing = plate and not (plate_file and os.path.isfile(plate_file))
    if plate and want_plate and (args.only == "plate" or plate_missing):
        seed = args.seed if (args.seed is not None and args.only == "plate") else plate.get("seed", 7)
        name = f"{slug}-plate-s{seed}"
        print(f"plate  seed {seed}")
        if args.dry_run:
            print("  " + plate["prompt"])
        else:
            open(os.path.join(gen, name + ".prompt.txt"), "w").write(plate["prompt"])
            staged = os.path.join(stage, name + ".png")
            if generate(binary, plate["prompt"], [], staged, plan, seed, os.path.join(gen, name + ".log")):
                plate["seed"], plate["file"] = seed, finish(name, staged)
                plate_file = os.path.join(gen, plate["file"])
                json.dump(plan, open(plan_path, "w"), indent=2)
            else:
                failed.append("plate")

    for number in want_frames:
        frame = frames[number - 1]
        people = frame.get("characters", [])
        order = list(people)
        refs = [os.path.join(stage, f"{name.replace(' ', '_')}.png") for name in people]
        use_plate = bool(plate) and frame.get("plate", True) and len(order) < 3
        if use_plate:
            order.append("room")
            if not args.dry_run:
                if not (plate_file and os.path.isfile(plate_file)):
                    sys.exit("the plate hasn't rendered; run with --only plate first")
                staged_plate = os.path.join(stage, "room.png")
                shutil.copyfile(plate_file, staged_plate)
                refs.append(staged_plate)
        if len(order) > 3:
            sys.exit(f"frame {number}: {len(order)} references; Vinetas takes at most 3")
        seed = args.seed if (args.seed is not None and args.only not in (None, "plate")) else frame.get("seed", 22)
        prompt = compose(frame["prompt"], order)
        name = f"{slug}-{number:02d}-s{seed}"
        print(f"frame {number}  seed {seed}  refs: {', '.join(order) or 'none'}")
        if args.dry_run:
            print("  " + prompt)
            continue
        open(os.path.join(gen, name + ".prompt.txt"), "w").write(prompt)
        staged = os.path.join(stage, name + ".png")
        if generate(binary, prompt, refs, staged, plan, seed, os.path.join(gen, name + ".log")):
            frame["seed"], frame["file"] = seed, finish(name, staged)
            json.dump(plan, open(plan_path, "w"), indent=2)
        else:
            failed.append(f"frame {number}")

    if failed:
        sys.exit("failed: " + ", ".join(failed))
    if not args.dry_run:
        print(gen)


if __name__ == "__main__":
    main()
