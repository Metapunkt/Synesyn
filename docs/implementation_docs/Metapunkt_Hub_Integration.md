# Metapunkt ↔ Synesyn Hub integration (v1)

## Purpose
Metapunkt is the **local-first orchestrator** (runs in Godot). The Synesyn Hub is the **system-of-record** (runs as a local service by default) for:
- durable event logs (LatentSubstrate `events`)
- durable artifacts/entities/relations (LatentSubstrate + artifact store)
- cross-app observability + replay via `/ws/events` + `/substrate/query`

This doc defines the boundary and the concrete integration contract.

## Boundary (what lives where)
- **Godot / Metapunkt (authoritative at runtime)**
  - agent runtime state: BT/FSM runners, blackboards, in-flight tasks, tick scheduling
  - tool execution: calls into app integrations (`SynTreeInterface`, `GodotUtilsInterface`, etc.)
  - local control plane: SLOP endpoints (`/agents`, `/actions`, `/tools`, `/models`, `/tasks`) for localhost UI/dev tooling
- **Hub (system-of-record)**
  - durable audit + orchestration event stream (substance, not UI state)
  - durable artifacts produced by tools/jobs (including tool-call results that create artifacts)
  - durable session metadata and provenance fields used by policy gates (e.g. voice consent)

Rule of thumb:
- If it must survive app restarts and support replay/query/export → **Hub**
- If it must run at frame-rate and drive gameplay/editor state → **Godot**

## Event contract
Metapunkt emits canonical orchestration events via Hub substrate:
- `tool.call`, `tool.result`, `tool.error`
- `agent.spawned`, `agent.stopped`
- `agent.action` (high-level action envelope)

These are forwarded best-effort to `POST /substrate/events`.

### Hub WS subscription (optional)
If orchestration should react to sensors/jobs:
- Metapunkt may connect to Hub WS: `GET /ws/events`
- It may send:
  - `{"type":"subscribe","event_types":[...]}`
  - `{"type":"replay","window_sec":..., "event_types":[...]}`
- It should treat Hub connectivity as **optional** (degrade gracefully).

## Versioning
Metapunkt should treat the hub as versioned and introspectable:
- `GET /health` for capability flags
- `GET /version` for hub version + schema versions

Metapunkt’s own localhost control plane should expose:
- `GET /status` (already)
- `GET /version` (recommended) including API version + schemas
- `GET /roles` and `POST /roles` for role/tool policy (local override + optional hub artifact publish)

## Provenance expectations (v1)
For tool call events, Metapunkt should include:
- **input references**: `session_id`, `turn_id`, and (when applicable) `workflow_id`, `prompt_chain_id`, etc.
- **output identifiers**: artifact ids/uris returned by tools or created via hub substrate endpoints
- **model/workflow stamps**: model id/provider where available, and workflow/version ids where applicable

## Security stance (local-first default)
- Metapunkt SLOP server is localhost-only in v0/v1.
- Hub auth is pluggable; local mode should work without auth.
- If hub auth is enabled, Metapunkt should send `Authorization: Bearer <token>` (future).

---

## Capability Packs: provenance + system-of-record expectations

Metapunkt “Capability Packs” (installable skills/modules) should be treated as part of the **system-of-record** story. If a session outcome depends on a pack, we should be able to replay/explain:
- which pack(s) were installed
- which versions were enabled
- which permissions/secrets scopes were granted (names/scopes only; never secret values)
- which tools were invoked from which pack

### Event expectations (recommended)
When packs are installed/configured/enabled, Metapunkt should emit substrate events (best-effort) such as:
- `capability.pack_installed`
- `capability.pack_removed`
- `capability.pack_enabled`
- `capability.pack_disabled`
- `capability.pack_config_updated`

Minimum recommended fields:
- `pack_id`, `pack_version`
- `capability_id` (when applicable)
- `actor` / `user_id` (if identity is available)
- `correlation_id` (so pack actions can be tied to subsequent tool calls)

### Tool call provenance (required for correctness)
For any tool call originating from a pack capability, the tool call audit/provenance should include:
- `pack_id`, `pack_version`, `capability_id`
- standard tool-call correlation ids (session/turn/call/workflow) as already required

This ensures downstream artifacts can be attributed to the correct capability implementation.

### Artifact expectations (recommended)
To support replay and export, Metapunkt should publish a pack manifest snapshot as an artifact when a pack is enabled for a workspace/session:
- `metapunkt.capability_pack_manifest.v1` (artifact schema name suggestion)

The artifact should include:
- the `pack.json` manifest content
- an install fingerprint (checksum of installed pack directory or manifest + schemas)
- timestamps + actor id (when available)

Important:
- store only **secret names** and permission scopes; never store secret values.


