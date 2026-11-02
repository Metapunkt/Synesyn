# Synesyn UI Refresh Rollout Plan

**Status**: Superseded on 2026-07-14 by the spatial UI direction, which was
itself withdrawn on 2026-07-15 (see ADR 0010; tracker and contract archived
under `_archive/spatial_ui/docs/`). Only the semantic visual-profile system was
retained (`addons/synesyn_visual_profiles/`). Retained as historical UI
research; do not execute as the active rollout plan.  
**Scope**: Shared visual system + first-pass UI refresh for `Synesyn Launcher`, `ScenSyn Services`, `ScenSyn Character Selection`, and `ScenSyn Tools`  
**Primary reference inputs**: `synesyn/docs/ui_update_suggestions/After_1-1.jpeg`, `synesyn/docs/ui_update_suggestions/After_1-2.jpeg`, `synesyn/docs/ui_update_suggestions/After_1-3.jpeg`, `synesyn/docs/ui_update_suggestions/After_2-1.jpeg`

---

## 1) Purpose

This document captures the recommended rollout strategy for translating the current Synesyn UI toward the mockup direction shown in the UI suggestion images.

The goal is not to reproduce the mockups literally at first pass. The goal is to:

- establish a stronger, more coherent visual system
- improve hierarchy and readability
- make key workflows easier to understand at a glance
- reduce the "debug form" feeling in important screens
- implement changes in a safe, staged way that avoids broad UI regressions

This plan is intended to be a reusable reference during implementation, review, and later prioritization.

---

## 2) Core implementation principle

The mockups should be interpreted in two layers:

### 2.1 Structural layer (high priority, feasible now)
- cleaner grouping of content into sections/cards
- better spacing and hierarchy
- stronger selected/active states
- more deliberate headers, status rows, and primary actions
- clearer distinction between configuration, status, and action controls
- more product-like shells around existing features

### 2.2 Visual polish layer (secondary, partially manual)
- bespoke background artwork
- polished illustration treatment
- finalized icon family
- portrait/photo assets
- fine-grained brand styling decisions

The structural layer should be implemented first. It produces most of the UX value and is significantly safer than chasing full visual fidelity too early.

---

## 3) Delivery model

The refresh should be delivered scene-by-scene, not as a single broad redesign pass.

Recommended execution order:

1. Shared theme foundation
2. `Synesyn Launcher`
3. `ScenSyn Services`
4. `ScenSyn Character Selection`
5. `ScenSyn Tools` shell

This order is chosen to maximize visible improvement early while keeping the scope controlled.

---

## 4) Implementation split: what can be done directly vs what needs manual input

### 4.1 Agent-doable / in-repo implementation work

These changes are realistic to do directly in Godot scenes, themes, and scripts:

- theme tuning
- button, input, and panel restyling
- spacing and alignment cleanup
- section header hierarchy
- card-style grouping using `PanelContainer` / `MarginContainer` / layout nodes
- status row improvements
- tab shell cleanup
- scroll and viewport-fit behavior
- selection-state improvements
- restructuring scene layout to match the information architecture of the mockups

### 4.2 Medium-complexity implementation work

These are feasible, but require careful scene refactoring and verification:

- converting flat forms into grouped panels/cards
- rebuilding generated character rows into card-like selection items
- restructuring launcher and tools shells into clearer multi-column layouts
- cleaning modal/sheet presentation while preserving current behavior

### 4.3 Manual or design-owner work

These are likely best supplied or approved manually:

- final background art and gradients
- polished iconography
- portrait/character photography assets
- exact brand treatment
- decisions about how literal the mockup styling should be
- any final art-direction choices that go beyond layout and hierarchy

---

## 5) Shared foundation pass

### 5.1 Target files
- `synesyn/synesyn_client/ScenSyn/themes/SynesynUtility_light.tres`
- `synesyn/synesyn_client/ScenSyn/themes/SynesynBase_light.tres`

### 5.2 Goals
- define a cleaner shared light theme baseline
- normalize padding, corner radius, and spacing
- establish a reusable card/panel language
- improve button hierarchy for primary, secondary, and neutral actions
- improve label hierarchy for titles, section labels, and status text

### 5.3 Likely changes
- increase consistency of control padding
- soften borders and separators
- strengthen selected/focus states
- establish panel/card surfaces for grouped content
- tune font sizes and weights for hierarchy

### 5.4 Intentionally deferred
- bespoke gradients
- decorative background illustration
- highly custom icon styling

---

## 6) Phase 1: Synesyn Launcher

### 6.1 Mockup reference
- `synesyn/docs/ui_update_suggestions/After_1-1.jpeg`

### 6.2 Current implementation

Primary files:
- `synesyn/synesyn_client/scenes/synesyn_launcher.tscn`
- `synesyn/synesyn_client/scripts/synesyn_launcher.gd`

### 6.3 Why this scene goes first
- it is the front door to the platform
- the current structure is simple and low-risk to improve
- the mockup direction is clear and immediately testable
- it sets the tone for later scene refreshes

### 6.4 Intended changes
- turn the current launch actions into a clearer right-hand action stack or card stack
- separate branding from actions more deliberately
- group hub health/status and hub controls into a dedicated `Local Hub` card
- improve prominence of `Open ScenSyn`
- preserve `How To / Help`, but position it as a secondary support action

### 6.5 Files likely to change
- `synesyn/synesyn_client/scenes/synesyn_launcher.tscn`
- `synesyn/synesyn_client/scripts/synesyn_launcher.gd`
- shared theme files above

