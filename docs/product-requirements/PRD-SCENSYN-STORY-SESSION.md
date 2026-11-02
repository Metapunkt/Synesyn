---
id: PRD-SCENSYN-STORY-SESSION
title: ScenSyn story session
status: review
version: "0.1"
owner: ScenSyn product owner
last_reviewed: 2026-07-10
primary_users: [facilitator, participant, solo explorer]
supersedes: null
---

# ScenSyn story session

## Problem and outcome

People exploring possible futures need a structured way to rehearse tensions,
choices, and consequences without treating model output as prediction or truth.
ScenSyn should let a user enter an authored scenario, interact with distinct
roles, retain an inspectable session record, and move between text and staged
presentation where assets support it.

## Users and jobs

- **Facilitator:** run a legible multi-role scenario and steer discussion without
  losing the authored frame or session record.
- **Participant:** contribute to a scenario and understand which role or system
  produced each response.
- **Solo explorer:** rehearse branches and review the resulting narrative record.

## Success measures

- A configured scenario loads with its authored identity and active roles.
- A user message produces an attributed scenario response without unexpected
  runtime errors.
- A multi-turn session shows more than one character sender when the scenario
  calls for role rotation.
- Session context remains isolated from unrelated SynTree and application chats.
- Story Stage is usable for scenarios with the required visual and voice assets.

## Scope

### In scope

- Scenario and role selection.
- Story Log interaction and attributed multi-character responses.
- Facilitator or participant input.
- Session logging and provenance.
- Story Log to Story Stage transition where scenario assets exist.
- Opt-in continuity through the ScenSyn continuity contract.

### Out of scope

- Full Story Stage parity for scenarios without avatar or staging assets.
- The planned Session Type and Society of Minds redesign.
- Multiplayer networking and 3D staging.
- Workshop Catalyst-specific timing, buckets, voting, and decision records.

## Critical journey

1. The user selects an authored scenario and their role.
2. ScenSyn loads the scenario frame, cast, and controls.
3. The user contributes through Story Log.
4. AI-controlled roles respond with visible attribution.
5. The user continues, reviews the log, or opens Story Stage when supported.
6. The session produces an inspectable record and optional continuity input for a
   later session.

Detailed operation belongs in
[`user-guide/scensyn.md`](../user-guide/scensyn.md).

## Requirements

- **REQ-SCENSYN-001:** A session must identify and load the selected scenario.
- **REQ-SCENSYN-002:** User input must enter the active scenario context without
  importing unrelated prompt-surface history.
- **REQ-SCENSYN-003:** Generated turns must expose sender attribution in the Story
  Log.
- **REQ-SCENSYN-004:** Multi-role scenarios must support rotation among eligible
  AI-controlled roles.
- **REQ-SCENSYN-005:** The session must preserve an inspectable turn record.
- **REQ-SCENSYN-006:** Story Stage must use the same active session state where
  scenario assets support staged presentation.
- **REQ-SCENSYN-007:** Continuity must be explicit, scenario-controlled, and
  derived through the ScenSyn adapter contract.

## Acceptance

Automated coverage:

- [`scensyn_game_session_wait_for_ai_response.json`](../technical-review/run_specs/scensyn_game_session_wait_for_ai_response.json)
  covers loading, input, and response capture.
- [`scensyn_workshop_catalyst_multiturn.json`](../technical-review/run_specs/scensyn_workshop_catalyst_multiturn.json)
  exercises multi-turn role rotation on a ScenSyn session.

Manual coverage remains required for Story Stage asset quality, voice parity,
scenario selection UX, and Story Log to Story Stage handoff.

## Constraints and dependencies

- [Human Agency UX Contract](../implementation_docs/Human_Agency_UX_Contract.md)
- [ScenSyn Scenario Continuity Contract](../implementation_docs/ScenSyn_Scenario_Continuity_Contract.md)
- [ADR 0006: self-validating JSON harness specs](../architectural-decisions/0006-self-validating-json-harness-specs.md)

## Open questions and risks

- Story Stage support varies by scenario asset completeness.
- User-facing terminology still uses themes while Session Types remain planned.
- The generic story-session harness does not yet assert continuity restoration.

## Evidence map

- User workflow: [`user-guide/scensyn.md`](../user-guide/scensyn.md)
- Normative contracts: Human Agency UX and ScenSyn continuity contracts
- Review criteria:
  [`technical-review/run_specs/README.md`](../technical-review/run_specs/README.md)
- Roadmap:
  [`implementation_tracking/active/10_Session_Types_and_Society_of_Minds.md`](https://github.com/Metapunkt/Synesyn/blob/main/implementation_tracking/active/10_Session_Types_and_Society_of_Minds.md)
