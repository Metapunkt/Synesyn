# STFX Memory Capability Spec

**Status**: Proposed implementation spec (updated November 2026; ADR 0032)  
**Scope**: Synesyn-native, app-agnostic symbolic memory capability  
**Canonical home**: `services/synesyn_hub/app/stfx_memory/`  
**Prototype reference only**: `stochasticdreams_visualsystem/Artrhythmetic/artrhythmetic-database_system/`

**Narrative integration note (v5.2)**: In the Stochastic Dreams scenario,
`StfxMemory`'s `continuity_context` outputs (anchors, latent_tensions,
focus_terms) are narratively framed as "what the Tapestry dreamed between turns."
The Echo character (Keeper of Memory and Dreaming) uses these as source material.
This operationalizes the Forward Remembrance research concept of Social Dreaming
(Lawrence): memory and dreaming are coupled — what the world remembers, it dreams.
See `development_notes/Stochastic_Dreams_Concept_Note_v5.txt` section 12.

---

## 1) Purpose

`StfxMemory` is a reusable Synesyn capability for deterministic, auditable, culturally grounded memory retrieval.

It is not a Stochastic Dreams feature, not a ScenSyn-only subsystem, and not a generic database wrapper. It is a symbolic memory model grounded in the STFX (Seed-to-Field Expansion) framework:

- compact **4×4 seed matrices** (with `IFA_ODU` as the default reference lexicon) act as relational addresses
- **Boolean tensor expansion** is the retrieval and context-expansion mechanism
- a human-readable **symbolic index** replaces opaque embedding or vector retrieval
- optional LLM analysis is limited to **ingest-time interpretation only**

This capability must remain usable by:

- Stochastic Dreams
- ScenSyn
- SynPunkt
- future Synesyn applications
- external tooling that consumes Synesyn Hub APIs

---

## 2) Non-negotiable philosophical constraints

These requirements are normative. Implementations that violate them are not compliant even if technically functional.

### 2.1 Symbolic addressing is primary

Memory retrieval must be based on symbolic seed selection and chunk hierarchy, not on embeddings, semantic nearest-neighbor search, or opaque ranking.

### 2.2 Deterministic tensor retrieval is primary

Runtime retrieval must remain pure deterministic tensor math. The retrieval engine is the STFX expansion method itself, not a SQL query dressed up with symbolic metadata.

### 2.3 Human-auditable storage is primary

Canonical memory state must remain inspectable by humans as structured files. The memory method must never become inscrutable infrastructure.

### 2.4 Source texts remain untouched

Original markdown or source documents must remain separate from the memory index. The index stores symbolic structure, offsets, summaries, and rationales, not rewritten source documents.

### 2.5 LLM use is ingest-only and inspectable

If an LLM is used, it may only assist with ingest:

- chunking
- summary generation
- seed recommendation
- nesting recommendation

Every such decision must be saved with rationale. No runtime retrieval may depend on an LLM.

### 2.6 App-agnostic contract

The capability must not encode `StochasticDreams`, `ScenSyn`, `vis_story`, or any other app semantics into its canonical data model. Apps consume it through adapters.

### 2.7 Optional substrate mirroring only

The Synesyn substrate may store exports, snapshots, and provenance links, but it is not the canonical symbolic memory store.

---

## 3) Relationship to the STFX kernel

`StfxMemory` extends the same conceptual basis defined in `stfx_core`:

- **4×4 seed matrices** (such as the Odù groupings in `IFA_ODU`)
- **Boolean complementary pairing** as Ìbejì logic
- **Kronecker / Boolean tensor expansion** as recursive retrieval structure

In the visual system, the STFX operator produces fractal binary patterns for image generation.  
In the memory system, the same seed logic produces fractal relational context for document retrieval and symbolic recall.

The visual engine and memory engine are therefore siblings, not duplicates:

- `stfx_core` = shared Seed-to-Field Expansion kernel
- `StfxMemory` = symbolic memory and retrieval engine

Both inherit from the same seed-to-field deterministic recursive logic.

---

## 4) Canonical location in Synesyn

Production implementation lives at:

`services/synesyn_hub/app/stfx_memory/`

Recommended module layout:

```text
app/stfx_memory/
  __init__.py
  adapter_contracts.py
  seed_registry.py
  schemas.py
  index_store.py
  ingest.py
  retrieve.py
  service.py
  routes.py
  README.md
```

