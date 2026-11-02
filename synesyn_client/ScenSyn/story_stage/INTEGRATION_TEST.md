# ScenSyn + story_stage Integration Test

> **Historical.** This describes the first integration of the stage into ScenSyn.
> The stage code has since moved to `addons/story_stage/` (ADR 0029), and this folder
> now holds only ScenSyn's scenario art: sprites, backdrops and generated resources.
> The checks below are no longer maintained. The current ones are the
> `scensyn_story_stage_*.json` and `playback_smoke.json` harness specs, and the
> checks listed in `addons/story_stage/README.md`.

## Quick Integration Test

This document outlines how to test that the story_stage visual presentation is properly integrated with ScenSyn.

## Test Steps

### 1. Start ScenSyn Game Session
1. Run the ScenSyn project
2. Start a multiplayer or single-player game session
3. Select any scenario with characters

### 2. Expected Visual Integration Behavior

When the game session starts, you should see:

✅ **Visual Presentation Loaded**: The story_stage visual novel UI should appear
✅ **Characters Registered**: Console should show "Character: Registered character 'X' with ID: Y"
✅ **Background System**: Console should show "DynamicBackgroundManager: Loaded X backgrounds"
✅ **Integration Ready**: Console should show "GameSession: Visual presentation system initialized successfully"

### 3. During Gameplay

When AI responses are generated:

✅ **Visual Display**: Character sprites and dialogue should appear in visual novel style
✅ **Background Changes**: Backgrounds should change based on AI location descriptions
✅ **Parallel Systems**: Both the original Story Log AND visual presentation should update
✅ **Fallback Sprites**: Characters without specific sprites should use fallback sprites

## Console Output to Look For

```
GameSession: Initializing visual presentation system...
VisualPresentationManager: Initializing...
VisualPresentationManager: Loaded story_stage scene successfully
DynamicBackgroundManager: Loaded 3 backgrounds
Character: Registered character 'Detective Sarah' with ID: 0
Character: Registered character 'Suspect Mike' with ID: 1
GameSession: Visual presentation system initialized successfully
```

## Troubleshooting

### If Integration Doesn't Load:
- Check that `story_stage.tscn` exists in `ScenSyn/story_stage/scenes/`
- Verify console for any error messages during initialization
- Ensure background images and metadata exist in `ScenSyn/story_stage/assets/images/`

### If Characters Don't Appear:
- Check that fallback sprites exist in `ScenSyn/story_stage/sprites/_fallback/`
- Verify character registration messages in console
- Ensure scenario has characters defined

### If Backgrounds Don't Change:
- Verify background metadata JSON files exist
- Check that AI responses contain location-related keywords
- Ensure DynamicBackgroundManager initialization messages appear

## Test Scenarios

The integration should work with any existing ScenSyn scenario. The system automatically:
- Registers characters from the scenario
- Discovers available backgrounds
- Processes AI responses for visual presentation
- Maintains parallel Story Log system

## Success Criteria

✅ No errors during visual system initialization
✅ Character sprites appear (fallback sprites if no specific sprites)
✅ Backgrounds change appropriately during story progression
✅ Original ScenSyn functionality remains intact
✅ Story Log system continues to work alongside visual presentation














