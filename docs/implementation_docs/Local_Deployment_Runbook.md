# Synesyn — Local Deployment Runbook (One‑Zip, No‑CLI)

**Status**: Normative for packaging and user experience  
**Goal**: Users can run Synesyn/ScenSyn from a single folder without using the command line.

**Additional normative UX reference**:
- `Human_Agency_UX_Contract.md` (“propose → preview → commit → version” and “editable by default”)

---

## 1) Packaging outcomes (“definition of done”)

A user should be able to:
- unzip a folder
- double-click **`Synesyn.exe`**
- choose **ScenSyn** (flagship), **ReadyMade**, or **Synesyn Tools** from a simple launcher
- click **Start Services** (or have services auto-start) in the UI
- see green health indicators for required services
- run a session and generate artifacts

No shell commands required.

### 1.1 Smoke check (release checklist)
- Confirm the zip contains the canonical layout (ADR 0018):
  - `Synesyn*.exe` at the app-folder root (the `.pck` is embedded by the export preset)
  - `services/synesyn_hub/synesyn_hub.exe` with `services/synesyn_hub/_internal/` beside it
  - no `dist/`, `build/`, `.venv/`, or `tests/` inside `services/synesyn_hub/`
- Launch: `Synesyn.exe` → Open ScenSyn → Tools → Settings
- Click **Start Hub** and confirm `GET /health` shows OK
- Click **Test Voice** and confirm it produces an `audio_url` (if voice providers are packaged/enabled)
- Click **Export Workspace Zip** and confirm an export is produced

Automation (Windows) — these two steps produce and verify the layout, so the
release does not depend on assembling folders by hand:
1. `services/synesyn_hub/packaging/build_windows.ps1` → one-dir bundle in `dist/synesyn_hub/`
2. `synesyn/synesyn_client/tools/package_windows.ps1 -ExportDir <godot export folder>` → flattens the hub into place, validates, zips

Standalone check of an existing folder:
- `synesyn/synesyn_client/tools/validate_windows_layout.ps1 -Root <staging_or_unzipped_folder>`

---

## 2) Folder layout (Windows-first, but portable)

**One layout.** The client resolves the hub through a single path
(`HubLocator.get_production_path()`), so there is nothing to probe and nothing to
guess. A `godot/` subfolder variant was previously listed as "Layout B"; no
release ever shipped it and it is no longer supported (ADR 0018).

```
Synesyn/
  Synesyn.exe            # or Synesyn_v<version>.exe; pck embedded
  services/
    synesyn_hub/
      synesyn_hub.exe    # flattened from PyInstaller dist/synesyn_hub/
      _internal/         # one-dir runtime; must sit beside the exe
      config.yaml (optional; defaults apply if omitted)
      logs/
      plugins/ (future)
    comfyui/
      (optional bundled comfyui OR a pointer to an external install)
      start_comfyui.(bat|exe)
      logs/
```

The hub path is load-bearing: `services/synesyn_hub/synesyn_hub.exe` relative to
the folder holding the Godot executable. Shipping PyInstaller's `dist/synesyn_hub/`
wrapper instead of its contents puts the exe one level too deep and autostart
fails with "hub not found".

In addition to the shipped zip folder, Synesyn maintains a **user-owned data vault** on the local machine.

### 2.1 Local data vault (default)

- Default root: `~/Documents/Synesyn/<workspace_slug>/`
- Subfolders:
  - `substrate/` (SQLite DB + indexes)
  - `artifacts/` (images/audio/json/projections/closures)
  - `exports/` (session/range archive bundles)
  - `logs/` (hub logs; optional client logs)

The `<workspace_slug>` is chosen on first run (see §5.3).

---

## 3) Godot “Services” panel requirements

The UI must expose:
- **Start Hub / Stop Hub**
- **Start ComfyUI / Stop ComfyUI** (if configured to manage it)
- **Status**:
  - hub: `/health` and `/status`
  - events: WebSocket connected/disconnected
  - sensors: last packet age per source (from `/status`)
  - comfy: reachable (HTTP/WS) and current workflow path validity
- **Open Logs** buttons:
  - open `services/synesyn_hub/logs/`
  - open `services/comfyui/logs/`
- **Data vault UX**:
  - **Open Data Folder**
  - **Change Data Folder / Workspace** (file picker; do not silently migrate—offer explicit migration)
  - **Choose Archive Folder** (optional; separate from data root)
  - **Export Session / Export Date Range** (writes zip into `exports/` or a user-chosen archive folder)
  - **Privacy/Consent** controls (see §5.4)
- **Configuration**:
  - ports (hub HTTP/WS, UDP ingest)
  - provider modes: local/BYO/hosted for LLM, render, voice
  - paths: comfy install/workflows/artifact folders

Implementation note: Godot uses `OS.create_process()` and stores PIDs for stop/restart.

---

## 3.5 Group sessions (Host/Join, Hub-first)

Normative: **one Hub host per workspace/session**.

