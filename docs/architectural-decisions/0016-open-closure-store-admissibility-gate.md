# 0016 — Open Closure admissibility gate in Artrhythmetic Store (+ SynAxes import)

- **Status:** Accepted (amended 2026-11-01)
- **Date:** 2026-08-07
- **Area:** hub / substrate / SynAxes / Open Closure bridge
- **Relates to:** Open_Closure Note 87; ADR 0015 (Closure Map orientation); Latent SEEDS positioning

> Amendment note (2026-11-01, ADR 0032): Artrhythmetic Store was renamed to
> STFX Store (`stfx_store`, mounted at `/stfx-store`).

## Context

Open Closure validated a provenance-gated context-pack decision against Synesyn
store schemas (standalone harness, Note 87) but did not modify Synesyn. SynAxes
can form `ui.closure` artifacts without a normative exclusion layer: high-scoring
but inadmissible material can still enter Pattern Space.

SynAxes (formation + Closure Map orientation) and Open Closure (enforce + audit
exclusion) must remain distinct instruments. The join is an **opt-in Store gate**
and a thin SynAxes import filter — not a merge of the two projects.

## Options considered

1. **Depend on Open Closure `ClosureRouter` inside the hub** for every retrieve.
   Pros: full audit API. Cons: new hard dependency, training/runtime cost,
   packaging Open_Closure into hub releases.
2. **Hard provenance filter in Store (opt-in), optional Open Closure discovery** —
   policy in `store_manifest.admissibility`; forbidden sources never enter
   context packs; structural faithfulness (leakage=0). SynAxes filters imports
   when the same policy is enabled. Pros: reversible, LLM-free, matches Note 87
   seam. Cons: no attention-mask audit unless Open Closure is separately on
   PYTHONPATH (informational only).
3. **SynAxes-only client filter** — Pros: no hub change. Cons: context packs and
   other consumers stay ungated; wrong system-of-record.

## Decision

Adopt option 2.

- Default **off** (`admissibility.enabled: false`).
- Gate sits after `sort_candidates`, before `build_context_pack`.
- Policy rejection reasons use `rejection_axis: "admissibility"` (never conflated
  with relevance).
- Uncertain→exclude applies on Store sources when configured.
- Optional `persist_closure` writes `closure.v1` with
  `symbolic_constraints.forbidden_source_ids` + faithfulness fields.
- SynAxes import respects the same policy when enabled (explicit matches +
  forbidden ids from Store closures); does not apply uncertain→exclude to sparse
  client metadata.

## Consequences

- Positive: Note 87 production path exists; Latent SEEDS exclusion instrument
  plugs into Synesyn without renaming Open Closure into SynAxes.
- Trade-offs: operators must enable and tune policy; sources need trustworthy
  `produced_by` / `source_type` / authorship tags.
- Follow-ups: document policy examples for facilitators; optional deeper Open
  Closure `audit()` when packaging allows; keep Closure Map A–D tags orthogonal
  to admissibility.