Module responsibilities:

- `services/synesyn_hub/app/stfx_core/kernel.py`
  - Boolean tensor product
  - complement logic
  - recursive expansion
  - matrix derivation helpers

- `seed_registry.py`
  - Odù signatures
  - named seed families
  - custom family loading
  - validation of complements and family definitions

- `schemas.py`
  - schema version constants
  - validation for config, document record, chunk record, snapshot record

- `index_store.py`
  - file-backed storage
  - atomic writes
  - backups/snapshots
  - lock handling

- `ingest.py`
  - deterministic fallback parsing
  - optional LLM-assisted ingest
  - rationale capture

- `retrieve.py`
  - document lookup
  - chunk-path traversal
  - expansion API
  - selection utilities

- `service.py`
  - high-level facade used by hub routes/jobs

- `routes.py`
  - hub API endpoints for app consumers

---

## 5) Canonical persistence model

### 5.1 Canonical rule

Canonical memory state is file-backed and symbolic.

The capability may run inside Synesyn Hub, but the hub is a host and API envelope, not the canonical memory ontology.

### 5.1.1 STFX Store direction

The **STFX Store** formalizes this persistence rule as a broader canonical memory substrate:

- **STFX Memory** remains the capability / user-facing concept.
- **STFX Core** (`stfx_core`) remains the governing logic: seed matrices, complement logic, tensor expansion, symbolic addressing, deterministic recall.
- **STFX Store** (`stfx_store`) is the human-readable file-backed substrate that preserves canonical source, chunk, memory, closure, artifact, trace, and provenance records.
- Generated indexes are **disposable accelerators**, not truth:
  - symbolic index
  - lexical index
  - relation index
  - optional vector index
  - optional SQLite or external database mirror
- If an index disagrees with a canonical record, the canonical record wins.
- Deleting `indexes/` must not lose memory; the system must be able to rebuild indexes from canonical records.
- Embeddings, SQLite, vector databases, and future database backends are optional accelerators and mirrors. They must not become the canonical memory ontology.

The repair loop is normative: a human should be able to open a retrieval trace, inspect why chunks were selected or rejected, edit the canonical record, rebuild indexes, and rerun retrieval without trusting an opaque index.

### 5.2 Workspace layout

Inside an active Synesyn workspace:

```text
<workspace_root>/
  stfx_store/
    store_manifest.json
    sources/
      <source_id>/
        source.json
        original.<ext>
        chunks/
          <chunk_id>.json
    memories/
      <memory_id>.json
    closures/
      <closure_id>.json
    artifacts/
      context_packs/
        <context_pack_id>.json
      <artifact_id>.json
    traces/
      <YYYY-MM-DD>/
        <trace_id>.json
    ingest_reports/
    repair_reports/
    indexes/
      symbolic_index.json
      lexical_index.json
      relation_index.json
      vector_index.manifest.json

  # Document-memory layout:
  stfx_memory/
    memory_config.json
    memory_index.json
    seeds/
      seed_registry.json
    documents/
      <document_id>.json
    snapshots/
      <timestamp>_<document_id>.json
    ingest_reports/
      <timestamp>_<document_id>.json
```

The `stfx_store/` layout is the canonical substrate for source/chunk/memory/closure/trace/context-pack records. The `stfx_memory/` layout supports document-memory workflows and can be exported into store records.

### 5.3 Canonical files

- `stfx_store/store_manifest.json`
  - store identity and workspace metadata
  - canonical authority declaration
  - accelerator flags and record counts

- `stfx_store/sources/<source_id>/source.json`
  - original source reference
  - content hash
  - ingest policy and provenance

- `stfx_store/sources/<source_id>/chunks/<chunk_id>.json`
  - source spans
  - symbolic fields
  - rationale and relation hints

- `stfx_store/memories/<memory_id>.json`
  - symbolic address
  - related sources/chunks/closures
  - rationale and repair notes
  - provenance

- `stfx_store/closures/<closure_id>.json`
  - selected sources/chunks/memories/artifacts
  - symbolic constraints
  - human commit metadata
  - provenance

- `stfx_store/traces/<date>/<trace_id>.json`
  - retrieval request, plan, candidates, selected/rejected records, score components, and explanations

