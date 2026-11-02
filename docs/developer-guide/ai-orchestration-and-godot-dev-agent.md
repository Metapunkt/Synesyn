# AI Orchestration (SynTree) + Packs (Metapunkt) + Godot Dev Agent

This document explains how **SynTree** (ensembles and prompt chains),
**Metapunkt** (capability packs), and the **Godot Dev Agent harness** divide
responsibilities across the platform.

Current CLI operating instructions live in
[`devagent-cli-for-agents.md`](devagent-cli-for-agents.md). The executable-spec
decision is recorded in
[ADR 0006](../architectural-decisions/0006-self-validating-json-harness-specs.md).
Metapunkt's binding contract lives in
[`Metapunkt_Synterfaces_and_Bindings.md`](../implementation_docs/Metapunkt_Synterfaces_and_Bindings.md).

## Core concepts (short + precise)

### Ensemble (SynTree)
An **Ensemble** is a set of cooperating AI roles (agents) with distinct responsibilities (e.g., Planner, Editor, Verifier).  
It answers: **“who is participating?”**

### Prompt Chain (SynTree)
A **Prompt Chain** is an ordered (sometimes branching) workflow of steps (plan → generate → validate → repair → finalize).  
It answers: **“in what order do they act, and how do we recover from errors?”**

### Pack (Metapunkt)
A **Pack** is a *shippable, reusable capability* that wraps orchestration into a product-like unit with:
- an input/output contract,
- defaults + configuration UI,
- tool/permission constraints,
- versioning + dependencies.

It answers: **“what can I install/use as a named feature?”**

## Where each concept should “live” (and why)

### SynTree should own Ensembles + Prompt Chains
SynTree is the orchestration engine and authoring environment. Keeping Ensembles/Chains here:
- avoids duplicate orchestration logic in multiple systems,
- keeps debugging in one place,
- makes “multi-agent + multi-step” behavior consistent across apps.

### Metapunkt should own Packs
Metapunkt is the packaging/distribution + UX layer. Packs belong here because they:
- present capabilities as installable tools,
- define stable contracts,
- handle versioning, defaults, and UI exposure.

## How they work together (author → package → run)

1) **Author** Ensemble + Prompt Chain in SynTree (roles + step graph + validators/retries).  
2) **Package** them as a Metapunkt Pack by either:
   - **Reference-based Pack**: points to a SynTree chain/ensemble by ID/path (best during active development).
   - **Snapshot Pack**: embeds an exported copy of the chain/ensemble (best for portability + releases).
3) **Run** the Pack in Godot: Metapunkt provides the UI/config + contract, SynTree executes the chain under the hood.

## Godot Dev Agent (what it is)

The **Godot Dev Agent** is a SynTree-authored ensemble + chain, shipped as a Metapunkt Pack, that helps:
- run focused UI flows,
- capture screenshots/artifacts,
- analyze results,
- apply fixes safely,
- repeat.

## Godot Test Harness (agreed design)

### Goal
Enable a tight loop: **run → set deterministic UI state → capture artifacts (screenshots/metrics) → critique → fix → repeat**, without shipping test-only runtime singletons.

### Where it runs
- **Agent/CLI path:** Python validates and expands JSON run specs, launches the
  Godot harness scene, and evaluates structured artifacts and assertions.
- **Editor path:** SynTree can still write or launch pending specs for interactive
  work.
- The harness remains a scene plus small target-scene hooks, not another runtime
  autoload.

### What the harness needs (minimum)
- **Scene load control**: open Story Log and/or Story Stage.
- **Deterministic state setting**: scenario, toggles (e.g., Auto Player Input), emitter selection, etc.
- **Artifact output**:
  - screenshots to disk,
  - optional layout metrics dump to JSON (node rects, visibility, enabled states),
  - logs.

### Key design constraint
Even when “embedded in SynTree”, the harness should rely on a **small explicit interface** (“test hooks”) in the target scenes, rather than hardcoding deep scene internals in the editor plugin.

### Hooks: when they are required vs optional

- **Without any hooks**, the harness can still:
  - load a scene from a Run Spec’s **`scene_path`**
  - capture a **screenshot** (PNG)
  - capture **generic UI metrics** (JSON) by walking the `Control` tree
  - write a run manifest (`run.json`) and update `harness_last_run.json`

- **Hooks are required** when you need **deterministic setup** or **project-specific outputs**, because the editor plugin/harness should not hardcode fragile node paths:
  - deterministic toggles (e.g. “auto player input”, emitter selection)
  - session type, collection, and scenario selection
  - structured logs/errors that the agent can read reliably
  - richer UI metrics than the generic Control-walk provides

#### Current test-hook surface
On the root node of each target scene (or a dedicated child node), expose methods like:
- `test_apply_state(state: Dictionary) -> void`
- `test_send_user_message(message_text: String) -> void`
- `test_dump_logs(output_path: String, since_msec: int = 0) -> void`

