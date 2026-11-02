# To‑Do — Metapunkt (Orchestrator)

**Primary spec references**
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Synesyn_Hub_API_Spec.md` (for hub integration)
- `../LatentSubstrate_Data_Model.md` (for audit/provenance expectations)

**What’s already covered / existing**
- Metapunkt already exists as a working Godot addon with:
  - multi-agent orchestration
  - SLOP-style HTTP server endpoints
  - LimboAI integration (BT runners)
  - memory + audit logger foundations  
  See `synesyn/synesyn_client/addons/metapunkt/README.md`.

---

## Priority guide
- **v0 MVP**: keep existing behavior working; add hub adapter + write audit/events/artifacts to substrate; minimal permission hardening.
- **v1**: harden SLOP API, richer role/permission controls, cleaner runner lifecycle, better observability.
- **later**: multi-tenant/SaaS auth, enterprise-grade policy packs, deeper compliance tooling.

## A) Clarify Metapunkt’s boundary vs the Synesyn Hub
- [x] (v0) Decide and document: which state lives in Godot vs in the hub (system-of-record). (See `../Metapunkt_Hub_Integration.md`)
- [x] (v0) Ensure Metapunkt writes session/audit artifacts into LatentSubstrate (via hub) rather than only local ad-hoc logs.
- [x] (v0) Define “orchestration event” types to publish (e.g., `session.turn`, `agent.action`, `tool.call`).

## B) Hub adapter (“Tool routing to hub”)
- [x] (v0) Add a Metapunkt tool adapter for Hub calls:
  - [x] (v0) publish events to hub (optional `POST /substrate/events`)
  - [x] (v0) store artifacts/entities/relations via substrate endpoints
  - [x] (v1) subscribe to hub WS events (if orchestration reacts to sensors/jobs)
- [x] (v0) Standardize error handling (hub down = degrade gracefully via best-effort posting).

## C) SLOP API hardening (for API-first future)
- [x] (v0) Keep Metapunkt’s SLOP server strictly localhost-only (bind to `127.0.0.1`).
- [x] (v0) Add basic request parsing hardening (header/body size limits + body read timeout).
- [x] (v0) Add consistent request/response envelope conventions (via `HTTPResponse.send_ok/send_fail`).
- [x] (v0) Add a stable `GET /status` response (service/api/version/modules).
- [x] (v1) Confirm stable endpoint surface (`/agents`, `/actions`, `/tools`, `/models`, `/tasks`) and versioning (`/version`).
- [ ] (later) Add authorization hooks (no-op local mode; pluggable SaaS mode).

## D) Decision logic runners (LimboAI + beyond)
- [x] (v0) Audit runner lifecycle correctness (add-to-tree ordering, cleanup on reassignment).
- [x] (v0) Provide a clean “tick loop contract” for AgentManager with deterministic scheduling.
- [ ] (v1) Document runner config schema conventions (e.g., `{"path": ..., "config": ...}`).

## E) Role/permission model (for client deployments)
- [x] (v0) Formalize roles (developer/roleplay/facilitator/system) and allowed tool scopes.
- [x] (v0) Enforce tool allowlists per role; log denied actions to audit.
- [x] (v1) Make role config exportable as a resource/artifact (persist to substrate for traceability).
  - [x] (v1) Add `/roles` endpoint to view/update role policy and optionally publish to hub as an artifact.

## F) AuditLogger → substrate provenance
- [x] (v0) Normalize audit events into LatentSubstrate `Event` + `Artifact` forms.
- [x] (v0) Add provenance for tool calls:
  - [x] (v0) input references (session/turn/call/workflow ids)
  - [x] (v0) output artifact ids/uris (best-effort extraction)
  - [x] (v0) model/workflow version stamps (best-effort from ctx/args)

### Notes (implemented in code)
- **SLOP envelope + /status + localhost-only + size/time limits**:
  - `synesyn/synesyn_client/addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd`
  - `synesyn/synesyn_client/addons/metapunkt/Networking/SLOPServer/HTTPServer.gd`
  - `synesyn/synesyn_client/addons/metapunkt/Networking/SLOPServer/EndpointHandler.gd`
  - plus endpoint callers updated to use the envelope: `AgentRegistry.gd`, `ActionDispatcher.gd`, `ToolRegistry.gd`, `ShortTermMemory.gd`, `SensorInterface.gd`
- **Outbound request correlation fix** (safe concurrency): `synesyn/synesyn_client/addons/metapunkt/Memory/LongTermMemoryClient.gd`
- **JSONL + best-effort Hub forwarding** (system-of-record path with local fallback): `synesyn/synesyn_client/addons/metapunkt/Audit/AuditLogger.gd`

## G) “App-first” UX integration hooks
- [x] (v0) Provide minimal UI hooks for apps (ScenSyn/ReadyMade) to:
  - [x] (v0) spawn/stop agents
  - [x] (v0) query agent status
  - [x] (v0) route tool calls
  - [x] (v0) stream orchestration events (in-process signal)

## H) Docs consolidation
- [x] (v0) Add a Metapunkt ↔ Hub integration page to Metapunkt docs, referencing:
  - `../Synesyn_Hub_API_Spec.md`
  - `../LatentSubstrate_Data_Model.md`
  - `../Metapunkt_Hub_Integration.md`

## Metapunkt developer docs (contract pages)
- [x] Synterfaces + Bindings contract: `../Metapunkt_Synterfaces_and_Bindings.md`

---

## L) Capability Packs (v0) — installable skills + 1 UI panel template

Goal:
- Allow end users running an exported Synesyn build (and developers in-editor) to **install, configure, enable, and disable** “Capability Packs” without editing the Godot project.
- Start **tool-first** for safety and simplicity, but include **one UI panel capability** as a reference/template.

Primary spec reference:
- `../Metapunkt_Synterfaces_and_Bindings.md` (Capability Packs section)

### L1) Pack manifest + schema (validation)
- [x] Define a v0 `pack.json` JSON Schema (identity, compatibility, capabilities, permissions, limits).
  - Impl: `addons/metapunkt/Packs/capability_pack_manifest.gd` (`CapabilityPackManifest`)
- [x] Add pack validation rules:
  - [x] manifest must include `id`, `version`, `capabilities[]`, `permissions`
  - [x] capability `type` must be `tool` or `ui_panel` in v0
  - [x] tool capabilities must reference existing `schemas/*.json` for args/results
  - [x] forbid secret values in pack payloads (names only)

### L2) Pack storage model (repo vs installed runtime)
- [x] Define user-facing pack repo path convention (recommended):
  - [x] `Documents/Synesyn/PacksRepo/` (source-of-truth; optional — user copies from here)
- [x] Implement install destination under user data:
  - [x] `user://synesyn/packs/<pack_id>/<version>/...`
  - Impl: `addons/metapunkt/Packs/capability_pack_store.gd` (`CapabilityPackStore`)
- [x] Implement uninstall/remove with safe cleanup (only within `user://synesyn/packs/**`).

### L3) Metapunkt UI: Pack Manager (install/config/enable)
- [x] Add a Metapunkt “Pack Manager” panel:
  - [x] list installed packs + versions + enabled state
  - [x] install from folder (copy/unpack into `user://`)
  - [x] validate manifest + schemas; show actionable errors
  - [x] configure secrets (names only in manifest; values stored separately)
  - [x] permission preview + enable/disable toggles per capability
  - [ ] “test / health check” button per pack (best-effort tool dry-run)

### L4) Secrets + permissions enforcement (runtime)
- [x] Secrets store (local-first) for pack config:
  - [x] values stored outside the pack directory
  - [x] rotation/edit UX (API ready) in Pack Manager
- [x] Enforce pack-declared permissions at runtime:
  - [x] network allowlist (when applicable)
  - [x] filesystem read/write scopes
  - [x] role/tool policy gates remain authoritative (pack permissions are necessary but not sufficient)

### L5) Tool registration + provenance
- [x] Register enabled `tool` capabilities into ToolRegistry at runtime.
- [x] Ensure tool call envelopes include:
  - [x] `pack_id`, `pack_version`, `capability_id`
  - [x] correlation ids (session/turn/call/workflow) as per ToolCallSchema
- [x] Ensure AuditLogger records pack metadata and denied actions.

### L6) UI panel capability (single reference implementation)
- [x] Define a stable “UI mount slot” mechanism in Metapunkt UI (e.g. `tools_panels`).
- [x] Support `ui_panel` capability type:
  - [x] load `scene_path` from installed pack under `user://...`
  - [x] instantiate into the declared mount slot with label/icon metadata
  - [x] panels invoke tools via ToolRegistry (no bypass; inherit policy + audit)
- [x] Provide one reference/demo pack:
  - [x] a simple panel that calls a demo tool (e.g. `demo.echo`) and shows the audited result

### L7) Hub system-of-record integration for packs (best-effort)
- [x] Emit substrate events for:
  - [x] pack installed/removed/enabled/disabled/config updated
- [x] Publish a “pack manifest snapshot” artifact when a pack is enabled for a workspace/session:
  - [x] includes manifest + checksum/fingerprint
  - [x] includes permission scopes + secret names (never secret values)

## I) AgentDefs vNext — Synterfaces + Bindings (“AppHost”) contract (framework alignment)

Goal: make Metapunkt the **single entry point** for agent creation/lifecycle across application-layer apps (ScenSyn, ReadyMade, etc.) without forcing those apps to give up tight scene coupling.

Principles:
- **Metapunkt owns**: agent identity, spawn/stop/status, tick scheduling, tool execution surface, role/tool policy, audit/provenance.
- **Apps own**: domain state + scene coupling, but only via a **standard binding contract** (no bespoke agent systems).
- **Fail fast**: agents must not spawn/run if required ports are missing or malformed (prevents accidental bypass / “Metapunkt redundancy”).

### I1) Schema + data-model (AgentDefinition v1)
- [x] Add `schema_version` to `AgentDefinition` (default: `metapunkt.agentdef.v1`).
- [x] Add synterface requirements to `AgentDefinition`:
  - [x] `required_synterfaces: Array` (string IDs)
  - [x] `synterface_defaults: Dictionary` (optional, schema-specific defaults)
  - [x] `binding_hints: Dictionary` (optional, non-binding hints for host)
- [x] Keep non-LimboAI logic pathways available in AgentDefs UI (as future stubs), but harden `limboai` + `scene_agent` first.

### I2) Synterface catalog (Metapunkt-shipped + extendable)
- [x] Add a Metapunkt **core synterface catalog** (versioned) with:
  - [x] per-synterface description
  - [x] per-synterface JSON Schema (shape contract)
- [x] Define initial core synterfaces (v1 minimum):
  - [x] `conversation_io`
  - [x] `thread_scope`
  - [x] `scene_root`
  - [x] `workplan`
  - [x] `ui_hooks`
- [x] Allow apps to register additional **namespaced** synterfaces (e.g. `scensyn.story_state`, `readymade.workplan`) with:
  - [x] description
  - [x] JSON Schema
- [x] Handle synterface ID collisions:
  - [x] compatible multi-impl (same schema) prefers the active app’s provider; otherwise requires selection
  - [x] conflicts (schema mismatch) require explicit selection
  - [x] persist selection as local override under Documents Synesyn data root

### I3) AppHost contract (autoload; deterministic composition root)
- [x] Define `/root/MetapunktAppHost` as an **autoload contract** (router autoload) for deterministic discovery + binding.
- [x] Provide a base/reference interface with required methods:
  - [x] `get_app_id() -> String`
  - [x] `get_synterface_catalog() -> Dictionary` (custom synterfaces; merged with core catalog)
  - [x] `bind_synterfaces(required_synterfaces: Array, hints: Dictionary) -> Dictionary`
  - [x] `spawn_agent_node(agent_id: String, def: Resource, ports: Dictionary) -> Dictionary` (future; stub exists)
  - [x] `stop_agent_node(agent_id: String) -> Dictionary` (future; stub exists)
- [x] Provide a “null host” behavior: if the autoload is missing, Metapunkt surfaces a clear error and refuses to spawn synterface-requiring agents.
- [x] Router auto-discovers installed app-host providers (no per-app router edits required).

### I4) Enforcement (no silent bypass)
- [x] On agent spawn (via SLOP + in-process hooks):
  - [x] validate `schema_version` at spawn-time (fail-fast; refuses to spawn on unknown schema versions)
  - [x] resolve synterface catalog (core + host/router)
  - [x] validate required synterfaces exist
  - [x] validate host bindings against JSON Schema
  - [x] refuse spawn with actionable error when invalid/missing (including “selection required” when ambiguous)

### I5) AgentDefs UI hardening (developer authoring)
- [x] Update AgentDefs tab to edit and persist:
  - [x] schema_version
  - [x] required_synterfaces (pick-list from catalog + allow namespaced entries)
  - [x] synterface_defaults / binding_hints (JSON editor w/ validation)
- [x] Pre-flight validation on Save/Spawn:
  - [x] logic runner config validity (e.g. LimboAI requires `logic_config.path`)
  - [x] synterfaces validity (exists + schema-valid) + binding preflight
- [x] Provide templates/examples (non-breaking) for:
  - [x] ScenSyn Narrator (template; requires app synterfaces)
  - [x] ReadyMade A1 (template; requires app synterfaces)
- [x] Provide UI for synterface conflict/selection overrides (so non-dev users can resolve collisions).

### I6) Docs (developer-facing contract)
- [x] Add a developer doc page: “Metapunkt Synterfaces + Bindings contract”
  - [x] core synterface catalog (v1)
  - [x] how apps register custom synterfaces + schemas (provider discovery via router)
  - [x] how AgentDefs declare `required_synterfaces`
  - [x] examples for ScenSyn + ReadyMade
  - [x] local override path + UI resolution flow for conflicts/multiple implementations



---

## J) Agent ensembles (slot system) + SynTree as the user-facing UI (vNext)

Goal:
- Allow application-layer apps (ScenSyn, ReadyMade, future apps) to **declare an agent ensemble** as a set of **slots/roles**.
- Allow users to **assign Metapunkt agents to those slots** (or leave slots unassigned / app-default).
- Make SynTree the **primary UI environment** where non-dev users can interact with agent ensembles (beyond app-specific UIs).

Principles:
- **Declaration lives in the app provider** (e.g. `ScenSynMetapunktAppHost`), not in the router.
- **Operationalization lives in Metapunkt** (router merges declarations; UI validates + persists assignments; runtime can route calls by slot).
- **Opt-in for apps**: ScenSyn/ReadyMade keep their tuned internal pipelines unless they explicitly consult slot assignments.
- **Human Agency UX**: “Propose → Preview → Commit” where changes are meaningful (ensemble configs, slot assignments, workflow templates).

### J1) AppHost provider API: slot declarations (per app)
- [x] Add optional provider method to `MetapunktAppHostBase`:
  - [x] `get_agent_slots() -> Array[Dictionary]`
- [x] Define a slot record schema (doc + code comments), minimally:
  - [x] `slot_id` (namespaced, e.g. `scensyn.narrator`, `readymade.a1`)
  - [x] `label` (human readable)
  - [x] `kind` (e.g. narrator/character/planner/reviewer)
  - [x] `required_synterfaces` (Array[String])
  - [x] `recommended_templates` (Array[String]) (ties to AgentDefs templates)
  - [x] optional `default_thread_scope` and/or `thread_scope_pattern`
  - [x] optional `notes` (developer guidance)
- [x] Implement slot declarations in:
  - [x] `ScenSynMetapunktAppHost` (ScenSyn’s multi-agent ensemble slots)
  - [x] `ReadyMadeMetapunktAppHost` (ReadyMade’s planning/workplan slots)

### J2) Router operationalization: merge + conflict reporting for slots
- [x] Extend `MetapunktAppHostRouter` to:
  - [x] discover slot declarations from providers
  - [x] merge into a “slot catalog” (with collision handling for `slot_id`)
  - [x] expose a read API for UI/tools (e.g. `get_agent_slots_catalog()`)
- [x] Persist **user slot assignments** locally (local-first, user-visible path under Documents Synesyn root):
  - [x] `Documents/Synesyn/synesyn/config/metapunkt/slot_assignments.json`
  - [x] map: `slot_id -> agent_id` (canonical for v0)
- [x] Provide clear validation errors when:
  - [x] assigned agent does not exist / is stopped
  - [x] assigned agent lacks required synterfaces for the slot
  - [x] slot is unknown (provider removed)

### J3) Metapunkt UI: ensemble/slot assignment (developer + power user)
- [x] Add a “Slots / Ensembles” UI section to Metapunkt panel:
  - [x] show discovered slots grouped by app/provider
  - [x] dropdown per slot: choose from running agents (or “none / app-default”)
  - [x] validate assignments (synterfaces + role policy) and surface actionable errors
  - [x] persist locally (write `slot_assignments.json`)
  - [x] optional: “Publish to hub” (artifact versioning), keep local-first as default (manual button)
- [x] Add status strip messages when:
  - [x] slot mapping changed
  - [x] validation fails

### J4) App integration (opt-in): consuming slot assignments safely
- [x] ScenSyn:
  - [x] Add an opt-in “use Metapunkt for slot X” path (Narrator first; then additional slots)
  - [x] Ensure ScenSyn’s existing internal multi-agent pipeline remains default unless enabled
  - [x] Ensure thread scopes and provenance are correct when delegating to Metapunkt agents (Metapunkt audit + explicit thread_name passed)
- [x] ReadyMade:
  - [x] Add an opt-in path for using a Metapunkt agent for workplan/planning slot(s)

### J5) SynTree as the user-facing UI for ensembles (v0 usability)
- [x] Add a small SynTree UI surface for “Ensembles”:
  - [x] view slots (from Metapunkt router)
  - [x] view/edit slot assignments (writes `slot_assignments.json` via Metapunkt router API)
  - [x] display validation state (missing synterfaces, missing agents) (best-effort; slot/agent presence shown; missing synterfaces validated via Metapunkt UI)
- [x] Add 1–2 safe “workflow templates” that route across slots (manual user-triggered):
  - [x] Example: “Plan → Draft → Review” (coding assistant prototype)
  - [x] Example: “Outline → Expand → Summarize” (writing assistant)
- [x] Keep Console as the “CLI-like” power surface for testing, but ensure SynTree covers:
  - [x] selecting which ensemble/slots to use for a given action
  - [x] showing progress/logs (best-effort via hub events / Metapunkt audit)

### J6) Data-driven synterfaces + ensembles (non-dev customization)
- [x] Improve UX around `user_synterfaces.json`:
  - [x] surface path in Metapunkt UI (and/or SynTree)
  - [x] quick-open button(s) in Metapunkt UI (and/or SynTree)
  - [x] validate and display errors if a user synterface entry is malformed
  - [x] allow ensemble templates to reference user synterfaces (e.g. `docs.guidelines`)

### J7) Acceptance criteria (v0)
- [x] Apps can declare slots in their provider; Metapunkt UI shows them without manual router edits.
- [x] Users can assign agents to slots, persist locally, and re-open the project with assignments intact.
- [x] Slot assignments are validated against required synterfaces (fail-fast, actionable).
- [x] SynTree can act as the primary UI to run a small multi-slot workflow template (manual trigger) without needing Metapunkt “agent chat”.

---

## K) Optional authentication + identity propagation (multi-user / multi-player readiness)

Goal:
- Allow **auth-required** sessions *and* **open** sessions (no login) without code forks.
- Ensure every agent/tool call has an attached **AuthContext** (at minimum `user_id` + `scopes`) for audit, role policy, and multiplayer correctness.

### K1) Runtime config surface (local-first)
- [x] Add Metapunkt auth settings to runtime config:
  - [x] `apps.metapunkt.auth_mode`: `"open"` | `"required"` (default: `"open"`)
  - [x] `apps.metapunkt.auth_token`: shared bearer token for local deployments (optional; only used when `auth_mode=="required"`)

### K2) SLOP request identity extraction (HTTP path)
- [x] Parse identity context from SLOP request headers:
  - [x] `Authorization: Bearer <token>` (optional in open mode; required in required mode)
  - [x] `X-User-Id: <id>` (required in required mode; optional in open mode)
  - [x] `X-SLOP-Scope: a,b,c` (optional)

### K3) Optional auth enforcement (v0)
- [x] **Open mode**:
  - [x] allow missing Authorization header
  - [x] if `X-User-Id` missing, assign a safe `guest` user_id
- [x] **Required mode**:
  - [x] reject requests without valid bearer token
  - [x] reject requests without explicit `X-User-Id`
  - [x] (v0) token check is local/shared-secret (matches runtime config)

### K4) Identity propagation to actions/tools/audit
- [x] Ensure extracted `user_id` + `scopes` are passed to:
  - [x] `ActionDispatcher.dispatch_action(...)`
  - [x] `AuditLogger` events and published artifacts

### K5) App integration (ScenSyn/ReadyMade) for multiplayer
- [x] In open mode, apps can still provide per-peer identity:
  - [x] ScenSyn: map peer→`user_id` and pass via in-process Metapunkt calls (v0: stable role ids; peer mapping helper available)
  - [x] ReadyMade: support team identity mapping for shared workspaces (v0: stable local user id)

### K6) Future (hub-verified auth)
- [x] Optionally verify tokens via hub auth middleware (via `/auth/whoami`) instead of shared-secret checking in Metapunkt.
