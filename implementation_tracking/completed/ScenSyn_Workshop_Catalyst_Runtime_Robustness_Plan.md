# ScenSyn Workshop Catalyst Runtime Robustness Plan

**Status**: Implemented — all sections complete, open decisions closed (2026-05-05). Phase 6 (closure formation) complete (2026-05-06). Phase 7 (closure consolidation) complete (2026-05-06).  
**Scope**: Workshop Catalyst runtime affordances, continuity, timing, synthesis, and export hardening  
**Primary implementation area**: `synesyn/synesyn_client/ScenSyn`  
**Policy constraint**: Keep scenario-specific logic out of shared actor/director/runtime infrastructure unless the behavior is genuinely scenario-generic

---

## 1) Purpose

This document turns the current Workshop Catalyst design discussion into a trackable implementation plan for the ScenSyn codebase.

It focuses on the runtime layer needed to make Workshop Catalyst scenarios usable in real facilitated sessions, including:

- live session duration selection
- multi-day session support
- resumable session continuity
- clearer human facilitator steering affordances
- safer bucket synthesis and carry-forward
- export/session-state hardening

This plan is intentionally **Workshop Catalyst-specific but scenario-generic**.  
It must not hardcode `uk_glp1_market_integrity_stress_test` behavior into shared infrastructure such as:

- `ActorAgent`
- `DirectorAgent`
- other cross-theme systems that are not specific to Workshop Catalyst

---

## 2) Non-goals

This plan does **not** include:

- GLP-1-specific logic in shared infrastructure
- calendar/scheduling product features
- arbitrary custom session durations in the first pass
- installation-specific systems from `stochastic_dreams` such as pendulum/OSC/verse/vis-story carryover
- scene-layout migration of Workshop Catalyst controls to `.tscn` in the first pass

---

## 3) Design constraints

### 3.1 Scenario/runtime separation

- Scenario-specific content belongs in scenario `.txt` files.
- Workshop Catalyst runtime behavior belongs in:
  - `workshop_catalyst_controller.gd`
  - `metaprompt_manager_workshop_catalyst.gd`
- Shared engine/runtime code should only gain generic capabilities.

### 3.2 Time model separation

The system must distinguish:

- **live workshop time**: 1-4 hour session, possibly part of a multi-day series
- **scenario-world time**: e.g. "next 72 hours", "next quarter", "next month"

Runtime controls should manage the first.  
Scenario text should define the second.

### 3.3 Human facilitator priority

The system should privilege clear facilitator control over hidden automation.

Examples:

- stage advancement should be explicit
- synthesis should be facilitator-triggered or facilitator-confirmed
- note-only vs facilitator-visible input modes must be clear

### 3.4 Continuity layering

Workshop Catalyst continuity should reuse the existing Synesyn Hub / Artrhythmetic path only at the correct layer:

`ArtrhythmeticMemory` -> `continuity_context` -> `scensyn.scenario_continuity_state` -> Workshop Catalyst interpretation

Rules:

- the canonical memory capability remains app-agnostic
- continuity payloads remain ScenSyn-generic
- Workshop Catalyst interprets continuity in workshop terms, not narrative-fiction terms
- Stochastic Dreams-specific language or framing must not live in shared base layers

---

## 3A) Continuity design

### 3A.1 Why continuity is useful for Workshop Catalyst

Workshop Catalyst can benefit from continuity when a session is:

- resumed later the same day
- continued across multiple days
- revisited after a previous workshop output already exists

The most relevant continuity functions are:

- carry-forward of prior decisions
- preservation of unresolved questions
- persistence of live stakeholder tensions
- continuity of experiments, safeguards, and ownership
- brief reminder of what the previous workshop actually established

### 3A.2 What continuity should not do

Continuity should **not**:

- replace the controller's own session/stage/bucket state
- become a hidden per-turn steering system
- introduce scenario-specific logic into shared runtime systems
- inherit Stochastic Dreams framing such as "Tapestry" or "dreaming" language
- use raw story log replay as the main continuity experience for facilitators

### 3A.3 Recommended continuity source for Workshop Catalyst

Workshop Catalyst should not treat raw transcripts as the primary memory document.

Preferred continuity source composition:

1. scenario scaffold content
2. exported workshop summary content
3. compact carry-forward digest of:
   - decisions
   - safeguards
   - unresolved questions
   - next steps
   - experiments
   - owners where known

This means the memory source for Workshop Catalyst should be:

- stable
- auditable
- human-readable
- compact enough to produce useful continuity anchors

### 3A.4 Workshop interpretation of generic continuity fields

The existing ScenSyn continuity contract is reusable, but Workshop Catalyst should interpret it differently from narrative themes.

Recommended mapping:

- `continuity.anchors`
  - carry-forward commitments, framing anchors, or agreed workshop positions

- `continuity.latent_tensions`
  - unresolved workshop tensions, deferred trade-offs, stakeholder conflicts still in play

- `continuity.focus_terms`
  - recurring topical anchors worth keeping legible in resumed sessions

- `state_patch.memory_context.session_history`
  - prior workshop summary/digest block, not narrative recap

- `state_patch.unresolved_challenges`
  - unresolved policy or facilitation questions still worth carrying forward

- `prompt_cues.continuity_prompt`
  - compact workshop continuity instruction, not mythic/narrative framing

### 3A.5 Workshop continuity prompt behavior

