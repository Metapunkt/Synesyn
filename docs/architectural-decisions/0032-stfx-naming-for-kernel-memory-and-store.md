# 0032 — Rename `artrhythmetic_*` kernel, memory, and store to `stfx`

- **Status:** Accepted
- **Date:** 2026-11-01
- **Area:** hub | client | contract
- **Amends:** ADR 0002, ADR 0005, ADR 0016, ADR 0026

## Context
The hub packages `artrhythmetic_core`, `artrhythmetic_memory`, and
`artrhythmetic_store`, their `/artrhythmetic-memory` and `/artrhythmetic-store`
HTTP routes, and the matching `HubSubstrateClient` methods carried the working
name *Artrhythmetic* from the earlier visual-pattern manuscript. Before public
release, three problems with that name forced a decision:

1. **Phonetic and citation collision.** *Artrhythmetic* sits one syllable away
   from Moyo Okediji's *Artrithmetic* (2026), the published visual framework it
   draws on, creating avoidable ambiguity in prose, search, and attribution.
2. **Cultural binding vs. culture-neutral kernel.** `artrhythmetic_core.kernel`
   explicitly separates Layer 1 (a culture-neutral Boolean tensor expansion and
   closure kernel) from Layer 2 (pluggable lexicons, of which `IFA_ODU` is one).
   Naming the general kernel and file-backed provenance store after the cultural
   portmanteau blurred the boundary the code itself enforces.
3. **API ergonomics.** `artrhythmetic` is a recurring spelling trap across
   routes, Python packages, GDScript facade methods, and user documentation.

## Options considered
1. **Keep `artrhythmetic_*` in code and change only prose.** Avoids code churn,
   but leaves every public HTTP endpoint, module path, and client method carrying
   the retired term into the public release.
2. **Drop the prefix (`core`, `memory`, `store`).** Too generic inside the hub
   and client, and loses the fact that `memory` and `store` derive from and
   operate with the same generative procedure as the kernel.
3. **Rename the family to `stfx` (Seed-to-Field Expansion): `stfx_core`,
   `stfx_memory`, `stfx_store`.** Names the opening generative operation the
   kernel performs (expanding a compact seed into a structured field from which
   complement pairing, selection, and provenance follow) while keeping the family
   link across kernel, symbolic memory, and canonical store.

## Decision
Adopt option 3 before public release, executed in three passes so no intermediate
state breaks the build:

- **Packages:** `app/stfx_core/`, `app/stfx_memory/`, `app/stfx_store/`.
- **HTTP mounts:** `/stfx-memory` and `/stfx-store` (with migration endpoint
  `/stfx-store/migrations/stfx-memory/export`).
- **Workspace storage directory:** `StfxStorePaths` uses `<workspace>/stfx_store`
  and `StfxMemoryStore` uses `<workspace>/stfx_memory` without legacy on-disk or
  schema fallback, giving the first public release a clean slate.
- **Contract identifiers:** `stfx_memory.continuity_context`,
  `stfx_memory.adapter_contract`, `json.stfx_*` substrate artifact types,
  `stfx.*.v1` store record schemas, and `engine: "stfx_core"` in closure
  provenance records.
- **Client facade:** `HubSubstrateClient` exposes `stfx_ingest_document`,
  `stfx_get_document`, and `stfx_store_*`.
- **Legacy removal:** temporary compatibility aliases used during the migration
  are removed in the final pass prior to release. Historical ADRs retain their
  original wording with dated amendment notes.

## Consequences
- Positive: public release ships with concise, culture-neutral identifiers
  (`stfx_core`, `stfx_memory`, `stfx_store`, `/stfx-store`, `/stfx-memory`) that
  name the actual operation while preserving the shared lineage of the three
  modules, with no legacy fallback branches in runtime code.
- Trade-off: touches hub packages, routes, tests, GDScript callers, rules, and
  documentation across the repository; pre-release local workspaces that used the
  old folder/schema names must be renamed manually or run with earlier builds.
