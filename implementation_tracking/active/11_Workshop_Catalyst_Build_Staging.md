# To-Do - Workshop Catalyst Build Staging (sequenced delivery plan)

**Status**: Living plan. Sequencing and safety layer over the decisions already recorded elsewhere — do not duplicate their detail here; link and extend.

**Primary spec references (source-of-truth order per `docs/SYSTEM_MAP.md`)**
- `../../product-requirements/PRD-SCENSYN-WORKSHOP-CATALYST.md` (product intent)
- `../Synesyn_Platform_Technical_Architecture.md`, `../Synesyn_Hub_API_Spec.md`, `../LatentSubstrate_Data_Model.md`, `../Human_Agency_UX_Contract.md`, `../ScenSyn_Scenario_Continuity_Contract.md` (normative contracts)
- `../ScenSyn_Workshop_Catalyst_Runtime_Robustness_Plan.md` (implemented; do not regress)
- `10_Session_Types_and_Society_of_Minds.md` (companion detail doc — Session Type/Collection, Society of Minds, gotchas E.1–E.5, guardrails)
- `../../architectural-decisions/` (record ADRs where a stage makes a real choice with alternatives)

**Scope captured in this plan**
Everything clarified in the ScenSyn → Workshop Catalyst strategy thread: Session Type / Collection elevation; Society of Minds hidden synthesis; the voice-first Wayfore-inspired flow (welcome/start, live voice, transcript trust, thinking map, compare paths, editable summary, settings); the panel-group + workspace-preset UI density system; and the mock-up read as the "Full Dashboard" preset.

**Explicitly deferred (per user)**
Email notifications and any active outbound follow-up automation. `Plans` and `Progress` remain **visible as stubbed previews** (labelled "coming soon", never dead controls), not built features. Remote participant sync remains **target UI** (`Invite`/avatars kept) with integration catching up later — no real multi-client turn sync in this plan.

**Working principles carried into every stage (from `SYSTEM_MAP.md`)**
1. Hub is the system-of-record; Godot is presentation/interaction. No authoritative state duplicated client-side.
2. Any payload crossing the Godot ↔ Hub seam is a **contract change**: update both sides + the normative spec + run the harness. Never change one side silently.
3. Workshop-specific logic stays inside the Workshop Catalyst Session Type / Collection; shared runtime only gains generic hooks.
4. Propose → preview → commit → version; editable before commit (Human Agency UX Contract).
5. Non-blocking Hub I/O during live sessions.
6. Respect line limits (`utilities/checks/check_line_limits.py`, soft 900 / hard 1200); split before adding surfaces.
7. Verification spine after each stage: `test_harness.py` smoke + multiturn specs, `check_line_limits.py --check-baseline`, hub tests when Python changes.

---

## Stage map (dependencies)

```
S0 Groundwork ─┬─ S1 Session Type/Collection ─┬─ S2 Facilitator entry
               │                               ├─ S3 WC settings .tscn split
               │                               └─ S4 Panel-group + preset shell
               └─ (contracts drafted)
S4 ─ S5 Society of Minds runtime ─ S6 Voice-first live view + transcript trust
S5/S6 ─ S7 Editable Session Record ─ S8 Thinking Map ─ S9 Compare Paths
S7/S8/S9 ─ S10 Participant + Plans/Progress stubs
```
S2, S3, S4 can proceed in parallel once S1 lands. S5 depends on S4 (needs a home for the single-voice output and "show reasoning" affordance). S8/S9 depend on S7's commit/provenance pattern. S8 also depends on the reusable Graph Workspace seam established by SynTree Context Graph stages I.1–I.3 in `03_SynTree.md`; it must not copy or import SynTree-specific controllers.

---

## Stage 0 — Groundwork, contracts, and safety net (no behaviour change)
**Goal**: make later stages safe and reviewable; change zero runtime behaviour.
- [x] Capture baseline: run existing WC smoke + multiturn harness specs and record green baseline; run `check_line_limits.py --check-baseline`. (2026-07-10: smoke passed with 5 story-log entries; multiturn passed with 13 entries and two character senders; line-limit ratchet passed.)
- [x] Record ADR(s) for the decisions with real alternatives: (a) Session Type/Collection elevation replacing "theme"; (b) Society of Minds hidden-synthesis topology for WC; (c) panel-group + preset UI model. (ADR 0009 records the coupled product architecture decision.)
- [x] Draft (not yet implement) the contract deltas each later stage needs, so both sides move together:
  - [x] `LatentSubstrate_Data_Model.md`: transcript/correction lineage, specialist trace, thinking-map item ownership, workshop summary, and path-set v1 shapes.
  - [x] `Synesyn_Hub_API_Spec.md`: generic artifact commit remains sufficient initially; dedicated routes require a complete seam update.
  - [x] `Human_Agency_UX_Contract.md`: proposal review and explicit commit now cover bucket updates, map items, summaries, and paths.
- [x] Confirm PRD covers the voice-first professional journey; PRD v0.2 now includes hidden synthesis, voice/transcript trust, presets, map proposals, path comparison, and human commit authority.
- **Verification**: baselines recorded; no code diff beyond docs.
- **Rollback**: docs-only; nothing to revert.

## Stage 1 — Session Type / Collection scaffolding (mechanical)
**Goal**: elevate "theme" → `SessionType` with a generic `SessionType → Collection` registry. Detail: doc 10 §A, §B, §B.1, §B.2.
- [x] Folder `scenario_themes/` → `session_types/`; nested Collection subfolders for `story_catalyst`.
- [x] `Global.gd`: `current_theme` → `current_session_type`; three scenario lists → two-level registry `session_type_id → collection_id → scenario_names`; generic dispatch written uniformly for both Session Types.
- [x] `scenario_loader.gd`: `theme` param → `session_type` + `collection_id`.
- [x] `workshop_catalyst` registers exactly one Collection (`decision_triage`); `story_catalyst` registers `sustainability` + `cultural_narratives` with their existing managers/subsystems intact.
- [x] Manual-check `behavior_trees/narrator_x_bt.tres`; add "superseded terminology" note to `THEME_REFACTORING_IMPLEMENTATION_PLAN.md`.
- **Guardrails**: Story Catalyst behaviour byte-for-byte unchanged; no `mode` local-var shadowing; keep `ThemeManager` (light/dark) untouched to avoid the naming collision.
- **Verification**: all existing sustainability + cultural + workshop scenarios load and run via harness; line-limit baseline holds. (2026-07-11: focused registry/loader test passed; WC smoke and multiturn passed; sustainability and cultural smoke specs passed; line-limit ratchet passed.)
- **Rollback**: single mechanical commit; revert restores `scenario_themes/`.

## Stage 2 — Facilitator entry + character-selection bypass
**Goal**: WC sessions skip character selection; human enters as `Facilitator`. Detail: doc 10 §G.
- [x] `character_options.gd`: bypass for `workshop_catalyst`; `story_catalyst` keeps the character cards. (Both active and alternate routes use the same explicit Session Type guard.)
- [x] New minimal `facilitator_session_setup.gd`: sets sender = `Facilitator` (reuse existing `send_as_facilitator`), skips character-pool generation.
- [x] `game_session.tscn` `%CharacterLabel` shows "Facilitator", not a stakeholder name.
- **Guardrails**: reuse existing facilitator sender/commands (`/decide`, `/vote`, note-only); no new closure paths.
- **Verification**: passed 2026-07-11 — focused routing/identity/real-entry test; Session Type registry test; WC smoke (4 log entries, no errors) and multiturn (8 entries, Facilitator + two AI character senders, no errors); sustainability Story Catalyst smoke (4 entries, no errors); line-limit ratchet; changed-file lints.
- **Rollback**: routing guard is isolated; revert re-enables selection.

## Stage 3 — Workshop settings `.tscn` migration + controller split
**Goal**: stop growing the WC controller (already ~1152 lines, at the hard limit) before adding any UI. Detail: doc 10 §G, gap-closure "UI surfaces".
- [x] Extract `WorkshopCatalystController._build_settings_ui()` (code-built tree) into `workshop_catalyst_settings_panel.tscn`; controller binds state only.
- [x] Split controller into focused modules (runtime orchestration, settings binding, timing/agenda normalization, and the existing export utility) to clear the line-limit violation.
- **Guardrails**: pure refactor — identical behaviour; no new features in this stage.
- **Verification**: passed 2026-07-11 — deterministic settings scene/binding/defaults/persistence/ownership test; real Workshop facilitator-entry scene test; WC smoke (5 log entries) and multiturn (13 entries, three tail senders) harness specs; sustainability Story smoke (3 entries); line-limit ratchet; changed-file lints. Main controller is 756 lines; settings binding 262; timing module 227; export utility 159. The focused test covers the pre-session-dependent settings/timer bindings that the harness cannot exercise.
- **Rollback**: refactor-only commit.

