# 0017 — Shared library addon `synesyn_core` (drop-in boundary)

- **Status:** Accepted
- **Date:** 2026-08-07
- **Area:** client / tooling / packaging
- **Relates to:** ADR 0005 (HubSubstrateClient transport split); PRD-SYNAXES-NAVIGABLE-DEFAULT-PATH Phase 0

> Amendment note (2026-09-18): the enforcement scripts named below now live at
> `synesyn/utilities/checks/check_addon_autoloads.py` and
> `synesyn/utilities/checks/addon_compile_sweep.gd`. Their behaviour, and the
> boundary this ADR establishes, are unchanged.

## Context

SynAxes, SynTree, Metapunkt and SynPunkt are marketed as Godot addons but their
scripts preload host paths (`res://scripts/hub_substrate_client.gd`,
`res://scripts/runtime_config.gd`) and the host autoload
`ThemeManager` points into `res://ScenSyn/`. A missing preload target is a hard
compile failure: the addons do not degrade in a clean project — they fail to load.

The four product addons must remain drop-in while still sharing config, hub client
and theme-switcher services. Duplicating those services per addon would drift;
leaving them in the host makes “addon” a false claim.

## Options considered

1. **Per-addon shims with local fallbacks** — Pros: literal single-folder drop-in.
   Cons: four copies of RuntimeConfig / hub client; provenance and URL policy drift.
2. **Shared library addon `addons/synesyn_core/`** — owns RuntimeConfig,
   ProviderModePolicy, HubSubstrateTransport, HubSubstrateClient, ThemeConfig,
   ThemeManager. Product addons depend on it only. Pros: one shared resource set;
   honest “drop in `synesyn_core` + the addon you want.” Cons: two folders minimum;
   ~30 path rewrites in the host project.
3. **Move shared code into each product addon as git submodules / copies** —
   Pros: single-folder per product. Cons: worse drift than (1); packaging cost.

## Decision

Adopt option 2.

**Canonical inventory in `addons/synesyn_core/scripts/`:**

- Config / policy: `runtime_config.gd`, `provider_mode_policy.gd`
- Hub client: `hub_substrate_transport.gd`, `hub_substrate_client.gd`
- Theme: `theme_config.gd`, `theme_manager.gd` (soft-loads host theme packs)
- Cross-app helpers: `synesyn_session.gd`, `thread_scope_utils.gd`,
  `auth_context_utils.gd`, `tool_call_schema.gd`
- Render: `synesyn_render_request_v1.gd`, `synesyn_comfy_client.gd`,
  `synesyn_render_service.gd`
- Graph workspace: `graph_workspace/**`
- Hub deployment / error rendering: `hub_locator.gd`, `hub_error_text.gd`
- Shared conceptual vocabulary: `closure_orientation.gd` — the Closure Map quadrant
  definitions, read by the SynAxes Closure Editor and the ScenSyn Workshop Catalyst
  Closure Audit (ADR 0020, amended 2026-09-06)

Former host copies under `res://scripts/` and
`res://ScenSyn/scripts/core/theme_*.gd` are **removed** after path rewrite
(not left as `extends` shims — those re-triggered “hides a global script class”
errors against the cached `class_name`).

Boundary rules:

1. **Scripts only.** No script under `addons/<product>/**` may reference
   `res://scripts/**` or `res://ScenSyn/**` for shared services. Resolve through
   `res://addons/synesyn_core/scripts/...` or global `class_name` symbols owned
   by that addon. Optional host *assets* (themes, schemas) may be soft-probed.
2. **Library shape.** `synesyn_core` ships no dock and no product scenes. Its
   `plugin.gd` registers the `ThemeManager` autoload via
   `add_autoload_singleton` (same pattern as SynTree’s `NotificationManager` /
   `ContentBus`). List `synesyn_core/plugin.cfg` first under
   `editor_plugins/enabled`.
3. **Runtime autoload.** The Synesyn host keeps a `ThemeManager=` entry in
   `project.godot` (EditorPlugin registration alone does not cover exported /
   game runs) but the path points into `synesyn_core`.
