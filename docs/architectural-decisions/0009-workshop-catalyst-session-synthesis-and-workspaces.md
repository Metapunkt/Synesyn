# 0009 — Workshop Catalyst session model, synthesis, and workspaces

- **Status:** Accepted
- **Date:** 2026-07-10
- **Area:** ScenSyn / Workshop Catalyst
- **Partially superseded by:** ADR 0010 for the workspace-preset and responsive
  dashboard-shell presentation only. Session, synthesis, safety, and
  human-agency decisions remain active.

> Amendment note (2026-09-19): ADR 0010 was itself withdrawn on 2026-07-15, so
> the supersession above no longer transfers those presentation decisions
> anywhere. Read it as: the workspace-preset and dashboard-shell presentation
> described below is **not** current, and no replacement decision has been
> recorded. The spatial direction that displaced it was abandoned; only the
> semantic visual-profile system survived. Everything else in this ADR stands.

## Context

ScenSyn originally grouped scenarios through themes and presented visible AI
characters as the primary interaction model. Workshop Catalyst now targets
professional facilitation. Its default experience needs one coherent assistant
voice, a voice-first workspace, and progressive disclosure of a dense dashboard.
Story Catalyst must retain visible character role-play and its existing scenario
behavior.

Three choices are coupled. Product identity must move above scenarios without
conflicting with light/dark `ThemeManager`. Workshop analysis needs several
specialist perspectives without flooding the conversation. The interface needs
to support Talk, mapping, and review tasks without hiding safety controls.

## Options considered

1. Keep themes, visible workshop characters, and one fixed dashboard. This
   minimizes migration work but keeps the naming collision and does not fit the
   facilitation journey.
2. Create a separate Workshop Catalyst application and runtime. This gives full
   freedom but duplicates scenario loading, conversation, continuity, voice, and
   closure infrastructure.
3. Add product-specific conditions throughout shared ScenSyn code. This appears
   quick but spreads Workshop Catalyst semantics into Story Catalyst behavior.
4. Add a generic Session Type → Collection registry, select a runtime profile,
   and expose product-owned workspace presets. Workshop Catalyst uses hidden
   synthesis; Story Catalyst uses the visible ensemble.

## Decision

Adopt option 4.

`SessionType` is the user-facing experience category. Each Session Type owns one
or more Collections, and each Collection owns scenarios. Workshop Catalyst starts
with `decision_triage`. Story Catalyst retains `sustainability` and
`cultural_narratives`.

The runtime profile determines turn presentation:

- `visible_ensemble` preserves Story Catalyst character rotation;
- `hidden_synthesis` batches specialist contributions and publishes one
  Workshop Catalyst assistant response.

Hidden contributions remain traceable. They do not become canonical decisions
and cannot run as concurrent `ConversationManager.chat()` requests.

Specialists do not cast votes. Their retained summaries may surface concerns,
tensions, and options, but only participant/facilitator-visible voting and the
existing explicit `/vote` and `/decide` paths can establish workshop closure.

Workshop Catalyst owns the Talk, Map, Review, Full Dashboard, and Custom
workspace presets. Presets control named regions and content within a stable
dashboard hierarchy; they do not rearrange six interchangeable cards. Full
Dashboard uses a navigation rail, flexible center workspace, and insight/record
rail. Talk prioritizes the voice/conversation center, Map prioritizes the
Thinking Map, and Review moves the editable Session Record beside Compare Paths
in an intentional center review surface. Custom remembers region visibility and
rail state. Recording and consent status, errors, uncommitted-change warnings,
and End & Save remain reachable in every preset. Static structure belongs in
`.tscn` scenes.

At wide widths all three regions can remain visible. Medium widths use narrower,
independently collapsible rails. Narrow widths keep the center primary and expose
the rails as labelled, sequential drawers, avoiding a single stacked mega-column.

## Consequences

- Story Catalyst keeps its visible ensemble and current Collection behavior.
- Workshop-specific state stays in the Workshop Catalyst Session Type and its
  adapters; shared runtime receives generic registry and profile hooks only.
- Specialist traces require retention and privacy rules.
- Stage 5 retains concise role summaries, model/timestamp provenance, synthesis
  references, and degraded/persistence status as best-effort
  `json.workshop_specialist_trace` artifacts. It does not retain chain-of-thought
  or credentials, and Hub failure never blocks the visible response.
- The AI Assistant reasoning disclosure is collapsed by default and revocable.
  It reports unavailable/degraded trace state rather than implying analysis was
  retained successfully.
- Preset persistence records user layout preference, not workshop meaning.
- Session Type migration needs compatibility readers until all known theme-based
  scenarios and callers have moved.
