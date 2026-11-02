# To‑Do — Synesyn UI Refresh

**Status:** Superseded on 2026-07-14 by the spatial UI direction, which was
itself withdrawn on 2026-07-15 (see ADR 0010; tracker archived under
`_archive/spatial_ui/docs/`). Do not execute this checklist independently. Its
readability, hierarchy, focus, and status findings remain inputs to the
retained semantic visual-profile work (`addons/synesyn_visual_profiles/`).

**Primary spec references**
- `../Synesyn_UI_Refresh_Rollout_Plan.md`
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Human_Agency_UX_Contract.md`
- `../Local_Deployment_Runbook.md`

**Mockup references** — the `ui_update_suggestions/` mockups (`After_1-1`, `After_1-2`,
`After_1-3`, `After_2-1`) guided this work but are not distributed with the
repository, so the paths they were tracked under are omitted here.

**Intent**
- Translate the current Synesyn UI toward the mockup direction in a controlled, scene-by-scene rollout.
- Prioritize hierarchy, grouping, readability, status clarity, and selection states before bespoke visual polish.
- Separate theme/layout work that can be done directly in Godot from manual art-direction inputs that should remain owner-driven.

---

## Priority guide
- **v0 foundation**: stabilize shared light-theme language and refresh the launcher.
- **v1**: refactor the Services panel into clear section cards and improve modal readability.
- **v1.1**: redesign character selection around card-like presentation and clearer selection affordances.
- **later**: improve the Tools shell once the shared visual system is proven in the primary surfaces.

## A) Shared theme foundation
- [ ] (v0) Review and normalize shared light-theme behavior across:
  - [ ] `synesyn/synesyn_client/ScenSyn/themes/SynesynUtility_light.tres`
  - [ ] `synesyn/synesyn_client/ScenSyn/themes/SynesynBase_light.tres`
- [ ] (v0) Standardize control padding, corner radii, and spacing.
- [ ] (v0) Define clearer styles for:
  - [ ] primary buttons
  - [ ] secondary buttons
  - [ ] neutral buttons
  - [ ] inputs / dropdowns
  - [ ] panel/card surfaces
- [ ] (v0) Improve text hierarchy for:
  - [ ] scene titles
  - [ ] section headers
  - [ ] body/help text
  - [ ] status text
- [ ] (v0) Verify disabled, hover, focus, and selected states remain readable and distinct.

## B) Phase 1 — Synesyn Launcher
- [ ] (v0) Refresh the launcher shell in:
  - [ ] `synesyn/synesyn_client/scenes/synesyn_launcher.tscn`
  - [ ] `synesyn/synesyn_client/scripts/synesyn_launcher.gd`
- [ ] (v0) Separate branding and launch actions more clearly.
- [ ] (v0) Present launch actions as stronger, more deliberate surfaces/cards:
  - [ ] `Open ScenSyn`
  - [ ] `Open ReadyMade`
  - [ ] `Open Synesyn Studio (v2)`
- [ ] (v0) Group hub health and hub controls into a dedicated `Local Hub` section/card.
- [ ] (v0) Make hub status and URL easier to scan.
- [ ] (v0) Keep `How To / Help`, but visually demote it beneath core launch actions.
- [ ] (review) Decide whether the launcher needs:
  - [ ] owner-supplied background art
  - [ ] owner-approved action icons
  - [ ] a different logo/content balance

## C) Phase 2 — ScenSyn Services
- [ ] (v1) Refactor Services layout in:
  - [ ] `synesyn/synesyn_client/ScenSyn/scenes/services_panel.tscn`
  - [ ] `synesyn/synesyn_client/ScenSyn/scripts/services/services_panel.gd`
- [ ] (v1) Reorganize content into clear grouped sections/cards:
  - [ ] Hub
  - [ ] Workspace
  - [ ] Actions
  - [ ] Display
  - [ ] Providers / voice settings
- [ ] (v1) Improve the modal header and close affordance.
- [ ] (v1) Make primary actions visually obvious:
  - [ ] `Apply Workspace`
  - [ ] `Save & Apply Providers` (or equivalent current action)
  - [ ] `Test Voice`
- [ ] (v1) Improve current workspace summary presentation so it reads like a status block rather than a raw label.
- [ ] (v1) Reduce visual density in the workspace controls without losing capability.
- [ ] (review) Decide whether Services should remain:
  - [ ] full-panel modal overlay
  - [ ] or evolve later toward a centered sheet/card

## D) Phase 3 — ScenSyn Character Selection
- [ ] (v1.1) Refresh character selection in:
  - [ ] `synesyn/synesyn_client/ScenSyn/scenes/character_options.tscn`
  - [ ] `synesyn/synesyn_client/ScenSyn/scripts/character_options.gd`
- [ ] (v1.1) Replace flat checkbox/list presentation with clearer card-like selection items.
- [ ] (v1.1) Improve hierarchy for:
  - [ ] character name
  - [ ] role/title
  - [ ] summary/description
- [ ] (v1.1) Make selected state unambiguous and visually stronger.
- [ ] (v1.1) Improve scroll behavior and list readability under longer descriptions.
- [ ] (review) Decide whether character cards should use:
  - [ ] real portraits
  - [ ] placeholders
  - [ ] initials / abstract stand-ins

## E) Phase 4 — ScenSyn Tools shell
- [ ] (later) Improve the outer Tools shell in:
  - [ ] `synesyn/synesyn_client/ScenSyn/scenes/synesyn_tools.tscn`
  - [ ] `synesyn/synesyn_client/ScenSyn/scripts/synesyn_tools.gd`
- [ ] (later) Improve header hierarchy and shell consistency.
- [ ] (later) Refine tabs so the current structure feels more product-like.
- [ ] (later) Avoid a full left-nav conversion until the shared design language is proven in launcher/services/character selection.
- [ ] (review) Decide whether the long-term shell should remain:
  - [ ] top-tab based
  - [ ] or migrate toward a left-nav application shell

## F) Scope guardrails
- [ ] (always) Do not attempt a full app-wide redesign in one pass.
- [ ] (always) Avoid literal mockup reproduction where it increases maintenance burden without major UX gain.
- [ ] (always) Prefer layout/hierarchy wins before decorative polish.
- [ ] (always) Keep popup and modal changes conservative if they affect startup/navigation stability.
- [ ] (always) Verify one refreshed scene before moving to the next.

## G) Review checkpoints
- [ ] After theme foundation: confirm shared visual direction is acceptable before scene refactors continue.
- [ ] After launcher pass: confirm hierarchy, branding balance, and hub card structure.
- [ ] After Services pass: confirm grouping, readability, and modal presentation.
- [ ] After character selection pass: confirm selection clarity and information density.
- [ ] Before Tools-shell pass: confirm the earlier scenes establish the desired visual vocabulary.

## H) Suggested execution order
1. [ ] Shared light-theme foundation
2. [ ] Synesyn Launcher
3. [ ] ScenSyn Services
4. [ ] ScenSyn Character Selection
5. [ ] ScenSyn Tools shell
