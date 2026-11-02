---
id: PRD-SYNAXES-CLOSURE-MAP-ORIENTATION
title: SynAxes Closure Map orientation tags and coverage
status: implementing
version: "0.1"
owner: SynAxes / product
last_reviewed: 2026-08-07
primary_users: ["facilitator", "curator", "researcher", "developer"]
supersedes: null
---

# SynAxes Closure Map orientation tags and coverage

## Problem and outcome

SynAxes can form and commit closures, but cannot yet say *what kind of closure*
was formed in Closure Map terms. Without orientation tags, facilitators and
curators cannot audit whether a corpus of commits is structurally skewed (e.g.
always Distal Past, rarely Deep Future).

**Outcome:** A human can tag Dream Inbox candidates and committed closures with
quadrants A–D, see coverage across Saved Closures, and persist orientation with
the `ui.closure` artifact — without changing Pattern Space geometry.

Canonical theory: [`../concepts/closure-map.md`](../concepts/closure-map.md).  
Architecture: [ADR 0015](../architectural-decisions/0015-synaxes-v2-closure-map-orientation.md).

## Users and jobs

- **Facilitator / curator:** When reviewing Dream Inbox proposals, they need to
  assign an orientation (or leave untagged), so that later they can see which
  registers are over/under-represented.
- **Researcher / critic:** When inspecting Saved Closures, they need a coverage
  summary, so that structural bias is legible at a glance.
- **Developer:** When extending SynPunkt or analytics, they need a stable
  optional field on `ui.closure`, so that orientation travels with provenance.

## Success measures

- A candidate can be tagged A–D (or left untagged) before commit.
- Committed `ui.closure` payloads include optional orientation when set.
- Saved Closures list shows orientation; a coverage strip summarizes counts.
- Untagged closures remain valid; tagging is never required to commit.
- No automatic A–D inference from embeddings in this version.

## Scope

### In scope (spike / v0.1)

- Human-first orientation control in Closure Editor.
- Persist `orientation` on `ui.closure` (schema bump).
- Coverage summary over currently loaded Saved Closures.
- Display orientation on Saved Closures rows and Dream Inbox rows when set.
- Tooltips using Closure Map vocabulary (Distal / Deep · Recursive Closure).

### Out of scope

- Auto-classification from embeddings or LLMs.
- Plotting Distal/Deep as Y-axis of Pattern Space.
- Full tetrahedron UI (edges); may show a read-only hint later.
- Proxistance choreography as a dedicated mode (ADR 0015 V2 navigation; later).
- SynPunkt orientation filters (follow-on once field exists).

## Critical journey

1. User discovers patterns; Dream Inbox fills.
2. User selects a candidate; Closure Editor opens.
3. User optionally sets **Orientation** (A–D or Untagged).
4. User commits; Hub stores `ui.closure` with orientation when set.
5. User reloads Saved Closures; sees tags and a coverage strip
   (e.g. `A:3  B:1  C:4  D:0  ·:2`).

## UI sketch (Closure Editor + Closures tab)

```text
┌─ Closures tab ─────────────────────────────────────────────────────────┐
│ Dream Inbox                                                            │
│  [Cluster #2 …]  [A]                                                   │
│  [Cluster #5 …]  [·]                                                   │
│                                                                        │
│ Closure Editor                                                         │
│  Name:     [________________]                                          │
│  Intent:   [________________]                                          │
│  Orientation: ( ) Untagged  ( ) A Distal Past  ( ) B Distal Future     │
│               ( ) C Deep Past  ( ) D Deep Future                       │
│  Time: From [YYYY-MM-DD]  Until [YYYY-MM-DD]                           │
│  Items: …   [Add] [Remove]                                             │
│  [Commit Closure to Hub]                                               │
│                                                                        │
│ Saved Closures                                                         │
│  Coverage: A:3  B:1  C:4  D:0  untagged:2                              │
│  [A] Ecological archive …………                                           │
│  [D] Latent workshop intentions ……                                     │
└────────────────────────────────────────────────────────────────────────┘
```

**Control type:** `OptionButton` or exclusive button group — five values:
`untagged`, `A`, `B`, `C`, `D`. Prefer OptionButton to match existing SynAxes
controls; keep labels short with richer tooltips.

**Coverage strip:** plain `Label` above Saved Closures list; recompute on reload
and after commit. No charts in v0.1.

## Schema sketch (`ui.closure`)

Bump `schema_version` to `2` when orientation is present; readers must tolerate
v1 (missing field = untagged).

```json
{
  "schema_version": 2,
  "name": "…",
  "intent": "…",
  "orientation": {
    "quadrant": "A",
    "label": "distal_past",
    "map_version": "closure-map-2026-08"
  },
  "selection": { },
  "time_window": { "start": "", "end": "" }
}
```

| `quadrant` | `label` |
| --- | --- |
| `A` | `distal_past` |
| `B` | `distal_future` |
| `C` | `deep_past` |
| `D` | `deep_future` |

Omit `orientation` entirely when untagged (do not store `"untagged"` unless
needed for explicit “reviewed as untagged” later).

Optional later (not v0.1): `active_edges: ["A-C", "C-D"]` for tetrahedral
trajectories.

## Requirements

- **REQ-CMO-001:** Closure Editor exposes Orientation with values Untagged, A, B,
  C, D and tooltips naming Distal Past / Distal Future / Deep Past / Deep Future
  (Deep band = Deep / Recursive Closure).
- **REQ-CMO-002:** Commit includes `orientation` on `ui.closure` when not
  Untagged; Hub accepts schema_version 2.
- **REQ-CMO-003:** Saved Closures reload displays quadrant badge/prefix per row.
- **REQ-CMO-004:** Coverage label shows counts for A, B, C, D, and untagged among
  loaded Saved Closures.
- **REQ-CMO-005:** Commit remains possible without orientation (untagged).
- **REQ-CMO-006:** No embedding- or model-based auto-tag in this version.

## Acceptance

| ID | Method | Note |
| --- | --- | --- |
| REQ-CMO-001–005 | Manual | Tools → SynAxes → import → discover → tag → commit → reload |
| REQ-CMO-006 | Manual / code review | No auto-tag path |

Harness: not required for v0.1 (Hub artifact shape only); add a run spec when
automated substrate checks cover `ui.closure` fields.

## Implementation notes (spike)

| Piece | Location | Status |
| --- | --- | --- |
| Orientation control | `addons/synaxes/scenes/synaxes_main.tscn` (`OrientationOption`) | Done |
| Coverage strip | `CoverageLabel` above Saved Closures | Done |
| Bind + commit field | `synaxes_closure_controller.gd` | Done |
| Coverage recompute | on `reload_saved_closures()` via `get_artifact_json` | Done |
| Docs | Closure Map + ADR 0015 | Done |

Manual acceptance still required for REQ-CMO-001–005 in a live Hub session.
Later: refresh technical-review “4D” wording; tetrahedral edges; Proxistance UX.

## Links

- Concepts: [`../concepts/closure-map.md`](../concepts/closure-map.md)
- ADR: [`../architectural-decisions/0015-synaxes-v2-closure-map-orientation.md`](../architectural-decisions/0015-synaxes-v2-closure-map-orientation.md)
- SynAxes addon: [`../../synesyn_client/addons/synaxes/README.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/addons/synaxes/README.md)
- Tracker: [`../implementation_tracking/active/05_SynAxes.md`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/active/05_SynAxes.md)