### 6.6 Manual design inputs that may still be needed
- final background art
- whether launch targets should have dedicated icons
- final decision on logo prominence vs content prominence

---

## 7) Phase 2: ScenSyn Services

### 7.1 Mockup reference
- `synesyn/docs/ui_update_suggestions/After_1-2.jpeg`

### 7.2 Current implementation

Primary files:
- `synesyn/synesyn_client/ScenSyn/scenes/services_panel.tscn`
- `synesyn/synesyn_client/ScenSyn/scripts/services/services_panel.gd`

### 7.3 Why this scene is second
- it has a strong mockup analogue
- it currently contains important functionality but still reads as a dense utility form
- clearer grouping would improve both aesthetics and usability

### 7.4 Intended changes
- split content into explicit visual sections:
  - Hub
  - Workspace
  - Actions
  - Display
  - Providers / voice settings
- make the modal feel more deliberate and less like a raw full-screen form
- improve the presentation of current workspace state
- make the primary action(s) obvious
- keep feedback/status messaging visible and contextual

### 7.5 Files likely to change
- `synesyn/synesyn_client/ScenSyn/scenes/services_panel.tscn`
- `synesyn/synesyn_client/ScenSyn/scripts/services/services_panel.gd`
- shared theme files above

### 7.6 Manual design inputs that may still be needed
- whether Services should remain a full-screen modal overlay or evolve toward a centered sheet/card
- how closely the layout should mirror the mockup

---

## 8) Phase 3: ScenSyn Character Selection

### 8.1 Mockup reference
- `synesyn/docs/ui_update_suggestions/After_2-1.jpeg`

### 8.2 Current implementation

Primary files:
- `synesyn/synesyn_client/ScenSyn/scenes/character_options.tscn`
- `synesyn/synesyn_client/ScenSyn/scripts/character_options.gd`

### 8.3 Why this scene is third
- it would benefit substantially from a card-based redesign
- the current interaction is functional but visually weak
- the structural changes are more involved than launcher or services

### 8.4 Intended changes
- move from checkbox-like list presentation toward card-like entries
- improve typography and hierarchy for:
  - character name
  - role/title
  - summary/description
- make selected state much clearer
- improve spacing, margins, and list readability
- preserve current gameplay logic while improving presentation

### 8.5 Files likely to change
- `synesyn/synesyn_client/ScenSyn/scenes/character_options.tscn`
- `synesyn/synesyn_client/ScenSyn/scripts/character_options.gd`
- shared theme files above

### 8.6 Manual design inputs that may still be needed
- portrait assets or final decision on portrait placeholders
- final choice on how much descriptive text should always be visible on each character card

---

## 9) Phase 4: ScenSyn Tools shell

### 9.1 Mockup reference
- `synesyn/docs/ui_update_suggestions/After_1-3.jpeg`

### 9.2 Current implementation

Primary files:
- `synesyn/synesyn_client/ScenSyn/scenes/synesyn_tools.tscn`
- `synesyn/synesyn_client/ScenSyn/scripts/synesyn_tools.gd`

### 9.3 Why this scene is fourth
- it is valuable, but more complex because it wraps multiple embedded tool surfaces
- a full shell redesign should not happen before the shared theme and other primary scenes are stabilized

### 9.4 Intended changes
- improve the header and shell hierarchy
- make tabs feel more polished and intentional
- give the outer shell a more cohesive product feel
- establish a stronger sense of navigation and current location

### 9.5 Important caution
The mockup implies a left-navigation shell. The current implementation is a tab-based shell hosting multiple embedded scenes. A full conversion to left-nav should not be the first step.

Recommended first pass:
- improve the current shell visually
- defer any larger shell architecture change until after the rest of the refresh has stabilized

### 9.6 Files likely to change
- `synesyn/synesyn_client/ScenSyn/scenes/synesyn_tools.tscn`
- `synesyn/synesyn_client/ScenSyn/scripts/synesyn_tools.gd`
- shared theme files above

### 9.7 Manual design inputs that may still be needed
- whether to keep tabs short-term or commit to a true left-nav shell later

---

## 10) Explicit non-goals for the first rollout

The following should not be treated as first-pass requirements:

- full literal mockup reproduction
- broad app-wide redesign in one sweep
- replacing all existing UI patterns at once
- introducing heavy visual effects that are hard to maintain
- destabilizing already fragile modal and popup flows while primary shell scenes are still being refreshed

In particular, the `Play A Scenario` popup should be treated cautiously after the recent regression-prone changes around viewport fitting and popup behavior.

---

## 11) Recommended implementation rhythm

Each phase should follow the same pattern:

1. adjust shared theme only as needed for that phase
2. refactor one scene layout carefully
3. verify behavior, scrolling, and navigation
4. review visually before moving on
5. only then continue to the next scene

This keeps the refresh reviewable and reduces the risk of hidden regressions.

---

## 12) Recommended immediate next step

If implementation begins now, the best starting point is:

1. shared theme refinement
2. `synesyn/synesyn_client/scenes/synesyn_launcher.tscn`
3. `synesyn/synesyn_client/scripts/synesyn_launcher.gd`

This yields the quickest visible improvement and establishes the visual vocabulary for later scenes.

---

## 13) Summary

The refresh should be treated as a controlled staged rollout, not a single redesign burst.

The main practical insight from the mockups is not only aesthetic. It is architectural:

- stronger shells
- stronger grouping
- clearer status presentation
- more obvious primary actions
- better use of whitespace
- more meaningful selected states

Those improvements are realistic to implement directly in the current Godot project, and they should deliver most of the UX gain even before final manual art direction is added.
