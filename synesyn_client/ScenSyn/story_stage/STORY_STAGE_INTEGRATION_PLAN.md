# ScenSyn + story_stage Integration Implementation Plan

> **Historical.** The original plan for bringing the stage into ScenSyn; its `IretiOkan/`
> paths come from the project it was written in. The stage has since become the
> host-driven addon `addons/story_stage/` (ADR 0029), and the standalone
> visual-novel mode this plan adapted (`SceneManager`, dialogue files, title screen)
> has been removed. This folder now holds only ScenSyn's scenario art.

## Overview
This plan integrates story_stage's polished visual novel presentation layer with ScenSyn's AI-driven narrative engine while maintaining all existing functionality and architecture.

## Core Principles
- **No Regression**: All existing ScenSyn functionality must remain intact
- **Parallel Systems**: Story Log and visual presentation run simultaneously
- **No Code Duplication**: Reuse existing ScenSyn systems where possible
- **Clean Architecture**: Follow existing ScenSyn directory structure and patterns
- **No Hardcoding**: Remove phoenix/trucy/apollo references - use dynamic system
- **Future-Proof**: Design for syntree_voice integration

---

## Phase 1: Foundation & Architecture Setup

### Task 1.1: Create Core Integration Components
**Location**: `IretiOkan/ScenSyn/scripts/core/`
- [ ] Create `StoryStageAdapter.gd` - Converts AI responses to story_stage format
- [ ] Create `VisualPresentationManager.gd` - Manages story_stage UI integration
- [ ] Add integration hooks to existing `story_state_manager.gd`

### Task 1.2: Setup Fallback Sprite System
**Location**: `IretiOkan/ScenSyn/story_stage/sprites/`
- [ ] Create `_fallback/` directory structure with all animation folders:
  - `idle/`, `talking/`, `happy-idle/`, `happy-talking/`, `confident-idle/`, `confident-talking/`
- [ ] Remove hardcoded phoenix/trucy/apollo references from Character.gd
- [ ] Implement dynamic character sprite discovery system

### Task 1.3: Enhance Character System
**Location**: `IretiOkan/ScenSyn/story_stage/scripts/`
- [ ] Modify `Character.gd` to support dynamic character registration
- [ ] Add `register_scensyn_character()` method
- [ ] Implement sprite auto-discovery with fallback system
- [ ] Add voice profile support for future syntree_voice integration

---

## Phase 2: UI Integration Layer

### Task 2.1: Adapt Dialog UI for ScenSyn
**Location**: `IretiOkan/ScenSyn/story_stage/scripts/`
- [ ] Enhance `dialog_ui.gd` with ScenSyn integration hooks
- [ ] Add support for dynamic character switching
- [ ] Implement emotion/expression mapping from AI responses
- [ ] Add voice system integration points (for future syntree_voice)

### Task 2.2: Create ScenSyn-Compatible Scene Manager
**Location**: `IretiOkan/ScenSyn/story_stage/scripts/`
- [ ] Modify `SceneManager.gd` to work with ScenSyn's phase system
- [ ] Integrate with existing ScenSyn transition management
- [ ] Remove dependency on static scene files

### Task 2.3: Adapt Character Sprite System
**Location**: `IretiOkan/ScenSyn/story_stage/scripts/`
- [ ] Enhance `character_sprite.gd` for dynamic character loading
- [ ] Implement expression mapping from AI emotional context
- [ ] Add fallback handling for missing sprites

---

## Phase 3: Core Integration Implementation

### Task 3.1: Implement StoryStageAdapter
**Location**: `IretiOkan/ScenSyn/scripts/core/StoryStageAdapter.gd`
- [ ] Convert AI response format to story_stage dialogue format
- [ ] Extract speaker information from ScenSyn character data
- [ ] Parse emotional context for character expressions
- [ ] Handle scene/location changes from AI narrative descriptions
- [ ] Implement robust error handling and validation

### Task 3.2: Create Visual Presentation Manager
**Location**: `IretiOkan/ScenSyn/scripts/core/VisualPresentationManager.gd`
- [ ] Coordinate between ScenSyn AI responses and story_stage UI
- [ ] Manage character registration from ScenSyn character setup
- [ ] Handle parallel Story Log and visual presentation streams
- [ ] Integrate with existing conversation management system

### Task 3.3: Integrate with Conversation Management
**Location**: `IretiOkan/ScenSyn/scripts/conversation_management_system.gd`
- [ ] Add hooks for visual presentation without affecting existing flow
- [ ] Ensure AI responses flow to both Story Log and story_stage UI
- [ ] Maintain existing multiplayer synchronization
- [ ] Preserve all current conversation features

---

## Phase 4: ScenSyn System Integration

### Task 4.1: Character Setup Integration
**Location**: `IretiOkan/ScenSyn/scripts/game_session.gd`
- [ ] Add character registration calls during scenario initialization
- [ ] Register all ScenSyn characters with story_stage system at game start
- [ ] Ensure character data includes sprite discovery information
- [ ] Handle character updates during gameplay

