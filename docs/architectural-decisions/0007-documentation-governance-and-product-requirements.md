# 0007 — Documentation governance and product requirements

- **Status:** Accepted
- **Date:** 2026-07-10
- **Area:** documentation / product governance

> Amendment note (2026-09-18): the root-level `Technical_Implementation_Documents/`
> named below now lives at `docs/implementation_docs/`. Only the location and name
> changed.
>
> Amendment note (2026-09-19, ADR 0025): that directory no longer owns all three
> kinds of writing. It keeps normative contracts; active work tracking and frozen
> engineering history moved to `implementation_tracking/`, outside `docs/`. The
> governance principle below — one owner per kind of document — is unchanged and is
> in fact what motivated the split. Read the ownership table with
> `implementation_tracking/` substituted wherever it assigns plans or history to
> the implementation-documents directory.

## Context

Synesyn documentation had grown across curated guides, technical implementation
documents, review packs, application-local plans, agent rules, and completed
task records. Several documents described the same subsystem without stating
which one owned product intent, current behavior, rationale, operating guidance,
or delivery status. Architectural decisions were also stored in a generically
named `docs/decisions/` directory, and no concise PRD layer connected user
outcomes to contracts and executable acceptance.

## Options considered

1. **Keep the existing distributed structure** and rely on contributors to infer
   authority from context. This avoids migration work but preserves ambiguity and
   encourages duplicate summaries to become competing specifications.
2. **Consolidate all documentation into one hierarchy.** This produces a simple
   tree but mixes audiences, disrupts useful subsystem-local material, and creates
   a large migration with little product value.
3. **Define ownership by document type, add one system map, and introduce thin
   flow-level PRDs.** Existing sources stay where they serve their audiences, but
   each layer owns one question and links to the others.

## Decision

Adopt option 3.

- `docs/SYSTEM_MAP.md` is the primary orientation and documentation-governance
  map.
- `docs/product-requirements/` owns users, problems, scope, outcomes,
  requirements, and acceptance links.
- `docs/architectural-decisions/` owns append-only design rationale and replaces
  the former `docs/decisions/` path.
- `Technical_Implementation_Documents/` owns normative contracts, active
  implementation tracking, and clearly marked engineering history.
- `docs/developer-guide/` owns current contributor procedures and code
  navigation.
- `docs/user-guide/` owns operational product guidance.
- `docs/technical-review/` owns reviewer workflows and executable run specs.

PRDs remain short and link to manuals, contracts, ADRs, implementation trackers,
and executable specifications. They do not duplicate those sources.

## Consequences

- Positive: new contributors and agents have one entry point and explicit
  source-of-truth rules.
- Positive: product intent can be reviewed independently of implementation detail
  while remaining connected to executable acceptance.
- Positive: legacy documents can remain useful without silently competing for
  authority.
- Trade-off: indexes and links must be maintained when a source of truth moves.
- Trade-off: current legacy overlaps are tolerated only when each document's role
  is stated or clear from the system map.
- Follow-up: create a new ADR only if this ownership model changes. Routine index
  maintenance does not require another decision record.