## Stage 4 — Panel-group + workspace-preset shell (the density solution)
**Goal**: reproduce the established Synesyn panel-toggle pattern for WC so the full dashboard can be progressively disclosed. Reference implementations: `synaxes_runtime_controller.gd` (`_on_toggle_left/viewer/bottom_panel`), SynTree toolbar toggles, SynPunkt artifacts/advanced toggles.
- [x] Define WC panel groups: Conversation, Thinking Map, AI Assistant, Session Record, Participants, Navigation.
- [x] Toolbar with per-group toggles + workspace presets: **Talk**, **Map**, **Review**, **Full Dashboard** (the mock-up), **Custom** (remembers manual toggles).
- [x] Persist last preset/custom layout in runtime config (`apps.scensyn.*`).
- [x] Always-visible safety controls regardless of preset: recording/listening status, mic consent, End & Save, connection/transcription errors, uncommitted-change warnings.
- **Guardrails**: presets choose default *visible* panels only; never hide safety/consent controls; `.tscn`-authored panels, not code-built.
- **Verification**: passed 2026-07-11 — focused pure-model/scene/controller test covers every preset, manual-toggle → Custom memory, persisted-state restoration, action routing, and the structural invariant that the safety bar is outside preset-managed panels; Stage 3 and real facilitator-entry scene regressions passed. WC smoke passed (4 log entries); WC multiturn passed (14 entries, Facilitator + Gareth Price + Maya Desai in the asserted tail); sustainability Story smoke passed (4 entries); all harness runs reported no unexpected errors. Line-limit ratchet and changed-file lints passed. Main controller is 814 lines; workspace controller 379; pure preset model 84. The harness does not exercise pre-session preset selection; the focused UI test is the evidence for preset and safety behavior.
- **Rollback**: shell is additive; default to Full Dashboard if preset logic disabled.

### Dashboard hierarchy refactor (2026-07-11)
- [x] Replaced the generic six-card `GridContainer` with a scene-authored
  three-region dashboard: fixed/collapsible left navigation rail, flexible center
  workspace, and fixed/collapsible right insight/record rail.
- [x] Moved participant presence/Invite into the session header, kept Thinking
  Map as the main center canvas, and moved Compare Paths out of the permanent
  Session Record subtree into the center Review surface.
- [x] Established a clean Session Type boundary for the live conversation:
  Workshop mounts only the shared `StoryLogSystem`, input, and voice actions.
  The legacy StoryLog/About/How To `TabContainer` remains hidden and owned by
  Story Catalyst rather than being mounted and cosmetically concealed.
- [x] Integrated safety state into the compact shell footer with End & Save
  anchored at its right edge; presets cannot hide it.
- [x] Reworked preset semantics around named content/regions. Review reparents
  the existing editable Session Record into the center review surface without
  replacing its controller or persistence state; other presets retain it in the
  right rail. Custom retains region and rail preferences.
- [x] Added deterministic wide/medium/narrow coverage. Navigation and Insights
  use one CheckButton each as the sole rail controls; the duplicate header and
  drawer buttons were removed. In narrow mode the same checks open the
  corresponding sequential panel while keeping the center primary. At 1024px
  the two rails reserve at most 440px of
  horizontal minimum size. Thinking Map Causes/Effects/Opportunities stay
  side-by-side (`columns = 3` via `workshop_map_layout_utils.gd`) and shrink
  to share width rather than stacking vertically.
- [x] Updated focused Stage 4/8/9/10 hierarchy assertions; the Stage 4 test
  rejects a generic `WorkspacePanels` grid and duplicate rail controls, and
  checks the 1024px responsive contract, unified checks, preset semantics,
  safety reachability, and bound controls.

### Godot UI architecture hardening (2026-07-13)
- [x] Made the Workshop shell hidden-by-default and controller-activated, and
  replaced Session Record's ancestor-walk lookup with an explicit scene-owned
  mount region. Existing shared conversation/input controls still cross one
  centralized compatibility mount seam; no feature controller may reparent or
  independently resize those controls.
- [x] Kept panel visibility, presets, rail drawers, split persistence, and
  responsive breakpoints under `WorkshopWorkspaceController`. Transcript trust
  now requests preview/correction visibility through that owner rather than
  mutating layout controls directly.
- [x] Added shared structural `SynesynUiTokens` for breakpoints, rail extents,
  split minima, spacing, and practical content sizes; visual colors, fonts,
  radii, and widget styling remain owned by Godot Theme resources.
- [x] Preserved scene-authored specialist widgets and extracted retained
  specialist-summary presentation into `WorkshopSpecialistTraceView`, keeping
  the workspace controller below the 900-line policy.
- [x] Expanded Stage 4 coverage to a narrow/medium/wide boundary matrix across
  Talk, Map, Review, and Full Dashboard, while retaining explicit clipping,
  scroll-ownership, safety, split, and control-binding assertions.
- [x] Added a debug-build-only layout diagnostics overlay showing active
  breakpoint, viewport width, split offsets, actual/minimum sizes, parentage,
  clipping, scroll ownership, and detected horizontal overflow.
- **Verification**: Stage 4–10 focused regressions, real Facilitator entry,
  changed-file lints, and the 669-script line-limit ratchet passed on
  2026-07-13. The smoke harness reached the correct scenario, retained the
  facilitator turn, and produced three log entries, but its `--no-errors`
  assertion was blocked by the configured Anthropic account's HTTP 400
  insufficient-credit response. Multiturn was not repeated against the same
  definitively unavailable provider.

### GTML pilot decision (2026-07-13)
- [x] Complete a bounded, read-only Workshop Overview pilot without replacing
  the authoritative native Session Record or adding persistence seams.
- [x] Reject GTML for production use after visual evaluation. Live-state
  binding worked, but generated Controls produced oversized, sparse geometry
  and did not reliably honour the CSS sizing and flex constraints needed by
  the Workshop dashboard.
- [x] Remove the pilot controller, dialog, toolbar control, HTML/CSS assets,
  focused pilot test, and complete vendored GTML runtime.
- **Decision**: continue with scene-authored native Godot UI, shared tokens,
  reusable components, centralized layout ownership, and viewport regression
  coverage. GTML would add dependency and debugging cost without reducing
  layout-specific Godot work.
- **Removal verification**: Stage 4 responsive-shell and Stage 7 native-record
  regressions pass, changed-file lints are clean, no ScenSyn source or vendored
  GTML files remain, and the 669-script line-limit ratchet has no hard
  violations. The required smoke harness reaches the correct scenario and
  retains three log entries; `--no-errors` remains blocked solely by the
  configured Anthropic account's insufficient-credit HTTP 400 response.
- [ ] Complete human visual/projector and keyboard inspection at target
  resolutions. Automated structural and responsive checks do not certify visual
  polish, focus order, room readability, or hardware behavior.

### Spatial UI Stage S8 vertical slice (2026-07-14) — WITHDRAWN 2026-07-15
> The spatial UI effort was abandoned after a cost-benefit review (see ADR 0010).
> All spatial code and planning docs were moved to `_archive/spatial_ui/`; only
> the semantic visual-profile system was salvaged (`addons/synesyn_visual_profiles/`).
> The checklist below is retained as historical record and is not active work.
- [x] Product owner explicitly authorized the additive S8 implementation while
  retaining every S7 manual check as a migration/native-retirement blocker.
- [x] Added five product-owned surfaces and exact preset compatibility:
  Talk/Talk, Thinking Map/Map, Compare Paths plus Session Record/Review, and
  Overview/Full Dashboard. Custom remains a local native layout preference.
- [x] ADR 0011 selects the shared cube over the horizontal drum: four lateral
  workflow faces plus Overview/top. The bottom is intentionally unused;
  evidence/provenance stays in contextual frame content.
- [x] Added product-owned adapter/host/fallback facades around
  `WorkshopWorkspaceController.apply_preset(...)` and stable root-node IDs.
  No Workshop business logic moved into the shared addon.
- [x] Added scene-authored Workshop top/right/input/action/safety injection,
  true face-mounted rendering/input of the single authoritative native root,
  reachable history/rollback, one-shot product validation, attention
  non-acceptance, draft/focus retention, lossless acknowledged fallback for all
  five surfaces, and visible recovery after failed acknowledgement.
- [x] Added a default-false
  `apps.scensyn.workshop_spatial_vertical_slice_enabled` setting without wiring
  any production entry route. Deterministic review scene:
  `res://ScenSyn/session_types/workshop_catalyst/workshop_spatial_debug.tscn`.