For Workshop Catalyst, continuity should appear in the prompt as:

- previous decisions to preserve or revisit
- unresolved tensions still in play
- carry-forward terms
- prior session summary
- current workshop stage framing

It should **not** appear as:

- symbolic world-lore
- narrative-phase push
- poetic framing copied from Stochastic Dreams

### 3A.6 Continuity should remain opt-in

Workshop Catalyst continuity should remain controlled by scenario configuration, e.g. `[MEMORY_CONTINUITY]`, rather than automatically enabled for every workshop scenario.

This preserves:

- scenario-generic infrastructure
- explicit authorship
- clear facilitator expectations

---

## 4) Acceptance criteria

This implementation is considered ready for live testing when:

- [x] A facilitator can choose a `1-4` hour live session duration.
- [x] A facilitator can mark the session as part of a multi-day series.
- [x] Workshop state persists session timing and continuity metadata.
- [x] Stage timings can be recommended/scaled generically from session duration.
- [x] `Start` resumes correctly after pause instead of always resetting.
- [x] Stage transitions record history.
- [x] Bucket synthesis merges rather than destructively replacing prior work.
- [x] `Facilitator Note` content does not pollute AI dialogue context.
- [x] Workshop state saves and reloads cleanly.
- [x] Export writes to a runtime-safe path (`user://`).
- [x] All new logic remains Workshop Catalyst-generic and does not hardcode GLP-1 rules into shared infrastructure.
- [x] Shared continuity wording in base prompt layers is scenario-generic.
- [x] Workshop Catalyst can consume ScenSyn continuity without inheriting Stochastic Dreams-specific language.
- [x] Workshop continuity is based on scaffold/summary/digest material, not transcript replay alone.
- [x] Workshop continuity remains opt-in via scenario configuration (`[MEMORY_CONTINUITY]` enabled gate).

---

## 5) Target runtime contract

### 5.1 Session affordances

First-pass facilitator affordances should be limited to:

- `Session Duration` dropdown with:
  - `1 hour`
  - `2 hours`
  - `3 hours`
  - `4 hours`
- `Part of multi-day session` toggle

Optional readonly labels:

- current session duration
- whether timing is scaled or fixed
- whether the session is resumed

### 5.2 Resume modes

The runtime should eventually support:

- `fresh`
- `continue_prior_session`
- `summary_only`

### 5.3 Stage timing rule

Scenario-authored stage durations remain canonical defaults.  
Selected live session duration may produce **recommended** runtime timings when the scenario allows scaling.

This must not rewrite scenario text or scenario-world temporal language.

---

## 6) Recommended workshop state shape

Target state under `StoryState["workshop_catalyst"]`:

```json
{
  "session_id": "wc_20260503_2034_01",
  "series_id": "",
  "session_number": 1,
  "is_multi_day": false,
  "session_duration_minutes": 120,
  "uses_scaled_stage_timing": true,
  "resume_mode": "fresh",
  "resume_summary": "",
  "agenda": [],
  "day_index": 0,
  "stage_index": 0,
  "current_stage_name": "",
  "stage_status": "not_started",
  "stage_started_at_unix": 0,
  "stage_completed_at_unix": 0,
  "stage_remaining_sec": 0,
  "is_note_only_next_input": false,
  "send_as_facilitator": false,
  "current_stage_buckets": {
    "ideas": [],
    "constraints": [],
    "risks": [],
    "decisions": [],
    "open_questions": [],
    "next_steps": []
  },
  "session_buckets": {
    "ideas": [],
    "constraints": [],
    "risks": [],
    "decisions": [],
    "open_questions": [],
    "next_steps": []
  },
  "stage_history": []
}
```

First-pass simplification is allowed if needed, but these fields are the intended direction.

---

## 7) File-by-file implementation checklist

## 7.1 `synesyn/synesyn_client/ScenSyn/scripts/core/scenario_loader.gd`

Purpose: add generic Workshop Catalyst scenario schema support.

- [ ] Parse `[TIME_MODEL]` into `scenario["time_model"]` as a key/value dictionary.
- [ ] Parse `[STAGE_GUIDANCE]` into `scenario["stage_guidance"]` using subsection parsing similar to `PHASE_GUIDANCE`.
- [ ] Allow `[FACILITATOR_PLAYBOOK]` to flow through as `facilitator_playbook_text`.
- [ ] Allow `[RESUME_GUIDANCE]` to flow through as `resume_guidance_text`.
- [ ] Keep the parser generic; do not add GLP-1-specific schema keys here.
- [ ] Preserve backward compatibility for older Workshop Catalyst scenarios with none of these sections.

Done when:

- [ ] Existing scenario files still load unchanged.
- [ ] New fields are present in the scenario dictionary when authored.

---

## 7.2 `synesyn/synesyn_client/ScenSyn/session_types/workshop_catalyst/scenarios/uk_glp1_market_integrity_stress_test.txt`

Purpose: consume the new generic Workshop Catalyst schema.

- [ ] Add `[TIME_MODEL]` with:
  - [ ] `default_session_duration_hours`
  - [ ] `allow_session_duration_override`
  - [ ] `min_session_duration_hours`
  - [ ] `max_session_duration_hours`
  - [ ] `default_multi_day`
  - [ ] `stage_timing_mode`
