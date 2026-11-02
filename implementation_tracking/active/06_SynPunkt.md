# To‑Do — SynPunkt (Presentation + generation surface: SynDeck v2 + Story Stage + render orchestration)

**Primary spec references**
- `../Synesyn_Platform_Technical_Architecture.md` (SynPunkt is the canvas; Comfy is a bridge)
- `../LatentSubstrate_Data_Model.md` (entities/relations/projections/closures)
- `../Synesyn_Hub_API_Spec.md` (events + substrate CRUD; optional render-submit)
- `../Local_Deployment_Runbook.md` (services UI and no-CLI expectations)

**What’s already covered / existing**
- `synpunkt` addon exists in `synesyn/synesyn_client/addons/synpunkt/`.
- ComfyUI Godot-side integration pattern to build on:
  - `arigbs/Godot-Comfy-AI` ([GitHub](https://github.com/arigbs/Godot-Comfy-AI))

---

## Priority guide
- **v0 MVP**: SynDeck v2 (outline + edgeless/Prezi) over a `ui.syndoc` artifact, plus a minimal “closure performer” view that loads `ui.closure` and lets users curate/present it.
- **v1**: Render orchestration mode + ComfyUI bridge (SynPunktRenderBridge) with strong provenance; Story Stage as a first-class mode; realtime sensor overlays.
- **v1.5 hardening**: improve render reliability/UX without major architecture changes (policy controls, diagnostics, cleanup).
- **v2**: orchestration depth (queueing/cancel/retry/resume), richer preset lifecycle, stronger provider/routing parity.

## A) Human agency UX contract (non-negotiable)
- [x] (v0) Implement the shared pattern from `../Human_Agency_UX_Contract.md`:
  - [x] (v0) Propose → Preview → Commit → Version (SynDoc drafts + explicit Save/Save-as-version; render request uses explicit submit after previewing workflow+patch)
  - [x] (v0) “Editable by default” where practical (layouts/text blocks/prompt mappings; render patch set editable pre-submit)

## A2) Mode layout (how SynPunkt flows without bloat)

SynPunkt is one component, but it has multiple *modes* that share the same substrate-backed state:

- **Design mode (v0)**: author/curate `ui.syndoc` artifacts (editable blocks, frames) and save/version them.
- **Render mode (v1 placeholder in v0 UI)**: bridge to ComfyUI (or hub-routed render later). Produces image artifacts with strong provenance.
- **Present mode (v0)**: present a `ui.syndoc` as a lightweight SynDeck/slide-outline (prev/next frame, readable preview).
- **Settings mode (v0 placeholder)**: provider routing (local vs hub), defaults, and future mode options.

Principle: **one shared data model (SynDoc + Substrate)**; modes are UI surfaces over it. No duplicated logic.

## B) SynDeck v2 (unified outline + edgeless/Prezi)
- [x] (v0) Define a single **SynDoc** schema stored as `ui.syndoc` artifacts:
  - [x] (v0) frames/nodes, spatial transforms, text/media blocks
  - [x] (v0) outline ordering + “edgeless” spatial layout as two views over the same model
  - [x] (v1) camera path / zoom path:
    - per-frame camera capture/apply in Present → Edgeless
    - optional deck steps stored as `presentation.steps[]` for Prezi-style stepping
- [x] (v0) Build Godot editor/runtime UI for SynDoc:
  - [x] (v0) edit text/layout (editable by default; images via artifact refs later)
  - [x] (v0) save/load/version SynDocs via substrate
- [x] (v1) Interop: ingest/export HTML deck formats (reference: `metapunkt-pitch-v4`) without bloating the core.
  - Implementation note: interop is implemented via the deck’s exported `slides.json` schema (`json.slides_deck`) rather than parsing HTML directly.

## C) Closure “performer” view (consume closures; do not form them)
- [x] (v0) Load `ui.closure` artifacts and present them as a navigable/presentable surface.
- [x] (v0) Allow users to curate outputs derived from a closure into SynDocs (frames/blocks) and Present mode.
- [x] (v0) Any edits here create new artifacts/versions; do not overwrite closure history.
  - Implementation note: SynPunkt does not edit/overwrite `ui.closure`; it creates new `ui.syndoc` artifacts, and “Save as new version” creates a new artifact with provenance pointing at the previous version.

## D) Render orchestration + ComfyUI integration as a bridge module
- [x] (v1) Define “render recipe” artifacts (prompt set → workflow preset + param mapping) with provenance.
- [x] (v1) Create `SynPunktRenderBridge` (Godot module) based on the Godot-Comfy-AI approach:
  - [x] (v1) load workflow JSON (API format)
  - [x] (v1) patch runtime inputs (via patch set applied to node inputs)
  - [x] (v1) submit job (WS best-effort) and track progress (WS progress when available; polls history for completion)
  - [x] (v1) fetch output images and register them as artifacts with provenance
- [x] (v1) Render results UX:
  - [x] append results (do not overwrite prior runs)
  - [x] store selected result metadata (artifact id) for copy/open actions
  - [x] keep results list visible (minimum height; ensure-current-visible on add)
- [x] (v1) Define a stable “render request” interface for SynPunkt/ScenSyn to call:
  - [x] (v1) workflow id/version (hash)
  - [x] (v1) parameter patch set
  - [x] (v1) desired output routing (local ComfyUI vs hub-submit vs hosted later)
  - Implementation note: contract is now standardized as `SynesynRenderRequestV1` + shared entrypoint `SynesynRenderService.submit_render_request()`; hub-submit endpoint `/render/submit` emits `render.*` events.

## E) LatentSubstrate provenance requirements for renders
- [x] (v1) Always persist:
  - [x] (v1) workflow JSON hash
  - [x] (v1) seed and offsets
  - [x] (v1) model/checkpoint identifiers (if discoverable)
  - [x] (v1) runtime patch set applied
- [x] (v1) Link generated image artifacts back to:
  - [x] (v1) the prompt artifact
  - [x] (v1) the session/turn that triggered it
  - [x] (v1) any sensor events used as parameters (via linking latest `json.sensor_snapshot` when present)

## F) Real-time sensor overlays (optional but powerful)
- [x] (v1) Subscribe to hub events and visualize live sensor streams on the canvas:
  - [x] (v1) “world state” nodes update in realtime (overlay nodes in Edgeless previews)
  - [x] (v1) record snapshots as artifacts for later replay (`json.sensor_snapshot`)

## G) Minimal v0 milestone
- [x] (v0) Load a `ui.closure` and create/save a `ui.syndoc` that curates/presents it (persisted + versioned).
- [x] (v1) Submit one Comfy render via the bridge and persist the generated image + provenance into the substrate.

## H) V1.5 hardening (current next phase)
- [x] (v1.5) Stabilize workflow selector UX:
  - [x] distinguish reusable workflow presets (`json.workflow`) from render history (`json.render_request`)
  - [x] ensure dropdown refresh reflects persisted rows correctly (fix selector reset bug)
- [x] (v1.5) Add workflow save policy controls to reduce artifact bloat:
  - [x] global toggle for automatic workflow persistence during render
  - [x] explicit manual action to save current workflow as preset
  - [x] when auto-save is off, keep workflow inline in `json.render_request` for replayability
- [x] (v1.5) Improve render diagnostics:
  - [x] robust error parsing for non-JSON hub error bodies
  - [x] explicit warnings when workflow/render_request persistence fails
- [x] (v1.5) Add lightweight retention/cleanup actions for render history artifacts:
  - [x] delete selected `json.render_request` from render history (explicit user action)
  - [x] delete selected generated image artifacts (single/multi-select explicit user action)
  - [x] keep default behavior non-destructive unless user explicitly triggers delete
- [x] (v1.5) Add simple dedupe policy for repeated workflows (hash-based reuse) beyond current session scope
  - [x] check in-session hash map first
  - [x] best-effort cross-session lookup via `json.workflow` query + provenance hash match before creating a new workflow artifact
  - [x] strict hash-only policy (no legacy migration fallback; old records will be wiped pre-deployment)
- [x] (v1.5) Add focused regression checks for render flow variants (dev-side routine; no user-facing controls):
  - [x] auto-save ON: submit same workflow twice -> same `workflow_artifact_id` is reused
  - [x] auto-save OFF: submit render -> workflow remains inline in `json.render_request` and no forced `json.workflow` create
  - [x] manual preset save: saves once, second save reuses existing by hash
  - [x] restart and reload: workflow dropdown still loads presets/history and dedupe still reuses existing workflow hash
- [x] (v1.5) Improve Render results gallery UX (workspace-level artifacts, not session-only):
  - [x] reload/list workspace `image.generated` artifacts
  - [x] filter + sort controls (newest/oldest/name)
  - [x] metadata/details panel for selected artifact (id/time/type/ext/size/hash)
  - [x] refresh observability in UI (loaded count + source + last refresh time/failure hint)
  - [x] tokenized filter facets in existing field (no new controls): `has:*`, `missing:*`, `last:*`
  - [x] list density modes via existing filter tokens (no new controls): `view:compact`, `view:expanded`
- [x] (v1.5) Add artifact naming UX for generated renders:
  - [x] default incremental display names with configurable prefix
  - [x] rename selected artifact using Hub metadata update
  - [x] reset selected name to metadata/default
- [x] (v1.5) Add cross-link navigation from selected render artifact:
  - [x] load linked workflow
  - [x] load linked render_request (and resolve workflow from it)
  - [x] copy all link ids
  - [x] link health status display (ok/missing/na/checking)
  - [x] normalize refs-map semantics in details panel (`MISSING` vs `N/A` vs link-not-found)
  - [x] ensure post-render metadata patch writes full refs map (guards against partial-merge link loss)
- [x] (v1.5) Add one-click insertion of selected render artifacts into current SynDoc frame.
- [x] (v1.5) Render-request playback clarity:
  - [x] selecting render history now performs explicit editor replacement from `json.render_request` (workflow + patch set + route URL when present)
  - [x] unified playback path for dropdown history and linked render_request action
  - [x] playback status text now reports source (`artifact`/`inline`) and patch count
- [x] (v1.5) Error-path hardening in Render mode:
  - [x] normalized status categories for submit/history/results-query failures (`hub_unreachable`, `comfy_unreachable`, `workflow_invalid`, `patch_invalid`, `output_missing`)
  - [x] centralized status text shaping to keep messages actionable and consistent
  - [x] route/provider parity in status text (`mode/provider` tags on submit, completion, and failures)
  - [x] aligned selector/playback query/load statuses to same route-aware semantics (`hub/substrate`)
  - [x] aligned render-details linked-load failures with centralized categorized formatter
- [x] (v1.5) Workflow health diagnostics hardening:
  - [x] detect malformed prompt nodes and missing `class_type` with explicit node-id hints
  - [x] keep passive status indicator colorized by severity (`ok`/`warn`/`error`)

## H2) Post-v1.5 validation still pending (based on current code state)
- [x] (evidence) Hub render job-control API smoke check passed against source server (`/render/submit`, `/render/jobs`, `/render/jobs/{id}/cancel`, `/render/jobs/{id}/retry`).
- [x] (evidence) Hub restart persistence smoke check passed for render jobs (statuses reloaded after restart; retried job retained `retried_from_job_id` linkage in `metadata_json`).
- [ ] (pilot-readiness) Run a focused end-to-end Render regression pass:
  - [ ] startup hydrate + restart hydrate
  - [ ] submit -> complete -> artifact persistence + refs integrity
  - [ ] playback (history + linked request) and workflow replacement correctness
  - [ ] link health states + delete/rename actions + workspace switch
  - [ ] filter/token facets and density modes under realistic data volume
- [ ] (pilot-readiness) Validate Render results list/details responsiveness on high artifact counts (no UI stalls under large workspace history).
- [ ] (pilot-readiness) Final wording/UX pass for status text from live runs (tighten actionability/consistency without reducing diagnostic signal).

## I) V2 roadmap (render mode)
- [x] (v2) Job orchestration UX:
  - [x] queue view with running/pending/completed jobs
  - [x] cancel/retry/resume controls
  - [x] clearer mapping between Comfy prompt ids and Synesyn render requests
- [x] (v2) Preset lifecycle:
  - [x] preset metadata (name/tags/model family/last used)
  - [x] preset versioning + compare/diff
  - [x] archive/prune workflows with safety checks
- [x] (v2) Provider/routing parity:
  - [x] make hub-routed render mode feature-par with direct mode
  - [x] consistent status/error semantics across local/direct/hub routes
- [x] (v2) Provenance graph UX:
  - [x] trace view from generated image -> render_request -> workflow/prompt/inputs
  - [x] "why this output?" inspector (seed/model/patch summary)

## I2) V2 phased delivery plan (execution-ready)

### V2.1 — Job orchestration baseline (queue + control)
- Scope:
  - queue list in Render mode (pending/running/completed/failed)
  - per-job actions: cancel + retry
  - stable identifiers shown in one row (`job_id`, `render_request_artifact_id`, `prompt_id`)
- Acceptance checks:
  - submit 3 renders quickly -> all appear in queue with independent status updates
  - cancel an in-flight job -> status transitions to canceled/failed with clear reason
  - retry a failed/canceled job -> new job row created with traceable linkage to original
  - app restart -> queue/history list reloads from hub without losing linkage fields

### V2.2 — Preset lifecycle + provider/routing parity
- Scope:
  - preset metadata (`name`, `tags`, `model_family`, `last_used_at`)
  - preset versioning/diff view (at least JSON-level compare)
  - parity pass for direct vs hub-routed render status/errors
- Acceptance checks:
  - create/edit/version preset -> previous versions remain loadable
  - switching direct/hub route preserves equivalent user-facing run states
  - same invalid workflow in both routes produces comparable, actionable error semantics
  - preset search/filter by tag/name works on >=100 presets without UI stalls

### V2.3 — Provenance graph and cross-app consumption
- Scope:
  - graph navigation: image -> render_request -> workflow -> prompt (+ optional sensor snapshot)
  - "why this output?" panel with structured summary (seed, model, patch set, route)
  - shared artifact-link traversal conventions for ScenSyn/ReadyMade
- Acceptance checks:
  - from any selected image artifact, all existing upstream links are navigable in <=3 clicks
  - missing links are explicitly labeled and distinguishable from transient loading
  - copied link bundle from SynPunkt resolves in ScenSyn/ReadyMade using same ids/semantics
  - graph/details view remains responsive on workspaces with >=5k artifacts

### Cross-phase quality gates (must pass each phase)
- [ ] no regressions in v1.5 render flow checks (auto-save on/off, manual save, restart reload)
- [ ] no silent artifact-loss paths (all destructive actions require explicit user action)
- [ ] status text stays high-signal and user-actionable (avoid opaque transport-only messages)
- [x] docs updated in lockstep (`06_SynPunkt.md`, user guide, hub API notes)

### Notes (implemented in code)
- **SynPunktRenderBridge**: `synesyn/synesyn_client/addons/synpunkt/scripts/synpunkt_render_bridge.gd`
- **Render UI wiring + “Load workflow from SynDoc block”**: `synesyn/synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd`
- **Hub inline bytes for images** (`inline_bytes_base64`): `synesyn/services/synesyn_hub/app/substrate/routes.py` + Godot `HubSubstrateClient.create_artifact_inline_bytes_base64`
- **Render request contract + entrypoint**: `synesyn/synesyn_client/scripts/synesyn_render_request_v1.gd` + `synesyn/synesyn_client/scripts/synesyn_render_service.gd`
- **Hub-submit render endpoint + events**: `synesyn/services/synesyn_hub/app/routes/render.py` + hub job runner `synesyn/services/synesyn_hub/app/routes/jobs.py` (job type `render.comfyui`, emits/persists `render.queued|started|progress|completed|failed`)
- **Slides deck interop** (`metapunkt-pitch-v4` `slides.json`): `synesyn/synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd` (`json.slides_deck` import/export)
- **Present camera capture/apply**: `synesyn/synesyn_client/addons/synpunkt/scripts/edgeless_preview.gd` + `synesyn/synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd`
- **Present deck steps** (`presentation.steps[]`) and stepping logic: `synesyn/synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd`
- **Workflow dropdown population** (`json.workflow` + fallback `json.render_request`): `synesyn/synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd`
- **Render gallery/details/actions + insertion into frame**: `synesyn/synesyn_client/addons/synpunkt/scripts/synpunkt_dock.gd` + `synesyn/synesyn_client/addons/synpunkt/scenes/synpunkt_dock.tscn`
- **Artifact metadata rename API usage** (`PATCH /substrate/artifacts/{id}/metadata`): `synesyn/services/synesyn_hub/app/substrate/routes.py` + `synesyn/services/synesyn_hub/app/substrate/repo.py` + `synesyn/synesyn_client/scripts/hub_substrate_client.gd`


