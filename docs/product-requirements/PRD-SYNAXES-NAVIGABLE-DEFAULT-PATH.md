---
id: PRD-SYNAXES-NAVIGABLE-DEFAULT-PATH
title: SynAxes navigable default path (latent reality → holds)
status: review
version: "0.2"
owner: SynAxes / product
last_reviewed: 2026-08-07
primary_users: ["facilitator", "curator", "researcher", "godot_developer"]
supersedes: null
---

# SynAxes navigable default path (latent reality → holds)

## Problem and outcome

SynAxes already supports import → discover → Dream Inbox → commit, but the Tools
UI exposes ML/control chrome as the front door. Regular users cannot complete
practical jobs without absorbing discovery methods, embedding tiers, and Hub jobs.

**Outcome:** Opening SynAxes (Synesyn Tools or editor plugin) feels like entering
a navigable field of your material and leaving with human-owned closures. Power
controls remain available under Advanced. Occasion-specific journeys stay in the
application layer (ScenSyn / Workshop), which may call SynAxes rather than
re-skin the whole dock.

**Sell line:** Walk your material as a space and leave with a few closures you
can stand behind.

## Users and jobs

- **Facilitator / curator:** When they have published sources or session residue,
  they need a short Import → Explore → Choose → Name → Commit path so they can
  leave with named themes and optional Closure Map coverage.
- **Researcher / power user:** When tuning analysis, they need Advanced controls
  (method, dim-reduction, Hub jobs, embedding tier) without forcing those on
  everyone.
- **Godot developer (addon only):** When they enable the plugin, they need a clear
  expectation: pattern dock + local demos; full substrate loop when Hub/SynTree
  are present — not an NPC brain.

## Success measures

- A new user completes demo → discover → commit (or defer) without opening Advanced.
- After discover, Pattern Overview is the default attention surface; 3D remains
  available as Explore.
- Coverage is visible once Saved Closures exist; Orientation labels are plain-language.
- Tools tooltip / empty state / user-guide one-pager use the sell line.
- At least one application-layer entry (“propose themes from this session”) can
  invoke SynAxes without the user configuring PCA.
- SynAxes, SynTree, Metapunkt and SynPunkt each load in a clean Godot project
  beside `synesyn_core` alone, so the addon claim in the README is true.
- No user text reaches a third-party embedding provider without a disclosed,
  remembered opt-in.

## Scope

### In scope (this plan)

- Phase 0: `synesyn_core` shared library addon; restore drop-in addon boundaries
  (ADR 0017)
- Phase A: Default-path UI (Advanced collapse, spine, empty states, Overview-first)
- Phase B: Smarter defaults and post-commit hand-off
- Phase C: Copy / docs / packaging honesty
- Phase D: Application hook + Metapunkt API extensions
- Phase E: Reload last analysis
- Phase F: Headless discovery (completes the callable pipeline begun in D)

### Out of scope

- Full Proxistance temporal scrubber / tetrahedral edge UI (ADR 0015 later)
- Nightly “dreaming” into Dream Inbox (existing later item)
- Replacing SynAxes with a Workshop Catalyst theme
- Hard-depending Open Closure `ClosureRouter` in the hub (ADR 0016 stands)

## Critical journey (default)

1. Open Tools → SynAxes (or editor SynAxes main screen).
2. See sell line + step spine; Import (latest context graph CTA or demo).
3. Discover with defaults (no Advanced).
4. Review Pattern Overview; select a theme → Closure Editor.
5. Name, intent, optional Orientation → Commit.
6. See Coverage update; optional “Open in SynPunkt”.

## Requirements

### Phase 0 — Shared core and drop-in addon boundaries

SynAxes, SynTree, Metapunkt and SynPunkt must each remain a drop-in addon while
sharing resources. None of them is today: every one reaches into host paths
(`res://addons/synesyn_core/scripts/hub_substrate_client.gd` is preloaded by 9 addon files across
four addons; `RuntimeConfig` is a `class_name` in `res://scripts/`;
`ThemeManager` is an autoload pointing into `res://ScenSyn/`). A missing preload
target is a hard compile failure in a clean project, so the current addons do not
merely degrade — they fail to load.