- [ ] Add `[STAGE_GUIDANCE]` keyed to the authored workshop stages.
- [ ] Optionally add `[FACILITATOR_PLAYBOOK]`.
- [ ] Optionally add `[RESUME_GUIDANCE]`.
- [ ] Optionally add `[MEMORY_CONTINUITY]` only when Workshop Catalyst continuity is actually intended for this scenario.

Done when:

- [ ] The scenario remains intelligible as a standalone authored packet.
- [ ] No runtime code contains GLP-1-specific hardcoded behavior that duplicates this content.

---

## 7.3 `synesyn/synesyn_client/ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller.gd`

Purpose: implement the core Workshop Catalyst runtime affordances.

### State initialization

- [ ] Add generic runtime state fields:
  - [ ] `session_id`
  - [ ] `series_id`
  - [ ] `session_number`
  - [ ] `is_multi_day`
  - [ ] `session_duration_minutes`
  - [ ] `uses_scaled_stage_timing`
  - [ ] `resume_mode`
  - [ ] `resume_summary`
  - [ ] `stage_status`
  - [ ] `stage_history`
- [ ] Read defaults from `scenario["time_model"]` when available.
- [ ] Generate a stable `session_id` once and persist it.

### UI controls

- [ ] Add `Session Duration` dropdown with `1-4` hour options.
- [ ] Add `Part of multi-day session` toggle.
- [ ] Add readonly label summarizing current session format.
- [ ] Make note/facilitator mode labels explicit:
  - [ ] `Next input is note only`
  - [ ] `Send as Facilitator (visible to AI)`
- [ ] Add readonly current-mode summary.

### Timing logic

- [ ] Preserve authored stage durations as original values.
- [ ] Compute recommended durations when timing mode is `scalable`.
- [ ] Make `Start` resume if paused and only initialize full duration when the stage has not started.
- [ ] Make `Pause` preserve remaining time.
- [ ] Make `Next`:
  - [ ] finalize current stage
  - [ ] snapshot relevant stage state into `stage_history`
  - [ ] advance agenda indices
  - [ ] initialize next stage timing without forcing auto-start

### Synthesis / buckets

- [ ] Split synthesis/export actions into clearer commands:
  - [ ] `Synthesize Current Stage`
  - [ ] `Export Snapshot`
  - [ ] `Export Final Summary`
- [ ] Replace destructive bucket replacement with merge/dedupe behavior.
- [ ] Preserve prior facilitator-curated bucket items when synthesizing new content.
- [ ] If possible, begin separating `current_stage_buckets` from `session_buckets`.

### Resume support

- [ ] Support `fresh`, `continue_prior_session`, and `summary_only` as runtime state concepts.
- [ ] Surface resumed-session context in a lightweight way to the facilitator.
- [ ] If continuity is loaded from the Hub path, expose only workshop-relevant carry-forward information to the facilitator.

Done when:

- [ ] A facilitator can run a 1-hour session without changing scenario text.
- [ ] A facilitator can mark the workshop as part of a multi-day series.
- [ ] Stage progression no longer feels ambiguous or destructive.

---

## 7.4 `synesyn/synesyn_client/ScenSyn/session_types/workshop_catalyst/metaprompt_manager_workshop_catalyst.gd`

Purpose: expose live Workshop Catalyst runtime context to the prompt, without scenario hardcoding.

- [ ] Read `scenario["stage_guidance"]` and include the active stage's guidance in prompt construction.
- [ ] Read `facilitator_playbook_text` if needed for workshop/facilitator prompt context.
- [ ] Extend the live workshop state block with:
  - [ ] session duration
  - [ ] multi-day flag
  - [ ] resume mode
  - [ ] stage status
- [ ] Add a resume-context block when continuing a previous session:
  - [ ] prior decisions
  - [ ] unresolved questions
  - [ ] current or intended next stage
- [ ] If `memory_context` / `continuity_prompt_cues` exist, reinterpret them in workshop terms:
  - [ ] carry-forward anchors
  - [ ] unresolved tensions
  - [ ] prior session summary
  - [ ] suggested facilitation focus
- [ ] Keep the content generic to Workshop Catalyst and free of GLP-1-specific conditionals.

Done when:

- [ ] Prompt quality improves because the model understands session format and current stage purpose.
- [ ] Shared actor/director code remains untouched by scenario-specific rules.

---

## 7.5 `synesyn/synesyn_client/ScenSyn/scripts/core/game_session_ai_flow_utils.gd`

Purpose: tighten only generic Workshop Catalyst input routing.

- [x] Keep `/note` handling generic and reliable.
- [x] Ensure one-shot note mode always resets after use.
- [x] Preserve clear distinction between:
  - [x] participant/role input
  - [x] facilitator-visible input (`send_as_facilitator` → sender "Facilitator")
  - [x] facilitator-note-only input (`/note` or `is_note_only_next_input` → sender "Facilitator Note")
- [x] Prepare for future sender-type metadata if needed for export/synthesis. (current sender labels are sufficient; no structural change needed yet)
- [x] Do not add scenario-specific routing rules here. (only a theme-level `workshop_catalyst` check — generic to all WC scenarios)

Done when:

- [x] A human facilitator can steer the workshop in concert with AI without confusing the runtime about what kind of input was sent.

---

## 7.6 `synesyn/synesyn_client/ScenSyn/scripts/conversation_management_system.gd`

Purpose: prevent facilitator notes from polluting AI conversation context.

