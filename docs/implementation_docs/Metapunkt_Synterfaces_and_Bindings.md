## Purpose
This page defines Metapunkt’s **Synterfaces + Bindings** contract.

It exists to make Metapunkt the **single entry point** for agent creation and lifecycle across Synesyn application-layer apps (ScenSyn, ReadyMade, and future apps), while still allowing tight app/scene coupling in a controlled, explicit way.

Key goals:
- **Framework alignment**: agents are authored as `AgentDefinition` resources and provisioned by Metapunkt.
- **No accidental bypass**: agents requiring synterfaces **must not spawn** unless the host binds those synterfaces.
- **Clarity**: synterface contracts are JSON-native (schemas), so they can be transmitted, validated, surfaced in UI, and documented.

## Terms
- **Synterface**: a named capability/surface an agent requires from the application host (e.g. `scene_root`, `conversation_io`).
- **Binding**: the JSON-friendly object returned by the host for a synterface, validated against that synterface’s JSON Schema.
- **Host**: a **router autoload** at `/root/MetapunktAppHost` that discovers and routes to installed app-host providers.

## Where this lives in the repo
- **AgentDefinition schema**: `synesyn_client/addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd`
- **Core synterface catalog**: `synesyn_client/addons/metapunkt/Core/Ports/synterface_catalog.gd`
- **Host base contract**: `synesyn_client/addons/metapunkt/Core/Ports/metapunkt_app_host_base.gd`
- **Schema validator (subset)**: `synesyn_client/addons/metapunkt/Core/Ports/json_schema_validator.gd`
- **Reference host stub**: `synesyn_client/addons/metapunkt/examples/metapunkt_app_host_stub.gd`

## AgentDefinition fields (v1)
Metapunkt uses these fields on `AgentDefinition`:
- **`schema_version`**: string (default `metapunkt.agentdef.v1`)
- **`required_synterfaces`**: Array of synterface IDs (strings)
- **`synterface_defaults`**: Dictionary (JSON object)
- **`binding_hints`**: Dictionary (JSON object)

Notes:
- `required_synterfaces` may include **namespaced custom synterfaces** (recommended format: `app_id.synterface_name`, e.g. `scensyn.story_state`).
- Metapunkt enforces synterface existence at **spawn time** (catalog + host bindings must satisfy required synterfaces).

## MetapunktAppHost autoload contract
In multi-app projects, `/root/MetapunktAppHost` is a **router autoload** (provided by Metapunkt) and should not be replaced per app.

### App-host provider (per app) contract (auto-discovered)
Each application that wants to run synterface-requiring agents must ship a **provider script** that:
- has a `class_name` (so it is registered as a global class)
- extends `MetapunktAppHostBase`
- publishes **namespaced** synterface IDs (e.g. `myapp.*`) via `get_synterface_catalog()`

The router discovers providers via `ProjectSettings.get_global_class_list()` and routes binding per synterface id.

Required methods:
- **`get_app_id() -> String`**
- **`get_synterface_catalog() -> Dictionary`**
  - returns custom synterfaces: `synterface_id -> {version, description, schema}`
- **`bind_synterfaces(required_synterfaces: Array, hints: Dictionary) -> Dictionary`**
  - returns:
    - `{ ok: true, synterfaces: {synterface_id: <binding dict>} }`
    - or `{ ok: false, missing: [..], error: "..." }`

Optional (future, for scene-coupled provisioning):
- `spawn_agent_node(agent_id, def, synterfaces)`
- `stop_agent_node(agent_id)`

## Synterface catalog (v1)
Metapunkt ships a **core synterface catalog** (v1). Apps can extend it at runtime via `get_synterface_catalog()`.

### Core synterfaces (v1)
- **`conversation_io`**
  - intent: agent can request tool calls/chat through Metapunkt (policy + audit enforced)
  - binding shape (high level):
    - `{ kind:"service", service:"...", operations:[...] }`

- **`thread_scope`**
  - intent: thread scoping metadata for isolating conversations/artifacts
  - binding shape:
    - `{ scope:"..." }`

- **`scene_root`**
  - intent: stable spawn parent / scene attachment root (for scene-coupled agents)
  - binding shape:
    - `{ kind:"node" | "path", path?: "...", label?: "..." }`

- **`workplan`**
  - intent: workplan/task-queue capability (ReadyMade-style planning/execution apps)
  - binding shape:
    - `{ kind:"service", service:"...", operations:[...] }`

- **`ui_hooks`**
  - intent: UI feedback hooks (toasts/notifications/status strip)
  - binding shape:
    - `{ kind:"service", service:"...", operations:[...], channels?:[...] }`

## Enforcement rules (fail-fast)
Metapunkt enforces Synterfaces/Bindings only when:
- `AgentDefinition.required_synterfaces` is **non-empty**

Spawn-time checks:
- `MetapunktAppHost` must exist at `/root/MetapunktAppHost`
- all `required_synterfaces` must exist in the **merged catalog** (core + host)
- host must bind all required synterfaces
- each returned binding must be a **Dictionary** (JSON-friendly)
- binding must validate against the synterface’s JSON Schema (subset validator)

If any check fails:
- agent spawn fails
- error is surfaced as an actionable string (UI-friendly)

## Local overrides (conflicts / multiple implementations)
When multiple apps provide the same synterface id:
- If their schemas match, Metapunkt treats them as **compatible implementations**.
- If their schemas differ, Metapunkt treats it as a **conflict** and requires user selection.

