# **SynTree Voice Integration Guide**

## **Quick Integration with GameSession**

### **Option 1: Minimal Integration (Recommended)**

Add these lines to your `GameSession._ready()` function:

```gdscript
# Add after existing initialization code
if VoiceService and VoiceService.is_voice_available():
	var voice_bridge = preload("res://addons/syntree_voice/scripts/integration/scensyn_voice_bridge.gd").new()
	voice_bridge.name = "VoiceBridge"
	add_child(voice_bridge)
	print("GameSession: Voice integration enabled")
```

Add this to your `display_message()` function (after the existing message display):

```gdscript
# Add at the end of display_message() function
if has_node("VoiceBridge"):
	var voice_bridge = get_node("VoiceBridge")
	if voice_bridge.should_request_voice_for_message(sender, message):
		var character_name = voice_bridge.extract_character_name_from_sender(sender)
		var clean_message = message.replace_regex("\\[/?[^\\]]*\\]", "").strip_edges()
		voice_bridge.request_character_speech(character_name, clean_message)
```

### **Option 2: Test Without Modifying GameSession**

1. Create a new scene
2. Add a Node and attach `addons/syntree_voice/test_scensyn_integration.gd`
3. Run the scene to see the voice integration in action

## **What You Get**

✅ **Character voices** for Narrator, Ingrid Tog, Nathan Coleman, Astrid Olavson  
✅ **Automatic emotion detection** from message content  
✅ **Lip sync animation** with mouth shapes  
✅ **Facial expressions** based on text analysis  
✅ **No interference** with existing game functionality  

## **Voice Controls**

- **Auto-enabled** for AI character messages
- **Disabled by default** for player input messages
- **Configurable** per character
- **Graceful fallback** if voice service unavailable

## **Testing**

Run the integration test:
```
Scene: Create new scene → Add Node → Attach test_scensyn_integration.gd → Run
```

You'll see a complete conversation with all characters speaking with proper voices and lip sync!

## **Sender Name Convention — Voiced vs. Silent Entries**

Every call to `StoryState.add_log_entry(sender, message)` results in a story log entry. The
voice bridge decides whether to speak it based on the `sender` string.

| Sender prefix | Behaviour |
|---|---|
| Normal name (e.g. `"Narrator"`, `"The Seeker"`) | Voiced if the character is in `voice_enabled_characters` |
| Starts with `[` (e.g. `"[System]"`, `"[Debug]"`) | **Never voiced** — silently skipped by `should_request_voice_for_message()` |

### When to use a `[Bracket]` sender

Use a bracketed sender any time you need to surface a technical or meta message in the story
log UI without having it spoken aloud. Examples:

```gdscript
# AI timeout / error — shown in log, never read by TTS
const _AI_ERROR_SENDER := "[System]"
StoryState.add_log_entry(_AI_ERROR_SENDER, "The AI is taking longer than expected.")

# Debug annotation visible in the log UI during development
StoryState.add_log_entry("[Debug]", "Fallback triggered at turn %d" % turn_number)
```

The gate lives in `scensyn_voice_bridge.gd → should_request_voice_for_message()`:

```gdscript
# Senders prefixed with '[' are technical/meta messages — never voiced.
if sender.begins_with("["):
    return false
```

Keep bracket-prefixed senders short and descriptive. Do **not** use them for narrative content
that characters should speak — use a real character name for that.

---

## **Troubleshooting**

1. **No voice**: Ensure Python voice service is running (`python voice_server.py`)
2. **No avatars**: Check that VoiceService autoload is enabled
3. **Performance**: Voice synthesis happens in background, no game lag

## **Advanced Configuration**

Access the voice bridge in GameSession:
```gdscript
var voice_bridge = get_node("VoiceBridge")
voice_bridge.set_voice_enabled_for_character("Narrator", false)  # Disable narrator voice
voice_bridge.stop_all_speech()  # Stop all current speech
var status = voice_bridge.get_voice_status()  # Get system status
``` 