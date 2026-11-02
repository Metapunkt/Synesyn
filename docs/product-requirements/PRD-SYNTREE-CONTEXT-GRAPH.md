---
id: PRD-SYNTREE-CONTEXT-GRAPH
title: SynTree Context Graph
status: implementing
version: "0.1"
owner: SynTree product owner
last_reviewed: 2026-07-10
primary_users: [knowledge worker, researcher, prompt author]
supersedes: null
---

# SynTree Context Graph

## Problem and outcome

People grounding AI work in multiple sources need more control than a file list or
hierarchy provides. They need to express how material relates, inspect what the AI
will receive, understand why particular context was used, and revise that context
without surrendering authority to automatic retrieval.

Context Graph should turn source relationships into an inspectable
context-engineering workspace. A user should be able to structure evidence and
instructions, preview the resulting context package, run it, inspect what was
used, and improve the graph with versioned human approval.

## Users and jobs

- **Knowledge worker:** organize related and conflicting source material so an AI
  response is grounded in the intended evidence.
- **Researcher:** preserve provenance and distinguish source claims from summaries
  and AI inferences.
- **Prompt author:** bind reusable context selections to prompt chains and inspect
  their effect before committing a new version.

## Success measures

- Users can express relationships that cannot be represented by List or Hierarchy
  alone.
- Before submission, users can inspect included context, inclusion reasons,
  omissions, ordering, and estimated budget.
- After a response, users can trace the context package and source paths used.
- AI-proposed graph changes never alter the committed graph without explicit
  review and approval.
- Published context graphs remain reusable, versioned, and auditable through the
  Hub.
- Existing sources, stacks, List, Hierarchy, chat, and prompt chains continue to
  function during migration.

## Scope

### In scope

- Context Graph as a permanent peer to List and Hierarchy.
- Typed and annotated source/content relationships.
- Context preview and budget controls.
- Transparent activation rules and named context sets.
- Prompt Chain references to committed context sets.
- Provenance, retrieval traces, graph diagnostics, and version comparison.
- Human-reviewed AI proposals for graph improvement.
- Focus, filtering, accessibility, and practical large-graph behavior.
- Reusable graph interaction foundations for other Synesyn surfaces without
  merging their product semantics.

### Out of scope

- Replacing List or Hierarchy or hiding Context Graph for simple sources.
- Turning Context Graph into the Prompt Chain graph editor.
- Automatically committing model-generated relationships or context rules.
- Claiming model attention or causal influence from prompt inclusion alone.
- Storing Workshop Catalyst maps as `ui.context_graph`.
- General-purpose workflow automation unrelated to controlling AI context.

## Critical journey

1. The user selects or creates content sources and opens Context Graph.
2. They arrange material and define meaningful relationships, annotations, and
   provenance.
3. They select or create a named context set and inspect its activation rules.
4. SynTree previews the exact context package, inclusion reasons, omissions, and
   estimated budget.
5. The user edits the proposal and explicitly commits a version.
6. They apply the context directly or through a Prompt Chain and run a request.
7. SynTree highlights what was included, cited, omitted, or heuristically unused.
8. The user revises or forks the graph, preserving the prior version and trace.

## Requirements

- **REQ-CG-001:** Context Graph must remain directly available as a peer to List
  and Hierarchy without complexity-based automatic switching.
- **REQ-CG-002:** Users must be able to create, edit, inspect, and remove typed,
  directed relationships with human-readable meaning.
- **REQ-CG-003:** Every committed node and relationship must support provenance or
  clearly state that provenance is unknown.
- **REQ-CG-004:** Preview must show the context package that will be submitted,
  including reasons, omissions, ordering, and estimated budget.
- **REQ-CG-005:** Pinned or locked content must never be silently omitted.
- **REQ-CG-006:** Named context sets and activation rules must be inspectable,
  reusable, scoped, and versioned.
- **REQ-CG-007:** Prompt Chains may reference context sets without merging the two
  editors or silently rebinding committed versions.