Local-first override storage lives under your Documents Synesyn data root:
- `Documents/Synesyn/synesyn/config/metapunkt/synterface_overrides.json`

This file stores a simple mapping:
- `synterface_id -> implementation_id`

In the Metapunkt panel, use:
- `AgentDefs → synterface selection (conflicts / multiple implementations)` to set/clear overrides.

## User synterfaces (Model A — data-driven synterfaces)
Non-developer users can add **data-driven synterfaces** by editing a local JSON file:
- `Documents/Synesyn/synesyn/config/metapunkt/user_synterfaces.json`

Format (v1):
- `{ "schema_version": "metapunkt.user_synterfaces.v1", "synterfaces": { "<id>": { "version": "...", "description": "...", "schema": {..}, "binding": {..} } } }`

Notes:
- IDs must be **namespaced** (contain a dot), e.g. `docs.guidelines`.
- User synterfaces cannot override Metapunkt core synterfaces.
- Bindings are validated against the provided JSON Schema at bind time.

## Example: add a custom synterface (namespaced)
Example custom synterface ID:
- `scensyn.story_state`

In `MetapunktAppHost.get_synterface_catalog()`:
- provide `{version, description, schema}` for `scensyn.story_state`

In `bind_synterfaces()`:
- if required, return a JSON-friendly capability object that matches the schema.

## Example: typical AgentDefinition (synterfaces)
An AgentDefinition might declare:
- `required_synterfaces = ["conversation_io","thread_scope","ui_hooks","scensyn.story_state"]`
- `binding_hints = {"default_scope":"scensyn_session","spawn_root_group":"game_session"}`
- `synterface_defaults = {}` (optional)

---

## Capability Packs (v0) — “skills” as installable modules

This section defines a **Capability Pack** concept for Metapunkt. The goal is to make adding new “skills” feel modular and safe for end users, while keeping Metapunkt’s existing contracts (Synterfaces + Bindings + ToolRegistry + audit) as the enforcement layer.

### Definitions
- **Capability**: a named unit of functionality exposed as:
  - a **tool** (invocable via ToolRegistry with schema-validated args/results), and/or
  - a **UI panel** (a Godot scene mounted into a host UI slot)
- **Capability Pack**: a versioned bundle that declares one or more capabilities + schemas + permissions.

### Pack locations (repo vs installed runtime)
Packs may be stored anywhere on disk (e.g. `Documents/Synesyn/PacksRepo/`), but Metapunkt should treat packs as **installed into user data** for runtime loading:
- **Installed packs root**: `user://synesyn/packs/<pack_id>/<version>/...`

Rationale: `user://` is stable across editor vs exported builds; it avoids relying on absolute OS paths for resource loading.

### Minimum pack contract (v0)
Each installed pack must provide:
- `pack.json` manifest (identity, version, capabilities list, permissions, compatibility)
- referenced schemas under `schemas/` for tool args/results (JSON Schema)

Optional:
- `ui/` scenes/scripts for UI panel capabilities

### Capability types supported in v0
- **`tool`**: registers a tool into Metapunkt’s ToolRegistry.
  - Must declare `tool_name`, `args_schema`, `result_schema`.
  - Tool calls MUST be emitted using the canonical `ToolCallSchema` envelope so audit + correlation IDs are preserved.
- **`ui_panel`**: mounts a scene into an existing Metapunkt UI “slot”.
  - A UI panel is not a new tool system; it is a user-facing surface that typically *invokes tools* (and therefore inherits policy + audit).

### Permissions (pack-declared; Metapunkt-enforced)
Packs must declare permissions in the manifest. Metapunkt enforces them at runtime:
- **Network**: allowlist of domains (or none)
- **Filesystem**: read/write scopes (prefer `user://`-scoped globs)
- **Secrets**: required secret names (values are stored outside the pack)
- **Dangerous actions**: explicit flags for high-risk operations (rare; always opt-in)

### Relationship to Synterfaces + Bindings
Capability Packs do not replace Synterfaces; they *use* existing contracts:
- **Tools** are executed through Metapunkt’s tool surface (policy + audit), typically requiring `conversation_io` and `thread_scope`.
- **UI panels** are mounted via host-controlled UI composition, typically using `ui_hooks` or a dedicated UI mount surface.

Recommended pattern:
- Introduce a stable “mount slot” catalog for UI panels (e.g. `metapunkt.tools_panels`, `metapunkt.utilities_panels`) rather than ad-hoc scene injection.
- UI panels should be treated as **untrusted UI**: they can request tool execution, but do not bypass policy gates.

### Manifest sketch (illustrative, non-normative)
Example `pack.json` excerpt:

```json
{
  "id": "synesyn.workshop_exporter",
  "name": "Workshop Exporter",
  "version": "0.1.0",
  "synesyn_min_version": "2026.2",
  "schemas": { "tool_call": 1 },
  "capabilities": [
    {
      "capability_id": "export_bundle",
      "type": "tool",
      "entrypoints": {
        "tool_name": "workshop.export_bundle",
        "args_schema": "schemas/workshop.export_bundle.args.v1.json",
        "result_schema": "schemas/workshop.export_bundle.result.v1.json"
      }
    }
  ],
  "permissions": {
    "network": { "allow": [] },
    "filesystem": { "read": ["user://synesyn/sessions/**"], "write": ["user://synesyn/exports/**"] },
    "secrets": [],
    "dangerous_actions": []
  }
}
```


