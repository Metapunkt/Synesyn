# To‑Do — SynTree Voice (`syntree_voice` + external Python service)

**Primary spec references**
- `../Synesyn_Platform_Technical_Architecture.md` (SynTree Voice is a SynTree capability)
- `../Synesyn_Hub_API_Spec.md` (`POST /voice/speak`, `POST /voice/transcribe`, hub plugin model)
- `../Local_Deployment_Runbook.md` (no-CLI packaging + Godot services UI)
- `../LatentSubstrate_Data_Model.md` (audio artifacts + provenance)

**What’s already covered / existing**
- A Godot addon exists: `scensyn_dec2025/addons/syntree_voice/`
- It explicitly assumes an **external Python service** on `http://127.0.0.1:8765` and provides integration guidance:
  - `scensyn_dec2025/addons/syntree_voice/README.md`
  - `scensyn_dec2025/addons/syntree_voice/INTEGRATION_GUIDE.md`

**Key prior update from this thread**
- For end-user simplicity, we prefer **one endpoint** and **no CLI**:
  - SynTree Voice should be delivered as a **hub capability** (plugin or hub-managed sidecar),
    so Godot starts “Hub” rather than asking users to start a separate `python voice_server.py`.

---

## Priority guide
- **v0 MVP**: hub-exposed `/voice/speak` (TTS) and `/voice/transcribe` (STT) work; Godot addon can call hub; artifacts are persisted; start/stop is managed without CLI; STT stores transcript-only by default.
- **v1**: caching, richer voice mapping + overrides, better cancellation controls, improved diagnostics.
- **later**: hosted voice provider support, enterprise voice packs, multi-language tuning pipelines.

## A) Decide packaging topology (pick one)
- [x] (v0) Option 1 (preferred): integrate voice service into hub as a plugin capability (`/voice/*`).
- [x] (v0) Option 2: hub-managed sidecar (hub starts/stops voice service and proxies `/voice/*`).

## B) Normalize API contract
- [x] (v0) Implement or adapt to `POST /voice/speak` (TTS) from `Synesyn_Hub_API_Spec.md`.
- [x] (v0) Implement or adapt to `POST /voice/transcribe` (STT) from `Synesyn_Hub_API_Spec.md`.
- [x] (v0) Standardize voice config schema (name/rate/pitch/volume).
- [x] (v0) Add `/health` capability flags for voice TTS/STT (surfaced via hub `/health`).

## C) Artifact persistence + provenance
- [x] (v0) Store generated audio as `audio.tts` artifact in the artifact store.
- [x] (v0) Store STT output as `text.transcript` artifact in the artifact store.
- [x] (v0) Record provenance:
  - [x] (v0) voice model/engine version
  - [x] (v0) voice parameters
  - [x] (v0) input text hash
  - [x] (v1) character mapping used (if any)
- [x] (v0) Enforce privacy default: STT stores transcript-only by default; store `audio.input` only when `save_recordings=true` AND consent is recorded.

## D) Godot integration simplification
- [x] (v0) Update Godot addon client to call hub `/voice/speak` and `/voice/transcribe` (instead of direct `:8765`) when hub mode is enabled.
- [x] (v1) Maintain backwards compatibility: allow direct mode as a fallback (advanced users).
- [x] (v0) Add service availability checks to avoid “silent failure.”

## E) Character voice mapping
- [x] (v1) Move `character_voices.json` into a standard location and treat it as a versioned artifact:
  - [x] (v1) local file for v0/v1 (decide)
  - [ ] (later) persist into substrate for auditability (if needed)
- [x] (v1) Support scenario-specific voice overrides (ScenSyn already has VOICES/VOICE_OVERRIDES concepts).

## F) Performance and UX
- [x] (v0) Ensure synthesis is async and does not block Godot frame.
- [x] (v1) Provide cancellation/stop APIs:
  - [x] (v1) stop current speech
  - [x] (v1) stop all speech
- [x] (v1) Provide caching: same text/voice combo can reuse artifact.

## G) “No CLI” deliverable
- [x] (v0) Ensure voice capability starts via the single “Start Services” button (hub).
- [x] (v0) Ensure logs land in `services/hub/logs/` (and/or a voice subfolder).

## H) Packaging resilience (avoid hub-crash regressions)
- [ ] (v1) Ensure optional voice dependencies (e.g. Whisper STT, audio conversion deps) never crash the hub at import-time in packaged builds:
  - prefer request-time errors (`503`) with clear reasons
  - keep `/health` and `/status` truthful about which providers are actually available
  - decide whether heavy STT belongs in-process or as a hub-managed sidecar


