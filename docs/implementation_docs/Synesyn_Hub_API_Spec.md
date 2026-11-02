# Synesyn Hub — API Specification (Local-first, v0)

**Status**: Draft-but-normative for implementation  
**Audience**: Hub + Godot client implementers (ScenSyn, SynTree, SynPunkt, SynAxes)  
**Goal**: Prevent ambiguity by specifying endpoints, schemas, and expected behaviors.

---

## 1) Transport and ports

### 1.1 Local hub defaults
- **HTTP**: `127.0.0.1:17777`
- **WebSocket**: `ws://127.0.0.1:17777/ws/events`
- **SSE (optional alternative)**: `http://127.0.0.1:17777/sse/events`

All ports are configurable via `services/synesyn_hub/app/config.yaml`.

### 1.2 Sensor ingestion defaults
- **UDP ingestion**: `0.0.0.0:5000` (configurable)

Sensors send UDP JSON packets to the hub; the hub normalizes and republishes.

---

## 2) Auth modes (must be supported, even if minimal)

### 2.1 Local mode (default)
- No auth required on `127.0.0.1`.
- Hub must refuse non-local interfaces unless explicitly configured (safety default).

### 2.2 SaaS/remote mode (future)
- Bearer tokens (`Authorization: Bearer <token>`)
- Device tokens for kiosks (device-code or pre-provisioned token)

**Note**: Implement local mode first; keep auth middleware pluggable.

---

## 3) Health, status, and diagnostics

### GET `/health`
Returns liveness + basic module readiness.

Response (200):
```json
{
  "ok": true,
  "version": "0.1.0",
  "uptime_sec": 1234,
  "time_utc": "2025-12-19T00:00:00Z",
  "capabilities": {
    "substrate": true,
    "ws_events": true,
    "udp_ingest": true,
    "voice_tts": true,
    "voice_stt": true,
    "synaxes_jobs": false,
    "render_submit": false
  }
}
```

### GET `/status`
Returns operational stats used by the Godot “Services” UI.

Response (200):
```json
{
  "ok": true,
  "udp": { "port": 5000, "sources": { "pendulum_cam": { "last_seen_ms": 32, "seq": 8841 } } },
  "event_bus": { "clients": 2, "ring_buffer_events": 2048 },
  "storage": { "backend": "sqlite", "path": "data/substrate.db", "queue_depth": 3 },
  "voice": {
    "tts": { "provider_chain": ["edge_tts", "sapi"], "edge_tts_self_test_ok": true },
    "stt": { "engine": "whisper", "ready": false, "reason": "optional_dependency_missing" }
  },
  "workspace": { "name": "Local Test", "slug": "local_test" }
}
```

---

## 4) Workspace management (local-first UX)

The hub persists a “current workspace” so clients can reliably restart without user re-selection each launch.

### GET `/workspace`
Returns the active workspace selection (if any).

### POST `/workspace/select`
Sets the active workspace (and persists it).

---

## 5) Event stream (hub → clients)

### WebSocket: `GET /ws/events`
Purpose: realtime low-latency updates for Godot and other clients.

#### 4.1 Client → server messages
- `subscribe` (optional filter)
```json
{ "type": "subscribe", "event_types": ["sensor.*", "render.*", "session.*"] }
```

- `replay` (request ring-buffer replay window)
```json
{ "type": "replay", "since_event_id": "evt_...", "max_events": 500 }
```

#### 4.2 Server → client event envelope (normative)
```json
{
  "schema_version": "1",
  "event_id": "evt_01J...",
  "event_type": "sensor.pendulum",
  "source_id": "pendulum_cam",
  "seq": 8842,
  "t_device": 1766188800.123,
  "t_hub_received": 1766188800.456,
  "payload": { "bias": 0.12, "stability": 0.77 },
  "provenance": {
    "session_id": "sess_...",
    "artifact_id": null
  }
}
```

#### 4.3 Backpressure + drop policy
- Hub must maintain an in-memory **ring buffer** (configurable size).
- If a client falls behind:
  - Hub may drop events for that client (do not stall realtime for others).
  - Client is expected to request replay or resync via substrate queries.

---

## 6) Sensor ingestion (sensors → hub)

### UDP JSON packets
Sensors send a JSON object. Hub normalizes into the event envelope above.

Recommended sensor payload structure:
```json
{
  "source_id": "pendulum_cam",
  "seq": 8842,
  "t_device": 1766188800.123,
  "type": "pendulum",
  "payload": { "bias": 0.12, "stability": 0.77 }
}
```

Normalization rules:
- `event_type` becomes `sensor.<type>` (e.g., `sensor.pendulum`)
- `t_hub_received` is added by the hub
- packets missing `seq` must be assigned monotonic sequence per `source_id`

---

## 7) LatentSubstrate CRUD (hub as system-of-record)

All substrate resources must include provenance metadata where applicable.

### POST `/substrate/sessions`
Create a session.

### POST `/substrate/events`
Persist an event (normally hub persists sensor + turn events automatically; clients may also submit).

### POST `/substrate/artifacts`
Persist an artifact (text, image ref, JSON blob, etc.).

