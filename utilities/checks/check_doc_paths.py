#!/usr/bin/env python3
"""Check that repository paths written in documentation still exist.

Markdown links are already validated by `mkdocs build --strict`, but most paths in
these documents are prose written in backticks — `synesyn_client/scripts/foo.gd`,
`res://ScenSyn/main_scene.tscn` — and nothing has been checking those. They rot
every time code moves, and a reader who follows one and finds nothing stops
trusting the documentation.

Run from the repository root:

    python utilities/checks/check_doc_paths.py           # report and fail on rot
    python utilities/checks/check_doc_paths.py --list-ok  # also show what resolved

Exit status is 1 if any path cannot be resolved, so this is usable in CI.

A candidate resolves if it exists relative to the repository root, to the document
that mentions it, or to one of the ANCHORS below, since documents legitimately
write paths relative to the subtree they are describing. `res://` is resolved
against the Godot project. Genuine exceptions go in the allowlist file beside this
script, one path per line.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Depends on this file living at utilities/checks/; update if it is moved.
REPO_ROOT = Path(__file__).resolve().parents[2]
ALLOWLIST = Path(__file__).with_name("doc_paths_allowlist.txt")

SCAN_DIRS = ("docs",)
SCAN_FILES = ("README.md", "AGENTS.md")

# Not scanned, deliberately:
#   docs/architectural-decisions/ — append-only. An ADR records the tree as it
#     stood, so `synesyn_dec2025/` in a 2026-08 decision is correct, not rot.
#   implementation_tracking/ — not authoritative by ADR 0025, and its historical
#     entries are explicitly not rewritten when code moves.
EXCLUDE_DIRS = ("docs/architectural-decisions",)

# A documented path resolves against the repository root, against the document
# that mentions it, or against one of these subtrees, because a document
# describing a subtree reasonably writes paths relative to it. Keep this list
# short: every entry is a way for a wrong path to resolve by accident.
ANCHORS = (
    "",
    "synesyn_client",
    "synesyn_client/addons",
    "services/synesyn_hub",
    "docs",
)

GODOT_PROJECT = "synesyn_client"

SUFFIXES = {
    ".md", ".gd", ".py", ".tscn", ".tres", ".json", ".cfg", ".yml", ".yaml",
    ".txt", ".cs", ".gdextension", ".ttf", ".otf", ".png", ".jpg", ".jpeg",
    ".wav", ".mp3", ".exe", ".spec", ".mdc", ".toml", ".ini", ".bat", ".ps1",
}

BACKTICKED = re.compile(r"`([^`\n]+)`")
FENCE = re.compile(r"^\s*```")
# A backticked path used as a link label, e.g. [`../foo/bar.md`](../foo/bar.md).
# The target beside it is what matters, and `mkdocs build --strict` checks that,
# so the label is not this script's business.
LINK_LABEL = re.compile(r"\[`([^`\n]+)`\]\(")

# Prose, globs and elisions that happen to contain a slash.
SKIP_SUBSTRINGS = (
    "http://", "https://", "://localhost", " ", "<", ">", "*", "|", "{", "$",
    "...", "?", "%", "@",
)

# Paths that are real but not in the repository: user data, OS locations, and
# Godot's writable filesystem.
SKIP_PREFIXES = ("user://", "AppData/", "Documents/", "~/", "./", "C:", "/")


def candidates(text: str) -> list[tuple[int, str]]:
    """Backticked spans that look like repository paths, with line numbers."""
    out: list[tuple[int, str]] = []
    in_fence = False
    for lineno, line in enumerate(text.splitlines(), start=1):
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        labels = set(LINK_LABEL.findall(line))
        for raw in BACKTICKED.findall(line):
            if raw in labels:
                continue
            token = raw.strip().rstrip(".,;:")
            if "/" not in token or any(s in token for s in SKIP_SUBSTRINGS):
                continue
            if token.startswith(SKIP_PREFIXES):
                continue
            if token.startswith("res://"):
                out.append((lineno, token))
                continue
            # A single-segment directory, e.g. `output/`, is illustrative rather
            # than a location the reader is expected to find.
            if token.endswith("/") and token.count("/") == 1:
                continue
            if token.endswith("/") or Path(token).suffix.lower() in SUFFIXES:
                out.append((lineno, token))
    return out


def resolves(token: str, doc: Path) -> bool:
    if token.startswith("res://"):
        rel = token[len("res://"):]
        return (REPO_ROOT / GODOT_PROJECT / rel).exists()
    rel = token.rstrip("/")
    if (doc.parent / rel).exists():
        return True
    return any((REPO_ROOT / anchor / rel).exists() for anchor in ANCHORS)


def load_allowlist() -> set[str]:
    if not ALLOWLIST.exists():
        return set()
    entries = set()
    for line in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            entries.add(line)
    return entries


def documents() -> list[Path]:
    docs: list[Path] = []
    for name in SCAN_FILES:
        p = REPO_ROOT / name
        if p.exists():
            docs.append(p)
    for d in SCAN_DIRS:
        for p in sorted((REPO_ROOT / d).rglob("*.md")):
            rel = p.relative_to(REPO_ROOT).as_posix()
            if not rel.startswith(EXCLUDE_DIRS):
                docs.append(p)
    return docs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--list-ok", action="store_true", help="also print paths that resolved")
    args = ap.parse_args()

    allowlist = load_allowlist()
    broken: list[tuple[Path, int, str]] = []
    checked = 0
    allowed = 0

    for doc in documents():
        text = doc.read_text(encoding="utf-8", errors="replace")
        for lineno, token in candidates(text):
            checked += 1
            if token in allowlist:
                allowed += 1
                continue
            if resolves(token, doc):
                if args.list_ok:
                    print(f"ok    {doc.relative_to(REPO_ROOT).as_posix()}:{lineno}  {token}")
                continue
            broken.append((doc, lineno, token))

    print(f"Checked {checked} path reference(s) in {len(documents())} document(s); "
          f"{allowed} allowlisted.")
    if not broken:
        print("All documented paths resolve.")
        return 0

    print(f"\n{len(broken)} path(s) do not exist:\n")
    current: Path | None = None
    for doc, lineno, token in broken:
        if doc != current:
            print(f"  {doc.relative_to(REPO_ROOT).as_posix()}")
            current = doc
        print(f"    line {lineno}: {token}")
    print("\nFix the path, or add a genuine exception to "
          f"{ALLOWLIST.relative_to(REPO_ROOT).as_posix()}.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
