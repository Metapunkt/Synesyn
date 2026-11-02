# To‑Do — SynTree (Editor assistant + semantic/LLM wrapper)

**Primary spec references**
- `../../SYSTEM_MAP.md` (documentation ownership, precedence, change workflow, verification)
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Synesyn_Hub_API_Spec.md` (provider modes + potential hub calls)
- `../LatentSubstrate_Data_Model.md` (artifact/provenance expectations)
- `../Human_Agency_UX_Contract.md` (Propose → Preview → Commit → Version)

**What’s already covered / existing**
- SynTree has an explicit internal architecture doc and guardrails:
  - `scensyn_dec2025/addons/godot_syntree/docs/architecture.md`
- SynTree already functions as:
  - editor panel UI
  - conversation/thread management
  - API services + model management (in current plugin form)

---

## Priority guide
- **v0 MVP**: keep SynTree stable; only add thin integration points needed by the platform (status indicators; optional artifact persistence).
- **v1**: split runtime-safe core vs editor UI; consolidate provider modes; standardize thread↔substrate mapping.
- **later**: deep substrate-first workflows, richer tool-calling, advanced governance/analytics integrations.

## A) Split responsibilities cleanly: runtime-safe core vs editor UI
- [x] (v1) Create/confirm a “core” layer that can be used by apps (ScenSyn/ReadyMade) without editor-only dependencies. (`SynTreeCore`, `SynTreeRuntimeInstaller`)
- [x] (v1) Ensure editor plugin UI depends on core (one-way), not vice versa. (core is runtime-safe; UI uses autoload/services)
- [x] (v1) Define a stable public API surface for apps (GDScript interfaces/classes). (core entrypoint + autoload access conventions)

## B) Provider modes (local/BYO/hosted) alignment
- [x] (v1) Add a provider selection mechanism consistent with `Local_Deployment_Runbook.md`:
  - [x] (v1) local (Ollama discovery, health, capabilities, metrics, cancellation, streaming, residency controls)
  - [x] (v1) BYO keys/endpoints (shared `ProviderModePolicy` / runtime config)
  - [ ] (later) hosted (SaaS)
- [x] (v1) Ensure provider choice is centralized and shared across apps (no per-app drift).
- [x] (v1) Per-call model override: `ConversationManager.chat()` accepts an optional `model_override` string; plumbed through `APIService` and all six provider loaders without mutating global selection. Enables per-scenario per-agent routing via `[SYSTEM_CONFIG]` keys `director_model` / `actor_model`. See `../Synesyn_Platform_Technical_Architecture.md` §9.1 and `../SynTree_as_a_Synesyn_runtime_module.md`.

### B.1) Ollama local-provider hardening
- [x] Discover installed models from `/api/tags`; retain the legacy model list only as an offline fallback.
- [x] Inspect `/api/show` metadata for context limits and model capabilities, and expose parameter size/quantization in the selector.
- [x] Stream ordinary SynTree chat through a cancellable `HTTPClient` path while preserving the completed-response contract; keep structured Workshop Catalyst tasks on non-streaming JSON requests.
- [x] Reject overlapping Ollama inference with an actionable `ollama_busy` result and support cancellation by request ID or for all active requests.
- [x] Parse Ollama timing/token metrics and expose prompt/output counts, generation rate, load duration, and provider status in the SynTree model strip.
- [x] Query `/api/ps`, unload the prior Ollama model on model changes, and retain the bounded five-minute `keep_alive` policy.
- [x] Persist a configurable Ollama HTTP/HTTPS origin in canonical runtime config, expose Apply/Refresh controls, and route discovery, control, and streaming requests through it.
- [x] Use discovered context limits conservatively for SynTree source-context trimming: reserve capacity for instructions/history/output and retain the existing 20k-character per-source ceiling.
- [x] Cover discovery metadata, capability mapping, metrics, NDJSON streaming, and status UI with `test_ollama_integration.gd`.

## C) LatentSubstrate integration points (optional but strategic)
- [x] (v0) When SynTree produces important outputs (metaprompts, analyses), optionally persist them as artifacts:
  - [x] (v0) `text.prompt`
  - [x] (v0) `text.summary`
  - [x] (v0) `json.metrics` (where relevant)
- [x] (v0) Add minimal provenance stamps for persisted artifacts:
  - [x] (v0) model name/version
  - [x] (v0) tool version
  - [x] (v0) input sources (document ids, selection context) (baseline thread/scope refs)

## D) Thread/session semantics (avoid fragmentation)
- [x] (v1) Define mapping from “SynTree conversation threads” → substrate sessions/artifacts:
  - [x] (v1) local caching in plugin is allowed
  - [x] (v1) substrate is system-of-record when hub is running (best-effort hub persistence + local index)
- [x] (v1) Provide export/import of threads as artifacts (for replay/audit) via `chat.thread` versions + “Hub Versions” load/import UI.

## D.2) Thread disk authority rules (v0 stability guardrail)
- [x] (v0) Disk is the source of truth for thread existence and content:
  - [x] ThreadDropdown options are populated from existing `*.json` in the threads folder (plus `default`).
  - [x] Selecting a thread reloads its JSON; UI shows only the selected thread’s messages.
- [x] (v0) Prevent confusing overwrites/recreation:
  - [x] Do **not** “touch-save” threads on startup.
  - [x] Do **not** flush/save all threads on shutdown (can recreate deleted JSON).
  - [x] Only write a thread JSON when the selected thread is explicitly mutated:
    - user prompt appended
    - assistant response appended
    - edit-history saved
    - new thread created (explicit)

## D.1 Context isolation (critical; implemented baseline)
- [x] (v0) Ensure SynTree editor chat and ScenSyn runtime chat are isolated by default:
  - [x] thread storage is scoped (e.g., `syntree_editor` vs `scensyn_session`)
  - [x] SynTree `ContentBus` context injection is opt-in for ScenSyn (no automatic bleed)
- [x] (v1) Extend scoping to other apps/clients (ReadyMade, Studio) and define a naming convention for scopes. (documented + enforced “set scope before setup()” convention)
- [x] (v1) Optional: allow “bridge artifacts” instead of direct content injection:
  - [x] (v1) ScenSyn selects a `ui.context_graph` artifact id and passes it to hub/LLM as a reference (preferred for auditability). (optional `bridge.ui_context_graph` helper + publish toggle)

## E) Tool-call interface for Metapunkt (and beyond)
- [x] (v1) Standardize tool-call request schema used by Metapunkt:
  - [x] (v1) operation names (`chat`, `analyze_content`, etc.)
  - [x] (v1) args structure
  - [x] (v1) error handling
- [x] (v1) Ensure tool-call results can be logged to substrate with provenance.

## F) UX: keep SynTree editor experience excellent
- [x] (v0) Maintain architecture constraints for Content Sources UI:
  - no `ContentBus` discovery inside views
  - inject `ContentStateResource` + `ViewStateResource`
  - coordinator-driven tab switching
  - reference: `../completed/SynTree_Content_Sources_View_Orchestration.md`
- [x] (v0) **UI signal wiring policy**: prefer wiring critical UI button signals in `.tscn` (scene connections) rather than runtime `pressed.connect(...)` in editor plugins, since editor docks/windows can re-instance/reparent controls and silently drop runtime hookups.
- [x] (v0) Add a visible “Provider / Service Status” indicator:
  - [x] (v0) hub reachable?
  - [x] (v0) voice available? (surfaced via hub /health capabilities)
  - [x] (v0) current model/provider active?
- [x] (v0) Add a **Prompt Chain Editor (local-first scaffold)**:
  - [x] Prompt Chains surface lives under “Conversation Manager” (not mixed into Content Sources tabs)
  - [x] Thread-scoped settings: asset vs thread-local draft; “apply to chat”
  - [x] Local persistence under `user://synesyn/prompt_chains/<scope>.json`
  - [x] When “apply to chat” is enabled, the chain compiles into a prefix for the system/context prompt
