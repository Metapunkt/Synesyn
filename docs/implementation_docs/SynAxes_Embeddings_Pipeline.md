# SynAxes embeddings pipeline (v1 plan)

## Goal
Make SynAxes projections/clusters/bridges/hubs reproducible and substrate-backed by introducing **explicit embedding artifacts** produced by hub jobs, instead of per-run random vectors.

## Boundary
- **SynAxes (Godot UI)**: selects dataset, requests jobs, previews results, and performs explicit commits for any “meaningful”/publishing actions.
- **Hub jobs**: perform compute and persist outputs as artifacts with provenance.

## Canonical artifacts (proposal)
- **Embeddings**
  - `embeddings.text` — `{schema_version, dim, vectors:{item_id:[...]}}`
  - `embeddings.image` — same shape; vectors derived from image references (hash/uri) or image bytes (future)
- **Downstream analytics**
  - `coords.projection_2d/3d`
  - `graph.cluster_result`
  - `graph.bridge_result`
  - `graph.hub_result`
- **Run record**
  - `json.analysis_run` — includes all inputs, parameters, and output artifact ids (no overwrites; new version per run)

## Hub job types (v1 contract)
- `synaxes.embed_text`
  - input: `item_ids[]`, `texts[]`, `dim`
  - output: `embeddings.text`
- `synaxes.embed_image`
  - input: `item_ids[]`, `image_refs[]`, `dim`
  - output: `embeddings.image`
- `synaxes.project`
  - input: `item_ids[]`, `vectors[]`, `dim`, `method`
  - output: `coords.projection_2d/3d`
- `synaxes.cluster`
  - input: `coords` (or `item_ids+vectors`)
  - output: `graph.cluster_result`
- `synaxes.bridges`
  - input: `coords`, `labels` (item_id → cluster_id)
  - output: `graph.bridge_result`
- `synaxes.hubs`
  - input: `coords`, `k`
  - output: `graph.hub_result`

Each job emits `job.progress` with `stage/phase/percent` and persists the output artifact with provenance.

## Next upgrade (real embeddings)
Current `synaxes.embed_*` is a deterministic placeholder to stabilize the contract. Next steps:
- Add a real embedding backend (local-first default, hub-managed) and keep the artifact shape identical.
- Add caching keyed by `(text_hash, model_id, dim)` / `(image_hash, model_id, dim)` to avoid recompute bloat.
- Record the embedding model/provider/version in artifact provenance (`metadata.provenance`).


