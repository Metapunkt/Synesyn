# Synesyn Product Requirements

Product requirement documents define who a capability serves, which problem it
addresses, what outcome it must produce, its scope, and how success is observed.
Read [`../SYSTEM_MAP.md`](../SYSTEM_MAP.md) for the full documentation hierarchy.

PRDs are a thin intent layer. They link to user guides, technical contracts,
architectural decisions, implementation trackers, and executable specs instead of
copying them.

## Product flows

| ID | Product flow | Status | Last reviewed |
|---|---|---|---|
| [PRD-SCENSYN-STORY-SESSION](PRD-SCENSYN-STORY-SESSION.md) | ScenSyn story session | Review | 2026-07-10 |
| [PRD-SCENSYN-WORKSHOP-CATALYST](PRD-SCENSYN-WORKSHOP-CATALYST.md) | Workshop Catalyst facilitation | Review | 2026-07-10 |
| [PRD-READYMADE-EDIT-SESSION](PRD-READYMADE-EDIT-SESSION.md) | ReadyMade edit session | Draft / implementing | 2026-07-10 |
| [PRD-SYNTREE-CONTEXT-GRAPH](PRD-SYNTREE-CONTEXT-GRAPH.md) | SynTree Context Graph | Implementing | 2026-07-10 |
| [PRD-SYNAXES-CLOSURE-MAP-ORIENTATION](PRD-SYNAXES-CLOSURE-MAP-ORIENTATION.md) | SynAxes Closure Map orientation tags and coverage | Implementing | 2026-08-07 |
| [PRD-SYNAXES-NAVIGABLE-DEFAULT-PATH](PRD-SYNAXES-NAVIGABLE-DEFAULT-PATH.md) | SynAxes navigable default path (latent reality → holds) | Draft | 2026-08-07 |
| [PRD-WORKSHOP-CATALYST-CLOSURE-AUDIT](PRD-WORKSHOP-CATALYST-CLOSURE-AUDIT.md) | Workshop Catalyst Closure Audit stage | Draft | 2026-09-05 |

## Lifecycle

- **Draft:** intent is being consolidated; unresolved gaps are allowed.
- **Review:** evidence is consolidated and ready for product review.
- **Approved:** scope and success conditions are accepted.
- **Implementing:** engineering is active against the approved intent.
- **Shipped:** acceptance conditions are met for the stated version.
- **Parked:** work is explicitly deferred.
- **Superseded:** a successor PRD owns the product intent.

PRDs remain living documents until shipped. After shipping, change product intent
through a new version or successor rather than silently rewriting the original
scope.

## Rules

- Create PRDs for substantial user-facing capabilities, not internal refactors.
- Keep each PRD short. Link detailed workflows and contracts.
- Do not duplicate API payloads, schemas, facilitator instructions, or task lists.
- Give requirements stable IDs so run specs and plans can reference them.
- Link an ADR only when an architectural choice affects the product flow.
- Link executable acceptance where the harness can observe the behavior.
- Record manual acceptance explicitly when automation cannot reproduce the flow.

Use [`_template.md`](_template.md) for new PRDs.