- [x] (v0) Chat output rendering supports fenced code blocks:
  - [x] Assistant messages split markdown fences (```lang ... ```) into `CodeBlock` UI blocks + normal text.
  - [x] Editing/export uses the stored raw message content (not scraped from UI nodes).
- [ ] (v1) Upgrade Prompt Chains into substrate-first, versioned assets:
  - [x] (v1) Persist `ui.prompt_chain` artifacts to hub with provenance (see `../LatentSubstrate_Data_Model.md`)
  - [x] (v1) Add slot definitions (type/locked/default) + UI for editing slot values
  - [x] (v1) Add “Save as new version” (hub versions list + load/import; diff/compare remains later)
  - [ ] (v1) Add explicit “Propose → Preview → Commit → Version” workflow and commit events

## H) Stacks as orchestration assets (SynTree Content Sources)
Reference: `../completed/SynTree_Content_Sources_View_Orchestration.md` (Stacks — normative semantics)

- [x] (v0) **UI indicator: Stack badge** in Content Sources list rows (e.g. “STACK” tag/icon).
- [x] (v0) **UI indicator: Stack badge** in Hierarchy and Graph headers when the current source is a stack.
- [x] (v0) **UI indicator: Unwired count** for stacks (e.g. “Unwired: N”) in the stack header/status strip.
- [ ] (v1) **Stack settings**: add `include_unwired_nodes` (default true) stored on stack root `meta.ai_context`.
- [ ] (later) Stack utilities:
  - [ ] “Auto-wire by layout (left→right)”
  - [ ] “Make linear chain from selection”

## I) Context Graph — visual context-engineering workspace

**Status**: Approved direction; implementation not started.

**Intent**: Evolve the existing Graph View from a mostly spatial parent/child editor into SynTree's inspectable workspace for controlling what context an AI receives, why it receives it, and what effect that context has. The Context Graph remains one of three permanent peer views—**List / Hierarchy / Context Graph**—and must not be hidden or auto-selected based on graph complexity.

**Confirmed boundaries**
- Rename the user-facing **Graph** / **Graph View** label to **Context Graph**. Internal class/file renaming is optional and should occur only where it improves clarity without creating migration risk.
- List and Hierarchy remain available and behaviorally unchanged.
- Context Graph owns content/source relationships, context assembly, and context-use inspection.
- Prompt Chains keep their separate linear block editor. Context Graph may supply named context sets and traversal rules to a prompt chain, but it must not become the Prompt Chain graph editor.
- Context Graph and Workshop Catalyst's Live Thinking Map share a runtime-safe **Graph Workspace** foundation for graph documents, typed relationships, proposal states, provenance, layout, inspection, diff/version support, and Hub artifact handling.
- The two products keep separate adapters, semantics, controllers, and artifact types: `ui.context_graph` is not a workshop thinking-map record.
- Hub remains the system-of-record for published/versioned `ui.context_graph` artifacts; Godot remains the authoring and inspection client.
- AI may propose nodes, edges, clusters, and rules, but only the user may commit them.

