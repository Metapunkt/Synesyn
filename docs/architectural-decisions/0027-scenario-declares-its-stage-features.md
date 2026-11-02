# 0027 — A scenario declares the stage features it wants

- **Status:** Accepted
- **Date:** 2026-09-19
- **Area:** scensyn

## Context

Story Catalyst's *Stochastic Dreams* is a performance installation: it runs largely
unattended, driven by a physical pendulum, and must never look dead. Building it added
three things to Story Stage — a tiered lull protocol that escalates through slideshow,
breathing arcs, murmurs and a replay of the opening; a background slideshow fed by
vis_story renders; and a per-scenario backdrop folder of animation frames.

Only the *content* of those features was scoped to the scenario. The machinery ran for
every Story Catalyst session, and the older *Ireti Okan* scenario broke as a result:

- Its declared `default_background` was applied correctly and then overwritten two
  lines later, because the new backdrop resolver fell through to a black placeholder
  image when a scenario had no frame folder. The image loaded successfully, so nothing
  reported a failure — the stage was simply black for the rest of the session.
- The slideshow was enabled unconditionally, leaving a permanently empty image queue
  standing in for the backdrop.
- The lull escalation ran with hardcoded defaults, so a facilitator pausing to let a
  room think got breathing arcs at 45 seconds and the Narrator's welcome replayed at
  180 seconds.

A fourth defect had the same shape at the session level: the human's chosen character
lived in a `Global` field that nothing cleared, so a character chosen in one scenario
was carried into the next — announced in the header, and used to attribute typed input
in the story log, crediting a line to a character from another scenario.

Two mechanisms for scoping already existed and were already used correctly by the
pendulum: named sections in the scenario `.txt`, parsed by `scenario_loader.gd`, and a
per-collection metaprompt manager. Nothing forced new behaviour to use them.

## Options considered

1. **Scenario-id checks in the stage code** — `if scenario_name.contains("stochastic_dreams")`.
   Already present in one place for the pendulum bridge. Cheap, but every new scenario
   means editing engine code, and the check is invisible to whoever authors a scenario.
2. **A capability registry in code**, mapping scenario ids to feature flags. Central and
   greppable, but a second source of truth about a scenario, kept somewhere the
   scenario's author does not look.
3. **The scenario declares its own features** — presence of a section in the scenario
   file is the opt-in. No engine change to add a scenario; the declaration sits beside
   the rest of that scenario's configuration.

## Decision

Option 3. A stage feature runs only for a scenario that declares it:

| Feature | Declared by | Default without it |
| --- | --- | --- |
| Tiered lull protocol | `[LULL_PROTOCOL]` | Off — silence stays silent |
| Background slideshow | `[VIS_STORY] enabled: true` | Off — the backdrop stands |
| Ambient audio | `[AMBIENT_SOUND] enabled: true` | Off (unchanged) |
| Auto/external input | `[PLAYER_AUTO_INPUT]` | Off (unchanged) |
| Scenario backdrop art | `sprites/<collection>/<scenario>/background/` | The scenario's `default_background` |

Presence is the opt-in, and a section may switch itself off with `enabled: false`.
Sections whose accidental activation is worse than their absence — audio and hardware —
keep requiring an explicit `enabled: true`.

Two supporting rules follow from the same principle:

- **A resolver that finds nothing returns nothing.** `resolve_scenario_default_bg()`
  returns `""` rather than a placeholder, and the caller leaves the existing background
  alone. Substituting art that happens to load is worse than declining, because it
  looks like correct behaviour.
- **A chosen character belongs to the scenario it was chosen in.**
  `Global.get_current_character()` returns `{}` once the scenario has changed, so a
  selection cannot be displayed or attributed outside its own scenario. A *session
  role* — Facilitator, Participant — is not scenario cast and survives the change.

## Consequences

- Positive: a scenario is readable as a description of what its session does, and
  adding one needs no engine change. Stochastic Dreams keeps every behaviour it
  declares; scenarios that never asked for them are unaffected.
- Positive: no line in a story log can be attributed to a character from a different
  scenario, which matters because that log is the session record.
- Negative: presence-as-opt-in is implicit. A scenario author who copies a section
  gets its behaviour without having typed `enabled: true`, and the only place that
  reads as documentation is the scenario file itself.
- Negative: one scenario-id check remains, at
  `metaprompt_manager_cultural_narrative.gd`, deciding whether to instantiate the
  pendulum bridge. It should become a declared section; it is left as the single known
  exception rather than changed alongside a bug fix.
- Follow-up: AI-driven background changes, which moved Ireti Okan between its named
  locations, are orphaned — `BackgroundController.process_ai_response()` has no
  callers. Restoring them means deciding how a scenario names its locations and how a
  change is signalled; a marker the model emits explicitly is preferable to scoring its
  prose for keywords, and that is a separate decision.
- Nothing here crosses the client↔hub seam.
