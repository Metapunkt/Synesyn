# 0011 — Workshop spatial slice uses a cube topology

- **Status:** Superseded / Withdrawn (2026-07-15) — the spatial UI slice this
  ADR shaped was abandoned along with ADR 0010. The cube topology is not used;
  Workshop Catalyst retains its native dashboard shell. Kept as a decision-log
  record only.
- **Original status:** Accepted
- **Date:** 2026-07-14
- **Area:** ScenSyn client presentation

## Context

Workshop Catalyst has five stable workflow surfaces: Talk, Thinking Map, Compare
Paths, Session Record, and Overview. The spatial slice must preserve direct
selection, orientation, native fallback, and the existing Workshop controllers.
Evidence and provenance already belong in the stable contextual frame and do
not justify a sixth domain surface.

## Options considered

1. **Six-slot horizontal drum** — keeps every destination on one rotational
   ring, but the five-surface workflow leaves an arbitrary empty segment and
   weakens the distinction between primary work and Overview.
2. **Cube** — maps the four sequential work surfaces to lateral faces and
   Overview to the top. The bottom remains unused, avoiding an invented
   Evidence surface while preserving room for future presentation-only use.

## Decision

Use the shared cube definition as Workshop's preferred shell. Map Talk, Thinking
Map, Compare Paths, and Session Record to front, right, back, and left;
map Overview to top. Retain the shared horizontal drum only as a declared
fallback shell. Custom remains a local native layout preference, not a surface.

## Consequences

- Positive: direct navigation mirrors the established five-surface workflow and
  Overview has a distinct, memorable orientation.
- Trade-off: one cube face is intentionally unused and hidden from direct
  navigation.
- The native Workshop shell, product commands, drafts, and Hub state remain
  authoritative. This decision does not authorize native retirement.
