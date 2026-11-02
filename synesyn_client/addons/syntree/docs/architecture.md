# SynTree Architecture Documentation

## Component Responsibilities

### Core Components
- **ContentStateResource**: Panel content, source compatibility state, relationships, and persistence mutations
- **ViewStateResource**: Panel-local navigation, focus, and multi-selection state
- **ContentViewManager**: List, Hierarchy, and Context Graph surface coordination
- **SyntreePanel**: Composition root that injects resources and services
- **ContentBus**: Compatibility and cross-boundary events; not view state ownership

## Communication Patterns

✅ **Recommended Patterns**
- SyntreePanel -> controllers/views: injected resource and service references
- Views -> resources: explicit intent methods
- Resources -> views: state-change signals
- Cross-boundary consumers -> ContentBus: compatibility/event signals only

❌ **Prohibited Patterns**
- Direct node searches across components (e.g., find_node, get_node)

## Reference Management

✅ **Recommended Practices**
- Pass references through constructor/setup methods
- Store references in properly named variables

❌ **Prohibited Practices**
- Search for nodes outside component boundaries

## Development Guidelines

### 1. AVOID REGRESSION
- Ensure changes don't break existing functionality
- Maintain view switching/button visibility behavior
- Preserve existing signal connections
- Test all view modes after making changes

### 2. REDUCE REDUNDANCY
- Leverage existing infrastructure
- Reuse existing methods rather than creating duplicates
- Check whether `ContentStateResource`, `ViewStateResource`, or an injected service already owns the operation
- Place new code in appropriate component based on responsibility

### 3. MAINTAIN SIMPLICITY
- Keep code clean and maintainable
- Avoid overly complex solutions when simpler ones suffice
- Don't add unnecessary abstraction layers
- Keep method and class sizes reasonable

### 4. RESPECT COMPONENT BOUNDARIES
- UI logic belongs in view components
- Source data and persisted graph mutations belong in `ContentStateResource`
- Navigation and selection belong in `ViewStateResource`
- Runtime-safe graph mechanics belong in `scripts/graph_workspace/`
- Container/coordination and dependency injection belong in `SyntreePanel`

## Extension Patterns
- Add new view types by extending ContentViewManager with new view methods
- Add new content source types by extending ContentModel parsers
- Add new graph node types by creating new scene inheriting from ContentSourceGraphNode
- Add resource signals for panel-local state; reserve ContentBus signals for genuine cross-boundary compatibility events

## Error Handling
- Use NotificationManager (utils/notification_manager.gd) for user-facing notifications
- Use dedicated error handlers in utils/error_handling/ for structured error management
- Component-level errors should use appropriate error classes from error_handling/
- Log technical errors using push_error() for debugging
- Cross-component errors should be communicated via ContentBus to NotificationManager
- For UI components, emit show_error_requested signal to bubble errors up to notification display

## Performance Considerations
- Defer heavy operations when UI responsiveness is important
- Batch updates to prevent multiple UI refreshes
- Cache frequently accessed data
- Use signals for asynchronous operations rather than polling

## Ollama Provider Runtime

`AIModelManager` owns model identity and provider state; `APIService` owns
inference request lifecycle. Ollama-specific HTTP control operations are isolated
in `OllamaRuntimeService`, while incremental NDJSON chat transport is isolated in
`OllamaStreamingClient`.

- Startup discovery reads `/api/tags`, then `/api/show` for installed-model
  context limits and capabilities. The loader's static list is an offline
  fallback, not the authoritative installed-model list.
- The Ollama HTTP/HTTPS origin is stored at
  `apps.syntree.ollama_base_url` in canonical runtime config. Discovery,
  control, non-streaming, and streaming transports use the same origin.
- Discovered context limits inform conservative source trimming without
  increasing the established 20,000-character per-source ceiling. Workshop
  Catalyst retains its smaller explicit structured-output budget.
- Ordinary SynTree chat streams deltas and still resolves to the standard final
  response dictionary. Structured callers such as Workshop Catalyst continue to
  use non-streaming JSON completion.
- Only one Ollama inference request may run at a time. Callers receive
  `ollama_busy` instead of competing for local RAM/VRAM. Active requests support
  request-ID cancellation.
- Ollama response counters and nanosecond timings are normalized into token
  counts, tokens/second, total/load durations, model ID, provider ID, and request
  ID. The model settings strip displays the latest local status or metrics.
- `/api/ps` reports loaded models. Changing away from an Ollama model requests
  unloading of the previous model; regular requests retain a five-minute
  `keep_alive`.