- [x] Focused S8, Workshop Stage 4–10, facilitator entry, spatial S1–S8,
  LimboAI compatibility, changed-file lints, addon import boundary, debug-scene
  load, and the 734-script line-limit ratchet completed. All named model-free
  assertions pass. The existing Stage 5 test fixture still emits
  `StoryState.current_narrative_phase` dictionary access while reporting its
  assertions passed; startup/teardown also retains the pre-existing unavailable
  logging-service and resource-leak diagnostics, so the sweep is not described
  as globally error-free.
- [ ] Provider-dependent harness acceptance. Smoke reached the GLP-1 Scenario
  with 3 log entries; multiturn reached 7 entries, exactly one visible Workshop
  assistant, and one Session Record response per turn. Both failed `--no-errors`
  because Anthropic returned HTTP 400: `Your credit balance is too low to access
  the Anthropic API. Please go to Plans & Billing to upgrade or purchase
  credits.` The degraded multiturn path also had only one distinct tail sender.
- [ ] Owner live visual/projector, voice, keyboard, interruption,
  reduced-motion, and assistive-technology review. S8 remains feature-flagged,
  the native Workshop shell remains authoritative, and the S8 gate remains
  pending owner preference/lossless-fallback review.

## Stage 5 — Society of Minds runtime (hidden synthesis)
**Goal**: WC produces ONE synthesized assistant voice per turn from a batched specialist call. Detail: doc 10 §C, §D, §E (esp. E.1 batched-not-parallel, E.2 reuse Session Record, E.4 vote re-scope, E.5 single seam).
- [x] `SessionTypeRuntimeProfile`: `visible_ensemble` (Story) vs `hidden_synthesis` (WC).
- [x] `AICharacterAgent`: single `_finalize_turn()` dispatch → `_finalize_turn_visible_ensemble()` / `_finalize_turn_hidden_synthesis()`. `DirectorAgent`/`ActorAgent` unchanged.
- [x] Specialist contributions, validated map candidates, facilitator cues, and
  the participant-facing response now return through one structured model call.
  Production inference is stateless: no persisted chat history, general SynTree
  context, or current-thread mutation.
- [x] Preserve long-session continuity through bounded curated state: Scenario,
  current stage, latest input, eight meaningful recent exchanges,
  facilitator-authorized Session Record buckets, and explicitly enabled
  committed Thinking Map context. Provider errors and degraded fallbacks are
  excluded.
- [x] `WorkshopCatalystSessionRecord` posts the response already synthesized by
  the specialist batch. Its older `synthesize_turn(...)` compatibility seam is
  not used by the production hidden-synthesis path, eliminating the second
  per-turn model request.
- [x] Re-scope vote/closure for hidden mode (E.4): specialists do not vote; participant/facilitator-visible `/vote` and `/decide` paths remain authoritative.
- [x] Retain concise specialist contributions as non-blocking `json.workshop_specialist_trace` artifacts and expose the collapsed-by-default, revocable reasoning/status disclosure.
- **Guardrails**: exactly one stateless model task per Workshop turn; no
  concurrent or sequential `ConversationManager.chat()` calls; `StoryState
  {sender,message}` schema unchanged; Story Catalyst path provably untouched.
- **Verification**: passed 2026-07-11 — focused Stage 5 Godot tests cover profile dispatch, exactly one specialist batch, deterministic malformed-response fallback, one visible synthesis, zero specialist votes, trace/degraded-Hub contract, and reasoning-panel states. WC multiturn passed with 7 log entries, exactly one non-human sender (`Session Record`), and exactly three Session Record responses across three turns; WC smoke passed with 3 entries; Story sustainability multiturn passed with 9 entries and three visible AI senders (`ARIA`, `ELSA`, `SAIA`). Stage 3/4 regressions, harness Python tests, changed-file lints, and line-limit ratchet passed. Largest changed scripts: `ai_character_agent.gd` 898 lines, Session Record 794, workspace controller 454; new coordinator 234, trace store 142, profile 21.
- **Rollback**: profile flag — set WC back to `visible_ensemble` to disable synthesis without code removal.

**2026-07-11 local-model hardening**: Ollama Workshop tasks now enforce JSON
output, 4096 context tokens, 768 predicted tokens, temperature 0.2, one attempt,
and a 180-second HTTP budget aligned with a 210-second in-scene watchdog.
Focused Stage 5, Scenario/map-correction, and Stage 8 regressions pass; the
line-limit ratchet and changed-file lints pass.

**2026-07-11 Thinking Map/Ollama resilience**: substantive facilitator
statements now receive a strictly validated, model-free `participant_said`
candidate fallback when the structured model batch yields no map candidate.
These records remain Suggested, unsupported, provenance-labelled, and
facilitator-reviewed; meta/process text remains excluded. Locally validated
participant candidates survive model-service degradation without converting a
failed AI result into an AI claim. Ollama `keep_alive` was reduced from 24 hours
to five minutes so switching models does not pin multiple large models in
RAM/VRAM all day. Stage 5, Stage 8, Scenario/map-correction, lints, and line
limits pass.

## Stage 6 — Voice-first live view + transcript trust
**Goal**: WC default surface is voice-first with a trustworthy transcript. Detail: gap-closure "Live session" + "Transcript review".
- [x] WC live layout integrated into the Stage 4 Conversation panel using
  `%RecordButton`, `MicrophoneRecorder`, `ScenSynVoiceBridge`, and existing Hub
  voice services; static transcript controls are scene-authored.
- [x] STT preview is editable and requires explicit send; cancel/re-record works
  and typed input retains its existing direct path.
- [x] Post-send correction preserves original STT and creates immutable
  `json.workshop_transcript_segment` lineage through the generic Hub artifact
  seam. Save-only is the default; resend is a separate explicit action.
- [x] Session Record is the only Workshop sender allowed through TTS. Hidden
  specialist summaries and technical/facilitator senders remain silent; Story
  Catalyst voice behavior is unchanged.
- **Guardrails**: correction is a contract change (new artifact type) — update `LatentSubstrate_Data_Model.md` + both sides + harness; non-blocking persistence.
- **Verification**: passed 2026-07-11 — focused Stage 6 Godot tests cover
  preview edit/send/cancel, typed-input non-regression, immutable original +
  corrected lineage, correction without a second turn, degraded Hub behavior,
  and Session Record-only speech. Hub suite passed 29 tests including validation
  and compatibility-reader round-trip. Deterministic STT harness, WC smoke, WC
  hidden-synthesis multiturn (one Session Record sender, three responses), Story
  sustainability smoke, and Story sustainability multiturn all passed with no
  unexpected errors. Stage 3–5 regressions, changed-file lints, and line-limit
  ratchet passed. Real microphone permissions, device capture, acoustic quality,
  and audible playback remain manual hardware checks.
- **Rollback**: set `apps.scensyn.workshop_transcript_trust_enabled=false` to
  restore the shared input behavior while preserving Session Record-only speech.

## Stage 7 — Editable Session Record (propose → preview → commit)
**Goal**: turn the read-only record into an editable, committable summary. Detail: gap-closure "Summary"; Human Agency contract.
- [x] Replace `%SessionRecordTabLabel` read-only BBCode with structured editable fields: decisions, risks, open questions, owners, next steps.
- [x] AI bucket update becomes a **diff preview**: accept / edit / reject / defer — not automatic merge.
- [x] Commit accepted summary snapshot to Hub (`ui.workshop_summary` or extend `ui.syndoc`); export references the committed artifact.
- [x] Record reject/defer events (SynAxes Dream-Inbox pattern) so discarded proposals aren't re-suggested.
- **Guardrails**: facilitator edits win over LLM merge; commits go through ClosureBus/substrate with provenance; contract change → both sides + spec + harness.
- **Verification**: passed 2026-07-11 — focused Stage 7 Godot coverage
  proves proposal isolation; accept/edit/reject/defer; facilitator-edit
  precedence; exact/semantic repeat suppression; preview non-mutation; no Hub
  artifact before explicit commit; immutable `previous_version_id` lineage;
  degraded-Hub retention/retry; committed-reference and truthful fallback
  exports; scene controls; and module limits. Stage 3–6 focused regressions
  passed. The full Hub suite passed 35 tests, including summary validation and
  round-trip. WC smoke (3 entries), WC hidden-synthesis multiturn (7 entries,
  one AI sender and three Session Record responses), STT preview (3 entries),
  Story sustainability smoke (3 entries), and Story sustainability multiturn
  (9 entries, four visible ensemble senders) all passed with no unexpected
  errors. Line-limit ratchet and changed-file lints passed. Controller is 815
  lines, Session Record 794, state/store 512, panel controller 283, proposal
  engine 116, and persistence coordinator 96.
- **Rollback**: keep current export path as fallback behind flag.