- The Workshop Catalyst harness must change from role rotation to one
  assistant-attributed sender only when hidden synthesis is implemented.

## 2026-07-11 clarification: Scenarios, stable functions, and map extraction

The user-facing term remains **Scenario**. Workshop Catalyst opens with
Scenario creation as the default action; authored Scenarios are optional
templates. User-authored drafts use a versioned Workshop Packet and local
`user://` persistence until a separate, explicit publication contract exists.

Workshop Catalyst has no simulated cast. Its four Specialist Functions are
stable across Scenarios: Systems & Consequences; Stakeholder & Communication;
Risk & Feasibility; Options & Innovation. Stable functions provide predictable
coverage, testable prompts, and comparable traces. Scenario context changes what
they analyze, not which functions exist. Compatibility normalization strips
legacy Workshop character arrays at the Workshop boundary only; Story Catalyst
character behavior is unchanged.

The same single specialist batch returns versioned `map_candidates` and separate
`facilitator_cues`. Only strictly validated semantic candidates cross the
Workshop-owned event/command seam into `ThinkingMapAdapter`, where they remain
Suggested. Raw transcript or Session Record prose is not a candidate fallback.
Malformed batches therefore create zero map suggestions.

## 2026-07-11 clarification: stateless inference, stateful workshop

Workshop Catalyst performs one stateless model operation per facilitator turn.
That operation returns the four concise specialist summaries, validated map
candidates, facilitator cues, and the single participant-facing assistant
response. It does not use or mutate persisted `ConversationManager` thread
history and does not inherit general SynTree source context.

Continuity remains stateful through bounded, curated inputs: Scenario objective
and packet, current stage, the latest facilitator message, up to eight meaningful
recent exchanges, facilitator-authorized Session Record buckets, and explicitly
enabled committed Thinking Map context. Provider errors and degraded fallback
messages are excluded. Ollama structured tasks use a bounded 4096-token context,
2048-token output budget, low temperature, one attempt, and a 180-second request
budget. When the single full-envelope call fails to parse, Workshop Catalyst may
retry with a two-phase roles-then-synthesis path (ADR 0012 recovery); it does
not pin a specialist model. This replaces raw-history accumulation rather than discarding workshop
memory.

When the structured model response contains no usable map candidate, a bounded
model-free extractor may structure an explicit facilitator statement as a
`participant_said` Suggested item. It only recognizes concrete driver,
consequence, or intervention language; applies the same meta-text and schema
validation as model candidates; labels evidence unsupported; and never commits
the item. These locally validated participant candidates remain deliverable when
the model service is degraded because their provenance does not depend on a
successful model claim.

Ollama models remain warm for five minutes between calls rather than 24 hours.
This avoids retaining every model selected during testing in RAM/VRAM while
preserving normal workshop-turn responsiveness.

## 2026-08-03 clarification: the synthesized narrative is recalled, not broadcast

