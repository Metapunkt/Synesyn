# **SynTree Voice Integration - Implementation Plan**

## **Phase 1: Python Voice Service Setup** ✅ COMPLETED
*Goal: Get basic TTS service running externally*

### **Python Service Foundation**
- [x] Create `syntree-voice-service/` directory (outside Godot project)
- [x] Create `environment.yml` with required dependencies
  - [x] TTS library (Edge TTS - Windows friendly)
  - [x] FastAPI for HTTP server
  - [x] Audio processing libraries (soundfile)
  - [x] Basic Python dependencies
- [x] Create `requirements.txt` as backup to conda
- [x] Test conda environment creation and activation

### **Basic TTS Server**
- [x] Create `voice_server.py` with FastAPI framework
- [x] Implement `/health` endpoint for service status
- [x] Implement `/synthesize` endpoint accepting text + character
- [x] Test basic TTS with default voice
- [x] Add character-specific voice mapping
- [x] Test audio output (WAV format, base64 encoded)
- [x] Create simple lip sync data generation (energy-based)

### **Service Testing**
- [x] Test service startup: `python voice_server.py`
- [ ] Test health check: `curl http://127.0.0.1:8765/health`
- [ ] Test synthesis: `curl -X POST http://127.0.0.1:8765/synthesize`
- [ ] Verify audio output quality
- [ ] Test service restart/error handling

---

## **Phase 2: Godot Voice Addon Structure** ✅ COMPLETED
*Goal: Create clean addon architecture*

### **Addon Foundation**
- [x] Create `addons/syntree_voice/` directory structure
- [x] Create `plugin.cfg` with addon metadata
- [x] Create `plugin.gd` with autoload registration
- [x] Create `README.md` with setup instructions
- [x] Test addon enable/disable in Godot

### **Core Service Classes**
- [x] Create `voice_client.gd` (HTTP client for TTS requests)
  - [x] HTTP request handling
  - [x] Base64 audio decoding
  - [x] Error handling and retries
  - [x] Connection testing
  - [x] Fixed response parsing to match Python service format
  - [x] Character tracking for proper response association
- [x] Create `voice_service_manager.gd` (main service coordinator)
  - [x] Service availability checking
  - [x] Character voice configuration loading
  - [x] Signal management for voice events
  - [x] Enable/disable functionality

### **Integration Bridge**
- [ ] Create `scensyn_voice_bridge.gd` (ScenSyn integration)
  - [ ] GameSession connection interface
  - [ ] Character avatar discovery
  - [ ] Voice request routing
  - [ ] Clean separation from core game logic

### **Basic Testing**
- [x] Create test script for voice integration
- [x] Test addon loading without errors
- [x] Test VoiceService autoload creation
- [x] Test HTTP client connection to Python service
- [x] Test voice synthesis request flow
- [x] Fix response parsing (audio field name and character tracking)
- [x] Verify audio playback functionality
- [x] Confirm lip sync data generation (35 points for 45+ second audio)

---

## **Phase 3: Character Avatar System** ✅ COMPLETED
*Goal: Create avatar lip sync and animation*

### **Avatar Base Classes**
- [x] Create `character_avatar.gd` base class
  - [x] Character name identification
  - [x] Group membership (`character_avatars`)
  - [x] Audio playback capability
  - [x] Basic animation interface
  - [x] Voice service integration
  - [x] Speech synthesis coordination
- [x] Create `lipsync_animator.gd` for blendshape control
  - [x] Mouth shape blendshape mapping
  - [x] Keyframe-based animation
  - [x] Smooth transitions between shapes
  - [x] Animation timing synchronization
  - [x] Placeholder blendshape application (ready for real mesh)

### **Emotion System**
- [x] Create `emotion_controller.gd` for facial expressions
  - [x] Basic emotion detection from text
  - [x] Animation trigger system
  - [x] Expression blending
  - [x] Keyword-based emotion analysis
- [x] Define emotion mapping (happy, concerned, neutral, determined, surprised)
- [x] Create animation resources for each emotion (placeholder implementation)

### **Avatar Scene Template**
- [x] Create `character_avatar.tscn` template scene
  - [x] 3D character mesh placeholder with blendshapes
  - [x] AudioStreamPlayer3D component
  - [x] Proper node structure and naming