## Stage 8 — Thinking Map
**Goal**: the mock-up's central map as the "Map" preset, with states and evidence. Detail: gap-closure "Thinking map"; user decisions (Causes/Effects/Opportunities plural; item states; provenance distinction).
- [x] Consume the runtime-safe shared Graph Workspace defined by `03_SynTree.md`: graph document primitives, typed-edge validation/diff, proposal/review states, provenance references, layout separation, and Hub artifact transport.
- [x] Add a WC-owned `ThinkingMapAdapter` and `workshop_thinking_map.tscn`/controller; forbidden-dependency tests cover SynTree content/controller/compiler/editor imports.
- [x] Present the workshop projection as columns **Causes / Effects / Opportunities** while retaining a graph-capable underlying document for causal and evidential connections.
- [x] Add a Columns | Graph view toggle on the Thinking Map that projects the same document through the shared Graph Workspace canvas (typed edges, selection, layout persistence) with a WC-owned selected-node review strip; no SynTree editor import.
- [x] Map item states: Suggested, Accepted, Edited, Rejected; defer is retained as an explicit proposal decision without inventing a shared canonical graph state.
- [x] Provenance markers distinguish participant-said, AI-inferred, and external-evidence-supported; unsourced synthesis remains AI-inferred.
- [x] Apply transcript/synthesis changes as batched incremental graph commands with stale replacement and idempotent batch ids; no full live-event rebuild path exists.
- [x] Persist snapshots as a separate versioned `ui.workshop_thinking_map` Hub artifact with Preview-before-Commit, facilitator provenance, lineage, and degraded retry.
- [x] Route facilitator-approved map outcomes into Session Record/ClosureBus only through explicit WC actions.
- [x] Keep each map column independently scrollable with wrapped review actions
  and content-responsive card heights, so long Suggested propositions remain
  readable without clipping adjacent dashboard regions.
- **Guardrails**: map semantics stay WC-owned (not SynTree- or SynPunkt-coupled); map entries are proposals; no auto-inject into specialist prompts without a visible toggle; persistence is non-blocking; no automatic conversion to `ui.context_graph`.
- **Verification**: passed 2026-07-11 — focused Stage 8 and shared conformance Godot tests cover forbidden dependencies, plural columns, proposal lifecycle/provenance, typed edges, incremental/stale batches with zero rebuilds, preview non-mutation, explicit version commit/degraded retry, separate artifact kind/type, explicit Session Record/ClosureBus routing, and default-off/revocable specialist context with absent/disabled prompt identity. Hub suite passed 41 tests including map validation/round-trip. WC smoke passed with 3 entries; hidden-synthesis multiturn passed with 7 entries, one visible `Session Record` sender, and exactly three responses; STT passed with one response. Story sustainability smoke passed with 3 entries and multiturn with 8 entries/multiple senders. Stage 4/5/7 regressions, line-limit ratchet, boundary search, and changed-file lints passed. Manual visual/interaction testing remains appropriate for the pre-session Map preset because the harness cannot select it before session start.
- **Rollback**: map is an additive panel group; disable via preset.

## Stage 9 — Compare Paths (evidence-backed, incl. do-nothing)
**Goal**: the commercial centrepiece. Detail: gap-closure "Compare paths".
- [x] First-class path objects incl. explicit `is_do_nothing`; fields: outcomes, biggest risk, assumptions, uncertainty, time horizon, `evidence_refs[]` (or explicit `evidence_status: none`).
- [x] Evidence retrieval via Artrhythmetic Store; citations surfaced in plain language.
- [x] Facilitator selects/combines a path → commit via ClosureBus with store trace ids.
- **Guardrails**: every path states evidence status honestly; do-nothing always present; commit only on explicit approval; no simulation jargon in UI.
- **Verification**: passed 2026-07-11 — focused Stage 9 Godot coverage
  proves normalization and complete required fields, exactly one do-nothing path,
  proposal-only import, facilitator-edit precedence, evidence-none labels, stale
  retrieval cancellation and unavailable state, preview non-mutation, single and
  combined draft selection, explicit-only Hub and ClosureBus commit,
  delivery-only retry without duplicate artifact or lineage advance, and
  explicit Session Record routing. Stage 7/8 focused regressions passed. The
  full Hub suite passed 47 tests, including path-set validation/round-trip. WC
  smoke passed with 3 entries; hidden-synthesis multiturn passed with 7 entries,
  one visible `Session Record` sender and exactly three responses; STT passed
  with one response. Story sustainability smoke passed with 4 entries and
  multiturn with 7 entries and three visible ensemble senders. All harness
  assertions reported no unexpected errors. The line-limit ratchet passed;
  controller/path store/path UI controller/evidence/persistence are
  899/517/409/185/154 lines. Changed-file lints passed. Manual visual review
  remains appropriate because the harness cannot select the pre-session Review
  workspace.
- **Rollback**: the scene-authored Compare Paths surface and WC-owned modules are
  additive. Removing its Review-panel instance and controller mount disables the
  feature without changing Stage 5 synthesis, Stage 6 voice, Stage 7 Session
  Record, Stage 8 map, or Story Catalyst paths. Persisted path-set artifacts
  remain immutable history.

## Stage 10 — Participant + Plans/Progress stubs (target UI, no dead controls)
**Goal**: keep the aspirational surfaces visible without implying capability that isn't there.
- [x] `Invite` + participant avatar/status retained as target UI. The panel shows
  the local Facilitator on this device and states that remote presence is
  unavailable. Invite opens an explanatory dialog, requests no contact data, and
  performs no outbound action.
- [x] `Plans` and `Progress` remain in Navigation and open distinct labelled
  previews describing current local review surfaces and deferred capabilities.
- **Guardrails**: no email/outbound automation; no false affordances (regression-test rule from robustness plan — "no visible control leads to a dead end").
- **Verification**: passed 2026-07-11 — focused Stage 10 Godot coverage
  enumerates every visible Participant/Plans/Progress control, verifies Invite
  dialog and acknowledgement resolution, verifies both previews, checks the
  focused controller for outbound seams, and reports zero outbound actions.
  Stage 4 workspace regression passed. WC smoke passed with 3 log entries; WC
  hidden-synthesis multiturn passed with 7 entries, one visible `Session Record`
  sender, and three responses; deterministic STT passed with 3 entries and one
  response. Story sustainability smoke passed with 5 entries; multiturn passed
  with 10 entries and four visible ensemble senders. All harness assertions
  reported no unexpected errors. Line-limit ratchet and changed-file lints
  passed. Main controller remains 899 lines; workspace controller is 457 lines;
  the new target-surfaces controller is 110 lines. Projector readability,
  keyboard focus, and visual dialog placement remain manual checks.
- **Rollback**: remove the Stage 10 scene nodes and focused controller mount to
  restore the prior static labels. No Hub data, participant records, messages,
  plans, or progress records require migration or cleanup.

## Stage 11 — Scenario authorship and structured map correction
**Goal**: remove legacy Workshop role-play assumptions, make Scenario creation
the default entry action, and prevent facilitation prose from becoming map
content.
- [x] Migrated all Workshop templates to character-free institutional
  perspectives and added a Workshop-only compatibility normalizer.
- [x] Kept Story Catalyst character parsing and `visible_ensemble` unchanged.
- [x] Added scene-authored Scenario setup, explicit facilitator review, generic
  agenda/time defaults, and versioned local-draft persistence under `user://`.
- [x] Removed forced GLP-1 Workshop entry; authored Scenarios remain templates.
- [x] Extended the existing specialist batch with versioned structured
  `map_candidates` plus separate `facilitator_cues`.
- [x] Added strict category, proposition, provenance, evidence-status, meta-text,
  and semantic-duplicate validation. Degraded batches create zero candidates.
- [x] Routed valid candidates through the Workshop event/command seam as
  Suggested map nodes; removed whole-response and whole-participant insertion.
- [x] Added focused compatibility, Story preservation, prompt isolation,
  custom-Scenario round-trip, candidate parsing/rejection, provenance, and
  no-whole-response coverage.
- [ ] Record final harness and regression outcomes after the full Stage 3–10,
  Workshop, Story, line-limit, and lint verification sweep.
  - 2026-07-11: focused correction, Stages 3 and 5–10, Workshop STT, both Story
    smoke specs, Story multiturn, 52 Hub tests, 6 harness-unit tests, changed-file
    lints, and the 657-script line-limit ratchet passed.
  - Blockers retained truthfully: Stage 4's pre-existing headless responsive-rail
    assertions fail at medium/wide transitions; Workshop smoke and multiturn
    failed twice because the configured AI service was unreachable. Their
    selection/sender assertions still passed where evaluable. Story and Workshop
    STT calls succeeded in the same sweep.

