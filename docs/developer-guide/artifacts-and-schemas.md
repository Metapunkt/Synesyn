# Artifacts and schemas

Synesyn is artifact-first. Artifacts are stored on the Hub and referenced by artifact ID.

This page is a navigation summary. Normative entity, relation, artifact,
provenance, and versioning rules live in the
[`LatentSubstrate Data Model`](../implementation_docs/LatentSubstrate_Data_Model.md);
transport payloads live in the
[`Hub API Spec`](../implementation_docs/Synesyn_Hub_API_Spec.md).

## “Read-only” vs “editable”

- **SynAxes closures (`ui.closure`)**: read-only snapshots; never overwritten.
  - `schema_version` 1 (integer): name, intent, selection, time_window.
  - `schema_version` 2: adds `orientation` `{quadrant, label, map_version}`
    (Closure Map A–D). See
    [`../concepts/closure-map.md`](../concepts/closure-map.md) and
    ADR 0015.
- **Session captures (`ui.workshop_closure`)**: what a room committed during a
  session — `schema_version` 1 (integer), `session_type_id`, `kind`, `statement`,
  `outcome`, `human_commit`, plus optional owner, confidence and vote fields.
  Written by ScenSyn's closure bus.
- **SynDocs (`ui.syndoc`)**: edited and saved as new artifacts/versions.

The two closure types are **not interchangeable**, and the hub rejects a payload
written under the wrong one. Captures were stored as `ui.closure` before ADR 0026,
so artifacts from then may still carry that type; a capture is recognisable by
having a `statement` and no `selection`. Both validators live in
`services/synesyn_hub/app/substrate/closure_artifacts.py`.

## Rendering contract (client ↔ hub ↔ ComfyUI)

Canonical render request schema:

- `SynesynRenderRequestV1` (normalises and validates render requests)
  - Godot: `synesyn_client/addons/synesyn_core/scripts/synesyn_render_request_v1.gd`

Related artifact types:

- `json.workflow`
- `json.render_request`
- `json.render_recipe`
- `image.generated`

## Cross-application render entrypoint

Clients submit renders through a shared service in `synesyn_core`:

- `SynesynRenderService.submit_render_request(...)`
  - Godot: `synesyn_client/addons/synesyn_core/scripts/synesyn_render_service.gd`
  - Routing modes:
    - `routing.mode == "direct"` → direct ComfyUI submission from the client
    - `routing.mode == "hub"` → Hub `POST /render/submit` (asynchronous job and WebSocket events)