The original decision above ("publishes one Workshop Catalyst assistant
response") had that response posting to the visible log unconditionally on
every facilitator turn. In practice the 2-5 paragraph narrative became a wall
of text after every exchange, which fights the voice-first live-facilitation
use case this ADR is meant to serve — a facilitator running a room does not
want a paragraph to read out after each thing a participant says.

The specialist *analysis* is unchanged and still runs every turn exactly as
decided above: one stateless batched call, still feeding the Thinking Map and
facilitator cues. What changed is whether the resulting narrative *broadcasts*
to the log automatically:

- `ai_character_agent.gd` caches the full narrative
  (`workshop_catalyst.session_record_latest_text`) and a one-line ambient
  pulse (`workshop_catalyst.session_record_pulse`, formatted by the new pure
  `WorkshopSessionRecordPulse` helper from `map_candidates` category counts)
  into `StoryState` every turn, instead of calling
  `WorkshopCatalystSessionRecord.post()`.
- The pulse mirrors into the Workshop status bar every turn (so the
  facilitator can see analysis happened without reading a paragraph).
- The full narrative is recalled on demand via a new `/synthesis` facilitator
  command — joining the existing `/vote`, `/note`, `/decide`, `/risk`,
  `/defer` vocabulary rather than adding a new UI control paradigm (a button
  was deliberately deferred pending live-session feedback on whether the
  slash command alone feels sufficient).

This does not change the specialist contract, the trace/privacy rules, or the
`/vote`/`/decide` closure paths above — only when the synthesized narrative
becomes visible to the facilitator.

## 2026-08-03 addition: a How To preset, and a clarification of two panels

Facilitator questions during a live-testing pass surfaced that two existing
surfaces were confusing:

- **The right-rail "Session Record" panel** is not the synthesized narrative
  above. It is the Stage 7 editable record (`workshop_session_record_panel_controller.gd`):
  five facilitator-editable categories (decisions, risks, open questions,
  owners, next steps) plus AI proposals awaiting accept/edit/reject/defer. It
  starts empty by design and only fills once `/decide`/`/risk`/`/defer` are
  used, a category's "Add" button is used, or **Next Stage** triggers the
  once-per-stage proposal-suggestion model call. This is a second,
  largely-separate "what did we decide" pipeline from the Thinking Map's
  `map_candidates` — worth unifying at some point, but out of scope here.
- **The left-rail "Session shortcuts" card** is not a static label; it is the
  default state of `workshop_target_surfaces_controller.gd`'s contextual
  preview card, which swaps copy when Plans/Progress preview buttons are
  clicked. No code changes were needed, just documentation of intent.

Separately, scenario-authored `how_to_text` guidance (the same field shown in
the pre-session mode-select popup) had no live-session surface for Workshop
Catalyst: `_move_existing_regions()` only reparents the conversation, input
field, and Session Record region out of the legacy `%TabContainer` when the
dashboard shell mounts, so the old "How To" tab was left orphaned and
unreachable once the shell took over.

Fix: a sixth workspace preset, `PRESET_HOW_TO`, added alongside
Talk/Map/Review/Full Dashboard/Custom in `workshop_workspace_preset_model.gd`
and toolbar (`HowToPresetButton`, next to Custom). Selecting it hides the
conversation and Thinking Map groups (same visibility profile as Review) and
shows a new `HowToSurface` panel in `CenterSecondaryPane` — the same
mechanism Review already uses to take over the main workspace — populated
once at mount from `Global.get_current_scenario().how_to_text` via
`WorkshopWorkspaceController.set_how_to_text()`. No new persistence, no
model calls; purely a read-only view of data that already existed.

While making this change, `workshop_catalyst_controller.gd` and
`workshop_workspace_controller.gd` both crossed the 900-line soft-warning
ratchet. Per the script-size rule, self-contained mechanics were split out
rather than left to grow: one-time region reparenting moved to
`workshop_workspace_region_mount.gd`, and the stress-injection text
extraction plus session-id lookup moved to
`workshop_catalyst_controller_utils.gd`. Both extractions are static/stateless
helpers with no new behavior, only relocated code.

## 2026-08-03 follow-up: How To content, and a watchdog/HTTP-timeout mismatch

The How To preset above shipped as empty scaffolding. It now always renders
an app-level Workshop Catalyst usage guide (presets, all slash commands,
where results surface) from a new standalone constant,
`workshop_catalyst_how_to_text.gd`; a scenario's own optional `how_to_text`
is appended below it labelled "This scenario's guidance," rather than
replacing the base guide (most scenarios never author this field, and the
slash-command vocabulary is universal, not scenario-specific).

Separately, a facilitator hit a spurious failure mode this ADR's guardrails
don't cover: a turn against a cloud model logged `Narrator: ...Timed out
waiting for an AI response...`, while the AI Assistant panel and Session
Record still filled in shortly after — the response had not actually failed.

Root cause: `ai_character_agent.gd` enforces its own in-scene watchdog timer
(`_process()` / `_awaiting_response` / `_response_timer`), entirely
independent of the HTTP-layer timeout inside
`workshop_stateless_model_task.gd`. The 2026-08-02 fix above gave cloud
providers a 120s HTTP budget (`CLOUD_TIMEOUT_SECONDS`) but nobody raised the
watchdog, which still fired at the pre-existing default of 90s
(`RESPONSE_TIMEOUT`) — comfortably before a legitimately slow cloud response
completes. Because `_finalize_turn_hidden_synthesis()` (which caches the
narrative/pulse) runs *inside* the awaited call, before the outer
`my_gen != _generation_id` staleness check, a request that succeeds after
the watchdog already gave up still populates the panels — just with the
Narrator error left standing in the log from the earlier, premature timeout.

Fixed by adding `WORKSHOP_CLOUD_RESPONSE_TIMEOUT := 150.0` (mirroring the
existing +30s buffer `OLLAMA_RESPONSE_TIMEOUT` already keeps above its own
180s Ollama HTTP budget) and applying it in `_response_timeout_seconds()`
whenever the runtime profile is `HIDDEN_SYNTHESIS` and the model isn't
Ollama. Story Catalyst's non-Ollama watchdog is untouched. A regression test
(`_test_hidden_synthesis_watchdog_outlasts_cloud_timeout`,
`test_workshop_catalyst_stage5.gd`) reads both constants back out of source
and asserts the watchdog stays above the HTTP timeout, so the two budgets
can't silently drift out of sync again if either changes.