### Facilitation method made explicit (2026-08-01)
**Goal**: name the facilitation method Workshop Catalyst already implied, and make
it travel to Scenarios the facilitator creates. See ADR 0012.
- [x] Named the reasoning method each of the four stable lenses already implied
  (abductive inference, perspective adoption, iterative narrowing, counterfactual
  framing) in `ROLE_DEFINITIONS`. No new roles, ids, or visible voices.
- [x] Added backstage domain adoption to the specialist prompt: each lens reasons
  from the expertise the subject matter requires, never names or performs it,
  never appears as a participant, and never upgrades evidential standing.
- [x] Added `CROSS_CHECKS` — the six pairings of four lenses — and instructed
  synthesis to work the pairings the current stage's required output depends on
  rather than compress generically. The pairings were already demanded by
  authored stage guidance; nothing new was invented.
- [x] Rejected a fifth adversarial instrument. Pre-mortem (counterfactual x
  abductive) and redraft-to-commit (perspective x iterative) are edges of the
  existing four, so the fourfold is sufficient.
- [x] Added `Weigh Who Is Affected` to `DEFAULT_AGENDA`. The Stakeholder lens was
  the only one without a stage; `weight_of_decision_glp1_policy_triage` had been
  compensating by hand with its equity/exclusion stress stage.
- [x] Added `default_stage_guidance()` so every Scenario runs with a four-part
  stage contract. Previously `create_custom()` supplied stage names and timers
  but no `stage_guidance`, so a facilitator-created Scenario ran a whole session
  on generic core rules. Authored guidance still wins.
- [x] Extended `test_workshop_scenario_and_map_corrections.gd`: six cross-checks,
  a method per lens, never-surface and evidential guards, complete four-part
  contracts for every default stage, the Stakeholder beat, objective
  interpolation, and authored guidance not overwritten.
- **Verification**: focused correction, Stage 3, 5, 7, 8, and facilitator-entry
  regressions passed. Line-limit ratchet reported no hard violations; changed-file
  lints clean. Changed files are prompt text, Scenario defaults, and tests; no
  schema, route, envelope, or Python change.
- **Harness finding (2026-08-01)**: the WC smoke spec passes but every turn
  returns the deterministic fallback, "I could not retain a reliable specialist
  analysis for this turn." The configured specialist model resolves to
  `llama2:latest`, which does not produce the strict four-role JSON envelope.
  An A/B run with the new prompt sections removed produced the identical
  fallback, so this is pre-existing and unrelated to the facilitation-method
  change. Consequence: the harness currently evidences scenario loading,
  sender attribution, and error-freedom only — it cannot evidence specialist
  content quality at all, because the assertions pass on fallback text. Any
  claim about specialist output quality needs a structured-output-capable model
  configured first.
- [x] Adaptive packaging recovery (no model pin): raise Ollama `num_predict` to
  2048; on full-envelope parse failure retry roles-then-synthesis; if phase 2
  fails keep roles with deterministic synthesis. Stage 5 tests cover single-call
  success, two-phase recovery, and roles-only degradation.
- [ ] Re-run smoke and multiturn against a model that can complete at least the
  roles phase, then judge manually whether the cross-checks improve facilitation.
  Automated coverage proves the structure and recovery path; it cannot prove the
  assistant is more useful to a facilitator.
- **Rollback**: revert the prompt block, `CROSS_CHECKS`, the added agenda stage,
  `default_stage_guidance()`, and the two-phase recovery in
  `workshop_specialist_coordinator.gd` / `workshop_stateless_model_task.gd`.
  Authored Scenarios are unaffected either way.
- **Cloud-provider finding (2026-08-02)**: after provisioning xAI/Grok and
  selecting `grok-4.5` live, specialist turns still returned the degraded
  fallback ("The specialist model could not be reached for this turn.").
  `godot.log` showed `[APIService] Attempt 1/2 failed (connection error)` for
  both turns, then `ERROR: APIService: Could not connect to AI service.` A
  headless `HTTPRequest` probe against `https://api.x.ai/v1/chat/completions`
  from this machine succeeded immediately (got a real 400 for a bad test
  key), ruling out DNS/TLS/proxy/firewall — the request itself was fine.
  Root cause: `workshop_stateless_model_task.gd` only extended the network
  read timeout (and single-attempt retry budget) for the `ollama` provider;
  every other provider fell through to `api_service.gd`'s default 25-second
  timeout with 2 attempts. The specialist envelope (four roles + cross-checks
  + map candidates as strict JSON) is a heavy structured generation that a
  "thinking" cloud model can legitimately take longer than 25s to produce;
  Godot buckets both real connection failures and read timeouts under the
  same generic "connection error" retry path, so this looked identical to a
  dead endpoint. Fix: `CLOUD_TIMEOUT_SECONDS = 120.0`, `max_retries = 1`
  applied to every non-Ollama provider (one long attempt beats two short
  ones against a slow model). Added `_test_stateless_cloud_task_timeout()`
  to Stage 5 asserting the extended budget is applied for a non-Ollama
  model. Not a Grok capability issue — no model pin, no scope change.