- `stfx_store/artifacts/context_packs/<context_pack_id>.json`
  - cited chunks selected for LLM/app context
  - trace linkage and provenance

- `stfx_store/indexes/*.json`
  - generated symbolic, lexical, relation, and optional vector accelerators
  - protected by process-local write guard in the Hub service
  - disposable and rebuildable from canonical records

`stfx_memory/` files:

- `memory_config.json`
  - capability config
  - ingest policy
  - schema version
  - feature flags

- `memory_index.json`
  - top-level registry
  - document summaries
  - lookup metadata

- `seeds/seed_registry.json`
  - canonical seed families
  - Odù definitions
  - complement mappings

- `documents/<document_id>.json`
  - one full symbolic memory record per ingested document

- `snapshots/*.json`
  - immutable frozen copies for audit/recovery

- `ingest_reports/*.json`
  - ingest-time decision report, including rationale and any LLM-produced structure

---

## 6) Core data model

### 6.1 Document record

Each document record must include:

```json
{
  "schema_version": 1,
  "document_id": "stfxmem_doc_001",
  "title": "example_document",
  "source_ref": {
    "kind": "file",
    "path": "docs/example_document.md"
  },
  "ingested_at": "2026-03-29T12:00:00Z",
  "ingest_strategy": "headings",
  "root_seed_family": "primary",
  "root_seed_matrix": [[0,0,0,0],[1,1,1,1],[1,0,0,1],[0,1,1,0]],
  "ingest_rationale": "Heading-based fallback used; no LLM analyzer provided.",
  "chunks": {},
  "metadata": {}
}
```

### 6.2 Chunk record

Each chunk record must include:

```json
{
  "chunk_id": "section_0",
  "path": "section_0",
  "parent_path": "",
  "start_offset": 0,
  "end_offset": 120,
  "summary": "Introduction",
  "recommended_sub_seed_family": "primary",
  "sub_seed_matrix": [[0,0,0,0],[1,1,1,1],[1,0,0,1],[0,1,1,0]],
  "selection_rationale": "Chosen for strongest contrast and foundational role.",
  "sub_chunks": {}
}
```

### 6.3 Required invariants

- every `document_id` must be unique
- every `chunk_id` must be unique within its parent
- every chunk must have a stable `path`
- `start_offset <= end_offset`
- `root_seed_family` and `recommended_sub_seed_family` must resolve in the seed registry
- every LLM-assisted seed choice must include a rationale string

---

## 7) Seed registry model

The default seed registry ships with named families derived from the `IFA_ODU` reference lexicon:

- `primary`
- `transitional`
- `rhythmic`
- `alternating`

Each family record must include:

- `family_id`
- `display_name`
- `description`
- `oduu_members`
- `seed_matrix`
- `complement_properties`

Example:

```json
{
  "family_id": "primary",
  "display_name": "Primary",
  "description": "Foundational contrast pairings",
  "oduu_members": ["Ogbe", "Oyeku", "Iwori", "Odi"],
  "seed_matrix": [[0,0,0,0],[1,1,1,1],[1,0,0,1],[0,1,1,0]],
  "complement_properties": {
    "validated": true,
    "notes": "Strong contrast and foundational polarity."
  }
}
```

Custom seed families are allowed, but they must:

- preserve 4×4 binary form
- pass validation
- declare provenance

---

## 8) Retrieval model

### 8.1 Core retrieval primitives

The capability supports:

- **document-level expansion**
- **chunk-level expansion**
- **path-based retrieval**
- **seed-family-based filtering**

### 8.2 Expand contract

Input:

```json
{
  "document_id": "stfxmem_doc_001",
  "chunk_path": "chapter_2.section_1",
  "depth": 3
}
```

Output:

```json
{
  "ok": true,
  "document_id": "stfxmem_doc_001",
  "chunk_path": "chapter_2.section_1",
  "seed_family": "transitional",
  "depth": 3,
  "matrix_shape": [256, 256],
  "matrix": [[0,1,1,...], ...],
  "meta": {
    "complementarity_verified": true,
    "source_ref": {"kind": "file", "path": "docs/example.md"}
  }
}
```

### 8.3 Chunk-path rules

Chunk traversal must be stable and deterministic:

- use dot notation for hierarchical paths
- `chapter_1.section_2.subsection_a`
- retrieval must return the target chunk entry itself, not only its children
- lookup failures must return explicit structured errors

