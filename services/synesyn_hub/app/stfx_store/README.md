# STFX Store

STFX Store is the file-backed canonical substrate for Synesyn memory.

Core rule:

```text
Canonical files are the memory truth.
Generated indexes are disposable accelerators.
```

The store is intentionally inspectable. A human should be able to open the workspace folder, inspect source/chunk records, read retrieval traces, repair canonical records, rebuild indexes, and rerun retrieval without trusting an opaque database or vector index.

## Workspace Layout

```text
stfx_store/
  store_manifest.json
  sources/
  memories/
  closures/
  artifacts/
  traces/
  ingest_reports/
  repair_reports/
  indexes/
```

`indexes/` is generated. It can be deleted and rebuilt from canonical records.

## Current v0.1 Capabilities

- Markdown/text source ingest.
- Canonical `source.json` records.
- Per-chunk JSON records with spans, headings, symbolic fields, and rationale.
- Canonical memory records with symbolic address, related source/chunk links, rationale, repair notes, and provenance.
- Canonical closure records with selected sources/chunks/memories, symbolic constraints, human commit metadata, and provenance.
- Ingest reports.
- Reviewable LLM-assisted ingest recommendations for chunking, summaries, seeds, nesting, and rationales.
- Generated symbolic, lexical, relation, vector, external-vector manifest, and SQLite mirror indexes.
- Symbolic index sections for chunk seeds/tensions, memory seeds/tensions, memory related ids, and closure selected ids.
- Runtime-configurable Store/accelerator flags in the Store manifest.
- Process-local reentrant write guard for mutating Hub store operations.
- Retrieval traces and context packs.
- Repair reports that validate canonical records, generated index freshness, and trace references.
- Relation-neighborhood candidate discovery from generated relation indexes.
- Optional SynTree context path for local file-backed active sources.
- Optional SynTree `ui.context_graph` mirroring into the store.
- Optional SynTree chat output commits with trace/context-pack provenance.
- SynTree "Open Store Trace" affordance for the latest store-backed chat context.
- SynTree inline trace viewing, canonical chunk opening, symbolic metadata repair, and "Store Repair" affordances.
- ScenSyn continuity-state adapter for context packs.
- Explicit ScenSyn `json.scensyn_continuity_context` artifact commits for store-context loads.
- SynAxes `ui.closure` commit bridge into canonical Store closure records.
- Optional ScenSyn captured-closure mirror into Store closure records.
- SynPunkt browsing affordances for Store closure records and context packs.
- SynPunkt Atlas binding that performs loaded Store records as field/collapse/twin visual surfaces using symbolic constraints where available.
- SynAxes generated Store index consumption for symbolic, relation, and vector datasets.
- ReadyMade context-pack consumption and generated-output commits with trace links.
- Migration/export reports for legacy STFX Memory documents, SynTree context graphs, and substrate artifact mirrors.

## Hub Routes

Mounted under `/stfx-store`:

- `GET /status`
- `POST /config`
- `GET /sources`
- `GET /memories`
- `GET /closures`
- `GET /context-packs`
- `POST /sources/ingest`
- `POST /indexes/rebuild`
- `GET /indexes/{index_name}`
- `POST /retrieve`
- `GET /traces/{trace_id}`
- `GET /context-packs/{context_pack_id}`
- `GET /chunks/{chunk_id}`
- `POST /chunks/{chunk_id}/symbolic`
- `POST /artifacts/commit`
- `POST /context-graphs/commit`
- `POST /memories/commit`
- `POST /closures/commit`
- `POST /validate`
- `POST /repair/report`
- `POST /migrations/stfx-memory/export`
- `POST /migrations/syntree-context-graphs/export`
- `POST /migrations/substrate-artifacts/export`

ScenSyn also exposes:

- `POST /scensyn/continuity-state/from-store-context`

That endpoint converts an STFX Store context pack into ScenSyn's existing `scensyn.scenario_continuity_state` contract. Trace and context-pack references are preserved in the continuity state's provenance and `memory_context`.

When requested with `commit_artifact=true`, the same endpoint also commits a `json.scensyn_continuity_context` artifact to STFX Store. The Godot `ScenSynContinuityService.load_store_context_pack_into_story_state()` helper requests this by default and passes the current ScenSyn session id.

## SynTree Opt-In

SynTree can append STFX Store context packs to chat prompts when enabled in the client runtime config:

```json
{
  "apps": {
    "syntree": {
      "use_stfx_store_context": true,
      "publish_context_graph_to_stfx_store": true,
      "stfx_store_top_k": 5,
      "stfx_store_expansion_depth": 1,
      "stfx_store_default_seed": "primary"
    }
  }
}
```

This path is best-effort. It only ingests local file-backed active sources that the Hub can read. Direct SynTree ContentBus context injection remains the fallback.

After a store-backed chat response, SynTree keeps the latest `trace_id` and `context_pack_id` in its conversation manager. The Store buttons can open the trace folder, view the trace/context pack inline, open the first selected canonical chunk folder, and write a reviewed symbolic repair note back through the Hub.

The `Store Repair` button runs the first maintenance loop through the Hub: validate canonical records, write a repair report, rebuild generated indexes, and summarize the report id plus source/chunk counts in the SynTree status strip.

## Closure Bridges

SynAxes explicit `Commit Closure` writes the existing `ui.closure` artifact and then best-effort mirrors it into `stfx_store/closures/` with symbolic constraints, selected artifact ids, human commit metadata, and provenance.

ScenSyn captured closures can also mirror into Store closure records when `apps.scensyn.publish_closures_to_stfx_store` is enabled. The default is `false` so live workshop capture remains substrate-only unless the workspace opts into the memory bridge.