- **Thinking Map graph view: relations, manual connect, grouping, symbolic
  rules (2026-08-02)**: the Graph view rendered nodes but no edges, and
  overlapping nodes had no way to be organized. Four additive changes, kept
  behind the existing Columns/Graph toggle:
  - **Relations end-to-end.** `workshop_specialist_prompts.gd`'s map schema
    gained an optional per-candidate `relates_to: [{target_id, relation}]`
    (relation ∈ `causes|supports|contradicts|evidenced_by|related_to`,
    target_id must be another candidate's id in the same batch).
    `workshop_specialist_coordinator.gd` normalizes/dedupes it structurally
    (drops self-references and unknown relations; does **not** check the
    target exists — that is deferred). `thinking_map_adapter.gd`'s new
    `specialist_candidate_commands()` builds every node command first (so
    stable node ids are known), then resolves each `relates_to` entry into a
    `propose_edge` command; a target that didn't survive dedup/rejection is
    silently dropped rather than failing the batch. This is the only change
    that puts real, model-derived wires on the graph.
  - **Manual connect.** `graph_workspace_canvas.gd` gained a
    `connection_requested(from_id, to_id)` signal — the shared canvas stays
    domain-neutral per ADR 0008 and does not draw the connection itself. WC's
    `workshop_thinking_map_graph_projection.gd` catches it, pops the new
    `%ManualConnectRelationMenu` (`PopupMenu` in the `.tscn`) for a relation
    pick, and emits `manual_edge_requested`; the controller calls
    `ThinkingMapAdapter.manual_edge_command()`, which starts the edge
    pre-`accepted` (the facilitator authored it directly; no separate review
    step needed) instead of `suggested`.
  - **Visual grouping.** The canvas clusters any nodes sharing an
    `annotations.group_key` into a `GraphFrame` titled from `group_label`
    (≥2 members; a 1-node "cluster" is noise). WC populates `group_key` as
    `"stage:<current_stage_name>"` when a specialist batch lands — stage name
    is threaded from `ai_character_agent.gd`'s `workshop_state` through
    `WorkshopSpecialistTraceStore.retain_and_persist()`'s new `stage_name`
    param into the `candidate_batch_ready` payload. Godot 4.7's `GraphFrame`
    has no native collapse, so the canvas adds a `CheckButton` to the frame's
    own titlebar (`get_titlebar_hbox()`) that hides/shows member nodes — a
    literal "collapse this stage's cluster" control.
  - **Symbolic rules layer.** New `workshop_thinking_map_symbolic_rules.gd`
    (pure, read-only, no document mutation) runs three deterministic rules
    over the active (non-rejected) typed graph: `contradicts` edges become
    contradiction findings; `causes` edges are walked (cycle-guarded, depth
    ≤4) into derived multi-hop chains (never written back as new edges —
    that would blur asserted-vs-inferred); and any node feeding a
    `causes`/`supports` edge while its own `evidence_status` is
    `unknown`/`unsupported` is flagged as an evidence gap. The controller
    runs this on every `refresh()` and surfaces a one-line summary with a
    detail tooltip on the new `%SymbolicInsightsLabel` in the map footer —
    this is the actual neurosymbolic bridge: neural/human judgment produces
    typed claims and relations, deterministic rules reason over the
    resulting structure.
  - Covered by new/extended tests in
    `test_workshop_scenario_and_map_corrections.gd` (relation resolution
    end-to-end, manual-edge pre-accepted status and idempotency, canvas
    connection-request resolution + GraphFrame clustering, symbolic rules
    unit coverage) — all pass headlessly. Pre-existing, unrelated environment
    quirk: running these test scripts via `godot --headless --script`
    intermittently hits `Identifier not found: ThemeManager` while compiling
    `workshop_thinking_map_controller.gd` as a `preload()` dependency before
    autoloads register (reproduces identically on unmodified stage 8 tests);
    it does not affect the actual application, only breaks
    `ThinkingMapController.new()` inside that one CLI invocation.
  - **Rollback**: each of the four changes is additive and independently
    revertible — relations (prompt schema + coordinator/adapter/controller
    resolution), manual connect (canvas signal + projection popup + adapter
    method), grouping (canvas frame logic + stage_name threading), symbolic
    rules (new file + controller's `refresh()` hook + footer label). None
    change the Columns view, the commit/preview pipeline, or the Hub
    contract.
- **Session Record UX: pulse-per-turn + on-demand `/synthesis` recall
  (2026-08-03)**: the hidden-synthesis narrative (2-5 paragraphs, per doc 10
  §E.2) was posting to the visible log unconditionally every facilitator
  turn — a wall of text after each exchange. Decoupled the specialist
  *analysis* (which must keep running every turn; it feeds the Thinking Map
  and facilitator cues) from the *narrative* getting printed:
  - `ai_character_agent.gd::_finalize_turn_hidden_synthesis()` no longer
    calls `_workshop_session_record.post(message_text)`. Instead
    `_cache_session_record_synthesis()` writes
    `workshop_catalyst.session_record_latest_text` (the full narrative) and
    `workshop_catalyst.session_record_pulse` (a one-line summary) into
    `StoryState`, so the recall path doesn't depend on which of the app's
    several independently-instantiated `WorkshopCatalystSessionRecord`
    objects happens to be "the" one wired to the controller.
  - New `WorkshopSessionRecordPulse` (pure static helper, no
    autoload/Node dependencies, independently testable) formats the pulse
    from `map_candidates` category counts, e.g. `"Session Record: 2 causes,
    1 opportunity noted — type /synthesis for the full recap."`, or a
    no-new-claims message when the turn produced nothing.
  - New facilitator command `/synthesis` (`game_session_ai_flow_utils.gd`,
    dispatched alongside `/vote`/`/note`/`/decide`) posts the cached
    `session_record_latest_text` into the log on demand, matching the
    existing terse slash-command vocabulary rather than adding a toolbar
    button. A future button (fills/submits `/synthesis`) was deferred until
    after live-session testing shows whether one is actually needed.
  - The pulse is mirrored to a new `%SessionRecordPulseLabel` in the
    Workshop footer status bar (`workshop_catalyst_workspace_shell.tscn`,
    right-aligned in `SafetyBar/SafetyStatusRow`) via
    `workshop_workspace_controller.gd::set_session_record_pulse()`, called
    from `workshop_catalyst_controller.gd::_on_story_state_updated()` →
    `_refresh_session_record_pulse()` every time `StoryState` changes.
    Unlike the safety alert labels it stays visible by default (it's
    informational, not a warning).
  - Covered by new tests in `test_workshop_catalyst_stage5.gd`:
    `_test_session_record_pulse_helper()` (pulse formatting: mixed
    categories, singular/plural, empty/malformed input, unknown
    categories), `_test_synthesis_recall_command_wiring()` and
    `_test_session_record_status_bar_wiring()` (source-text checks, matching
    this file's existing convention of not instantiating
    `ai_character_agent.gd`/`game_session_ai_flow_utils.gd` directly in
    headless CLI tests), plus an extended
    `_test_finalization_seam_and_story_nonregression()`. Stage 5 and Stage 6
    regressions pass.
  - **Rollback**: restore the unconditional
    `_workshop_session_record.post(message_text)` call and drop the
    `/synthesis` handler; the cached `session_record_*` state keys and pulse
    label are additive and harmless to leave in place either way.
- **Panel clarification + How To preset (2026-08-03)**: facilitator questions
  surfaced that the right-rail "Session Record" panel (Stage 7's editable
  decisions/risks/proposals record) and the left-rail "Session shortcuts"
  card (the default state of the Plans/Progress contextual preview,
  `workshop_target_surfaces_controller.gd`) were both working as designed but
  undocumented — see the 2026-08-03 addition in ADR 0009 for the full
  explanation of what each displays and when. Also fixed a real gap: scenario
  `how_to_text` guidance had no live-session surface for Workshop Catalyst
  (only shown once, pre-session, in the mode-select popup) because
  `_move_existing_regions()` never reparents the legacy "How To" tab into the
  new dashboard shell. Added a sixth workspace preset, `PRESET_HOW_TO`
  (`HowToPresetButton`, next to Custom), that shows a new `HowToSurface`
  panel in `CenterSecondaryPane` — reusing the same take-over-the-workspace
  mechanism Review already uses — populated once at mount from
  `Global.get_current_scenario().how_to_text` via
  `WorkshopWorkspaceController.set_how_to_text()`. Read-only; no new
  persistence or model calls.
  - While making this change, `workshop_catalyst_controller.gd` and
    `workshop_workspace_controller.gd` both crossed the 900-line soft-warning
    ratchet. Split out `workshop_workspace_region_mount.gd` (one-time region
    reparenting, previously `_move_existing_regions`/`_find_input_actions_region`/
    `_normalize_reparented_region`) and `workshop_catalyst_controller_utils.gd`
    (stress-injection text extraction + session-id lookup) — both
    static/stateless, no behavior change, just relocated code. Both files are
    back under 900 lines; `python synesyn/utilities/checks/check_line_limits.py`
    confirms no hard violations and neither file in the soft-warning band.
  - Stage 4 and Stage 10 regressions pass (these instantiate the shell and
    assert every preset button/panel resolves).
- **How To content, and a spurious-timeout bug fix (2026-08-03)**: two
  facilitator reports from live use.
  - The new How To surface (above) was empty scaffolding. It now always shows
    an app-level "how to use Workshop Catalyst" guide — presets, all six
    slash commands (`/note`, `/decide`, `/risk`, `/defer`, `/vote`,
    `/synthesis`), and where each result surfaces (Thinking Map, Session
    Record, AI Assistant panel, status bar pulse) — sourced from
    `workshop_catalyst_how_to_text.gd` (a standalone constant, kept out of
    `workshop_workspace_controller.gd` to protect the line-limit ratchet). A
    scenario's own optional `how_to_text` is appended underneath, labelled
    "This scenario's guidance," instead of replacing the base guide.
  - **Bug**: a facilitator turn against a cloud model (e.g. Grok 4.5) could
    show `Narrator: The AI couldn't generate a response right now... Timed
    out waiting for an AI response...` in the story log, while the AI
    Assistant panel and Session Record still filled in moments later — the
    response wasn't actually missing. Root cause: `ai_character_agent.gd`
    runs its own in-scene watchdog timer (`_process()`, `_awaiting_response`/
    `_response_timer`) completely independent of the HTTP-layer timeout in
    `workshop_stateless_model_task.gd`. The 2026-08-02 fix gave cloud
    providers a 120s HTTP budget (`CLOUD_TIMEOUT_SECONDS`), but the watchdog
    still fired at the old default of 90s (`RESPONSE_TIMEOUT`) — reachable
    well before a legitimately-slow-but-successful response completes. The
    watchdog firing first posts the spurious Narrator error and bumps
    `_generation_id`, marking that turn stale; when the request *does*
    succeed shortly after, `_finalize_turn_hidden_synthesis()` still runs (it
    executes before the outer `my_gen != _generation_id` staleness check) and
    caches the narrative/pulse as normal — hence real output appearing in the
    panels despite the log already showing an error.
  - **Fix**: added `WORKSHOP_CLOUD_RESPONSE_TIMEOUT := 150.0` (120s + the same
    30s buffer already used for `OLLAMA_RESPONSE_TIMEOUT` above its own 180s
    HTTP budget) and made `_response_timeout_seconds()` apply it whenever
    `_get_runtime_profile_id() == HIDDEN_SYNTHESIS` and the model isn't
    Ollama. Story Catalyst's non-Ollama watchdog timeout (90s) is unchanged.
  - Covered by a new regression test,
    `_test_hidden_synthesis_watchdog_outlasts_cloud_timeout()`
    (`test_workshop_catalyst_stage5.gd`), which reads both constants via
    regex and asserts the watchdog stays above the HTTP timeout — so this
    can't silently drift back out of sync if either constant changes later.
  - **Rollback**: revert `RESPONSE_TIMEOUT`'s use in `_response_timeout_seconds()`
    to unconditional; the How To content change is independently safe to keep.
- **Thinking Map card/control clarity pass (2026-08-04)**: facilitator
  screenshot flagged the `ProvenanceLabel`/`StateLabel` pair on each card
  (`workshop_thinking_map_card.tscn`) rendering as two bare, unlabeled lines
  (e.g. "AI inferred" directly above "Suggested") with no indication of what
  either line meant or that they were two different concepts.
  - **Fix**: `workshop_thinking_map_controller.gd::_add_card()` now prefixes
    them ("Source: AI inferred" / "Status: Suggested"), and the tscn adds a
    thin `HSeparator` above the pair, a muted/smaller font for
    `ProvenanceLabel`, and a status-colored font for `StateLabel` (amber
    suggested, green accepted/edited, red rejected, purple deferred) via new
    `_source_class_tooltip()` / `_proposal_state_tooltip()` /
    `_proposal_state_color()` helpers, so status is scannable per-column at a
    glance, not just readable one card at a time.
  - Added hover tooltips explaining each source class and review state on
    both labels, plus on the card's Accept/Edit/Reject/Defer/Route/Closure
    buttons and their Graph-view equivalents (`MapGraphReview` row).
  - Reworded/added tooltips across `workshop_thinking_map.tscn`'s toolbar and
    footer: `ColumnsViewButton`, `GraphViewButton`, `MapContextToggle`
    (explicitly states it only affects future turns' prompt context and is
    reversible), `PreviewMapButton` (now also documents the toggle behavior
    below), `CommitMapButton`, `RetryMapCommitButton`, `RelationshipStatus`,
    `MapCommitStatus`, and the Semantic impact preview heading/text.
    `SymbolicInsightsLabel`'s tooltip was already dynamic (lists actual
    findings) and was left unchanged.
  - **Bug**: `PreviewMapButton` only ever opened `MapPreviewPanel`; pressing
    it again while already open just rebuilt the same preview instead of
    closing it, so facilitators had no way to dismiss the JSON panel short of
    switching presets.
  - **Fix**: split `show_preview()` (still public, still called directly by
    anything that wants to force a fresh preview open) from a new
    `_on_preview_button_pressed()` handler wired to the button, which closes
    `MapPreviewPanel` if already visible and otherwise calls `show_preview()`.
  - **Rollback**: each of the two changes (card labels/tooltips vs. preview
    toggle) is independently revertible; neither touches the adapter, the
    coordinator, or the commit/preview payload itself.

- 2026-08-04: Session Menu rename + resolved placeholder buttons.
  - **Rename**: the left-rail navigation panel (previously node
    `NavigationPanel`, visibility group `"navigation"`, Custom-panel toggle
    labelled "Menu") is now `SessionMenuPanel` / group `"session_menu"` /
    `SessionMenuToggle` labelled "Session Menu" — matches the panel's own
    internal identity instead of colliding with the app's hamburger (☰) menu.
    Touched: `workshop_workspace_preset_model.gd` (`GROUP_SESSION_MENU`, all
    preset visibility lists), `workshop_workspace_controller.gd`
    (`PANEL_NODE_IDS`/`TOGGLE_NODE_IDS`, all `_desired_visibility`/`_toggles`
    lookups), `workshop_layout_diagnostics.gd` (`TRACKED_CONTROL_IDS`),
    `workshop_catalyst_workspace_shell.tscn` (node + all descendant `parent=`
    paths), and `test_workshop_catalyst_stage4.gd` /
    `test_workshop_catalyst_stage10.gd`. Persisted layout configs with the old
    `"navigation"` key simply fall back to default (visible) for that one
    flag — not destructive, no migration needed.
  - **Scenarios button removed** (not rebuilt): the existing top-bar
    `ScenarioObjectiveBtn` toggle (shared with Story Catalyst, always present
    in `game_session.tscn`'s header) already shows the current scenario's
    objective/description in a popup. The Session Menu's `ScenariosButton`
    duplicated that with a dead "unavailable" stub, so it was deleted rather
    than given a second implementation.
  - **Insights button wired for real**: `InsightsButton.pressed` now calls a
    new `_on_insights_button_pressed()` in `workshop_workspace_controller.gd`,
    which flips the same right-rail collapse state as the Custom panel's
    `InsightsToggle` (reuses `_on_insights_toggled()`) and keeps that
    CheckButton's pressed state in sync so the two controls can't disagree.
  - **Settings button wired for real**: `SettingsButton.pressed` now calls a
    new `_on_settings_button_pressed()`, which finds the mounted
    `game_session.gd` instance via the existing `"game_session"` scene-tree
    group (same lookup pattern as
    `workshop_catalyst_controller_utils.gd::find_current_session_id()`) and
    calls its `_on_hamburger_menu_pressed()` — opening the same ☰ drawer that
    already hosts the live Workshop Catalyst settings (stage timer, Next
    Stage, notes, exports, Inject Stress, facilitator command reference).
    There was no separate Workshop settings surface to build.
  - **My Sessions left as an honest placeholder**: no session browser/history
    feature exists anywhere in the app to link to (only fragments: open the
    logs folder, load a raw story-log JSON). Still routed through
    `workshop_target_surfaces_controller.gd`'s
    `_on_unavailable_navigation_requested()`. Scoping a real browser
    (Hub-backed vs. local-file-backed, resume semantics) is tracked as a
    follow-up, not done here. **Superseded the same day** — see the "My
    Sessions: local-file browser + resume-live" entry below; the facilitator
    asked for it built out immediately rather than deferred.
  - **Discovered Godot 4.7.1-rc2 engine fragility (unrelated to the above,
    found while regression-testing it)**: removing `ScenariosButton` dropped
    `LeftRailContent`'s minimum height just enough that resizing
    `WorkshopWorkspaceShell` from 1024×576 to 1024×768 during
    `test_workshop_catalyst_stage4.gd`'s `_assert_bounded_viewport()` crashed
    the engine outright (signal 11) inside `await process_frame`, reproducibly.
    Root cause is inside Godot's own `ScrollContainer`/`VBoxContainer` resize
    layout pass at that specific content-height/viewport-height boundary —
    nothing in Workshop Catalyst's own code is doing anything wrong, and no
    error is logged before the crash. Restoring the lost height with a plain
    `Control` spacer (`LeftRailStabilitySpacer`, `custom_minimum_size =
    Vector2(0, 32)`, tooltipped with this explanation) makes the crash
    disappear; confirmed the fix is about total height, not node type/count,
    by reproducing with a spacer alone. **Do not remove this spacer** without
    re-running `test_workshop_catalyst_stage4.gd` at 1024×768 first — the rail
    is one edit away from tripping this again in either direction.
  - **Verification**: `test_workshop_catalyst_stage4.gd` and
    `test_workshop_catalyst_stage10.gd` pass; `test_workshop_catalyst_stage5.gd`
    spot-checked as unaffected (pre-existing, unrelated `current_narrative_phase`
    script error still logs but the suite still reports all passed).
  - **Rollback**: the rename is mechanical and file-scoped (revert the 6
    touched files together, since `.tscn` and `.gd` must agree on the group
    id/node names). The button wiring/removal changes are independent of the
    rename and of each other.

- **My Sessions: local-file browser + resume-live (2026-08-04)**: built out
  the placeholder noted above the same day, per facilitator request. Backend
  is local files (no Hub route); action is resume-live (reload the session
  into the already-running Workshop Catalyst UI, not just re-open the raw
  transcript). This reuses, rather than duplicates, the existing hamburger
  ☰ → "Load Story Log" file-picker path (`GameSessionStoryLogUtils
  .apply_story_log_from_json`), which already rebinds file identity and loads
  the `.workshop.json` sidecar into `StoryState.workshop_catalyst` — the gap
  was that nothing then told the live Thinking Map / Session Record / Compare
  Paths controllers to re-render from that freshly loaded state.
  - **Reload/remount path**: new `WorkshopCatalystController.reload_from_loaded_state()`
    re-initializes the Session Record store, Thinking Map adapter, and Compare
    Paths store from `StoryState.workshop_catalyst` and calls each panel's
    existing `refresh()` — never `mount()` again, since re-mounting would
    duplicate button signal connections. The ~40-line body lives in a new
    static helper, `workshop_catalyst_controller_utils.gd
    ::reload_workshop_panels_from_state()`, to keep the controller under the
    900-line soft limit (confirmed safe to reuse for this because
    `ThinkingMapAdapter.initialize()`, `WorkshopSessionRecordStore.initialize()`,
    and their panel controllers' `refresh()` were all already idempotent
    re-render paths, not one-shot setup).
  - **Wiring**: `game_session_storylog_utils.gd::apply_story_log_from_json()`
    now calls `WorkshopCatalystController.reload_from_loaded_state()` after
    loading a `.workshop.json` sidecar, so both the hamburger-menu Load Story
    Log path and the new My Sessions path converge on the same reload.
  - **Local session scanner**: new `WorkshopSessionScanner` (pure
    `RefCounted`, no autoload dependency) reads every `*.provenance.json` in
    the story-log directory, filters to Workshop Catalyst sessions (via the
    provenance's new `session_type` field, added to `story_log_system.gd`'s
    save path; falls back to `.workshop.json` sidecar presence for sessions
    saved before that field existed), and sorts most-recent-first. Each entry
    surfaces scenario, saved-at, decision/open-question counts, and last
    stage name for the list label.
  - **UI**: `MySessionsButton` (previously routed to the generic
    "unavailable" dialog) now opens a new `MySessionsDialog` `Window` in
    `workshop_catalyst_workspace_shell.tscn`, populated from the scanner via a
    dedicated `workshop_my_session_list_item.tscn` button template (kept as a
    scene rather than `Button.new()` to satisfy the existing Stage 10
    UI-authoring test). Selecting an entry hides the dialog and calls the
    mounted `game_session` node's existing `_on_story_log_file_selected()` —
    the exact same call the hamburger Load Story Log picker makes — so there
    is exactly one code path that actually loads a session.
  - **Tests**: `test_workshop_catalyst_stage11.gd` covers the Session Record
    reload rehydration, the scanner's filtering/sorting/legacy fallback, the
    My Sessions button opening the real dialog (not the unavailable stub),
    the close button, and selection dispatching to `game_session`. The
    Thinking Map half of the reload path is covered separately in
    `test_workshop_catalyst_stage11b.gd`, split out because preloading
    `workshop_thinking_map_controller.gd` alongside the other Stage 11
    fixtures reproduces the pre-existing `ThemeManager` headless-compile
    flake (documented above under the relations/graph-view entry); isolating
    it lets the rest of Stage 11 run reliably. Both pass headlessly
    (`test_workshop_catalyst_stage11.gd`: "all passed"; `stage11b`: "all
    passed" whenever the environment flake doesn't trigger the compile
    error — reproduced identically against the unmodified `stage8` test, so
    it is confirmed pre-existing and unrelated to this change).
  - **Line limits**: `workshop_catalyst_controller.gd` is 820 lines,
    `workshop_workspace_controller.gd` 770, new
    `workshop_catalyst_controller_utils.gd` 97, new
    `workshop_session_scanner.gd` 131, `workshop_target_surfaces_controller.gd`
    170. `check_line_limits.py` reports no hard violations.
  - **Rollback**: remove `MySessionsDialog`/list-item scene and revert
    `workshop_target_surfaces_controller.gd`'s My Sessions wiring to restore
    the "unavailable" stub. `reload_from_loaded_state()` and the scanner are
    additive and harmless to leave in place independently — Load Story Log
    from the hamburger menu already depended on the same reload call once
    added, so removing only the My Sessions UI does not regress that path.

- **Multi-instance identity + workshop state sync (2026-08-05, ADR 0013)**:
  first slice of local multi-instance Workshop Catalyst. Reuses Story
  Catalyst's ENet transport (`Network`, port 28960); does **not** reuse the
  character-pool lobby.
  - **Presence store** (`workshop_presence_store.gd`): claim-until-taken
    facilitator, register participant, rename, disconnect clears claim and
    reopens need-facilitator. Facilitator display form: `Name (Facilitator)`.
  - **Presence sync** (`workshop_presence_sync.gd`): Node child of `Network`
    with host-authoritative RPCs (`rpc_request_claim` / `register` / `rename`,
    `rpc_sync_presence`). Inactive for Story Catalyst and single-player WC.
  - **UI** (`NeedFacilitatorDialog` in workspace shell +
    `workshop_presence_controller.gd`): non-dismissable while no facilitator;
    Become Facilitator / Join as Participant / Rename. Invite dialog copy
    updated to explain the local Multiplayer join path (still no email /
    outbound).
  - **Identity**: single-player still auto-applies Facilitator;
    multiplayer WC starts as temporary Participant until claim/name dialog
    resolves (`main_menu.gd`, `game_session_startup_utils.gd`,
    `facilitator_session_setup.gd`).
  - **Gates**: Next Stage, Inject Stress, End & Save, map/record/paths
    commits require local facilitator claim when presence is active.
  - **State sync**: host `_set_ws` broadcasts `sync_story_state`; clients
    rehydrate Thinking Map / Session Record / Compare Paths when the
    `workshop_catalyst` fingerprint changes.
  - **Tests**: `test_workshop_catalyst_stage12_presence.gd` (store + dialog
    nodes + identity helpers). Stage 10 Invite assertion updated for new copy.
  - **Still manual / follow-up**: live two-instance ENet smoke; Hub-remote
    Invite; participant chat when host AI is generating; polish Participants
    chips beyond the status labels.
  - **Rollback**: deactivate `WorkshopPresenceSync` and remove dialog /
    presence controller mount; single-player `apply()` path is unchanged.

---

## Cross-cutting: contract seam register (keep both sides + spec in lockstep)
| Artifact / route | Introduced in | Contract doc to update |
|---|---|---|
| Transcript segment + correction | S6 | `LatentSubstrate_Data_Model.md` |
| Workshop summary commit (`ui.workshop_summary` v1; implemented) | S7 | `LatentSubstrate_Data_Model.md`, `Synesyn_Hub_API_Spec.md` |
| `ui.workshop_thinking_map` v1 item + snapshot using shared graph primitives (implemented; generic route + Hub validator) | S8 | `LatentSubstrate_Data_Model.md`; `Synesyn_Hub_API_Spec.md`; shared Graph Workspace contract/ADR |
| Path object + selection closure (`ui.workshop_path_set` v1; implemented) | S9 | `LatentSubstrate_Data_Model.md`, closure/`ui.closure`, `Synesyn_Hub_API_Spec.md` |
| Specialist-contribution trace (`json.workshop_specialist_trace` v1; implemented, generic route + Hub validator) | S5 | `LatentSubstrate_Data_Model.md`, `Synesyn_Hub_API_Spec.md` |
| Participant + Plans/Progress target UI (presentation-only; no payload or route) | S10 | No Hub/API contract change; remote session sync remains deferred |

## Verification spine (run at each stage boundary)
- [x] `test_harness.py` WC smoke + multiturn; the S5 single-sender assertions
  remain active and passed through Stage 10.
- [x] `check_line_limits.py --check-baseline` (especially around S3, S5).
- [x] Hub tests (`run-hub-tests`) whenever Python/Hub changes (S6–S9 contract
  work). Recorded stage evidence rises from 29 tests at S6 to 47 tests at S9;
  Stage 10 changes no Python, Hub payload, or route.
- [x] Final Stage 0–10 automated integration sweep (2026-07-11): 12 focused
  Godot scripts passed (registry, Facilitator entry, Stages 3–10, shared Graph
  Workspace document, and adapter conformance); 50/50 Hub tests and 6/6 harness
  Python tests passed; all 6 executable behavior specs passed. WC smoke logged 3
  entries; WC multiturn logged 7 with exactly one visible non-human sender
  (`Session Record`) and exactly 3 Session Record responses; STT logged 3 with
  exactly 1 Session Record response. Story sustainability smoke logged 4,
  cultural smoke logged 4, and sustainability multiturn logged 8 with visible
  ensemble senders ELSA, SAIA, and SIMS. All specs reported no unexpected
  errors. The line-limit ratchet passed across 653 scanned scripts. The final
  contract pass added the missing `json.workshop_specialist_trace` Hub validator
  and its 3 passing tests, bringing all five documented Workshop artifact types
  under matching generic-seam validation.
- [ ] Complete the canonical
  [manual acceptance checklist](../../user-guide/workshop-catalyst-facilitator-manual.md#manual-acceptance-checklist)
  for pre-session selection, visual/projector layouts, keyboard focus,
  microphone/audio hardware, proposal review, and real-session operations.
- [ ] Full regression sweep: every visible control resolves (no dead ends).
  Stage 4 proves shell-button binding and Stage 10 exhaustively proves the new
  target surfaces; dynamic proposal/map/path controls and hardware-dependent
  states still require the manual sweep above.

The automated verification spine is complete. The implementation is ready for
manual acceptance; it is not production-certified until the two open manual
items above are witnessed on target hardware.

## Global rollback posture
Each stage is a discrete, revertible commit behind a flag or profile where behaviour changes (S5 profile, S6/S7 feature flags, S8/S9 additive panels). Story Catalyst must remain a provable safe-harbour throughout: if any WC stage regresses, Story Catalyst continues on the unchanged visible-ensemble path.

---

## Open decisions to resolve as stages are reached (from doc 10 §I)
- [x] Specialist Functions: four stable controlled functions; no named personas.
- [x] Specialists do not vote; visible participant/facilitator `/vote` and `/decide` remain authoritative.
- [x] Batched prompt requests independent role summaries; no sequential cross-specialist calls.
- [x] Specialist summaries/provenance/status remain behind the collapsed-by-default "Show reasoning/analysis" control.

*Living plan. Update as stages complete; move frozen stages to `../completed/` once verified.*
