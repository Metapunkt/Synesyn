#!/usr/bin/env python3
"""
Story Stage drop-in test.

Builds a throwaway Godot project that contains only `addons/story_stage` and
`addons/synesyn_core` - no ScenSyn, no autoloads, no hub - and runs the stage
headless on a minimal host that hands it three scripted lines. Passes when all
three lines reach the dialogue box, the process exits 0, and Godot printed no
errors.

This is what "Story Stage is a component" (ADR 0029) means in practice: anything
the stage still takes from ScenSyn shows up here as a parse or runtime error.

Needs a Godot 4.7 binary: `godot` on PATH, or set GODOT_BIN.

Usage:
    python utilities/checks/story_stage_dropin_test.py [--keep]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Depends on this file living at utilities/checks/; update if it is moved.
REPO_ROOT = Path(__file__).resolve().parents[2]
ADDONS = REPO_ROOT / "synesyn_client" / "addons"
COPIED_ADDONS = ("story_stage", "synesyn_core")
LINES = [
    ("Narrator", "The room is quiet."),
    ("Didi", "Are we waiting for someone?"),
    ("Gogo", "We always are."),
]
TIMEOUT_SEC = 120

PROJECT_GODOT = """config_version=5

[application]

config/name="StoryStageDropIn"
config/features=PackedStringArray("4.7")

[rendering]

renderer/rendering_method="gl_compatibility"
"""

HOST_GD = """extends StoryStageHost
## A host that knows three lines and nothing else.

var _entries: Array = []

func _init(lines: Array) -> void:
\tfor pair in lines:
\t\t_entries.append({"sender": pair[0], "message": pair[1]})

func get_story_log_entries() -> Array:
\treturn _entries
"""

RUNNER_GD = """extends SceneTree

const LINES := %s
const STAGE_SCENE := "res://addons/story_stage/scenes/story_stage.tscn"

var _shown: Array = []
var _deadline_msec := 0

func _init() -> void:
\tprocess_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
\tvar stage = load(STAGE_SCENE).instantiate()
\tstage.host = load("res://dropin_host.gd").new(LINES)
\tstage.line_displayed.connect(_on_line)
\troot.add_child(stage)
\t_deadline_msec = Time.get_ticks_msec() + %d * 1000
\tprocess_frame.connect(_watch)

func _on_line(sender: String, message: String, index: int) -> void:
\tprint("DROPIN line %%d: [%%s] %%s" %% [index, sender, message])
\t_shown.append([sender, message])

func _watch() -> void:
\tif _shown.size() >= LINES.size():
\t\t_finish()
\telif Time.get_ticks_msec() > _deadline_msec:
\t\tprint("DROPIN timeout after %%d of %%d lines" %% [_shown.size(), LINES.size()])
\t\tquit(1)

func _finish() -> void:
\tprocess_frame.disconnect(_watch)
\tfor i in LINES.size():
\t\tif _shown[i][0] != LINES[i][0] or _shown[i][1] != LINES[i][1]:
\t\t\tprint("DROPIN mismatch at line %%d: %%s" %% [i, str(_shown[i])])
\t\t\tquit(1)
\t\t\treturn
\tprint("DROPIN ok")
\tquit(0)
"""

ERROR_LINE = re.compile(r"^(SCRIPT ERROR|ERROR|USER ERROR)\b")


def godot_bin() -> str:
    for env_key in ("GODOT_BIN", "SYNESYN_GODOT_PATH"):
        val = os.environ.get(env_key, "").strip()
        if val and Path(val).exists():
            return val
    cfg_path = REPO_ROOT / "docs" / "technical-review" / "run_specs" / "devagent_config.json"
    if cfg_path.exists():
        try:
            cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
            cfg_godot = str(cfg.get("godot_path", "")).strip()
            if cfg_godot and Path(cfg_godot).exists():
                return cfg_godot
        except (OSError, ValueError):
            pass
    found = shutil.which("godot")
    if not found:
        sys.exit("FAIL: no Godot binary; put godot on PATH or set GODOT_BIN / SYNESYN_GODOT_PATH")
    return found


def build_project(root: Path) -> None:
    for name in COPIED_ADDONS:
        shutil.copytree(ADDONS / name, root / "addons" / name)
    (root / "project.godot").write_text(PROJECT_GODOT, encoding="utf-8")
    (root / "dropin_host.gd").write_text(HOST_GD, encoding="utf-8")
    lines = "[" + ", ".join(f'["{s}", "{m}"]' for s, m in LINES) + "]"
    (root / "dropin_runner.gd").write_text(RUNNER_GD % (lines, TIMEOUT_SEC), encoding="utf-8")


def run(godot: str, root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [godot, "--headless", "--path", str(root), *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        timeout=TIMEOUT_SEC + 60,
    )


def errors_in(output: str) -> list[str]:
    return [line for line in output.splitlines() if ERROR_LINE.match(line.strip())]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keep", action="store_true", help="keep the temporary project for inspection")
    args = parser.parse_args()

    godot = godot_bin()
    root = Path(tempfile.mkdtemp(prefix="story_stage_dropin_"))
    try:
        build_project(root)
        imported = run(godot, root, "--import")
        played = run(godot, root, "--script", "res://dropin_runner.gd")
        output = imported.stdout + imported.stderr + played.stdout + played.stderr
        errors = errors_in(output)
        shown = [l for l in played.stdout.splitlines() if l.startswith("DROPIN line")]
        for line in shown:
            print("  " + line)
        ok = played.returncode == 0 and "DROPIN ok" in played.stdout and not errors
        if ok:
            print(f"PASS: Story Stage played {len(shown)} lines in a project with only {', '.join(COPIED_ADDONS)}.")
            return 0
        print(f"FAIL: exit code {played.returncode}, {len(shown)} of {len(LINES)} lines shown, {len(errors)} error line(s).")
        for line in errors[:40]:
            print("  " + line)
        if not errors:
            print(played.stdout[-3000:])
        return 1
    finally:
        if args.keep:
            print(f"Kept: {root}")
        else:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
