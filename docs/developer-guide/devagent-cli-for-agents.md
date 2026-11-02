# DevAgent CLI — for Cursor/agents (no editor required)

This describes how an automated agent (e.g. Cursor) can run the Synesyn DevAgent harness, read artifacts, and validate checklist items **without** a human opening the Godot editor.

## Prerequisites

- **Godot 4.x** must be runnable from the CLI. For **Cursor/agents to run the harness without you**:
  - **Option A:** Add Godot to your system PATH.
  - **Option B:** Set **`SYNESYN_GODOT_PATH`** to the Godot executable (e.g. `C:/Godot/Godot_v4.7_win64.exe`). The runner script checks this when `godot` is not on PATH.
  - **Option C:** Pass `--godot "C:/path/to/Godot.exe"` when calling the script.
- **Project**: `synesyn_client` (resolved relative to the repository root by default).
- **Session data dir**: where the harness reads/writes. Default is `~/Documents/Synesyn` (or `SYNESYN_SESSION_DATA_DIR` if set). Must match what the Godot project uses (see `synesyn/session_data_dir` in project.godot or harness fallback).

## How it works

1. **Harness behaviour**: The harness scene (`res://addons/syntree/harness/harness_runner.tscn`) can run in two modes:
   - **Editor**: launched from SynTree “Run” (play custom scene). Unchanged.
   - **Non-editor (CLI)**: when run as the main scene (e.g. `godot --path project harness_runner.tscn`), it runs **only if** `_pending_run.json` exists in the session data dir. So the agent writes that file, then starts Godot with the harness scene; the harness runs once and exits.

2. **Runner script**: `utilities/harness/run_devagent_harness.py`:
   - Validates the spec and expands reusable named actions.
   - Writes `user://syntree_run_specs/_pending_run.json` (payload: `thread_id`, expanded `spec`, `created_at`).
   - Runs: `godot --path <project> res://addons/syntree/harness/harness_runner.tscn`.
   - Waits for `user://syntree_artifacts/harness_last_run.json` (pointer to the last run).
   - Prints that pointer as JSON (or just `run_dir`) so the agent can read artifacts.

3. **Run spec format** (same as SynTree UI):

   ```json
   {
     "scene_path": "res://ScenSyn/scenes/game_session.tscn",
     "state": {},
     "action_libraries": ["scensyn_action_library.json"],
     "actions": [],
     "post_actions": [],
     "assertions": [],
     "wait_frames_after_post": 0,
     "logs_since_msec": 0,
     "godot_log_tail_bytes": 256000
   }
   ```

   - **scene_path** (required): any `.tscn` that the project can load. For ScenSyn flows, use the scene that implements `test_apply_state` / `test_dump_logs` (e.g. game session or story stage scene path — see project).
   - **state**: optional dict passed to the scene’s `test_apply_state(state)` if present.
   - **actions**: optional array of `{ "type": "call_autoload", "autoload": "...", "method": "...", "args": [] }` run before the scene is added.
   - **post_actions**: optional array of post-load actions run after the scene is instantiated. Supported types: `call_scene_method`, `call_node_method`, `set_node_property`, `call_autoload`, `wait_seconds`, `wait_frames`, `capture_screenshot`, and `mount_scene`.
   - **capture_screenshot**: `{ "type": "capture_screenshot", "name": "thinking-map" }` writes `<run_dir>/<name>.png`. A run always captures `screenshot.png` at the end; this is for the states it passes through on the way, so one session can yield several images instead of one session per image.
   - **mount_scene**: `{ "type": "mount_scene", "scene_path": "res://…", "hide_current": true }` adds a second scene beside the first, sharing the process and therefore the session already held in the autoloads. The product switches views with `change_scene_to_file`, which would free the runner mid-run and lose the artifacts. Later actions still address the original scene root.
   - **action_libraries**: optional paths, relative to the spec, containing reusable `action_sequences`.
   - **use / with**: invoke a named action sequence with parameters. Python expands these references before Godot runs.
   - **assertions**: optional acceptance checks evaluated by `test_harness.py`. See `docs/technical-review/run_specs/README.md`.
   - **wait_frames_after_post**: optional number of frames to wait after `post_actions` before capturing screenshot/metrics/logs.

