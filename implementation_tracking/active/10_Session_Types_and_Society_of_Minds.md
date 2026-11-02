# To-Do - Session Types & Workshop Catalyst Society of Minds (experience-boundary elevation + hidden multi-agent synthesis)

**Primary spec references**
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Human_Agency_UX_Contract.md`
- `../ScenSyn_Workshop_Catalyst_Runtime_Robustness_Plan.md` (status: Implemented — do not duplicate; this doc extends it)
- `../../../synesyn_client/ScenSyn/THEME_REFACTORING_IMPLEMENTATION_PLAN.md` (historical; introduced the "theme" terminology this doc supersedes)

**Context**
This document captures decisions from an ongoing strategy conversation about pivoting ScenSyn from a visible 4-agent role-play platform toward a professional, voice-first AI planning tool. See prior discussion: value proposition ("ScenSyn helps organisations reduce the unintended consequences of today's decisions..."), infrastructure audit (Hub, Artrhythmetic Store, ClosureBus, Workshop Catalyst are the strongest existing foundation), the naming decision that "theme" collides with `ThemeManager` (light/dark UI theming) and should become `SessionType`, and a grounded code trace of the actual per-turn call path (`AICharacterAgent` → `DirectorAgent` → `ActorAgent` → `StoryState`) that corrected several assumptions in the original plan (see section E).

**Intent**
- Replace the current three-theme split (`sustainability`, `cultural_narratives`, `workshop_catalyst`) with two front-facing **Session Types**: **Workshop Catalyst** (professional facilitation/planning) and **Story Catalyst** (narrative/theatrical experiences, absorbing `sustainability` + `cultural_narratives`).
- Elevate the internal "theme" concept into `SessionType`, which owns not just metaprompt manager + scenario set (as today) but also **agent topology** and default visualization/UI framing — this is what lets Planning and Theatre genuinely diverge instead of sharing one runtime shell.
- Introduce a second, generic tier beneath Session Type — **Collection** — for cases where scenarios within a Session Type need genuinely different runtime subsystems, not just different content.
- Within Workshop Catalyst specifically, refactor the existing 4-agent Director/Actor infrastructure from "4 visible characters" into a hidden **Society of Minds**: functional specialist roles contribute, then a synthesis step combines their contributions into ONE unified voice presented to the user, inspired by the pattern implemented in `ArtificialSubjects/Kernel/Kernel_MVP_Demo/kernel_mvp_01` (`AgentOrchestrator` + `ReviewSynthesizer`) but adapted to ScenSyn's actual (single-request-at-a-time) conversation infrastructure — see section E for why this adaptation is necessary.
- Story Catalyst keeps the current visible multi-character Director/Actor dialogue loop **unchanged** — visible multiplicity is appropriate for narrative/theatre; hidden multiplicity is appropriate for professional facilitation.

**Naming (confirmed 2026-07-02)**
- Front-facing concept/label: **Session Type** (UI copy: "Choose a session type"). Deliberately not "Mode" — collides with the existing light/dark "Switch to Light/Dark Mode" UI copy in `game_session.gd`.
- Technical identifiers: `SessionType`, `session_type`, `session_types/` (folder), `session_type_id`, "session-type-gated" (doc/comment language replacing "theme-gated").
- Two `session_type_id` values at launch: `workshop_catalyst`, `story_catalyst`.
- Second tier beneath Session Type: **Collection** (`collection_id`) — deliberately not "sub-theme," to avoid recreating the naming collision one level down. See section B.
- Workshop Catalyst hidden multi-agent layer: **Society of Minds** (concept name).

---

## Priority guide
- **v0**: SessionType renaming scaffolding (mechanical, low risk).
- **v0.1**: Three themes → two Session Types + Collection tier (content consolidation, regression-tested).
- **v0.2**: Society of Minds vertical slice for Workshop Catalyst, built on the corrected (batched-call, not parallel-call) architecture in section E.
- **v1**: Optional "show reasoning" drill-down, per-role model routing, ClosureBus/Artrhythmetic Store trace integration for specialist contributions, character-selection bypass for Workshop Catalyst.
- **later**: Real concurrent request support in the conversation layer (only then reconsider true-parallel specialist calls), adaptive role count, role-specific tool use, cross-session specialist memory, additional Workshop Catalyst Collections if a genuinely different facilitation methodology is needed.

---

## A) SessionType renaming
- [x] Rename folder `ScenSyn/scenario_themes/` → `ScenSyn/session_types/`.
- [x] Rename `Global.current_theme` → `Global.current_session_type`.
- [x] Replace theme manager dispatch with generic Session Type + Collection manager dispatch.
- [x] Remove the old `theme_to_use` resolution in `Global.gd`.
- [x] Update `scenario_loader.gd` to require `session_type_id` + `collection_id`.
- [x] Update `WorkshopCatalystController` doc comment "Theme-gated workshop facilitation controller" → "Session-type-gated workshop facilitation controller".
- [x] Add a short "superseded terminology" note at the top of `THEME_REFACTORING_IMPLEMENTATION_PLAN.md` pointing to this doc (leave its historical content intact — it's a completed changelog).
- [x] Front-facing UI copy for the picker: "Session Type", never "Mode".
- [x] Manual check (not blind find-replace): `behavior_trees/narrator_x_bt.tres` — confirm no blackboard key literally depends on the string "theme".
- [x] Regenerate moved-resource caches/import metadata through Godot.

## B) Two-tier structure: Session Type → Collection (resolved 2026-07-02)

**Decision**: Session Type and Collection answer different questions and must not be conflated.
- **Session Type** decides *agent topology* — visible ensemble (Story Catalyst) vs. hidden synthesis (Workshop Catalyst).
- **Collection** decides *which runtime subsystem* a scenario needs, independent of agent topology.

This resolves the previous open question about whether to merge `metaprompt_manager_sustainability.gd` and `metaprompt_manager_cultural_narrative.gd`: **do not merge them.** They stay separate because they are not just differently-worded prompts — they are bound to genuinely different subsystems:
- `sustainability` Collection owns: `sustainability_tracker.gd`, `sustainability_meter.gd`, `sustainability_integration_system.gd`, `sustainability_alert_task.gd`, intensity-scaled prompt injection.
- `cultural_narratives` Collection owns: the Odu/UWP ontology (`odu_ontology.json`, `uwp_16x16_ontology.json`), the dramaturgy-matrix CSV processor, verse reading, and (Stochastic Dreams specifically, not the whole Collection) the pendulum/OSC hardware bridge. Confirmed via code: `CulturalNarrativeMetapromptManager` is explicitly data-driven so one manager already hosts both Ireti Okan and Stochastic Dreams — no further split needed within this Collection.

- [x] `workshop_catalyst` session type becomes the professional/planning path and maps to exactly one Collection today (see B.2).
- [x] New `story_catalyst` session type gets two Collections:
  - [x] `sustainability` → `session_types/story_catalyst/sustainability/` (keeps tracker/meter subsystem scoped to the content that uses it).
  - [x] `cultural_narratives` → `session_types/story_catalyst/cultural_narratives/` (keeps Odu/UWP ontology + hardware bridge scoped).
- [x] `sustainability_tracker.gd` / `sustainability_meter.gd` / `sustainability_integration_system.gd` remain scoped to the `sustainability` Collection, active only when that Collection is selected.
- [x] Regression: sustainability and cultural-narrative harness smoke specs pass after the folder move.

### B.1) Generic dispatch (build once, for both Session Types)
- [x] Replace the three parallel lists (`available_scenario_names` / `cultural_scenario_names` / `workshop_catalyst_scenario_names`) with a uniform registry: `session_type_id -> collection_id -> scenario_names`.
- [x] Resolve Session Type → Collection from the registry and instantiate that Collection's manager uniformly for both Session Types.
- [x] `workshop_catalyst` registers exactly one Collection, `decision_triage`, containing all three existing scenarios (`karlsruhe_library_future_design`, `weight_of_decision_glp1_policy_triage`, `workshop_catalyst_demo`).

### B.2) Is Workshop Catalyst really Collection-free forever? (resolved: no hard "no")
Investigated and deliberately left open rather than closed:
- Today's three Workshop Catalyst scenarios differ only in *content* (policy domain vs. library design), not *mechanics* — they share one controller, one `WorkshopCatalystSessionRecord`, one bucket schema (decisions/risks/open questions), one vote/closure engine. This is by design per the robustness plan's "no scenario hardcoding" guardrail, and it is genuinely sufficient for all scenarios that exist today.
- However, a *different facilitation methodology* — not different content — would plausibly need a second Collection, analogous to how Sustainability needed its meter subsystem. Concrete plausible triggers (none built, none planned yet):
  - Divergent ideation/brainstorming (success = idea count/novelty, not decision-bucket convergence; the current engine is built entirely around convergence pressure, which would actively fight a brainstorming session).
  - Crisis/timed-pressure simulation (escalating severity mechanics, closer to Sustainability's intensity scaling than to calm bucket-filling).
  - Negotiation/mediation (success = trust/relationship movement, not a decision record).
- [x] Decision: keep the dispatch mechanism in B.1 generic across both Session Types (cheap now) so that adding a second Workshop Catalyst Collection later is "register a new collection," not an architecture change. Do not build a second Workshop Catalyst Collection speculatively — wait for an actual second methodology to justify it.

## C) Agent topology divergence by Session Type (the actual payoff of the SessionType boundary)
- [ ] `story_catalyst`: keep the current Director/Actor loop fully unchanged — batched tactical cues → N visible character lines in the story log, exactly as `AICharacterAgent.generate_ai_character_response()` does today. Visible multiplicity is intentional here; it is theatre.
- [ ] `workshop_catalyst`: adopt the Society of Minds pattern (section D) — specialist contributions run hidden, one synthesized voice is shown.
- [ ] Add a declared per-session-type agent pipeline selector (e.g. on `Global` or a small `SessionTypeRuntimeProfile` resource): `"visible_ensemble"` vs `"hidden_synthesis"`. This is the concrete mechanism that lets the split live at the architecture boundary rather than as scattered `if` checks through `game_session.gd`.

## D) Workshop Catalyst: Society of Minds (hidden multi-agent synthesis)

Reference implementation studied: `ArtificialSubjects/Kernel/Kernel_MVP_Demo/kernel_mvp_01/backend/ai/agents/kernel_agent_base.py` (`AgentOrchestrator.conduct_parallel_review`) and `backend/ai/synthesis/review_synthesizer.py` (`ReviewSynthesizer`).

**Pattern being ported (adapted — see section E for why not verbatim)**: named specialist agents each independently produce a structured contribution — in Kernel, run in parallel via `asyncio.gather`. A separate, distinct Synthesizer (not one of the specialists) computes consensus/disagreement and produces ONE unified, human-facing artifact. Individual contributions are preserved in metadata for auditability but are not the primary UX.

**Important distinction from ScenSyn's current loop**: `DirectorAgent` + `ActorAgent`, orchestrated by `AICharacterAgent.generate_ai_character_response()`, today fan multiplicity *out* to the visible story log (cues → visible lines, posted individually via `StoryState.add_log_entry()`). Society of Minds requires collapsing multiplicity back *in* via a synthesis step — relabeling the characters as "expert roles" alone does not achieve this.

- [x] Define four controlled functional specialist roles for Workshop Catalyst, replacing narrative "characters": Systems & Consequences, Stakeholder & Communication, Risk & Feasibility, and Options & Innovation.
- [x] Build specialist contribution generation using the **batched-call pattern**, not N separate `ActorAgent` calls and not concurrent requests.
- [x] Extend `WorkshopCatalystSessionRecord` with mandatory per-turn `synthesize_turn(...)`, posting one visible message through `post()`.
- [x] Preserve concise specialist summaries in a hidden buffer and best-effort `json.workshop_specialist_trace`; expose them only through the collapsed reasoning/status disclosure.
- [x] Support optional `specialist_model` and `synthesizer_model` `[SYSTEM_CONFIG]` routing without mutating the global model.
- [x] Add complementary Workshop exact-single-sender and Story multi-sender harness coverage.

## E) Implementation gotchas found by tracing the actual call path (2026-07-02)

The original draft of section D assumed a Kernel-style parallel-agents architecture was a straightforward port. Tracing `AICharacterAgent.gd`, `ConversationManager.gd`, and `WorkshopCatalystSessionRecord.gd` surfaced several corrections, documented here so they aren't silently lost.

### E.1) The conversation layer is single-request-at-a-time — true parallelism is not safe to assume
- `ConversationManager.is_busy()` delegates to `api_service.is_request_in_progress()` — a **singular** boolean, not a counter or set of in-flight IDs.
- `ConversationManager.chat()` mutates shared instance state (`_current_thread`) synchronously before awaiting the network response.
- Firing multiple `chat()` calls without awaiting between them (the Godot equivalent of Kernel's `asyncio.gather`) risks corrupting `_current_thread` bookkeeping and the `animate_progress_start/complete` pairing in `AICharacterAgent`, which also assumes one in-flight operation.
- [x] **Decision implemented**: do not attempt concurrent `ConversationManager.chat()` calls for specialist contributions. Use the batched-single-call pattern (section D) instead.
- [ ] Corrected cost/latency accounting: batched-call approach ≈ 1 specialist-batch call + 1 Synthesizer call = **2 sequential LLM round-trips per turn**, independent of specialist count — cheaper and simpler than the original "4 parallel Actor calls" estimate, which relied on a concurrency guarantee the codebase doesn't have.

### E.2) `WorkshopCatalystSessionRecord` already is a partial synthesizer — reuse, don't duplicate
- It already runs its own LLM calls (`conv.chat(prompt, "session_record_synth")`), independent of Director/Actor, with its own throttling (`_PROACTIVE_MIN_TURN_GAP`, `_PROACTIVE_LM_EVERY_N_TURNS`, real-time cooldowns) and its own posting path (`post()` → `StoryState.add_log_entry("Session Record", message)`).
- Today it operates in **periodic observer mode** (comments on the transcript every N turns), not **mandatory per-turn synthesizer mode**.
- [ ] Converting it to per-turn-mandatory mode means the existing throttle constants (turn-gap, real-time cooldown) need explicit re-scoping for the new call site — they were tuned for "occasional proactive observation," not "always synthesize this turn." Do not assume they transfer unchanged.

### E.3) Sequential `weaver_context` vs. independent judgment — an explicit fork, not a detail
- `AICharacterAgent` deliberately runs Actor calls sequentially within a turn and injects `weaver_context` so each subsequent speaker reacts to the prior one — the code comment states this exists "to avoid oblivious parallel monologues."
- Kernel's pattern depends on the opposite: specialists judge **independently** so consensus/disagreement is meaningful.
- [ ] Open decision (see H): if Workshop Catalyst specialists see each other's contributions before the Synthesizer runs, the Synthesizer's "consensus" claim is weaker (anchored, not independent). If they don't, an existing anti-monologue mechanism is deliberately not reused. Resolve explicitly per section D's batched-call design (a single batched call naturally makes this an explicit prompt-level choice, not a per-call architectural one).

### E.4) The existing vote/closure mechanism assumes visible dialogue — needs explicit re-scoping
- Votes today are cast *as dialogue*: an AI character's actual visible line must open with "Yes"/"No" (or `<<YES>>`/`<<NO>>` tokens), parsed by `process_actor_dialogue()` and forwarded to `WorkshopCatalystSessionRecord.record_vote()`.
- Under Society of Minds, specialist contributions are hidden — there is no visible line for this parsing to act on.
- [x] Resolved: specialists do not vote and synthesis cannot create canonical consensus. Existing participant/facilitator-visible `/vote` and `/decide` paths remain authoritative.

### E.5) `AICharacterAgent.gd` will need a change — correcting an earlier over-broad claim
- `DirectorAgent.gd` and `ActorAgent.gd` genuinely do not need to change.
- `AICharacterAgent.gd` (the shared orchestrator autoload, used by all Session Types) **does** need one change: the point where each character's line is posted individually to `StoryState` (its step 5) must branch by Session Type.
- [x] Implemented as one `_finalize_turn()` delegation point using the generic Session Type runtime profile.
- [ ] Corrected "definition of done" language: "no changes to `DirectorAgent.gd` / `ActorAgent.gd`" (precise), not "no changes to shared infrastructure" (was over-broad; `AICharacterAgent.gd` is shared and does change, once, at a single seam).

## F) Architectural guardrails to protect
- [ ] `DirectorAgent.gd` / `ActorAgent.gd` stay genuinely unchanged — only `AICharacterAgent.gd` gets one clean, session-type-dispatched branch point (E.5).
- [ ] `StoryState`'s log schema (`{sender, message}`) stays unchanged — Society of Minds only changes *what* gets appended, never the shape of an entry.
- [ ] Do not attempt concurrent `ConversationManager.chat()` calls until the API layer is verified/upgraded to support multiple in-flight requests (E.1).
- [ ] Raw specialist contributions must be retained somewhere inspectable (Human Agency UX Contract) — commit to Artrhythmetic Store as a trace rather than an ephemeral in-memory buffer.
- [ ] Vote/closure semantics must be explicitly re-scoped for hidden-synthesis mode (E.4), not silently inherited from the visible-dialogue vote mechanism.
- [ ] `story_catalyst` path must be provably untouched — any change to `AICharacterAgent.gd` needs a regression check that visible-ensemble scenarios still run byte-for-byte the same.
- [ ] Session Type ↔ Collection dispatch (B.1) stays generic across both Session Types — do not special-case "only `story_catalyst` has Collections" in code, even though only it uses more than one today.

## G) UI refactoring to anticipate
- [ ] **Character-selection bypass (currently missing entirely)**: `character_options.gd` has zero special-casing for `workshop_catalyst` today — a facilitator can currently pick to "play" one of the four named stakeholders (e.g. Dr. Alice Carter) in the GLP-1 scenario, with the rest AI-controlled. This framing is incompatible with Society of Minds, where specialist roles become hidden internal analysts, not player-selectable personas. Skip character selection entirely for `workshop_catalyst`; the human enters directly as "Facilitator" (a sender role that already exists via `send_as_facilitator`).
- [ ] **Hamburger settings panel tech debt**: `WorkshopCatalystController._build_settings_ui()` builds its entire UI tree in GDScript (`Button.new()`, `Label.new()`, etc.), already inconsistent with the workspace preference for `.tscn`-authored static UI. Decide explicitly whether to migrate to `.tscn` before adding a "Show reasoning" drill-down panel here, rather than defaulting to more code-built UI.
- [ ] **Story log rendering**: no structural change needed (already renders generic `{sender, message}` entries), but sender styling/portrait lookup for "Session Record" vs. multiple named specialists should gracefully degrade to one consistent voice instead of rotating character colors/avatars.
- [ ] **"Show reasoning" drill-down**: needs a concrete UI home — likely a collapsible panel or per-message expandable region next to the Session Record entry, not a new screen.
- [ ] **Session Type / Collection picker**: front-facing flow becomes "choose a Session Type" then, only for Story Catalyst, "choose a Collection" (or scenario grouped by Collection) — Workshop Catalyst skips the second step today since it has one Collection.

## H) Human Agency UX Contract alignment
- [x] Treat each specialist contribution as a "propose" step; the synthesized message is the visible preview and does not commit closure.
- [ ] Any facilitator action that promotes a specialist's raw point directly into the workshop record (bypassing synthesis) must be an explicit, visible action, not silent.
- [ ] Synthesized messages that lead to a captured decision still flow through `ClosureBus` / `closure_substrate_emitter.gd` — the synthesis step changes *how the message is produced*, not the closure/provenance pipeline (subject to the E.4 vote-mechanism re-scoping).

## I) Open decisions (need input before implementation)
- [ ] Final specialist role names/count — keep at 4, or change (no longer tied to reusing a fixed "character slot" infrastructure, since Society of Minds uses a batched call, not N character slots).
- [ ] Named personas (Kernel-style, e.g. "Agent Peirce") vs. plain functional titles (e.g. "Risk & Feasibility Analyst")? Meeting notes lean toward "no gimmicks" — functional titles are the current recommendation, open to revisit.
- [ ] Should the Synthesizer's consensus/tension metadata be user-visible by default (small inline note) or fully hidden behind a "Show reasoning" toggle?
- [ ] Independent specialist judgments vs. sequential/aware-of-each-other framing within the batched call (E.3) — affects how honestly the Synthesizer can claim "consensus."
- [ ] Do specialists "vote" at all under Society of Minds, or does `/vote` (facilitator-only) become the sole vote path (E.4)?
- [ ] Should Synthesizer output route through `WorkshopCatalystSessionRecord.post()` verbatim, or does Session Record become a thin wrapper specifically around Synthesizer output?
- [ ] Timing of the hamburger-panel `.tscn` migration (G) relative to adding the "Show reasoning" drill-down.

---

## Suggested execution order
1. Section A (SessionType renaming) — mechanical, low risk, unblocks everything else.
2. Section B (two Session Types + Collection tier) — content move, regression-tested against existing scenarios.
3. Section C (agent topology switch declared per session type).
4. Section D + E (Society of Minds vertical slice, using the corrected batched-call architecture) — start with a single Workshop Catalyst scenario as smoke test.
5. Section G (UI refactoring), starting with the character-selection bypass since it's a functional gap, not just polish.
6. Section H (UX contract alignment).
7. Resolve section I open decisions as they're hit, not all upfront.

## Definition of done for v0.2
- [ ] A user is asked to choose a "Session Type" (Workshop Catalyst / Story Catalyst), never a "theme" or "mode".
- [ ] Story Catalyst scenarios (former sustainability + cultural_narratives Collections) run unchanged, visible multi-character dialogue intact.
- [ ] A Workshop Catalyst session shows exactly one AI-voiced message per turn in the primary log, attributed to Session Record.
- [ ] The underlying specialist contributions exist and are inspectable (dev-facing at minimum) even though not shown by default.
- [ ] No changes made to `DirectorAgent.gd` / `ActorAgent.gd` logic — `AICharacterAgent.gd` gets exactly one new session-type-dispatched branch point.
- [ ] Character selection is bypassed for Workshop Catalyst sessions; the human enters as Facilitator directly.
- [ ] ScenSyn test harness passes for both session types (existing workshop_catalyst specs + new single-sender assertion).

---

*This is a living planning document capturing decisions from ongoing strategy conversations. Update as decisions are refined; do not treat as frozen spec until items are checked off.*