- **REQ-NDP-018:** A library addon `addons/synesyn_core/` (no dock, no scenes)
  owns `runtime_config.gd`, `theme_manager.gd`, `hub_substrate_client.gd`, and
  registers the `ThemeManager` autoload from its own `plugin.gd`
  (`add_autoload_singleton`, mirroring SynTree's `NotificationManager` /
  `ContentBus`). The manual `ThemeManager=` entry leaves `project.godot`, and
  `synesyn_core/plugin.cfg` is listed first in `editor_plugins/enabled` because
  plugin-registered autoloads need an editor restart.
- **REQ-NDP-019:** No script under `addons/**` references `res://scripts/**` or
  `res://ScenSyn/**`. All shared services resolve through `synesyn_core`.
  Migration surface: ~32 path references across ~30 files (17 for the hub client,
  15 for RuntimeConfig, 1 autoload entry).
- **REQ-NDP-020:** Verified drop-in: `synesyn_core` plus any one of SynAxes,
  SynTree, Metapunkt or SynPunkt parses and enables in a clean Godot project.
  Checked headlessly, not by inspection.

### Phase A — Default-path UI

- **REQ-NDP-001:** Left panel shows Sources + Import + theme-count control +
  Discover/Clear by default; discovery method, dim-reduction, Hub jobs, embedding
  tier, and cache stats live under a collapsed **Advanced** section (scene nodes;
  RuntimeConfig remembers open/closed).
- **REQ-NDP-002:** Persistent step spine label:
  `Import → Explore → Choose → Name → Commit` (updates emphasis by state).
- **REQ-NDP-003:** Empty / first-run status uses the sell line and CTAs
  (Import demo / publish context graph guidance).
- **REQ-NDP-004:** After successful discover, bottom tabs switch to **Pattern
  Overview** by default.
- **REQ-NDP-005:** Dream Inbox primary control is **Work on this** (select +
  populate editor); Defer/Reject remain secondary.
- **REQ-NDP-021:** A single `synaxes_ui_binder.gd` resolves the node set once and
  returns the refs dictionary both wiring paths already speak; `plugin.gd`
  (editor main screen) and `synaxes_runtime_controller.gd` (Synesyn Tools) both
  consume it. Phase A/B behaviour must not be implemented twice. Reparenting is
  safe: both paths already bind via `find_child(name, true, false)`.
- **REQ-NDP-022:** Before adding Phase A/B state, extract discovery/analysis
  orchestration out of `synaxes_runtime_controller.gd` into a `RefCounted`
  controller with injected optional UI, following the pattern
  `synaxes_closure_controller.gd` already uses. This is a precondition, not a
  contingency — the file is at 960 lines against a 900-line soft limit — and it
  is the same seam Phase F depends on.

### Phase B — Defaults and completion

- **REQ-NDP-006:** When an embed-capable SynTree model is active, surface a
  one-click **disclosed** opt-in that names the destination (“Use model themes —
  sends item text to <provider>”), and remember the answer per provider in
  RuntimeConfig. Tier 3 must **not** auto-enable: `_try_tier3_model_embeddings`
  POSTs the full text of every imported item to a third-party endpoint and spends
  the user's API credit, so the `UseHubEmbeddings` checkbox is currently the
  consent gate. Silently flipping it would contradict the Human Agency UX
  Contract and the provenance stance of ADR 0016. Default remains Tier 2, labelled
  in plain words (“Local themes” vs “Model themes”). Capability detection is free:
  `loader.supports_embeddings()` is already checked before any request is made.
- **REQ-NDP-007:** One-click or prominent **Import latest Hub context graph** when
  any `ui.context_graph` exists (skip picker when count == 1; else picker).
- **REQ-NDP-008:** After commit, offer next actions: commit another, or open
  SynPunkt Closures. This is a real control, not fallback copy — the Tools shell
  has an addressable `TabContainer` (`synesyn_tools.gd` holds
  `_TABS_PATH := "OuterMargin/VBox/TabsCard/Tabs"` and already manipulates it).
  SynAxes emits a navigation signal that the host shell wires; the addon must not
  reach up into the host scene tree (see REQ-NDP-019).