4. **Artifacts** (under `run_dir` from `harness_last_run.json`):

   - `run.json` — full run manifest (ok, error, paths).
   - `run_spec.json` — spec that was run.
   - `screenshot.png` — viewport capture.
   - `ui_metrics.json` — control tree (path, visible, pos, size).
   - `scene_logs.json` — if the scene implements `test_dump_logs`.
   - `godot_log_tail.txt` — best-effort engine log tail.

## DevHarness contract (keep it small)

DevHarness only works long-term if it **does not become a second UI layer**.

- **Principle**: Hooks expose **intent**, not UI mechanics.
  - Good: “apply scenario + toggles”, “send user message”, “dump snapshot”.
  - Bad: “click hamburger button”, “set dropdown index 3”, “type into %InputField then press %SendButton”.

- **Allowed hook surface (ScenSyn)**
  - Scenes may expose **only** these stable forwarders:
    - `test_apply_state(state: Dictionary)` → scene-local DevHarnessHooks `apply_state(state)`
    - `test_send_user_message(message_text: String)` → `send_user_message(message_text)`
    - `test_dump_logs(output_path: String, since_msec: int = 0)` → `dump_logs(output_path, since_msec)`
  - Anything beyond that should be justified as a **product invariant** that can’t be observed via artifacts.

- **How to validate failures without “fault injection”**
  - Prefer **environment control** (e.g. stop Ollama, remove API keys, block outbound) to trigger real failure paths.
  - Prefer **diagnostics in artifacts** (e.g. log which provider/model/base_url was active) over adding test-only switches.

## Usage (for the agent)

From the **repository root** (or anywhere with Python and Godot available):

```bash
# Run with a spec file; output is JSON pointer (run_dir, run_manifest_path, ok, error)
python utilities/harness/run_devagent_harness.py --spec path/to/run_spec.json

# Spec from stdin
echo '{"scene_path":"res://ScenSyn/scenes/game_session.tscn","state":{}}' | python utilities/harness/run_devagent_harness.py --spec -

# Only write pending (e.g. for editor-driven run)
python utilities/harness/run_devagent_harness.py --spec run_spec.json --write-only

# Custom session dir / project / Godot
python utilities/harness/run_devagent_harness.py --spec run_spec.json --session-dir "C:/Users/me/Documents/Synesyn" --project synesyn_client --godot "C:/Godot/Godot_v4.x_win64.exe"

# Output just the run dir path (for scripting)
python utilities/harness/run_devagent_harness.py --spec run_spec.json --out dir

# Run a self-validating spec with embedded assertions
python utilities/harness/test_harness.py --spec run_spec.json
```

Exit code: **0** if the run completed and `harness_last_run.json` has `ok: true`; **1** on failure or timeout.

For `test_harness.py`, exit code 0 additionally requires all embedded/CLI
assertions and all dispatched actions to pass.

## Validating checklist items

1. **Create a run spec** that loads the right scene and (if needed) applies state (e.g. session type, collection, scenario).
2. **Run**: `python utilities/harness/run_devagent_harness.py --spec run_spec.json`
3. **Read** `run_dir` from the JSON output; then:
   - `<run_dir>/run.json` — success/failure, artifact paths.
   - `<run_dir>/scene_logs.json` — structured state/errors from the scene (if implemented).
   - `<run_dir>/screenshot.png` — visual check.
4. **Assert** on content (e.g. “error message present in scene_logs” or “screenshot shows Services panel with workspace X”).

Example run specs: **`docs/technical-review/run_specs/`** — see `docs/technical-review/run_specs/README.md` and the included JSON files (e.g. `scensyn_game_session_dump_logs.json`, `scensyn_story_stage_dump_logs.json`).

## Reference: session data layout

- `SYNESYN_SESSION_DATA_DIR` or `~/Documents/Synesyn`
  - `user://syntree_run_specs/_pending_run.json` — input (written by script).
  - `user://syntree_artifacts/harness_last_run.json` — output pointer (written by harness).
  - `syntree_artifacts/runs/<run_id>/` — run_dir (run.json, screenshot.png, etc.).