- [ ] Exclude `Facilitator Note` entries from narrative/AI context construction, or isolate them into a clearly separate optional channel.
- [ ] Keep workshop notes available for export and continuity, but not as ordinary in-character dialogue context.
- [ ] Ensure the rule is generic to Workshop Catalyst system-cue semantics, not tied to GLP-1 content.

Done when:

- [ ] Facilitator notes help humans but do not silently steer roleplay output.

---

## 7.7 `synesyn/synesyn_client/ScenSyn/scripts/story_log_system.gd`

Purpose: harden export and persistence for live workshop use.

- [ ] Continue saving Workshop Catalyst sidecar state, including new runtime fields.
- [ ] Add support for `snapshot` and `final summary` export concepts.
- [ ] Move workshop summary output from `res://` to `user://`.
- [ ] Include workshop metadata in exports:
  - [ ] session duration
  - [ ] multi-day flag
  - [ ] session ID
  - [ ] series ID
  - [ ] stage history
- [ ] Distinguish facilitator notes, facilitator-visible inputs, and ordinary role messages in export output where possible.

Done when:

- [ ] Export is reliable in real builds.
- [ ] Post-session workshop artifacts are usable without manual cleanup.

---

## 7.8 `synesyn/synesyn_client/ScenSyn/scripts/core/game_session_storylog_utils.gd`

Purpose: harden load/resume behavior.

- [ ] Restore new Workshop Catalyst sidecar fields when loading prior sessions.
- [ ] Support resume behaviors at the state level:
  - [ ] full continue
  - [ ] summary only
  - [ ] fresh
- [ ] Ensure resumed sessions do not duplicate or corrupt bucket/state history.
- [ ] Preserve backward compatibility for older workshop saves with fewer fields.

Done when:

- [ ] A previous session can be resumed later with predictable continuity.

---

## 7.9 `synesyn/synesyn_client/ScenSyn/scripts/game_session.gd`

Purpose: keep Workshop Catalyst initialization clean and theme-bounded.

- [ ] Ensure Workshop Catalyst initialization remains lightweight and theme-specific.
- [ ] Pass any needed setup/resume context into the controller cleanly.
- [ ] Avoid story-first startup wording for Workshop Catalyst where possible.
- [ ] Do not move Workshop Catalyst-specific timing or resume logic into shared narrative/theme-agnostic systems unless the behavior is clearly reusable.

Done when:

- [ ] Workshop Catalyst boots cleanly without broadening shared runtime coupling.

---

## 7.10 `synesyn/synesyn_client/ScenSyn/scripts/services/scensyn_continuity_service.gd`

Purpose: keep the Hub/Artrhythmetic continuity path reusable for Workshop Catalyst.

- [ ] Ensure Workshop Catalyst continuity source documents are scaffold-based and summary/digest-oriented, not transcript-replay-oriented.
- [ ] Extend `_build_scenario_memory_markdown()` to include workshop-relevant authored sections when present, such as:
  - [ ] `facilitator_playbook_text`
  - [ ] `resume_guidance_text`
  - [ ] `stage_guidance`
  - [ ] output-template text where relevant
- [ ] Keep source-building logic scenario-generic and text-section-based.
- [ ] Preserve the current adapter layering; do not make the continuity service canonical contract Workshop Catalyst-specific.

Done when:

- [ ] Workshop scenarios can use the continuity service without importing Stochastic Dreams semantics.

---

## 7.11 `synesyn/synesyn_client/ScenSyn/scripts/core/game_session_startup_utils.gd`

Purpose: load continuity only when explicitly configured and keep it advisory.

- [x] Keep Workshop Catalyst continuity behind `[MEMORY_CONTINUITY]` or equivalent scenario config. (`_load_scenario_continuity` checks `memory_continuity.enabled == "true"` before doing anything)
- [x] Ensure continuity load remains non-destructive if workshop state already exists. (`load_into_story_state` writes to `scenario_continuity_state`, a separate field from `workshop_catalyst`)
- [x] If continuity load fails, do not block workshop startup. (errors are logged and silently skipped; startup continues normally)

Done when:

- [x] Workshop continuity is opt-in and operationally safe.

---

## 7.12 `synesyn/synesyn_client/ScenSyn/scripts/core/base_metaprompt_manager.gd`

Purpose: preserve scenario-generic continuity language in the shared base layer.

- [ ] Ensure cross-session continuity wording remains neutral and reusable across themes.
- [ ] Do not reintroduce Stochastic Dreams-specific language such as "Tapestry" or "dreaming" into the base continuity block.
- [ ] Keep any continuity interpretation that is theme-specific in the theme metaprompt managers instead.

Done when:

- [ ] Shared continuity infrastructure is reusable without thematic bleed.

---

## 8) Recommended implementation sequence

### Phase 1: schema + state foundation ✓

- [x] `scenario_loader.gd`
- [x] `uk_glp1_market_integrity_stress_test.txt`
- [x] `workshop_catalyst_controller.gd` state initialization

### Phase 2: session duration + timing ✓

- [x] Workshop controller session duration dropdown
- [x] Workshop controller multi-day toggle
- [x] Stage timing recommendation/scaling
- [x] Timer semantics hardening
- [x] Workshop metaprompt live-state injection

### Phase 3: continuity substrate alignment ✓

- [x] Base continuity prompt wording neutralization
- [x] Workshop continuity design finalized (decisions closed)
- [x] continuity service source-building review for workshop use
- [x] startup continuity remains opt-in and advisory