### I.0 Dependency map

```text
I.1 Protocol + baseline
    └── I.2 Rename + modularize
            └── I.3 Typed relationships
                    ├── I.4 Context compiler + budget preview
                    │       ├── I.5 Activation rules + named context sets
                    │       │       └── I.6 Prompt Chain integration
                    │       └── I.7 Run trace + explainable retrieval
                    └── I.8 Provenance + evidence quality
                            └── I.9 AI-assisted proposals

I.5 + I.7 + I.8
    └── I.10 Diagnostics + version comparison
            └── I.11 Scale, focus, and performance hardening
```

Typed relationships are the semantic foundation. Context compilation and provenance can then progress in parallel. AI-assisted editing must wait until proposal/commit semantics and provenance are in place.

### I.1 Stage 0 — Protocol, contracts, acceptance, and baseline

**Goal**: establish source-of-truth ownership and capture current behavior before changing it.

- [x] Create a concise SynTree Context Graph PRD under `docs/product-requirements/` defining users, problems, outcomes, journey, success measures, and acceptance links—not schemas or implementation tasks. (`PRD-SYNTREE-CONTEXT-GRAPH.md`)
- [x] Record an ADR under `docs/architectural-decisions/` for the substantive choice: Context Graph is a semantic context-engineering workspace, remains a peer view, and is distinct from the Prompt Chain editor. (ADR 0008)
- [x] Include in that ADR the shared Graph Workspace boundary: reusable graph mechanics and human-agency behavior, with product-owned adapters and artifact schemas for SynTree and Workshop Catalyst.
- [x] Update `LatentSubstrate_Data_Model.md` before implementation with the Shared Graph Workspace envelope v1 and enhanced `ui.context_graph` v2 contract covering stable node/edge ids, typed relationships, annotations, activation rules, named context sets, provenance, proposal state, and compatibility with existing `ui.context_graph` schema v1.
- [x] Update `Human_Agency_UX_Contract.md` to explicitly cover graph edits and AI graph proposals under Propose → Preview → Commit → Version.
- [x] Review `Synesyn_Hub_API_Spec.md`; no dedicated route is required for the initial scaffold because existing generic artifact operations remain sufficient. Revisit when validation, comparison, compilation, or trace transport is implemented.
- [x] Add executable model/serialization tests for existing graph behavior and existing `ui.context_graph` schema-v1 round trips before schema work:
  - [x] Pure graph-operation tests: child/parent symmetry, existing dependency/association storage, stack edges/layout, and node positions.
  - [x] Shared Graph Workspace envelope validation and semantic-layout separation tests.
  - [x] Controller routing tests for ordinary/stack positions and connection add/remove/deduplication.
  - [x] Extract and test the existing publisher payload builder, including the exact schema-v1 node, stack-edge, selection, and version shape.
  - [x] Resource-layer node deletion tests covering complete stale-reference normalization and node-to-source mapping cleanup.
  - [x] Stack composition test covering member-source composition, composed ids, GraphEdit insertion, and persisted layout.
- [x] Add a Context Graph acceptance section to `docs/technical-review/03_review_checklists.md`, linked from the PRD.
- [ ] Capture a baseline using simple, hierarchical, relationship-rich, and multi-source stack fixtures:
  - all three views switch correctly;
  - node movement and layout persistence work;
  - ordinary and stack connections persist;
  - Active and Metaprompt state remains synchronized;
  - node deletion cleans references;
  - publishing produces a loadable `ui.context_graph`;
  - SynTree chat context remains isolated from ScenSyn unless explicitly bridged.
- [x] Run `python synesyn/utilities/checks/check_line_limits.py --check-baseline`. (Passed after Stage I.2 extractions; 525 scripts scanned, no new/worsened violations.)

**Gate**: PRD, ADR, normative contract delta, acceptance coverage, and green baseline exist before behavior-changing code lands.

### I.2 Stage 1 — Rename safely and split the graph controller

**Goal**: establish clear product language and create room for later features without growing existing large scripts.

- [x] Change user-facing labels, tooltips, context-menu entries, reviewer text, and documentation from Graph View to **Context Graph**.
- [x] Preserve `ViewMode.GRAPH`, serialized ids, node paths, and existing class/file names during the first pass unless a migration is explicitly tested; this is a UI-language change, not a data migration.
- [x] Keep Context Graph permanently available beside List and Hierarchy. Do not add complexity-based automatic view switching.
- [x] Split `content_graph_controller.gd` before adding features. Retain it as coordinator and extract focused collaborators for:
  - [x] first extraction: movement and legacy ordinary/stack connection routing moved to `GraphPersistenceCommands`, with stack edge mutation owned by `ContentStateResource`/`ContentStackOps`;
  - [x] graph persistence and schema-v1-to-v2 compatibility migration;
  - [x] relationship command dispatch extracted while preserving legacy child-edge behavior;
  - [x] stack composition moved to `GraphStackComposer` with controller-owned node factory/signal wiring;
  - [x] selection routing moved to `GraphSelectionCoordinator`; layout writes remain in `GraphPersistenceCommands`.