Workshop Catalyst initially commits `json.workshop_transcript_segment`,
`json.workshop_specialist_trace`, `ui.workshop_summary`,
`ui.workshop_thinking_map`, and `ui.workshop_path_set` through this generic
artifact route. No Workshop-only route is required while generic commit,
version lineage, and retrieval meet the contracts in
`LatentSubstrate_Data_Model.md`. A dedicated summary, map, or path route may be
added only with a matching client, server, normative contract, compatibility
reader, and test update.

For `json.workshop_transcript_segment`, the Hub validates the schema-v1 fields,
immutable original/correction relationship, consent/retention consistency, and
absence of embedded credentials or raw audio. The compatibility reader accepts
the drafted `captured_at` timestamp alias and normalizes it to
`capture_started_at` plus `capture_completed_at`; it never rewrites an existing
artifact. Invalid Workshop transcript payloads return `400`. Client commits are
best-effort and asynchronous from the live conversation: an unavailable Hub
must be shown as degraded retention and must not block or retract the local turn.

For `json.workshop_specialist_trace`, the Hub validates schema version 1,
session/turn identity, ordered specialist roles and concise contribution records,
model/timestamps, the Session Record synthesis reference, generation status, and
session-scoped revocable retention. Privacy flags must explicitly confirm that
credentials and chain-of-thought are absent, and sensitive embedded fields are
rejected with `400`. A degraded generation requires a failure reason. The live
client submits the trace with `persistence_status: pending`; Hub failure remains
best-effort and cannot block or retract the synthesized response.

For `ui.workshop_summary`, the Hub validates schema version 1, session and
facilitator-review status, all five reviewed item arrays, globally unique stable
item ids, provenance objects/references, proposal decisions, closure references,
and string `previous_version_id` lineage. Only `accepted`, `edited`, `rejected`,
and `deferred` proposal decisions are valid. Embedded credentials and duplicate
item ids are rejected with `400`. The generic route always creates a new
immutable artifact id; it never patches an earlier summary. The Godot client
must invoke this route only after explicit Preview and Commit, and retain a
failed payload for non-blocking retry.

For `ui.workshop_thinking_map`, the Hub validates product schema version 1,
Shared Graph Workspace envelope version 1, the exact
`graph_kind: workshop_thinking_map` discriminator, Workshop Session
Type/Collection references, stable unique node/edge ids, controlled WC node and
relationship vocabularies, endpoint integrity, review states, provenance
references, source-class labels, proposal decisions, facilitator provenance,
and string `previous_version_id` lineage. It rejects `context_graph` payloads at
this seam and rejects AI-inferred nodes relabelled as participant statements.
The Godot client retains a failed reviewed payload for retry and does not advance
map lineage until the generic artifact route returns a new artifact id.

For `ui.workshop_path_set`, the Hub validates schema version 1, Workshop
Session Type/Collection identity, facilitator-review status, unique stable path
ids, complete path fields, controlled review and evidence states, and exactly one
explicit do-nothing path. An unsourced path must state `none`, `degraded`, or
`unavailable`; it cannot claim supporting evidence. The selection must reference
reviewed paths in the same comparison, and a combined selection requires at
least two paths. The Hub also validates facilitator provenance, retrieval
metadata, string store trace ids, and `previous_version_id`. The artifact payload
cannot pre-claim a ClosureBus reference. After Hub success, Godot emits the
separate explicit ClosureBus action. A failed closure delivery retains the Hub
artifact id for delivery-only retry and does not advance local committed
lineage.

### PATCH `/substrate/artifacts/{artifact_id}/metadata`
Partially updates artifact metadata (generic for all artifact types, not render-only).

Request:
```json
{
  "metadata": {
    "ui": { "display_name": "Shot 014" }
  },
  "merge": true
}
```

Response (200):
```json
{
  "ok": true,
  "id": "art_...",
  "metadata": {
    "ui": { "display_name": "Shot 014" }
  }
}
```

Notes:
- With `merge=true`, the hub deep-merges the patch into existing metadata.
- This endpoint is intended for post-hoc UI annotations (labels/names) without changing artifact id/uri/hash.
- For missing artifact ids, return `404`.

### POST `/substrate/entities`
Create/update an entity (concept, character, node, cluster).

### POST `/substrate/relations`
Create/update a relation (typed edge).

### POST `/substrate/query`
Query by:
- session id / time range
- entity type
- relation type
- tags
- provenance constraints (model/workflow version)

**Note**: Exact storage schema is defined in `LatentSubstrate_Data_Model.md`. This API can be implemented as a thin wrapper over that schema.

---

## 7A) STFX Store (canonical memory substrate)

STFX Store is the file-backed canonical memory substrate. Canonical records are the truth layer; indexes are generated accelerators that can be rebuilt.

Mounted under `/stfx-store`:

