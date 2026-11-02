# Harness

Runs the JSON behaviour specs in
[`../../docs/technical-review/run_specs/`](../../docs/technical-review/run_specs/README.md)
against a headless Godot client and checks their assertions, so behaviour can be
verified without a human reading artifacts. ADR 0006 records why verification is
spec-driven.

- `test_harness.py` — the runner to use. Executes one or more specs, expands
  reusable named actions, and reports PASS/FAIL per assertion.
- `run_devagent_harness.py` — lower-level single-run driver. Writes a run pointer
  as JSON to stdout and leaves artifacts (`run.json`, `screenshot.png`,
  `scene_logs.json`) in the run directory.
- `harness_assertions.py`, `harness_spec_utils.py` — assertion evaluation and spec
  loading, shared by both.
- `tests/` — unit tests for spec loading.

Run from the repository root:

```bash
python utilities/harness/test_harness.py \
  --spec docs/technical-review/run_specs/scensyn_workshop_catalyst_smoke.json
```

Specs carry their own assertions; the CLI assertion flags are overrides for
temporary use. Godot is located via `--godot`, `SYNESYN_GODOT_PATH`, `PATH`, or
`devagent_config.json` beside the run specs, which is machine-local and untracked.
