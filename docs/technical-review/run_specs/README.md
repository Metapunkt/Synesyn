# Run specs for the DevAgent harness

Use `test_harness.py` for self-validating specs:

```bash
python utilities/harness/test_harness.py --spec docs/technical-review/run_specs/<file>.json
```

Run from the repository root. The runner resolves Godot from `devagent_config.json`,
an explicit `--godot` argument, or the environment/PATH.

Use `run_devagent_harness.py` when artifacts are the goal and assertion evaluation
is not required.

## Embedded assertions

Specs can carry their own acceptance checks:

```json
"assertions": [
  { "type": "min_story_log", "value": 3 },
  { "type": "scenario_contains", "value": "karlsruhe" },
  { "type": "no_errors" },
  { "type": "min_unique_senders", "value": 2 }
]
```

Supported types:

- `min_story_log`
- `exact_story_log`
- `last_sender`
- `last_sender_in` (`value` may be an array or comma-separated string)
- `last_message_contains`
- `scenario_contains`
- `no_errors`
- `log_not_contains`: no line of `godot_log_tail.txt` contains `value`, ignoring case
- `min_unique_senders` and `exact_unique_senders` (`exclude_system` defaults to `true`)
- `exact_sender_occurrences`: `sender` spoke exactly `value` times
- `snapshot_field`: a dotted `path` into `scene_logs.json` (for example
  `playback.lines_displayed`) is at least `min`, `equals` a value, `contains` a
  string, or, given none of those, is present and not empty

Legacy CLI assertion flags remain available for ad-hoc checks. A CLI assertion
replaces an embedded assertion of the same type.

Failed pre-scene or post-scene actions automatically fail `test_harness.py`.

## Reusable named actions

Declare one or more libraries relative to the run-spec file:

```json
"action_libraries": ["scensyn_action_library.json"]
```

Reference a named sequence from `actions` or `post_actions`:

```json
{
  "use": "send_user_message_and_wait",
  "with": {
    "message": "What should we decide today?",
    "seconds": 45
  }
}
```

A library contains parameterized sequences:

```json
{
  "action_sequences": {
    "wait_for_ai": {
      "parameters": ["seconds"],
      "actions": [
        { "type": "wait_seconds", "seconds": "{{seconds}}" }
      ]
    }
  }
}
```

Exact placeholders such as `"{{seconds}}"` retain their JSON type. Placeholders
inside longer strings are converted to text. Sequences may call other sequences;
cycles, missing parameters, duplicate names, unsupported actions, and unknown
assertions fail validation before Godot starts.

Specs may also define local `action_sequences`. Local names must not duplicate
library names.

Named-action expansion is performed by the Python runners before `_pending_run.json`
is written. For editor-driven execution, first run `run_devagent_harness.py
--write-only` so the pending spec is expanded and validated.

## Specs

| File | Scene | Purpose |
|------|--------|--------|
| `scensyn_game_session_dump_logs.json` | Game session (Story Log) | Load ScenSyn game session; capture screenshot + UI metrics + scene logs (if scene implements dump in this run context). Use to validate e.g. error message in logs, session state. |
| `scensyn_story_stage_dump_logs.json` | Story Stage | Load Story Stage scene; capture screenshot + UI metrics + scene logs. Use to validate Stage UI, voice/state. |
| `scensyn_game_session_with_state_example.json` | Game session | Same as above with optional `state` (scenario, toggles). Use from editor runs where `test_apply_state` is applied. |
| `scensyn_game_session_send_message.json` | Game session | Loads game session then uses `post_actions` to call `test_send_user_message(...)` and waits a few frames. Use to validate harness-driven “type + submit”. |
| `scensyn_game_session_wait_for_ai_response.json` | Game session | Loads game session, sends a message, then waits longer so an AI turn can complete. Use to validate “AI responded” and inspect `scene_logs.json` / `godot_log_tail.txt` for diagnostics. |
| `scensyn_workshop_catalyst_smoke.json` | Game session | Workshop Catalyst one-turn smoke test (Karlsruhe scenario) with embedded assertions and reusable actions. |
| `scensyn_workshop_catalyst_multiturn.json` | Game session | Three-turn rotation test with embedded assertions and reusable actions. |
| `scensyn_workshop_catalyst_stt_preview.json` | Game session | Workshop Catalyst speech-to-text preview path. |
| `scensyn_story_catalyst_sustainability_smoke.json` | Game session | Story Catalyst / Sustainability one-turn smoke test. |
| `scensyn_story_catalyst_sustainability_multiturn.json` | Game session | Story Catalyst / Sustainability multi-turn rotation test. |
| `scensyn_story_catalyst_cultural_smoke.json` | Game session | Story Catalyst / Cultural Narratives one-turn smoke test. |
| `scensyn_readme_captures.json` | Game session | Regenerates the published Workshop Catalyst screenshots from a real three-turn session. Costs model calls and takes minutes, so it is run deliberately rather than as part of a suite — see the [capture guide](../../assets/screenshots/CAPTURE_GUIDE.md). |
| `scensyn_story_stage_capture.json` | Game session, then Story Stage mounted beside it | Regenerates the published Story Stage screenshot: one real turn against *Ireti Okan*, then the visual view replaying it. Costs a model call, and needs a sprite pack installed. |
| `scensyn_story_stage_presence.json` | Story Stage mounted before anything is typed | Checks that the stage is never a bare backdrop — at the opening, which is narrated by a voice with no sprite, and again once a line's dialogue box has retired. The `[budget]` lines in `godot_log_tail.txt` also give the seconds each model call of the turn took. Costs a turn's model calls and needs a sprite pack installed. |
| `scensyn_story_stage_features.json` | Game session, then Story Stage mounted beside it | Exercises Story Stage against *Stochastic Dreams* across opening, a live turn, and lull escalation, capturing screenshots at each beat. |
| `playback_smoke.json` | Story-log player | Replays the five-line fixture log in `synesyn_client/ScenSyn/tests/fixtures/` at reading pace and four times speed, voice off. Checks that every line reached the stage, that the log's stage record was read, and that no hub session was attached. Needs no model, hub or sprite pack, and takes under a minute. |
| `scensyn_turn_speaker_census.json` | Game session | Three consecutive inputs against *Ireti Okan*, to see how many speakers each turn plans and how many of them actually speak. The count is a local weighted roll (one speaker 60%, two 25%, three 15%), so a session that always answers with one character is either rolling ones or losing planned lines to validation; the `[turn]` lines in `godot_log_tail.txt` report both numbers. Costs a director call and an actor call per speaker, three times over. |
| `synaxes_toggle_tier3_on.json`, `synaxes_verify_tier3_persisted.json` | SynAxes panel | Toggle a tier-3 option and verify it persists. |
| `synaxes_headless_discover.json` | — | Documents a headless SynAxes discovery run; invoked via Godot directly rather than through the harness. |

`scensyn_action_library.json` is a shared action library, not a runnable spec.

## Note on scene logs when run from CLI

The harness can run from the CLI (no editor UI) when `_pending_run.json` exists.

- In practice, the CLI runner launches the **Godot editor executable**, so `OS.has_feature("editor")` is **true** and the scene’s `test_*` hooks can run, producing **`scene_logs.json`**.
- In an **exported player build**, `OS.has_feature("editor")` is **false** and the `test_*` hooks are expected to be inert. This is intentional: exported builds should not ship a test API.

If `scene_logs.json` is missing, still use `screenshot.png`, `ui_metrics.json`, and `godot_log_tail.txt` to diagnose what happened (and confirm the runner is launching the editor build).