### Task 4.2: Story State Integration
**Location**: `IretiOkan/ScenSyn/scripts/core/story_state_manager.gd`
- [ ] Add visual presentation state tracking
- [ ] Integrate with story_stage scene transitions
- [ ] Maintain synchronization between AI state and visual presentation
- [ ] Handle narrative phase changes in visual system

### Task 4.3: Phase Management Integration
**Location**: `IretiOkan/ScenSyn/scripts/phase_management_system.gd`
- [ ] Connect phase transitions to story_stage visual effects
- [ ] Update visual presentation during narrative phase changes
- [ ] Maintain existing phase management functionality

---

## Phase 5: UI Scene Setup & Configuration

### Task 5.1: Create Integration Scene
**Location**: `IretiOkan/ScenSyn/scenes/`
- [ ] Create `story_stage_integration.tscn` scene
- [ ] Include story_stage dialogue UI components
- [ ] Configure for ScenSyn's multiplayer architecture
- [ ] Ensure compatibility with existing scene structure

### Task 5.2: Modify Existing ScenSyn Scenes
**Location**: `IretiOkan/ScenSyn/scenes/`
- [ ] Update `chat_system.tscn` to include story_stage presentation layer
- [ ] Maintain existing UI functionality alongside new visual presentation
- [ ] Ensure proper layering and UI hierarchy
- [ ] Test with existing themes and scenarios

### Task 5.3: Configure Scene Transitions
**Location**: `IretiOkan/ScenSyn/story_stage/scripts/SceneManager.gd`
- [ ] Remove static scene references
- [ ] Integrate with ScenSyn's dynamic scene management
- [ ] Ensure smooth transitions between AI-generated content
- [ ] Maintain existing transition effects

---

## Phase 6: Testing & Validation

### Task 6.1: Unit Testing
- [ ] Test StoryStageAdapter with various AI response formats
- [ ] Validate character sprite discovery and fallback systems
- [ ] Test dynamic character registration
- [ ] Verify parallel Story Log and visual presentation

### Task 6.2: Integration Testing
- [ ] Test complete AI response → visual presentation flow
- [ ] Validate character switching during conversations
- [ ] Test scene transitions with AI-generated content
- [ ] Ensure no regression in existing ScenSyn functionality

### Task 6.3: Scenario Testing
- [ ] Test with different ScenSyn themes and scenarios
- [ ] Validate multiplayer functionality with visual presentation
- [ ] Test character sprite fallback system
- [ ] Verify Story Log system continues working unchanged

---

## Phase 7: Cleanup & Documentation

### Task 7.1: Remove Reference Characters
- [ ] Remove phoenix/trucy/apollo sprite folders
- [ ] Clean up any remaining hardcoded character references
- [ ] Ensure system works with arbitrary character names
- [ ] Test fallback system thoroughly

### Task 7.2: Code Cleanup
- [ ] Remove unused story_stage components not needed for integration
- [ ] Optimize sprite loading and caching
- [ ] Clean up any temporary or debug code
- [ ] Ensure consistent coding style with ScenSyn

### Task 7.3: Documentation Updates
- [ ] Update integration documentation
- [ ] Document character sprite directory conventions
- [ ] Create developer guide for adding character sprites
- [ ] Document fallback system usage

---

## Technical Requirements

### Directory Structure Compliance
```
IretiOkan/ScenSyn/
├── scripts/
│   ├── core/                     # Core integration components
│   │   ├── StoryStageAdapter.gd
│   │   └── VisualPresentationManager.gd
│   └── [existing structure]
├── story_stage/                  # Visual presentation components
│   ├── sprites/
│   │   ├── _fallback/           # Generic placeholder sprites
│   │   └── [dynamic character folders]
│   ├── scripts/                 # Adapted story_stage scripts
│   └── scenes/                  # story_stage UI scenes
└── scenes/                      # Integration scenes
```

### Key Integration Points
1. **AI Response Processing**: conversation_management_system.gd
2. **Character Registration**: game_session.gd scenario initialization
3. **Visual Presentation**: New VisualPresentationManager
4. **Story State Sync**: story_state_manager.gd
5. **Phase Management**: phase_management_system.gd

### Future Compatibility
- **syntree_voice Integration**: Voice system hooks in dialog_ui.gd
- **Character Expansion**: Dynamic sprite discovery system
- **Theme Support**: Integration with existing ScenSyn theme system
- **Multiplayer**: Maintain existing network synchronization

---

## Success Criteria
- [ ] All existing ScenSyn functionality preserved
- [ ] Visual novel presentation enhances user experience
- [ ] Story Log system continues unchanged
- [ ] Character sprites load dynamically with fallback
- [ ] No performance regression
- [ ] Clean, maintainable code architecture
- [ ] Future-ready for voice integration

---

## Notes
- This integration maintains ScenSyn as the primary narrative engine
- story_stage provides presentation layer only
- All AI-driven features remain in ScenSyn core
- Implementation should be incremental and testable at each phase














