# Synesyn Platform — Technical Implementation Architecture (Authoritative)

**Status**: Approved direction (Dec 2025, updated April 2026)  
**Scope**: Synesyn framework + first‑party apps (ScenSyn, ReadyMade) + external services (Synesyn Hub, ComfyUI, `syntree_voice`, SuperCollider)  
**Primary user journey**: Clients running applications like **ScenSyn**.  
**Secondary user journey**: Creators extending/building apps against the open-source core (documentation + code navigation expected).  
**Flagship scenario**: **Stochastic Dreams** (interactive divination installation with four-voice ensemble, pendulum-driven turn data, vis_story v2 image generation, SuperCollider ambient sound, and tiered lull protocol). See `development_notes/Stochastic_Dreams_Concept_Note_v5.txt` for full narrative and integration architecture.  

## Developer completeness note (read this first)

This document is the **authoritative high-level architecture**. To avoid developer confusion during implementation, it is paired with the following **contract/spec documents** in the same folder:

- **`Synesyn_Hub_API_Spec.md`**: concrete HTTP/WebSocket APIs, message formats, error codes, replay semantics, provider routing.
- **`LatentSubstrate_Data_Model.md`**: canonical entities/relations/artifacts, provenance rules, versioning, and storage backends.
- **`Local_Deployment_Runbook.md`**: one-zip packaging, service lifecycle, ports, logs, and “no CLI” UX requirements.
- **`STFX_Memory_Capability_Spec.md`**: app-agnostic symbolic memory capability grounded in deterministic seed/tensor retrieval, with file-backed canonical storage and optional hub/substrate integration.
- **`ScenSyn_Scenario_Continuity_Contract.md`**: ScenSyn-facing adapter contract that translates app-agnostic memory continuity into scenario/session continuity state.

Implementers should treat the contract and specification documents listed above as normative for their respective interfaces and behavior.
Additionally, the following UX contract is normative for cross-module interaction:
- **`Human_Agency_UX_Contract.md`**: “propose → preview → commit → version” and “editable by default” guardrails.

---

## 1) Goals and non-goals

### Goals
- **App-first client experience**: clients launch, run sessions, and generate artifacts with minimal friction.
- **Open-core platform**: core is open and extensible; premium value can be layered without forking the architecture.
- **Pluggable providers**: local vs BYO vs hosted (SaaS) should be selectable without rewriting apps.
- **Auditable “Latent Reality”**: all generated/derived outputs are traceable to inputs, prompts, workflows, versions, and events.
- **One-zip deployment**: runnable without command line; services start/stop from Godot UI.
- **Multi-surface future**: Godot is the first UI layer, but the platform can support a future React/Electron UI without recreating the core.

### Non-goals (for initial implementation)
- Fully rebuilding the entire Godot runtime experience layer in another UI stack.
- Implementing every “premium” feature immediately (analytics, certification tooling, etc.); instead, reserve extension points.

---

## 2) Canonical architecture (mapped to the intended module diagram)

Synesyn is organized as:
- **Godot platform shell** (the primary UI/runtime surface)
- **Core services layer** (local-first, Python, as the system-of-record)
- **Generation engines** (ComfyUI, optional external inference)

### 2.1 In-Godot modules (Synesyn core plugins)

#### **Metapunkt (orchestrator)**
- Multi-agent coordination, role/permission model, tool routing, workflow orchestration.
- Acts as the **control layer** inside Godot (and/or via API in the future).

#### **SynTree (semantic assistant + wrapper)**
- Editor-integrated assistant and reusable semantic/LLM wrapper for Synesyn apps.
- **SynTree Voice** is conceptually a SynTree capability, even if implemented externally.
- **Context Graph** is SynTree's context-engineering workspace: it structures
  content relationships, previews compiled context, and publishes versioned
  `ui.context_graph` artifacts without replacing List, Hierarchy, or the Prompt
  Chain editor.
- **Prompt Chains**: a human-editable “prompt program” for repeatable prompting across sessions/apps:
  - stored as versioned artifacts (`ui.prompt_chain`) (see `LatentSubstrate_Data_Model.md`)
  - designed to be reusable (assets) while still allowing thread-local drafts in the UI
  - follows the normative UX contract: “propose → preview → commit → version” (`Human_Agency_UX_Contract.md`)

#### **Graph Workspace (shared runtime-safe interaction foundation)**
- Supplies domain-neutral graph document primitives, typed relationships,
  proposal/review states, provenance references, semantic validation/diff,
  layout separation, reusable GraphEdit interaction, and Hub artifact transport.
