# ScenSyn Theme-Based Architecture Refactoring Plan

> **Superseded terminology (2026-07-10):** This historical plan describes the
> former scenario-theme architecture. Runtime organization now uses
> `Session Type → Collection` under `ScenSyn/session_types/` per ADR 0009.
> References below to themes and `scenario_themes/` are retained only as
> implementation history and must not be used as current paths or APIs.

## Overview
Transform ScenSyn from sustainability-coupled to theme-agnostic architecture while improving naming and maintainability. Focus on simplicity, zero redundancy, and comprehensive testing at each phase.

**Status**: In Progress  
**Started**: January 2025  
**Estimated Completion**: 8-12 hours (1-2 days)

---

## PHASE 1: Scenario Loader Refactoring (2-3 hours)

### Task 1.1: Create New ScenarioLoader Class ✅
**File**: Create `IretiOkan/ScenSyn/scripts/core/scenario_loader.gd`
**Action**: 
- Copy `quick_test_scenario2.gd` content
- Rename class to `ScenarioLoader`
- Rename methods: `load_metaprompt()` → `load_scenario()`, etc.
- Improve method signatures and documentation
- Add theme parameter to `load_scenario(scenario_name: String, theme: String = "sustainability")`
**Test**: Instantiate new class and verify it loads existing scenarios

### Task 1.2: Update Global.gd References ✅
**File**: `IretiOkan/ScenSyn/scripts/Global.gd`
**Action**:
- Change `var quick_test_scenario = preload("res://ScenSyn/scripts/quick_test_scenario2.gd").new()`
- To `var scenario_loader = preload("res://ScenSyn/scripts/core/scenario_loader.gd").new()`
- Rename `get_quick_test_scenario()` → `get_scenario_loader()`
- Update all internal calls to use new method names
**Test**: Verify Global.gd loads without errors

### Task 1.3: Update All Script References ✅
**Files**: All files using `quick_test_scenario`
- `character_options.gd`
- `character_options_2.gd` 
- `game_mode_popup.gd`
- `networkscripts/Network.gd`
**Action**: Replace `quick_test_scenario` with `scenario_loader` and update method calls
**Test**: Load each scene/script to verify no errors

### Task 1.4: Integration Testing ✅
**Action**: 
- Start ScenSyn application
- Load each existing scenario (sustainability themes)
- Verify character generation works
- Test multiplayer scenario loading
- Confirm all existing functionality works identically
**Success Criteria**: No functionality changes, all existing features work

### Task 1.5: Remove Legacy quick_test_scenario2.gd ✅
**Action**: Delete `quick_test_scenario2.gd` and `.uid` files after successful testing
**Test**: Full application test to ensure nothing references old files

---

## PHASE 2: Theme-Based Folder Structure (1-2 hours)

### Task 2.1: Create Theme Folder Structure ✅
**Action**: Create folders:
```
IretiOkan/ScenSyn/scenario_themes/
├── sustainability/
│   └── scenarios/
└── cultural_narratives/
    └── scenarios/
```

### Task 2.2: Move Scenario Files ✅
**Action**: 
- **Copy** all files from `scenario_metaprompts/` to `scenario_themes/sustainability/scenarios/`
- Move `ireti_okan_awaiting_an_awakening.txt` to `scenario_themes/cultural_narratives/scenarios/`
- Update `scenario_loader.gd` to use theme-aware path: 
  Historical loader path concatenation (removed by the Session Type migration).
**Test**: Verify all sustainability scenarios still load correctly

### Task 2.3: Update Available Scenarios List ✅
**File**: `Global.gd`
**Action**: 
- Add `var current_theme: String = "sustainability"`
- Create theme-specific scenario lists (`available_scenario_names`, `cultural_scenario_names`)
- Update scenario validation to auto-detect theme based on scenario name
**Test**: Scenario selection UI works with new paths

### Task 2.4: Remove Old scenario_metaprompts Folder ✅
**Action**: Delete `scenario_metaprompts/` folder after confirming new theme structure works
**Test**: Full scenario loading test across all sustainability scenarios

---

## PHASE 3: Theme Component Extraction (3-4 hours)