- [x] Create `test_avatar_system.gd` for testing
- [x] Test blendshape functionality with dummy data
- [x] Test audio playback synchronization
- [x] Test full avatar pipeline: text → TTS → lip sync → animation
- [x] Fix Godot 4 compatibility issues (node type checking, time functions)
- [x] Fix lip sync data parsing (mouth_open, viseme fields)
- [x] Verify viseme-based lip sync animation working

---

## **Phase 4: ScenSyn Integration** 🔄 IN PROGRESS
*Goal: Surgical integration with existing game*

### **Minimal GameSession Changes**
- [x] Create `scensyn_voice_bridge.gd` integration bridge
  - [x] GameSession discovery and connection
  - [x] Character avatar management
  - [x] Voice request routing with character mapping
  - [x] Clean separation from core game logic
- [x] Create `game_session_voice_patch.gd` reference implementation
  - [x] Voice bridge instantiation pattern
  - [x] Enhanced display_message integration approach
  - [x] Graceful fallback if voice unavailable
- [ ] Add voice bridge to GameSession scene or script
- [ ] Test integration with existing game session functionality

### **Character Avatar Placement**
- [x] Add avatar container to voice bridge system
- [x] Create individual character avatar scenes
  - [x] Narrator avatar
  - [x] Ingrid Tog avatar  
  - [x] Nathan Coleman avatar
  - [x] Astrid Olavson avatar
- [x] Position avatars appropriately in 3D space
- [x] Test avatar discovery by voice bridge

### **Configuration System**
- [ ] Add voice settings to project settings
  - [ ] Enable/disable toggle
  - [ ] Service URL configuration
  - [ ] Character voice mappings
- [ ] Create `character_voices.json` configuration file
- [ ] Add voice settings UI panel (optional)

### **Integration Testing**
- [x] Create `test_scensyn_integration.gd` for validation
  - [x] Simulate GameSession message flow
  - [x] Test character voice mapping
  - [x] Test message cleaning and processing
  - [x] Test avatar speech coordination
- [ ] Test with actual GameSession
- [ ] Verify no conflicts with existing functionality
- [ ] Test multiplayer compatibility

---

## **Phase 5: Polish and Testing**
*Goal: Robust, production-ready system*

### **Error Handling & Fallbacks**
- [ ] Handle Python service unavailable gracefully  
- [ ] Handle network timeout errors
- [ ] Handle audio playback failures
- [ ] Add service status indicator to UI
- [ ] Test system behavior with service crashes

### **Performance Optimization**
- [ ] Implement audio caching for repeated phrases
- [ ] Add request queuing to prevent overload
- [ ] Optimize blendshape animation performance
- [ ] Test with multiple simultaneous speakers

### **User Experience**
- [ ] Add voice enable/disable toggle in game UI
- [ ] Add volume controls for character voices
- [ ] Add subtitle synchronization with speech
- [ ] Test user workflow and feedback

### **Documentation & Setup**
- [ ] Complete addon README with step-by-step setup
- [ ] Create troubleshooting guide
- [ ] Document character voice customization
- [ ] Create video setup tutorial (optional)

---

## **Phase 6: Advanced Features (Optional)**
*Goal: Enhanced immersion and polish*

### **Advanced Lip Sync**
- [ ] Implement phoneme-based lip sync (vs energy-based)
- [ ] Add pronunciation dictionary for Norwegian names
- [ ] Fine-tune blendshape transitions
- [ ] Add mouth movement variation

### **Voice Personality**
- [ ] Character-specific speaking rates
- [ ] Emotional inflection in voice synthesis  
- [ ] Context-aware emotion detection
- [ ] Dynamic voice parameter adjustment

### **Multi-language Support**
- [ ] Norwegian TTS model integration
- [ ] Language detection for mixed content
- [ ] Accent/dialect variations for characters
- [ ] Localization-aware voice selection

---

## **Testing Checklist**

