---
id: PRD-SCENSYN-WORKSHOP-CATALYST
title: Workshop Catalyst facilitation
status: review
version: "0.2"
owner: Workshop Catalyst product owner
last_reviewed: 2026-07-11
primary_users: [facilitator, workshop participant]
supersedes: null
---

# Workshop Catalyst facilitation

## Problem and outcome

Complex workshops often produce discussion without a clear record of what was
decided, which risks remain, or what was deferred. Workshop Catalyst should help a
human facilitator expose institutional pressures, move a group toward closure,
and leave with a human-readable decision record. The AI supports facilitation; it
does not replace facilitator authority.

## Users and jobs

- **Facilitator:** structure a timeboxed session, intervene when needed, and
  convert discussion into a usable decision record.
- **Participant:** understand the positions in play, contribute to decisions, and
  see what the session has actually established.

## Success measures

- A facilitator can run a session without using developer-facing Tools or
  Services panels after the hub is available.
- The default Talk workspace supports a voice-first session while keeping
  recording, consent, transcription, and save status visible.
- The live Session Record makes captured decisions, risks, and deferred questions
  visible during the workshop.
- Workshop turns present one synthesized assistant response while retaining
  traceable specialist contributions for optional review.
- A useful session can export at least one decision with ownership, one risk, and
  one deferred question with an owner or reason.
- Session timing, stages, buckets, and continuity can be controlled without
  silently overriding facilitator choices.
- The smoke and multi-turn executable specs pass without unexpected errors.

The documented target of three decisions, two risks, and one deferred question is
the complete-session goal. The smaller set above is the minimum viable exported
record for acceptance.

## Scope

### In scope

- Hidden Society of Minds synthesis with one assistant voice per workshop turn.
- Session Type and Collection selection for Workshop Catalyst and Story Catalyst.
- Voice-first facilitation with editable pre-send transcription and versioned
  post-send correction.
- Session duration and stage controls.
- Facilitator notes and visible interventions.
- Authored stress injections.
- Facilitator-reviewed bucket extraction and an editable Session Record.
- Live Thinking Map proposals for causes, effects, and opportunities.
- Evidence-labelled path comparison, including a do-nothing path.
- Talk, Map, Review, Full Dashboard, and Custom workspace presets.
- Vote-assisted and explicit closure capture.
- Workshop summary and decision-record export.
- Same-session resume and opt-in cross-session continuity.

### Out of scope

- Replacing the human facilitator.
- Automatic policy commitment or hidden canonical decisions.
- Scenario-specific policy logic in shared ScenSyn runtime infrastructure.
- Outbound email, active follow-up automation, and remote multi-client turn sync.

## Critical journey

1. The facilitator selects Workshop Catalyst and either creates a Scenario or
   chooses an optional authored Scenario template.
2. The facilitator enters as Facilitator, confirms voice and transcript settings,
   chooses a workspace preset, and starts the timed session.
3. Participants speak or type. Transcript previews remain editable before send,
   and later corrections preserve the original.
4. Hidden specialists analyze each turn in one batched operation. Workshop
   Catalyst presents one synthesized response and retains a reviewable trace.
5. Suggested bucket and Thinking Map updates remain proposals until the
   facilitator accepts, edits, rejects, or defers them.
6. The group compares evidence-labelled paths, including doing nothing, and the
   facilitator advances stages or records closure.
7. The facilitator reviews and commits the Session Record, then exports a
   human-readable decision record.

Detailed operation belongs in the
[`Workshop Catalyst Facilitator Manual`](../user-guide/workshop-catalyst-facilitator-manual.md).

## Requirements

- **REQ-WC-001:** The facilitator must retain control over start, pause, timing,
  stage advancement, and authored stress injection.
- **REQ-WC-002:** Facilitator-only notes must not trigger visible character
  responses.
- **REQ-WC-003:** Captured decisions, risks, and deferred questions must remain
  visible in the Session Record.
- **REQ-WC-004:** Closure capture must support explicit facilitator action when
  automatic convergence detection is insufficient.
- **REQ-WC-005:** Export must produce a human-readable decision record independent
  of the full transcript.
- **REQ-WC-006:** Workshop state must support safe resume without resetting the
  active stage or captured record.
- **REQ-WC-007:** Cross-session continuity must remain opt-in and preserve the
  app-agnostic memory boundary.