### Task 3.1: Create Base MetapromptManager ✅
**File**: Create `IretiOkan/ScenSyn/scripts/core/base_metaprompt_manager.gd`
**Action**:
- Extract theme-agnostic methods from current `metaprompt_manager.gd`
- Create base class with virtual methods for theme-specific behavior
- Keep narrative phase instructions (they're generic)
**Test**: Instantiate base class and verify core functionality

### Task 3.2: Create Sustainability MetapromptManager ✅
**File**: Create `IretiOkan/ScenSyn/scenario_themes/sustainability/metaprompt_manager_sustainability.gd`
**Action**:
- Extend base class
- Move sustainability keywords, concepts, and specific prompting logic
- Implement theme-specific methods
**Test**: Compare output with original metaprompt_manager for identical results

### Task 3.3: Update Theme Loading in Global.gd ✅
**File**: `Global.gd`
**Action**:
- Create `get_metaprompt_manager_for_theme()` method that returns theme-appropriate manager
- Simple match statement based on `current_theme`
- Update initialization to use theme-aware manager
**Test**: Verify AI agents receive correct metaprompts for sustainability theme

### Task 3.4: Move Sustainability Tracking Components ✅
**Files**: 
- Move `sustainability_tracker.gd` → `scenario_themes/sustainability/sustainability_tracker.gd`
- Move `sustainability_meter.gd` → `scenario_themes/sustainability/sustainability_meter.gd`
- Move `sustainability_integration_system.gd` → `scenario_themes/sustainability/sustainability_integration_system.gd`
- Move `limbo_tasks/sustainability_alert_task.gd` → `scenario_themes/sustainability/sustainability_alert_task.gd`
**Action**: Update all path references in importing scripts
**Test**: Sustainability metrics and UI work identically

### Task 3.5: Create Theme Factory in game_session.gd ✅
**File**: `game_session.gd`
**Action**:
- Replace direct sustainability system instantiation with theme-aware loading
- Simple match statement to load appropriate theme components
- Maintain same interface for theme-agnostic core functionality
**Test**: Game sessions work identically for sustainability themes

---

## PHASE 4: Cultural Narratives Theme Implementation (2-3 hours)

### Task 4.1: Create Cultural MetapromptManager ⬜
**File**: Create `themes/cultural_narratives/metaprompt_manager_cultural.gd`
**Action**:
- Extend base metaprompt manager
- Implement cultural narrative-specific prompting logic
- Remove sustainability-specific keywords/concepts
**Test**: Instantiate and verify basic functionality

### Task 4.2: Create Cultural Tracking System ⬜
**File**: Create `themes/cultural_narratives/cultural_tracker.gd`
**Action**:
- Simple progress tracking (no complex metrics initially)
- Track story elements relevant to cultural narratives
- Basic interface compatible with core systems
**Test**: Verify integration with game session

### Task 4.3: Add Ireti Okan Scenarios ⬜
**Action**:
- Move `ireti_okan_awaiting_an_awakening.txt` to `themes/cultural_narratives/scenarios/`
- Add to cultural theme scenario list
- Test loading and character generation
**Test**: Ireti Okan scenario loads and runs

### Task 4.4: Theme Switching Implementation ⬜
**File**: Update UI and Global.gd
**Action**:
- Add simple theme selection mechanism
- Update `current_theme` variable
- Test switching between sustainability and cultural themes
**Test**: Both theme types work correctly

### Dramaturgy Matrix Schema (NEW)
- Each scenario that wants matrix-driven guidance must add a `[DRAMATURGY_MATRIX]` section to its `.txt`.
- Required keys:
  - `type`: currently `character_table` (future types can plug in later).
  - `file`: CSV filename relative to the scenario folder (or full `res://` path).
  - `key_column`: column in the CSV that contains the display name (e.g. `Element`).
  - `field_columns`: comma-separated list of columns to expose (e.g. `Primary Components, Symbolic Function`).
- Optional keys:
  - `special_speakers`: additional non-character voices (e.g. `Narrator`, `The Child`) to register automatically.
  - `stage_manager_key`: which CSV entry should drive stage-manager guidance.
- CSV formatting expectations:
  - UTF-8 with header row; quote content that contains commas.
  - First column should match the `key_column` so aliases like `Name (Alias)` can be stripped automatically.
  - Additional columns are preserved and exposed to the metaprompt manager exactly as written.

---

## PHASE 5: Legacy Cleanup & Final Testing (1-2 hours)

### Task 5.1: Remove Debug/Legacy Files ✅
**Action**: Delete all temporary and legacy files:
- `quick_test_scenario.gd` (original placeholder)
- Any backup files created during migration
- Old `metaprompt_manager.gd` (after sustainability version confirmed working)
- Test files created during refactoring
**Test**: Full application test to ensure no broken references

### Task 5.2: Remove Temporary Compatibility Code ✅
**Action**: 
- Remove any fallback mechanisms added during migration
- Clean up temporary variables or methods
- Remove debug print statements added during refactoring
**Test**: Code review to ensure clean, production-ready state

### Task 5.3: Comprehensive Integration Testing ✅
**Action**:
- Test all sustainability scenarios end-to-end
- Test cultural narrative scenarios end-to-end  
- Test theme switching
- Test multiplayer with both themes
- Verify evaluation system works with both themes
**Success Criteria**: All functionality works, no performance degradation
**Note**: Minor linting warnings exist but don't affect functionality

### Task 5.4: Code Review & Documentation ✅
**Action**:
- Review all modified files for code quality
- Update any inline documentation
- Verify naming conventions are consistent
- Confirm no dead code remains
**Success Criteria**: Clean, maintainable codebase ready for future development

---

## PHASE 6: Workshop Catalyst Theme Implementation (Workshop / Facilitation Mode) (4-8 hours)

**Goal**: Add a new theme, `workshop_catalyst`, that provides facilitation-first flows (agenda/timeboxing, structured buckets, note-taking) **without hardcoding any specific scenario** and **without regressing existing sustainability/cultural themes**.

### Guardrails (must-follow)
- [ ] **Do not bloat existing large scripts**: keep new logic in new theme-scoped scripts (avoid growing `game_session.gd` further unless absolutely necessary).
- [ ] **Script size policy (hard threshold)**: follow the canonical project-wide policy in `addons/.cursor/rules/project-architecture-rules.mdc` (soft 800, hard 900). If a file approaches this threshold, split immediately into smaller theme-scoped modules (e.g. `workshop_controller.gd`, `workshop_state.gd`, `workshop_packet_loader.gd`).
- [ ] **GDScript naming rules**: avoid shadowing (`name`, `visible`, `mode`, `position`, `rotation`, `scale`, `log`, `call`, `signal`) and use `_node` suffix for UI node locals (see `.cursorrules`).
- [ ] **No scenario hardcoding**: all workshop behavior must work with any scenario under `scenario_themes/workshop_catalyst/scenarios/`.
- [ ] **Session-Type-gated behavior only**: all new UI/state/timers activate only when `Global.current_session_type == "workshop_catalyst"`.

### Task 6.1: Create theme folder structure (new theme scaffold)
- [ ] Create folder `ScenSyn/scenario_themes/workshop_catalyst/`
- [ ] Create subfolder `ScenSyn/scenario_themes/workshop_catalyst/scenarios/`
- [ ] Add `ScenSyn/scenario_themes/workshop_catalyst/metaprompt_manager_workshop_catalyst.gd`
- [ ] Add at least one minimal scenario file in `.../scenarios/` for smoke-testing

### Task 6.2: Wire theme into `Global.gd` (theme routing)
- [ ] Add `"workshop_catalyst"` case to `get_metaprompt_manager_for_theme()`
- [ ] Add `workshop_catalyst_scenario_names` list (like `available_scenario_names`, `cultural_scenario_names`)
- [ ] Update `set_current_scenario_metaprompt()` to map selected scenario name → theme `"workshop_catalyst"`
- [ ] **Test**: selecting a workshop scenario swaps metaprompt manager and loads scenario via `ScenarioLoader` with the correct theme path

### Task 6.3: Implement `WorkshopCatalyst` metaprompt manager (theme-only behavior)
- [ ] Create `metaprompt_manager_workshop_catalyst.gd` extending `BaseMetapromptManager`
- [ ] Implement facilitation “Catalyst” stance (synthesize, mediate, highlight synergies, propose next steps)
- [ ] Add structured “bucket update” contract to the prompt:
  - [ ] ideas
  - [ ] constraints
  - [ ] risks
  - [ ] decisions
  - [ ] open_questions
  - [ ] next_steps
- [ ] Define a stable, machine-readable output convention for bucket updates (must be resilient to minor LLM drift)
- [ ] Ensure this manager remains scenario-agnostic (reads optional workshop packet/agenda sections if present, otherwise degrades gracefully)

### Task 6.4: Add theme-gated Workshop state (persistent, scenario-agnostic)
- [ ] Add a new `StoryState` block for workshop state (e.g. `state["workshop_catalyst"] = {...}`) that exists only under the workshop theme
- [ ] Proposed minimal fields:
  - [ ] `day` (int)
  - [ ] `session_label` (String)
  - [ ] `agenda` (Array; parsed from scenario packet)
  - [ ] `current_stage_index` (int)
  - [ ] `stage_started_at_unix` (int)
  - [ ] `stage_duration_sec` (int)
  - [ ] `is_note_only_next_input` (bool)
  - [ ] `buckets` (Dictionary matching the bucket schema)
- [ ] **Test**: save/load story logs preserves workshop state (no crashes when absent)

### Task 6.5: Workshop packet ingestion (scenario-agnostic)
- [ ] Define optional scenario sections for workshop scenarios (parsed automatically by `ScenarioLoader`):
  - [ ] `[WORKSHOP_PACKET]` (brief / world notes / facilitation constraints)
  - [ ] `[WORKSHOP_AGENDA]` (agenda data; inline JSON or file reference)
- [ ] Implement a small loader that resolves agenda file references using scenario `_base_dir` metadata (no absolute path hardcoding)
- [ ] **Test**: workshop scenario can ship packet + agenda and the theme reads them correctly

### Task 6.6: Agenda-driven session flow (timeboxing + stage controls)
- [ ] Implement a dedicated theme-scoped controller script (e.g. `workshop_controller.gd`) to avoid adding more complexity to `game_session.gd`
- [ ] Features:
  - [ ] Start stage / pause / resume
  - [ ] Advance stage
  - [ ] Add time (+5/+10 minutes)
  - [ ] Optional “auto stage wrap-up prompt” behavior when timer ends
- [ ] **Test**: stage progression updates workshop state; no impact in other themes

### Task 6.7: Minimal UI hooks (theme-gated)
- [ ] Add workshop controls to the existing settings panel only when workshop theme is active:
  - [ ] Display current day/session/stage
  - [ ] Countdown timer
  - [ ] Buttons: start/pause/next/+5/+10
  - [ ] Toggle: “Note-only next message”
- [ ] Ensure UI node locals follow naming rules (`*_node`) and avoid forbidden identifiers

### Task 6.8: Note-only (“acknowledge without responding”) mode
- [ ] Implement note-only flag (`is_note_only_next_input`) in workshop state
- [ ] When active:
  - [ ] Record the user message into story log and/or workshop state
  - [ ] Produce strict ACK behavior (either skip AI call, or force minimal ACK response via metaprompt)
- [ ] **Test**: note-only doesn’t derail session and doesn’t contaminate narrative prompts in other themes

### Task 6.9: Export / artifacts (reuse story log pipeline)
- [ ] Add workshop summary export (buckets + decisions + next_steps) to a standalone file alongside story logs
- [ ] Ensure exports are optional and do not change existing story log formats unless versioned/guarded

### Task 6.10: Acceptance + regression tests (must-pass)
- [ ] Workshop scenario loads and runs end-to-end
- [ ] Sustainability scenarios run unchanged
- [ ] Cultural narratives scenarios run unchanged
- [ ] Multiplayer scenario selection still works
- [ ] No new warnings/errors introduced in unrelated themes

---

## Risk Mitigation Strategy

### Backup Strategy
- Create git branch before starting: `git checkout -b scensyn-refactoring`
- Commit after each completed phase
- Keep original files until final testing complete

### Testing Protocol
- **After each task**: Specific functionality test
- **After each phase**: Full application test
- **Before cleanup**: Comprehensive end-to-end test

### Rollback Plan
- If any phase fails: revert to previous commit
- If critical issues found: temporary disable new features, fix, re-enable

---

## Success Metrics

1. **Zero Functionality Loss**: All existing features work identically
2. **Clean Architecture**: Theme-specific code clearly separated
3. **Easy Extension**: New themes can be added in < 1 day
4. **Maintainable Code**: No redundancy, clear naming, simple structure
5. **Performance**: No degradation in loading or runtime performance

---

## Progress Tracking

**Status**: ✅ COMPLETED  
**Completed Tasks**: 20/20  
**Final Status**: Theme-based architecture successfully implemented  
**Architecture**: Clean separation between sustainability and cultural narrative themes

---

## Change Log
- **2025-01-XX**: Initial plan created
- **2025-01-XX**: Phase 1 started

---

*This file will be updated as tasks are completed. Use ✅ for completed tasks, ⬜ for pending tasks.*

## Updates Since Last Revision (October 2025)

- Deterministic Director (no LLM planning): DirectorAgent now computes `{turn_outcome, scene_aim, plan[{character, move_id, addressed_to}]}` locally to eliminate LLM JSON/structure errors.
- Actor prompt/validator tightened: connective-start, ≤18 words, no opening question, second-person addressing, stage-directions blocked with a single corrective reprompt.
- The Child metric coupling: percentage reacts to recent dialogue signals and biases by Director `turn_outcome`; prevents contradictory cues and nudges beats.
- Per-turn diagnostics (temporary): logs UI vs ConversationManager model names and instance IDs for model-sync verification.
- Model selection architecture: ScenSyn gets an app-level model selector in the hamburger settings that calls SynTree AIModelManager APIs; optional per-turn override supported; Global listens to `model_changed`.
- Hamburger menu UI: panel converted to PanelContainer → MarginContainer → VBox; autosizes to content with padding; controls placed under a clean VBox; right-edge clipping resolved with container docking and padding.

> Note: Pre-existing linter warnings in `game_session.gd` remain; no functional changes were made there to avoid risk. Per-turn diagnostics will be removed once stability is confirmed.
