#!/usr/bin/env python3
"""
Run the Synesyn DevAgent harness from the command line so that Cursor/agents
can trigger runs and read artifacts without using the Godot editor UI.

Usage:
  python run_devagent_harness.py --spec <path-to-run-spec.json> [options]
  python run_devagent_harness.py --spec -  # read spec from stdin (JSON)

Output:
  Writes last run pointer to stdout as JSON: { "run_dir", "run_manifest_path", "ok", "error" }
  so the caller can read run.json, screenshot.png, scene_logs.json, etc. from run_dir.

Requires:
  - Godot 4.x: on PATH as "godot", or set SYNESYN_GODOT_PATH to the executable path,
    or pass --godot /path/to/godot (so Cursor/agents can run without you after one-time setup).
  - Project path (default: synesyn_client next to this script's repo root)
  - Session data dir (default: SYNESYN_SESSION_DATA_DIR or ~/Documents/Synesyn)
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

from harness_spec_utils import (
    SpecValidationError,
    load_and_prepare_spec,
    prepare_spec,
)


def _default_project_dir() -> Path:
    # Script lives in synesyn/utilities/harness/; project is synesyn/synesyn_client
    repo_root = Path(__file__).resolve().parents[2]
    return repo_root / "synesyn_client"


def _default_session_dir() -> Path:
    env = os.environ.get("SYNESYN_SESSION_DATA_DIR", "").strip()
    if env:
        return Path(env)
    if os.name == "nt":
        docs = Path(os.environ.get("USERPROFILE", "")) / "Documents"
    else:
        docs = Path.home() / "Documents"
    return docs / "Synesyn"


def _godot_config_path() -> Path:
    """Path to optional devagent config (godot_path, etc.) next to run_specs or script dir."""
    repo_root = Path(__file__).resolve().parents[2]
    # Prefer run_specs sibling so it lives with technical-review assets
    run_specs_dir = repo_root / "docs" / "technical-review" / "run_specs"
    return run_specs_dir / "devagent_config.json"


def _resolve_godot_exe(godot_arg: str) -> str:
    """Resolve Godot executable: use arg if not default; else config file; else PATH; else SYNESYN_GODOT_PATH."""
    if godot_arg != "godot":
        return godot_arg
    config_path = _godot_config_path()
    if config_path.is_file():
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            path_val = (cfg.get("godot_path") or "").strip()
            if path_val:
                return path_val
        except (json.JSONDecodeError, OSError):
            pass
    exe = shutil.which("godot")
    if exe:
        return exe
    env_path = os.environ.get("SYNESYN_GODOT_PATH", "").strip()
    if env_path:
        return env_path
    return "godot"  # let subprocess report "not found"


def main() -> int:
    ap = argparse.ArgumentParser(description="Run DevAgent harness from CLI (for Cursor/agents)")
    ap.add_argument("--spec", required=True, help="Path to run spec JSON, or '-' for stdin")
    ap.add_argument("--thread-id", default="cli", help="Thread id for this run (default: cli)")
    ap.add_argument("--session-dir", type=Path, default=None, help="Session data root (default: SYNESYN_SESSION_DATA_DIR or ~/Documents/Synesyn)")
    ap.add_argument("--project", type=Path, default=None, help="Godot project path (default: synesyn_client next to synesyn repo)")
    ap.add_argument("--godot", default="godot", help="Godot executable (default: godot from PATH, or SYNESYN_GODOT_PATH)")
    ap.add_argument("--timeout", type=float, default=120.0, help="Seconds to wait for harness to finish (default: 120)")
    ap.add_argument("--write-only", action="store_true", help="Only write pending run spec; do not launch Godot (for editor-driven runs)")
    ap.add_argument("--out", choices=["json", "dir"], default="json", help="Output: 'json' (default) or just print run_dir path")
    args = ap.parse_args()

    session_dir = args.session_dir or _default_session_dir()
    project_dir = args.project or _default_project_dir()
    spec_path = args.spec

    try:
        if spec_path == "-":
            raw_spec = json.load(sys.stdin)
            spec = prepare_spec(raw_spec, Path.cwd())
        else:
            spec = load_and_prepare_spec(Path(spec_path))
    except (json.JSONDecodeError, SpecValidationError) as error:
        validation_errors = (
            error.errors if isinstance(error, SpecValidationError) else [str(error)]
        )
        print(json.dumps({
            "ok": False,
            "phase": "validation",
            "validation_errors": validation_errors,
        }), file=sys.stderr)
        return 1

    pending_dir = session_dir / "syntree_run_specs"
    pending_path = pending_dir / "_pending_run.json"
    pending_dir.mkdir(parents=True, exist_ok=True)
    pending = {
        "thread_id": args.thread_id,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()),
        "spec": spec,
    }
    with open(pending_path, "w", encoding="utf-8") as f:
        json.dump(pending, f, indent=2)

    if args.write_only:
        out = {"ok": True, "pending_path": str(pending_path), "message": "Pending run spec written; launch harness from editor or run without --write-only."}
        print(json.dumps(out))
        return 0

    pointer_path = session_dir / "syntree_artifacts" / "harness_last_run.json"
    # Cleared before launching, because the pointer outlives the run that wrote it: a run
    # that dies early would otherwise be reported with the previous run's directory.
    pointer_path.unlink(missing_ok=True)

    godot_exe = _resolve_godot_exe(args.godot)
    harness_scene = "res://addons/syntree/harness/harness_runner.tscn"
    project_abs = project_dir.resolve()
    cmd = [godot_exe, "--path", str(project_abs), harness_scene]
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=args.timeout + 10)
    except subprocess.TimeoutExpired:
        print(json.dumps({"ok": False, "error": "Godot process timed out"}), file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print(json.dumps({"ok": False, "error": f"Godot exited {e.returncode}", "stderr": (e.stderr or b"").decode("utf-8", errors="replace")}), file=sys.stderr)
        return 1
    except FileNotFoundError:
        msg = f"Godot not found: {godot_exe}. Install Godot 4, add it to PATH, or set SYNESYN_GODOT_PATH (or --godot)."
        print(json.dumps({"ok": False, "error": msg}), file=sys.stderr)
        return 1

    # Godot has exited, so the pointer is either written or never coming.
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline:
        if pointer_path.is_file():
            with open(pointer_path, "r", encoding="utf-8") as f:
                pointer = json.load(f)
            if args.out == "dir":
                print(pointer.get("run_dir", ""))
            else:
                print(json.dumps(pointer))
            return 0 if pointer.get("ok", False) else 1
        time.sleep(0.5)

    print(json.dumps({"ok": False, "error": "Godot exited without writing harness_last_run.json; the run ended early", "pointer_path": str(pointer_path)}), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