- Product adapters own meaning: SynTree's `ContextGraphAdapter` handles context
  engineering, while Workshop Catalyst's `ThinkingMapAdapter` handles live
  facilitation.
- Shared mechanics do not imply shared artifacts: `ui.context_graph` and
  `ui.workshop_thinking_map` remain separate versioned contracts.
- The shared layer must not depend on editor-only SynTree UI, Workshop Catalyst
  session controllers, or either product's domain state.
- The Stage 8 WC implementation uses `ThinkingMapAdapter` plus a scene-authored
  column projection. Live event batches mutate the WC document incrementally;
  semantic preview, non-blocking version commit/retry, Session Record routing,
  and the default-off specialist-context trace remain product-owned.

#### **SynPunkt (infinite canvas)**
- **Presentation + visualization surface** for “performing” Latent Reality outputs:
  - **SynDeck** (unified outline + edgeless/Prezi-style infinite canvas over one schema)
  - **Story Stage** as a mode (2D now; 3D later)
  - **Render orchestration** mode for ComfyUI workflows (“image subroutines” driven by closures + prompt sets)
- SynPunkt primarily **consumes** closures/projections/pattern artifacts from the Hub and turns them into images, decks, and staged experiences.
- SynPunkt should avoid duplicating SynAxes’s closure formation and analysis logic; it focuses on curation, performance, and output generation.

#### **SynAxes (pattern synthesizer)**
- **Latent Reality engine**: pattern discovery + synthesis + interactive formation of canonical “closures”.
- Pattern Space is a **3D exploration surface**; V2 orientation follows the **Closure Map** (Distal / Deep · Recursive Closure, Past↔Future) with **Proxistance** as movement between overview and recursive encounter — not a physics spacetime / “4D canvas” simulation (ADR 0015). Closure time windows already exist in the editor.
- Produces derived artifacts (projections, clusters/bridges/hubs) **and** commits canonical `ui.closure` artifacts back into the shared substrate with provenance.

### 2.2 Applications built on Synesyn

#### **ScenSyn**
- Scenario synthesis + generative theatre + narrative arc orchestration.
- Consumes Synesyn modules and the shared substrate; emits session logs and artifacts.
- Session Type runtime profiles select presentation topology through one generic
  finalization seam: Story Catalyst uses `visible_ensemble`; Workshop Catalyst
  uses `hidden_synthesis`.
- Workshop hidden synthesis performs one batched specialist request followed by
  one Session Record synthesis request. Only the synthesized `Session Record`
  message enters `StoryState`; concise specialist summaries remain Workshop-owned
  and persist best-effort as `json.workshop_specialist_trace`.
- Workshop Catalyst has no runtime scenario cast. The only human runtime identity
  is Facilitator; four stable cross-scenario Specialist Functions run behind the
  single batched operation. Workshop compatibility normalization discards legacy
  character arrays before prompt, UI, or continuity projection. Story Catalyst's
  `visible_ensemble` and character contract are unchanged.
- Workshop entry defaults to scene-authored Scenario creation; authored
  Scenarios are optional templates. The normalized Workshop Packet has no
  characters and local drafts persist version-safely under `user://`. Local
  draft state is not a Hub publication or canonical artifact.
- The specialist batch also emits validated `map_candidates` and separate
  `facilitator_cues`. Only valid Cause/Effect/Opportunity propositions cross the
  Workshop event/command seam as Suggested map nodes. Raw transcript, raw
  Session Record output, malformed JSON, and process guidance create no nodes.
- Workshop voice input follows a Session Type-owned proposal controller:
  microphone/STT completion → editable preview → explicit send. A sent speech
  segment is retained as immutable `json.workshop_transcript_segment` versions;
  corrections preserve `original_text` and do not mutate `StoryState` or trigger
  another model turn unless explicitly resent.
- The existing voice bridge remains shared. Workshop Catalyst supplies a
  sender-policy hook that allows only `Session Record` output to reach TTS;
  Story Catalyst retains its existing character voice behavior.
- Workshop Session Record state is split into a local facilitator-reviewed draft,
  an isolated AI proposal/decision ledger, and the last immutable Hub commit.
  Bucket extraction can create suggestions only. Accept/edit/reject/defer update
  the review ledger; only the explicit Commit action writes
  `ui.workshop_summary` through the generic substrate artifact route.
- Workshop Compare Paths uses separate path-state, proposal, evidence-retrieval,
  persistence, and UI-controller modules. The Review workspace supplies the
  scene-authored surface; dynamic cards project first-class path objects. The
  state model enforces one explicit do-nothing path and keeps selection or
  combination as a draft until Preview and Commit.
