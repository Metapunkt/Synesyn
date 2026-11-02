#!/usr/bin/env python3
"""
Synesyn DevAgent test harness runner with assertions.

Runs one or more run specs through the harness, expands reusable named actions,
and checks embedded and/or CLI assertions against the artifacts. Designed for
agent-driven (self-service) testing without requiring a human to read artifacts.

Usage:
  python test_harness.py --spec path/to/spec.json [options]
  python test_harness.py --spec spec1.json --spec spec2.json

Specs may define a top-level "assertions" array. These CLI assertion options are
optional and replace embedded assertions of the same type:
  --min-story-log N          story_log.count >= N
  --exact-story-log N        story_log.count == N
  --last-sender NAME         last entry sender equals NAME (case-insensitive)
  --last-sender-in A,B,C     last sender is one of the given names
  --last-message-contains T  case-insensitive substring match in last message
  --scenario NAME            scenario field matches NAME (case-insensitive, partial ok)
  --no-errors                godot_log_tail has no ERROR: lines (excluding known-benign)
  --min-unique-senders N     at least N distinct senders in story log tail (character rotation check)

Other options:
  --timeout N                floor for how long to wait (default 250). A spec's own
                             harness_timeout_sec, or the total of the waits it asks
                             for plus 120s, raises this automatically.
  --resolution WxH           window size, and so the screenshot size; overrides a
                             spec's own harness_window_size
  --godot PATH               Godot executable (default: from devagent_config.json or PATH)
  --session-dir PATH         session data dir (default: ~/Documents/Synesyn)
  --project PATH             Godot project dir (default: synesyn_client sibling)
  --json                     output results as JSON (default: human-readable)
  --quiet                    suppress per-assertion detail (just print PASS/FAIL summary)

Exit codes:
  0  all assertions passed (or no assertions given and run succeeded)
  1  one or more assertions failed, or harness run failed
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from harness_assertions import merge_assertions, run_assertions
from harness_spec_utils import SpecValidationError, load_and_prepare_spec

# Seconds to wait for the run pointer after Godot has exited. Long enough for the write
# to land, short enough that a run which died is reported as one rather than hanging.
POINTER_GRACE_SEC = 10.0


# ── Paths ────────────────────────────────────────────────────────────────────

def _script_dir() -> Path:
    return Path(__file__).resolve().parent

def _repo_root() -> Path:
    # This file lives at utilities/harness/; update if it is moved.
    return _script_dir().parents[1]

def _default_project_dir() -> Path:
    return _repo_root() / "synesyn_client"

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
    return _repo_root() / "docs" / "technical-review" / "run_specs" / "devagent_config.json"

def _resolve_godot_exe(godot_arg: str) -> str:
    import shutil
    if godot_arg != "godot":
        return godot_arg
    config_path = _godot_config_path()
    if config_path.is_file():
        try:
            with open(config_path, encoding="utf-8") as f:
                cfg = json.load(f)
            val = (cfg.get("godot_path") or "").strip()
            if val:
                return val
        except (json.JSONDecodeError, OSError):
            pass
    exe = shutil.which("godot")
    if exe:
        return exe
    env_path = os.environ.get("SYNESYN_GODOT_PATH", "").strip()
    if env_path:
        return env_path
    return "godot"


# ── Harness runner ───────────────────────────────────────────────────────────

def spec_timeout(spec: dict, cli_timeout: float) -> float:
    """Seconds to allow this spec, honouring its own budget.

    A spec that waits out model latency knows how long it needs, and the operator does
    not. The multi-turn spec waits 120s three times: at the 250s default it could not
    finish regardless of product health, and reported "Godot process timed out" — which
    reads like a hang rather than a budget that was never raised alongside the waits.

    A spec's own ``harness_timeout_sec`` therefore wins, and where absent the floor is
    derived from the waits the spec actually asks for plus room for startup and
    shutdown. An explicit ``--timeout`` above either still wins, so raising it by hand
    is never blocked.
    """
    declared = float(spec.get("harness_timeout_sec", 0) or 0)
    waits = 0.0
    for action in list(spec.get("actions", [])) + list(spec.get("post_actions", [])):
        with_block = action.get("with", {}) if isinstance(action, dict) else {}
        waits += float(with_block.get("seconds", 0) or 0)
    waits += float(spec.get("wait_time_sec_after_post", 0) or 0)
    derived = waits + 120.0 if waits else 0.0
    return max(cli_timeout, declared, derived)


def window_size(spec: dict, cli_resolution: str) -> str:
    """Window size for this run, as Godot's ``<W>x<H>``, or "" for the project default.

    The harness screenshots the viewport, so the window size is the capture size. The
    project default is fine for assertions but crops and truncates panel text, which
    matters when the artifact is an image someone reads rather than a metrics dump.
    An explicit ``--resolution`` wins over the spec's own ``harness_window_size``.
    """
    size = (cli_resolution or str(spec.get("harness_window_size", ""))).strip()
    if not size:
        return ""
    width, _, height = size.partition("x")
    if not (width.isdigit() and height.isdigit()):
        raise ValueError(f"window size must be <W>x<H>, got {size!r}")
    return size


def run_spec(spec: dict, godot_exe: str, session_dir: Path,
             project_dir: Path, timeout: float, resolution: str = "") -> dict:
    """Run a single spec through the harness. Returns the pointer dict."""
    timeout = spec_timeout(spec, timeout)
    try:
        size = window_size(spec, resolution)
    except ValueError as error:
        return {"ok": False, "error": str(error)}
    pending_dir = session_dir / "syntree_run_specs"
    pending_path = pending_dir / "_pending_run.json"
    pending_dir.mkdir(parents=True, exist_ok=True)

    pending = {
        "thread_id": "test_harness",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()),
        "spec": spec,
    }
    with open(pending_path, "w", encoding="utf-8") as f:
        json.dump(pending, f, indent=2)

    pointer_path = session_dir / "syntree_artifacts" / "harness_last_run.json"
    # The pointer outlives the run that wrote it, so a run that dies before writing its
    # own would be reported with the previous run's directory, scene logs and assertions:
    # a pass for a session that never happened. Clearing it first makes that a failure.
    pointer_path.unlink(missing_ok=True)

    harness_scene = "res://addons/syntree/harness/harness_runner.tscn"
    cmd = [godot_exe, "--path", str(project_dir.resolve())]
    if size:
        cmd += ["--resolution", size]
    cmd.append(harness_scene)
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=timeout + 15)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "Godot process timed out"}
    except subprocess.CalledProcessError as e:
        return {"ok": False, "error": f"Godot exited {e.returncode}",
                "stderr": (e.stderr or b"").decode("utf-8", errors="replace")}
    except FileNotFoundError:
        return {"ok": False, "error": f"Godot not found: {godot_exe}"}

    # Godot has already exited by here, so the pointer is either written or never
    # coming; the grace period only covers the write landing on disk.
    deadline = time.monotonic() + POINTER_GRACE_SEC
    while time.monotonic() < deadline:
        if pointer_path.is_file():
            with open(pointer_path, encoding="utf-8") as f:
                return json.load(f)
        time.sleep(0.5)

    return {
        "ok": False,
        "error": (
            "Godot exited without writing harness_last_run.json; the run ended early "
            "(see the Godot log for the scene's own errors)"
        ),
    }


# ── Artifact readers ─────────────────────────────────────────────────────────

def read_scene_logs(run_dir: str) -> dict:
    p = Path(run_dir) / "scene_logs.json"
    if not p.is_file():
        return {}
    with open(p, encoding="utf-8") as f:
        return json.load(f)

def read_godot_log(run_dir: str) -> str:
    p = Path(run_dir) / "godot_log_tail.txt"
    if not p.is_file():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")

def read_run_manifest(run_dir: str) -> dict:
    path = Path(run_dir) / "run.json"
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as file_handle:
        return json.load(file_handle)


def action_failure_results(run_manifest: dict) -> list[dict]:
    """Treat failed pre/post actions as test failures, not just diagnostics."""
    failures = []
    for field_name in ("actions", "post_actions"):
        values = run_manifest.get(field_name, [])
        if not isinstance(values, list):
            continue
        for index, value in enumerate(values):
            if isinstance(value, dict) and not value.get("ok", False):
                failures.append({
                    "name": f"{field_name}[{index}]",
                    "type": "action_succeeded",
                    "ok": False,
                    "detail": str(value.get("error", "action failed")),
                })
    return failures


def cli_assertions(args: argparse.Namespace) -> list[dict]:
    """Convert legacy assertion flags to the structured assertion format."""
    assertions = []
    mappings = (
        ("min_story_log", "min_story_log"),
        ("exact_story_log", "exact_story_log"),
        ("last_sender", "last_sender"),
        ("last_sender_in", "last_sender_in"),
        ("last_message_contains", "last_message_contains"),
        ("scenario", "scenario_contains"),
        ("min_unique_senders", "min_unique_senders"),
    )
    for argument_name, assertion_type in mappings:
        value = getattr(args, argument_name)
        if value is not None:
            assertions.append({"type": assertion_type, "value": value})
    if args.no_errors:
        assertions.append({"type": "no_errors"})
    return assertions


# ── Report ───────────────────────────────────────────────────────────────────

def print_report(spec_path: Path, pointer: dict, scene_logs: dict,
                 assertion_results: list[dict], as_json: bool, quiet: bool) -> bool:
    all_ok = pointer.get("ok", False) and all(r["ok"] for r in assertion_results)

    if as_json:
        print(json.dumps({
            "spec": str(spec_path),
            "ok": all_ok,
            "run_dir": pointer.get("run_dir", ""),
            "harness_ok": pointer.get("ok", False),
            "harness_error": pointer.get("error", ""),
            "story_log_count": scene_logs.get("story_log", {}).get("count", 0),
            "last_sender": scene_logs.get("story_log", {}).get("last_entry", {}).get("sender", ""),
            "scenario": scene_logs.get("scenario", ""),
            "assertions": assertion_results,
        }, indent=2))
        return all_ok

    tag = "PASS" if all_ok else "FAIL"
    print(f"\n{'='*60}")
    print(f"  {tag}  {spec_path.name}")
    print(f"{'='*60}")
    if not pointer.get("ok", False):
        print(f"  HARNESS ERROR: {pointer.get('error', '?')}")
    else:
        print(f"  run_dir : {pointer.get('run_dir', '?')}")
        sl = scene_logs.get("story_log", {})
        le = sl.get("last_entry", {})
        print(f"  scenario: {scene_logs.get('scenario', '?')}")
        print(f"  log cnt : {sl.get('count', '?')}")
        print(f"  last    : [{le.get('sender', '?')}] {str(le.get('message',''))[:100]}")

        if not quiet and assertion_results:
            print(f"  assertions:")
            for r in assertion_results:
                sym = "PASS" if r["ok"] else "FAIL"
                detail = f"  ({r['detail']})" if r.get("detail") else ""
                print(f"    [{sym}] {r['name']}{detail}")

    return all_ok


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(description="Synesyn harness test runner with assertions")
    ap.add_argument("--spec", action="append", required=True, metavar="PATH",
                    help="Run spec JSON path (repeat for multiple specs)")
    ap.add_argument("--timeout", type=float, default=250.0)
    ap.add_argument("--resolution", default="", metavar="WxH",
                    help="window/screenshot size (overrides spec harness_window_size)")
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--session-dir", type=Path, default=None)
    ap.add_argument("--project", type=Path, default=None)
    ap.add_argument("--json", action="store_true", dest="as_json")
    ap.add_argument("--quiet", action="store_true")

    # Assertions
    ap.add_argument("--min-story-log", type=int, default=None)
    ap.add_argument("--exact-story-log", type=int, default=None)
    ap.add_argument("--last-sender", default=None)
    ap.add_argument("--last-sender-in", default=None)
    ap.add_argument("--last-message-contains", default=None)
    ap.add_argument("--scenario", default=None)
    ap.add_argument("--no-errors", action="store_true")
    ap.add_argument("--min-unique-senders", type=int, default=None)

    args = ap.parse_args()

    session_dir = args.session_dir or _default_session_dir()
    project_dir = args.project or _default_project_dir()
    godot_exe = _resolve_godot_exe(args.godot)

    overall_ok = True
    for spec_str in args.spec:
        spec_path = Path(spec_str)
        if not spec_path.is_file():
            print(f"ERROR: spec not found: {spec_path}", file=sys.stderr)
            overall_ok = False
            continue

        try:
            spec = load_and_prepare_spec(spec_path)
        except SpecValidationError as error:
            if args.as_json:
                print(json.dumps({
                    "spec": str(spec_path),
                    "ok": False,
                    "phase": "validation",
                    "validation_errors": error.errors,
                }, indent=2))
            else:
                print(f"\n  FAIL  {spec_path.name}")
                for validation_error in error.errors:
                    print(f"    [VALIDATION] {validation_error}")
            overall_ok = False
            continue

        pointer = run_spec(spec, godot_exe, session_dir, project_dir,
                           args.timeout, args.resolution)
        run_dir = pointer.get("run_dir", "")
        scene_logs = read_scene_logs(run_dir) if run_dir else {}
        godot_log = read_godot_log(run_dir) if run_dir else ""

        assertion_results = []
        if pointer.get("ok", False):
            assertions = merge_assertions(
                spec.get("assertions", []),
                cli_assertions(args),
            )
            assertion_results = run_assertions(scene_logs, godot_log, assertions)
            assertion_results.extend(action_failure_results(read_run_manifest(run_dir)))

        spec_ok = print_report(spec_path, pointer, scene_logs,
                               assertion_results, args.as_json, args.quiet)
        if not spec_ok:
            overall_ok = False

    if not args.as_json:
        print(f"\n{'='*60}")
        print(f"  Overall: {'PASS' if overall_ok else 'FAIL'}")
        print(f"{'='*60}\n")

    return 0 if overall_ok else 1


if __name__ == "__main__":
    # Force UTF-8 stdout so Unicode in AI responses doesn't crash on Windows cp1252.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