- **Host machine**:
  - runs the **Synesyn Hub** (the shared substrate + event bus + jobs runner)
  - may or may not run ComfyUI locally
- **Participant machines**:
  - run SynPunkt / ScenSyn / other clients
  - do **not** need to run the Hub
  - are configured to point at the host’s hub URL (e.g. `http://<host-ip>:17777`)

### 3.5.1 ComfyUI can be remote

It’s valid (and often preferred) for ComfyUI to run on a different machine than the hub:

- clients → hub
- hub → comfyui

Only the **hub machine** needs network reachability to ComfyUI.

### 3.5.2 Optional hub auth (Bearer token)

If hub auth is enabled on the hub, clients must send:

- `Authorization: Bearer <token>`

Client-side config lives in `synesyn_client.json` under:

- `hub.base_url`
- `hub.auth.enabled`
- `hub.auth.token`

For quick LAN demos, keep auth disabled; for teams/Tailscale/org networks, enable auth and distribute the token to participants.

---

## 4) Startup and shutdown behavior

### 4.1 Startup order (recommended)
1) Hub
2) ComfyUI (optional, if managed)
3) Connect event stream (WebSocket)
4) Mark system ready

### 4.2 Shutdown order
1) Disconnect WebSocket clients
2) Stop ComfyUI (optional)
3) Stop hub

### 4.3 Crash handling
If hub dies:
- UI must flip status to red within a short poll interval (e.g., 1s–2s)
- user can click Restart Hub
- Godot should attempt automatic reconnect to `/ws/events`

Packaging-specific note:

- If the hub process “spawns then exits”, run `services/synesyn_hub/synesyn_hub.exe` directly to capture a traceback.
- Packaged Python executables can exit due to missing optional modules; the hub should degrade (disable that capability) rather than crash.

If ComfyUI dies:
- renders fail gracefully
- UI provides restart + clear error

---

## 5) Configuration files

### 5.1 `services/synesyn_hub/config.yaml` (minimum)
- `http_port`
- `ws_path`
- `udp_port`
- `storage_backend` (sqlite default)
- `artifact_store_path`
- `ring_buffer_size`
- `plugins_enabled`

Notes (packaging / zip-relative behavior):
- The hub config loader checks (in order): `SYNESYN_HUB_CONFIG`, then `services/synesyn_hub/app/config.yaml` (dev), then `config.yaml` next to `synesyn_hub.exe` (packaged).

Voice packaging topology (v0):
- **Option 1 (default)**: voice is implemented inside the hub (providers + routes in-process).
- **Option 2 (optional)**: hub-managed voice sidecar (hub starts/stops an external voice server and proxies compute).
  - This preserves the “one endpoint, no CLI” UX while letting compute live outside the hub process if desired.
  - Sidecar env/config keys (optional):
    - `SYNESYN_VOICE_SIDECAR_ENABLED` (`true|false`)
    - `SYNESYN_VOICE_SIDECAR_URL` (default `http://127.0.0.1:8765`)
    - `SYNESYN_VOICE_SIDECAR_CMD` (optional; if empty, hub will only proxy if sidecar is already running)
    - `SYNESYN_VOICE_SIDECAR_ARGS` (comma-separated)
    - `SYNESYN_VOICE_SIDECAR_CWD` (optional working dir)

### 5.2 Client runtime config (normative)

**Implemented v0 (current)**: Godot stores user runtime config at:
- `user://synesyn_client.json`

This is the canonical place for user-specific settings (so exports are configurable without editing `project.godot`).

Current keys (v0):
- `hub.base_url`
- `voice.provider_mode` (`direct` | `hub`)
- `voice.service_url`
- `voice.hub_url`
- `apps.<app_id>.include_syntree_context` (bool; opt-in bridging of SynTree sources into runtime app prompts)
  - example: `apps.scensyn.include_syntree_context`
- `apps.scensyn.workshop_workspace_preset` (`talk` | `map` | `review` |
  `full_dashboard` | `custom`; last Workshop Catalyst density preset)
- `apps.scensyn.workshop_workspace_custom_panels` (object of panel-id → bool;
  remembered Custom visibility for `conversation`, `thinking_map`,
  `ai_assistant`, `session_record`, `participants`, and `navigation`)
  - These keys are layout preferences only. They never store workshop meaning
    and cannot hide recording/consent/error/uncommitted-change/End & Save safety
    controls.

Implementation note (v1 drift guardrail):
- Provider interpretation is centralized in `res://addons/synesyn_core/scripts/provider_mode_policy.gd` (Godot), so apps do not re-implement URL/mode precedence rules.

Thread scoping (v1 stability guardrail):
- Each app/surface must set a **thread scope** before calling `ConversationManager.setup()` to avoid history collisions.
- Convention: `thread_scope = "<app_id>"` or `"<app_id>.<workspace_slug>"` (sanitized by `res://addons/synesyn_core/scripts/thread_scope_utils.gd`).
- Back-compat: if a non-`shared` scope is requested but only legacy `shared` threads exist, `ConversationManager` will fall back to `shared` to avoid “missing history” surprises.