### Phase 4: continuity + buckets ✓

- [x] Bucket merge/dedupe behavior
- [x] Stage history capture
- [x] Facilitator note filtering from AI context
- [x] Resume/load behavior

### Phase 5: export hardening ✓

- [x] Snapshot export (manual via Export button)
- [x] Final summary export (decision-record-first format)
- [x] `user://` path migration
- [x] richer workshop metadata in exported artifacts (session duration, multi-day, session ID, stage history)

---

## 9) Open decisions

**All decisions closed 2026-05-05.**

| # | Decision | Resolution |
|---|---|---|
| 1 | Stage timing scaling — default on or user-controlled? | **On by default** when `stage_timing_mode == scalable`. No extra toggle. Facilitators ignore recommended times if not useful. |
| 2 | Synthesize-and-advance — one button or two? | **Keep separate.** "Next Stage" advances; bucket synthesis is its own explicit action. Combining risks a failed LLM call mid-transition. |
| 3 | `current_stage_buckets` / `session_buckets` — split now or later? | **Later.** Merged `buckets` field works. Split when per-stage reporting is an active requirement. |
| 4 | Resume UI — immediate dialog or just restore state? | **Just restore and label.** Show a status label ("Resumed — stage X"). Full mode-choice dialog deferred. |
| 5 | Facilitator-visible inputs in export — inline or separate? | **Inline**, sender clearly labelled "Facilitator". Decision record section at top is already a distinct artifact; no further separation needed. |
| 6 | Continuity source — exported summaries or purpose-built digest? | **Exported summaries for now.** `.workshop.json` already has decisions/risks/open questions structured. Dedicated digest pipeline deferred. |
| 7 | How much generic continuity payload does Workshop Catalyst surface? | **Translate, don't surface raw.** Metaprompt manager reframes `anchors`/`latent_tensions`/`focus_terms` into workshop language. Generic payload must not bleed through uninterpreted. |

---

---

## Phase 6: Closure Formation System (complete 2026-05-06)

This phase was driven by observed failure modes in live sessions: AI characters could reach consensus verbally but the system could not detect it, leading to sessions that never captured decisions without direct facilitator intervention.

### 6.1 Design decision: vote-based closure via Session Record

The Session Record was promoted from a passive progress tracker to an **active closure formation controller**. Instead of relying on character output tokens (`[VOTE:DECIDE]`), the Session Record synthesises a formal PROPOSAL from recent dialogue using an LLM call and asks participants to vote Yes or No.

This decision was made over alternatives that elevated Session Record to a full agent (deferred), and over a simpler phrase-detection patch (insufficient on its own).

### 6.2 Files changed in Phase 6

#### `workshop_catalyst_session_record.gd`

- `call_vote_from_recent_log(trigger)`: core vote initiation. Uses `conv.chat()` with `_build_vote_proposal_prompt()` to synthesize a JSON proposal (decision / risk / open question), then registers it in `StoryState.workshop_catalyst.pending_vote`. Guarded by `_vote_call_in_flight` to prevent concurrent invocations from a single AI batch.
- `record_vote(voter, choice)`: tallies `votes_yes` / `votes_no`. Captures on simple majority Yes or majority No. Resolves by plurality when all participants have voted.
- `_build_vote_proposal_prompt()`: detailed LLM prompt that produces `{ kind, text, owner, confidence }`. Explicitly instructs the LLM that `owner` is **required** for decisions (defaults to `"Workshop chair"`), and that `text` must not carry a trailing period.
- `_llm_detect_convergence_skirt()`: periodic background convergence check. YES rules: new kernel being refined with agreement and no new blocking objections. NO rules: vote rationale attached to a vote, decision recently captured, characters still disagreeing substantively.
- `_maybe_run_convergence_check()`: calls the convergence detector every 3 turns (2 turns after a capture). Respects the capture cooldown.
- `_capture_proposal_and_clear()`: strips trailing period from LLM-supplied statement (`rstrip(".")`). Ensures owner defaults to `"Workshop chair"` for decisions. Sets `_capture_cooldown_until_turn`. Posts a pivot summary via `_build_pivot_summary()`.
- `_discard_proposal_and_clear()`: also sets `_capture_cooldown_until_turn`.
- `_build_pivot_summary()`: generates a directive message naming remaining targets and directing the group to pivot.
- `is_in_capture_cooldown()`: public accessor used by `metaprompt_manager_workshop_catalyst.gd`.
- `_try_post_gap_flag()`: now triggers `call_vote_from_recent_log()` rather than a SYNTHESIS DIRECTIVE. Respects cooldown.

Removed: `synthesis_directive_pending` state, all `SYNTHESIS DIRECTIVE` machinery, `_auto_capture_voted_decision`, old `_record_vote` format, `require_response_prefix` integration.

#### `metaprompt_manager_workshop_catalyst.gd`

- `process_actor_dialogue(character_name, dialogue)`: routes each character turn through vote detection and closure-request detection.
  - If `_has_pending_vote()` is true: detects `<<YES>>` / `<<NO>>` tokens or strict Yes/No openers and calls `_route_vote(character_name, choice)`.
  - If no vote pending: calls `_looks_like_closure_request(dialogue)`. On match, calls `_request_vote_call(trigger)` via `call_deferred`.