## Documentation Preservation
- Interface headers (COMPONENT, RESPONSIBILITY, etc.) must NOT be removed or modified without explicitly changing the component's architecture
- ARCHITECTURE-BOUNDARY comments serve as critical guardrails and should be preserved across code changes
- When making changes to a file, always retain these architectural markers unless specifically directed to modify them
- If architectural boundaries must change, update both the code AND the corresponding documentation

## Context Graph System

The Context Graph system visualizes and edits content nodes and their relationships. It is the SynTree product adapter over the runtime-safe shared Graph Workspace; SynTree-specific context compilation, source/stack state, and Prompt Chain integration remain outside the shared graph mechanics. It consists of:

1. ContentGraphController: Manages the graph view and node connections
2. ContentSourceGraphNode: Visual representation of content nodes
3. GraphEdit: Godot's built-in graph editing control
4. GraphPersistenceCommands: Routes legacy semantic connection mutations to
   ContentStateResource without coupling the view controller to persistence
   details
5. GraphStackComposer: Builds multi-source stack canvases using injected state,
   builder, renderer, and controller-owned node factory
6. GraphSelectionCoordinator: Routes graph selection to the injected content and
   view-state owners while preserving stack display roots
7. ContextGraphAdapter: Maps schema-v1 artifacts and current SynTree sources,
   stacks, chunks, compatibility flags, and context-set metadata onto the shared
   Graph Workspace envelope

The shared `scripts/graph_workspace/` package owns domain-neutral document
validation, semantic diff/layout separation, and a Hub artifact facade for
loading and versioned commits. It has no dependency on the SynTree addon or
Workshop Catalyst.

`ContentStateResource` owns semantic graph mutations shared by Context Graph and
Hierarchy, including ordinary edges, stack edges, and node deletion/unlinking.
Legacy embedded node positions remain readable for compatibility, but new canvas
movement does not write them. `GraphWorkspaceLayoutStore` persists explicitly
named, user-local layouts under `user://` with node positions, zoom, and viewport
state. Layout save/load/delete is therefore independent of `ui.context_graph`
commits and cannot create a semantic artifact version.

Rich relationship records live in `content.context_graph_edges`; stack-owned
records live in `meta.ai_context.stack_context_graph_edges`. The
`ContextGraphRelationshipRegistry` owns the controlled vocabulary,
canonical/inverse behavior, structural cycle checks, and initial visual colors.
Legacy arrays and bare stack edges remain compatibility projections. Hierarchy
and stack ordering read only structural `contains` relationships, while Context
Graph renders every typed relation. The `.tscn`-authored Relationship Inspector
is the commit boundary for creating, editing, reversing, and disconnecting
relationships. It also provides keyboard-selectable endpoints. Relationship
categories use dedicated, theme-safe port colors, with the category legend kept
beside the inspector.

`ContextCompiler` is the pure, deterministic context-selection service. It
returns ordered inclusions, traversal reasons and paths, explained omissions,
compiled text, heuristic token estimates, budget status, model/estimator
identity, and graph/context-set references. `ConversationContextCompilerBridge`
is the single adapter used by chat submission and the Context Preview panel. The
panel exposes ordered inclusions, explained omissions, estimated token use, and
the exact compiled text. When the user enables compiled context, that preview
result is frozen in `ConversationManager` metadata and consumed unchanged by the
next chat submission; refreshing or changing active sources replaces the frozen
result. The compiler path remains opt-in while legacy Active-source injection
remains the default.

`ContextActivationPolicy` applies the five transparent node modes and the
normative review-state/pin/mode precedence without model calls. Conditions use
only explicit thread, app, prompt-chain, tag, and slot inputs. `ContextCompiler`
uses this policy to include `always` nodes and explain policy omissions.
`ContextSetStore` owns normalization and local persistence of named sets through
the public `ContentStateResource` update boundary. `ContextGraphAdapter`
projects those local sets into v2 artifacts with owner-qualified ids while the
legacy Active checkbox remains the generated `active-sources` entry set. The
`.tscn`-authored Context Sets sidebar tab edits local drafts and node activation;
its controller is deliberately separate from `ContentGraphController`. Draft
preview passes an explicit context-set override through
`ConversationContextCompilerBridge` and can freeze the exact result used by the
next chat submission. Hub commit remains distinct from local save: the
controller rejects a changed or unpreviewed draft, builds the v2 graph through
`ContextGraphAdapter`, commits it through `GraphWorkspaceArtifactClient`, and
stores the root/latest artifact lineage in the owning source. Version history
is queried by artifact type and filtered by `owner_source_id`; a committed set
cannot be locally deleted or silently overwritten by a new draft.