- [x] Move node deletion/unlinking out of `ContentGraphController` and `ContentHierarchyView` into `ContentStateResource`; preserve normalization across all current relationship arrays and clear stale node-to-source mappings.
- [ ] Extract reusable mechanics into a runtime-safe Graph Workspace module rather than a SynTree UI namespace:
  - [x] `GraphWorkspaceDocument` primitives validate stable nodes, typed edges, proposal/review state, and provenance references;
  - [x] graph validation, semantic diff, and layout-state separation;
  - [x] reusable GraphEdit canvas, relationship rendering, selection, and layout persistence (`scripts/graph_workspace/graph_workspace_canvas*`); product adapters own review/inspector chrome (WC Map uses a selected-node review strip). Full shared inspector contract remains open if SynTree needs richer shared chrome later.
  - [x] a Hub artifact client/facade for load, commit, version, and trace references.
- [ ] Add a SynTree `ContextGraphAdapter` that maps content sources, chunks, stacks, Active/Metaprompt compatibility, context sets, and compiler behavior onto those shared primitives.
  - [x] Deterministic schema-v1-to-v2 migration that requires an explicit new commit and preserves the legacy artifact.
  - [x] Source, stack, chunk, legacy relationship, Active/Metaprompt, and initial active-source context-set mapping.
  - [ ] Context compiler behavior (Stage I.4) and activation-rule execution (Stage I.5).
- [x] Keep Workshop Catalyst out of the SynTree addon dependency graph; it will consume the shared module through its own `ThinkingMapAdapter`.
- [x] Keep static inspector/tool UI in `.tscn` scenes; instantiate code nodes only for genuinely dynamic graph items.
- [x] Remove only verified-dead legacy graph wiring (`Toggle_Graph_Tree_View`, stale graph-update signal, legacy no-ops) as an isolated refactor batch. (No commit was created because none was requested.)
- [x] Update `addons/syntree/docs/architecture.md` to describe the current `ContentStateResource` / `ViewStateResource` ownership rather than reviving legacy `ContentBus` discovery inside views.

**Guardrails**
- Pure rename/refactor first: no graph semantics change in this stage.
- Preserve current node ids, persisted positions, stack edges, Active/Metaprompt behavior, and tab indices.
- Views receive injected resources; they do not discover global state.

**Verification**: repeat the Stage 0 baseline; run line-limit enforcement; manually verify every entry point says Context Graph.

**Rollback**: label and refactor commits remain separate so either can be reverted independently.

### I.3 Stage 2 — Typed, annotated relationships

**Goal**: make graph connections express meaning unavailable in List or Hierarchy.

- [x] Define a small controlled v1 relationship vocabulary in the normative data model:
  - structural: `contains`, `part_of`;
  - dependency: `depends_on`, `precedes`;
  - evidential: `supports`, `contradicts`, `derived_from`;
  - semantic: `refines`, `example_of`, `related_to`.
- [x] Decide and document inverse-edge behavior. Store one canonical directed edge; derive inverse labels for display where appropriate rather than silently duplicating records.
- [x] Give every edge a stable id and fields for `relation`, optional explanation/notes, confidence, provenance, status, and creation/update timestamps.
- [x] Add a `.tscn`-authored Relationship Inspector opened immediately for new connections and through its existing-edge selector.
- [x] Add an explicit connection workflow: choose relationship type immediately after drawing an edge; cancelling removes the uncommitted visual connection, and direct disconnection is restored until confirmed.
- [ ] Render edge types distinctly using restrained color, line style, direction markers, and a legend that remains legible under existing light/dark themes. (Completed: category-colored connection ports/lines, directed endpoints, and a theme-safe legend. Remaining: optional per-relation line-style differentiation beyond category color.)
- [x] Add keyboard-accessible create, edit, reverse, and disconnect actions with confirmation where data would be lost. (Endpoint selectors provide keyboard-only relationship creation; inspector actions and disconnect confirmation use standard keyboard focus.)
- [x] Add cycle validation for structural relations while permitting valid cycles for associative/evidential relations.
- [x] Migrate legacy ordinary parent/child edges deterministically to the agreed structural type; retain legacy reading and projected-edge removal support without destructive rewrite.
- [x] Upgrade stack edges from bare `{from,to}` records to typed edges while preserving v0 stack loading and legacy canvas rendering.
- [x] Ensure Hierarchy and stack ordering derive only structural containment and do not flatten semantic edges into parent/child.

**Verification**
- [x] Round-trip every relationship type through the rich-edge store; verify source/stack persistence and `ui.context_graph` adapter mapping.
- [x] Test invalid structural cycles, duplicate edges, edge reversal, self-edges, node deletion, and cross-source stack edges.
- [x] Confirm old source files and v0 context-graph artifacts still load without destructive rewrite.

### I.4 Stage 3 — Context compiler, preview, and token budgeting

**Goal**: show exactly what SynTree will send to the model before it is sent.

- [x] Introduce a runtime-safe `ContextCompiler` service in SynTree core; UI controllers call it but do not implement compilation rules.
- [x] Define a deterministic compilation result containing:
  - included node ids and ordering;
  - inclusion reason and traversal path per node;
  - omitted/truncated nodes and reasons;
  - compiled context text;
  - token estimate and estimator/model identity;
  - graph/context-set version used.