- `_looks_like_closure_request(dialogue)`: high-precision detector of ~40 explicit closure phrases. Returns true only on strong, unambiguous closure signals.
- `_strict_opener_vote(dialogue)`: returns "yes" or "no" if the response opens with that word exclusively (not preceded by a greeting).
- `_request_vote_call(trigger)`: deferred async call to `session_record.call_vote_from_recent_log()`. Checks `is_in_capture_cooldown()` first and suppresses autonomous triggers during the cooldown; facilitator `/vote` bypasses this check.
- `get_director_directive_state()`: returns a Director state string that varies by closure mode ("vote_pending" / "convergence" / "open"), including current decision counts and convergence signals.
- `get_director_cue_verb_constraints()`: returns Director cue-verb constraints appropriate to the current closure mode. During `vote_pending`: suspends reactive verbs, allows only convergent verbs. During `convergence`: minimizes reactive verbs, favors Endorse/Synthesize/Propose.
- `get_max_speakers_this_turn()`: returns 1 speaker during `vote_pending`, otherwise uses the standard weighted distribution (60 / 25 / 15 for 1 / 2 / 3 speakers).
- `should_trigger_ai_from_system_entry()`: triggers AI response on Session Record PROPOSAL entries only (not all system messages).
- `set_session_record(sr)`: links the metaprompt manager to the active session record instance.

Removed: `get_required_response_prefix()`, `_synthesis_directive_is_pending`, `_register_pending_proposal`, all `<<VOTE:DECIDE>>` / `[VOTE:DECIDE]` processing.

Updated: CLOSURE PROTOCOL block in the metaprompt teaches AI characters the Yes/No vote mechanic and rules. ASSENT AND CLOSURE CALIBRATION block reframed: assent should not be unreasonably withheld where logical grounds exist, rather than a hard automatic rule.

#### `base_metaprompt_manager.gd`

Added three generic Director affordance hooks with default no-op implementations:
- `get_director_directive_state() -> String`
- `get_director_cue_verb_constraints() -> Dictionary`
- `get_max_speakers_this_turn() -> int`

These are permanently available in the base class. Themes that do not override them get no-op behaviour. Any theme can configure them.

Removed: `get_required_response_prefix()`.

#### `DirectorAgent.gd`

`generate_batch_plan()` prompt template now dynamically includes `DIRECTIVE STATE` and `CUE VERB CONSTRAINTS` sections when the metaprompt manager returns non-empty values. Director framing updated to: "You are a performance and dialogue director for a performative role play experience."

#### `ai_character_agent.gd`

- `_plan_next_response_speakers()`: calls `_cached_metaprompt_manager.get_max_speakers_this_turn()` to constrain speaker count.
- Removed: `_coerce_required_response_prefix`, `_proposal_body_from_unprefixed_text`.
- Added: `call_deferred("_maybe_generate_ai_response")` after processing AI batches to pick up any System entries immediately.

#### `ActorAgent.gd`

Removed all code enforcing `require_response_prefix` (both `_violates_hard_rules()` check and corresponding `_build_fix_prompt()` branch). Duplicate `txt_lower` variable declaration fixed (first instance renamed to `txt_opener`).

#### `game_session_ai_flow_utils.gd`

- `_handle_workshop_vote_command()`: async static function. Detects `/vote` typed by the facilitator, retrieves the session record, and calls `await session_record.call_vote_from_recent_log("facilitator_vote_command")`.
- `on_player_input_received()`: human input is routed through `Global.get_metaprompt_manager().process_actor_dialogue()` for vote/closure-request detection.

Removed: `_handle_workshop_pending_proposal_adoption`, `_handle_workshop_direct_decision_assent`, `_handle_workshop_synthesis_request`, `_looks_like_chair_adoption`, `_looks_like_direct_decision_assent`, `_find_previous_substantive_statement`, `_decision_text_from_statement`.

#### `workshop_catalyst_controller.gd`

- `initialize()` and `_on_start_pressed()` now call `mgr.set_session_record(_session_record)`.
- `_advance_stage()`: correctly logs unresolved pending votes using `pv.get("votes_yes", [])` / `pv.get("votes_no", [])`.
- `_update_buckets_from_recent_log()` prompt includes a **WHAT NOT TO EXTRACT** block: explicitly prevents workshop meta-state, progress narration, time warnings, and stage transition language from entering any bucket (particularly `constraints` and `next_steps`). Includes self-check rule.
- `_bucket_item_to_string()`: defensive collapse of `".."` artifacts: `while raw.find("..") != -1: raw = raw.replace("..", ".")`.

### 6.3 Architectural rule preserved

All Phase 6 changes satisfy the normative rule:

- The Director affordances (`get_director_directive_state`, `get_director_cue_verb_constraints`, `get_max_speakers_this_turn`) are **generic capabilities always present** in `base_metaprompt_manager.gd`. They produce no-ops unless overridden by a theme.
- Workshop Catalyst closure logic lives entirely in `metaprompt_manager_workshop_catalyst.gd`, `workshop_catalyst_session_record.gd`, and `workshop_catalyst_controller.gd`.
- No scenario-specific content (GLP-1 or otherwise) was introduced into `DirectorAgent`, `ActorAgent`, `ai_character_agent`, or any other shared infrastructure.

### 6.4 Cosmetic output quality fixes (2026-05-06)

Three output quality issues were corrected:

