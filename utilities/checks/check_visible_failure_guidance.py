#!/usr/bin/env python3
"""CI check: source-run voice/avatar failures stay visible and documented.

Godot headless suites cover behaviour. This script only asserts that the
user-facing strings and docs section still exist, so a refactor cannot drop the
guidance while CI stays green.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

CHECKS: list[tuple[Path, str]] = [
    (
        REPO_ROOT / "synesyn_client/addons/synesyn_core/scripts/hub_locator.gd",
        'Voice unavailable: Synesyn Hub isn\'t running at %s',
    ),
    (
        REPO_ROOT / "synesyn_client/addons/synesyn_core/scripts/runtime_config.gd",
        '"autostart_from_source": false',
    ),
    (
        REPO_ROOT / "synesyn_client/addons/syntree_voice/scripts/services/voice_client.gd",
        "const MAX_REQUEST_QUEUE := 32",
    ),
    (
        REPO_ROOT / "synesyn_client/addons/story_stage/scripts/story_stage_character.gd",
        "Story Stage art pack not installed",
    ),
    (
        REPO_ROOT / "synesyn_client/addons/story_stage/scripts/story_stage_character.gd",
        "utilities/assets/story_stage_sprites.py",
    ),
    (
        REPO_ROOT / "docs/developer-guide/local-dev.md",
        "## Running ScenSyn from source with voice and avatars",
    ),
    (
        REPO_ROOT / "docs/developer-guide/local-dev.md",
        '"autostart_from_source": true',
    ),
    (
        REPO_ROOT / "docs/developer-guide/local-dev.md",
        "python utilities/assets/story_stage_sprites.py",
    ),
]


def main() -> int:
    failures: list[str] = []
    for path, needle in CHECKS:
        if not path.is_file():
            failures.append(f"missing file: {path.relative_to(REPO_ROOT)}")
            continue
        text = path.read_text(encoding="utf-8")
        if needle not in text:
            failures.append(
                f"{path.relative_to(REPO_ROOT)}: missing expected text {needle!r}"
            )
    if failures:
        print("Visible-failure guidance check FAILED:")
        for item in failures:
            print(f"  - {item}")
        return 1
    print(f"Visible-failure guidance check OK ({len(CHECKS)} assertions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
