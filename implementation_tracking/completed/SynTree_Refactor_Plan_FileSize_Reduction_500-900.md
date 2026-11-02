### SynTree Refactor Plan — File Size Reduction (Target Range: 500–900 LOC)

**Purpose**: reduce maintenance risk and eliminate “endless churn” by executing a bounded, sequenced refactor program that reduces file sizes *without* breaking the 3-view sync contract (List ↔ Hierarchy ↔ Graph), persistence, stack behavior, or linked-child semantics.

This plan is intentionally **checklist-driven** and **scope-locked**. We only refactor what is on the target list, and we only do “safe bloat removal” (dead code, unused shims, debug spam) outside those targets.

---

### 0) Guardrails (anti-churn rules) — MUST be followed

- [ ] **Single thread of change**: only one target file/module “in progress” at a time.
- [ ] **No opportunistic edits**: if it’s not required for the current checklist item, defer it.
- [ ] **Purpose header required**:
  - [ ] Every script must begin with `## Purpose: ...` (one line, short intent).
  - [ ] If code doesn’t fit the stated purpose, extract into a new purpose-labeled module (don’t expand the original).
- [ ] **Anti–over-atomization (avoid helper sprawl)**:
  - [ ] **Extract by domain, not by function**: new `internal/` scripts must represent a cohesive domain (stack ops, edge ops, schema ops, sync ops, etc.), not a single one-off helper.
  - [ ] **Prefer extending an existing domain helper** over creating a new file for a tiny addition.
  - [ ] **Keep helper public API small**: target ~3–7 public functions per helper; if it grows materially beyond that, re-scope or split by sub-domain.
  - [ ] **No deep helper chains**: helpers should not form long call stacks (A→B→C). Prefer a thin orchestrator calling a small set of leaf helpers.
  - [ ] **No cross-layer leakage**: `resources/internal/*` must not touch scene tree, signals, or `ContentBus`. `ui/*/internal/*` must not read/write content state directly.
- [ ] **Single source of truth**:
  - [ ] Toggle state writes go through `ContentStateResource` setters.
  - [ ] `ContentStateResource` emits state-change signals; UI listens and updates via guarded methods.
- [ ] **No new legacy surfaces**:
  - [ ] If compatibility shims are required, they must be explicitly listed with a removal task in this plan.
- [ ] **Debug output discipline**:
  - [ ] No noisy `print()` in runtime paths; use `DEBUG` + `_dbg()` gates.
- [ ] **Keep changes reversible**:
  - [ ] Prefer extraction + thin wrapper over rewrite.
  - [ ] Avoid schema changes unless strictly necessary; if required, add a migration step.

---

### 1) Target files (current >500 LOC inventory)

Target range is **500–900 LOC** where feasible; if a file remains >900, the plan must document why and what would be required to split further.

- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/syntree_panel.gd` (~900)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/resources/content_state_resource.gd` (~766)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/ui/panel/content_sources_panel_controller.gd` (~889)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/services/chat/conversation_manager.gd` (~739)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/autoload/content_bus.gd` (~804)
### 1.1) Recent reductions (notes)

- [x] `syntree_panel.gd` reduced to **~900 LOC** by extracting cohesive *internal* helpers (not new micro-controllers):
  - [x] `ui/panel/internal/syntree_panel_wiring.gd` (UI + manager signal wiring, initial UI state)
  - [x] `ui/panel/internal/syntree_panel_bootstrap.gd` (setup/bootstrap + resource injection + view-manager instantiation)
  - [x] `ui/panel/internal/syntree_panel_content_sources_glue.gd` (remaining content-sources glue that stayed in the panel)

- [x] `content_bus.gd` reduced to **~804 LOC** by extracting remote URL loading:
  - [x] `autoload/internal/content_bus_url_loader.gd` (URL rewrite + HTTPRequest + source upsert)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_source_list/content_hierarchy_view.gd` (~899)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/resources/content_source_resource.gd` (~633)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_graph/content_graph_controller.gd` (~759)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/ui/prompt_chain/prompt_chain_panel.gd` (~619)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_view_manager.gd` (~581)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_graph/content_source_graph_node.gd` (~520)
- [ ] `synesyn/synesyn_dec2025/addons/syntree/scripts/ui/content_source_list/content_list_view.gd` (~502)

---

### 2) Regression contract (must stay correct throughout)

Run this checklist after each “unit of extraction” (each module split), not only at the end.

- [ ] **Toggle sync**:
  - [ ] Toggling **ActiveSource** in Graph updates List + Hierarchy, persists after restart.
  - [ ] Toggling **Metaprompt** in Graph updates List + Hierarchy, persists after restart.
  - [ ] Toggling in List updates Graph + Hierarchy (and vice versa).
- [ ] **No mass toggle / spillover**:
  - [ ] Toggling a single node never flips all nodes.
  - [ ] Switching views never flips toggles.
- [ ] **Selection stability**:
  - [ ] Selecting/deselecting graph nodes never forces an unwanted view switch.
  - [ ] “Select All” operates only on visible nodes in the current view (per existing behavior).
- [ ] **Hierarchy editing**:
  - [ ] Move Up/Down works in normal source hierarchy.
  - [ ] Move Up/Down works in stack context (reorders member sources, not internal nodes).
- [ ] **Linked child sources**:
  - [ ] Add Child opens dialog; child is a distinct source; link node has unique composed ID.
  - [ ] Link node shows dialog-provided name/path; effective-source toggles apply correctly.
- [ ] **Tab labels/tooltips**:
  - [ ] Tab title includes truncated source name (12 chars + ellipses).
  - [ ] Tooltip shows correct name/id/path (+ stack details when relevant).

---

### 3) Sequenced refactor program (safe order)

#### 3.1) Extract pure data operations first (lowest UI-risk)

**Goal**: reduce `content_state_resource.gd` and `content_source_resource.gd` without affecting UI wiring.

- [ ] Create `scripts/resources/internal/` folder (if absent).
- [ ] Extract **pure graph ops** (no signals, no Node/scene tree):
  - [ ] `content_graph_ops.gd`: node add/remove, edge add/remove, composed-id helpers (if appropriate).
  - [x] `content_stack_ops.gd`: stack edge/layout persistence helpers; stack member reorder helpers.
  - [x] `content_hierarchy_ops.gd`: hierarchy node move/reorder helpers.
  - [x] `content_edge_ops.gd`: edge add/remove mutation helpers.
  - [x] `content_stack_order_ops.gd`: read-only stack ordering helpers.
  - [x] `content_refresh_ops.gd`: active-source refresh + content parsing helpers.
  - [x] `content_node_persistence_ops.gd`: node field persistence helpers (e.g., positions).
  - [x] `content_source_schema_ops.gd`: schema validation + normalization helpers.
  - [x] `content_source_sync_ops.gd`: directory scan + sync-plan helpers.
- [ ] Extract persistence helpers if needed:
  - [ ] `content_persistence_ops.gd`: save + verify + retry helpers (resource-level, no UI).
- [ ] Replace big blocks in `ContentStateResource` with thin wrappers:
  - [ ] wrappers call ops, then emit signals if (and only if) state changed.
- [ ] Ensure strict typing where Godot inference fails (avoid parse errors).
- [ ] Remove redundant/legacy code once wrapper paths are fully used.

#### 3.2) Split “UI orchestration” second (highest churn risk)

**Goal**: reduce `syntree_panel.gd` by extracting cohesive controllers *and/or* cohesive internal helpers, keeping SyntreePanel as coordinator.

- [x] Create `scripts/ui/panel/` controllers (Nodes/scripts), owned by SyntreePanel:
  - [ ] `source_menu_controller.gd`: context menu building + select-all actions.
  - [ ] `add_child_flow_controller.gd`: dialog flow + pending-link handling (local + URL).
  - [ ] `move_node_controller.gd`: Move Up/Down wiring; stack-context pass-through.
  - [ ] Optional: `panel_refresh_controller.gd`: panel-level refresh scheduling hooks only.
- [x] Replace corresponding logic in `syntree_panel.gd` with delegation calls.
- [x] Delete dead code and old commented legacy blocks after delegation.

#### 3.3) Reduce “view components” third (clear responsibilities)

- [ ] `content_view_manager.gd`: isolate tab title/tooltip formatting helpers into a small utility file if needed.
- [ ] `content_list_view.gd`: keep only list rendering + signal handling; move data mapping helpers to a small internal.
- [ ] `content_hierarchy_view.gd`: isolate selection helpers + tree building into internal helper(s) as needed.

#### 3.4) Graph subsystem final tightening (only after core correctness is stable)

- [ ] Keep the single supported path:
  - [ ] `ContentViewManager` injects resources and calls `ContentGraphController.initialize(...)`.
  - [ ] Graph builds only via `initialize_with_source(...)` and internal builder/renderer.
- [ ] Ensure `ContentSourceGraphNode` never writes global state; it only emits signals.
- [ ] Ensure all remaining debug is gated behind `DEBUG/_dbg`.
- [ ] Remove any dead compatibility shims (only if no call sites).

#### 3.5) Non-graph large files (bounded follow-up)

- [x] `conversation_manager.gd`: split into cohesive internal helpers (kept manager as façade):
  - [x] `services/chat/internal/conversation_thread_disk_store.gd` (thread JSON disk IO)
  - [x] `services/chat/internal/conversation_context_utils.gd` (source matching + text extraction for context)
  - [x] `services/chat/internal/conversation_hub_thread_store.gd` (hub index/versioning/sync + load version)
  - [x] **Thread persistence guardrail** (v0 stability): thread JSON files are written only on explicit actions:
    - new thread creation
    - user prompt append
    - AI response append
    - edit-history save
    - (no startup “touch” save; no shutdown flush that can recreate deleted files)
- [ ] `prompt_chain_panel.gd`: split “prompt chain rendering”, “node editing”, “persistence wiring”.
- [ ] `content_bus.gd`: keep only autoload bus responsibilities; extract cohesive domains out as needed.
  - [x] Extract editor-only persistence/debounce scheduling into `autoload/internal/content_bus_persistence_scheduler.gd`

---

### 4) Execution workflow for each target file (repeatable template)

For each file in the target list:

- [ ] **Identify cohesive sections** that can become a module (single responsibility).
- [ ] **Extract** as a new script under a stable folder:
  - [ ] Prefer `internal/` helpers for pure logic.
  - [ ] Prefer `ui/panel/` controllers for panel orchestration.
- [ ] **Replace with thin wrapper** in the original file.
- [ ] **Remove dead code** (only when grep shows 0 call sites).
- [ ] **Run regression contract** (Section 2).
- [ ] **Stop and review**: confirm no new complexity/signals spaghetti were introduced.

---

### 5) Current status (as of this plan)

- [ ] Graph subsystem already has `GraphDataBuilder` and `GraphRenderer` extracted.
- [ ] Some dead code and unused fields were removed recently (low-risk bloat cleanup).

---

### 6) Next step (the immediate continuation)

**Next step** (choose one, based on current priorities):

- **Option A**: start the next large remaining file (e.g. `prompt_chain_panel.gd`) and apply the same domain-based extraction approach.
- **Option B**: tighten remaining view components (`content_hierarchy_view.gd`, etc.) if you want those <800 for comfort (optional; they’re already in-range).

Rationale: `syntree_panel.gd` and `content_bus.gd` are now within target range; we can shift focus to the next highest-maintenance surface.