- **REQ-NDP-009:** Orientation OptionButton and Coverage legend use plain-language
  subtitles (Distal Past = remote/public history, etc.) without removing A–D codes.
- **REQ-NDP-010:** Post-discover status summarises in human words:
  `N themes from M items · themes: local|model`.

### Phase C — Positioning and docs

- **REQ-NDP-011:** Synesyn Tools tooltip / SynAxes tab intro copy matches sell line.
- **REQ-NDP-012:** User-guide one-pager for default path only; Advanced appendix;
  update `facilitator-workflow.md` SynAxes stages to match.
- **REQ-NDP-013:** Addon README splits Synesyn Tools user vs Godot developer;
  editor plugin expectations documented. The drop-in story is written only after
  Phase 0 makes it true (`synesyn_core` + SynAxes in a clean project), and states
  the `synesyn_core` dependency plainly.
- **REQ-NDP-014:** Refresh technical-review / platform-architecture “4D canvas”
  wording to ADR 0015 (Proxistance / orientation); fix stale claims in
  `05_SynAxes.md` header (“not yet wired to substrate”). **Delivered in Phase A**
  — these are false statements standing today, and correcting them is minutes of
  work that should not wait for the docs phase.

### Phase D — Application layer hook

- **REQ-NDP-015:** Metapunkt SynAxes interface supports `discover_patterns`
  (existing), `get_dream_candidates`, and `commit_closure`. The closure half needs
  no refactor: `synaxes_closure_controller.gd` is already `extends RefCounted`
  with UI injected via `bind_ui`, and every widget read already falls back to the
  candidate dictionary, so it commits correctly with no UI bound. Three additions
  suffice — an optional `overrides: Dictionary` on `commit_closure`, a
  `select_candidate(idx)` that does not depend on an ItemList selection, and a
  candidates accessor.
- **REQ-NDP-025:** Delete `addons/metapunkt/scripts/interfaces/synaxes_interface.gd`.
  It has zero references; `synesyn_client/addons/metapunkt/Integrations/SynaxesInterface.gd` is the copy preloaded
  and registered in `ToolRegistry.gd`. Do this first so nobody edits the dead one.
- **REQ-NDP-016:** One ScenSyn or Workshop Catalyst entry point that proposes
  themes from current/last session data. In this phase it opens SynAxes with
  session data preloaded and discovery queued — it does **not** attempt headless
  discovery, which is Phase F. Minimal vertical slice acceptable.

### Phase E — Reload last analysis

- **REQ-NDP-017:** Reload last analysis run (projection/cluster artifacts) into
  Pattern Space without full re-import when artifacts exist on Hub.

### Phase F — Headless discovery

Completes the callable pipeline. Deferred rather than dropped: candidates come
from `build_dream_inbox_from_patterns(patterns)`, and patterns come from a
discovery pipeline currently interleaved with the dock's `_data`,
`_apply_embeddings` and viewer updates. REQ-NDP-022 extracts that seam for
line-limit reasons anyway, which is what makes this phase an increment rather
than a rewrite.

- **REQ-NDP-024:** Import → embed → discover is callable without the dock, via
  the Phase A analysis controller with no UI bound, so an application can obtain
  candidates without opening SynAxes. Tier 3 remains gated by REQ-NDP-006 consent;
  a headless caller with no recorded consent runs Tier 2.

## Acceptance

| IDs | Method |
| --- | --- |
| REQ-NDP-018–020 | Headless parse/enable of `synesyn_core` + each addon in a clean project; `rg` shows no `res://scripts/**` or `res://ScenSyn/**` under `addons/**` |
| REQ-NDP-001–005, 021–022 | Cold-start script (below) on both wiring paths: Synesyn Tools and editor main screen; line-limit ratchet passes |
| REQ-NDP-006–010 | Manual with/without embed model; confirm no network egress until consent is given |
| REQ-NDP-011–014 | Doc review |
| REQ-NDP-015–016, 025 | Manual + Metapunkt console op; commit with no UI bound |
| REQ-NDP-017 | Manual when Hub has prior analysis artifacts (`Reload last analysis` near Discover) |
| REQ-NDP-024 | `addons/synaxes/tests/test_headless_discover.gd` (headless SceneTree); Metapunkt `discover_patterns` |