- `GET /status`
- `POST /config`
- `GET /sources`
- `GET /memories`
- `GET /closures`
- `GET /context-packs`
- `POST /sources/ingest`
- `POST /retrieve`
- `GET /traces/{trace_id}`
- `GET /context-packs/{context_pack_id}`
- `GET /indexes/{index_name}`
- `GET /chunks/{chunk_id}`
- `POST /chunks/{chunk_id}/symbolic`
- `POST /artifacts/commit`
- `POST /context-graphs/commit`
- `POST /memories/commit`
- `POST /closures/commit`
- `POST /indexes/rebuild`
- `POST /validate`
- `POST /repair/report`
- `POST /migrations/stfx-memory/export`
- `POST /migrations/syntree-context-graphs/export`
- `POST /migrations/substrate-artifacts/export`

Record contracts are defined in `STFX_Memory_Capability_Spec.md` and `implementation_tracking/active/09_Artrhythmetic_Store.md`.

---

## 7) Jobs (“dreaming”, SynAxes compute)

### POST `/jobs`
Submit a job:
```json
{
  "type": "synaxes.cluster",
  "input": { "entity_ids": ["ent_..."], "method": "umap+dbscan" },
  "output_target": { "session_id": "sess_...", "collection": "dreaming_2025-12-19" }
}
```

### WebSocket events
Jobs publish:
- `job.queued`, `job.started`, `job.progress`, `job.completed`, `job.failed`

`job.completed` must reference created artifact ids in `provenance`.

---

## 8) Voice (SynTree Voice) — TTS + STT

This API is owned conceptually by **SynTree Voice**, but exposed by the hub as a single local endpoint.

### 8.1 POST `/voice/speak` (TTS)
```json
{
  "text": "Hello.",
  "character": "Narrator",
  "character_mapping": {
    "source": "user://syntree_voice/character_voices.json",
    "version": 3,
    "character": "Narrator",
    "voice": "en-US-AriaNeural"
  },
  "voice": {
    "name": "en-US-AriaNeural",
    "rate": "+0%",
    "volume": "+0%",
    "pitch": "+0Hz"
  },
  "format": "wav",
  "return_lipsync": true,
  "session_id": "sess_..." 
}
```

Response (200):
```json
{
  "ok": true,
  "audio_artifact_id": "art_...",
  "audio_url": "file://.../artifacts/audio/tts/art_....wav",
  "lipsync_artifact_id": "art_...",
  "lipsync_url": "file://.../artifacts/json/lipsync/art_....json",
  "duration_sec": 1.23,
  "voice_used": "en-US-AriaNeural",
  "voice_params_used": { "name": "en-US-AriaNeural", "rate": "+0%", "volume": "+0%", "pitch": "+0Hz" }
}
```

Notes:
- This endpoint follows **Option A** (file-backed artifacts). Do not return base64 audio by default.
- `lipsync_artifact_id` should reference a `json.lipsync` artifact (if `return_lipsync=true`).
- The hub must persist provenance for `audio.tts` (and lipsync, if generated): engine/model versions, parameters, and input text hash.
- `character_mapping` is optional but recommended when a character→voice mapping table is in play (auditability).
- A blank or omitted `voice.name` is spoken as `en-US-AriaNeural`. A client that has resolved a scenario voice sends that id on this request. Reading the id afterwards from a shared mapping is how a speaker's first line was spoken as the default ([ADR 0031](../architectural-decisions/0031-spoken-line-carries-its-resolved-voice.md)).
- **Packaging topology note**: the hub may compute via built-in providers OR proxy compute to a hub-managed sidecar; either way the hub persists artifacts + provenance.

### 8.2 POST `/voice/transcribe` (STT)
Transcribe speech audio to text.

Request:
```json
{
  "audio_base64": "<base64-audio-bytes>",
  "audio_format": "wav",
  "language": "en",
  "save_recordings": false,
  "session_id": "sess_...",
  "character": "Narrator",
  "character_mapping": {
    "source": "user://syntree_voice/character_voices.json",
    "version": 3,
    "character": "Narrator"
  }
}
```

Response (200):
```json
{
  "ok": true,
  "text": "Transcribed text goes here.",
  "transcript_artifact_id": "art_...",
  "transcript_url": "file://.../artifacts/text/transcript/art_....txt",
  "recording_artifact_id": null,
  "model_used": "whisper-base"
}
```

Privacy defaults (normative):
- **Store transcript only by default** (`save_recordings=false`).
- Persist the transcript as a `text.transcript` artifact with provenance (model/version, parameters, input-audio hash).
- Even when recordings are not saved, the hub should compute and store an input-audio hash for traceability/dedupe.
- Only store raw audio as `audio.input` if:
  - `save_recordings=true`, AND
  - the session/workspace has recorded explicit consent for saving recordings.

### 8.3 Optional helper endpoints (v1)
- `GET /voice/voices` (enumerate available voices)
- `GET /voice/characters` (list character voice mapping)
- `POST /voice/set_character_voices` (runtime update of mapping)

---

## 9) Rendering (ComfyUI integration)

Two supported modes:
- **Client-direct**: Godot connects to ComfyUI directly (SynPunktRenderBridge).
- **Hub-submit (optional)**: hub submits jobs to ComfyUI for batch/non-interactive pipelines.

If hub-submit is enabled:
- POST `/render/submit`
- events `render.queued|started|progress|completed|failed`
- outputs persisted as artifacts with provenance: workflow hash + seed + model versions.


