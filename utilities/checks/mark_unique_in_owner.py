#!/usr/bin/env python3
"""
Mark Godot .tscn nodes as unique_name_in_owner=true for every node referenced via %Name in a .gd script.

Usage:
  python synesyn/utilities/checks/mark_unique_in_owner.py path/to/script.gd path/to/scene.tscn

Notes:
- Only adds the flag if it's missing in that node block.
- Keeps the file formatting stable (inserts the flag immediately after the [node ...] header).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PERCENT_REF_RE = re.compile(r"%([A-Za-z_][A-Za-z0-9_]*)")
NODE_HEADER_RE = re.compile(r'^\[node name="([^"]+)" ')


def extract_percent_refs(gd_text: str) -> set[str]:
    return set(PERCENT_REF_RE.findall(gd_text))


def patch_tscn_unique_flags(tscn_text: str, names: set[str]) -> tuple[str, int]:
    lines = tscn_text.splitlines(True)
    out: list[str] = []
    inserted = 0

    i = 0
    while i < len(lines):
        line = lines[i]
        m = NODE_HEADER_RE.match(line)
        out.append(line)

        if m:
            node_name = m.group(1)
            if node_name in names:
                # Look ahead within this node block to see if unique_name_in_owner already exists.
                j = i + 1
                found = False
                while j < len(lines) and not lines[j].startswith("[node "):
                    if lines[j].lstrip().startswith("unique_name_in_owner"):
                        found = True
                        break
                    j += 1
                if not found:
                    out.append("unique_name_in_owner = true\n")
                    inserted += 1

        i += 1

    return ("".join(out), inserted)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("Usage: python mark_unique_in_owner.py path/to/script.gd path/to/scene.tscn", file=sys.stderr)
        return 2

    gd_path = Path(argv[1])
    tscn_path = Path(argv[2])

    gd_text = gd_path.read_text(encoding="utf-8")
    names = extract_percent_refs(gd_text)
    if not names:
        print(f"No %Name references found in {gd_path}")
        return 0

    tscn_text = tscn_path.read_text(encoding="utf-8")
    patched, inserted = patch_tscn_unique_flags(tscn_text, names)
    if inserted > 0:
        tscn_path.write_text(patched, encoding="utf-8")
    print(f"{tscn_path}: added unique_name_in_owner=true for {inserted} node(s) (tracked {len(names)} %ref name(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))


