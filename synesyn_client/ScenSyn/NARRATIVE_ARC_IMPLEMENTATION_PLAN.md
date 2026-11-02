# Narrative Arc & Unified Evaluation Implementation Plan

## Overview
Transform ScenSyn from endless crisis loops into structured narrative arcs with proper story beats, while unifying the evaluation system to measure improvements.

**Status**: In Progress  
**Started**: December 2024  
**Estimated Completion**: 6 days  

---

## PHASE 1: Story Arc Foundation (2 days)

### Task 1.1: Extend StoryStateManager ✅
**File**: `ScenSyn/scripts/core/story_state_manager.gd`
- [x] Add narrative phase constants: `setup`, `incident`, `rising`, `climax`, `resolution`, `ended`
- [x] Add fields: `current_narrative_phase`, `turn_in_phase`, `phase_transition_readiness`
- [x] Add methods: `set_narrative_phase()`, `get_phase_readiness()`, `increment_phase_turn()`
- [x] Update `advance_turn()` to call `increment_phase_turn()`
- [x] Add signal: `narrative_phase_changed(new_phase)`

### Task 1.2: Create Phase Transition Logic ✅
**File**: `ScenSyn/scripts/limbo_tasks/advance_story_phase_task.gd`
- [x] Create new LimboAI task extending `BTTask`
- [x] Implement text-based transition detection (keywords, sentiment analysis)
- [x] Add phase-specific exit criteria:
  - `setup → incident`: 3 turns OR first dilemma injected
  - `incident → rising`: sustainability score < 0.4 OR unresolved_challenges > 0
  - `rising → climax`: keywords ("decide", "vote", "agreement") OR player choice logged
  - `climax → resolution`: 1 turn after climax narration
  - `resolution → ended`: 2 turns with no new challenges OR narrator summary
- [x] Include 2-turn grace period before forced transitions
- [x] Only execute on server (multiplayer safety)
- [x] Add RPC handler for client-suggested transitions

### Task 1.3: Update Narrator Behavior Tree ✅
**File**: `ScenSyn/scripts/agents/narrator_agent.gd`
- [x] Add `AdvanceStoryPhaseTask` node to existing tree (programmatically)
- [x] Set appropriate priority (after existing intent determination)
- [x] Connect to blackboard for state access
- [x] Add RPC handler integration for client suggestions

---

## PHASE 2: Prompt Integration (1 day)

### Task 2.1: Phase-Aware Prompting ✅
**File**: `ScenSyn/scripts/metaprompt_manager.gd`
- [x] Add `_narrative_phase_instructions` dictionary:
  ```gdscript
  var _narrative_phase_instructions = {
      "setup": "Introduce setting, roles and stakes. Foreshadow conflict but do NOT resolve anything yet.",
      "incident": "Present the central crisis that forces characters to act.",
      "rising": "Escalate complications, highlight trade-offs, opposing viewpoints.",
      "climax": "Drive toward a decisive choice or turning point. Tension high.",
      "resolution": "Describe consequences, reflect on goals, provide closure."
  }
  ```
- [x] Modify `get_game_session_metaprompt()` to prepend current phase instruction
- [x] Add fallback instruction for undefined phases

### Task 2.2: Sustainability Integration ✅
**File**: `ScenSyn/scripts/game_session.gd`
- [x] Modify sustainability trigger logic in `_trigger_proactive_character_action()`
- [x] Change from crisis injection to phase-appropriate content injection
- [x] Ensure sustainability becomes phase content, not phase driver
- [x] Add `_get_phase_appropriate_context()` helper method

### Task 2.3: Client-Suggested Transitions ✅
**File**: `ScenSyn/scripts/game_session.gd`
- [x] Add RPC: `suggest_phase_transition(suggested_phase, reason)`
- [x] Server validates client suggestions in `AdvanceStoryPhaseTask`
- [x] Add client helper method: `suggest_narrative_phase_transition()`

---

## PHASE 3: Narrator Re-enablement (½ day)