- **REQ-WC-008:** Workshop-specific behavior must remain outside shared actor and
  director infrastructure unless it is scenario-generic.
- **REQ-WC-009:** Workshop Catalyst must emit one synthesized assistant voice per
  turn while retaining specialist contributions as a reviewable trace. The
  specialist summaries, map candidates, and visible response must be produced
  in one stateless operation from bounded curated workshop state; raw persistent
  chat history must not accumulate in the inference request.
- **REQ-WC-010:** Transcript correction must preserve the original segment and
  create a new version rather than silently rewriting spoken input.
- **REQ-WC-011:** Bucket, Thinking Map, summary, and path updates must follow
  Propose → Preview → Commit → Version.
- **REQ-WC-012:** Workspace presets may change panel visibility but must not hide
  recording, consent, error, uncommitted-change, or End & Save controls.
- **REQ-WC-013:** Path comparison must include an explicit do-nothing path and
  display whether each claim has supporting evidence.
- **REQ-WC-014:** Workshop Catalyst and Story Catalyst must use the same generic
  Session Type → Collection registry without changing Story Catalyst behavior.
- **REQ-WC-015:** The Participants surface must distinguish local facilitator
  presence from unavailable remote presence. Invite must resolve to an
  explanation and must not collect contact details or perform outbound actions.
- **REQ-WC-016:** Plans and Progress navigation must open labelled previews that
  distinguish current review surfaces from deferred execution, tracking,
  analytics, and follow-up capabilities.
- **REQ-WC-017:** Workshop Catalyst must not create, select, rotate, display, or
  prompt simulated scenario characters. Its four cross-scenario Specialist
  Functions remain stable analytical functions, while Story Catalyst retains
  visible characters.
- **REQ-WC-018:** A facilitator must be able to create and explicitly review a
  Scenario with title, objective, context, outcomes, constraints, time horizon,
  relevant perspectives, and optional evidence notes. Authored Scenarios remain
  optional templates and no template is force-loaded.
- **REQ-WC-019:** User-authored Scenario drafts must be normalized without
  characters and saved reliably as clearly labelled local drafts. Local save
  must not imply Hub publication or canonical commitment.
- **REQ-WC-020:** Thinking Map suggestions must come from validated,
  versioned structured candidates in the existing batched specialist operation.
  Raw participant or Session Record prose and facilitation/meta guidance must
  never be inserted wholesale as Cause, Effect, or Opportunity content.

Stage 9 implements REQ-WC-011 and REQ-WC-013 for Compare Paths. Candidate
generation and import create proposals only. Every committable comparison has
one reviewed do-nothing path with the same required fields as other paths.
Facilitator selection or combination stays draft until semantic Preview and
explicit Commit. Evidence retrieval is non-blocking and cancellable; empty
results and unavailable retrieval remain visible without invented references.
Hub and ClosureBus failures retain truthful retry state. Session Record routing
requires a separate facilitator action.

## Acceptance

Automated coverage:

- [`scensyn_workshop_catalyst_smoke.json`](../technical-review/run_specs/scensyn_workshop_catalyst_smoke.json)
  checks scenario loading, response generation, and error-free execution.
- [`scensyn_workshop_catalyst_multiturn.json`](../technical-review/run_specs/scensyn_workshop_catalyst_multiturn.json)
  asserts exactly one non-human visible sender (`Session Record`) across three
  Workshop turns.
- [`scensyn_story_catalyst_sustainability_multiturn.json`](../technical-review/run_specs/scensyn_story_catalyst_sustainability_multiturn.json)
  retains the complementary multi-sender visible-ensemble assertion.
- `test_workshop_catalyst_stage5.gd` covers profile dispatch, one specialist
  batch, parse/fallback, one synthesized post, zero specialist votes,
  best-effort trace status, and reasoning-panel disclosure states.
- `test_workshop_catalyst_stage6.gd` deterministically covers editable STT
  preview/send/cancel, typed-input non-regression, immutable correction lineage,
  degraded Hub retention, correction-without-resend, and the Session
  Record-only spoken-voice policy.
- `test_workshop_catalyst_stage7.gd` covers isolated summary proposals,
  accept/edit/reject/defer, facilitator-edit precedence, exact and semantic
  repeat suppression, preview non-mutation, explicit-only commit, immutable
  version lineage, degraded Hub retry, committed-reference export, fallback
  labelling, scene controls, and module line limits.