Generic screenshot and UI-metric capture belong to the harness runner. This keeps
the scene hook surface small as the UI refactors.

## Godot Dev Agent capabilities (what’s feasible, and what it requires)

This answers the practical question: “can the agent **view scenes/nodes/scripts**, do **CRUD**, **play/stop**, **update properties**, and **read output**?”

### Two surfaces: editor-time vs runtime-time

- **Editor-time (EditorPlugin / EditorInterface)** is best for:
  - opening/changing/saving scenes,
  - inspecting & editing node trees and properties,
  - orchestrating play/stop,
  - driving deterministic setup before a run.
- **Runtime-time (test hooks in scenes)** is best for:
  - screenshots (actual in-game rendering),
  - UI metrics (rects, visibility, enabled/disabled),
  - collecting logs/errors in a machine-readable way.

### Capability matrix (requested items → recommended approach)

- **View scenes (which scene is loaded / open a scene)**:
  - **How**: editor harness opens a `.tscn` via editor API; runtime harness can also load a scene in a test runner.
  - **Requires**: editor harness plugin *or* a small test-runner entrypoint.

- **View nodes (tree, names, paths, key properties)**:
  - **How**: editor harness reads `EditedSceneRoot` and iterates children; runtime hook can dump a stable tree snapshot to JSON.
  - **Requires**: editor harness plugin (for interactive inspection) and/or `test_dump_ui_metrics(...)`.

- **CRUD on nodes (create/delete/reparent, set properties)**:
  - **How**: editor harness mutates the edited scene via editor API and saves.
  - **Requires**: editor harness plugin; keep operations small + reversible.

- **CRUD on scripts**:
  - **How**: treat scripts as **files on disk** and make changes via patch-based edits, then verify by Godot parse/reload and (optionally) a run.
  - **Requires**: a writeback path (apply patch → save → refresh sources) + a verification step (parse errors, missing resources) wired into the harness loop.
  - **Important**: avoid “editing scripts inside a CodeBlock”. In SynTree, CodeBlocks are best as **read-only evidence**; writeback should be explicit and reversible.

- **CRUD on scenes (`.tscn`)**:
  - **How**: editor harness is ideal (preserves Godot’s serialization expectations); filesystem edits are possible but brittle.
  - **Requires**: editor harness plugin for most changes.

- **Play / stop scenes**:
  - **How**: editor harness triggers play and stop via editor API.
  - **Requires**: editor harness plugin.

- **Update node properties / presets / values**:
  - **How**: editor harness sets properties before play; runtime hook can apply state at runtime for UI toggles.
  - **Requires**: either editor harness property set, or `test_apply_state(state)`.

- **Access console output (prints/warnings/errors)**:
  - **How**: prefer *explicit log capture to disk* (JSON/text) during harness runs; treat the editor console as non-contractual UI.
  - **Requires**: runtime log capture helper (inside test hooks) or standardized “artifact log” output.

- **Access debugger output**:
  - **Reality**: fully automating the live debugger UI is not a good target.
  - **Replacement**: capture errors as structured artifacts + assert on them; for crash-level issues use exit codes and Godot logs.

### Minimal runtime “test hook” contract (recommended)

Keep these methods small and stable; they are the bridge between SynTree’s editor harness and the game’s internal scene logic.

- **`test_apply_state(state: Dictionary) -> void`**:
  - Inputs: session type, collection, scenario name, toggles (auto input, autosend voice), etc.
  - Goal: deterministic UI/config without requiring the editor plugin to know deep node paths.

- **`test_send_user_message(message_text: String) -> void`**:
  - Exercises the stable user-intent boundary without scripting internal controls.

- **`test_dump_logs(output_path: String, since_msec: int = 0) -> void`** (recommended):
  - A lightweight log ring-buffer exported as JSON for the agent to read.
  - Lets the agent “read console output” without scraping editor UI.

Screenshots and generic Control-tree metrics are captured by the harness runner,
not by target-scene hooks.

### Logs: “scene logs” vs “engine console logs”

There are two complementary strategies, and the harness supports both:

1) **Scene logs** (recommended, deterministic):
   - Implement `test_dump_logs(...)` on the scene root (or a stable child).
   - Export JSON that represents *what matters* for your app (state snapshot, errors, counters, last N messages, etc.).
   - This does **not** require any new runtime autoload; it’s just a method on your scene.

2) **Engine console logs** (best-effort, for “real prints/warnings/errors”):
   - The harness runner also writes a `godot_log_tail.txt` artifact by reading the tail of Godot’s logfile (location varies by platform/settings).
   - This captures real engine/editor output, but it is less deterministic and not a strong “contract” (file location/content can vary).

### Harness artifact contract (one spec → one run folder)

Each harness run produces a stable output folder under the configured session data root:
- `<session_data_dir>/syntree_artifacts/runs/<run_id>/`
  - `run.json` (manifest)
  - `run_spec.json` (spec actually used)
  - `pending_run.json` (the pending payload SynTree wrote)
  - `screenshot.png`
  - `ui_metrics.json`
  - `scene_logs.json` (if the scene implements `test_dump_logs`)
  - `godot_log_tail.txt` (best-effort logfile tail)