**Cold-start script.** There is no telemetry, so the Phase A/B success measures
are otherwise self-assessed by whoever built them. Write the default path as a
numbered walkthrough and have one named person who did not write the code run it
once before Phase A and once after, recording where they stall. A weak instrument,
but an honest one.

Harness: not required for UI-first phases; add a run spec once REQ-NDP-024 makes a
session→propose-themes path automatable.

## Constraints and dependencies

- Scene-over-code: layout changes in `synaxes_main.tscn`; scripts only for
  dynamic behaviour and RuntimeConfig.
- GDScript naming / typing rules (`.cursorrules`).
- ADR 0015 (Closure Map / Proxistance framing); ADR 0016 (admissibility stays Advanced/status).
- Human Agency UX Contract: commit remains explicit; no silent overwrite; no
  network egress of user text without disclosed consent (REQ-NDP-006).
- `synaxes_runtime_controller.gd` is already at 960 lines against a 900-line soft
  limit, so REQ-NDP-022's extraction gates Phase A rather than following it.
  (`pattern_viewer.gd` is at 934 and out of scope here, but on the same ratchet.)
- Extraction seam is fixed by convention: `RefCounted` with injected optional UI,
  as `synaxes_closure_controller.gd` already does. The line limit, wiring parity
  (REQ-NDP-021) and headless discovery (REQ-NDP-024) are the same problem; solving
  them with one seam is the point.

## Open questions and risks

- Workshop vs Story Catalyst for REQ-NDP-016: prefer Workshop Catalyst if session
  residue is the corpus; otherwise ScenSyn session import path.
- Theme-count UX: keep numeric slider in Advanced; default path may use a simple
  OptionButton (Fewer / Default / Finer) mapped to k — decide in Phase A implementation.
- Phase 0 rewrites ~32 path references across ~30 files in five addons and the
  host. Mechanical, but the blast radius is the whole project rather than SynAxes;
  land it on its own and verify with a headless parse before starting Phase A.
- `synesyn_core` boundary recorded as ADR 0017.

## Evidence map

- Concept: [`../concepts/closure-map.md`](../concepts/closure-map.md)
- ADRs: 0015, 0016
- Orientation PRD: [`PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md`](PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md)
- Tracker: [`../implementation_tracking/active/05_SynAxes.md`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/active/05_SynAxes.md)
- Addon: `synesyn_client/addons/synaxes/`
- Tools shell: `ScenSyn/scenes/synesyn_tools.tscn`, `ScenSyn/scripts/synesyn_tools.gd`

---

## Implementation plan (engineering)

### Phase 0 — `synesyn_core` and drop-in boundaries (estimate: 1–2 days)

**Files**

- New `addons/synesyn_core/` — `plugin.cfg`, `plugin.gd`, `scripts/`
- Moved: `synesyn_client/addons/synesyn_core/scripts/runtime_config.gd`, `synesyn_client/addons/synesyn_core/scripts/hub_substrate_client.gd`,
  `synesyn_client/addons/synesyn_core/scripts/theme_manager.gd`
- `project.godot` — drop manual `ThemeManager=` autoload; put
  `synesyn_core/plugin.cfg` first in `editor_plugins/enabled`
- ~30 files carrying `res://scripts/**` / `res://ScenSyn/**` preloads

**Tasks**

1. Create the library addon (no dock, no scenes); move the three shared scripts.
2. Register `ThemeManager` from `synesyn_core/plugin.gd` via
   `add_autoload_singleton`. `class_name RuntimeConfig` needs no registration —
   Godot resolves script classes from file presence, plugin enabled or not.
3. Rewrite preload paths across addons and host (17 hub client, 15 RuntimeConfig).
4. SynAxes' own five sites: two `HubSubstrateClient` preloads, three
   `RuntimeConfig` calls, two `ThemeManager` references.
5. Headless parse of the full project; then of a clean project containing only
   `synesyn_core` + one addon, for each of the four.

**Exit:** No `addons/**` script references host paths; each addon loads standalone
beside `synesyn_core`.

### Phase A — Default-path UI (estimate: 2–3 days)

**Files**