- **REQ-CG-008:** A completed run must retain an auditable reference to the graph,
  context set, compilation result, model/provider, and resulting output.
- **REQ-CG-009:** AI-generated graph changes must remain proposals until accepted,
  edited, or rejected by a user.
- **REQ-CG-010:** Existing graph/source data and `ui.context_graph` v0 artifacts
  must remain readable through the migration period.
- **REQ-CG-011:** Cross-surface context use must be explicit and must not create
  accidental conversation or source-context bleed.
- **REQ-CG-012:** Shared graph infrastructure must permit Workshop Catalyst to
  reuse graph mechanics without depending on SynTree-specific semantics.
- **REQ-CG-013:** Named visual layouts must remain user-local preferences
  separate from semantic graph artifacts and versions.
- **REQ-CG-014:** On the deterministic 1,000-node/999-edge headless fixture,
  filtering should complete within 300 ms, context compilation within 500 ms,
  and diagnostics within 1,000 ms on the supported development baseline. These
  are regression ceilings, not claims about every device. A 240-node rendered
  canvas must open incrementally across multiple frames, add no more than 20
  nodes per measured frame in the acceptance fixture, and finish within 3,000
  ms on the supported development baseline.

## Acceptance

Automated coverage to add:

- Graph model and serialization fixtures for legacy and current schemas.
- Typed relationship, validation, migration, compilation, rule-precedence, diff,
  provenance, and artifact round-trip tests.
- Conformance fixtures proving preview and submitted context are identical.
- Shared graph-workspace tests exercised through both Context Graph and Workshop
  Thinking Map adapters when the latter is implemented.
- A deterministic 1,000-node fixture measuring pure filtering, compilation, and
  diagnostics against REQ-CG-014, plus semantic-diff coverage proving layout
  state does not alter semantic versions.
- A 240-node rendered GraphEdit fixture proving bounded incremental canvas
  construction, multi-frame responsiveness, and the rendered REQ-CG-014 ceiling.

Manual coverage remains required for:

- List / Hierarchy / Context Graph switching and discoverability.
- Relationship drawing and inspection.
- Theme, keyboard, accessibility, and large-graph interaction.
- Context preview comprehension and provenance navigation.
- Prompt Chain binding and post-run retrieval overlays.

Acceptance cases belong in executable harness specs under
[`technical-review/run_specs/`](../technical-review/run_specs/README.md) as
harness support for these surfaces becomes available.

## Constraints and dependencies

- [Human Agency UX Contract](../implementation_docs/Human_Agency_UX_Contract.md)
- [LatentSubstrate Data Model](../implementation_docs/LatentSubstrate_Data_Model.md)
- [Synesyn Hub API Specification](../implementation_docs/Synesyn_Hub_API_Spec.md)
- [SynTree implementation tracker](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/active/03_SynTree.md)
- [ADR 0008: Shared Graph Workspace with product-owned adapters](../architectural-decisions/0008-shared-graph-workspace-product-adapters.md)

## Open questions and risks

- Relationship vocabulary must remain expressive without becoming ungovernable.
- Token estimates may differ from provider tokenization and must be labelled.
- Graph scale and live diagnostics can degrade editor responsiveness.
- Provenance and execution traces may contain sensitive prompt context.
- Prematurely generalizing the shared graph layer could make both products harder
  to evolve; shared code must remain domain-neutral.

## Evidence map

- Normative UX:
  [`Human_Agency_UX_Contract.md`](../implementation_docs/Human_Agency_UX_Contract.md)
- Normative artifact model:
  [`LatentSubstrate_Data_Model.md`](../implementation_docs/LatentSubstrate_Data_Model.md)
- Architectural decision:
  [`0008-shared-graph-workspace-product-adapters.md`](../architectural-decisions/0008-shared-graph-workspace-product-adapters.md)
- Implementation tracker:
  [`03_SynTree.md`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/active/03_SynTree.md)
- Review criteria:
  [`technical-review/run_specs/README.md`](../technical-review/run_specs/README.md)