Prompt Chain context binding remains owned by `ui.prompt_chain` and the linear
Prompt Chain subsystem. `PromptChainStore` supplies stable block ids and
normalizes additive chain-level `context_binding` and block-level
`context_override` fields. `PromptChainContextResolver` loads the explicitly
bound graph version through `GraphWorkspaceArtifactClient`, validates owner and
context-set scope, and invokes the existing deterministic `ContextCompiler`.
It does not route prompt blocks through `ContentGraphController` or infer a
binding from the inverse `prompt_chain_ids` field on context sets.
The `.tscn`-authored Prompt Chain binding panel edits binding metadata through
the existing proposal/commit flow and previews through that resolver. Hub
payload construction is isolated in `PromptChainArtifactPayloadBuilder`, which
includes slots, stable blocks, binding metadata, and graph-version provenance.
During chat, `BoundPromptChainContextBuilder` appends the resolved compiled
context once after the linear chain prefix and suppresses the ordinary
Active-source path, preventing duplicate context injection. Resolution failure
is fail-closed: the chain prefix remains usable and a warning is retained on
`ConversationManager`.
Successful binding preview broadcasts only the compiled node ids to the existing
`graph_controllers` scene-tree group. `ContentGraphController` maps artifact
ids back to the current ordinary/stack canvas, and graph nodes render a
transient gold border without changing selection, persistence, Active state, or
Metaprompt state. Binding changes and failed previews clear the overlay.

Each compiler-backed chat also creates a privacy-safe
`json.context_execution_trace` v1 record through
`ContextExecutionTraceCoordinator`. New thread messages receive stable ids;
the trace snapshots graph/context-set/compiler decisions before the request and
is finalized with response status and assistant-message identity. Canonical
trace payloads contain a SHA-256 hash rather than raw compiled text and are
persisted to Hub on a deferred, best-effort path. Hub failure cannot fail the
chat: the latest trace remains in `ConversationManager` metadata with a
persistence warning. The `.tscn`-authored Trace sidebar tab explains included
and omitted nodes, traversal paths, policy/provenance, and stable message
references. It may show the exact compiled text while still in memory; that
text is not added to the persisted trace. Selecting the latest trace overlays
included nodes in cyan and omitted candidates in gray without mutating graph
state. No model-attention or “unused” claim is inferred.

`ContextGraphProvenance` normalizes node and edge authorship, origin,
source-location/artifact references, derivation references, review state, and
evidence state without inferring missing facts. `ContextProvenanceStore`
persists the same shape on source metadata or content nodes, and
`ContextGraphAdapter` guarantees that every v2 graph record exports normalized
provenance plus compatibility `provenance_refs`. Relationship editing preserves
that record and exposes authorship, review, and evidence separately from
confidence; unknown values remain explicit. The static Provenance sidebar tab
uses `ContextProvenanceStore` to inspect and edit source/content-node records,
offers explicit source-location navigation, and lists incident `supports` and
`contradicts` paths without deciding between them. Graph-node badges display
authorship and evidence as text as well as an authorship-specific accent, so
the distinction does not depend on color alone.

AI-assisted graph changes use an isolated proposal layer.
`ContextGraphProposalGenerator` can call the configured model and parse only
constrained suggestion records, but it has no graph mutation or Hub commit
dependency. `ContextGraphProposalStore` persists reviewable suggestions and
review decisions outside canonical nodes/edges, suppressing identical
rejected/deferred proposals unless evidence changes. `ContextGraphProposalEngine`
normalizes proposals and produces a copied, validated semantic diff; it never
mutates the input document. The `.tscn`-authored Proposals tab supports
multi-select accept/edit/reject/defer, records review events best-effort, and
shows semantic, inclusion, and token-estimate impact. A separate human commit
action requires the accepted proposal set to match the last preview, then
materializes committed records as a new `ui.context_graph` Hub version and
advances lineage. Model-facing code cannot invoke this commit boundary.

`ContextGraphDiagnostics` performs model-free health checks for graph
integrity, structural cycles, orphans, duplicates, instruction conflicts,
provenance/review gaps, unpinned source artifacts, and token overflow. Every
diagnostic has severity, stable affected ids, and a non-mutating repair preview.
The Health sidebar tab can focus affected nodes with a transient diagnostic
overlay. It also loads earlier graph artifacts through
`GraphWorkspaceArtifactClient`, compares complete semantic records by stable id,
and compares compiled inclusion order, additions/removals, token estimates, and
text hashes. Comparison explicitly records that it makes no causation claim.
Fork creates a new artifact with the compared version as `previous_version_id`;
it never overwrites or silently activates the earlier version.