- `test_workshop_catalyst_stage8.gd` covers the WC/SynTree dependency boundary,
  plural map columns, proposal review actions and provenance labels,
  incremental batches with stale replacement, preview non-mutation,
  explicit-only version commit and degraded retry, explicit Session Record
  routing, and default-off/revocable specialist context with no absent-map
  prompt side effects.
- `test_workshop_catalyst_stage9.gd` covers path normalization, exactly one
  do-nothing path, proposal review and facilitator precedence, evidence-none
  labels, stale retrieval cancellation, degraded state, preview non-mutation,
  single and combined selections, immutable Hub lineage, ClosureBus retry, and
  explicit Session Record routing.
- `test_workshop_catalyst_stage10.gd` enumerates every visible Participant,
  Plans, and Progress control; verifies each action resolves; checks the Invite
  dialog and acknowledgement; checks both labelled previews; and proves the
  focused controller has no outbound seam or reported outbound action.
- The shared adapter conformance fixture is exercised through both
  `ContextGraphAdapter` and `ThinkingMapAdapter`; it proves common envelope,
  validation, provenance, and layout-diff semantics while preserving distinct
  graph kinds and artifact contracts.
- Hub Workshop summary tests validate schema/provenance, rejected/deferred
  decision retention, immutable lineage round-trip, duplicate-id rejection, and
  forbidden-field rejection through the generic artifact seam.
- Hub Thinking Map tests validate v1 round-trip/lineage, endpoint and vocabulary
  integrity, source-label honesty, forbidden-field rejection, and refusal of
  `context_graph` payloads through the WC artifact type.
- Hub path-set tests validate v1 round-trip/lineage, one do-nothing path,
  evidence honesty, selection integrity, closure pre-claim rejection, and
  forbidden-field rejection.
- [`scensyn_workshop_catalyst_stt_preview.json`](../technical-review/run_specs/scensyn_workshop_catalyst_stt_preview.json)
  exercises deterministic transcription completion and a confirmed Workshop
  turn while retaining the single Session Record response assertion.

Manual coverage remains required for pre-session selection, timer and agenda
behavior, stress injection timing, bucket extraction quality, real microphone
device capture/permissions and acoustic STT quality, audible Session Record
playback, panel presets, proposal review, Thinking Map, path comparison, voting,
resume, and exports.

The canonical open list is the facilitator manual's
[`Manual acceptance checklist`](../user-guide/workshop-catalyst-facilitator-manual.md#manual-acceptance-checklist).
It includes Stage 10 projector, Invite, preview, and keyboard checks alongside
the hardware and interaction checks for earlier stages. Outbound isolation and
deterministic action resolution remain covered by the Stage 10 test; the linked
items must not be marked complete without target-room evidence.

## Constraints and dependencies

- [Human Agency UX Contract](../implementation_docs/Human_Agency_UX_Contract.md)
- [ScenSyn Scenario Continuity Contract](../implementation_docs/ScenSyn_Scenario_Continuity_Contract.md)
- [Implemented runtime plan](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/completed/ScenSyn_Workshop_Catalyst_Runtime_Robustness_Plan.md)
- [ADR 0006: self-validating JSON harness specs](../architectural-decisions/0006-self-validating-json-harness-specs.md)

## Open questions and risks

- LLM-based bucket extraction and convergence detection require facilitator review.
- Transcript correction defaults to transcript-only retention, preserves the
  original as an immutable version, and never resends without an explicit
  facilitator action. Real-device consent and acoustic behavior still require
  pilot hardware checks. Stage 5 specialist traces are session-scoped,
  participant-visible on request, omit credentials/chain-of-thought, and report
  degraded Hub retention truthfully.

## Evidence map

- User workflow:
  [`workshop-catalyst-facilitator-manual.md`](../user-guide/workshop-catalyst-facilitator-manual.md)
- Runtime definition:
  [`ScenSyn_Workshop_Catalyst_Runtime_Robustness_Plan.md`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/completed/ScenSyn_Workshop_Catalyst_Runtime_Robustness_Plan.md)
- Review criteria:
  [`technical-review/run_specs/README.md`](../technical-review/run_specs/README.md)
- Roadmap:
  [`implementation_tracking/active/10_Session_Types_and_Society_of_Minds.md`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/active/10_Session_Types_and_Society_of_Minds.md)