- Evidence retrieval calls the existing STFX Store seam asynchronously.
  Generation ids discard stale responses. Retrieval traces and context-pack
  references travel with `ui.workshop_path_set`; absent evidence remains
  labelled `none`, `degraded`, or `unavailable`.
- Path commitment writes an immutable generic Hub artifact before an explicit
  ClosureBus action. Closure delivery retry reuses the persisted artifact id.
  Committed outcomes reach Session Record state only through the facilitator's
  separate route action, and path state is absent from specialist prompts.
- Workshop target surfaces are scene-authored and presentation-only. The
  Participants panel shows the local Facilitator on the current device and
  states that remote participant presence is unavailable. Invite opens an
  explanatory dialog and has no contact, email, network, or Hub dependency.
  Plans and Progress remain Navigation previews; they describe current local
  review surfaces and do not claim execution, tracking, analytics, or follow-up.
  A focused target-surfaces controller owns these actions without introducing a
  participant store or changing workspace preset and safety-bar ownership.
- Summary persistence is asynchronous. A failed Hub write retains the reviewed
  draft and exact payload for retry, while exports identify and reference the
  last committed artifact or label the legacy file export as an uncommitted
  fallback.
- `DirectorAgent` and `ActorAgent` remain the unchanged Story Catalyst path.
  Workshop specialists do not vote or create closure.

#### **ReadyMade**
- Agentic content planning/creation workflows built atop Synesyn stack.
- Consumes the shared substrate for “found concepts” and produces publishable artifacts.

---

## 3) The decisive refinement: Synesyn Hub + Latent Substrate as system-of-record

### 3.1 Why the hub exists
To keep Synesyn future-proof and multi-surface, **the canonical “core engine” lives outside Godot**:
- **Python Synesyn Hub** owns the canonical data model, event normalization, provenance, storage, and heavy compute.
- **Godot** becomes a first-party client UI/runtime: it renders, edits, orchestrates, and stages experiences, but does not have to be the canonical store.

This preserves the option to add a future UI client (React/Electron) by implementing a new client against the same hub API.

### 3.2 Latent Substrate (core concept)
The **LatentSubstrate** is the shared, inspectable substrate that makes “latent reality” pragmatic:
- **Entities**: concepts, signals, sessions, characters, documents, images, nodes, clusters, prompts, workflows, metrics, etc.
- **Relations**: typed edges between entities (e.g., “supports”, “contradicts”, “derived_from”, “located_at”, “mentioned_in”, “cluster_member”).
- **Representations**:
  - embeddings (text/image/audio)
  - projections (2D/3D coordinate sets with method metadata)
  - labels/tags/ontologies
  - “closures” (saved views/slices/constraints)
- **Provenance**:
  - source references (file, url, session, sensor source)
  - model/workflow versions and seeds
  - transformation metadata (who/when/which tool produced it)

**Core principle**: *Anything that matters is persisted as an artifact with provenance.*

---

## 4) External services (local-first) and responsibilities

### 4.1 Synesyn Hub (Python) — single local service process
The hub should be one process that hosts multiple capabilities behind one local API.

**Owns**:
- LatentSubstrate persistence and retrieval (system-of-record)
- Sensor ingestion normalization + timestamps + sequencing
- Realtime event broadcast to clients (WebSocket/SSE)
- Batch jobs (“dreaming”) scheduling and execution
- Optional heavy compute adapters (embeddings, big projections, etc.)

**Does not own**:
- Godot scene rendering, interaction, or UI presentation
- ComfyUI internals (ComfyUI stays a separate engine)

### 4.2 ComfyUI (external engine)
ComfyUI runs as its own process (local or hosted), and Synesyn uses it via:
- A **Godot-side bridge** (SynPunktRenderBridge) based on the WebSocket workflow pattern in **Godot-Comfy-AI**.
- Optionally, the hub can also submit jobs to ComfyUI for non-interactive/batch workflows.

