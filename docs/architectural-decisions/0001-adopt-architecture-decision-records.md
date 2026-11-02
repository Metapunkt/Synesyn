# 0001 — Adopt Architecture Decision Records

- **Status:** Accepted
- **Date:** 2026-07-09
- **Area:** tooling

> Amendment note (2026-09-18): `Technical_Implementation_Documents/`, mentioned
> below as context, now lives at `docs/implementation_docs/`.

## Context
Synesyn has rich implementation docs (`Technical_Implementation_Documents/`, developer-guide) but no durable, append-only record of *why* decisions were made. Rationale lived in chats and commit messages and evaporated between sessions and between agents. The `synesyn-architecture-invariants` rule already assumes a "record the decision" practice.

## Options considered
1. **Keep decisions implicit** in implementation docs / commit messages — zero overhead, but rationale stays scattered and un-discoverable; priors keep evaporating.
2. **Numbered ADRs** under `synesyn/docs/architectural-decisions/`, created via the `record-decision` skill — small per-decision cost, durable and greppable.

## Decision
Adopt ADRs. Files are `NNNN-<slug>.md`, indexed in `README.md`, created via the `record-decision` skill, and **append-only** — a reversal is a new ADR that marks the old one `Superseded by NNNN` rather than editing it away.

## Consequences
- Positive: durable rationale; agents/contributors can consult prior decisions before re-litigating them.
- Negative / trade-offs: light overhead per decision; discipline required to actually record.
- Follow-ups: the `synesyn-reviewer` and `record-decision` steps should flag when a new decision invalidates an existing rule so the rule gets updated too.
