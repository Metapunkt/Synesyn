# Code map (what to read first)

Read [`../SYSTEM_MAP.md`](../SYSTEM_MAP.md) before using this map. Paths below are
relative to the repository root and are checked by
`utilities/checks/check_doc_paths.py`, so a stale one here is a build failure
rather than a wasted search.

## ScenSyn

- Session runtime: `synesyn_client/ScenSyn/scripts/game_session.gd`
- Story Stage in a session: `synesyn_client/ScenSyn/scenes/scensyn_story_stage.tscn`
  (the addon stage plus ScenSyn's render, services and harness nodes), answered by
  `synesyn_client/ScenSyn/scripts/core/scensyn_stage_host.gd`
- Scenario art the stage draws on (sprites, backdrops, generated `.tres`):
  `synesyn_client/ScenSyn/story_stage/`
- Session Types and Collections: `synesyn_client/ScenSyn/session_types/`
- Story Catalyst Collections:
  `synesyn_client/ScenSyn/session_types/story_catalyst/`
- Workshop Catalyst:
  `synesyn_client/ScenSyn/session_types/workshop_catalyst/`
  - Runtime orchestration and StoryState/session-record coordination:
    `workshop_catalyst_controller.gd`
  - Static settings tree and control-to-action binding:
    `workshop_catalyst_settings_panel.tscn` and
    `workshop_catalyst_settings_binding.gd`
  - Scene-authored panel/preset shell and layout preference binding:
    `workshop_catalyst_workspace_shell.tscn` and
    `workshop_workspace_controller.gd`
  - Pure Talk/Map/Review/Full Dashboard/Custom visibility state:
    `workshop_workspace_preset_model.gd`
  - Thinking Map column sizing (always horizontal), audit split sizing, and
    claim-column light/dark styling: `workshop_map_layout_utils.gd`
  - Custom drawer's two Thinking Map sub-switches (claim columns, Closure audit
    panel), which span the shell and map scenes:
    `workshop_map_panel_toggles.gd`
  - Facilitation method — four lenses with their reasoning methods, the six
    cross-lens checks, adaptive two-phase recovery, and backstage domain
    adoption: `workshop_specialist_coordinator.gd` (`ROLE_DEFINITIONS`,
    `CROSS_CHECKS`); prompt text in `workshop_specialist_prompts.gd`
  - Default agenda and default four-part stage contracts:
    `workshop_scenario_contract.gd` (`DEFAULT_AGENDA`,
    `default_stage_guidance()`); authored `[STAGE_GUIDANCE]` always wins
  - Workspace persistence is preference-only under `apps.scensyn.*`; safety
    controls are structurally outside preset-managed panel containers.
  - Agenda normalization, duration scaling, and stage lookup:
    `workshop_catalyst_timing.gd`
  - Markdown export formatting and writes:
    `workshop_catalyst_export_utils.gd`
- Themes / visual chrome:
  - Live Themes: `synesyn_client/ScenSyn/themes/*_light.tres` and
    `*_contemporary_dark.tres` (via `theme_config.tres`)
  - Semantic colors + profile: `synesyn_client/ScenSyn/themes/profiles/synesyn_compatibility.tres`
  - Type-variation decoration: `synesyn_client/addons/synesyn_visual_profiles/`
  - Theme runtime: `synesyn_client/addons/synesyn_core/scripts/theme_manager.gd`
  - Structural breakpoints/rails: `synesyn_client/ScenSyn/scripts/core/synesyn_ui_tokens.gd`
  - Portrait header banner fit: `synesyn_client/ScenSyn/scripts/core/game_session_ui_utils.gd`

## SynTree

- Main panel: `synesyn_client/addons/syntree/scripts/syntree_panel.gd`
- Services: `synesyn_client/addons/syntree/scripts/services/`
- Internal architecture:
  `synesyn_client/addons/syntree/docs/architecture.md`

## Metapunkt

- Main surface: `synesyn_client/addons/metapunkt/scenes/metapunkt_main.gd`
- Addon overview: `synesyn_client/addons/metapunkt/README.md`

## SynAxes

- Runtime controller:
  `synesyn_client/addons/synaxes/scripts/runtime/synaxes_runtime_controller.gd`
- Addon overview: `synesyn_client/addons/synaxes/README.md`
- Closure Map (concept): `docs/concepts/closure-map.md`
- V2 orientation ADR: `docs/architectural-decisions/0015-synaxes-v2-closure-map-orientation.md`
- Orientation PRD: `docs/product-requirements/PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md`

## Story Stage (Godot addon)

- Functional specification (drop-in contract and architecture):
  [`../developer-guide/story-stage-functional-specification.md`](story-stage-functional-specification.md)