And a stable pointer file:
- `<session_data_dir>/syntree_artifacts/harness_last_run.json` → points at the latest `run.json`

## UI affordances for effective Godot iteration (using existing SynTree surfaces first)

You already have strong building blocks in the SynTree addon:
- **Content Sources** (file/URL), with a **graph/list/hierarchy** view, plus **Active Source** and **Metaprompt** toggles.
- **Stacks** (curated “working sets” of sources).
- **Refresh Active Sources**.
- **Publish Context Graph** (ships a snapshot of “what’s active” to the Hub as an artifact).
- **Conversation Threads** (persistent run history / prompts / outputs).

To fully iterate on a Godot project (including script CRUD) with a Dev Agent loop, the key is to make 4 actions effortless:

### 1) Curate “working context” (already mostly solved)
- **Use “Active Source?”** as “include this file in context compilation”.
- **Use “isMetaprompt?”** for sticky instructions (house style, constraints, project invariants).
- **Use Stacks** for repeatable working sets (e.g. “Story Stage UI stack”, “External input stack”).
- **Add one-click ways to populate Active Sources** from the Godot editor selection (minimal new surface):
  - From FileSystem dock: “Add to Active Sources”
  - From ScriptEditor: “Add current script to Active Sources”

### 2) Run a deterministic check/capture loop (small new surface)
Add a lightweight “Run Spec” concept (JSON) that can be saved/loaded from a SynTree thread, containing:
- **`scene_path`**: explicit `.tscn` path to run (project-agnostic)
- **`state`**: optional dictionary passed into `test_apply_state(state)` if the scene root implements it
- **`actions`**: optional array of generic calls into `/root/<autoload>` nodes (project-specific but not hardcoded)
- artifact outputs (paths for screenshot/metrics/logs) — produced into the configured session data dir

This avoids “try to remember what you clicked last time”.

### 3) Review + apply changes (this is the main missing surface for script CRUD)
Because SynTree can generate code blocks but CodeBlocks are read-only, you need an explicit writeback affordance:
- **Patch review**: show unified diff (or “before/after”) for affected files.
- **Apply**: write changes to disk (guarded by scope rules).
- **Revert**: one-click rollback of the last apply (store backups or a patch stack).
- **Refresh**: trigger “Refresh Active Sources” so the next prompt sees the updated code.

If you want to minimize new UI: make this a single modal (“Apply Patch”) launched from the chat output or toolbar.

### 3.5) Dev Agent ON/OFF toggle (required safety affordance)
Add a clear “armed/disarmed” toggle in the SynTree panel:
- **OFF (default)**: read-only. Allow chat + context compilation + run spec authoring, but disable side-effect actions (apply patches, run harness, publish, etc.).
- **ON**: enables side-effect actions.

Implementation note: persist this per-project (e.g., in `ViewStateResource`) so it survives editor reloads.

### 4) Verify from artifacts, not eyeballing editor UI (small new surface)
Make “what happened?” readable without scraping the editor:
- screenshots
- UI metrics JSON
- logs/errors JSON

Provide a simple “Open last artifacts” button (or a list inside the thread).

## Practical recommendation: script CRUD in the Dev Agent should be *patch-based and scoped*

To keep this safe and usable:
- **Scope write permissions** to either:
  - selected/active sources only, or
  - an explicit allowed directory list (e.g. `res://ScenSyn/`, `res://addons/...`).
- **Prefer patch application** over raw “replace file content” operations.
- **Always follow apply with verification** (parse + basic run + artifact capture).

## Operational discipline (policy/workflow)

These are “guardrails” to keep the Dev Agent workflow maintainable across projects:

- **Orchestration lives in SynTree**:
  - Ensembles + prompt chains should be authored/edited in SynTree.
  - Metapunkt Packs should **wrap** capabilities (UI + contracts + permissions), not re-implement the orchestration loop.

- **Harness stays project-agnostic**:
  - The harness runner should depend on **`scene_path`** and optional **hooks**, not on app-specific autoloads or hardcoded scene mappings.
  - Project-specific behavior should be expressed in the Run Spec (e.g. `actions`) and/or via scene hooks.

- **Prefer stable hooks over deep coupling**:
  - Avoid hardcoding fragile node paths from the editor plugin/harness.
  - Add/keep small `test_*` hooks on scene roots (or a dedicated test child) to provide a stable interface.

- **Treat artifacts as the contract**:
  - Prefer structured artifacts (`run.json`, `scene_logs.json`, metrics JSON) over scraping editor UI.
  - Keep “engine logfile tail” as best-effort debugging, not the primary API.

- **Keep side effects explicit and reversible**:
  - Dev Agent toggle OFF should mean read-only.
  - Patch apply should be backed by backups + easy revert.

