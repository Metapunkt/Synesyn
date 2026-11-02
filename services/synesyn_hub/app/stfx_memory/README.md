# STFX Memory

Synesyn-native symbolic memory capability built on the STFX (Seed-to-Field Expansion) kernel.

Canonical implementation home:

- `synesyn/services/synesyn_hub/app/stfx_memory/`

Canonical design references:

- `synesyn/docs/implementation_docs/STFX_Memory_Capability_Spec.md`
- `synesyn/implementation_tracking/active/07_Artrhythmetic_Memory.md`

Core commitments:

- deterministic seed-based retrieval
- file-backed canonical storage
- no embeddings or vector store
- ingest-time-only LLM assistance
- app-agnostic API surface

Current scaffold includes:

- seed registry
- Boolean tensor expansion engine (`stfx_core`)
- file-backed workspace store
- workspace-local source copy store
- headings-based ingest
- chunk-path retrieval
- ingest report export
- seed registry export
- hub routes under `/stfx-memory`
- app-agnostic continuity contract at `/stfx-memory/context/continuity`

Workspace behavior:

- canonical state lives under `<workspace>/stfx_memory/`
- ingested source documents are copied into `<workspace>/stfx_memory/sources/`
- switching Synesyn workspaces yields a separate memory store for each project/session

Consumer contract:

- `stfx_memory.continuity_context` is the canonical adapter-facing payload
- it exposes branch lineage, sibling context, symbolic expansion metadata, and carry-forward cues
- apps translate that payload into their own story, scenario, or UI-layer structures
