# Developing Synesyn

For contributors and integrators. If you are here to run a session rather than
change the code, you want the [user guide](../user-guide/README.md).

Synesyn is a Godot 4.7 client plus an optional Python hub. The client works
without the hub; the hub is the system of record when present.

## The path to a first change

Follow these in order. Each step assumes the previous one worked.

1. **Set up.** [`local-dev.md`](local-dev.md) — prerequisites, the required LimboAI
   install, and running the hub and client. Do not skip the LimboAI step; the
   project will not open without it.
2. **Learn the vocabulary.** [Glossary](../concepts/glossary.md) — *artifact*,
   *closure*, *session type* and *specialist* all have specific meanings, and the
   code assumes you know them.
3. **Get oriented.** [`architecture.md`](architecture.md) for how the pieces fit,
   then [`code-map.md`](code-map.md) for where to look for a given concern.
4. **Understand the boundaries.** [`hub-api.md`](hub-api.md) and
   [`artifacts-and-schemas.md`](artifacts-and-schemas.md) describe the contract
   between client and hub, which is where most integration mistakes happen.
5. **Make the change**, observing the house rules in
   [`AGENTS.md`](https://github.com/Metapunkt/Synesyn/blob/main/AGENTS.md):
   GDScript conventions, the 900/1200-line script limits, and the addon boundary.
6. **Verify it.** Behaviour is checked by executable specs rather than prose
   (ADR 0006):

   ```bash
   python utilities/harness/test_harness.py \
     --spec docs/technical-review/run_specs/scensyn_workshop_catalyst_smoke.json
   ```

   Specs live in
   [`../technical-review/run_specs/`](../technical-review/run_specs/README.md).
   For hub changes, run `python -m pytest tests/` from `services/synesyn_hub/`.
7. **Open a pull request**, following
   [`CONTRIBUTING.md`](https://github.com/Metapunkt/Synesyn/blob/main/CONTRIBUTING.md),
   which lists the checks expected for each kind of change.

## Working with agents

This repository is built with AI coding agents as a normal part of the workflow,
and that is documented rather than hidden:

- [`ai-orchestration-and-godot-dev-agent.md`](ai-orchestration-and-godot-dev-agent.md)
  — how orchestration and capability packs work.
- [`devagent-cli-for-agents.md`](devagent-cli-for-agents.md) — driving a headless
  Godot client from a script or an agent, without the editor.
- [`workshop-scenario-authoring.md`](workshop-scenario-authoring.md) — authoring
  scenario content, which is text rather than code.

## Sources of truth

This guide describes current practice, and deliberately does not restate contracts
or rationale. When they conflict, the owning source wins.

| For | Read |
| --- | --- |
| What the system must do | [Implementation contracts](../implementation_docs/README.md) |
| Story Stage as a replaceable addon | [Story Stage functional specification](story-stage-functional-specification.md) |
| Why it is built this way | [Architectural decisions](../architectural-decisions/README.md) |
| What problem a feature solves | [Product requirements](../product-requirements/README.md) |
| Repository layout and which doc owns what | [`../SYSTEM_MAP.md`](../SYSTEM_MAP.md) |
| What is being worked on now | [`implementation_tracking/active/`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/active/README.md) — trackers, not authoritative |

## Core contracts

- [Platform architecture](../implementation_docs/Synesyn_Platform_Technical_Architecture.md)
- [Hub API](../implementation_docs/Synesyn_Hub_API_Spec.md)
- [LatentSubstrate data model](../implementation_docs/LatentSubstrate_Data_Model.md)
- [Human Agency UX contract](../implementation_docs/Human_Agency_UX_Contract.md)
- [ScenSyn continuity contract](../implementation_docs/ScenSyn_Scenario_Continuity_Contract.md)
- [Local deployment runbook](../implementation_docs/Local_Deployment_Runbook.md)
