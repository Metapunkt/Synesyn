# Architecture (high-level)

## Components

The client is one Godot project in three layers. Dependencies point downward:
applications use addons, addons reach shared behaviour through `synesyn_core`, and
nothing in an addon depends on an application (ADR 0017). See
[building on Synesyn](building-on-synesyn.md).

- **Applications**: ScenSyn (two session types — Workshop Catalyst and Story
  Catalyst), ReadyMade, Play a Story Log (`synesyn_client/playback/`), and the
  Synesyn Tools shell
- **Product addons**: SynTree, SynAxes, SynPunkt, Metapunkt, SynTree Voice,
  Story Stage (`addons/story_stage`), and `synesyn_visual_profiles`
- **Shared library**: `synesyn_core` — config, hub client, theme, render contracts
- **Hub** (server, optional): artifact storage + job queue + event stream + auth
- **External services** (optional): ComfyUI, local or hosted LLM providers,
  SuperCollider (OSC)

## Data model

Synesyn is artifact-first. Applications and tools read and write immutable
artifacts on the Hub and reference each other by artifact ID.

Key artifact types:

- `ui.context_graph` — published source-material context graphs from SynTree
- `ui.closure` — SynAxes closures: read-only saved slices of accumulated material
- `ui.workshop_closure` — session captures committed during a workshop (ADR 0026)
- `ui.workshop_summary`, `ui.workshop_thinking_map`, `ui.workshop_path_set` —
  facilitator-committed Workshop Catalyst records
- `ui.syndoc` — editable presentation documents in SynPunkt
- `json.workflow`, `json.render_request`, `json.render_recipe` — rendering
  workflows and request records
- `image.generated` — generated images with provenance

## Group sessions (Hub-first)

One device hosts the Hub, others join by configuring the Hub URL (and optional
bearer token). This shares the *artifact substrate*, not a live session: a Workshop
Catalyst workshop still runs on one device, and multi-client session
synchronisation is deferred.

## Workshop Catalyst UI ownership

- `workshop_catalyst_workspace_shell.tscn` owns the static Workshop dashboard
  hierarchy and is hidden until its controller mounts successfully.
- `WorkshopWorkspaceController` is the sole authority for presets, panel/rail
  visibility, narrow drawers, responsive breakpoints, and split-state
  persistence. Feature controllers request layout changes through its public
  methods.
- Shared conversation and input controls cross one centralized compatibility
  mount seam. Do not add reparenting, size, or visibility writes in feature
  controllers.
- Structural values come from `SynesynUiTokens`; colors, typography, radii, and
  widget styling remain in Godot Theme resources.
- Semantic accents and type variations (`SynesynPrimaryAction`,
  `SynesynRaisedPanel`, navigation/badge roles) come from
  `synesyn_client/ScenSyn/themes/profiles/synesyn_compatibility.tres` plus runtime
  decoration in `synesyn_client/addons/synesyn_visual_profiles/`. Live Themes are
  `*_light.tres` / `*_contemporary_dark.tres`.
- Tentative chrome convention (light and dark): idle surfaces separate by fill
  and spacing, not 1px outline strokes (soft AA borders read washed-out). Keep
  focus rings. Nested regions that need definition without a stroke (e.g.
  Thinking Map Causes/Effects/Opportunities) use a slight raised fill tint.
- Thinking Map Causes/Effects/Opportunities stay horizontal (`columns = 3`) via
  `workshop_map_layout_utils.gd`; they shrink to share width rather than stack.
- Workshop Catalyst's facilitation method (ADR 0012) lives in prompts and
  Scenario data, never in the interface: four stable lenses each carrying a
  reasoning method, six cross-lens checks the synthesis step must work, and a
  four-part stage contract per stage. Domain expertise is adopted backstage and
  never surfaced as a participant or used to upgrade evidential standing. Every
  Scenario gets a stage contract; authored guidance wins over the default.
- Portrait header banner sizing is owned by `game_session_ui_utils.gd` (fit on
  layout/scale changes; do not abandon fit when the header is tall).
- Debug builds expose the `Layout diagnostics` toolbar check for inspecting
  parentage, clipping, scroll ownership, actual/minimum sizes, and overflow.
- The bounded GTML pilot was removed after its generated Controls proved too
  unpredictable for the dashboard's responsive layout. Workshop UI remains
  scene-authored native Godot UI. Spatial-cube UI remains withdrawn (ADRs
  0010/0011).

## Script size policy (canonical)

This is the canonical source for script line-limit thresholds.

- Thresholds:
  - soft warning: **900 lines**
  - hard limit: **1200 lines**
- Scope:
  - `synesyn_client/**/*.gd`
  - `services/synesyn_hub/app/**/*.py`
- If a file approaches the threshold, split by cohesive domain/module immediately.
- Hard-limit violations are blocking for completion of an agent task.
- Automated checker:
  - `python utilities/checks/check_line_limits.py`
  - `python utilities/checks/check_line_limits.py --path <relative_file>`

Conflict resolution:
- If docs/rules disagree, follow this file plus `utilities/checks/check_line_limits.py`.
- Cursor rules should mirror this policy for agent behavior, not redefine it independently.

## Agent guardrails (Cursor workflow)

These are mandatory execution guardrails for coding agents:

- Size gate before/after edits:
  - Before editing a `.gd`/`.py` file, check its current size with `python utilities/checks/check_line_limits.py --path <relative_file>`.
  - After edits, run the same check again.
  - If a file crosses hard limit, stop feature growth and split/extract immediately.
- Safe refactor protocol:
  - Extract by cohesive domain (not one-off helper sprawl).
  - Before creating a new script, confirm whether the moved code fits an existing script/module first.
  - Only create a new script if no suitable existing module exists.
  - New scripts must be placed in the most logical existing directory for that subsystem architecture.
  - Keep behavior stable unless behavior change is explicitly requested.
  - Add/execute targeted regression checks for touched flows.
- Anti-bloat and anti-duplication:
  - Prefer reusing/extending existing modules before adding new ones.
  - If similar logic exists, refactor to shared helper instead of copy/paste.
  - Avoid creating duplicate directory trees or near-duplicate module names.
- Directory placement discipline:
  - Place new files inside the owning subsystem path (e.g., SynPunkt code under `addons/synpunkt/`).
  - Do not create alternate/parallel roots for the same subsystem.
- Completion criteria:
  - Task is not complete if policy violations were introduced.
  - If pre-existing violations exist, do not increase them without explicit approval; include a split-down note in the task output.