Bridge artifacts (optional v1 alignment):
- A conversation thread can be shared across apps without sharing local thread folders by exporting a **hub artifact**.
- Artifact type: `chat.thread`
- Payload (inline JSON) includes: `schema_version`, `scope`, `thread_id`, `session_id` (optional), `messages[]`, `updated_at`, `prev_artifact_id` (optional).
- Godot API (explicit actions only): `ConversationManager.export_thread_bridge_artifact(thread_id)` and `ConversationManager.import_thread_bridge_artifact(artifact_id, target_thread_id="")`.

---

## v1 acceptance checks (platform alignment)

### A) SynTree core usable without editor plugin
- **Goal**: a runtime app can use core services without relying on the SynTree `EditorPlugin`.
- **Check**:
  - From a runtime scene/script, call `SynTreeRuntimeInstaller.ensure_core_installed()`.
  - Confirm `/root/ContentBus` and `/root/NotificationManager` exist afterwards.
  - Confirm `SynTreeCore.require_core().ok == true`.

### B) Metapunkt tool-call schema standardization + substrate logging
- **Goal**: tool execution results have a consistent envelope and emit substrate events.
- **Check**:
  - Trigger a tool call via Metapunkt (sync path is enough).
  - Confirm returned dict includes: `ok`, `op`, `call_id`, `schema_version`.
  - Confirm `tool.call` + (`tool.result` or `tool.error`) events are emitted via `AuditLogger` (and forwarded to hub when enabled).

### C) Prompt Chains v1 (slots + Propose → Preview → Commit → Version)
- **Goal**: prompt-chain edits are proposed until committed; preview reflects slot substitution; hub versioning only for committed assets.
- **Check**:
  - In Prompt Chains UI, edit a chain and confirm it shows “(Proposed changes pending)”.
  - Confirm **Commit** applies changes and **Revert** discards proposals.
  - Add a slot and use `{{slot_name}}` in a block; set per-thread “Value (this thread)” and confirm preview updates.
  - Confirm “Save version to Hub” refuses when proposals are pending, and succeeds once committed (asset mode).

Where this is surfaced in the UI (v0):
- ScenSyn hamburger settings → **“Include SynTree content sources in ScenSyn prompts”**

**Planned v1**: a shipped file like `godot/config/synesyn_client.yaml` may exist as defaults, but runtime overrides live in `user://`.

### 5.2.1 (Future) `godot/config/synesyn_client.yaml` (minimum)
- `hub_base_url`
- `hub_ws_url`
- `workspace`:
  - `name`
  - `slug`
  - `data_root_path` (defaults under Documents)
- `archive`:
  - `archive_path` (optional override; default `exports/` under the workspace vault)
- `provider_modes`:
  - `voice: local|hosted|off`
  - `render: local|byo|hosted|off`
  - `llm: local|byo|hosted`
- `comfyui`:
  - `managed: true|false`
  - `url` (if BYO)
  - `workflow_dir`

### 5.2.2 Context isolation (critical)
Because Synesyn hosts multiple prompt surfaces (SynTree editor + ScenSyn runtime), configuration must support isolation-by-default:
- Default: ScenSyn does **not** include SynTree ContentBus sources in its prompts.
- Opt-in: users enable this explicitly via a ScenSyn UI toggle, persisted as:
  - `apps.scensyn.include_syntree_context: true`

### 5.3 First-run workspace setup (normative)
On first launch (local/offline), Synesyn must prompt the user to set up a workspace:

- Enter **workspace name**
- System generates a filesystem-safe **workspace slug**
- UI shows a preview path: `~/Documents/Synesyn/<workspace_slug>/`
- User can accept defaults or choose a different root folder
- System creates the folder structure (`substrate/`, `artifacts/`, `exports/`, `logs/`)
- Choices are persisted so the prompt is not shown again

Do not silently rename or migrate existing workspace folders; offer explicit “migrate data” actions.

### 5.4 Privacy / consent (GDPR-aligned defaults)
At minimum, provide explicit opt-in toggles for:

- Cloud storage/sync (off by default)
- Saving raw voice recordings used for STT (off by default)

If STT is enabled, store **transcript only by default**; store raw audio only when the user explicitly enables recording retention and consent is recorded.

---

## 6) Logging and supportability

Requirements:
- Each service writes structured logs to its own `logs/` folder.
- Godot should surface “last error” summaries in the Services panel.
- Include a “Copy diagnostics” button that collects:
  - hub `/status`
  - comfy status (reachable? workflow path?)
  - last N lines of log (or file paths)

---

## 7) Latency expectations (local kiosk)

Target budget (guidance):
- Sensor → hub ingest → websocket broadcast: typically sub‑50ms on same machine/LAN
- Godot UI update: next frame

Hub must not block realtime on disk writes:
- persist asynchronously
- keep a short in-memory queue and backpressure policy


