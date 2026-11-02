# To‑Do — Synesyn Hub (Python core engine + system-of-record)

**Primary spec references**
- `../Synesyn_Hub_API_Spec.md`
- `../LatentSubstrate_Data_Model.md`
- `../Local_Deployment_Runbook.md`

**What’s already covered**
- The “what/why” and top-level boundaries are covered in `../Synesyn_Platform_Technical_Architecture.md`.
- This checklist focuses on concrete implementation and packaging.

---

## Priority guide
- **v0 MVP**: local-first hub that runs from the one-zip package; sensor ingest → WS broadcast; minimal substrate persistence; TTS via hub; usable `/health` + `/status`.
- **v1**: solid query ergonomics, richer job framework, optional hub-submit rendering, better resilience/diagnostics.
- **later**: SaaS auth/tenancy, Postgres/S3 backends, multi-machine deployments, advanced compute.

---

## A) Hub skeleton, config, lifecycle
- [x] (v0) Create hub repo/module layout: `hub/`, `plugins/`, `data/`, `logs/`, `config.yaml`.
- [x] (v0) Implement config loader (`config.yaml`) with defaults from `Synesyn_Hub_API_Spec.md`.
- [x] (v0) Implement `/health` endpoint returning capability booleans.
- [x] (v0) Implement `/status` endpoint returning UDP sources + WS clients + storage queue depth.
- [x] (v0) Implement structured logging to `services/hub/logs/` (JSONL recommended).
- [x] (v0) Add safe defaults: bind to `127.0.0.1` unless explicitly configured.
- [x] (v0) Support a per-workspace local data vault rooted at `~/Documents/Synesyn/<workspace_slug>/` (selected on first run via Godot UI).
- [x] (v0) Persist the selected workspace config (name/slug/root) and load it on hub start (via `POST /workspace/select` + `~/Documents/Synesyn/_current_workspace.json`).

## B) Event bus (WebSocket/SSE) + ring buffer + replay
- [x] (v0) Implement WebSocket endpoint `/ws/events`.
- [x] (v0) Standardize the event envelope exactly as specified in `Synesyn_Hub_API_Spec.md`.
- [x] (v0) Implement in-memory ring buffer (configurable size).
- [x] (v0) Implement backpressure policy: drop per-client events (do not block global bus).
- [x] (v1) Implement `subscribe` message (filter by `event_types`).
- [x] (v1) Implement `replay` message (ring-buffer replay window / time-window semantics).
- [ ] (later) SSE alternative (`/sse/events`) if needed for non-WS clients.

## C) UDP sensor ingestion → normalized events → persistence
- [x] (v0) Implement UDP listener (default port 5000, configurable).
- [x] (v0) Parse sensor UDP JSON payload, validate, normalize to event envelope.
- [x] (v0) Maintain per-`source_id` sequence assignment if missing.
- [x] (v0) Publish normalized events to WS immediately (realtime path).
- [x] (v0) Enqueue persistence into substrate asynchronously (durable path).
- [x] (v0) Expose sensor source stats through `/status` (last_seen_ms, last seq).
- [x] (v1) Add basic dedupe/drop detection warnings (seq gaps / dupes) per source.

## D) LatentSubstrate storage (metadata + artifact store)
- [x] (v0) Implement local-first metadata store (SQLite) for sessions/events/entities/relations/artifacts/provenance.
- [x] (v0) Implement artifact store on disk (`data/artifacts/<type>/...`) and content hashing.
- [x] (v0) Implement substrate CRUD endpoints:
  - [x] `POST /substrate/sessions`
  - [x] `POST /substrate/events`
  - [x] `POST /substrate/artifacts`
  - [x] `POST /substrate/entities`
  - [x] `POST /substrate/relations`
  - [x] `POST /substrate/query` (v0 minimal; exact-match filters + limit)
- [x] (v0) Enforce provenance rules from `LatentSubstrate_Data_Model.md` for derived artifacts (configurable via `SYNESYN_ENFORCE_PROVENANCE`, default true).
- [x] (v1) Improve `/substrate/query` ergonomics (filters, pagination, time ranges).
- [ ] (later) Add storage backend abstraction (Postgres/S3) for hosted mode.

## D.1) User access + archiving (local-first requirement)
- [x] (v0) Ensure artifacts and session logs are written into the user-owned Documents workspace vault (not inside the shipped zip folder).
  - [x] (v0) `POST /export/session` (or job type `export.session`) that produces a zip in `exports/` and returns an export artifact reference.
  - [x] (v0) Include session JSON + artifacts in the export bundle (v0 also adds optional table dumps: `substrate/artifacts.json`, `substrate/entities.json`, `substrate/relations.json`).
- [x] (v1) Add `POST /export/range` (date range / multiple sessions).

