# Workshop Catalyst Scenario authoring

Workshop Catalyst keeps the user-facing **Scenario** term. Authored files are
optional templates; facilitators can instead create a local Scenario in the
selection flow.

## Authored template contract

Store templates in
`ScenSyn/session_types/workshop_catalyst/scenarios/`. Use:

- `[SCENARIO]` for name, objective, and setting/context;
- `[WORKSHOP_PACKET]` for the workshop context, desired outcomes, constraints,
  time horizon, relevant stakeholders/perspectives, and evidence notes;
- `[WORKSHOP_AGENDA]` for day/stage JSON;
- `[TIME_MODEL]` and `[STAGE_GUIDANCE]` when the generic defaults are
  insufficient;
- optional `[ABOUT]`, `[HOW_TO]`, and domain reference sections.

Do not add `[CHARACTERS]`, named personas, character-control instructions,
stay-in-role language, or character-specific decision ownership. Preserve useful
domain coverage under `Relevant stakeholders/perspectives` as institutional or
community functions, not simulated people.

Workshop Catalyst always uses four stable hidden Specialist Functions:
Systems & Consequences; Stakeholder & Communication; Risk & Feasibility; Options
& Innovation. Scenario context changes their subject matter, not their ids or
definitions.

## Stage contract convention

`[STAGE_GUIDANCE]` is keyed by exact stage name from `[WORKSHOP_AGENDA]`. Each
stage uses the same four-part contract, in this order:

```
--- <exact stage name> ---
Facilitator goal: what the facilitator is trying to get from the room.
AI goal: what the assistant should do for the facilitator in this stage.
Required output before advancing: what must exist before the stage ends.
Decision-forcing question: "the sentence that converts discussion into a commitment"
```

Write the required output as artifacts, not activities: a named decision with an
owner, a risk with a cost-bearer, an eliminated option. A stage whose required
output can be satisfied by discussion is not a stage contract.

Where a stage depends on a pairing of lenses, say so in the required output
rather than naming the lenses. "One effect that would be displaced rather than
removed" targets Systems × Stakeholder; "one option eliminated on feasibility
grounds" targets Options × Risk. See ADR 0012 for the six pairings.

A Scenario that omits `[STAGE_GUIDANCE]` inherits
`WorkshopScenarioContract.default_stage_guidance()`, which covers the six
default stages. Authored guidance always wins over the default, and mixing is
not supported: if a Scenario supplies `[STAGE_GUIDANCE]` at all, it must cover
every stage in its own agenda.

## User-authored local Scenarios

The scene-authored editor collects title, central question/objective, context,
desired outcomes, constraints, time horizon, relevant perspectives, and optional
evidence notes. It creates `custom_workshop_scenario`, adds the generic six-stage
agenda with its default stage contracts and a two-hour scalable time model, then
saves:

`Documents/Synesyn/scensyn/workshop_catalyst/scenario_draft_v1.json`
(via `RuntimeConfig.get_workshop_draft_path()`; see ADR 0014). Legacy
`user://scensyn/...` drafts are migrated into Documents on first load.

The file is a versioned local draft. It is neither a Hub artifact nor a
published/committed Scenario. Reopening the editor reloads and normalizes it for
explicit facilitator review.

## Compatibility and validation

The Workshop adapter normalizes old/custom Workshop files and discards legacy
character arrays and role-play lines before runtime use. It does not modify the
source file. Story Catalyst parsing and characters are unaffected.

Before merging a template:

1. Confirm no Workshop template contains `[CHARACTERS]` or role-play language.
2. Load it through `ScenarioLoader` and confirm `characters` is empty.
3. Run `test_workshop_scenario_and_map_corrections.gd`.
4. Run the Workshop smoke and hidden-synthesis multiturn harness specs.