- New `addons/synaxes/scripts/runtime/synaxes_ui_binder.gd` — single node resolver
- New `addons/synaxes/scripts/runtime/synaxes_analysis_controller.gd` — `RefCounted`,
  discovery orchestration extracted from the runtime controller
- `addons/synaxes/scenes/synaxes_main.tscn` — Advanced container; spine label;
  Work on this button; reorder visibility
- `addons/synaxes/scripts/runtime/synaxes_runtime_controller.gd` — Advanced toggle
  persistence; step-spine state; Overview tab after discover
- `addons/synaxes/scripts/plugin.gd` — consume the binder instead of its own
  `find_child` block
- `addons/synaxes/scripts/runtime/synaxes_closure_controller.gd` — Work on this =
  select + editor populate (may alias existing selection)

**Tasks**

0. **Precondition (REQ-NDP-022 / 021):** extract the analysis controller and the
   shared binder before adding UI state. Both wiring paths bind through the binder
   from here on, so Phase A/B behaviour is written once.
1. Wrap Options controls (method, dim-reduction, Hub jobs, embeddings, cache) in
   `AdvancedPanel` (`VBox` + toggle button `AdvancedToggle`, default collapsed).
   Safe for both paths — binding is `find_child(name, true, false)`, not fixed paths.
2. Keep outside Advanced: Sources, Refresh/Import, Clusters (or Fewer/Default/Finer),
   Discover, Clear.
3. Add `StepSpineLabel` under logo/status row; update text/emphasis from runtime
   state machine: `idle | imported | discovered | editing | committed`.
4. On `_on_discover` success → `bottom_tabs.current_tab` = Pattern Overview index.
5. Add `WorkOnThisButton` in Dream Inbox button row; wire to select active /
   `on_dream_candidate_selected`.
6. Persist `apps.synaxes.advanced_open` via RuntimeConfig.
7. Pull REQ-NDP-014 forward from Phase C: the “not yet wired to substrate” header
   and the “4D canvas” wording are false statements today; correcting them is
   ~20 minutes and should not wait three phases.

**Exit:** Cold-start demo path works with Advanced closed, identically on the
Tools path and the editor main screen; line-limit ratchet passes.

### Phase B — Defaults and completion (estimate: 1 day)

**Files**

- `synaxes_runtime_controller.gd` / `synaxes_import_controller.gd`
- `synaxes_closure_controller.gd` (orientation tooltips / coverage legend)
- `synaxes_main.tscn` (CTA button, legend label)

**Tasks**

1. Disclosed opt-in for model embeddings when SynTree reports an embed-capable
   model: name the provider in the prompt, remember per provider in RuntimeConfig,
   default stays Tier 2. Status in plain language.
2. `ImportLatestContextGraphButton` or Import smart-default when Hub graphs exist.
3. Post-commit status string with SynPunkt hand-off guidance.
4. Orientation/Coverage copy pass (tooltips + CoverageLabel legend).
5. Human discover summary line (REQ-NDP-010).

**Exit:** Latest-graph import + commit shows Coverage and next-step copy.

### Phase C — Docs and packaging (estimate: 0.5–1 day)

**Files**

- `addons/synaxes/README.md`
- `docs/user-guide/facilitator-workflow.md`
- New short `docs/user-guide/synaxes.md` (default path)
- `docs/user-guide/README.md` link
- `ScenSyn/scripts/synesyn_tools.gd` tooltip string
- `docs/technical-review/run_specs/README.md` (+ checklist 4D note)
- `docs/implementation_docs/Synesyn_Platform_Technical_Architecture.md`
  SynAxes 4D sentence → ADR 0015
- `implementation_tracking/active/05_SynAxes.md` Phase NDP section
  (header correction already landed in Phase A)

**Exit:** Docs/tooltips match the sell; drop-in claim is true because Phase 0 made
it true.

### Phase D — App hook (estimate: 1–2 days)

**Files**

- `addons/metapunkt/Integrations/SynaxesInterface.gd` (the live copy)
- Delete `addons/metapunkt/scripts/interfaces/synaxes_interface.gd` (unreferenced)
- `addons/synaxes/scripts/runtime/synaxes_closure_controller.gd` — headless args
- Minimal Workshop or ScenSyn caller (prefer smallest existing facilitator action
  surface)