### 8.4 Runtime retrieval rule

Runtime retrieval must never consult an LLM. It must operate only on:

- stored symbolic index
- stored seeds
- deterministic expansion logic

---

## 9) Ingest model

### 9.1 Allowed ingest modes

- `headings`
  - deterministic fallback
  - no LLM dependency

- `llm_once`
  - one-time analysis at ingest
  - allowed to propose chunking, seed family choices, summaries, and nesting
  - must produce explicit rationales

### 9.2 LLM-assisted ingest contract

Any ingest analyzer must return a structured object containing:

- `recommended_root_seed`
- `root_rationale`
- `chunks`
  - `id`
  - `summary`
  - `recommended_sub_seed`
  - `selection_rationale`
  - `start_offset`
  - `end_offset`
  - optional nested `sub_chunks`

No free-form output is acceptable.

### 9.3 Ingest outputs

Ingest must produce:

- document record
- memory index update
- ingest report
- optional snapshot

---

## 10) Hub API surface

The capability is exposed through dedicated routes, not only through generic substrate CRUD.

Base prefix:

`/stfx-memory`

### 10.1 Endpoints

- `POST /stfx-memory/documents/ingest`
  - ingest a source document
  - request may specify `strategy=headings|llm_once`

- `GET /stfx-memory/documents`
  - list document summaries

- `GET /stfx-memory/documents/{document_id}`
  - fetch canonical symbolic record

- `POST /stfx-memory/expand`
  - expand document/chunk to requested depth

- `POST /stfx-memory/retrieve`
  - symbolic retrieval by document, path, family, or metadata

- `POST /stfx-memory/snapshots/create`
  - create immutable snapshot

- `POST /stfx-memory/context/continuity`
  - build an app-agnostic continuity-context payload for downstream consumers

- `POST /stfx-memory/export/substrate-artifact`
  - publish selected state into substrate artifacts for cross-app use

### 10.2 Capability constraints

These routes must remain:

- app-agnostic
- deterministic
- explicit about ingest strategy
- explicit about whether LLM was involved

No route may mention Stochastic Dreams, ScenSyn, `vis_story`, or AraTitun in its canonical contract.

---

## 11) Optional substrate mirroring

Substrate mirroring is allowed but secondary.

Recommended artifact types:

- `json.stfx_memory_snapshot`
- `json.stfx_memory_ingest_report`
- `json.stfx_expansion`
- `json.stfx_seed_registry_export`

Use cases:

- provenance
- cross-app discovery
- UI browsing in SynPunkt
- linking memory state to render requests or story generation outputs

Non-use case:

- replacing the canonical file-backed symbolic index

---

## 12) App adapter contract

Applications should consume `StfxMemory` through adapters that translate app needs into generic symbolic queries.

### 12.1 First canonical consumer contract: continuity context

The first app-agnostic contract exposed by the capability is:

- `stfx_memory.continuity_context`

Purpose:

- provide a deterministic symbolic carry-forward payload for any downstream app
- expose branch continuity without embedding app-specific story or scenario logic
- give consumers a stable contract that can be translated into panels, scenes, chronicles, or other app-layer outputs

Request shape:

```json
{
  "document_id": "stfxmem_doc_001",
  "chunk_path": "chapter_2.section_1",
  "depth": 2,
  "sibling_window": 2
}
```

Response shape:

```json
{
  "ok": true,
  "contract_type": "stfx_memory.continuity_context",
  "contract_version": 1,
  "document": {
    "document_id": "stfxmem_doc_001",
    "title": "example_document",
    "root_seed_family": "primary"
  },
  "target": {
    "document_id": "stfxmem_doc_001",
    "chunk_path": "chapter_2.section_1",
    "summary": "Threshold negotiation",
    "seed_family": "transitional",
    "selection_rationale": "Chosen for strongest contrast in this branch.",
    "source_ref": {"kind": "file", "path": "workspace/stfx_memory/sources/..."}
  },
  "lineage": [
    {"path": "chapter_2", "summary": "Assembly", "seed_family": "primary"},
    {"path": "chapter_2.section_1", "summary": "Threshold negotiation", "seed_family": "transitional"}
  ],
  "sibling_context": [
    {"path": "chapter_2.section_2", "summary": "Counter-movement", "seed_family": "alternating"}
  ],
  "symbolic_context": {
    "root_seed_family": "primary",
    "target_seed_family": "transitional",
    "expansion_depth": 2,
    "matrix_shape": [64, 64],
    "complementarity_verified": true
  },
  "carry_forward": {
    "focus_terms": ["assembly", "threshold", "negotiation"],
    "summary_fragments": ["Threshold negotiation", "Assembly", "Counter-movement"],
    "seed_emphasis": ["transitional", "primary"]
  },
  "provenance": {
    "source_ref": {"kind": "file", "path": "workspace/stfx_memory/sources/..."},
    "origin": "stfx_memory.adapter_contract"
  }
}
```

