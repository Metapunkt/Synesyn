# To-Do - Artrhythmetic Store (canonical memory substrate + generated indexes)

**Primary spec references**
- `../Artrhythmetic_Memory_Capability_Spec.md`
- `../LatentSubstrate_Data_Model.md`
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Synesyn_Hub_API_Spec.md`
- `../Human_Agency_UX_Contract.md`

**Intent**
- Make Artrhythmetic the governing memory grammar for symbolic recall, semantic candidate discovery, provenance, traces, closures, and runtime context.
- Keep canonical memory human-readable, file-backed, auditable, and repairable.
- Treat SQLite, embeddings, vector indexes, and other databases as optional generated accelerators, not as the truth layer.
- Preserve the existing Artrhythmetic core logic: seed matrices, complement logic, tensor expansion, symbolic addressing, and deterministic retrieval remain primary.

**Naming**
- Capability / user-facing concept: **Artrhythmetic Memory**
- Technical subsystem: **Artrhythmetic Store**
- Python module: `artrhythmetic_store`
- Workspace folder: `artrhythmetic_store/`

---

## Priority guide
- **v0 foundation**: define the store contract, canonical file layout, schemas, atomic IO, rebuildable indexes, and retrieval traces.
- **v0.1 vertical slice**: ingest markdown/text into canonical source + chunk records, build symbolic/lexical indexes, retrieve a context pack with an explanation trace.
- **v1 integration**: expose Hub routes, let SynTree request context packs from active sources/context graphs, and let ScenSyn consume store-backed continuity context.
- **later**: optional vector/SQLite/Postgres/LanceDB accelerators, richer repair UI, batch indexing jobs, multi-workspace sync.

---

## A) Architectural rule: truth vs acceleration
- [x] (v0) Define the canonical rule in the spec:
  - [x] canonical records are the memory truth
  - [x] generated indexes are disposable accelerators
  - [x] indexes can be deleted and rebuilt without memory loss
  - [x] if an index disagrees with a canonical record, the canonical record wins
- [x] (v0) Define accelerator categories:
  - [x] symbolic index
  - [x] lexical index
  - [x] relation index
  - [x] vector index
  - [x] optional SQLite metadata/index mirror
  - [x] optional external vector backend mirror
- [x] (v0) Document the human repair loop:
  - [x] open retrieval trace
  - [x] inspect why chunks were selected/rejected
  - [x] edit canonical source/chunk/memory/closure record
  - [x] rebuild indexes
  - [x] rerun retrieval

## B) Module scaffold
- [x] (v0) Create canonical module home at `synesyn/services/synesyn_hub/app/artrhythmetic_store/`.
- [x] (v0) Add initial module files:
  - [x] `__init__.py`
  - [x] `schemas.py`
  - [x] `paths.py`
  - [x] `atomic_io.py`
  - [x] `records.py`
  - [x] `source_ingest.py`
  - [x] `chunking.py`
  - [x] `symbolic_index.py`
  - [x] `lexical_index.py`
  - [x] `relation_index.py`
  - [x] `vector_index.py`
  - [x] `accelerators.py`
  - [x] `retrieval.py`
  - [x] `traces.py`
  - [x] `provenance.py`
  - [x] `service.py`
  - [x] `routes.py`
  - [x] `README.md`
- [x] (v0) Keep the existing `artrhythmetic_memory` core importable and app-agnostic; do not duplicate seed/tensor logic inside the store.
- [x] (v0) Define the store as a host/body for Artrhythmetic core decisions, not a replacement for the core.

## C) Workspace layout
- [x] (v0) Create workspace-local canonical layout:
  - [x] `artrhythmetic_store/store_manifest.json`
  - [x] `artrhythmetic_store/schemas/`
  - [x] `artrhythmetic_store/seeds/`
  - [x] `artrhythmetic_store/sources/`
  - [x] `artrhythmetic_store/memories/`
  - [x] `artrhythmetic_store/closures/`
  - [x] `artrhythmetic_store/artifacts/`
  - [x] `artrhythmetic_store/traces/`
  - [x] `artrhythmetic_store/indexes/`
- [x] (v0) Mark `indexes/` as generated and rebuildable in `store_manifest.json`.
- [x] (v0) Add safe bootstrapping for missing folders and initial manifest creation.
- [x] (v0) Add atomic write behavior for canonical files and generated indexes.
- [x] (v0) Add safe write locks or equivalent guardrails for concurrent Hub operations.

## D) Canonical record schemas
- [x] (v0) Define `source.json` schema:
  - [x] stable `source_id`
  - [x] original path/URI
  - [x] source type
  - [x] content hash
  - [x] ingest policy
  - [x] provenance
- [x] (v0) Define chunk record schema:
  - [x] stable `chunk_id`
  - [x] `source_id`
  - [x] source span (`line_start`, `line_end`, `char_start`, `char_end`)
  - [x] heading path / node path
  - [x] chunk text or text reference
  - [x] symbolic seed/tension fields
  - [x] rationale fields
  - [x] relation references
  - [x] ingest metadata
  - [x] content hash
- [x] (v0) Define memory record schema:
  - [x] stable `memory_id`
  - [x] symbolic address
  - [x] related chunks/sources
  - [x] rationale
  - [x] repair notes
- [x] (v0) Define closure record schema:
  - [x] stable `closure_id`
  - [x] selected sources/chunks/memories
  - [x] symbolic constraints
  - [x] human commit metadata
  - [x] provenance links
- [x] (v0) Define artifact record schema:
  - [x] produced output reference
  - [x] input trace/context pack links
  - [x] model/tool/config metadata where relevant

## E) Ingest and repairability
- [x] (v0) Implement deterministic markdown/text ingest:
  - [x] preserve original source text separately
  - [x] generate source record
  - [x] generate chunk records with source spans
  - [x] generate ingest report
- [x] (v0) Support manual symbolic annotation:
  - [x] primary seed
  - [x] secondary/complement seed
  - [x] tensions
  - [x] rationale
  - [x] relation hints
- [x] (v1) Support optional LLM-assisted ingest only at ingest time:
  - [x] chunk recommendations
  - [x] summary recommendations
  - [x] seed recommendations
  - [x] nesting recommendations
  - [x] rationale capture for every recommendation
- [x] (v1) Add validation that LLM-assisted fields are reviewable and do not become hidden runtime dependencies.
- [x] (v1) Add repair commands:
  - [x] validate canonical records
  - [x] find stale indexes
  - [x] rebuild indexes
  - [x] verify traces still resolve to existing records

## F) Generated indexes
- [x] (v0) Implement symbolic index generated from canonical records:
  - [x] seed -> chunk ids
  - [x] tension -> chunk ids
  - [x] closure -> selected ids
  - [x] memory -> related ids
- [x] (v0) Implement lexical index generated from canonical records:
  - [x] normalized terms -> chunk ids
  - [x] heading terms -> chunk ids
  - [x] source names/path aliases -> source ids
- [x] (v0) Implement relation index generated from canonical records:
  - [x] source/chunk/memory/closure edges
  - [x] typed relation lookup
  - [x] reverse lookup
- [x] (v0.1) Add `index_report.json`:
  - [x] build timestamp
  - [x] source hashes used
  - [x] index versions
  - [x] warnings/errors
- [x] (v1) Implement optional vector index sidecar:
  - [x] vector manifest
  - [x] embeddings keyed by chunk id
  - [x] provider/model metadata
  - [x] regenerate vectors when chunk hashes change
- [x] (v1) Implement accelerator adapter interface:
  - [x] pure file indexes
  - [x] SQLite mirror
  - [x] external vector backend mirror
  - [x] no-embedding symbolic/lexical mode

## G) Retrieval and traces
- [x] (v0.1) Implement retrieval plan generation:
  - [x] active sources/context graph scope
  - [x] symbolic seed/tension inputs
  - [x] lexical terms
  - [x] expansion depth
  - [x] accelerator options
- [x] (v0.1) Implement candidate discovery:
  - [x] symbolic candidates
  - [x] lexical candidates
  - [x] relation-neighborhood candidates
  - Optional vector candidates are deferred to the optional vector accelerator work below.
- [x] (v1) Deepen Artrhythmetic core responsibility for final symbolic expansion/ranking decisions beyond the current trace-summary integration.
- [x] (v0.1) Emit retrieval trace for every retrieval:
  - [x] query/request
  - [x] scope
  - [x] retrieval plan
  - [x] candidates
  - [x] selected chunks
  - [x] rejected chunks with reasons
  - [x] per-candidate score components
  - [x] explanation strings
  - [x] produced context pack id
- [x] (v0.1) Emit context pack:
  - [x] selected chunk text
  - [x] source metadata
  - [x] citation labels
  - [x] trace id
  - [x] provenance metadata

## H) Hub API surface
- [x] (v1) Register routes under `/artrhythmetic-store`.
- [x] (v1) Implement:
  - [x] `GET /artrhythmetic-store/status`
  - [x] `POST /artrhythmetic-store/config`
  - [x] `GET /artrhythmetic-store/sources`
  - [x] `POST /artrhythmetic-store/sources/ingest`
  - [x] `POST /artrhythmetic-store/indexes/rebuild`
  - [x] `POST /artrhythmetic-store/retrieve`
  - [x] `GET /artrhythmetic-store/traces/{trace_id}`
  - [x] `GET /artrhythmetic-store/context-packs`
  - [x] `GET /artrhythmetic-store/context-packs/{context_pack_id}`
  - [x] `GET /artrhythmetic-store/indexes/{index_name}`
  - [x] `GET /artrhythmetic-store/chunks/{chunk_id}`
  - [x] `POST /artrhythmetic-store/chunks/{chunk_id}/symbolic`
  - [x] `POST /artrhythmetic-store/artifacts/commit`
  - [x] `POST /artrhythmetic-store/context-graphs/commit`
  - [x] `GET /artrhythmetic-store/memories`
  - [x] `POST /artrhythmetic-store/memories/commit`
  - [x] `GET /artrhythmetic-store/closures`
  - [x] `POST /artrhythmetic-store/closures/commit`
  - [x] `POST /artrhythmetic-store/validate`
  - [x] `POST /artrhythmetic-store/repair/report`
  - [x] `POST /artrhythmetic-store/migrations/artrhythmetic-memory/export`
  - [x] `POST /artrhythmetic-store/migrations/syntree-context-graphs/export`
  - [x] `POST /artrhythmetic-store/migrations/substrate-artifacts/export`
- [x] (v1) Keep routes app-agnostic; ScenSyn/SynTree/SynAxes semantics belong in adapters.
- [x] (v1) Add API responses that expose explanation traces, not only selected text.

## I) SynTree integration
- [x] (v1) Add optional SynTree path: active content sources -> Artrhythmetic Store retrieval -> context pack.
- [x] (v1) Preserve current direct active-source injection as fallback.
- [x] (v1) Let SynTree publish `ui.context_graph` snapshots into the store as canonical or mirrored context records.
- [x] (v1) Add citation labels based on source/chunk metadata.
- [x] (v1) Store chat responses with trace/context-pack provenance when enabled.
- [x] (later) Add richer UI affordances:
  - [x] (v1) open latest retrieval trace/context-pack folder after store-backed chat
  - [x] (v1) run validate/repair-report/index-rebuild from SynTree
  - [x] view retrieval trace inline
  - [x] open canonical chunk
  - [x] repair symbolic metadata
  - [x] (v1) rebuild indexes

## J) ScenSyn, SynAxes, and SynPunkt integration
- [x] (v1) ScenSyn:
  - [x] consume context packs for scenario/session continuity
  - [x] attach retrieval trace/context-pack refs to continuity state provenance
  - [x] commit `json.scensyn_continuity_context` session artifacts from store context packs
  - [x] add opt-in captured-closure mirror to Store `closures/`
  - [x] keep SynTree editor state isolated unless user opts into bridge/context graph
- [x] (v1) SynAxes:
  - [x] consume relation/symbolic/vector indexes as generated datasets
  - [x] produce closures back into the store with provenance
- [x] (v1) SynPunkt:
  - [x] browse closures and context packs
  - [x] perform memory structures as visual/spatial surfaces
- [x] (later) ReadyMade:
  - [x] consume store-backed context packs for agentic content workflows
  - [x] commit generated outputs with trace links

## K) Migration from current storage assumptions
- [x] (v0) Inventory current SQLite/LatentSubstrate/vector/embedding usage:
  - [x] canonical data
  - [x] metadata/provenance
  - [x] generated artifacts
  - [x] acceleration/indexing
- [x] (v0) Classify each current use as:
  - [x] canonical store responsibility
  - [x] generated accelerator responsibility
  - [x] artifact/provenance mirror
  - [x] legacy compatibility path

### K.1 Current storage classification

**Canonical Artrhythmetic Store responsibility**
- `artrhythmetic_store/sources/`, `chunks/`, `memories/`, `closures/`, `traces/`, and `artifacts/context_packs/` are the human-readable truth layer for memory retrieval and repair.
- SynTree local file-backed active sources should be ingested into source/chunk records when store-backed context is enabled.
- SynTree `ui.context_graph` payloads mirrored into the store are canonical for Artrhythmetic memory/provenance workflows, even if a LatentSubstrate artifact copy also exists.
- ScenSyn `json.scensyn_continuity_context` committed from store context packs is a store artifact when the continuity context is part of memory repair/provenance.
- Future SynAxes/SynPunkt closures should commit to `closures/` first when they express symbolic selection, human commit metadata, or Artrhythmetic constraints.

**LatentSubstrate / SQLite responsibility**
- `app/substrate/db.py` uses SQLite for sessions, events, entities, relations, artifact index records, jobs, and metadata/provenance lookup. Keep this as the local operational substrate and query index.
- `POST /substrate/artifacts`, `/substrate/events`, `/substrate/entities`, `/substrate/relations`, and `/substrate/query` remain the app-wide operational API for runtime events, UI artifacts, render outputs, and cross-app provenance queries.
- LatentSubstrate artifacts that duplicate store records should be treated as mirrors or compatibility bridges unless the artifact type is outside Artrhythmetic memory scope.
- The SQLite file is not the canonical ontology for Artrhythmetic memory. If SQLite and store records disagree about a source/chunk/memory/closure/trace, the store record wins.

**Generated accelerator responsibility**
- `artrhythmetic_store/indexes/` remains disposable: symbolic, lexical, relation, and vector manifests can be rebuilt from canonical records.
- SynAxes `embeddings.text` and `embeddings.image` job outputs are generated accelerator artifacts. They may support projection, clustering, semantic lookup, or future vector sidecars, but are not memory truth.
- SynAxes `coords.projection_2d/3d`, `graph.cluster_result`, `graph.bridge_result`, and `graph.hub_result` are generated analytic artifacts. They can inform closures, but a human-committed closure must be written as a canonical closure record when it becomes part of memory.
- Future SQLite/Postgres/LanceDB/Chroma/Qdrant mirrors belong behind an accelerator adapter and must be rebuildable from canonical store records plus artifact provenance.

**Artifact/provenance mirror responsibility**
- `ui.context_graph`, `ui.prompt_chain`, `text.summary`, `text.prompt`, `json.metrics`, `audio.tts`, `text.transcript`, render artifacts, and SynAxes result artifacts should remain valid LatentSubstrate artifacts with provenance.
- When such artifacts become inputs to Artrhythmetic retrieval, store records should reference their artifact ids or payloads explicitly; the store should not scrape opaque artifact indexes.
- Bridge artifacts such as `bridge.ui_context_graph` and `chat.thread` snapshots are compatibility/provenance handles, not canonical memory records.

**Legacy compatibility path**
- Existing SynTree direct ContentBus context injection remains fallback behavior when store-backed retrieval is disabled or Hub ingestion fails.
- Existing substrate artifact persistence for SynTree important outputs remains optional and privacy-preserving by default.
- Current deterministic placeholder embedding jobs remain useful for stable SynAxes contracts while real embedding backends are introduced later as accelerators.
- [x] (v1) Keep existing SQLite/embedding code paths as optional accelerators during migration.
- [x] (v1) Add app-level opt-in config flags:
  - [x] `apps.syntree.use_artrhythmetic_store_context`
  - [x] `apps.syntree.publish_context_graph_to_artrhythmetic_store`
  - [x] `apps.syntree.artrhythmetic_store_top_k`
  - [x] `apps.syntree.artrhythmetic_store_expansion_depth`
  - [x] `apps.syntree.artrhythmetic_store_default_seed`
  - [x] `apps.scensyn.publish_closures_to_artrhythmetic_store`
- [x] (v1) Add runtime-configurable global Store/accelerator flags:
  - [x] `artrhythmetic_store.enabled` or equivalent Hub-wide switch
  - [x] `artrhythmetic_store.accelerators.lexical`
  - [x] `artrhythmetic_store.accelerators.vector`
  - [x] `artrhythmetic_store.accelerators.sqlite`
- [x] (v1) Add migration/export commands:
  - [x] existing Artrhythmetic Memory documents -> Artrhythmetic Store records
  - [x] existing SynTree context graphs -> store context records
  - [x] existing substrate artifacts -> store artifact mirrors where appropriate

## L) Testing and correctness
- [x] (v0) Unit tests for canonical path layout and manifest creation.
- [x] (v0) Unit tests for atomic writes and index rebuilds.
- [x] (v0) Unit tests proving indexes can be deleted and rebuilt from canonical records.
- [x] (v0.1) Retrieval trace tests:
  - [x] selected chunks resolve
  - [x] rejected chunks include reasons
  - [x] score components are present
  - [x] context pack links back to trace
- [x] (v0.1) Repair report tests:
  - [x] ingest reports are written
  - [x] repair reports validate indexes and trace references
- [x] (v0.1) Relation-neighborhood retrieval tests.
- [x] (v1) Store artifact provenance tests:
  - [x] `ui.context_graph` commit
  - [x] chat `text.summary` commit with trace/context-pack provenance
- [x] (v1) ScenSyn context-pack continuity adapter tests.
- [x] (v1) ScenSyn continuity artifact commit tests.
- [x] (v1) Canonical memory/closure record commit and relation-index tests.
- [x] (v1) Process-local write guard concurrency smoke test.
- [x] (v1) Hub route integration tests.
- [x] (v1) SynTree integration smoke test:
  - [x] active source ingested
  - [x] retrieval returns context pack
  - [x] chat response stores trace reference
  - [x] latest trace/context-pack folder opens from SynTree
- [x] (v1) ScenSyn continuity test:
  - [x] context pack consumed without cross-surface state bleed
  - [x] session artifact links trace/provenance

## M) Suggested execution order
1. [x] Update `Artrhythmetic_Memory_Capability_Spec.md` with Artrhythmetic Store naming and truth-vs-index rule.
2. [x] Scaffold `app/artrhythmetic_store/`.
3. [x] Implement workspace layout, manifest, schemas, and atomic IO.
4. [x] Implement markdown/text ingest into source + chunk records.
5. [x] Implement symbolic, lexical, and relation index rebuild.
6. [x] Implement retrieval trace + context pack.
7. [x] Add Hub routes for Store status, source/memory/closure/context-pack listing, ingest, rebuild, retrieve, trace/context-pack lookup, commits, validate, and repair reports.
8. [x] Add SynTree optional retrieval path with direct-injection fallback.
9. [x] Add ScenSyn context-pack consumption.
10. [x] Add optional vector and SQLite accelerators after the symbolic/lexical slice works.

## N) Definition of done for v0.1
- [x] A human can open the store folder and understand sources, chunks, symbolic annotations, and provenance.
- [x] A human can open a retrieval trace and understand why each selected chunk was retrieved.
- [x] A human can repair a canonical record, rebuild indexes, and rerun retrieval.
- [x] A human can run validate, repair report, and index rebuild from SynTree.
- [x] Deleting `indexes/` does not lose memory.
- [x] Retrieval works without embeddings or SQLite.
- [x] Embeddings/SQLite can be enabled later as accelerators without changing canonical records.
