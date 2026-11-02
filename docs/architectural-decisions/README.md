# Synesyn Architectural Decision Records (ADRs)

This directory is the append-only record of non-trivial architecture and design
decisions. ADRs explain why the current system took a particular shape. Current
operating guidance belongs in the developer guide, while normative behavior and
interfaces belong in `../implementation_docs/`.

New entries are created via the `record-decision` skill. To reverse a decision,
add a new ADR and mark the old one `Superseded by NNNN`.

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](0001-adopt-architecture-decision-records.md) | Adopt Architecture Decision Records | Accepted | 2026-07-09 |
| [0002](0002-separate-hub-dev-dependencies.md) | Separate hub dev/test dependencies into requirements-dev.txt | Accepted | 2026-07-09 |
| [0003](0003-agent-infrastructure-scoping.md) | Scoping of agent infrastructure (rules, skills, sub-agents) | Accepted | 2026-07-09 |
| [0004](0004-line-limit-remediation-strategy.md) | Line-limit hard-violation remediation strategy | Accepted | 2026-07-09 |
| [0005](0005-hub-client-transport-facade-split.md) | Split HubSubstrateClient into transport base + endpoint facade | Accepted | 2026-07-09 |
| [0006](0006-self-validating-json-harness-specs.md) | Self-validating JSON harness specs | Accepted | 2026-07-09 |
| [0007](0007-documentation-governance-and-product-requirements.md) | Documentation governance and product requirements | Accepted | 2026-07-10 |
| [0008](0008-shared-graph-workspace-product-adapters.md) | Shared Graph Workspace with product-owned adapters | Accepted | 2026-07-10 |
| [0009](0009-workshop-catalyst-session-synthesis-and-workspaces.md) | Workshop Catalyst session model, synthesis, and workspaces | Accepted | 2026-07-10 |
| [0010](0010-shared-spatial-ui-and-visual-system.md) | Shared spatial UI and semantic visual system | Superseded / Withdrawn | 2026-07-14 |
| [0011](0011-workshop-spatial-cube-topology.md) | Workshop spatial slice uses a cube topology | Superseded / Withdrawn | 2026-07-14 |
| [0012](0012-workshop-catalyst-facilitation-method.md) | Workshop Catalyst facilitation method: four lenses, six cross-checks | Accepted | 2026-08-01 |
| [0013](0013-workshop-catalyst-multi-instance-identity.md) | Workshop Catalyst multi-instance identity and facilitator claim | Accepted | 2026-08-05 |
| [0014](0014-documents-synesyn-user-storage-root.md) | Documents/Synesyn as the user-visible storage root | Accepted | 2026-08-06 |
| [0015](0015-synaxes-v2-closure-map-orientation.md) | SynAxes V2: Closure Map orientation (Distal / Deep / Proxistance) | Accepted | 2026-08-07 |
| [0016](0016-open-closure-store-admissibility-gate.md) | Open Closure admissibility gate in STFX Store (formerly Artrhythmetic Store) (+ SynAxes import) | Accepted (amended 2026-11-01) | 2026-08-07 |
| [0017](0017-synesyn-core-shared-library-addon.md) | Shared library addon `synesyn_core` (drop-in boundary) | Accepted (amended 2026-09-06) | 2026-08-07 |
| [0018](0018-hub-deployment-path-contract.md) | Hub deployment path contract (one location, one resolver) | Accepted | 2026-09-05 |
| [0019](0019-thinking-map-human-authorship.md) | Thinking Map human authorship: propose vs commit | Accepted | 2026-09-05 |
| [0020](0020-thinking-map-closure-map-boundary.md) | Thinking Map and Closure Map boundary: the audit is a stage, not an ontology | Accepted (amended 2026-09-06) | 2026-09-05 |
| [0021](0021-hub-bundle-composition-and-process-lifecycle.md) | Hub bundle composition (CPU-only, bundled weights) and process lifecycle | Accepted | 2026-09-13 |
| [0022](0022-scenario-sharing-bundle-format.md) | Scenario sharing bundles, and library parity for Workshop Catalyst | Accepted | 2026-09-17 |
| [0023](0023-client-directory-rename-and-repository-root.md) | Client directory renamed to `synesyn_client`, and `synesyn/` is the repository root | Accepted | 2026-09-18 |
| [0024](0024-readymade-found-concepts-vocabulary.md) | ReadyMade's Found Concepts vocabulary, and why its source texts are not distributed | Accepted | 2026-09-18 |
| [0025](0025-documentation-publication-boundary.md) | `docs/` publishes explanation; work tracking moves to `implementation_tracking/` | Accepted | 2026-09-19 |
| [0026](0026-closure-artifact-type-split.md) | Session captures move to `ui.workshop_closure`; `ui.closure` means a SynAxes slice | Accepted | 2026-09-19 |
| [0027](0027-scenario-declares-its-stage-features.md) | A scenario declares the stage features it wants; a chosen character belongs to its scenario | Accepted | 2026-09-19 |
| [0028](0028-internal-calls-get-a-low-reasoning-budget.md) | Internal calls get a low reasoning budget; which model answers stays the participant's choice | Accepted | 2026-09-20 |
| [0029](0029-story-stage-is-a-host-driven-component.md) | Story Stage is a host-driven component, extracted in three phases | Accepted | 2026-09-24 |
| [0030](0030-story-stage-motion-and-imagery-layers.md) | Story Stage motion and imagery are coordinated opt-in layers | Proposed | 2026-09-24 |
| [0031](0031-spoken-line-carries-its-resolved-voice.md) | A spoken line carries the voice it was resolved with | Accepted | 2026-10-31 |
| [0032](0032-stfx-naming-for-kernel-memory-and-store.md) | Rename `artrhythmetic_*` kernel, memory, and store to `stfx` | Accepted | 2026-11-01 |
