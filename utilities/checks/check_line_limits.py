#!/usr/bin/env python3
"""
Repo line-limit guardrail checker.

Policy:
- soft warning at 900 lines
- hard violation at 1200 lines

Scope:
- synesyn_client/**/*.gd
- services/synesyn_hub/app/**/*.py

Modes:
- default: report soft warnings + hard violations (exit 1 if any hard violation).
- --write-baseline: snapshot current counts for files at/over the soft limit into
  a baseline JSON (the "ratchet"). Commit this file.
- --check-baseline: fail (exit 1) only on regressions relative to the baseline —
  a brand-new hard violation, or any baselined file that grew. Pre-existing
  violations that stay the same or shrink pass. This lets remediation proceed
  incrementally while preventing the problem from getting worse.

Regenerate the baseline (with --write-baseline) whenever you legitimately reduce a
file, so its improved count becomes the new ceiling.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
import sys

SOFT_LIMIT = 900
HARD_LIMIT = 1200

DEFAULT_BASELINE = Path(__file__).with_name("line_limit_baseline.json")


@dataclass(frozen=True)
class Scope:
    root: Path
    suffix: str


def _line_count(path: Path) -> int:
    text = path.read_text(encoding="utf-8", errors="replace")
    return text.count("\n") + (0 if text.endswith("\n") or text == "" else 1)


def _collect(scope: Scope) -> list[tuple[Path, int]]:
    rows: list[tuple[Path, int]] = []
    if not scope.root.exists():
        return rows
    for path in scope.root.rglob(f"*{scope.suffix}"):
        if not path.is_file():
            continue
        rows.append((path, _line_count(path)))
    return rows


def _normalize_paths(repo_root: Path, path_args: list[str]) -> list[Path]:
    selected: list[Path] = []
    for raw in path_args:
        p = Path(raw)
        abs_p = p if p.is_absolute() else (repo_root / p)
        abs_p = abs_p.resolve()
        if abs_p.is_file():
            selected.append(abs_p)
    return selected


def _gather_rows(repo_root: Path, scopes: list[Scope], selected_paths: list[Path]) -> list[tuple[Path, int]]:
    if selected_paths:
        return [(path, _line_count(path)) for path in selected_paths]
    rows: list[tuple[Path, int]] = []
    for scope in scopes:
        rows.extend(_collect(scope))
    return rows


def _rel(repo_root: Path, path: Path) -> str:
    return path.relative_to(repo_root).as_posix()


def _write_baseline(repo_root: Path, rows: list[tuple[Path, int]], baseline_file: Path) -> int:
    # Snapshot every file at or over the soft limit; these are the counts the
    # ratchet forbids exceeding.
    snapshot = {
        _rel(repo_root, path): count
        for path, count in sorted(rows, key=lambda item: item[1], reverse=True)
        if count >= SOFT_LIMIT
    }
    baseline_file.write_text(json.dumps(snapshot, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote baseline: {baseline_file}")
    print(f"Tracked files (>= {SOFT_LIMIT} lines): {len(snapshot)}")
    return 0


def _check_baseline(repo_root: Path, rows: list[tuple[Path, int]], baseline_file: Path) -> int:
    if not baseline_file.exists():
        print(f"ERROR: baseline file not found: {baseline_file}")
        print("Run with --write-baseline first.")
        return 1
    baseline: dict[str, int] = json.loads(baseline_file.read_text(encoding="utf-8"))

    new_hard: list[tuple[str, int]] = []
    regressions: list[tuple[str, int, int]] = []
    improvements: list[tuple[str, int, int]] = []

    for path, count in sorted(rows, key=lambda item: item[1], reverse=True):
        rel = _rel(repo_root, path)
        if rel in baseline:
            base = baseline[rel]
            if count > base:
                regressions.append((rel, base, count))
            elif count < base:
                improvements.append((rel, base, count))
        elif count > HARD_LIMIT:
            new_hard.append((rel, count))

    print(f"Ratchet check against baseline: {baseline_file}")
    print(f"Baselined files: {len(baseline)}  |  Scanned files: {len(rows)}")
    print("")

    if new_hard:
        print("NEW HARD VIOLATIONS (>1200, not in baseline):")
        for rel, count in new_hard:
            print(f"  {count:5d}  {rel}")
        print("")
    if regressions:
        print("REGRESSIONS (baselined file grew):")
        for rel, base, count in regressions:
            print(f"  {base:5d} -> {count:5d}  {rel}")
        print("")
    if improvements:
        print("Improvements (baselined file shrank - regenerate baseline to lock in):")
        for rel, base, count in improvements:
            print(f"  {base:5d} -> {count:5d}  {rel}")
        print("")

    if new_hard or regressions:
        print("RESULT: FAIL - new or worsened violations vs baseline.")
        return 1
    print("RESULT: PASS - no new or worsened violations.")
    return 0


def _report(repo_root: Path, rows: list[tuple[Path, int]]) -> int:
    rows = sorted(rows, key=lambda item: item[1], reverse=True)
    warnings = [(p, c) for p, c in rows if SOFT_LIMIT <= c <= HARD_LIMIT]
    violations = [(p, c) for p, c in rows if c > HARD_LIMIT]

    print(f"Line-limit policy: soft={SOFT_LIMIT}, hard={HARD_LIMIT}")
    print(f"Scanned files: {len(rows)}")
    print("")

    if violations:
        print("HARD VIOLATIONS (>1200):")
        for path, count in violations:
            print(f"  {count:5d}  {_rel(repo_root, path)}")
    else:
        print("HARD VIOLATIONS (>1200): none")

    print("")
    if warnings:
        print("SOFT WARNING BAND (900-1200):")
        for path, count in warnings:
            print(f"  {count:5d}  {_rel(repo_root, path)}")
    else:
        print("SOFT WARNING BAND (900-1200): none")

    return 1 if violations else 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Check script line limits.")
    parser.add_argument(
        "--path",
        action="append",
        default=[],
        help="Relative or absolute file path to check. Repeatable.",
    )
    parser.add_argument(
        "--write-baseline",
        action="store_true",
        help="Snapshot current counts (>= soft limit) to the baseline file.",
    )
    parser.add_argument(
        "--check-baseline",
        action="store_true",
        help="Fail only on new/worsened violations relative to the baseline.",
    )
    parser.add_argument(
        "--baseline-file",
        default=str(DEFAULT_BASELINE),
        help=f"Baseline JSON path (default: {DEFAULT_BASELINE.name} next to this tool).",
    )
    args = parser.parse_args()

    # Depends on this file living at utilities/checks/; update if it is moved.
    repo_root = Path(__file__).resolve().parents[2]
    scopes = [
        Scope(repo_root / "synesyn_client", ".gd"),
        Scope(repo_root / "services" / "synesyn_hub" / "app", ".py"),
    ]
    selected_paths = _normalize_paths(repo_root, args.path)
    baseline_file = Path(args.baseline_file)
    if not baseline_file.is_absolute():
        baseline_file = (repo_root / baseline_file).resolve()

    rows = _gather_rows(repo_root, scopes, selected_paths)

    if args.write_baseline:
        return _write_baseline(repo_root, rows, baseline_file)
    if args.check_baseline:
        return _check_baseline(repo_root, rows, baseline_file)
    return _report(repo_root, rows)


if __name__ == "__main__":
    sys.exit(main())
