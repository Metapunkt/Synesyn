## SynTree content sources — view orchestration & coupling policy (post‑refactor)

### Goal
Keep the Content Sources UI **stable under editor reparenting/refactors** by enforcing a strict coupling rule:

- **UI views do not “discover” `ContentBus`** (no `Engine.has_singleton("ContentBus")`, no `/root/ContentBus` lookups).
- UI views operate on **injected resources**:
  - `ContentStateResource` (system-of-record for sources + node mappings)
  - `ViewStateResource` (system-of-record for UI mode + selection)
- A single coordinator (`ContentViewManager`) translates `ViewStateResource` → TabContainer + view updates.

### Files and responsibilities (current)
- **`synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_view_manager.gd`**
  - Owns the **TabContainer** mode switching.
  - Listens to **`ViewStateResource.view_state_changed`** and updates:
    - tab index
    - tab enable/disable (Hierarchy/Graph require a selected source)
    - triggers `ContentHierarchyView.display_hierarchy(...)` when entering Hierarchy
    - triggers `ContentGraphController.initialize_with_source(...)` when entering Graph
  - Receives `content_state` + `view_state` via `setup(ui_references)`.

- **`synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_source_list/content_list_view.gd`**
  - Renders the “Sources list”.
  - Receives `ContentStateResource` + `ViewStateResource` via `setup_list(...)`.
  - Creates `ContentSourceItem` rows and wires their **intent signals** directly to resources:
    - `select_toggled → ViewStateResource.select_source`
    - `view_requested → ViewStateResource.change_view`
    - `metaprompt_toggled → ContentStateResource.set_metaprompt_state`
    - `active_source_toggled → ContentStateResource.set_source_active_state`

- **`synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_source_list/content_hierarchy_view.gd`**
  - Renders the “Hierarchy” (nodes within a selected source).
  - Receives `ContentStateResource` + `ViewStateResource` via `setup_hierarchy(...)`.
  - Reacts to `ViewStateResource.view_state_changed` to display the currently selected source’s hierarchy.
  - Emits graph navigation by calling `ViewStateResource.change_view(ViewMode.GRAPH, node_or_source_id)`.

- **`synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_graph/content_graph_controller.gd`**
  - Manages Graph view node lifecycle and graph interactions.
  - Receives `ContentStateResource` + optional `ViewStateResource` via `initialize(...)`.
  - Uses `ViewStateResource.select_source(...)` to propagate selection from graph interaction.

- **`synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_source_list/content_source_item.gd`**
  - Leaf UI row for list/hierarchy.
  - **No `ContentBus` usage**.
  - Emits intent signals only (selection, view request, toggles, delete).

### Ideal coupling map (enforced direction)

```text
SyntreePanel
  ├─ owns/inits resources: ContentStateResource + ViewStateResource
  ├─ injects resources into:
  │    ├─ ContentViewManager (coordinator)
  │    ├─ ContentListView (list surface)
  │    ├─ ContentHierarchyView (hierarchy surface)
  │    └─ ContentGraphController (graph controller)
  │
  ▼
ContentViewManager
  ├─ listens: ViewStateResource.view_state_changed / source_selected
  ├─ drives: TabContainer current tab + disabled state
  ├─ triggers:
  │    ├─ ContentHierarchyView.display_hierarchy(ContentStateResource.get_source_data(...))
  │    └─ ContentGraphController.initialize_with_source(source_id)
  ▼
Views (List/Hierarchy)
  ├─ render from ContentStateResource
  └─ write intents to resources (no ContentBus):
       - selection → ViewStateResource.select_source(...)
       - view mode → ViewStateResource.change_view(...)
       - toggles   → ContentStateResource.set_*_state(...)
```

### Enforcement notes
- Any code that searches for `ContentBus` inside a view is considered **policy-violating**.
- If a future feature needs cross-component coordination, do it in **`ContentViewManager`** (or a dedicated coordinator), not from leaf views.
- Avoid “helper sprawl” during refactors:
  - Prefer **domain helpers** (cohesive responsibility) over one-off micro-scripts.
  - Keep helpers **leaf-like** (no deep helper→helper→helper chains).
  - Keep `resources/internal/*` **pure** (no scene tree, no signals, no `ContentBus`), and keep UI internals **UI-only** (no content state writes).

### Script header rule (anti-bloat)
Every script in `synesyn/synesyn_dec2025/addons/syntree/scripts/` must start with a single-line header:

- `## Purpose: <short intent>`

This is intentionally brief (one line) and acts as a guardrail against code creep: if new logic doesn’t fit the purpose, it must be extracted into a new, purpose-labeled module.

---

### View Sync Contract (List ↔ Hierarchy ↔ Graph) — **stability/maintainability rules**

This contract exists to prevent regressions where the three UI surfaces drift out of sync, or where UI updates accidentally mutate persisted state.

#### 1) Systems of record (single source of truth)
- **Toggle state** (`is_active`, `metaprompt`) is stored in **content source JSON** under `meta.ai_context`.
- **In-memory authority** is `ContentStateResource` (reads/writes that JSON through `ContentSourceResource`).
- **View/selection authority** is `ViewStateResource` (mode + current source + selection set).