| Issue | Fix location | Fix |
|---|---|---|
| Trailing double-period in captured decisions | `workshop_catalyst_session_record.gd` `_capture_proposal_and_clear()` | `statement = statement.rstrip(".")` before appending Owner/Confidence. |
| Decision 1 missing owner field | `workshop_catalyst_session_record.gd` `_build_vote_proposal_prompt()` and `_capture_proposal_and_clear()` | Prompt instructs LLM that `owner` is **required** for decisions; lenient fallback to `"Workshop chair"` if still empty at capture. |
| Workshop progress narration in `constraints` bucket | `workshop_catalyst_controller.gd` `_update_buckets_from_recent_log()` | WHAT NOT TO EXTRACT block with explicit examples and self-check rule. |

Additionally, `_bucket_item_to_string()` now collapses any `".."` double-period artifacts from any source retroactively.

### 6.5 Open decisions from Phase 6

| # | Decision | Resolution |
|---|---|---|
| A | Should Session Record be elevated to a full agent (like DirectorAgent)? | **Resolved in Phase 7 below — chose Option B (kernel + substrate emitter), not full agent promotion.** |
| B | Should the capture cooldown be configurable per scenario? | **Deferred.** Default 4 turns lives in `CaptureCooldown.DEFAULT_DURATION_TURNS`; the duration argument to `start()` is per-call so themes can override without code changes here. Review when multi-scenario production testing begins. |

---

## Phase 7: Closure Formation Consolidation (complete 2026-05-06)

This phase responded to the framework-level question: **should closure formation be elevated to a first-class agent (like `DirectorAgent`/`ActorAgent`) given that closure is central to Synesyn beyond Workshop Catalyst?**

The decision matrix evaluated three options:

| Option | Description | Decision |
|---|---|---|
| A | Full promotion to a `SessionRecordAgent` / `ClosureAgent` in shared infrastructure | **Rejected** — premature abstraction with one data point; agent shape doesn't fit a stateful event-driven controller |
| B | Extract theme-generic primitives + add substrate emitter; keep theme ownership of synthesis | **Chosen** — solves only what is provably reusable, lights up substrate hand-off immediately |
| C | Status quo + minimal substrate emitter only | Rejected — defers a refactor that's safe to do now |

Rationale for Option B over A:
- The agent pattern in ScenSyn is for autonomous LLM-driven generation per turn. SessionRecord is fundamentally an event-driven coordinator with occasional LLM calls; forcing it into the agent shape misrepresents what it is.
- Substrate hand-off (closures persisted as `ui.closure` artifacts in the LatentSubstrate) is the immediate leverage point for "consolidating closure across Synesyn." Memory-bearing closures should later be mirrored into Artrhythmetic Store `closures/` as the canonical memory form. That requires an emitter/bridge, not an agent.
- The hard part of closure formation (what converges, what counts, what shape) is irreducibly theme-specific. Promoting it monolithically would either pull theme logic up or produce an empty abstraction.
- Workshop Catalyst is currently the only theme exercising vote-based closure. Two implementations are needed before the abstraction joints become visible.
- Option B does not foreclose Option A. The kernel is the natural Phase 1 of any future agent-promotion path.

### 7.1 New shared modules

Located under `synesyn/synesyn_client/ScenSyn/scripts/closure/`:

#### `vote_tally.gd` (`class_name VoteTally`)

Pure-logic, stateless helper. Theme-generic encoding of vote tally rules.

- `record(votes_yes, votes_no, voter, choice) -> bool` — idempotent vote recording, supports vote changes (yes ↔ no), returns false on stale duplicate.
- `threshold(cast_size) -> int` — simple-majority threshold with degenerate-case handling.
- `resolve(votes_yes, votes_no, cast_size) -> Dictionary` — returns `{outcome, reason}` where outcome is `"yes" | "no" | "pending"` and reason is `"Yes" | "No" | "Plurality (Yes)" | "Plurality (No)"`. Tie-break: Yes wins on ties (conservative pro-closure default).

#### `capture_cooldown.gd` (`class_name CaptureCooldown`)

Tiny stateful object owned by the theme record. One per session. Tracks the post-capture "riff window" during which autonomous closure detectors are suppressed.

- `start(current_turn, duration_turns = DEFAULT_DURATION_TURNS)` — starts/restarts the cooldown.
- `is_active(current_turn) -> bool` — returns true while in the window.
- `expires_at() -> int`, `clear()` — accessor and reset.
- `DEFAULT_DURATION_TURNS = 4` — the constant used by Workshop Catalyst, configurable per call.

#### `closure_bus.gd` (`class_name ClosureBus`, Node)

Cross-cutting event bus for closure formation. Theme records emit captures and discards here; consumers listen.

- `signal closure_captured(payload)` — fires when a closure is captured.
- `signal closure_discarded(payload)` — fires when a proposal is rejected.
- `emit_captured(payload)`, `emit_discarded(payload)` — convenience methods that stamp `schema_version` and `captured_at_unix` if missing.
- `SCHEMA_VERSION = "1.0"`.
- Composes a `ClosureSubstrateEmitter` child on `_ready()`.

Payload schema (theme-agnostic):
```
{
  "schema_version":  "1.0",
  "theme_id":        String,
  "scenario_id":     String,
  "scenario_name":   String,
  "kind":            String,         # theme-defined
  "statement":       String,
  "owner":           String,
  "confidence":      String,
  "voters_yes":      Array[String],
  "voters_no":       Array[String],
  "outcome":         "yes" | "no",
  "reason":          String,
  "trigger":         String,         # what initiated this closure round
  "stage_name":      String,
  "stage_turn":      int,
  "session_turn":    int,            # -1 if unknown
  "captured_at_unix": float,
  "source_log_index_open":  int,     # when proposal was registered
  "source_log_index_close": int      # at moment of capture
}
```