4. **Theme packs.** `synesyn_core` ships a bundled minimal theme pack
   (`addons/synesyn_core/themes/` + Noto fonts). Product addon scenes point at
   those paths. ThemeManager prefers a host `ScenSyn/themes/theme_config.tres`
   when present (full surface set), otherwise the bundled pack. Visual-profile
   bridge remains soft-loaded.
5. **Drop-in claim.** Documented as “`synesyn_core` + product addon,” verified
   headlessly for script load — not as a single orphan folder.
6. **No bare autoload identifiers.** No script under `addons/**` may name a
   project autoload directly (`ContentBus.foo()`). A bare identifier resolves
   only while that autoload is *live*, not merely declared in `project.godot`,
   so such scripts fail to compile in a fresh drop-in project or in headless
   tooling that loads scripts before autoloads register. Because the editor
   always has autoloads live, the mistake produces no local feedback — hence
   rule 8. (That last claim is narrower than written: see Amendment 2026-09-05.)
   Resolve at use time through:
   - `addons/syntree/scripts/autoload/syntree_autoloads.gd` — SynTree-owned
     (`ContentBus`, `PluginManager`)
   - `addons/synesyn_core/scripts/synesyn_autoload_access.gd` — host/project
     (`ThemeManager`, `WorkspaceBootstrapper`, `Global`, `StoryState`,
     `VoiceService`)

   An autoload name may not collide with a global script class name. Godot
   rejects the registration outright, so a script declaring `class_name X`
   cannot also be autoloaded as `X` — `NotificationManager` is exactly this
   case and is instantiated directly rather than autoloaded.

   Those two resolvers are the only exempt files. Give an accessor a `preload`ed
   script constant as its return type so call sites stay statically checked and
   autoload enums stay reachable without a live instance
   (`ContentBusScript.ViewMode.LIST`). Never cache a resolved autoload in a
   field: one registering later would leave the cached value null forever.
7. **Addons provision their own autoloads.** An addon requiring an autoload
   registers it in its own `EditorPlugin._enter_tree()` and removes in
   `_exit_tree()` only what it added, so disabling the plugin never strips a
   host project’s own entries. See `syntree_plugin.gd` `REQUIRED_AUTOLOADS`.
   Hosts are not expected to hand-edit `project.godot`. Registration must be
   guarded by `ProjectSettings.has_setting("autoload/<Name>")` — not only for
   tidiness: see Amendment 2026-09-05.
8. **Enforced, not just documented.**
   - `synesyn/tools/check_addon_autoloads.py` — reads autoload names from
     `project.godot` (so it tracks additions), skips names that are also
     `class_name` declarations, and fails on any bare reference under
     `addons/**`. Supports `--write-baseline` / `--check-baseline` like the
     line-limit ratchet.
   - `synesyn/tools/addon_compile_sweep.gd` — ground truth: compiles every
     product-addon script with no autoloads live. Catches what the pattern
     check cannot (type-inference breakage, renamed symbols).
   - `.cursor/rules/addon-autoload-access.mdc` — scoped to
     `addons/**/*.gd` so the convention reaches humans and agents at edit time.
9. **Shared conceptual vocabulary lives here too, not just shared services.** A set
   of terms defined *upstream* of the code — in a manual, an exposition, a standard —
   and rendered by two or more surfaces is a shared definition, and belongs in
   `synesyn_core` on the same grounds as hub policy. Two consequences follow from
   rule 1 rather than from taste. A definition held under `ScenSyn/**` cannot be read
   by an addon at all, so placing one there does not merely invite duplication, it
   mandates it. And no such vocabulary may be authored in a `.tscn`, because scene
   text cannot preload: baked picker rows, legends and help strings are transcriptions
   that no amount of care keeps synchronised, so they are populated from the shared
   table at mount. See ADR 0020 (amended 2026-09-06) for the case that established
   this: five transcriptions of the Closure Map quadrant table, one of which received
   a revision.

## Consequences

