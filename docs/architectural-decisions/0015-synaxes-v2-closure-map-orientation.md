# 0015 — SynAxes V2: Closure Map orientation (Distal / Deep / Proxistance)

- **Status:** Accepted
- **Date:** 2026-08-07
- **Area:** client / SynAxes / conceptual instrument
- **Relates to:** SynAxes V1 pipeline; Human Agency UX Contract; [Closure Map](../concepts/closure-map.md); [PRD-SYNAXES-CLOSURE-MAP-ORIENTATION](../product-requirements/PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md)

## Context

SynAxes V1 is a working Latent Reality engine: import → embed → discover →
Dream Inbox → commit `ui.closure` with provenance. Architecture and review docs
still describe V2 as a “4D canvas” (3 spatial + 1 temporal). That language
imports a physics spacetime metaphor that the Closure Map explicitly rejects as
asymmetrical and unsuitable for phenomenological / curatorial use.

Meanwhile the Closure Map matured into Distal ↔ Deep / Recursive Closure with
Past ↔ Future, Here-and-Now as double threshold, Proxistance as movement, and a
tetrahedral relational grammar. Without an ADR, SynAxes V2 risks building a
scrubber that pretends Pattern Space is spacetime, while the product’s real need
is orientation of *closures* and proxistant navigation between overview and
recursive encounter.

## Options considered

1. **Physics-4D canvas** — treat Pattern Space XYZ as “space” and add temporal
   scrubbing as the fourth dimension. Pros: matches older docs. Cons: false
   precision; fights embedding geometry; ignores Distal/Deep asymmetry.
2. **Replace Pattern Space with a 2D Closure Map plot** — plot items on
   Past/Future × Distal/Deep. Pros: theory-visible. Cons: destroys similarity
   geometry that clustering depends on; conflates typology with embedding.
3. **Closure Map as meta-layer; Proxistance as V2 navigation** — keep 3D
   Pattern Space for semantic proximity; add human-first A–D orientation on
   closures; treat Distal↔Deep as overview↔recursive encounter; treat
   Past↔Future as orientation of the hold (including time window). Pros: honest
   about Distal≠Deep magnitudes; aligns Lawson commit with typology audit.
   Cons: requires UI/schema for tags; “4D” language in older docs must be
   reframed.

## Decision

Adopt option 3.

- SynAxes remains the authoritative **closure-formation engine** (propose →
  preview → commit → version).
- The Closure Map is the authoritative **orientation and coverage instrument**
  over committed (and candidate) closures — not the literal axes of Pattern Space.
- V2 “temporal / 4D” work means: (a) Past↔Future orientation of the hold,
  (b) Proxistance between Distal overview and Deep / Recursive Closure
  encounter, (c) optional tetrahedral edge readings once A–D tags exist.
- Do **not** auto-classify A–D from embeddings in the first product slice.
- Do **not** claim Distal and Deep magnitudes are comparable in the UI.

## Consequences

- Positive: theory and product share vocabulary; Dream Inbox / Saved Closures
  can audit structural skew; bridges can later map to tetrahedral edges.
- Trade-offs: older “4D canvas” phrasing in technical-review and architecture
  docs should be updated to point here and to the Closure Map; V2 scope is
  orientation + proxistance, not a spacetime simulator.
- Follow-ups: ship A–D tags + coverage per
  PRD-SYNAXES-CLOSURE-MAP-ORIENTATION; bump `ui.closure` schema when tags
  persist; refresh SynAxes README / platform architecture wording for V2.
