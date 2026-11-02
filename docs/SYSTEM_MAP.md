# Synesyn System and Documentation Map

This is the primary orientation document for developers, agents, reviewers, and
maintainers. It explains how the runtime, documentation, decisions, requirements,
work tracking, and verification system fit together. It routes readers to the
source of truth rather than repeating full specifications.

## Read this first

Synesyn has two runtime sides:

- `synesyn_client/` is the Godot 4 client and application workspace.
- `services/synesyn_hub/` is the Python/FastAPI hub and system-of-record service.

Godot modules remain clients. Canonical artifacts, events, jobs, memory records,
and shared state cross the hub API. Optional services such as Ollama and ComfyUI
sit behind configured providers or hub-managed jobs.

Before changing a subsystem, read its normative contract, relevant architectural
decisions, current work tracker, and verification instructions.

## Repository topology

```text
synesyn/
├── docs/                              Curated documentation and this map
│   ├── product-requirements/          Product intent and measurable outcomes
│   ├── concepts/                      Conceptual instruments (e.g. Closure Map)
│   ├── architectural-decisions/       Append-only rationale
│   ├── developer-guide/               Current contributor instructions
│   ├── user-guide/                    User and facilitator workflows
│   ├── implementation_docs/           Normative contracts
│   └── technical-review/              Reviewer packs and executable run specs
├── implementation_tracking/           Work trackers and frozen history (not docs)
├── synesyn_client/                    Godot project, ScenSyn, and addons
├── services/synesyn_hub/              Python hub
├── utilities/                         Developer utilities
│   ├── harness/                       Harness runners and assertion support
│   ├── checks/                        Policy checkers
│   └── docs/                          Documentation site toolchain
├── .cursor/rules/                     Scoped agent guardrails
└── AGENTS.md                          Agent operating instructions
```

## Runtime relationships

```text
User
  │
  ├── ScenSyn / ReadyMade / story-log player / SynTree / SynAxes / SynPunkt / Metapunkt
  │                      Godot client surfaces; ScenSyn and the player share Story Stage
  │
  └── HubSubstrateClient
          │
          ├── HTTP/WebSocket transport
          └── Synesyn Hub
                  ├── artifacts, events, relations, and provenance
                  ├── jobs and provider orchestration
                  ├── STFX Store and Memory
                  └── continuity and shared-session state
```

The client/hub boundary is the main coherence seam. Changes to payloads, IDs,
provenance, continuity, or storage require contract review on both sides.

## Documentation ownership

Each documentation layer owns one question.

### Product requirements: who, why, and what outcome

Location: `product-requirements/`

PRDs define the user problem, scope, outcome, journey, requirements, success
measures, and acceptance links. They do not restate APIs, schemas, implementation
tasks, or operating manuals.

### Concepts: conceptual instruments

Location: `concepts/`

Stable descriptions of conceptual tools that orient product language (for example
the Closure Map). They are not runtime contracts; ADRs and PRDs bind them to
implementation when needed.

### Architectural decisions: why this design was chosen

Location: `architectural-decisions/`

ADRs are append-only history for choices with real alternatives and consequences.
They explain rationale. They do not replace current developer instructions or
normative contracts.

### Normative technical contracts: what the system must do

Location: `implementation_docs/`

These documents own platform architecture, API behavior, data models, UX
invariants, integration contracts, continuity, and deployment requirements. They
hold obligations only: plans and work records live outside `docs/` in
`implementation_tracking/` (ADR 0025), so that everything under `docs/` can be
read as an account of the system rather than of the project.

### Developer guide: how to work with the current system

Location: `developer-guide/`

The developer guide gives current setup, code navigation, policy, and operating
instructions. It stays concise and links to contracts and ADRs for detail and
rationale.

### User guide: how to use the product

Location: `user-guide/`

User and facilitator workflows belong here. User guides may explain concepts but
must not become engineering specifications.

### Work tracking and implementation history

Location: `implementation_tracking/`, outside `docs/` and excluded from the
documentation site.

- `active/` contains living per-component checklists.
- `completed/` contains frozen history, including withdrawn directions.
- Nothing there is authoritative. Where a tracker and a contract disagree, the
  contract wins and the tracker is out of date.
- A finished plan must be moved to `completed/`, not left ticked in `active/`.

### Verification and review

Locations:

- `technical-review/run_specs/` contains executable JSON behavior specs.
- `technical-review/` contains reviewer guidance and pilot checks.
- `utilities/harness/` contains harness runners and assertion support.
- `utilities/checks/` contains policy checks such as line-limit enforcement.