- Positive: product addons can be enabled beside `synesyn_core` without the
  ScenSyn host tree; shared hub/config/theme policy has one home; PRD Phase 0
  has a durable rule outside the UX tranche.
- Trade-offs: bundled pack covers base/utility (console/tools alias to utility);
  host ScenSyn pack remains the richer multi-surface set when present.
- Positive (rules 6–8): all 351 scripts across `syntree`, `syntree_voice`,
  `synaxes`, `synesyn_core`, `synpunkt` and `metapunkt` now compile with **no**
  autoloads live, so drop-in no longer depends on an editor restart and headless
  tooling can load addon scripts directly. The earlier `Engine.has_singleton()` /
  `Engine.get_singleton()` path in `syntree_plugin.gd` was removed: it never
  resolves autoloads in Godot 4 and was silently dead.
- Trade-offs (rules 6–8): resolving per use costs a `get_node_or_null` per call
  instead of a direct reference, and the correct form is a deviation from Godot’s
  documented idiom, which is why enforcement is mandatory rather than advisory.
  The conversion was behaviour-preserving: every converted site already carried
  its own null guard.

## Amendment — 2026-09-05: autoload registration rebuilds the autoload tree

### What was observed

The editor logged `GodotSynTreePlugin: PluginManager node not found in the scene
tree!` on every start, and every autoload initialised **twice**. A probe run in
game mode confirmed all 20 autoloads sit under `/root` and
`syntree_autoloads.gd` resolves them correctly, so the resolver was never at
fault — the failure was editor-only.

Cause: `addons/syntree_voice/plugin.gd` called `add_autoload_singleton(
"VoiceService", …)` unconditionally in `_enter_tree()`, even though the host
already declares `VoiceService` in `project.godot`. Mutating the autoload list
makes Godot tear down and re-create **every** autoload node. Because
`syntree_voice` is last in `editor_plugins/enabled`, that rebuild landed between
`syntree_plugin.gd` calling `_continue_initialization.call_deferred()` and the
callback running, so `/root/PluginManager` was genuinely absent for that frame
and SynTree's dock aborted the rest of its deferred setup.

### Corrections to the rules above

- **Rule 6's aside is too broad.** "The editor always has autoloads live" holds
  for *compilation* of bare identifiers, which is what rule 6 governs. It does
  **not** mean an autoload lookup always succeeds in the editor: autoload nodes
  are destroyed and rebuilt whenever the autoload list changes, so they are
  transiently absent during editor-plugin initialisation. Rule 6's existing
  instruction — resolve at use time, never cache — is what makes code safe here,
  and it now has a second justification beyond drop-in compilation.
- **Rule 7 gains a hard requirement.** Guarding `add_autoload_singleton` with
  `ProjectSettings.has_setting("autoload/<Name>")` is not cosmetic. An
  unconditional call by *any* enabled plugin invalidates autoload lookups for
  *every* other plugin initialising in the same batch. Plugin order in
  `editor_plugins/enabled` determines who gets broken, which makes the symptom
  look unrelated to its cause.

### Requirements for EditorPlugins

1. Guard registration: `if not ProjectSettings.has_setting("autoload/<Name>")`.
2. Track what was added and remove only that in `_exit_tree()`.
3. Never assume an autoload resolved during `_enter_tree()` is still valid in a
   deferred callback. Re-resolve (rule 6) and degrade rather than abort.

`synesyn_core/plugin.gd` and `syntree_plugin.gd` already complied;
`syntree_voice/plugin.gd` was the sole outlier and has been brought into line.
Its unconditional `remove_autoload_singleton` on `_exit_tree()` was also a
standing rule 7 violation that would have stripped a host project's own entry.

### Verification

Autoloads now initialise once, `GodotSynTreePlugin` reaches
`initialization complete` with `{ "success": true }`, and
`check_addon_autoloads.py` plus `addon_compile_sweep.gd` (351 scripts) both
pass. Neither tool detects this class of fault — both load scripts rather than
running the editor plugin lifecycle — so the guard is convention-enforced only.