`ContextGraphFocusFilter` is a pure visibility evaluator for id/label search,
tags, relationship types, activation/authorship/review state, confidence, and
inactive/rejected/unrelated records. It also computes configurable-depth
neighborhood focus and structural descendant collapse. The Focus sidebar tab
passes only the resulting visible ids to `ContentGraphController`; canvas
visibility changes are transient and never enter semantic artifacts. Reset
restores every node. The GraphEdit minimap remains available for overview, and
Fit relevant context frames only currently visible nodes. Arrow keys choose the
nearest visible node in the requested spatial direction. Node state, provenance,
relationship category, and relationship meaning all have text labels in
addition to visual accents.

Compilation, diagnostics, and focus filtering are scheduled through
`LatestDeferredJob`: work starts outside the initiating input callback, and a
new request cancels any stale queued result. This is cooperative cancellation,
not engine-object work on a background thread; Godot scene/resource access stays
on the main thread. Pure large-graph fixtures define deterministic 1,000-node
targets. `GraphSourceRenderCoordinator` routes ordinary source canvases above
144 nodes through `GraphRenderBatcher`, which creates at most 24 nodes per frame,
connects edges only after node construction, and cancels a stale render when a
new source is requested. A rendered 240-node fixture guards frame batching and
opening time without moving scene-tree mutation to unsafe worker threads.

### Connection Workflow

The graph connection system follows a specific workflow to ensure proper visualization:

1. Node Creation:
   - Instantiate ContentSourceGraphNode for each content node
   - Set basic properties (node_id, node_data, content, path)
   - Add nodes to the scene tree

2. UI Update:
   - Call update_ui_from_data() on each node after adding to tree
   - This updates all UI elements and initializes connection slots
   - Slots are configured based on relationship data (parents/children)

3. Connection Creation:
   - Create connections between nodes using GraphEdit.connect_node()
   - Use slot index 0 for all connections
   - Connections are made from parent's output slot to child's input slot
   - Force graph update after all connections are created

### Important Implementation Details
- Nodes must be added to the scene tree before UI update
- Slots must be initialized based on relationship data
- All connections use slot index 0
- The graph must be updated after all connections are created
- Relationship data structure: {"parents": [], "children": [], "dependencies": []}

## Content Source Selection Flow

Selection is owned by the panel-scoped `ViewStateResource`.

1. `ContentSourceItem.select_toggled` expresses user intent.
2. List and hierarchy surfaces route that intent to `ViewStateResource.select_source()`.
3. `ViewStateResource.source_selected` and `view_state_changed` notify all bound views.
4. Views render `ViewStateResource.is_source_selected()`; they do not discover or mutate `ContentBus`.

This keeps multi-selection and navigation synchronized without making a global
autoload the owner of panel-local UI state.

## View State Management

The view state management follows a strict pattern:

1. View State Source of Truth:
   - `ViewStateResource` owns the current mode, focused source, and selected source set.
   - Views change navigation through `ViewStateResource.change_view()`.
   - `ContentViewManager` observes `view_state_changed` and coordinates the List, Hierarchy, and Context Graph surfaces.

2. View Button Visibility Rules:
   - List View:
     * List button: Hidden (current view)
     * Hierarchy button: Visible and enabled only when source selected
     * Graph button: Hidden
   
   - Hierarchy View:
     * List button: Visible
     * Hierarchy button: Hidden (current view)
     * Graph button: Visible and enabled
   
   - Context Graph:
     * List button: Visible
     * Hierarchy button: Visible and enabled
     * Graph button: Hidden (current view)

3. View UI Updates:
   - ContentViewManager._update_view_ui_for_mode handles all UI updates
   - View type label shows current view and source context
   - Button states are updated through _update_button_states
   - View visibility is managed centrally

Static view controls and containers live in `.tscn` scenes. Code creates only
runtime-dependent graph nodes and other items whose count is not known at design time.

## Metaprompt State Management

The metaprompt state follows a centralized state management pattern with source-specific persistence:

1. State Source of Truth:
   - `ContentStateResource` owns source content, Active/Metaprompt compatibility state, relationships, and persistence.
   - Views express mutations through typed methods such as `set_metaprompt_state()`.
   - Resource signals notify bound surfaces after successful mutations.

2. View Updates:
   - List View: Checkbox in ContentSourceItem
   - Hierarchy View: Visual state in hierarchy items
   - Context Graph: Node appearance in ContentSourceGraphNode

3. State Flow:
   [Any View] -> ContentStateResource.set_metaprompt_state()
              -> source resource mutation and save
              -> ContentStateResource signal
              -> bound views update

4. Source-Specific Persistence:
   - Each content source saves its complete state
   - Changes are saved with the source's other data
   - State is restored when source is loaded

`ContentBus` remains a compatibility/event boundary for consumers that still require
autoload signals; views do not use it as a service locator or state authority.