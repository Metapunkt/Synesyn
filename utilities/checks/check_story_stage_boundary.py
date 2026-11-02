#!/usr/bin/env python3
"""
Story Stage boundary checker.

Policy
------
Story Stage is a component that any application can host (ADR 0029). Everything
it needs from its surroundings comes through a `StoryStageHost` and a
`StoryStageVoice`; it never reaches into the application directly. So scripts in
the stage folder must not:

- name a project autoload (`Global`, `StoryState`, `VoiceService`, ...);
- name a `class_name` declared outside the stage folder;
- load or preload a `res://` path outside the stage folder.

Any of these would compile and run inside ScenSyn and then break the first time
the stage is dropped into another project.

Scope
-----
The stage folder is `synesyn_client/addons/story_stage` once it has moved there,
otherwise `synesyn_client/ScenSyn/story_stage`. Only `.gd` files are scanned;
scenes may reference application art that the host supplies.

Exit code is 1 on any violation.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Depends on this file living at utilities/checks/; update if it is moved.
REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_DIR = REPO_ROOT / "synesyn_client"
PROJECT_GODOT = PROJECT_DIR / "project.godot"
STAGE_DIRS = ("addons/story_stage", "ScenSyn/story_stage")

_AUTOLOAD_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\"\*?(?:res|uid)://")
_CLASS_NAME = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
_RES_PATH = re.compile(r"[\"'](res://[^\"']+)[\"']")
_STRING = re.compile(r"\"[^\"]*\"|'[^']*'")
_TRIPLE_QUOTED = re.compile(r'"""(?:.|\n)*?"""')


def stage_dir() -> Path | None:
    for rel in STAGE_DIRS:
        candidate = PROJECT_DIR / rel
        if any(candidate.rglob("*.gd")):
            return candidate
    return None


def read_autoload_names() -> set[str]:
    names: set[str] = set()
    in_section = False
    for raw in PROJECT_GODOT.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("["):
            in_section = line == "[autoload]"
            continue
        match = _AUTOLOAD_LINE.match(line) if in_section else None
        if match:
            names.add(match.group(1))
    return names


def read_class_names(stage: Path) -> tuple[set[str], set[str]]:
    """Return (class names declared inside the stage, class names declared outside it)."""
    inside: set[str] = set()
    outside: set[str] = set()
    for path in PROJECT_DIR.rglob("*.gd"):
        if ".godot" in path.parts:
            continue
        try:
            found = _CLASS_NAME.findall(path.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            continue
        (inside if stage in path.parents else outside).update(found)
    return inside, outside - inside


def _code_lines(text: str) -> list[str]:
    blanked = _TRIPLE_QUOTED.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    return blanked.splitlines()


def scan(stage: Path) -> list[str]:
    autoloads = read_autoload_names()
    _inside, foreign_classes = read_class_names(stage)
    # An autoload that is also a class_name inside the stage is the stage's own.
    names = sorted((autoloads | foreign_classes) - _inside)
    ident = re.compile(r"\b(" + "|".join(re.escape(n) for n in names) + r")\b") if names else None
    stage_res = "res://" + stage.relative_to(PROJECT_DIR).as_posix() + "/"
    allowed_scene_prefixes = (stage_res, "res://addons/synesyn_core/")

    problems: list[str] = []
    for path in sorted(stage.rglob("*.gd")):
        rel = path.relative_to(PROJECT_DIR).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(_code_lines(text), start=1):
            stripped = line.lstrip()
            if stripped.startswith("#") or stripped.startswith("##"):
                continue
            for res in _RES_PATH.findall(line):
                if not res.startswith(stage_res):
                    problems.append(f"{rel}:{line_no}: path outside the stage: {res}")
            code = _STRING.sub('""', line.split("#", 1)[0])
            if ident:
                for match in ident.finditer(code):
                    kind = "autoload" if match.group(1) in autoloads else "application class"
                    problems.append(f"{rel}:{line_no}: {kind} {match.group(1)}: {line.strip()}")
    for path in sorted(stage.rglob("*.tscn")):
        rel = path.relative_to(PROJECT_DIR).as_posix()
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(text.splitlines(), start=1):
            for res in _RES_PATH.findall(line):
                if not res.startswith(allowed_scene_prefixes):
                    problems.append(f"{rel}:{line_no}: scene path outside the addon boundary: {res}")
    return problems


def main() -> int:
    stage = stage_dir()
    if stage is None:
        print("FAIL: no Story Stage scripts found in " + " or ".join(STAGE_DIRS))
        return 1
    problems = scan(stage)
    rel = stage.relative_to(PROJECT_DIR).as_posix()
    if not problems:
        print(f"PASS: {rel} reaches its surroundings only through its host and voice.")
        return 0
    print(f"FAIL: {len(problems)} boundary violation(s) in {rel}:\n")
    for row in problems:
        print(f"  {row}")
    print("\nRoute the dependency through StoryStageHost or StoryStageVoice instead.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
