# Hub API

The normative specification for all Hub endpoints and payloads is
[`Synesyn_Hub_API_Spec.md`](../implementation_docs/Synesyn_Hub_API_Spec.md). This
page is a short index of the endpoints and conventions client code touches most
often.

## Authentication

- Optional Bearer authentication: `Authorization: Bearer <token>`
- Configured in `Documents/Synesyn/synesyn/config/synesyn_client.json` under
  `hub.base_url`, `hub.auth.enabled`, and `hub.auth.token`.

## Render job endpoints

Used by SynPunkt and ScenSyn when routing renders through the Hub:

- `POST /render/submit`
- `GET /render/jobs/{job_id}`
- `GET /render/jobs?limit=...`
- `POST /render/jobs/{job_id}/cancel`
- `POST /render/jobs/{job_id}/retry`

## Artifact metadata updates

- `PATCH /substrate/artifacts/{artifact_id}/metadata`

Used by clients to update UI-facing metadata on an existing artifact (for example
setting a display name) without mutating the artifact payload itself:

```json
{
  "metadata": { "ui": { "display_name": "Render 0042" } },
  "merge": true
}
```

This endpoint applies to all artifact types.

### Render job type and WebSocket events

Hub job type:

- `render.comfyui`

Hub render lifecycle events streamed over `/ws/events`:

- `render.queued`
- `render.started`
- `render.progress`
- `render.completed`
- `render.failed`