### **Integration Testing**
- [ ] Test full voice pipeline: text → TTS → lip sync → avatar
- [ ] Test with existing ScenSyn multiplayer functionality
- [ ] Test with narrator agent and behavior trees
- [ ] Test game session without voice service running
- [ ] Test addon disable/enable without breaking game

### **Platform Testing**
- [ ] Test on Windows development environment
- [ ] Test conda environment setup on different machines
- [ ] Test service startup scripts
- [ ] Test Godot export with voice addon enabled

### **User Acceptance Testing**  
- [ ] Test setup process with fresh environment
- [ ] Test voice quality and character differentiation
- [ ] Test lip sync accuracy and timing
- [ ] Test integration with existing storytelling flow
- [ ] Gather feedback on avatar performance quality

---

## **Success Criteria**

**Phase 1-3 Complete**: ✅ Characters speak with basic lip sync  
**Phase 4 Complete**: ✅ Voice integrates seamlessly with existing game  
**Phase 5 Complete**: ✅ Production-ready, robust voice system  
**Phase 6 Complete**: ✅ Polished, immersive character performances  

Each checkbox represents a concrete deliverable that can be tested and verified before moving to the next task.

---

## **Progress Tracking**

*Last Updated: December 27, 2024*  
*Current Phase: Phase 4 - ScenSyn Integration*  
*Current Task: Surgical integration with existing game*

### **Completed Tasks**
- [x] ✅ **PHASE 1 COMPLETE** - Python Voice Service Setup
- [x] External service directory created and configured
- [x] Windows-friendly dependencies (Edge TTS)
- [x] FastAPI server with /health and /synthesize endpoints
- [x] Character voice mapping implemented
- [x] Service successfully running on port 8765
- [x] ✅ **PHASE 2 COMPLETE** - Godot Voice Addon Structure
- [x] Implementation plan created and saved
- [x] Created `addons/syntree_voice/` directory structure
- [x] Created `plugin.cfg` with addon metadata
- [x] Created `plugin.gd` with autoload registration
- [x] Created `voice_service_manager.gd` (main service coordinator)
- [x] Created `voice_client.gd` (HTTP client for TTS requests)
- [x] Created `README.md` with setup instructions
- [x] Created test script for voice integration testing
- [x] Fixed response parsing and character tracking
- [x] Verified full voice synthesis pipeline working
- [x] Confirmed audio playback and lip sync data generation
- [x] ✅ **PHASE 3 COMPLETE** - Character Avatar System
- [x] Created `character_avatar.gd` base class with full functionality
- [x] Created `lipsync_animator.gd` for blendshape control
- [x] Created `emotion_controller.gd` for facial expressions  
- [x] Created `character_avatar.tscn` template scene
- [x] Created comprehensive test system for avatars
- [x] Fixed Godot 4 compatibility issues (node finding, time functions)
- [x] Fixed lip sync data parsing (mouth_open, viseme fields)
- [x] Verified complete avatar pipeline: text → emotion → TTS → lip sync → animation
- [x] Confirmed viseme-based lip sync working (mouth_e, mouth_a, mouth_s)
- [x] Tested multiple mouth shapes and intensity values

### **Next Steps**
1. **CURRENT FOCUS**: Phase 4 - ScenSyn Integration
2. Implement voice bridge integration with game session
3. Test integration with existing game functionality
4. Fix any issues with voice integration
5. Gather feedback on integration

### **Service Testing Commands**

Test your running service with these commands:

```bash
# Health check
curl http://127.0.0.1:8765/health

# Test synthesis
curl -X POST http://127.0.0.1:8765/synthesize -H "Content-Type: application/json" -d "{\"text\": \"Hello from SynTree!\", \"character\": \"Narrator\"}"

# Get available voices
curl http://127.0.0.1:8765/voices
```

### **Godot Testing Steps**

1. **Enable the addon**: 
   - Go to Project Settings > Plugins
   - Find "SynTree Voice Integration"
   - Enable it

2. **Test with script**:
   - Create a test scene
   - Add the test script: `addons/syntree_voice/test_voice_integration.gd`
   - Run the scene to test functionality

3. **Enable voice service**:
   - Go to Project Settings > Application > Syntree Voice
   - Set "Enabled" to true
   - Set "Service URL" to "http://127.0.0.1:8765" 