#### 2) Allowed write paths (no UI writes to disk/state directly)
- **UI → state**:
  - List/Hierarchy/Graph UI may call:
    - `ContentStateResource.set_source_active_state(source_id, bool)`
    - `ContentStateResource.set_metaprompt_state(source_id, bool)`
  - UI must NOT directly edit `content_source_resource.sources` dictionaries, and must NOT write to disk itself.
- **State → UI**:
  - `ContentStateResource` must emit:
    - `active_state_changed(source_id, is_active)`
    - `metaprompt_state_changed(source_id, is_metaprompt)`
  - Views update UI from these signals OR by rebuilding from `ContentStateResource` on view entry.

#### 3) UI feedback-loop protection (programmatic updates)
- When code sets checkbox/button state programmatically, it MUST prevent emitting the “intent” signals.
- Preferred mechanism: per-control flags (e.g. `_is_updating_active_state`, `_is_updating_metaprompt`) checked inside toggle handlers.
- Avoid scattering `set_block_signals` unless necessary for a specific control.

#### 4) Graph node lifecycle timing rule (critical)
- `ContentSourceGraphNode.set_node_data()` **may be called before the node is in the scene tree**.
- Therefore the GraphNode must:
  - store pending `node_data` when not in-tree
  - apply it on `_ready()` / next frame and then call `update_ui_from_data()`

#### 4.1) Chat code-block lifecycle timing rule (critical)
- `CodeBlock.set_code(...)` **may be called before the CodeBlock is in the scene tree** (common when instantiating from `.tscn` and populating immediately).
- Therefore `CodeBlock` must:
  - buffer pending code when not ready
  - apply it on `_ready()` (or defer population by one frame from the caller)

#### 5) ID semantics (avoid cross-source collisions)
- **Node IDs are only unique within a source**.
- When referencing nodes across views, use composed IDs: `source_id + "__" + node_id`.
- Any mapping logic must accept composed IDs and resolve them to:
  - `source_id` (owning source)
  - `node_id` (raw node id inside that source)

#### 6) Stack mode rule (two different edge layers)
- **Member source internal hierarchy edges** live inside each member source’s node `relationships`.
- **Stack orchestration edges** live on the stack root (`meta.ai_context.stack_edges`).
- Don’t write stack orchestration edges into member sources.

#### 7) “Linked child source” nodes (created via Add Child…)
- These are nodes inside a parent source that reference another source by `meta.linked_source_id`.
- Rendering/toggles should use the linked source as the “effective source” for:
  - name/path display
  - active/metaprompt toggles
  while selection still targets the underlying parent node row for hierarchy actions.

#### 8) Regression checklist (manual, 30 seconds)
- Toggle Active/Metaprompt in Graph → List updates → Hierarchy updates → switch views back: values persist.
- Add Child… → new linked child shows correct name/path/id in all three views.
- In stack graphs: toggling a node affects only nodes of the same effective source (not all members).

### Stacks (SynTree “context orchestration assets”) — **normative semantics**
Stacks are **not** just another content source; they are **an orchestration layer** over reusable member sources.

#### A) Persistence & “system of record” rule
- **Stack Graph edits MUST persist to the stack root only** (the stack source’s `meta.ai_context`), never into member source files, unless the user explicitly enters an “Edit Member Source” mode.
- This preserves member source reuse and prevents surprising cross-stack mutations.

#### B) Stack schema (current)
`meta.ai_context.is_stack: true` indicates a stack source.  
Member listing is stored in `meta.ai_context.stack_sources` and may be:
- **Array of objects** (current): `{ "id": "<source_id>", "name": "...", "path": "res://..." | "https://..." }`
- **Array of strings** (legacy/template): `["source_id_1", "source_id_2"]`

#### C) Wiring semantics in Graph view
In **stack Graph view**, a wire (edge) means **context precedence / orchestration**.

- **Edge A → B**: “Within this stack, A is upstream of B.”  
  When compiling context for an app/agent, A’s content (or its derived summary/closure) is made available **before** B (and/or with higher priority).
- Stack wiring is **not** an edit to the member source structure; it is a stack-only preference.

#### D) Unwired nodes policy (v0)
Unwired nodes (or unwired member sources) are still part of the stack:

- **Unwired ≠ excluded**. Unwired members SHOULD be included by default.
- Wiring provides a **strong signal** (precedence/flow), not the only signal of relevance.

**Deterministic ordering rule** (recommended):
- Compile wired subgraph by **topological sort**, stable tie-break (e.g. by layout position, then id).
- Append unwired members/nodes in a stable order (layout position → id).

#### E) Stack-level toggle (v1 refinement; supported by doc now)
Add a stack-level option in `meta.ai_context`:
- `include_unwired_nodes` (bool, default **true**)
  - `true`: include unwired members/nodes as unordered context blocks (v0 default behavior)
  - `false`: treat the stack as a strict pipeline (only nodes reachable via wiring from a chosen target are included)

#### F) UI indicators (required)
To make user intent visible and reduce confusion:
- **Stack badge**: visually indicate “this source is a stack” in:
  - List view rows
  - Hierarchy header
  - Graph view header
- **Unwired indicator**: show when a stack contains unwired content, e.g.:
  - “Unwired: N” in the stack header/status strip
  - Optional action (later): “Auto-wire by layout (left→right)” / “Make linear chain”




