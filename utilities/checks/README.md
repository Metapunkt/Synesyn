# Checks

Policy checks. Each exits non-zero on failure, so all are usable in CI.

| Script | Guards against |
| --- | --- |
| `check_line_limits.py` | source files growing past the maintainability thresholds |
| `check_addon_autoloads.py` | addons reaching into application autoloads (ADR 0017) |
| `check_doc_paths.py` | documentation naming repository paths that no longer exist |
| `check_story_stage_boundary.py` | Story Stage reaching past its host into an application (ADR 0029) |
| `story_stage_dropin_test.py` | Story Stage failing to run in a project that has nothing but it and `synesyn_core` |

CI runs the first three. The Story Stage pair are run by hand after changing
`synesyn_client/addons/story_stage/`; the drop-in test needs a Godot binary.

## Story Stage boundary

- `check_story_stage_boundary.py` scans the addon's scripts and fails on any that
  name a project autoload, a `class_name` declared outside the addon, or a `res://`
  path outside it. Each of those compiles inside this project and breaks the first
  time the stage is used anywhere else. Scenes are not scanned, since they may
  reference art the host supplies.
- `story_stage_dropin_test.py` copies `story_stage` and `synesyn_core` into a
  temporary Godot project, gives the stage a host with three scripted lines, and
  passes when all three reach the dialogue box with no Godot errors. It finds Godot
  as `godot` on `PATH` or through `GODOT_BIN`; `--keep` leaves the project behind
  for inspection.
- Run: `python utilities/checks/check_story_stage_boundary.py`, then
  `python utilities/checks/story_stage_dropin_test.py`

## Documented path check

- Script: `check_doc_paths.py`
- Purpose: `mkdocs build --strict` validates markdown *links*, but most paths in
  the documentation are prose in backticks — `synesyn_client/scripts/foo.gd`,
  `res://ScenSyn/main_scene.tscn` — and nothing checked those. They rot silently
  whenever code moves. This check found 50 broken references the first time it
  ran.
- Run: `python utilities/checks/check_doc_paths.py`
- Show what resolved as well: `--list-ok`

Scope is the published surface: `docs/`, plus `README.md` and `AGENTS.md`. It
deliberately skips `docs/architectural-decisions/` and `implementation_tracking/`,
both of which are historical records where an old path is correct rather than
broken.

Genuine exceptions — build output, runtime directories, files excluded from the
repository — belong in `doc_paths_allowlist.txt`, with a comment saying why. If a
path is absent because code moved, fix the document instead.

## Line-limit policy check

- Script: `check_line_limits.py`
- Purpose: enforce source file line limits from `docs/developer-guide/architecture.md`.
- Run (full scan):
  - `python utilities/checks/check_line_limits.py`
- Run (single file during active edits):
  - `python utilities/checks/check_line_limits.py --path synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd`

Thresholds:
- soft warning: `900`
- hard limit: `1200` (non-zero exit code)

Scope:
- `synesyn_client/**/*.gd`
- `services/synesyn_hub/app/**/*.py`

## Cursor agent workflow

- Before editing a target `.gd`/`.py` file, run `--path` check for that file.
- After editing the same file, run `--path` again.
- Before completing a substantial task, run full scan.