- [x] Add a Context Preview panel showing final compiled context, inclusion reasons, ordering, omissions, and token budget before chat submission. (The `.tscn`-authored sidebar panel uses the shared compiler bridge and freezes the enabled preview for exact next-submission parity.)
- [x] Add estimated token cost per included/omitted node and for the complete context package, including UI display.
- [ ] Support user-controlled budget strategies: pinned essentials, priorities, relationship depth, branch summarization, and explicit truncation policy. (Pinned essentials, relationship depth, allowed relations, and explicit token-budget omissions are implemented; priority and branch summarization remain.)
- [x] Offer Full, Balanced, and Minimal as editable starting presets—not opaque automatic modes.
- [x] Add an opt-in `ConversationChatContextBuilder` path that consumes the same `ConversationContextCompilerBridge` result intended for Preview; legacy Active-source injection remains the default until UI parity acceptance is complete.
- [ ] Record compiler configuration and context-graph artifact id/version in chat provenance.

**Guardrails**
- Token counts are labelled estimates unless produced by the exact provider tokenizer.
- Pinned or locked content is never silently dropped.
- Compilation is deterministic for the same graph version, rules, model budget, and inputs.
- Preview must not trigger an LLM call or commit.

**Verification**
- [x] Golden tests assert deterministic traversal, inclusion reasons/paths, pinned-budget behavior, rejected-node omission, and exact equality between bridge preview text and submitted compiler context.
- Boundary tests cover empty graphs, oversized nodes, locked content exceeding budget, cycles, unavailable tokenizer, and disconnected nodes.
- Existing Active-source injection remains available behind a compatibility path until compiler parity is proven.

### I.5 Stage 4 — Activation rules and named context sets

**Goal**: move beyond one global Active checkbox while keeping context behavior inspectable.

- [x] Add explicit activation modes: Always, When Relevant, Conditional, Manual Only, and Excluded. (`ContextActivationPolicy`)
- [x] Support conditions based on transparent inputs such as tags, thread/app scope, prompt-chain id, slots, and maximum traversal depth. (Condition matching is deterministic; traversal depth remains context-set/compiler policy.)
- [x] Define deterministic precedence for node rules, context-set/compiler policy, review state, and explicit user pins in the normative data model and executable tests.
- [x] Keep the existing Active checkbox as a simple projection of the new model during migration; the adapter continues to generate the `active-sources` entry set rather than writing a contradictory node mode.
- [x] Add named context sets containing entry nodes, traversal/edge filters, activation rules, budget policy, and optional prompt-chain bindings. (`ContextSetStore` normalizes and persists local named sets; `ContextGraphAdapter` maps them to collision-safe artifact ids.)
- [x] Persist committed named sets within versioned `ui.context_graph` artifacts, with local drafts permitted under the existing local-first policy. (Commit requires an exact current preview, writes immutable Hub lineage through `GraphWorkspaceArtifactClient`, then marks the local set committed.)
- [x] Provide duplicate/fork, rename, preview, commit, and version-history actions. (The `.tscn`-authored Context Sets tab supports local draft create/rename, duplicate/fork, delete, node-entry and relationship filters, budget/depth policy, prompt-chain ids, exact preview, explicit Hub commit, and owner-scoped history.)
- [ ] Make cross-surface use explicit: applying a SynTree context set in ScenSyn/ReadyMade requires a visible bridge artifact selection and an auditable event.

**Verification**
- [x] Rule-precedence, explicit-condition scope, activation persistence, adapter mapping, Context Set UI/controller, and compiler-override tests.
- [x] Context sets compile identically after save/load and Hub JSON round trip in the artifact-client regression fixture. (Live-Hub transport remains covered by the existing generic client integration path.)
- [x] Switching threads or apps cannot silently activate a context set from another scope. (There is no automatic context-set selection; explicit node conditions are scope-tested, and history queries are owner-scoped.)

### I.6 Stage 5 — Prompt Chain integration without editor conflation

**Goal**: let prompt programs request controlled context while retaining their separate linear editor.

- [x] Extend `ui.prompt_chain` only through its owning normative contract to reference a context-graph artifact/version and optional named context-set id. (Schema v1 additive `context_binding`; `PromptChainStore` preserves normalized binding metadata.)
- [x] Allow individual prompt-chain blocks to request declared traversal/edge filters where needed. (Stable block ids and normalized `context_override` fields are persisted; `PromptChainContextResolver` applies the requested block override without moving blocks into the graph.)
- [x] In Prompt Chain Editor, display the bound context set, expected budget, and missing/stale reference warnings. (Static binding panel shows artifact/version/set/owner, preset, budget, resolver warnings, and compiled text.)
- [x] Selecting and previewing a prompt-chain binding highlights its included nodes transiently in Context Graph; changing chains/bindings or a failed preview clears the overlay, and chain blocks remain exclusively in the linear editor.
- [x] Prompt Chain compiled preview must include or link to the exact Context Compiler preview. (`PromptChainContextResolver` invokes the same deterministic compiler and the binding panel displays its exact output.)
- [x] A graph or context-set update does not silently mutate a committed prompt-chain version; require preview and a new version when rebinding. (Bindings pin artifact/version identifiers, binding edits are proposals, and Hub save rejects an unpreviewed binding.)

**Verification**
- [x] Resolver tests cover valid, missing artifact/set, unpinned-version warning, and unauthorized cross-scope references.
- [x] Prompt Chain order and current linear execution remain unchanged; bound context is appended exactly once and suppresses duplicate legacy/Active-source injection.

### I.7 Stage 6 — Execution traces and explainable retrieval

**Goal**: after a response, show what context was actually used and how it was reached.