- Stage core and line feed: `synesyn_client/addons/story_stage/scripts/story_stage.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_line_feed.gd`, and
  `synesyn_client/addons/story_stage/scripts/story_stage_ui.gd`
- Capability grants, cue player, and topology:
  `synesyn_client/addons/story_stage/scripts/story_stage_capabilities.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_cues.gd`, and
  `synesyn_client/addons/story_stage/scripts/story_stage_topology.gd`
- Presenter, portrait sprite, spectrum, and shader:
  `synesyn_client/addons/story_stage/scripts/story_stage_presenter.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_presenter_2d.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_character_sprite.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_spectrum.gd`, and
  `synesyn_client/addons/story_stage/shaders/portrait.gdshader`
- Per-speaker audio-bus motion and viseme mapping:
  `synesyn_client/addons/story_stage/scripts/story_stage_motion.gd` and
  `synesyn_client/addons/story_stage/scripts/story_stage_viseme.gd`
- Per-stage character registry and profile resource:
  `synesyn_client/addons/story_stage/scripts/story_stage_character.gd` and
  `synesyn_client/addons/story_stage/scripts/story_stage_character_profile.gd`
- Host, voice, and imagery ports:
  `synesyn_client/addons/story_stage/scripts/story_stage_host.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_voice.gd` (spoken through
  `syntree_voice` by `synesyn_client/scripts/stage_voice/syntree_stage_voice.gd`), and
  `synesyn_client/addons/story_stage/scripts/story_stage_imagery.gd`
- Backdrop, lull protocol, and ambient OSC:
  `synesyn_client/addons/story_stage/scripts/story_stage_background_controller.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_lull.gd`,
  `synesyn_client/addons/story_stage/scripts/story_stage_ambient_sound_bridge.gd`, and
  `synesyn_client/addons/story_stage/scripts/story_stage_osc.gd`
- Decisions:
  `docs/architectural-decisions/0029-story-stage-is-a-host-driven-component.md`,
  `docs/architectural-decisions/0030-story-stage-motion-and-imagery-layers.md`, and
  `docs/architectural-decisions/0031-spoken-line-carries-its-resolved-voice.md`

## Story-log player

- Player and transport: `synesyn_client/playback/scripts/story_log_player.gd`
- Host replaying a saved log: `synesyn_client/playback/scripts/story_log_playback_host.gd`
- Fixture log and sidecar: `synesyn_client/ScenSyn/tests/fixtures/story_log_playback_fixture.json`

## SynPunkt (Godot addon)

- UI + wiring: `synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd`
- Scene: `synesyn_client/addons/synpunkt/scenes/synpunkt_dock.tscn`
- Edgeless preview widget: `synesyn_client/addons/synpunkt/scripts/edgeless_preview.gd`

## Shared rendering (Godot)

- Render request schema: `synesyn_client/addons/synesyn_core/scripts/synesyn_render_request_v1.gd`
- Render entrypoint service: `synesyn_client/addons/synesyn_core/scripts/synesyn_render_service.gd`
- Comfy client: `synesyn_client/addons/synesyn_core/scripts/synesyn_comfy_client.gd`

## Hub client (Godot)

- Hub client: `synesyn_client/addons/synesyn_core/scripts/hub_substrate_client.gd`
- Transport base: `synesyn_client/addons/synesyn_core/scripts/hub_substrate_transport.gd`
- Runtime config: `synesyn_client/addons/synesyn_core/scripts/runtime_config.gd`

## Hub server (FastAPI)

- Application entrypoint: `services/synesyn_hub/app/main.py`
- Substrate: `services/synesyn_hub/app/substrate/`
- STFX Core: `services/synesyn_hub/app/stfx_core/`
- STFX Store: `services/synesyn_hub/app/stfx_store/`
- STFX Memory: `services/synesyn_hub/app/stfx_memory/`
- ScenSyn routes: `services/synesyn_hub/app/routes/scensyn.py`
- Render routes: `services/synesyn_hub/app/routes/render.py`
- Job runner (incl. render.comfyui): `services/synesyn_hub/app/routes/jobs.py`

## ReadyMade

- Mission Control facade:
  `synesyn_client/readymade/ui/mission_control_dashboard.gd`
- Document session facade:
  `synesyn_client/readymade/scripts/core/document_session_manager.gd`
- Internal split modules:
  `synesyn_client/readymade/scripts/core/internal/`

## Harness and policy tooling

- Godot harness:
  `synesyn_client/addons/syntree/harness/harness_runner.gd`
- Self-validating runner: `utilities/harness/test_harness.py`
- Run specs: `docs/technical-review/run_specs/`
- Line-limit checker: `utilities/checks/check_line_limits.py`
- Story Stage boundary: `utilities/checks/check_story_stage_boundary.py` and the
  clean-project drop-in test `utilities/checks/story_stage_dropin_test.py`


