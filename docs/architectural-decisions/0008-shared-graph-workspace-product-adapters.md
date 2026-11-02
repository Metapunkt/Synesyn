# 0008 — Shared Graph Workspace with product-owned adapters

- **Status:** Accepted
- **Date:** 2026-07-10
- **Area:** shared graph infrastructure / SynTree / ScenSyn

## Context

SynTree's existing Graph View visualizes and edits relationships among content
nodes and stack members. Its planned evolution into Context Graph adds typed
relationships, proposal states, provenance, layout management, inspection,
version comparison, and Hub-backed graph artifacts.

Workshop Catalyst's planned Live Thinking Map needs many of the same mechanics,
but its meaning is different. It organizes live workshop claims, causes, effects,
opportunities, decisions, risks, owners, and next steps. It also receives
incremental transcript and synthesis events and remains under facilitator review.

Reimplementing graph mechanics in both products would duplicate complex UI,
validation, migration, provenance, and persistence behavior. Reusing SynTree's
current controller wholesale would instead couple Workshop Catalyst to content
sources, Active/Metaprompt state, context compilation, Prompt Chains, and
editor-panel assumptions.

## Options considered

1. **Build the two graph surfaces independently.** Each product remains
   autonomous, but typed edges, proposal review, provenance, canvas interaction,
   layout, diffing, migration, and artifact transport are duplicated and likely
   drift.
2. **Use SynTree Context Graph directly inside Workshop Catalyst.** This maximizes
   immediate code reuse but imports SynTree-specific state and semantics into a
   live facilitation runtime and encourages both products to share the wrong
   artifact contract.
3. **Extract a runtime-safe Graph Workspace and add product-owned adapters.**
   Domain-neutral graph mechanics are shared. SynTree and Workshop Catalyst map
   their own state and meaning onto those primitives and retain separate
   controllers and artifacts.
4. **Create one universal graph schema and product.** This appears consistent but
   forces context engineering and live workshop facilitation into abstractions
   broad enough to obscure both user journeys.

## Decision

Adopt option 3.

Create a runtime-safe shared Graph Workspace responsible only for:

- stable graph document, node, and typed-edge primitives;
- proposal/review states and provenance references;
- semantic validation, migration, and diff support;
- layout state separated from semantic graph state;
- reusable GraphEdit canvas interaction, relationship rendering, selection, and
  inspector contracts;
- Hub artifact transport/version references;
- batched incremental updates and non-blocking persistence hooks.

SynTree owns a `ContextGraphAdapter` for content sources, chunks, stacks,
Active/Metaprompt compatibility, context sets, compilation, Prompt Chain
bindings, and retrieval overlays.

Workshop Catalyst owns a `ThinkingMapAdapter` for
Causes/Effects/Opportunities, participant statements, AI inferences, live update
events, facilitator proposal review, Session Record integration, and ClosureBus
commit behavior.

The products use separate versioned artifacts:

- `ui.context_graph` for user-curated AI context selection and structure;
- `ui.workshop_thinking_map` for a workshop's reviewed live thinking map.

Structural compatibility does not authorize silent conversion or cross-surface
context injection. Any conversion or bridge must be explicit, user-visible,
versioned, and traceable.

Context Graph remains a permanent peer to List and Hierarchy. Prompt Chains
retain their separate linear editor and may reference Context Graph artifacts or
named context sets without becoming graph nodes.

## Consequences

- Positive: complex graph mechanics and Human Agency behavior are implemented and
  tested once.
- Positive: Workshop Catalyst can use mature graph interaction without importing
  SynTree editor or content-management dependencies.
- Positive: each product can evolve its domain vocabulary and artifact contract
  independently.
- Positive: conformance fixtures can verify shared behavior across both adapters.
- Trade-off: an explicit adapter boundary and shared-module API must be designed
  and maintained.
- Trade-off: some visually similar behavior remains product-specific rather than
  being forced into the shared layer.
- Risk: premature abstraction could encode SynTree assumptions as generic
  primitives. Shared extraction should begin with demonstrated common mechanics
  and reject domain fields.
- Follow-up: update the normative data model before either product emits new
  graph artifact versions.
- Follow-up: update the Workshop Catalyst PRD before implementing the Live
  Thinking Map user journey.
- Follow-up (2026-08-02): the shared canvas (`graph_workspace_canvas.gd`)
  gained two more domain-neutral mechanics under this same boundary — a
  `connection_requested(from_id, to_id)` signal (the canvas reports a drag
  attempt but never decides what it means or draws the edge itself) and
  generic `annotations.group_key`/`group_label` clustering into `GraphFrame`s
  (the canvas has no opinion on what a group_key *means*). Workshop
  Catalyst's `ThinkingMapAdapter` is the first adapter to use both: it
  resolves manual connections into `propose_edge` commands with its own
  relation vocabulary, and stamps `group_key` as `"stage:<stage name>"`.
  A **symbolic rules layer**
  (`workshop_thinking_map_symbolic_rules.gd`) was also added, deliberately
  placed in ScenSyn rather than the shared Graph Workspace: contradiction
  flags, derived causal chains, and evidence-gap warnings depend entirely on
  Workshop Catalyst's relation/evidence vocabulary (`causes`, `supports`,
  `contradicts`, `evidence_status`), which the shared layer intentionally
  does not know about. If SynTree's Context Graph later wants comparable
  reasoning, it gets its own rules module over its own vocabulary rather than
  the shared layer growing an opinion about either product's ontology.