## E) Jobs (“dreaming” + SynAxes compute) framework
- [x] (v0) Implement `POST /jobs` submission API.
- [x] (v0) Emit job events: `job.queued`, `job.started`, `job.completed`, `job.failed` (progress optional in v0).
- [x] (v0) Implement job store (minimal) and worker execution model (in-process to start).
- [x] (v0) Ensure `job.completed` writes outputs as artifacts/entities/relations with provenance.
  - [x] `synaxes.cluster` producing a `graph.cluster_result` artifact.
  - [x] `synaxes.project` producing `coords.projection_3d` (and analysis run record).
- [x] (v1) Add `job.progress` events and percent/phase semantics.
- [ ] (later) Add a proper worker pool / queue if needed (only once demanded).

## F) Plugin system inside the hub (capabilities)
- [x] (v0) Define hub plugin interface (init, capability flags, route registration).
- [x] (v0) Load plugins from `plugins/` by config.
- [x] (v0) Add plugin health reporting to `/health` and `/status` (and `/version`).
- [x] (v0) Implement `syntree_voice` as a hub plugin or hub-managed sidecar (see `04_SynTree_Voice.md`).
  - [x] (v0) `POST /voice/speak` (Option A: file-backed `audio.tts` + optional `json.lipsync`)
  - [x] (v0) `POST /voice/transcribe` (STT in scope; transcript-only storage by default; optional raw audio storage only with explicit consent + `save_recordings=true`)
  - [x] (v0) Add Edge self-test on startup; show Edge vs SAPI fallback status in `/status`.
  - [x] (v0) Keep SAPI fallback installed (`pyttsx3`) and report `provider_used` in `/voice/speak` response.
  - [x] (v0) Pin/upgrade `edge-tts` so Edge voices actually work (current: `edge-tts==7.2.7`).
  - [ ] (v1) Bundle Whisper (or equivalent STT) as an **optional** capability:
    - hub must not crash if the module is missing in packaged builds
    - `/health` + `/status` must accurately report STT readiness and reason when unavailable
    - consider hub-managed sidecar for heavy ML deps to keep the main exe lightweight
- [ ] (v1) Add **VibeVoice** as an additional TTS provider (high-quality local/hosted mode):
  - [ ] (v1) Add `voice.provider_mode` + `voice.auto_order` config (e.g. `["edge_tts","vibevoice","sapi"]` or `["vibevoice","edge_tts","sapi"]`).
  - [ ] (v1) Define a canonical `voice` schema that can map across Edge voice IDs, VibeVoice speakers, and SAPI voices.
  - [ ] (v1) Package VibeVoice runtime + weights (or first-run download) with clear GPU/CPU expectations; expose capability flags in `/health` + `/status`.
- [ ] (v1) Add hot-reload or safe restart behavior (optional).

## G) ComfyUI integration (optional hub-submit mode)
- [ ] (v1) Decide whether hub-submit is needed (client-direct is allowed in v0).
- [ ] (v1) If enabled: implement `POST /render/submit` and `render.*` events.
- [ ] (v1) Persist outputs as artifacts with determinism provenance (workflow hash, seed, model ids).

## Notes (implemented in code — quick pointers)
- **Jobs API + job runner + persistence + WS events**: `services/synesyn_hub/app/routes/jobs.py`, `services/synesyn_hub/app/main.py`, `services/synesyn_hub/app/routes/ws_events.py`

## H) “No CLI” packaging deliverable
- [x] (v0) Produce `hub.exe` via PyInstaller (Windows) OR ship embedded python runner (packaging scaffold added: `services/synesyn_hub/packaging/` + build script).
- [x] (v0) Ensure hub can be started/stopped by Godot using `OS.create_process()`.
- [x] (v0) Validate relative-path operation from a zipped folder extraction (config resolves from exe-adjacent `config.yaml` or env override).
- [x] (v0) Decide and implement where logs/data are written (primary: Documents workspace vault; secondary: install-tree logs best-effort).

## Notes (implemented in code)
- **Workspace selection/persistence (no-CLI flow)**: `app/routes/workspace.py`, `app/config.py`
- **Provenance enforcement**: `app/substrate/provenance.py`, `app/substrate/repo.py`, plus hub-generated artifact metadata in `app/voice/routes.py`
- **Export enhancements**: `app/routes/export.py`
- **Packaging scaffold**: `packaging/README.md`, `packaging/build_windows.ps1`

## I) Compatibility + future SaaS alignment (guardrails)
- [x] (v0) Keep auth middleware pluggable; local mode is default.
- [x] (v0) Ensure all APIs are versioned (schema_version in events; optional `/version` endpoint).
- [ ] (later) Keep storage backend abstraction (SQLite now, Postgres/S3 later).