## Source-of-truth and precedence rules

When documents overlap, use this order:

1. Product intent and success conditions: approved PRD.
2. Runtime behavior, API, schema, and UX invariants: normative technical contract.
3. Current contributor procedure: developer guide and executable tooling.
4. Architectural rationale: latest applicable ADR.
5. Active delivery status: component to-do list.
6. Historical explanation: completed plans and review archives.

An ADR does not override current runtime behavior by itself. A decision that
changes behavior must update the normative contract and current developer guide.
If an accepted ADR is reversed, create a superseding ADR.

For line limits, `developer-guide/architecture.md` and
`utilities/checks/check_line_limits.py` are authoritative. Workspace rules must mirror them.

## Change workflow

Use the smallest set of documents required by the change:

```text
User-facing capability:
PRD → executable acceptance spec → implementation

API, schema, UX contract, or platform invariant:
normative contract → implementation → developer guide summary

Architectural choice with alternatives:
ADR → affected contract/guide updates → implementation

Routine implementation:
active to-do item → code → verification
```

Do not create an ADR for naming or formatting. Do not create a PRD for an internal
refactor without a changed user outcome. Do not copy requirements into task lists.

## Verification spine

Commands run from the repository root unless stated. After changing:

- Hub Python: `python -m pytest tests/` from `services/synesyn_hub/`, with
  `requirements-dev.txt` installed (ADR 0002). 94 tests, all expected to pass.
- ScenSyn runtime, session types, collections, harness, or scenario content: run
  the self-validating smoke and multi-turn JSON specs, for example
  `python utilities/harness/test_harness.py --spec docs/technical-review/run_specs/scensyn_workshop_catalyst_smoke.json`.
- GDScript or hub application Python:
  `python utilities/checks/check_line_limits.py --check-baseline`.
- Addon autoload access: `python utilities/checks/check_addon_autoloads.py`.
- Story Stage (`synesyn_client/addons/story_stage/`):
  `python utilities/checks/check_story_stage_boundary.py`, then
  `python utilities/checks/story_stage_dropin_test.py`, and the
  `scensyn_story_stage_dump_logs.json` and `playback_smoke.json` specs (ADR 0029).
  The drop-in contract and intended architecture are
  [`docs/developer-guide/story-stage-functional-specification.md`](developer-guide/story-stage-functional-specification.md).
- Documentation: `mkdocs build --strict`, which fails on a broken cross-reference
  or a document missing from the navigation.
- Godot code: use a pinned 4.7.x executable, located via `--godot`,
  `SYNESYN_GODOT_PATH`, or `devagent_config.json` beside the run specs. Do not
  rely on a bare `godot` from `PATH`, which may be a different major version.
- Architecture or contracts: check whether an ADR, PRD, or guide now requires a
  link or current-state update.

## Fast onboarding paths

### New developer or coding agent

1. Read this file.
2. Read `developer-guide/architecture.md` and `developer-guide/code-map.md`.
3. Read the owning normative contract from
   `implementation_docs/README.md`.
4. Check `architectural-decisions/README.md`.
5. Check the owning active to-do list.
6. Run the relevant verification before and after changes.

### Product or UX work

1. Read the relevant PRD.
2. Read `implementation_docs/Human_Agency_UX_Contract.md`.
3. Read the user journey or facilitator guide.
4. Link acceptance criteria to executable specs where possible.

### External review

Start with this system map, then `developer-guide/local-dev.md` to get a running
system and `technical-review/run_specs/README.md` to run the executable
verification. Use this map when a review question crosses product, architecture,
or implementation boundaries.

## Anti-pollution rules

- Extend an existing source of truth before creating another document with the
  same responsibility.
- Link to detail; do not paste contracts, schemas, manuals, or task lists into
  summary documents.
- Keep `docs/README.md` and subsection READMEs as routers.
- Keep PRDs short and outcome-focused.
- Keep ADRs append-only.
- Keep active tasks separate from completed history.
- Do not update generated HTML mirrors as if they were canonical Markdown.
- Do not copy code or docs from archived trees into the live project without
  confirming that they match current contracts.

## Conceptual background outside Synesyn

The wider StochasticDreams workspace contains research and conceptual material,
including `Metapunkt_artVenture/` and `development_notes/`. These sources inform
the project but do not override Synesyn product requirements or technical
contracts.
