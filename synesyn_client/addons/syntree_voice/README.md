# SynTree Voice Integration Addon

High-quality voice synthesis and lip sync system for SynTree collaborative storytelling.

## Overview

This addon provides:
- Character-specific voice synthesis
- Lip sync animation with blendshapes
- Emotional expression system
- Clean integration with existing ScenSyn gameplay

## Architecture

- **Hub Voice API (recommended)**: TTS/STT via Synesyn Hub `/voice/*` (single endpoint; artifacts+provenance persisted in hub substrate)
- **Optional Sidecar**: hub-managed legacy voice server (hub starts/stops; hub persists artifacts+provenance)
- **External Python Service (legacy direct mode)**: TTS synthesis and lip sync generation
- **Godot Addon**: Integration layer and avatar animation
- **Bridge Pattern**: Clean separation between voice system and game logic

## Prerequisites

1. **Python Environment**: Conda or Python 3.9+
2. **External Voice Service**: `syntree-voice-service` (separate repository)
3. **3D Character Models**: With blendshapes for mouth animation

## Setup Instructions

### 1. Clone Voice Service (Outside Godot Project)

```bash
# From your development directory (NOT inside SynTree project)
git clone <voice-service-repo> syntree-voice-service
cd syntree-voice-service
```

### 2. Setup Conda Environment

```bash
# Create environment
conda env create -f environment.yml

# Activate environment
conda activate syntree-voice
```

### 3. Start Voice Service

```bash
# Make sure you're in syntree-voice-service directory
python voice_server.py
```

The legacy service will start on `http://127.0.0.1:8765`

### 4. Enable Addon in Godot

1. Open Project Settings → Plugins
2. Enable "SynTree Voice Integration" 
3. Verify no errors in console

### 5. Configure Voice Settings

Add to your project settings:
```
[syntree_voice]
enabled=true
provider_mode="hub" # preferred: routes through Synesyn Hub /voice/*
hub_url="http://127.0.0.1:17777"
service_url="http://127.0.0.1:8765" # legacy direct mode fallback
```

## Provenance note (v1)
When running in hub mode, this addon forwards a `character_mapping` object (mapping source/version + chosen voice id)
so the hub can persist it into TTS/STT artifact provenance for auditability.

## Usage

Once setup is complete, character voices will automatically activate when:
- Voice service is running
- Character has dialogue in game
- Character avatar exists in scene

## Character Configuration

Customize character voices by editing `character_voices.json`:

```json
{
  "Narrator": {
    "voice": "narrator_neutral",
    "speed": 0.9,
    "emotion": "neutral"
  },
  "Ingrid Tog": {
    "voice": "female_professional_norwegian",
    "speed": 1.0,
    "emotion": "professional"
  }
}
```

## Troubleshooting

### Voice Service Not Starting
- Check conda environment is activated
- Verify all dependencies installed
- Check port 8765 is available

### No Voice in Game
- Verify addon is enabled in Project Settings
- Check voice service is running (`curl http://127.0.0.1:8765/health`)
- Ensure character avatars are in scene with group `character_avatars`

### Lip Sync Issues
- Verify character model has mouth blendshapes
- Check blendshape naming matches addon expectations
- Test with simple text first

## Development

See `IMPLEMENTATION_PLAN.md` for development roadmap and current progress.

## File Structure

```
addons/syntree_voice/
├── plugin.cfg                      # Addon configuration
├── plugin.gd                       # Main plugin script
├── README.md                       # This file
├── IMPLEMENTATION_PLAN.md          # Development roadmap
├── scripts/
│   ├── services/
│   │   ├── voice_service_manager.gd # Main service coordinator
│   │   └── voice_client.gd         # HTTP client (TODO)
│   ├── avatar/
│   │   ├── character_avatar.gd     # Avatar base class (TODO)
│   │   └── lipsync_animator.gd     # Blendshape controller (TODO)
│   └── integration/
│       └── scensyn_voice_bridge.gd # ScenSyn integration (TODO)
└── scenes/
    └── character_avatar.tscn       # Avatar template (TODO)
``` 