- [x] Define a versioned context-execution trace contract in the appropriate normative store/data-model document, referencing rather than duplicating canonical graph and source content. (`json.context_execution_trace` v1 stores references, decisions, and a compiled-text hash; raw compiled context remains runtime-only.)
- [x] Record graph version, context set, compiler rules, included/omitted nodes, traversal paths, token usage/estimate, model/provider, prompt-chain identity, stable message ids, optional Store references, and optional resulting artifact ids. (`ContextExecutionTraceCoordinator` snapshots before the request, finalizes after response/failure, and persists to Hub without blocking chat.)
- [ ] Overlay the selected run on Context Graph:
  - [x] retrieved/included nodes;
  - [x] traversal paths in the trace inspector;
  - [ ] cited nodes when reliable citation data is available;
  - [ ] included but apparently unused nodes, explicitly marked as heuristic;
  - [x] relevant candidates omitted by rules or budget.
- [x] Add “Why included?”, “Why omitted?”, and “Show compiled context” inspectors. (The static Trace tab shows reasons, traversal paths, provenance/message references, and runtime-only compiled text; included/omitted canvas states remain transient.)
- [x] Distinguish deterministic facts (included, omitted, cited) from heuristic claims (“apparently unused”). (The v1 contract prohibits attention claims and does not manufacture usage labels when provider evidence is unavailable.)
- [ ] Allow rerun from a trace with edited rules; rerun creates a new trace/version and never overwrites history.

**Guardrails**
- Do not infer model attention from prompt inclusion. Label influence analysis as heuristic unless the provider supplies reliable evidence.
- Trace writes are non-blocking and must not prevent chat completion.
- Sensitive context follows existing consent and storage policy.

**Verification**
- [x] Trace-to-response and trace-to-graph referential-integrity tests.
- [x] Degraded-mode test: the completed local trace remains available and records a non-blocking warning if Hub trace persistence is unavailable.

### I.8 Stage 7 — Provenance and evidence quality

**Goal**: make every node and relationship auditable.

- [x] Expose origin, source location, source artifact/version, authoring method, timestamps, and derivation links in node/edge inspectors. (The static Provenance tab edits source/content-node records and opens recorded source locations; the Relationship Inspector preserves and displays edge provenance.)
- [x] Visually distinguish imported quotation, user-authored content, deterministic summary, AI summary, and AI inference. (Graph nodes show a non-color-only authorship/evidence badge with an authorship-specific accent.)
- [x] Add review/evidence status separate from relationship confidence; do not collapse “high confidence” into “verified”. (`ContextGraphProvenance` defines separate normalized enums; the Relationship Inspector edits and displays them independently of confidence.)
- [x] Surface supporting and conflicting evidence paths without treating either as automatically decisive. (The Provenance tab lists incident `supports` and `contradicts` paths while keeping evidence status independently editable.)
- [x] Provide source-location navigation where the underlying format permits it. (`res://`, `user://`, filesystem, and URL locations use an explicit Open source action.)
- [x] Ensure every compiled node can answer “where did this come from?” and every generated node can answer “what produced this and what did it use?” (`ContextGraphAdapter` emits normalized provenance plus compatibility refs for every source/content node and rich edge; unavailable fields remain explicit `unknown`.)

**Verification**
- Provenance survives node split/merge, edge editing, context-set compilation, artifact versioning, and export.
- Missing provenance is explicit (`unknown`/`not recorded`), never fabricated.

### I.9 Stage 8 — AI-assisted graph proposals

**Goal**: accelerate graph construction without surrendering user control.

- [x] Support proposals for relationships, duplicate/overlap detection, contradictions, clusters, missing links, node split/merge, and potential metaprompt material. (`ContextGraphProposalGenerator` accepts constrained proposal types/operations and returns validated suggestions only.)
- [x] Keep proposed records in a distinct proposal layer/status; never write directly into the committed graph. (`ContextGraphProposalStore` persists proposals under source `ai_context`; `ContextGraphProposalEngine` has no content-state, Hub, or commit methods.)
- [x] Provide accept, edit, reject, defer, batch review, and impact preview. (The static Proposals tab supports multi-selection review and editable JSON payloads.)
- [x] Show rationale, evidence references, model/provider, prompt/configuration, and confidence for each proposal.
- [x] Record accept/reject/defer decisions as events so rejected proposals are not repeatedly resurfaced without new evidence. (Review events are sent best-effort to Hub; signature-equivalent rejected/deferred suggestions are suppressed unless their evidence changes.)
- [x] Preview the effect on compilation, token budget, and affected context sets before commit. (Preview reports semantic id-based diff plus baseline/proposed inclusion and token estimates.)
- [x] Commit accepted changes as a new `ui.context_graph` version with complete provenance. (Commit is a separate human action, requires an unchanged accepted-proposal preview, marks materialized records committed, and advances graph lineage through `GraphWorkspaceArtifactClient`.)

**Verification**
- [x] Assert that model calls cannot invoke the commit path.
- [x] Proposal rejection leaves canonical graph and compiled context unchanged.
- [x] Batch acceptance remains reviewable as an explicit diff.

### I.10 Stage 9 — Graph health diagnostics and version comparison

**Goal**: help users maintain trustworthy context over time.

