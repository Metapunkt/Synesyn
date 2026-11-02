# 0004 — Line-limit hard-violation remediation strategy

- **Status:** Accepted
- **Date:** 2026-07-09
- **Area:** client (GDScript) / tooling

> Amendment note (2026-09-18): the client directory named `synesyn_dec2025/`
> below is now `synesyn_client/` (ADR 0023). The path is left as written because
> the Context records the measurement as it stood; the `.cursorrules` file it
> refers to is now `AGENTS.md` at the repository root. The checker and its
> baseline also moved from `synesyn/tools/` to `synesyn/utilities/checks/`; the
> ratchet itself is unchanged.

## Context
`check_line_limits.py` reports **13 files over the 1200-line hard limit**, all GDScript in `synesyn_dec2025/` (the hub Python is entirely within the soft band). The largest is `mission_control_dashboard.gd` at 5509 lines. Refactoring GDScript is risky without coverage, and new violations can accrue faster than we fix old ones. The `.cursorrules` script-size rule (split at 800–900) and "prefer `.tscn` over code" rule already exist but are unenforced.

## Options considered
1. **Big-bang refactor all 13** — fast in theory, high regression risk, huge un-reviewable diff, blocks other work.
2. **Ignore / raise the limit** — abandons the maintainability guardrail.
3. **Ratchet + phased, verification-gated split** — freeze the current list as a baseline, block *new/worsening* violations immediately, then split in risk-ordered phases, verifying each split.

## Decision
Option 3. Two commitments:
1. **Ratchet now (prevention):** treat the current 13 as a frozen baseline. The `synesyn-reviewer` gate fails a change if it adds a new hard violation or increases the line count of any file already on the list. This stops the problem growing while we chip at it.
2. **Phased remediation (cure):** split in risk-adjusted order (see chat plan), not size order, verifying every split with a headless parse check + the ScenSyn harness (for ScenSyn files) + a targeted `check_line_limits.py --path` re-run. Prefer extracting static UI into `.tscn` and non-UI logic into `RefCounted` modules over moving code between scripts.

## Consequences
- Positive: no regressions during remediation; safe incremental progress; each phase independently reviewable.
- Negative / trade-offs: slower than big-bang; soft-band files (11) deliberately deferred.
- Follow-ups: implement the ratchet in the reviewer/checker; supersede this ADR with per-file ADRs only where a split forces a genuine boundary decision.

## Progress
- 2026-07-09: Phase 0 landed. `check_line_limits.py` gained `--write-baseline` / `--check-baseline`
  (ratchet); baseline committed at `synesyn/tools/line_limit_baseline.json`; the `synesyn-reviewer`
  skill now runs `--check-baseline` as a blocking gate.
- 2026-07-09: Phase 1 pilot landed — `hub_substrate_client.gd` split (1251 -> 799). See ADR 0005.
  Remaining hard violations: 12.
- 2026-07-09: Phase 1 continued. `conversation_manager.gd` moved chat context assembly into
  `conversation_chat_context_builder.gd` (1238 -> 1032); `scensyn_render_purpose_service.gd`
  moved stateless render/workflow helpers into `scensyn_render_purpose_utils.gd` (1528 -> 1160);
  `services_panel.gd` moved workspace state/path helpers into `services_panel_workspace_utils.gd`
  (1436 -> 1183). Baseline regenerated. Remaining hard violations: 9.
- 2026-07-09: Phase 2 started. `game_session.gd` moved UI/header/TTS/model-control helpers into
  `game_session_ui_utils.gd` and report/status helpers into `game_session_report_utils.gd`
  (1530 -> 1185). Baseline regenerated. Remaining hard violations: 8.
- 2026-07-09: Phase 2 continued. `workshop_catalyst_controller.gd` moved export/markdown helpers
  into `workshop_catalyst_export_utils.gd` and bucket merge/dedupe helpers into
  `workshop_catalyst_bucket_utils.gd` (1423 -> 1152). Baseline regenerated.
  Remaining hard violations: 7.
- 2026-07-09: Phase 2 continued. `story_stage.gd` moved controls/navigation/render-status
  helpers into `story_stage_controls_utils.gd`, presentation/TTS/lull/model/test helpers into
  `story_stage_presentation_utils.gd`, and input/story-log playback/STT helpers into
  `story_stage_input_utils.gd` (2434 -> 1161). Baseline regenerated.
  Remaining hard violations: 6.
- 2026-07-09: Phase 3 started. `brainstorming_tab.gd` moved debug, emergency visibility,
  cursor, layout-fix, and integration-test helpers into `brainstorming_tab_debug_utils.gd`
  (1863 -> 965). Baseline regenerated. Remaining hard violations: 5.
- 2026-07-09: Phase 4 started opportunistically while `document_session_manager.gd` was deferred
  for a dedicated `DocumentSessionManager.DocumentContext` compatibility pass. `metapunkt_main.gd`
  moved AgentDefinition validation/form/preflight helpers into `metapunkt_agentdef_utils.gd`
  (1384 -> 1172). Baseline regenerated. Remaining hard violations: 4.
- 2026-07-09: Phase 4 continued. `synpunkt_dock.gd` was already a utility-backed wrapper facade,
  so its wrapper-heavy tail was compacted without changing behavior (1418 -> 1132). Baseline
  regenerated. Remaining hard violations: 3.
- 2026-07-09: Phase 4 continued. `syntree_panel.gd` moved Dev Agent/run-spec behavior into
  `syntree_panel_dev_agent_utils.gd` and conversation/store actions into
  `syntree_panel_store_actions.gd`, preserving scene-wired wrapper names (2289 -> 1151).
  Baseline regenerated. Remaining hard violations: 2.
- 2026-07-09: Phase 4 continued. `mission_control_dashboard.gd` was split into a path-based
  inheritance chain under `readymade/ui/internal`, keeping `MissionControlDashboard` as the
  original scene-facing class while preserving method bodies and scene-wired names (5509 -> 4).
  Baseline regenerated. Remaining hard violations: 1.
- 2026-07-09: Phase 4 completed for hard violations. `document_session_manager.gd` was split
  into a path-based inheritance chain under `readymade/scripts/core/internal`, keeping the
  autoload path as a facade and preserving `DocumentSessionManager.DocumentContext` through the
  inherited base state (3142 -> 2). Baseline regenerated. Remaining hard violations: 0.
