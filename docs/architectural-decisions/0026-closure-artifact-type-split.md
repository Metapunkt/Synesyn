# 0026 — Session captures move to `ui.workshop_closure`; `ui.closure` means a SynAxes slice

- **Status:** Accepted (amended 2026-11-01)
- **Date:** 2026-09-19
- **Area:** hub substrate / ScenSyn / SynAxes
- **Amends:** ADR 0020 (Thinking Map / Closure Map boundary)
- **Relates to:** ADR 0015 (SynAxes v2 Closure Map orientation), ADR 0016 (Open Closure admissibility gate)

> Amendment note (2026-11-01, ADR 0032): Artrhythmetic Store was renamed to
> STFX Store (`stfx_store`).

## Context
Three producers wrote the artifact type `ui.closure`, with two incompatible
payloads, and the hub validated neither.

SynAxes' `commit_closure` writes a **slice**: a named, navigable way of looking at
accumulated material, carrying `name`, `intent`, `selection`, `time_window`, and
from schema v2 an `orientation` quadrant (ADR 0015). Its `schema_version` is the
integer 1 or 2.

ScenSyn's `ClosureSubstrateEmitter` wrote the `ClosureBus` event verbatim under the
same type. That event is a **session capture**: a decision, risk or deferred
question a room committed, carrying `statement`, `kind`, `outcome`, `voters_yes`,
`stage_name`. It has no `selection` and no `orientation`, and its `schema_version`
is the *string* `"1.0"` — the same field name holding a different type. Three
distinct call sites feed it: the session record's vote capture, the Thinking Map
facilitator route, and the Compare Paths commit.

Both are human-committed boundaries, which is why one type once looked
defensible. The cost showed up in the consumers:

- SynAxes' *Load saved closures* queries `ui.closure` and sorts each payload into
  Closure Map quadrants A–D. A capture has no orientation, so every one landed in
  `count_untagged`, **silently corrupting the coverage figure** that
  `PRD-SYNAXES-CLOSURE-MAP-ORIENTATION` treats as a measure of analytic spread.
- That query takes the 25 most recent artifacts of the type. A workshop capturing
  a dozen items can **push a facilitator's actual slices out of the window
  entirely**, with no indication anything was omitted.
- SynPunkt lists `ui.closure` for SynDoc generation. Selecting a capture yields a
  payload with no `selection` to present.
- Because the hub's `validate_workshop_artifact` seam returned unknown types
  untouched, nothing rejected either shape, and nothing would reject a third.

Every other workshop artifact already had the answer. `ui.workshop_summary`,
`ui.workshop_thinking_map` and `ui.workshop_path_set` each live in the
`workshop_` namespace with a strict hub validator and an integer `schema_version`.
The session capture was the one workshop artifact outside that convention.

## Options considered
1. **One type plus a discriminator field.** Add `closure_kind` and have consumers
   filter. Keeps the single "closure" concept, but every consumer must remember to
   filter, the hub cannot filter a payload field when serving
   `query_artifacts_by_type`, so captures still consume the 25-row budget before
   anyone can discriminate, and the `schema_version` type clash survives.
2. **Validate a union shape.** Have the hub accept either payload under
   `ui.closure`. Stops a third shape appearing but fixes none of the consumer
   breakage, which is the actual harm.
3. **Separate types, following the existing workshop convention.** Captures become
   `ui.workshop_closure`; `ui.closure` denotes a SynAxes slice and nothing else.
   Consumers become correct by construction: the type they query is the type they
   can parse.

## Decision
Adopt option 3.

- Session captures are written as **`ui.workshop_closure`**, joining their workshop
  siblings, with `schema_version` as the integer `1`.
- **`ui.closure`** denotes a SynAxes slice only.
- The hub **validates both**, in `app/substrate/closure_artifacts.py`, deliberately
  defined side by side so the two shapes cannot drift back together. Posting a
  capture-shaped payload as `ui.closure` is rejected with a message naming the
  correct type and this ADR.
- `outcome` is **not** constrained to a fixed vocabulary: votes record `yes`/`no`
  while a Compare Paths commit records `committed`. Enumerating one would have
  silently dropped the other.
- The `ClosureBus` event keeps its own `"1.0"` string version. The emitter now maps
  the event onto the artifact contract rather than posting it verbatim; the signal
  and the stored record are versioned separately because they change for different
  reasons.
- SynAxes' loader **skips capture-shaped payloads** already stored under
  `ui.closure` and says how many it skipped, so historical data stops distorting
  coverage without needing a migration.

## Consequences
- Positive: Closure Map coverage is computed from slices only; captures can no
  longer crowd out slices in SynAxes or appear unusable in SynPunkt; both payloads
  now fail fast at the seam with an actionable message; the naming matches every
  other workshop artifact.
- Positive: substrate writes stopped being silent. The emitter logs rejections and
  transport failures, so a contract break surfaces in the Godot output panel
  instead of vanishing. It also refuses to persist a capture with an empty
  statement rather than storing a record of nothing.
- Trade-off: artifacts written before this split keep the old type. They are read
  around, not migrated. A consumer reading raw history still meets both shapes
  under `ui.closure`, so the reader-side guard has to stay until that history is
  no longer interesting.
- Trade-off: the hub now rejects payloads it previously stored. That is the point,
  but any out-of-tree producer posting `ui.closure` will start seeing 400s.
- Follow-ups: mirror the split in the Artrhythmetic Store bridge, which still
  describes captures as mirrored `ui.closure` payloads; consider whether
  `query_artifacts_by_type` should expose metadata filtering, since `source_app`
  is already indexed and would let a unified "all closures" view exist without
  re-merging the types.