- [x] Add diagnostics for orphaned nodes, broken references, invalid structural cycles, duplicates, conflicting active instructions, stale source versions, unreviewed AI inferences, missing provenance, and token-budget overflow. (`ContextGraphDiagnostics` is deterministic and model-free.)
- [x] Classify diagnostics as error, warning, or information; each diagnostic links to the affected item and a safe repair preview. (Health tab focuses affected records with a transient orange overlay; repair descriptions are previews only.)
- [x] Add graph-version comparison for nodes, edges, annotations, activation rules, context sets, and provenance. (Comparison uses id-based full semantic records and ignores layout/viewport state.)
- [x] Add compiled-context comparison showing changed inclusions, ordering, token estimate, and final text. (Comparison reports ordered inclusion lists, additions/removals, token estimates, and privacy-safe compiled-text hashes.)
- [x] Where two runs are comparable, link graph/context differences to output differences without claiming unsupported causation. (`causation_claimed` is explicitly false.)
- [x] Support fork-from-version rather than overwriting an earlier graph. (Health tab creates a new Hub artifact with `previous_version_id`/`forked_from`, leaving the compared version immutable.)

**Verification**
- [x] Seeded diagnostic fixtures produce stable results.
- [x] Version diff is id-based, not layout-position-based; moving a node does not appear as a semantic change unless layout comparison is explicitly enabled.

### I.11 Stage 10 — Focus, filtering, accessibility, and performance

**Goal**: keep Context Graph usable as sources and stacks grow.

- [x] Add search/filter by source, tag, relationship type, activation state, proposal/review state, and provenance. (`ContextGraphFocusFilter` evaluates deterministic id/label, tag, relation, activation, authorship, and review filters.)
- [x] Add selected-node neighborhood focus with configurable depth.
- [x] Add collapse/expand for branches and user-approved clusters. (Focus tab accepts collapsed structural roots; descendants are hidden without changing graph semantics.)
- [x] Add show/hide controls for inactive, rejected, low-confidence, or unrelated items.
- [x] Persist named layouts separately from semantic graph data so visual rearrangement does not create semantic artifact versions. (`GraphWorkspaceLayoutStore` keeps explicitly named node/viewport layouts under `user://`; ordinary node movement no longer writes source/artifact semantics.)
- [x] Add minimap/overview and “fit relevant context” actions.
- [x] Add keyboard navigation, accessible relationship labels, non-color-only state indicators, and theme checks. (Directional arrow navigation, textual port/legend/state labels, and light/dark theme resource checks are covered.)
- [x] Move compilation, diagnostics, and large-graph layout off the immediate UI path; batch updates and cancel stale work. (Compilation, diagnostics, and filtering use deferred latest-request jobs; ordinary source canvases above 144 nodes render incrementally in 24-node main-thread batches and replacement builds cancel stale work.)
- [x] Set and test practical performance targets in the PRD/acceptance spec for graph opening, filtering, compilation, and interaction. (REQ-CG-014 covers deterministic 1,000-node pure-work ceilings and a 240-node rendered-canvas target with bounded per-frame growth.)

**Verification**
- [x] Test small, medium, and agreed large graph fixtures. (Focused tests cover small graphs, a 240-node incremental rendered canvas, and deterministic 1,000-node filtering, compilation, and diagnostics.)
- [x] Confirm semantic version hashes/diffs ignore transient selection, zoom, and unsaved viewport state.
- [x] Confirm no UI freeze during compilation, diagnostics, or Hub persistence. (Latest-request jobs defer expensive pure work; rendered canvas construction is frame-batched; Hub writes remain asynchronous.)

### I.12 Cross-cutting architecture and ownership

- [x] Shared Graph Workspace owns domain-neutral graph mechanics only: ids, nodes, typed edges, proposal states, provenance references, layout, validation, diff, canvas interaction, and artifact transport. (Workshop Stage 8 adapter-conformance and forbidden-dependency tests verify the runtime-safe document/validation/diff/transport/canvas subset and that `ThinkingMapAdapter` / WC graph projection import no SynTree content, compiler, controller, or editor semantics. Shared inspector chrome beyond product-owned review strips remains optional follow-up.)
- [x] `ContextGraphAdapter` owns SynTree semantics: sources/chunks/stacks, Active/Metaprompt migration, context rules, compilation, Prompt Chain bindings, and retrieval overlays.
- [x] `ThinkingMapAdapter` owns Workshop Catalyst semantics: Causes/Effects/Opportunities, live transcript-derived proposals, decisions/risks/owners/next steps, facilitator review, and Session Record/ClosureBus integration.
- [x] Shared primitives may be structurally compatible, but `ui.context_graph` and `ui.workshop_thinking_map` remain separate versioned contracts with explicit converters only where a user requests cross-surface use. (Cross-adapter conformance fixture and Hub discriminator rejection added in WC Stage 8.)
- [ ] The shared canvas must support batched incremental updates and non-blocking persistence so a live workshop does not rebuild the entire graph on each transcript or synthesis event.
- [ ] `ContentStateResource` owns working graph state and commands; views render state and emit user intent.
- [ ] `ContentViewManager` continues to own List/Hierarchy/Context Graph switching.
- [ ] `ContentGraphController` coordinates the view but does not become the schema, compiler, persistence store, diagnostic engine, or AI service.
- [ ] Runtime-safe services own compilation, rule evaluation, validation, migration, and diff logic so non-editor Synesyn clients can reuse them.
- [ ] Hub/Artrhythmetic Store owns committed artifacts, versions, provenance, traces, and repairability. Generated indexes/caches remain disposable.
- [ ] `ui.context_graph` stores semantic graph state; user layout state is stored separately or clearly namespaced and excluded from semantic diffs.
- [ ] Every Godot↔Hub payload change updates client, server, normative contract, migration/compatibility reader, and tests in one delivery stage.
- [ ] Maintain v0 readers until all known `ui.context_graph` consumers—including SynAxes bridge import—accept v1.
- [ ] Never let downstream consumers scrape live SynTree internals; they consume committed artifacts or explicit bridge references.