### Task 3.1: Activate Narrator Agent ✅
**File**: `ScenSyn/scripts/agents/narrator_agent.gd`
- [x] Remove temporary disable line in `_maybe_generate_narration()`
- [x] Add phase-aware narration control (don't narrate ended stories)
- [x] Add `_map_phase_to_intent()` method for phase-specific intents

### Task 3.2: Phase-Specific Narrator Intents ✅
**File**: `ScenSyn/scripts/limbo_tasks/determine_narrator_intent_task.gd`
- [x] Add new intents: `"INCIDENT_BEAT"`, `"RISING_TENSION"`, `"CLIMAX_BEAT"`, `"RESOLUTION_BEAT"`
- [x] Map intents to narrative phases
- [x] Update narrator intent determination to use narrative phase context
- [x] Maintain backward compatibility with legacy phase system

---

## PHASE 4: End-of-Session Handling (½ day)

### Task 4.1: Session Completion Logic ✅
**File**: `ScenSyn/scripts/game_session.gd`
- [x] Add check in `process_ai_response()` for `current_narrative_phase == "ended"`
- [x] Disable input field when session ends
- [x] Add session completion UI with sustainability score summary
- [x] Add `start_new_scenario()` method for future "Start New Scenario" button
- [x] Add `_check_session_completion()`, `_handle_session_ended()`, `_show_session_completion_ui()`

### Task 4.2: UI Feedback ✅
**File**: `ScenSyn/scripts/game_session.gd`
- [x] Add phase display label (created programmatically)
- [x] Connect to `StoryState.narrative_phase_changed` signal
- [x] Position unobtrusively (top-right corner)
- [x] Show phase transitions in chat with system messages
- [x] Display current phase and turn count in phase

---

## PHASE 5: Unified Evaluation System (1.5 days) ✅

### Task 5.1: Create Unified Controller ✅
**File**: `scensyn_agent_assembly/UnifiedEvaluationController.gd`
- [x] Merge `SimulatedPanelController` and `MetaCriticAnalyzer` logic
- [x] Single workflow: load transcript → meta-critic analysis → persona evaluations → save results
- [x] Implement progress tracking across both phases
- [x] Add error handling and fallback mechanisms

### Task 5.2: Create Unified Scene ✅
**File**: `ScenSyn/scenes/UnifiedEvaluationController.tscn`
- [x] Copy UI elements from existing controllers
- [x] Single "Run Evaluation" button
- [x] Progress bar showing overall completion
- [x] Status label for current operation
- [x] Phase indicator for current evaluation step

### Task 5.3: Enhanced Evaluation Criteria ✅
**Files**: Update prompts in `UnifiedEvaluationController.gd`
- [x] Add narrative arc questions to persona questionnaire:
  - Story progression clarity (1-5)
  - Conflict resolution satisfaction (1-5)
  - Pacing quality (1-5)
  - Closure satisfaction (1-5)
- [x] Update meta-critic prompt to assess story structure
- [x] Add narrative coherence detection
- [x] Phase-aware transcript summarization

### Task 5.4: Remove Old Evaluation System ⬜
- [ ] Delete `scensyn_agent_assembly/SimulatedPanelController.gd` and scene
- [ ] Delete `scensyn_agent_assembly/hybrid_panel/MetaCriticAnalyzer.gd` and scene  
- [ ] Update any references to point to new unified system

### Implementation Details:
- **456-line UnifiedEvaluationController**: Complete merger of both evaluation workflows
- **Enhanced Questionnaire**: Added 4 new narrative structure questions (10-13)
- **Meta-Critic Integration**: Added narrative_structure analysis section
- **Phase-Aware Summaries**: Groups transcript content by narrative phases
- **Progress Tracking**: 5-phase workflow with detailed progress indicators
- **Error Handling**: Comprehensive error handling and fallback mechanisms

---

## PHASE 6: Testing & Validation (1 day)

### Task 6.1: Unit Testing ⬜
- [ ] Test phase transitions with sample scenarios
- [ ] Verify multiplayer synchronization of phase changes
- [ ] Test narrator conflict resolution
- [ ] Validate end-of-session behavior

### Task 6.2: Integration Testing ⬜
- [ ] Run complete game sessions with phase system enabled
- [ ] Compare evaluation scores before/after implementation
- [ ] Test unified evaluation system with existing transcripts
- [ ] Verify backwards compatibility

### Task 6.3: Evaluation Validation ⬜
- [ ] Run unified evaluation on sample stories from `story_samples_evaluation`
- [ ] Compare results with previous two-step process
- [ ] Verify new narrative arc metrics capture improvements
- [ ] Document evaluation criteria changes

### Task 6.4: Generic Phase Timing Validation ⬜
- [ ] Test phase transitions work across different scenario types
- [ ] Ensure timing works for both short (energy_futures) and complex (windmill_syndrome) scenarios
- [ ] Validate phase progression feels natural without scenario-specific tuning

---

## PHASE 7: Documentation & Cleanup (½ day)

### Task 7.1: Code Documentation ⬜
- [ ] Add docstrings to new phase transition logic
- [ ] Document narrative phase flow in comments
- [ ] Update existing comments referencing old behavior

### Task 7.2: User Documentation ⬜
- [ ] Create brief guide explaining narrative phases
- [ ] Document unified evaluation workflow
- [ ] Add troubleshooting section for common issues

---

## Success Metrics

### Narrative Improvements
- [ ] Sessions have clear beginning, middle, end structure
- [ ] Evaluation scores for "narrative believability" increase from 3 to 4+
- [ ] Reduction in "endless crisis" complaints
- [ ] Presence of satisfying resolution in session logs

### Technical Achievements
- [ ] Phase transitions work smoothly in multiplayer
- [ ] No conflicts between narrator and main game flow
- [ ] Unified evaluation runs without manual intervention
- [ ] Backwards compatibility maintained

### Sustainability Focus
- [ ] Sustainability themes integrated into each phase appropriately
- [ ] No reduction in sustainability focus despite structural changes
- [ ] Improved coherence of sustainability discussions

---

## Implementation Notes

### Code Quality Requirements
- **No regression**: All existing functionality must continue working
- **No redundancy**: Avoid duplicating existing code patterns
- **No code duplication**: Reuse existing infrastructure where possible
- **Minimal complexity**: Keep solutions simple and maintainable
- **Bug prevention**: Thorough testing before marking tasks complete
- **Maintainability**: Clear, documented code that follows existing patterns

### Design Decisions Made
- **Generic phase timing**: No modification of scenario metaprompt files
- **Manual evaluation**: Unified system remains manually triggered
- **Client suggestions**: Clients can suggest phase transitions to server
- **Complete replacement**: Old two-step evaluation system will be removed
- **No override commands**: Experience matches actual player experience

### Key Files Modified
- `ScenSyn/scripts/core/story_state_manager.gd`
- `ScenSyn/scripts/limbo_tasks/advance_story_phase_task.gd` (new)
- `ScenSyn/scripts/metaprompt_manager.gd`
- `ScenSyn/scripts/game_session.gd`
- `ScenSyn/scripts/agents/narrator_agent.gd`
- `scensyn_agent_assembly/UnifiedEvaluationController.gd` (new)

### Progress Tracking
**Started**: December 2024  
**Current Phase**: Phase 6 - Testing & Validation  
**Completed**: Phases 1-5 (Story Arc Foundation, Prompt Integration, Narrator Re-enablement, End-of-Session Handling, Unified Evaluation System)  
**Next Milestone**: Complete testing and validation  
**Estimated Days Remaining**: 1.5

---

## Change Log
- **2024-12-XX**: Initial plan created
- **2024-12-XX**: Clarified scenario files and client suggestions
- **2024-12-XX**: Plan saved to implementation file

---

*This file will be updated as tasks are completed. Use ✅ for completed tasks, ⬜ for pending tasks.* 