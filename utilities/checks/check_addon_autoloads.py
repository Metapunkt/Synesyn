#!/usr/bin/env python3
"""
Addon autoload-access guardrail checker.

Policy
------
Scripts under `synesyn_client/addons/**` must not reference project autoloads by
bare global identifier (e.g. `ContentBus.foo()`). Bare identifiers only resolve
while the autoload is live, so such scripts fail to compile in a fresh drop-in
project, or in headless tooling that loads scripts before autoloads register.
Because the editor always has autoloads live, the mistake produces no local
feedback — hence this check.

Instead, resolve through the scene tree at use time:
- SynTree-owned autoloads: `addons/syntree/scripts/autoload/syntree_autoloads.gd`
- Host/project autoloads:  `addons/synesyn_core/scripts/synesyn_autoload_access.gd`

Never cache a resolved autoload in a field: one that registers later would leave
the cached value null forever.

Scope
-----
Autoload names are read from `synesyn_client/project.godot` so the check stays
correct as autoloads are added or removed. Names that are also declared as a
GDScript `class_name` are skipped: those resolve via the script-class registry
rather than the autoload, and are safe to use bare.

Modes
-----
- default: report every violation (exit 1 if any).
- --write-baseline: snapshot current violation counts per file into a baseline
  JSON (the "ratchet"). Commit this file.
- --check-baseline: fail only on regressions relative to the baseline — a new
  offending file, or a baselined file with more violations than recorded.
  Pre-existing violations that stay the same or shrink pass.

Regenerate the baseline whenever you legitimately reduce a file, so its improved
count becomes the new ceiling.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Depends on this file living at utilities/checks/; update if it is moved.
REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_DIR = REPO_ROOT / "synesyn_client"
ADDONS_DIR = PROJECT_DIR / "addons"
PROJECT_GODOT = PROJECT_DIR / "project.godot"

DEFAULT_BASELINE = Path(__file__).with_name("addon_autoload_baseline.json")

# Resolver scripts are allowed to name autoloads: that is their job.
EXEMPT_FILES = {
    "addons/syntree/scripts/autoload/syntree_autoloads.gd",
    "addons/synesyn_core/scripts/synesyn_autoload_access.gd",
}

# Autoload targets may be given as res:// paths or as uid:// references.
_AUTOLOAD_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\"\*?(?:res|uid)://")
_CLASS_NAME = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.MULTILINE)
_STRING = re.compile(r"\"[^\"]*\"|'[^']*'")
_TRIPLE_QUOTED = re.compile(r'"""(?:.|\n)*?"""')


def _blank_docstrings(text: str) -> str:
    """Blank out triple-quoted blocks, preserving line numbering."""

    def repl(match: re.Match[str]) -> str:
        return "\n" * match.group(0).count("\n")

    return _TRIPLE_QUOTED.sub(repl, text)


def read_autoload_names() -> list[str]:
    """Parse the [autoload] section of project.godot."""
    if not PROJECT_GODOT.exists():
        return []
    names: list[str] = []
    in_section = False
    for raw in PROJECT_GODOT.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("["):
            in_section = line == "[autoload]"
            continue
        if not in_section:
            continue
        match = _AUTOLOAD_LINE.match(line)
        if match:
            names.append(match.group(1))
    return names


def read_global_class_names() -> set[str]:
    """Names declared via `class_name` resolve without the autoload being live."""
    found: set[str] = set()
    if not PROJECT_DIR.exists():
        return found
    for path in PROJECT_DIR.rglob("*.gd"):
        if ".godot" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        found.update(_CLASS_NAME.findall(text))
    return found


def scan(names: list[str]) -> dict[str, list[tuple[int, str, str]]]:
    """Return {relative_path: [(line_no, autoload_name, line_text), ...]}."""
    if not names or not ADDONS_DIR.exists():
        return {}
    pattern = re.compile(r"\b(" + "|".join(re.escape(n) for n in names) + r")\b")
    violations: dict[str, list[tuple[int, str, str]]] = {}

    for path in sorted(ADDONS_DIR.rglob("*.gd")):
        if ".godot" in path.parts:
            continue
        rel = path.relative_to(PROJECT_DIR).as_posix()
        if rel in EXEMPT_FILES:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        # Triple-quoted blocks are prose, not code; blank them before scanning.
        lines = _blank_docstrings(text).splitlines()

        hits: list[tuple[int, str, str]] = []
        for line_no, line in enumerate(lines, start=1):
            if line.lstrip().startswith("#"):
                continue
            code = _STRING.sub('""', line)
            # A preload const legitimately binds the name locally.
            if re.search(r"\b(const|var)\s+\w+\s*=\s*preload", code):
                continue
            for match in pattern.finditer(code):
                hits.append((line_no, match.group(1), line.strip()))
        if hits:
            violations[rel] = hits
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-baseline", action="store_true")
    parser.add_argument("--check-baseline", action="store_true")
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    autoloads = read_autoload_names()
    class_names = read_global_class_names()
    names = [n for n in autoloads if n not in class_names]
    skipped = sorted(set(autoloads) & class_names)

    violations = scan(names)
    counts = {rel: len(hits) for rel, hits in violations.items()}

    if args.write_baseline:
        args.baseline.write_text(
            json.dumps({"counts": counts}, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote baseline: {args.baseline} ({len(counts)} file(s))")
        return 0

    if not args.quiet:
        print(f"Autoloads checked ({len(names)}): {', '.join(names) or '<none>'}")
        if skipped:
            print(f"Skipped (declared as class_name): {', '.join(skipped)}")
        print()

    if args.check_baseline:
        baseline: dict[str, int] = {}
        if args.baseline.exists():
            baseline = json.loads(args.baseline.read_text(encoding="utf-8")).get("counts", {})
        regressions: list[str] = []
        for rel, count in sorted(counts.items()):
            allowed = baseline.get(rel)
            if allowed is None:
                regressions.append(f"NEW      {rel}: {count} bare autoload reference(s)")
            elif count > allowed:
                regressions.append(f"GREW     {rel}: {count} (baseline {allowed})")
        if regressions:
            print("Bare autoload references regressed:\n")
            for row in regressions:
                print(f"  {row}")
            print(
                "\nResolve autoloads at use time via syntree_autoloads.gd or "
                "synesyn_autoload_access.gd instead of naming them directly."
            )
            return 1
        print("No regressions against baseline.")
        return 0

    if not violations:
        print("PASS: no bare autoload references under addons/.")
        return 0

    total = sum(counts.values())
    print(f"FAIL: {total} bare autoload reference(s) in {len(violations)} file(s):\n")
    for rel, hits in sorted(violations.items()):
        print(f"  {rel}")
        for line_no, name, text in hits:
            print(f"    {line_no:>5}: [{name}] {text}")
    print(
        "\nResolve autoloads at use time via syntree_autoloads.gd or "
        "synesyn_autoload_access.gd instead of naming them directly."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