### I.13 Stage-boundary verification and rollback

At every stage boundary:

- [ ] Run focused GDScript model/serialization tests using the Godot executable configured by `godotTools.editorPath.godot4`.
- [ ] Run Hub tests whenever Python, API behavior, artifact validation, or storage changes.
- [ ] Run `python synesyn/utilities/checks/check_line_limits.py --check-baseline`.
- [ ] Repeat Content Sources manual acceptance for List, Hierarchy, and Context Graph.
- [ ] Verify existing source files, stacks, and `ui.context_graph` v0 artifacts still load.
- [ ] Verify SynAxes can still consume published context graphs.
- [ ] Verify prompt-chain compilation and normal SynTree chat remain unchanged unless the stage intentionally changes their contract.
- [ ] Run ScenSyn smoke/multiturn harness only when a shared runtime or bridge change could affect ScenSyn.
- [ ] Check all visible controls resolve to a working action or clearly labelled unavailable state.

Delivery posture:

- Keep schema migration, UI, and behavior changes in discrete reviewable commits.
- Add compatibility readers before writers emit v1.
- Put the new Context Compiler behind an opt-in compatibility switch until preview/submission parity is proven.
- Make typed-edge migration non-destructive and reversible from the last committed artifact version.
- Feature-flag AI proposals, traces, and advanced diagnostics independently.
- If Hub is unavailable, preserve local draft editing but clearly disable canonical commit/version operations.

### I.14 Open decisions to resolve through the owning ADR/contracts

- [ ] Final controlled relationship vocabulary and which relations have display inverses.
- [ ] Whether canonical content-graph nodes represent source-level records, chunk-level records, or both through explicit node kinds.
- [ ] Exact local-draft versus Hub-committed boundary for graph edits.
- [ ] Token-estimation provider strategy and acceptable fallback accuracy.
- [ ] Whether context compilation remains local/runtime-safe, gains an optional Hub implementation, or both share conformance fixtures.
- [ ] Trace retention and privacy defaults for compiled prompt context.
- [ ] Practical graph-size performance targets.

## G) Documentation updates
- [x] (v1) Add a short “SynTree as a Synesyn runtime module” page:
  - [x] (v1) how apps call SynTree core
  - [x] (v1) how it relates to Metapunkt tool routing
  - [x] (v1) how it persists to the substrate (when enabled)

## J) Drop-in autoload boundary (ADR 0017 rules 6-8)

Done:

- [x] `syntree_plugin.gd` registers its own required autoloads (`PluginManager`,
      `ContentBus`) and removes only what it added, so the host no longer has to
      hand-edit `project.godot`. `NotificationManager` is deliberately excluded:
      it declares `class_name NotificationManager`, and Godot rejects an autoload
      whose name collides with a global script class. It is instantiated directly
      by SyntreePanel, so it never needed to be an autoload.
- [x] Deleted the orphaned `scripts/plugin.gd` (never loaded: `plugin.cfg` points
      at `syntree_plugin.gd`) and the dead `Engine.get_singleton("ContentBus")`
      path, which never resolves autoloads in Godot 4.
- [x] Replaced every bare autoload identifier under `addons/**` with use-time
      resolution via `syntree_autoloads.gd` (SynTree-owned) or
      `synesyn_autoload_access.gd` (host). Behaviour-preserving: each converted
      site already carried its own null guard.
- [x] Closed host-autoload leaks: `WorkspaceBootstrapper` in `syntree_panel.gd`;
      `Global` / `StoryState` / `PluginManager` in `harness/dev_harness_hooks.gd`;
      `VoiceService` / `WorkspaceBootstrapper` / `Global` in `syntree_voice`.
- [x] Enforcement: `utilities/checks/check_addon_autoloads.py` (pattern ratchet, reads
      autoload names from `project.godot`), `utilities/checks/addon_compile_sweep.gd`
      (ground truth), `.cursor/rules/addon-autoload-access.mdc` (edit-time rule).
- [x] Verified: 351 addon scripts compile with **no** autoloads live; ratchet
      passes across all 20 autoloads; host `project.godot` unchanged.

Follow-ups:

- [ ] Smoke-test SynTree in the editor and in play mode to confirm no runtime
      regression from use-time resolution. Signal wiring in
      `syntree_panel_dev_agent_utils.gd` is the area most worth watching: if the
      bus is absent at connect time the wiring silently never happens. That is
      pre-existing behaviour, not new, but worth confirming.
- [ ] Wire `check_addon_autoloads.py` into whatever runs `check_line_limits.py`
      so the ratchet actually gates changes.
- [ ] Line-limit baseline is stale in both directions and currently FAILS. Review
      the 7 pre-existing regressions before regenerating, largest first:
      `game_session.gd` 1185->1205 (over the hard limit),
      `synaxes_runtime_controller.gd` 1077->1175,
      `artrhythmetic_store/service.py` 900->989, `services_panel.gd`,
      `metapunkt_main.gd`, `synpunkt_dock.gd`, `story_stage.gd`. This work added
      +12 to `syntree_panel.gd` (1163) and +6 to
      `syntree_panel_dev_agent_utils.gd` (970), both under the hard limit. Four
      files also shrank, so regenerating now would lock in the growth as well.