Normative rules:

- the contract must remain deterministic
- no LLM may be consulted at runtime
- no field may encode app-specific semantics
- the contract may contain symbolic carry-forward cues, but not app-layer decisions
- consumers may use the contract to drive panel generation, scenario continuity, UI inspection, or other app behavior

### 12.2 Example downstream use

Possible consumer uses include:

- a story system converting `carry_forward` into cycle/panel planning inputs
- a scenario system converting `lineage` and `sibling_context` into continuity state
- a UI inspector visualizing `symbolic_context` and branch structure

These uses are downstream translations only. They must not redefine the canonical contract.

### 12.3 App-specific adapters stay outside the canonical capability

- a Stochastic Dreams / `vis_story` adapter may translate `continuity_context` into cycle/panel JSON
- a ScenSyn adapter may translate `continuity_context` into scenario/session continuity data
- a SynPunkt adapter may translate `continuity_context` into browser/inspection views

But the canonical capability itself remains limited to the generic symbolic contract above.

---

## 13) Maturity path

The production goal is not "replace JSON with SQL."  
The production goal is:

**turn the file-backed symbolic prototype into a robust, versioned, service-exposed Synesyn capability without compromising its symbolic transparency.**

### 13.1 Required maturity upgrades over prototype

- fix retrieval correctness for nested chunk paths
- add schema validation
- add atomic writes
- add snapshots and recovery
- add file locking / safe concurrent write behavior
- add structured ingest reports
- add deterministic API surface
- add tests for:
  - complementarity preservation
  - path traversal correctness
  - schema migration safety
  - expansion determinism

### 13.2 Explicit non-goals

- no embeddings
- no vector store
- no semantic ranking backend
- no app-specific schema at canonical layer
- no making substrate or SQL the primary memory ontology

---

## 14) Reference implementation notes

The prototype in:

`stochasticdreams_visualsystem/Artrhythmetic/artrhythmetic-database_system/`

should be preserved as reference material for:

- philosophy
- initial API shape
- proof-of-concept storage model
- prototype ingest/retrieval behavior

It should not be treated as the production home of the capability.

---

## 15) Definition of done

`StfxMemory` is ready as a Synesyn capability when:

- it lives under `services/synesyn_hub/app/stfx_memory/`
- it is callable via dedicated hub routes
- its canonical store remains file-backed and human-readable
- it supports deterministic ingest and expansion
- it preserves rationale and auditability
- it is consumed by apps only through adapters
- it is not hard-coded to Stochastic Dreams or ScenSyn

---

## 16) Short summary

`StfxMemory` is a first-class Synesyn capability with:

- symbolic canonical storage
- deterministic tensor retrieval
- optional ingest-time LLM assistance
- hub-hosted APIs
- optional substrate export
- app-agnostic adapters

The prototype remains reference.  
The production implementation lives in Synesyn proper.  
The philosophy remains STFX-first, not infrastructure-first.

---

## 17) Cross-session continuity via memory document mutation (April 2026)

The STFX memory substrate supports **cross-session continuity** without
new endpoints.  The mechanism:

1. At session end, ScenSyn appends a structured digest (markdown) to the scenario's
   existing memory document (the same file created by `_write_scenario_scaffold_markdown`)
2. The document cache is invalidated, forcing re-ingestion on next startup
3. On next startup, the standard `ingest → get_continuity_state` flow processes
   the updated document (now containing accumulated session history)
4. The continuity service reads the raw `## Session Digests` section and injects
   it as `memory_context.session_history` for prompt consumption

This preserves the layering: the memory capability remains app-agnostic (it just
indexes markdown), while ScenSyn owns the semantic interpretation of session digests.
The mutation is append-only with automatic trimming (max 20 entries).
