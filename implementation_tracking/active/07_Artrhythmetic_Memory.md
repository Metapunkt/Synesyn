# To‑Do — Artrhythmetic Memory (symbolic deterministic memory capability)

**Primary spec references**
- `../Artrhythmetic_Memory_Capability_Spec.md`
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Synesyn_Hub_API_Spec.md`
- `../LatentSubstrate_Data_Model.md`

**Prototype reference only**
- `stochasticdreams_visualsystem/Artrhythmetic/artrhythmetic-database_system/ARTRHYTHMETIC_MEMORY_README.md`
- `stochasticdreams_visualsystem/Artrhythmetic/artrhythmetic-database_system/artrhythmetric_memory.py`

**What’s already covered**
- The philosophy, boundaries, and canonical home are defined in `../Artrhythmetic_Memory_Capability_Spec.md`.
- This checklist focuses on implementation order, scaffold shape, and concrete tasks.

---

## Priority guide
- **v0 MVP**: file-backed canonical symbolic memory, deterministic ingest + expand, seed registry, safe writes, dedicated hub routes.
- **v1**: stronger ingest reports, snapshots, substrate export, app adapters, richer diagnostics.
- **later**: advanced visualization, batch ingest jobs, multi-workspace sync, optional alternative storage mirrors.

---

## A) Canonical scaffold and ownership
- [x] (v0) Create canonical module home at `synesyn/services/synesyn_hub/app/artrhythmetic_memory/`.
- [x] (v0) Add initial module files:
  - [x] `__init__.py`
  - [x] `engine.py`
  - [x] `seed_registry.py`
  - [x] `schemas.py`
  - [x] `index_store.py`
  - [x] `ingest.py`
  - [x] `retrieve.py`
  - [x] `service.py`
  - [x] `routes.py`
  - [x] `README.md`
- [ ] (v0) Ensure the capability is app-agnostic:
  - [ ] no imports from `ScenSyn/`
  - [ ] no imports from `stochasticdreams_visualsystem/`
  - [ ] no app-specific terms in canonical data models
- [ ] (v0) Treat `stochasticdreams_visualsystem/Artrhythmetic/artrhythmetic-database_system/` as reference only, not runtime home.

## B) Seed registry and symbolic engine
- [x] (v0) Implement canonical Odù seed registry with named families:
  - [x] `primary`
  - [x] `transitional`
  - [x] `rhythmic`
  - [x] `alternating`
- [x] (v0) Port the Boolean tensor product / complement logic from prototype into `engine.py`.
- [ ] (v0) Preserve deterministic expansion semantics exactly as defined in prototype/paper.
- [ ] (v0) Add validation utilities:
  - [ ] 4×4 binary matrix validation
  - [ ] complement-pair validation
  - [ ] custom seed family validation
- [ ] (v1) Add optional custom seed-family loading from workspace-local config.

## C) Canonical file-backed storage
- [x] (v0) Implement canonical workspace layout under `<workspace>/artrhythmetic_memory/`:
  - [x] `memory_config.json`
  - [x] `memory_index.json`
  - [x] `seeds/seed_registry.json`
  - [x] `documents/<document_id>.json`
  - [x] `sources/`
  - [x] `snapshots/`
  - [x] `ingest_reports/`
- [x] (v0) Implement atomic write behavior for all canonical files.
- [x] (v0) Implement safe directory bootstrapping on first use.
- [ ] (v0) Add file-locking or equivalent safe-write protection for concurrent writes.
- [ ] (v1) Add rolling backup/snapshot creation before destructive updates.

## D) Schema and validation
- [x] (v0) Define schema version constants in `schemas.py`.
- [x] (v0) Validate:
  - [x] document records
  - [x] chunk records
  - [x] seed registry records
  - [ ] ingest reports
- [ ] (v0) Enforce required rationale fields for any LLM-assisted decisions.
- [ ] (v1) Add migration helpers for schema upgrades.

## E) Ingest pipeline
- [x] (v0) Port deterministic fallback ingest (`headings`) from prototype.
- [x] (v0) Normalize chunk path rules:
  - [x] stable `chunk_id`
  - [x] stable `path`
  - [x] stable `parent_path`
- [ ] (v0) Persist ingest-time rationale in document records and ingest reports.
- [ ] (v0) Define LLM-assisted ingest contract:
  - [ ] `recommended_root_seed`
  - [ ] `root_rationale`
  - [ ] chunks with `recommended_sub_seed`
  - [ ] per-chunk `selection_rationale`
  - [ ] optional nested sub-chunks
- [ ] (v1) Add a strict validator for external LLM analyzer return payloads.
- [ ] (later) Add batch ingest job support through hub jobs framework.

## F) Retrieval and expansion
- [x] (v0) Implement document-level expansion.
- [x] (v0) Implement chunk-level expansion using dot-path traversal.
- [x] (v0) Fix and verify nested chunk lookup behavior so retrieval returns the intended chunk entry, not only its `sub_chunks`.
- [x] (v0) Return explicit structured metadata with every expansion:
  - [x] `seed_family`
  - [x] `depth`
  - [x] `matrix_shape`
  - [x] complementarity verification status
- [ ] (v1) Add retrieval helpers by seed family / metadata filters.
- [ ] (v1) Add immutable snapshot expansion export.

## G) Hub API surface
- [x] (v0) Register dedicated routes under `/artrhythmetic-memory`.
- [x] (v0) Implement:
  - [x] `POST /artrhythmetic-memory/documents/ingest`
  - [x] `GET /artrhythmetic-memory/documents`
  - [x] `GET /artrhythmetic-memory/documents/{document_id}`
  - [x] `POST /artrhythmetic-memory/expand`
  - [x] `POST /artrhythmetic-memory/retrieve`
- [ ] (v0) Ensure routes remain app-agnostic and do not mention Stochastic Dreams or ScenSyn concepts.
- [x] (v1) Implement:
  - [x] `POST /artrhythmetic-memory/snapshots/create`
  - [x] `POST /artrhythmetic-memory/export/substrate-artifact`

## H) Optional substrate export (secondary, not canonical)
- [x] (v1) Define substrate artifact types:
  - [x] `json.artrhythmetic_memory_snapshot`
  - [x] `json.artrhythmetic_memory_ingest_report`
  - [x] `json.artrhythmetic_expansion`
  - [x] `json.artrhythmetic_seed_registry_export`
- [x] (v1) Implement export helpers from canonical file-backed state into substrate artifacts.
- [ ] (v1) Preserve provenance links between:
  - [ ] source refs
  - [ ] memory snapshot artifacts
  - [ ] app outputs that consume them
- [ ] (later) Add bidirectional discovery helpers so SynPunkt or other apps can browse exported memory artifacts.

## I) App adapter layer (outside canonical capability)
- [x] (v1) Define a thin app adapter contract for consumers.
- [ ] (v1) Stochastic Dreams / `vis_story` adapter:
  - [x] request symbolic continuity context
  - [x] receive chunk summaries / seed emphasis / narrative tensions
  - [ ] translate into cycle/panel story JSON
- [ ] (v1) ScenSyn adapter:
  - [x] retrieve symbolic context for scenario continuity
  - [x] define `scenario_continuity_state` contract
  - [x] wire `scenario_continuity_state` into ScenSyn runtime as non-destructive `StoryState` enrichment
  - [ ] attach memory snapshots to session artifacts
- [ ] (v1) SynPunkt adapter:
  - [ ] inspect expansions
  - [ ] visualize chunk trees
  - [ ] compare seed families

## J) Testing and correctness
- [ ] (v0) Add unit tests for Boolean tensor product behavior.
- [ ] (v0) Add unit tests for complementarity preservation.
- [ ] (v0) Add unit tests for seed validation.
- [ ] (v0) Add unit tests for document/chunk schema validation.
- [x] (v0) Add unit tests for chunk-path traversal correctness.
- [ ] (v0) Add round-trip tests for index read/write consistency.
- [x] (v1) Add ingest tests for `headings` mode.
- [ ] (v1) Add ingest tests for `llm_once` mode.
- [ ] (v1) Add integration tests for hub routes.

## K) Minimal scaffold plan (implementation sequence)
- [x] Step 1: create module directory + empty files in `app/artrhythmetic_memory/`.
- [x] Step 2: port prototype engine + seed registry into `engine.py` / `seed_registry.py`.
- [x] Step 3: implement file-backed `index_store.py` + schemas.
- [x] Step 4: implement deterministic fallback ingest.
- [x] Step 5: implement retrieval / expand.
- [x] Step 6: add hub routes.
- [x] Step 7: add tests.
- [x] Step 8: add optional substrate export.
- [ ] Step 9: add app adapters.

- [x] Canonical implementation lives in Synesyn proper.
- [x] Canonical storage is still file-backed and human-readable.
- [x] Retrieval is deterministic tensor math only.
- [x] Ingest is inspectable and rationale-preserving.
- [x] Hub exposes dedicated routes.
- [x] Capability is usable by multiple apps without app-specific hard-coding.
- [ ] Prototype folder remains a reference, not the runtime implementation.