**Tasks**

1. Delete the dead interface duplicate first.
2. Closure controller: optional `overrides: Dictionary` on `commit_closure`,
   `select_candidate(idx)`, candidates accessor. No structural change needed —
   it is already `RefCounted` with state fallbacks behind every widget read.
3. Extend SynAxes interface: list/get candidates; commit closure with name/intent/
   orientation/item_ids (Hub required).
4. Add one UI entry: Workshop “Propose themes” that opens SynAxes with session data
   preloaded and discovery queued, then focuses the Closures tab.
5. Manual acceptance note in facilitator manual.

**Exit:** Facilitator can trigger theme proposals without opening Advanced;
candidates can be listed and committed without a dock instance.

### Phase E — Reload last analysis (estimate: 1 day)

**Files**

- `synaxes_hub_pipeline.gd` / import controller — query last `json.analysis_run` +
  projection/cluster artifacts and hydrate viewer

**Exit:** “Reload last analysis” restores Pattern Space from Hub artifacts.

### Phase F — Headless discovery (estimate: 1–2 days)

**Files**

- `synaxes_analysis_controller.gd` (from Phase A) — run import → embed → discover
  with no UI bound; emit progress/status as signals rather than label writes
- `addons/metapunkt/Integrations/SynaxesInterface.gd` — `discover_patterns` becomes
  genuinely headless

**Tasks**

1. Remove residual viewer/label assumptions from the extracted analysis path;
   guard every UI reference the way `bind_ui` consumers already do.
2. Honour REQ-NDP-006 consent state headlessly: no recorded consent → Tier 2.
3. Add a harness run spec for session → propose themes.

**Exit:** An application obtains candidates without SynAxes being opened.

---

## Suggested delivery order

```text
0 (shared core) → A (extraction + UI spine) → B (defaults/hand-off) → C (docs)
  → D (app hook) → E (reload) → F (headless discovery)
```

Phase 0 lands first and alone: it touches every addon, changes nothing the user
sees, and establishes where shared code lives before Phases A–F create new shared
seams. Ship A+B+C as the tranche that makes the sell honest in Tools. Ship D when
a pilot facilitator journey needs it, E when users complain about re-running
discovery, and F when an application needs candidates without the dock.

## Tracker checklist (mirror into 05_SynAxes.md §I)

- [x] REQ-NDP-018 `synesyn_core` library addon + ThemeManager autoload (Phase 0)
- [x] REQ-NDP-019 No `res://scripts/**` or `res://ScenSyn/**` refs under `addons/**` (Phase 0)
- [x] REQ-NDP-020 Verified drop-in for all four addons (Phase 0) — SynTree residual: own `ContentBus` autoload
- [x] REQ-NDP-022 Analysis controller extraction (Phase A precondition)
- [x] REQ-NDP-021 Single UI binder for both wiring paths (Phase A precondition)
- [x] REQ-NDP-001 Advanced collapse + RuntimeConfig
- [x] REQ-NDP-002 Step spine
- [x] REQ-NDP-003 Empty / sell-line CTA
- [x] REQ-NDP-004 Overview-first after discover
- [x] REQ-NDP-005 Work on this
- [x] REQ-NDP-014 Architecture / review / to-do refresh (pulled into Phase A)
- [x] REQ-NDP-006 Disclosed model-embedding opt-in + plain status
- [x] REQ-NDP-007 Import latest context graph CTA
- [x] REQ-NDP-008 Post-commit next actions + host navigation signal
- [x] REQ-NDP-009 Orientation/Coverage plain language
- [x] REQ-NDP-010 Human discover summary
- [x] REQ-NDP-011 Tools copy
- [x] REQ-NDP-012 User-guide one-pager + facilitator workflow
- [x] REQ-NDP-013 README audience split + drop-in story
- [x] REQ-NDP-025 Delete dead Metapunkt interface duplicate
- [x] REQ-NDP-015 Metapunkt API extensions (headless commit args)
- [x] REQ-NDP-016 App entry propose-themes slice (dock-preloaded)
- [x] REQ-NDP-017 Reload last analysis
- [x] REQ-NDP-024 Headless discovery (Phase F)