Reference integration approach: `arigbs/Godot-Comfy-AI` ([GitHub](https://github.com/arigbs/Godot-Comfy-AI)).

### 4.3 `syntree_voice` (external Python service; conceptually “SynTree Voice”)
`syntree_voice` runs externally (Python) but is productized as a SynTree capability:
- **Conceptual namespace**: SynTree Voice
- **Runtime topology**: hub plugin (or hub-managed sidecar) to keep “one service endpoint” for users

---

## 4.4 Context isolation and opt-in bridging (critical)

Synesyn runs multiple “surfaces” that can all call LLMs:
- **SynTree editor panel** (developer/authoring surface)
- **ScenSyn runtime sessions** (client/user surface)
- ReadyMade, Synesyn Tools (shared tools shell; also reachable from ScenSyn), API-first clients

**Non-negotiable rule**: these surfaces must be **isolated by default** to prevent metaprompt/context bleed.

### Isolation requirements (v0)
- **Conversation history isolation**:
  - SynTree editor chat and ScenSyn session chat must not share the same thread store.
  - Thread storage is under `user://synesyn/conversation_threads/<scope>/...` (per-scope).
  - Standard scopes:
    - `syntree_editor`
    - `scensyn_session`
- **Context injection isolation**:
  - SynTree’s `ContentBus` active sources must not automatically flow into ScenSyn prompts.
  - Cross-surface “use SynTree sources in ScenSyn” must be an explicit, user-visible opt-in.

### Opt-in bridging (supported, explicit)
For metafuturism practice, there are valid cases where ScenSyn wants curated context from SynTree.
This is supported as an explicit toggle (no hidden flags):
- **ScenSyn** exposes a UI toggle: “Include SynTree content sources in ScenSyn prompts”.
- The choice is persisted to runtime config under an app namespace:
  - `apps.<app_id>.include_syntree_context` (example: `apps.scensyn.include_syntree_context`) (see runbook).

### What we *do not* want
- Any implicit sharing of:
  - conversation threads
  - metaprompt layers
  - content source selection state
between SynTree and runtime apps.

---

## 5) Sensors and realtime I/O (Stochastic Dreams–style requirements)

### 5.1 Default flow (recommended)
**Sensors → Hub (UDP) → Clients subscribe (WebSocket/SSE)**

Benefits:
- One system-of-record (LatentSubstrate)
- Multi-client support (kiosk + facilitator + API consumer)
- Auditable replay (replay last N seconds or entire sessions)

### 5.2 Latency strategy (pragmatic)
- Run hub **locally** on the kiosk machine for realtime sessions.
- Split paths:
  - **Realtime**: parse/validate → broadcast immediately
  - **Durable**: enqueue writes; persistence must not block realtime fan-out
- Normalization fields required:
  - `source_id`, `seq`, `t_device`, `t_hub_received`, `payload`, `schema_version`
- Provide ring buffer + replay:
  - clients can request “last N seconds” at connect time

### 5.3 Fallback mode
Optional emergency: **Sensors → Godot directly** (degraded mode).
This is a fallback only; canonical recording should be hub-backed.

---

## 6) “Dreaming” (batch synthesis) and SynAxes integration

The “dreaming” concept is implemented as a hub-side batch pipeline:
- Inputs: session traces + artifacts (day’s logs, sensor streams, prompts, generated images)
- Jobs (SynAxes-like):
  - embeddings, clustering, hub/bridge detection
  - projection generation (UMAP/t‑SNE/PCA)
  - summarization into “chronicles” / memory blocks
- Outputs: persisted as **new substrate artifacts** with provenance

This enables:
- ScenSyn’s “Echo” to cite stable memory artifacts
- repeatable analytics instead of ad-hoc summaries
- auditability: “why did we conclude this pattern exists?”

---

## 7) Packaging and executable strategy (client-first but platform-owned)

### 7.1 Default shipping artifact
Ship **`Synesyn.exe`** as the primary entrypoint to support the platform + SaaS goals, but configure it to be **app-first**:
- Default boot: **directly into ScenSyn**
- “Platform surface” (app switcher, dev tools) hidden behind Settings / Developer Mode

### 7.2 Additional exports (optional)
Also export **`ScenSyn.exe`** for:
- kiosk deployments
- “single-purpose” client deliverables
This is a different export preset/entry scene, not a different architecture.

---

## 8) One-zip, no-command-line deployment model

### 8.1 Zip layout (example)
```
Synesyn/
  godot/
    Synesyn.exe
    Synesyn.pck
    config/
  services/
    hub/
      hub.exe               # or embedded-python launcher
      config.yaml
      plugins/
        syntree_voice/
        synaxes_jobs/
      logs/
    comfyui/                # optional “bundled” mode or user-configured path
      ComfyUI/...
      start_comfyui.(bat|exe)
```

### 8.2 Service management UX in Godot
Provide a Synesyn “Services” panel:
- Start/Stop Hub
- Start/Stop ComfyUI
- Status indicators (health, last packet, connected sources)
- Open Logs
- Configuration (ports, paths, provider selection)

Implementation: Godot uses `OS.create_process()` to start services and polls `/health` and WebSocket connectivity.

---

## 9) Provider modes (local / BYO / hosted) without “microservice sprawl”

For each capability, offer a simple mode selector:

### LLM provider (SynTree / orchestration)
- Local (if applicable)
- BYO endpoint/keys
- Hosted (SaaS)

### Render provider (ComfyUI)
- Local ComfyUI
- BYO ComfyUI URL
- Hosted GPU (SaaS)

### Voice provider (SynTree Voice)
- Local hub plugin
- Hosted voice (SaaS)
- Off

**Rule**: Godot and apps call one interface; mode only changes which adapter is used.

### 9.1 Per-scenario per-agent model routing (implemented May 2026)

ScenSyn's Director/Actor pipeline supports routing individual agent calls to a
different model from the global current model, without changing the global
selection and without adding any configuration surface outside the scenario file.

**How it works:**

Any scenario `.txt` file can declare optional keys in `[SYSTEM_CONFIG]`:

```
[SYSTEM_CONFIG]
director_model: gpt-4o-mini
actor_model: claude-sonnet-4-6
```

`DirectorAgent` reads `director_model`; every Actor call in that scenario reads
`actor_model`. Both are forwarded as a per-call `model_override` argument through:

```
ConversationManager.chat(prompt, thread, model_override)
  → APIService.process_message_with_history(messages, context, model_override)
    → chat_completion(effective_model, messages, settings)
      → loader.prepare_request(messages, system_prompt, effective_model)
```

Each concrete model loader (`AnthropicModelLoader`, `OpenAIModelLoader`,
`OllamaModelLoader`, etc.) uses `effective_model` for the request body,
max-token lookup, and cache-eligibility decisions **without mutating its
internal `model_name` state**. The global current model selected in the
SynTree editor panel is never disturbed.

**Rationale**: The Director makes a structurally simple one-sentence-per-speaker
decision. The Actor makes the performance-quality call the user sees. Routing
them to different models is the single highest-ROI cost/latency lever available
without changing any prompt or agent logic.

**Observability**: Every `ConversationManager.chat()` call emits one line to
stdout, regardless of whether a model override is active:

```
[budget] director_tactical_batch 4.8k chars (gpt-4o-mini)
[budget] actor_diviner 3.2k chars (claude-sonnet-4-6)
```

This line is always on and needs no configuration. It appears in the same output
stream as `[ActorAgent]`, `[DirectorAgent]`, and `[Validator]` diagnostics.

---

## 10) Open-core business alignment hooks (without premature complexity)

To align with the open-core model while keeping the initial build simple:
- Reserve a **capabilities registry** concept in config:
  - what’s enabled (open vs premium)
  - what provider mode is active (local/BYO/hosted)
- Ensure **artifact provenance** is always recorded (even in open/local mode).
- Add extension points for future:
  - Impact Toolkit (pre/post measures, reporting artifacts)
  - Ethics/consent capture and audit flows

---

## 11) Naming clarifications (to prevent confusion)

- **Synesyn**: the platform and plugin ecosystem (ships as `Synesyn.exe`)
- **ScenSyn**: flagship application built on Synesyn
- **SynPunkt**: the canvas (2D/3D mapping and navigation)
- **Comfy bridge**: an integration module (e.g., `SynPunktRenderBridge`), not the definition of SynPunkt
- **SynTree Voice**: a SynTree capability implemented via hub plugin/service (`syntree_voice`)

---

## 12) Implementation checkpoints (what “done” looks like)

Minimum viable platform alignment:
- `Synesyn.exe` boots into ScenSyn by default
- Hub runs locally, provides:
  - `/health`
  - `/ws/events` (or SSE)
  - substrate CRUD for sessions/artifacts
  - sensor ingestion endpoint(s) (UDP receiver + normalization)
  - voice endpoint (via `syntree_voice`)
- Godot Services UI can start/stop hub + ComfyUI and show status
- ScenSyn can:
  - consume live sensor events via hub subscription
  - write session logs + key artifacts into substrate
  - trigger render jobs (local ComfyUI via bridge) and register outputs as artifacts with provenance

---

## Appendix A — Suggested minimal “event” envelope (hub → clients)

The hub should broadcast events using a stable envelope:
- `schema_version`
- `event_id`
- `event_type` (e.g., `sensor.pendulum`, `session.turn`, `render.completed`)
- `source_id`
- `seq`
- `t_device` (optional)
- `t_hub_received`
- `payload` (typed per event_type)
- `provenance` (optional linkages to session/artifact ids)


