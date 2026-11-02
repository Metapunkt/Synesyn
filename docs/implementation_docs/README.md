# Implementation documents

This directory holds Synesyn's **normative technical contracts**: what the system
must do, and where its boundaries lie. Read [`docs/SYSTEM_MAP.md`](../SYSTEM_MAP.md)
first for the documentation hierarchy and precedence rules.

It deliberately holds nothing else. Delivery plans, work trackers and frozen
engineering history live in
[`implementation_tracking/`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/README.md)
outside `docs/`, because they are working material rather than documentation:
useful to whoever is building the thing, misleading to someone trying to
understand it. ADR 0025 records that split.

## Normative contract spine

These documents define current required behaviour or system boundaries:

1. [`Synesyn_Platform_Technical_Architecture.md`](Synesyn_Platform_Technical_Architecture.md)
2. [`Synesyn_Hub_API_Spec.md`](Synesyn_Hub_API_Spec.md)
3. [`LatentSubstrate_Data_Model.md`](LatentSubstrate_Data_Model.md)
4. [`Human_Agency_UX_Contract.md`](Human_Agency_UX_Contract.md)
5. [`Local_Deployment_Runbook.md`](Local_Deployment_Runbook.md)
6. [`ScenSyn_Scenario_Continuity_Contract.md`](ScenSyn_Scenario_Continuity_Contract.md)
7. [`STFX_Memory_Capability_Spec.md`](STFX_Memory_Capability_Spec.md)

## Subsystem contracts and integration specifications

- [`Metapunkt_Hub_Integration.md`](Metapunkt_Hub_Integration.md)
- [`Metapunkt_Synterfaces_and_Bindings.md`](Metapunkt_Synterfaces_and_Bindings.md)
- [`SynTree_as_a_Synesyn_runtime_module.md`](SynTree_as_a_Synesyn_runtime_module.md)
- [`SynAxes_Embeddings_Pipeline.md`](SynAxes_Embeddings_Pipeline.md)

These add subsystem detail. Where they overlap the spine, the platform
architecture, Hub API, data model and UX contract retain ownership of their
respective concerns.

## Maintenance rules

- Update the owning contract before changing required system behaviour.
- Create an ADR for a design choice with real alternatives and consequences.
- Keep product intent in [`../product-requirements/`](../product-requirements/README.md).
- Keep implementation checkboxes and delivery sequencing in
  `implementation_tracking/active/`, never here.
- A document in this directory should read as an obligation. If it reads as a plan
  or a diary, it belongs in `implementation_tracking/` instead.
