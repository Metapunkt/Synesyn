# 0010 — Shared spatial UI and semantic visual system

- **Status:** Superseded / Withdrawn (2026-07-15) — the spatial UI (cube/drum
  shells, HSM/BT flow, face-mounted surfaces) was abandoned after a cost-benefit
  review found the effort disproportionate and the UX thesis weak for this
  product. Only the **semantic visual profile system + components** were salvaged
  into `addons/synesyn_visual_profiles/` (used by `ThemeManager`). All spatial
  code, product adapters, and planning docs were moved to `_archive/spatial_ui/`.
  ADR 0009's Workshop dashboard-shell presentation decisions are back in force.
- **Original status:** Accepted
- **Date:** 2026-07-14
- **Area:** Godot client / cross-product presentation
- **Supersedes:** (historical) ADR 0009 only for the Workshop dashboard-shell
  presentation described by its workspace-preset and responsive-layout decision
  paragraphs; its session, synthesis, safety, and human-agency decisions remain
  in force. This partial supersession is itself withdrawn per the status above.

## Context

Synesyn's Godot client contains substantial business logic and several valuable
spatial systems, including SynPunkt's edgeless canvas, SynAxes' 3D pattern
viewer, SynTree's graph workspace, and Story Stage. Godot therefore remains an
important application engine rather than a disposable front end.

The current presentation layer nevertheless asks Godot to reproduce dense
desktop and web application conventions. The result is costly layout work,
large controller scripts, duplicated panel-state behavior, many local theme
overrides, and an interface users experience as dated.

The existing theme system centralizes light/dark selection across base, utility,
console, and tools surfaces, but structural tokens, product-local themes,
Control styling, 3D materials, and motion remain separate. ReadyMade also owns a
parallel theme stack.

Godot 4.7 adds Control offset transforms that make expressive UI motion inside
Containers more reliable. LimboAI 1.8 is already part of Synesyn and provides
both hierarchical state machines and Behaviour Trees.

## Options considered

1. Continue refreshing conventional panels and dashboards. This is least
   disruptive but retains the interaction and maintenance mismatch.
2. Move the primary application shell to web or Tauri. This improves conventional
   application UI but requires a broad boundary around existing Godot business
   logic and underuses current spatial infrastructure.
3. Build a Workshop-specific 3D cube. This validates the metaphor quickly but
   risks another product-owned shell that cannot support SynTree, SynAxes,
   SynPunkt, ReadyMade, or Story Catalyst.
4. Build a shared spatial interaction system with product adapters, configurable
   shells, LimboAI interaction flow, and a semantic visual profile spanning 2D
   and 3D. Migrate through bounded vertical slices with native fallbacks.

## Decision

Adopt option 4.

The Godot client will gain a product-neutral spatial UI package. Products
register work surfaces through resources and adapters. The shared package owns
spatial shell lifecycle, camera and transition behavior, input and focus routing,
responsive frame behavior, motion preferences, accessibility hooks, and visual
profile resolution.

The first shell prototype will use a stable application frame around a central
spatial object:

- a labelled destination/tool panel on the left;
- a contextual inspector or queue on the right;
- persistent voice, action, safety, and commit controls at the bottom;
- minimal identity, connection, and progress status at the top;
- a central fixed-camera spatial viewport containing a cube or horizontal drum.

Wide layouts may show both side panels. Medium layouts show one at a time.
Narrow layouts use overlay drawers. Projector mode minimizes the frame without
hiding essential status or safety.

LimboAI responsibilities are divided deliberately:

- a hierarchical state machine owns deterministic interaction lifecycle;
- Behaviour Trees sequence activation, transition, focus, fallback, recovery,
  and optional guidance inside those states;
- product domain state, artifacts, decisions, and commits remain outside both.

True face-mounted Control scenes rendered through SubViewports are the preferred
prototype path. A shared ray/UV input router will be validated against pointer,
wheel, drag, text, keyboard, popup, IME, high-DPI, and accessibility needs.
Front-aligned 2D overlays remain an allowed fallback, not the assumed design.

The visual system will use semantic profiles rather than multiplying independent
theme families and local overrides. A profile will resolve:

- Control Theme and type variations;
- typography and spacing roles;
- semantic and human-agency colors;
- motion timings and reduced-motion behavior;
- 3D materials, lighting, focus, and state treatments.

Products may select an appropriate shell form. A cube is not mandatory for
settings, services, text-heavy sheets, or any workflow that gains no material
benefit from spatial presentation.

## Consequences

- ADR 0009's stable Workshop dashboard hierarchy becomes a compatibility shell,
  not the long-term presentation target. Its safety and workflow invariants
  remain mandatory.
- The spatial framework must be derived from at least Workshop Catalyst and
  SynTree before its adapter contract is declared stable.
- Existing native surfaces remain operational until their replacements pass
  automated and manual acceptance.
- ThemeManager requires a compatibility bridge during migration; replacing it
  in one step is prohibited.
- LimboAI UI trees and states must remain presentation-scoped and must not
  become an alternate business-logic or persistence layer.
- SubViewport input complexity becomes an explicit feasibility gate rather than
  an incidental per-product workaround.
- Spatial motion may improve orientation and product identity, but reduced
  motion, direct navigation, focus restoration, and projector readability are
  non-negotiable.
- The former conventional UI refresh plan is superseded where it conflicts with
  this decision. Its readability, hierarchy, focus, status, and accessibility
  goals remain applicable.

## Validation and rollback

ADR acceptance records the architectural direction; the linked PRD remains in
Review and must be approved before runtime implementation begins.

The neutral shell and Workshop vertical slice must be feature-flagged. Failure
of the spatial renderer, LimboAI flow, input router, or profile resolver must
leave the existing native surface reachable. No native shell may be removed
until a second product adapter proves the shared contract and the owning
acceptance suite passes.
