## SynTree — SyntreePanel domain split plan (avoid over-atomization)

### Purpose
Reduce `synesyn/synesyn_dec2025/addons/syntree/scripts/syntree_panel.gd` safely by **splitting by domain (cohesive responsibility)**, not by “random standalone functions”.

This document is the “global picture” map: it defines the domains, the state/function ownership, and an extraction sequence that **minimizes callback spaghetti** and **avoids helper sprawl**.

---

### 1) Current situation (why it feels over-atomized)
`SyntreePanel` currently mixes multiple unrelated domains (chat UI, content-source UI, model/provider settings, hub status/publish, resource bootstrap, etc.).

Recent refactors added several small panel controllers. Even if each one is “reasonable”, the **aggregate** can feel over-atomized when:
- One conceptual domain is split across multiple files (e.g., content-sources actions spread across menu + add-child + move-node controllers).
- Controllers require many cross-callbacks, creating “indirection bloat”.

---

### 2) Domain map (what the panel actually does)

#### A) **Composition root / bootstrap**
**Owns**: onready node refs, plugin manager refs, resource injection/bootstrapping.

**Functions (examples)**:
- `_ready`, `setup(...)`, `_ensure_resources_from_content_bus`
- `_connect_ui_signals`, `_connect_manager_signals`
- `_initialize_notification_manager`, `_notification`

**Rule**: Keep this in `SyntreePanel` as the composition root. This is the *one place* where “wiring” is expected.

#### B) **Content sources domain (List ↔ Hierarchy ↔ Graph)**
**Owns**: “source management UI” behaviors: context menus, select-all, add/edit sources, add-child linked source, move node up/down, import hierarchy, refresh content, delete node/source, and (optionally) stack creation dialog.

**Functions (examples)**:
- Source menus / selection helpers: `_get_action_source_id_for_menu`, select-all helpers, refresh/reveal/edit dialogs
- Hierarchy node actions: `_get_selected_node_id_for_tree_actions`, `_raw_node_id`, delete/move node
- Add child flow integration (dialog + remote resolve)
- Source list loading and content directory selection

**Goal**: This should become **one cohesive controller**, not 3+ micro controllers.

#### C) **Conversation domain**
**Owns**: thread dropdown/new thread, sending chat, message resend/delete, edit history popup.

**Functions (examples)**:
- `_on_send_message`, `_on_thread_selected`, `_on_new_thread`
- `_on_edit_history_pressed`, `_on_edit_history_saved`, `_on_message_resend`, `_on_message_deleted`

#### D) **Model/provider settings domain**
**Owns**: provider selector, API key field, model selector population/sync.

**Functions (examples)**:
- `_populate_ai_model_selector`, `sync_model_selector_with_manager`
- `_on_model_selected`, `_on_api_key_changed`, provider selector sync helpers

#### E) **Hub/Status domain**
**Owns**: status strip timer + health checks, thread hub versions popup.

**Functions (examples)**:
- `_setup_status_strip`, `_update_status_strip_async`
- `_on_open_thread_hub_versions`, `_on_thread_hub_version_activated`

#### F) **Hub publish domain**
**Owns**: publish active-context graph payload build + async publish.

**Status**: already extracted into `ui/panel/publish_context_graph_controller.gd` and should remain a separate domain controller.

---

### 3) Target module layout (few modules, each domain-sized)
We want **few** panel-level controllers, each with a clear scope:

- `ui/panel/content_sources_panel_controller.gd`
  - **One** place for content-source UI actions (menus + add child + move node + related helpers).
  - Minimizes cross-callback surface area by owning the cohesive behaviors.

- `ui/panel/chat_panel_controller.gd` (implemented)
- `ui/panel/model_settings_controller.gd` (implemented)
- `ui/panel/status_hub_controller.gd` (implemented; status strip + hub versions popup)
- `ui/panel/publish_context_graph_controller.gd` (already)

`SyntreePanel` remains the composition root and delegates into these controllers.

---

### 4) Consolidation rule (anti–over-atomization)
- Prefer **domain controllers** over “one-feature controllers”.
- If 2–3 controllers operate on the **same state + same UI** surface, they should be merged.
- Aim for **~3–5 panel controllers total**, not dozens.

---

### 5) Sequenced cut plan (do this in order)

#### Step 1 — Consolidate existing content-sources controllers
Replace:
- `move_node_controller.gd`
- `add_child_flow_controller.gd`
- `source_menu_controller.gd`

…with **one** `content_sources_panel_controller.gd`.

Then delete the old scripts once no longer referenced.

#### Step 2 — Pull “delete selected sources” into the same content-sources controller
This is part of the same domain and reduces `SyntreePanel` further.

#### Step 3 — Pull “create source stack” dialog flow into content-sources controller (optional)
Still the same domain.

#### Step 4 — Extract Conversation domain
Create `chat_panel_controller.gd`, delegate from `SyntreePanel`. **(Done)**

#### Step 5 — Extract Model/provider settings domain
Create `model_settings_controller.gd`. **(Done)**

#### Step 6 — Extract Status strip domain
Create `status_hub_controller.gd`. **(Done)**

---

### 6) Acceptance checks (must remain correct)
- 3-view sync remains stable (List ↔ Hierarchy ↔ Graph).
- Add Child flow still:
  - opens dialog
  - creates distinct child source
  - attaches link node with unique composed ID
  - supports URL/remote “late resolve”
- Move Up/Down still works in normal + stack contexts.
- No new callback spaghetti (consolidation should reduce callback count).




