# To‑Do — SynAxes (Latent Reality engine: patterns + Closure Map / Proxistance + closure formation)

**Primary spec references**
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Synesyn_Hub_API_Spec.md` (jobs API + substrate persistence)
- `../LatentSubstrate_Data_Model.md` (embeddings, projections, cluster artifacts)
- `../../architectural-decisions/0015-synaxes-v2-closure-map-orientation.md` (Proxistance / orientation; not physics-4D)

**What’s already covered / existing**
- SynAxes exists as a Godot plugin/addon with visualization + discovery modes:
  - `synesyn_client/addons/synaxes/README.md`
- **V1 is wired to the Hub substrate**: import context graphs / embeddings, run local or Hub jobs (`synaxes.project` / `cluster` / bridges / hubs), persist analysis artifacts, and commit human-reviewed `ui.closure` records with provenance.

---

## Priority guide
- **v0 MVP**: SynAxes forms and commits human-reviewed `ui.closure` artifacts backed by the Hub substrate, and can run one projection+cluster workflow to propose closure drafts.
- **v1 Artrhythmetic Store bridge**: memory-bearing closures should also commit canonical `artrhythmetic_store/closures/` records with symbolic constraints and provenance.
- **v1**: broaden job suite (bridges/hubs/embeddings), improve provenance display, support “dreaming” pipelines at scale.
- **later**: large-corpus acceleration, hosted analytics packs, enterprise reporting.

## A) Decide what runs where (Godot vs hub)
- [x] (v0) Keep interactive visualization (3D exploration) in Godot.
- [x] (v0) Define the boundary: SynAxes UI submits jobs; hub executes; results come back as artifacts. (See `../SynAxes_Embeddings_Pipeline.md`)
- [ ] (v1) Move heavy compute (UMAP/t‑SNE on large sets, batch embedding) to hub jobs where needed.

## B) LatentSubstrate integration
- [x] (v0) Implement “import from substrate”:
  - [x] (v0) query entity/artifact sets for analysis (imports `ui.context_graph` for dataset selection)
  - [x] (v1) fetch embeddings if present (or request embedding job) (submits `synaxes.embed_text` when enabled)
- [x] (v0) Implement “write results to substrate”:
  - [x] (v0) cluster artifacts (`graph.cluster_result`)
  - [x] (v0) projection artifacts (`coords.projection_2d/3d`)
  - [x] (v1) bridge/hub artifacts (`graph.bridge_result` / `graph.hub_result`)
  - [x] (v0) relations linking cluster membership (bridges later)

## C) Jobs mapping (hub job types)
- [x] (v0) Define minimal job types and inputs:
  - [x] (v0) `synaxes.project` (pca)
  - [x] (v0) `synaxes.cluster`
- [x] (v0) Ensure each v0 job persists results with provenance.
- [x] (v1) Add additional job types:
  - [x] (v1) `synaxes.embed_text`
  - [x] (v1) `synaxes.embed_image`
  - [x] (v1) `synaxes.bridges`
  - [x] (v1) `synaxes.hubs`
- [x] (v1) Ensure each job emits progress events (optional for small runs).

## D) UX: analysis workflow and reproducibility
- [x] (v0) Implement the **Human Agency UX Contract** pattern (`../Human_Agency_UX_Contract.md`) for all proposals:
  - [x] (v0) Propose → Preview → Commit → Version (Dream Inbox + Closure Editor)
  - [x] (v0) “Editable by default” where practical (closure criteria/time window/labels are editable pre-commit)
- [x] (v0) Add explicit “analysis run” objects:
  - [x] (v0) chosen dataset (entity ids)
  - [x] (v0) chosen method + parameters
  - [x] (v0) output artifacts created
- [ ] (v0) Surface provenance in the UI (“this cluster came from X, using Y params”).
  - [x] (v1) Surface artifact ids in the UI status panel for traceability (analysis/projection/cluster/bridges/hubs).
- [x] (v0) Add a **Closure Editor** (writes `ui.closure` artifacts):
  - [x] (v0) selection criteria + pins/constraints
  - [x] (v0) explicit **time window** (the “+1 temporal dimension”)
  - [x] (v0) intent notes/labels
  - [x] (v0) commit creates new versions (no overwrites)
- [x] (v0) Add a **Dream Inbox**: proposed patterns/closures that users can accept/reject/defer (with decision events persisted).

## E) Integration with SynTree + ScenSyn + ReadyMade
- [ ] (v1) From SynTree: allow selecting content sources that are already persisted to substrate.
- [ ] (v1) From ScenSyn: “dreaming” jobs run nightly/idle and appear as SynAxes results.
- [ ] (later) From ReadyMade: analyze “found concepts” corpora and produce publishable pattern artifacts.

## F) Minimal v0 milestone
- [x] (v0) UI can select a dataset from substrate, run `synaxes.project+cluster`, visualize results, and **commit a `ui.closure`** to substrate with provenance.
- [x] (v1) When a committed closure has Artrhythmetic memory significance, also commit it to Artrhythmetic Store `closures/` via `/artrhythmetic-store/closures/commit`.

## G) Closure Map orientation (V2 — see ADR 0015)
Canonical concept: `synesyn/docs/concepts/closure-map.md`  
Product spike: `synesyn/docs/product-requirements/PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md`

- [x] (docs) Canonical Closure Map + ADR 0015 (Distal / Deep · Recursive Closure / Proxistance; not physics-4D).
- [x] (v2) Human-first A–D orientation on Dream Inbox / Closure Editor (`REQ-CMO-001`).
- [x] (v2) Persist optional `orientation` on `ui.closure` schema_version 2 (`REQ-CMO-002`).
- [x] (v2) Saved Closures badges + coverage strip (`REQ-CMO-003`, `REQ-CMO-004`).
- [ ] (later) Tetrahedral edge hints once tags exist; Proxistance-first navigation UX.
- [x] (A / REQ-NDP-014) Refresh technical-review / platform-architecture “4D canvas” wording to point at ADR 0015 (Proxistance / Closure Map orientation).

## H) Open Closure admissibility bridge (ADR 0016)
- [x] (hub) Opt-in Store gate after `sort_candidates` / before `build_context_pack`.
- [x] (client) Thin SynAxes import filter when Store `admissibility.enabled`.
- [ ] (later) Optional ClosureRouter.audit() packaging when Open Closure ships with hub.

## I) Navigable default path (PRD-SYNAXES-NAVIGABLE-DEFAULT-PATH)
Product plan: `synesyn/docs/product-requirements/PRD-SYNAXES-NAVIGABLE-DEFAULT-PATH.md`

Ship order: **0** (shared core, lands alone) → **A → B → C** (minimum honest sell),
then **D** (app hook), **E** (reload), **F** (headless discovery).

- [x] (0) `addons/synesyn_core` library addon owns RuntimeConfig / ThemeManager / HubSubstrateClient (+ session/render/graph_workspace helpers); product addons rewritten off host `res://scripts/**` paths; ADR 0017; headless compile OK for core + SynAxes + SynPunkt + Metapunkt SynaxesInterface (`REQ-NDP-018`–`020`). Residual: SynTree still uses bare `ContentBus` (its own autoload, not host ScenSyn); scene theme `.tres` skins remain optional host assets.
- [x] (A) Precondition: extract `synaxes_analysis_controller.gd` (RefCounted) and a single `synaxes_ui_binder.gd` shared by `plugin.gd` and the runtime controller (`REQ-NDP-022`, `REQ-NDP-021`) — runtime controller remains under the 1200-line hard limit after Phase A UI wiring
- [x] (A) Advanced collapse + step spine + empty CTA + Overview-first + Work on this (`REQ-NDP-001`–`005`)
- [x] (A) Correct stale “not yet wired to substrate” / “4D canvas” claims (`REQ-NDP-014`, pulled forward from C)
- [x] (B) Disclosed model-embedding opt-in (no silent egress), latest context-graph CTA, post-commit hand-off via host navigation signal, plain Orientation/Coverage, human discover summary (`REQ-NDP-006`–`010`)
- [x] (C) Tools/README/user-guide copy refresh incl. drop-in story (`REQ-NDP-011`–`013`)
- [x] (D) Delete dead Metapunkt interface duplicate; headless commit args on the closure controller; Metapunkt API; one propose-themes app entry that opens the dock preloaded (`REQ-NDP-025`, `015`, `016`) — Workshop Session Record **Propose themes** → Tools/SynAxes with session import + discover queued + Closures focus; full headless discovery remains Phase F
- [x] (E) Reload last analysis run (`REQ-NDP-017`) — `Reload last analysis` button near Discover; hub pipeline loads latest `json.analysis_run` + projection/cluster into Pattern Space without re-import
- [x] (F) Headless import → embed → discover with no dock; harness run spec (`REQ-NDP-024`) — `analysis_controller.import_embed_discover` + Metapunkt `discover_patterns`; Godot check `addons/synaxes/tests/test_headless_discover.gd` + run spec `synaxes_headless_discover.json`