#### `closure_substrate_emitter.gd` (`class_name ClosureSubstrateEmitter`, Node)

Subscribes to `ClosureBus.closure_captured` and posts each capture to the Synesyn Hub LatentSubstrate as a `ui.closure` artifact via `POST /substrate/artifacts` with `inline_json`.

- Uses `ProviderModePolicy.get_hub_base_url(RuntimeConfig.load_config())` for URL resolution.
- Disables system proxy for localhost (mirrors `HubProcessManager` workaround).
- Fire-and-forget: never awaits the response. Cannot block live workshop UX.
- Silent failure modes: if Hub unreachable, returns non-2xx, or workspace not configured, the post fails quietly. A single warning is printed once if the Hub URL cannot be resolved at all.
- Discards are not persisted by default (they are useful as a live signal but typically not as substrate artifacts).
- Provenance metadata indexed by the Hub: `source_app`, `theme_id`, `scenario_id`, `scenario_name`, `kind`, `outcome`, `trigger`, `stage_name`, `captured_at_unix`.
- Optional Artrhythmetic Store mirror: when `apps.scensyn.publish_closures_to_artrhythmetic_store=true`, captured closures are also posted to `/artrhythmetic-store/closures/commit` as canonical Store closure records.

### 7.2 Wiring

#### `Global.gd`

Added `var closure_bus: ClosureBus` and `func get_closure_bus() -> ClosureBus`. Instantiated in `_ready()` as a child node alongside the other helpers (external input listener, umeno engine, player auto input). Available at `Global.get_closure_bus()`.

### 7.3 Refactored `WorkshopCatalystSessionRecord`

Theme record now composes the new helpers. Behavior preserved exactly.

- Removed: `var _capture_cooldown_until_turn: int`, `const _CAPTURE_COOLDOWN_TURNS: int`, `func _vote_threshold()`. Tally branching collapsed.
- Added: `var _cooldown: CaptureCooldown = CaptureCooldown.new()`. `is_in_capture_cooldown()` now delegates to `_cooldown.is_active(_stage_turn_count)`. `reset_stage_turn_count()` calls `_cooldown.clear()`.
- `record_vote()` now uses `VoteTally.record()` and `VoteTally.resolve()`. Same outcomes (Yes, No, Plurality (Yes), Plurality (No)) — the rules moved into `VoteTally`, the dispatch is unchanged.
- `_capture_proposal_and_clear()` now calls `_cooldown.start(_stage_turn_count)` and emits to the closure bus via `_emit_closure_event(captured=true, ...)`.
- `_discard_proposal_and_clear()` mirrors the same: cooldown start + bus emit with `captured=false`.
- New helper: `_emit_closure_event(captured, kind, statement, owner, confidence, voters_yes, voters_no, reason, ws, pending)` — builds the payload defined by `ClosureBus` and forwards to the appropriate emit method. Silently no-ops if `Global` or the bus isn't available.
- New field on `pending_vote` dict: `"trigger"` — carried through from `call_vote_from_recent_log()` so substrate analysis can see which trigger paths produce captures vs discards.

### 7.4 Architectural rule preserved

All Phase 7 changes satisfy the normative rule:

- The closure primitives (`VoteTally`, `CaptureCooldown`, `ClosureBus`, `ClosureSubstrateEmitter`) live in shared infrastructure (`scripts/closure/`) and are theme-agnostic.
- No theme-specific logic was introduced into shared infrastructure. The bus payload carries `theme_id` and `kind` as opaque strings — themes own the meaning of those values.
- Theme ownership is unchanged: `WorkshopCatalystSessionRecord` retains proposal synthesis, convergence detection, bucket shape, and all decision/risk/open-question semantics.

### 7.5 What Phase 7 enables

The substrate hand-off lights up immediately when the Hub is running:

- ScenSyn closures become first-class `ui.closure` artifacts in the LatentSubstrate.
- Memory-bearing closures can be bridged into Artrhythmetic Store `closures/` as canonical symbolic memory records.
- SynAxes can now analyze cross-session closure patterns (which decisions recur, which dissolve, who votes for what).
- SynPunkt can stage captured closures as canonical objects, using `ui.closure` artifacts as operational handles and Store closure records where symbolic memory/provenance matters.
- ReadyMade can carry closures forward as published artifacts.
- The Hub indexes captures by `theme_id`, `scenario_id`, `kind`, `outcome`, and `trigger` for filterable retrieval.

### 7.6 Path forward (deferred)

If a second theme adopts vote-based closure formation, abstract the shared parts further. If the LLM-call surface area grows complex enough, consider promoting to a full agent. Neither step is needed today.

---

## 10) Normative implementation rule

All runtime improvements defined here must satisfy this rule:

- Workshop Catalyst may gain **generic workshop runtime capabilities**
- individual scenarios such as `uk_glp1_market_integrity_stress_test` may author scenario-specific content using those capabilities
- shared infrastructure must not gain scenario-specific behavior unless that behavior is demonstrably reusable across scenarios

This is the core architectural guardrail for the implementation.

