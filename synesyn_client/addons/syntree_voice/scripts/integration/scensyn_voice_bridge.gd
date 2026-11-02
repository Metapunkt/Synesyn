extends Node
class_name ScenSynVoiceBridge

const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")

func _voice_service() -> Node:
	return SynesynAutoloadAccessScript.voice_service()

# ScenSynVoiceBridge - Integration bridge between SynTree Voice system and ScenSyn GameSession
# Provides surgical integration with minimal changes to existing game code

signal voice_integration_ready()
signal character_speech_started(character_name: String)
signal character_speech_finished(character_name: String)

# Integration settings
@export var auto_request_voice: bool = true  # Automatically request voice for AI messages
@export var voice_for_player_input: bool = false  # Voice synthesis for player input (usually not needed)
@export var narrator_voice_enabled: bool = true  # Enable voice for narrator messages
## Pause inserted between consecutive character speeches (seconds). Default 0.1 s.
## Can be raised (e.g. 1.0–2.0 s) to give participants more breathing room between turns.
## Override via RuntimeConfig: apps.scensyn.inter_character_pause_sec.
@export_range(0.0, 5.0, 0.05) var inter_character_pause_sec: float = 0.1

# Character avatar management
var character_avatars: Dictionary = {}  # character_name -> CharacterAvatar
var avatar_container: Node3D
var game_session: Node

# Voice filtering
var voice_enabled_characters: Array = ["Narrator", "Ingrid Tog", "Nathan Coleman", "Astrid Olavson"]

# Speech queue management
var speech_queue: Array = []
var is_processing_queue: bool = false
var currently_speaking_character: String = ""
var is_queue_paused: bool = false
var current_request: Dictionary = {}
const AVATAR_RADIUS: float = 2.5

var _regex_cache_ready: bool = false
var _bbcode_strip_regex: RegEx = null
var _glitch_strip_regex: RegEx = null
var _xml_strip_regexes: Array[RegEx] = []

func _ensure_text_cleanup_regexes() -> void:
	if _regex_cache_ready:
		return
	_bbcode_strip_regex = RegEx.new()
	_bbcode_strip_regex.compile("\\[/?[^\\]]*\\]")
	_glitch_strip_regex = RegEx.new()
	_glitch_strip_regex.compile("\\*[a-zA-Z0-9_-]+\\*")
	_xml_strip_regexes.clear()
	var patterns: Array[String] = [
		"<[^>]*>",  # Any XML/HTML tags
		"</[^>]*>", # Closing tags specifically
		"<?[^>]*>", # XML declarations
	]
	for pattern_str in patterns:
		var re: RegEx = RegEx.new()
		re.compile(pattern_str)
		_xml_strip_regexes.append(re)
	_regex_cache_ready = true

func _ready():
	print("ScenSynVoiceBridge: Initializing voice integration...")
	# Allow runtime config to override the exported default without requiring a scene save.
	var bridge_cfg: Dictionary = RuntimeConfig.load_config()
	var scensyn_cfg: Dictionary = (bridge_cfg.get("apps", {}) as Dictionary).get("scensyn", {})
	if scensyn_cfg.has("inter_character_pause_sec"):
		inter_character_pause_sec = float(scensyn_cfg.get("inter_character_pause_sec", inter_character_pause_sec))
	
	# DON'T clear synthesis here - it kills audio from other scenes during transitions
	# Each bridge manages its own queue independently via character avatars
	
	# Wait for scene to be fully loaded (guard against null tree on fast scene switches)
	if not is_inside_tree():
		await self.tree_entered
	var tree = get_tree()
	if tree:
		await tree.process_frame
	else:
		print("ScenSynVoiceBridge: No SceneTree available; aborting initialization")
		return
	print("ScenSynVoiceBridge: Scene loaded, continuing initialization...")
	
	# Find the GameSession
	_find_game_session()
	
	# Extend voice-enabled characters from current scenario if available
	_populate_characters_from_scenario()
	
	# Setup avatar container
	_setup_avatar_container()
	
	# Create character avatars
	_create_character_avatars()
	
	# Connect to voice service if available
	_connect_voice_service()
	
	print("ScenSynVoiceBridge: Voice integration ready")
	voice_integration_ready.emit()

	# Ensure we clean up safely on scene exit
	self.tree_exited.connect(_on_tree_exited)

func _on_tree_exited():
	# When this VoiceBridge is destroyed (scene change), DON'T stop ongoing speech!
	# The global audio players will continue playing, and the new scene's VoiceBridge
	# will take over management of the queue.
	
	# Just clear our local queue state (don't call stop_all_speech which stops avatars)
	speech_queue.clear()
	is_processing_queue = false
	currently_speaking_character = ""

func _find_game_session():
	"""Find the GameSession node in the scene"""
	# Look for GameSession in the scene tree
	var game_sessions = get_tree().get_nodes_in_group("game_session")
	if not game_sessions.is_empty():
		game_session = game_sessions[0]
		print("ScenSynVoiceBridge: Found GameSession: ", game_session.name)
	else:
		# Fallback: search by class name
		game_session = _find_node_by_script_name(get_tree().root, "game_session.gd")
		if game_session:
			print("ScenSynVoiceBridge: Found GameSession by script: ", game_session.name)
		else:
			print("ScenSynVoiceBridge: WARNING - GameSession not found!")

func _find_node_by_script_name(node: Node, script_name: String) -> Node:
	"""Recursively find a node with a specific script name"""
	if node.get_script() and node.get_script().resource_path.ends_with(script_name):
		return node
	
	for child in node.get_children():
		var result = _find_node_by_script_name(child, script_name)
		if result:
			return result
	
	return null

func _setup_avatar_container():
	"""Create a container for character avatars"""
	print("ScenSynVoiceBridge: Setting up avatar container...")
	print("ScenSynVoiceBridge: game_session = ", game_session)
	
	# If no GameSession found, use the parent node (for testing)
	var container_parent = game_session if game_session else get_parent()
	
	if not container_parent:
		print("ScenSynVoiceBridge: Cannot setup avatars - No parent container found")
		return
	
	# Create 3D avatar container
	avatar_container = Node3D.new()
	avatar_container.name = "VoiceAvatarContainer"
	container_parent.add_child(avatar_container)
	
	print("ScenSynVoiceBridge: Created avatar container: ", avatar_container)
	print("ScenSynVoiceBridge: Container parent: ", container_parent)

func _create_character_avatars():
	"""Create avatars for each game character"""
	print("ScenSynVoiceBridge: Creating character avatars...")
	_ensure_avatars_for_voice_roster()
	print("ScenSynVoiceBridge: Avatar creation complete. Total avatars: ", character_avatars.size())

func _ensure_avatars_for_voice_roster():
	if not avatar_container:
		_setup_avatar_container()
	if not avatar_container:
		print("ScenSynVoiceBridge: ERROR - No avatar container!")
		return
	var avatar_scene = preload("res://addons/syntree_voice/scenes/character_avatar.tscn")
	var count := max(voice_enabled_characters.size(), 1)
	for i in range(voice_enabled_characters.size()):
		var character_name = voice_enabled_characters[i]
		if character_avatars.has(character_name):
			_position_avatar(character_avatars[character_name], i, count)
			continue
		var avatar = avatar_scene.instantiate()
		avatar.character_name = character_name
		_position_avatar(avatar, i, count)
		avatar.speech_started.connect(_on_character_speech_started)
		avatar.speech_finished.connect(_on_character_speech_finished)
		avatar_container.add_child(avatar)
		character_avatars[character_name] = avatar
		print("ScenSynVoiceBridge: Created avatar for: ", character_name)

func _position_avatar(avatar: Node3D, index: int, total_count: int):
	if not avatar:
		return
	var divisor := float(max(total_count - 1, 1))
	var x: float = -AVATAR_RADIUS + float(index) * (2.0 * AVATAR_RADIUS / divisor)
	avatar.position = Vector3(x, 0, -2)

func _populate_characters_from_scenario():
	"""Extend voice-enabled list with characters from the active scenario (if available)."""
	var scenario := _get_current_scenario()
	_extend_voice_roster_from_scenario(scenario)

func refresh_voice_roster(explicit_scenario: Dictionary = {}):
	"""Refresh voice list/avatars once scenario data is guaranteed to be available."""
	var scenario := explicit_scenario if not explicit_scenario.is_empty() else _get_current_scenario()
	_extend_voice_roster_from_scenario(scenario)
	_ensure_avatars_for_voice_roster()

func _get_current_scenario() -> Dictionary:
	var global_node := SynesynAutoloadAccessScript.global()
	if is_instance_valid(global_node) and global_node.has_method("get_game_flow_manager"):
		var gfm = global_node.get_game_flow_manager()
		if gfm and gfm.has_method("get_current_scenario"):
			return gfm.get_current_scenario()
	return {}

func _extend_voice_roster_from_scenario(scenario: Dictionary):
	if not scenario:
		return
	var chars = scenario.get("characters", [])
	if typeof(chars) == TYPE_ARRAY:
		for c in chars:
			if typeof(c) == TYPE_DICTIONARY and c.has("name"):
				var nm = String(c.get("name")).strip_edges()
				if nm != "" and not voice_enabled_characters.has(nm):
					voice_enabled_characters.append(nm)
	
	if scenario.has("voice_overrides"):
		var overrides: Dictionary = scenario["voice_overrides"]
		for k in overrides.keys():
			var src_name := String(k).strip_edges()
			var dst_name := String(overrides[k]).strip_edges()
			if src_name != "" and not voice_enabled_characters.has(src_name):
				voice_enabled_characters.append(src_name)
			if dst_name != "" and not voice_enabled_characters.has(dst_name):
				voice_enabled_characters.append(dst_name)
	print("ScenSynVoiceBridge: Voice roster synced:", voice_enabled_characters)

func _connect_voice_service():
	"""Connect to the voice service signals"""
	if _voice_service():
		# VoiceService signals are connected in CharacterAvatar
		pass

# Integration helper functions
func extract_character_name_from_sender(sender: String) -> String:
	"""Extract clean character name from formatted sender string"""
	# Remove formatting tags like [font_size=16][b] and [/b][/font_size]
	var clean_sender = sender
	
	# Remove BBCode formatting
	_ensure_text_cleanup_regexes()
	if _bbcode_strip_regex:
		clean_sender = _bbcode_strip_regex.sub(clean_sender, "", true)
	
	# Remove trailing colons
	clean_sender = clean_sender.replace(":", "").strip_edges()
	
	return clean_sender

func should_request_voice_for_message(sender: String, message: String) -> bool:
	"""Determine if voice should be requested for a message.

	Sender convention:
	  - Regular names ("Narrator", "The Seeker", etc.) → voiced if in voice_enabled_characters.
	  - Bracket-prefixed names ("[System]", "[Debug]", etc.) → NEVER voiced (silent/meta entries).
	    Use these for technical notices or error messages that appear in the UI but must not
	    be spoken aloud. See StoryState.add_log_entry() docstring and INTEGRATION_GUIDE.md.
	"""
	if not auto_request_voice:
		return false

	# Senders prefixed with '[' (e.g. "[System]") are technical/meta messages — never voiced.
	if sender.begins_with("["):
		return false

	var character_name = extract_character_name_from_sender(sender)
	
	# Check if character has voice enabled
	if not is_voice_enabled_for_character(character_name):
		# Lazy check: refresh list and try again
		print("ScenSynVoiceBridge: Character '%s' not initially enabled. Refreshing from scenario..." % character_name)
		_populate_characters_from_scenario()
		
		# If still not found, check for lazy enable
		if not is_voice_enabled_for_character(character_name):
			print("ScenSynVoiceBridge: Voice NOT enabled for character: ", character_name)
			return false
	
	# Only reject unrealistically short snippets. Loaded story logs often start with
	# concise human acknowledgements, so we keep this at 3 characters just to avoid blank requests.
	if message.length() < 3:
		return false
	
	# Skip empty or whitespace-only messages
	if message.strip_edges().is_empty():
		return false
	
	# Skip test messages (messages that contain test-related content)
	var message_lower = message.to_lower()
	if "test" in message_lower and ("audio" in message_lower or "synthesis" in message_lower):
		print("ScenSynVoiceBridge: Skipping test message")
		return false
	
	return true 

func is_voice_enabled_for_character(character_name: String) -> bool:
	"""Check if voice is enabled for a specific character"""
	return voice_enabled_characters.has(character_name)

func set_voice_enabled_for_character(character_name: String, enabled: bool):
	"""Enable/disable voice for a specific character"""
	if enabled:
		if not voice_enabled_characters.has(character_name):
			voice_enabled_characters.append(character_name)
			
			# Create avatar if needed
			if not character_avatars.has(character_name):
				# Need to recreate/update avatars
				_create_character_avatars()
	else:
		if voice_enabled_characters.has(character_name):
			voice_enabled_characters.erase(character_name)
			
			# Remove avatar if exists
			if character_avatars.has(character_name):
				var avatar = character_avatars[character_name]
				avatar.queue_free()
				character_avatars.erase(character_name)

# Public API
func request_character_speech(character_name: String, text: String, emotion: String = "neutral", voice_config: Dictionary = {}) -> bool:
	"""Request speech for a character (queues it)"""
	if not is_voice_enabled_for_character(character_name):
		print("ScenSynVoiceBridge: Ignoring speech request for disabled character: ", character_name)
		return false
	
	print("ScenSynVoiceBridge: Queuing speech for ", character_name, " (emotion: ", emotion, ")")
	
	# Add to queue. The voice config is copied onto the item so the request
	# that actually reaches the hub uses this speaker's scenario voice.
	speech_queue.append({
		"character": character_name,
		"text": text,
		"emotion": emotion,
		"voice_config": voice_config.duplicate(true)
	})
	
	# Start processing if idle
	if not is_processing_queue:
		_process_speech_queue()
	return true

func clear_all_voice_activity():
	"""Clear all queues and stop current speech"""
	stop_all_speech()
	speech_queue.clear()
	current_request = {}
	is_processing_queue = false
	currently_speaking_character = ""

func stop_all_speech():
	"""Stop all currently playing speech"""
	print("ScenSynVoiceBridge: Stopping all speech")
	
	for char_name in character_avatars:
		var avatar = character_avatars[char_name]
		if avatar:
			avatar.stop_speaking()
	
	# Note: We don't clear the queue here unless clear_all_voice_activity is called
	# This allows "pausing" by stopping current and resuming queue later if needed

func stop_current_speech() -> void:
	"""Stop only the currently speaking character (v1 stop-current API)."""
	if currently_speaking_character == "":
		return
	if not character_avatars.has(currently_speaking_character):
		currently_speaking_character = ""
		current_request = {}
		return
	var avatar = character_avatars[currently_speaking_character]
	if avatar and avatar.has_method("stop_speaking"):
		avatar.stop_speaking()
	# After stopping, allow the queue loop to proceed to next entry.
	currently_speaking_character = ""
	current_request = {}

func pause_queue():
	"""Pause processing new speech (current speaking will be stopped and re-queued)"""
	is_queue_paused = true
	# Stop current avatar if any and re-queue the interrupted request
	if currently_speaking_character != "" and character_avatars.has(currently_speaking_character):
		var avatar = character_avatars[currently_speaking_character]
		if avatar and avatar.has_method("stop_speaking"):
			avatar.stop_speaking()
		# Push the interrupted request back to the front of the queue if present
		if not current_request.is_empty():
			speech_queue.push_front(current_request)
			current_request = {}
	# Emit paused for listeners
	if _voice_service():
		if _voice_service().has_signal("tts_playback_paused"):
			_voice_service().tts_playback_paused.emit(currently_speaking_character)

func resume_queue():
	"""Resume processing queued speech"""
	is_queue_paused = false
	# If idle and there is content, restart processing
	if not is_processing_queue and not speech_queue.is_empty():
		_process_speech_queue()
	# Emit resumed for listeners (character may be set on next start)
	if _voice_service():
		if _voice_service().has_signal("tts_playback_resumed"):
			_voice_service().tts_playback_resumed.emit(currently_speaking_character)

func _process_speech_queue():
	"""Process the speech queue sequentially"""
	if is_processing_queue or speech_queue.is_empty():
		return
	
	if is_queue_paused:
		print("ScenSynVoiceBridge: Queue paused, deferring processing")
		return
	
	is_processing_queue = true
	print("ScenSynVoiceBridge: Starting queue processing (size: ", speech_queue.size(), ")")
	
	while not speech_queue.is_empty():
		while is_queue_paused and is_inside_tree():
			await get_tree().process_frame
		if not is_inside_tree():
			print("ScenSynVoiceBridge: Node left scene tree; stopping queue processing")
			break
		var speech_request = speech_queue.pop_front()
		current_request = speech_request
		var character_name = speech_request.character
		var text = speech_request.text
		var emotion = speech_request.emotion
		
		# Clean the text to remove any markup or unwanted content
		text = _clean_text_for_speech(text)
		
		print("ScenSynVoiceBridge: Processing speech for ", character_name, " (", speech_queue.size(), " remaining)")
		print("ScenSynVoiceBridge: Original text: ", speech_request.text.substr(0, 100))
		print("ScenSynVoiceBridge: Cleaned text: ", text.substr(0, 100))
		currently_speaking_character = character_name
		
		if not character_avatars.has(character_name):
			print("ScenSynVoiceBridge: ERROR - Avatar not found for ", character_name)
			current_request = {}
			continue
		
		var avatar = character_avatars[character_name]
		var prefetched := bool(speech_request.get("prefetched", false))
		var voice_config := _voice_for_send(speech_request)
		if not _voice_is_ready(character_name, voice_config):
			var attempts := int(speech_request.get("voice_attempts", 0))
			if attempts < 45:
				speech_request["voice_attempts"] = attempts + 1
				speech_queue.push_front(speech_request)
				currently_speaking_character = ""
				current_request = {}
				if is_inside_tree():
					await get_tree().process_frame
				continue
		if not prefetched:
			# Detect emotion from text if not specified
			if emotion == "neutral" and avatar.emotion_controller:
				emotion = avatar.emotion_controller.detect_emotion_from_text(text)
			# Start speaking
			var success = avatar.speak(text, emotion, voice_config)
			if not success:
				print("ScenSynVoiceBridge: [ERROR] ", character_name, " rejected speech (is_speaking=", avatar.is_speaking, ", _synthesis_requested=", avatar._synthesis_requested, ", _pending_lipsync=", avatar._pending_lipsync_start, ")")
				current_request = {}
				continue
		elif avatar.has_method("release_held_playback"):
			avatar.release_held_playback()
		await _wait_for_avatar(avatar, character_name, text)
		if is_inside_tree() and not is_queue_paused and inter_character_pause_sec > 0.0:
			var tree2 = get_tree()
			if tree2:
				await tree2.create_timer(inter_character_pause_sec).timeout
		
		print("ScenSynVoiceBridge: Continuing to next character. Remaining queue size: ", speech_queue.size())
		current_request = {}
	
	currently_speaking_character = ""
	is_processing_queue = false
	print("ScenSynVoiceBridge: Speech queue processing complete")


func _wait_for_avatar(avatar, character_name: String, text: String) -> void:
	var wait_start_ms := Time.get_ticks_msec()
	var last_log_ms := wait_start_ms
	var estimated_duration_sec := float(text.length()) / 12.5
	var max_wait_ms := int(max(estimated_duration_sec + 45.0, 60.0) * 1000.0)
	while is_inside_tree() and avatar.is_currently_speaking() and not is_queue_paused:
		# Synthesize the next queued line while this one plays. Playback of
		# that line stays held until this one has finished and the queue
		# reaches it, which is after its caption is on screen.
		_prefetch_next()
		await get_tree().process_frame
		var now_ms := Time.get_ticks_msec()
		if now_ms - last_log_ms >= 10000:
			var elapsed := (now_ms - wait_start_ms) / 1000.0
			print("ScenSynVoiceBridge: Still waiting for ", character_name, " (", elapsed, "s)")
			last_log_ms = now_ms
		if now_ms - wait_start_ms > max_wait_ms:
			print("ScenSynVoiceBridge: [WARNING] Timed out waiting for ", character_name, "; forcing stop to unblock queue")
			if avatar and avatar.has_method("stop_speaking"):
				avatar.stop_speaking()
			break


func _voice_is_ready(character_name: String, config: Dictionary) -> bool:
	if str(config.get("voice", "")).strip_edges() != "":
		return true
	var stage := get_parent()
	if stage == null:
		return false
	var voice: Variant = stage.get("voice")
	if voice != null and voice.has_method("installed_voice_id"):
		return str(voice.call("installed_voice_id", character_name)).strip_edges() != ""
	return false


func _bind_queued_voice(character_name: String) -> Dictionary:
	if character_name == "":
		return {}
	var stage := get_parent()
	if stage == null:
		return {}
	var voice: Variant = stage.get("voice")
	if voice != null and voice.has_method("bind_speaker_voice"):
		var fresh: Variant = voice.call("bind_speaker_voice", character_name)
		if typeof(fresh) == TYPE_DICTIONARY:
			return fresh
	return {}


func _voice_for_send(request: Dictionary) -> Dictionary:
	var queued: Variant = request.get("voice_config", {})
	if typeof(queued) == TYPE_DICTIONARY and str((queued as Dictionary).get("voice", "")).strip_edges() != "":
		return queued
	var fresh := _bind_queued_voice(str(request.get("character", "")))
	if str(fresh.get("voice", "")).strip_edges() != "":
		request["voice_config"] = fresh
	return fresh


func _prefetch_next() -> void:
	if speech_queue.is_empty():
		return
	var nxt: Dictionary = speech_queue[0]
	if bool(nxt.get("prefetched", false)):
		return
	var name := str(nxt.get("character", ""))
	if name == "" or name == currently_speaking_character:
		return
	if not character_avatars.has(name):
		return
	var next_avatar = character_avatars[name]
	if next_avatar.is_currently_speaking():
		return
	var spoken := _clean_text_for_speech(str(nxt.get("text", "")))
	var emotion := str(nxt.get("emotion", "neutral"))
	if emotion == "neutral" and next_avatar.emotion_controller:
		emotion = next_avatar.emotion_controller.detect_emotion_from_text(spoken)
	if next_avatar.has_method("hold_playback"):
		next_avatar.hold_playback()
	var voice_config := _voice_for_send(nxt)
	# A blank id would be spoken as the hub default, and marking the line
	# prefetched would keep that request from being resolved again.
	if str(voice_config.get("voice", "")).strip_edges() == "":
		if next_avatar.has_method("cancel_hold"):
			next_avatar.cancel_hold()
		return
	if not next_avatar.speak(spoken, emotion, voice_config):
		if next_avatar.has_method("cancel_hold"):
			next_avatar.cancel_hold()
		return
	nxt["prefetched"] = true


func _clean_text_for_speech(text: String) -> String:
	"""Clean text to remove markup and unwanted content for voice synthesis"""
	_ensure_text_cleanup_regexes()
	var cleaned = text
	
	# Remove BBCode tags first
	if _bbcode_strip_regex:
		cleaned = _bbcode_strip_regex.sub(cleaned, "", true)
	
	# Remove narrative markers and formatting
	cleaned = cleaned.replace("**", "")  # Remove ** narrative markers
	cleaned = cleaned.replace("*", "")   # Remove * emphasis
	
	# NEW: Remove performative glitches and stutters for TTS politeness
	cleaned = cleaned.replace("—", "-") # Replace em-dash with hyphen
	cleaned = cleaned.replace("…", ".") # Replace ellipsis with a period
	# Find and remove glitch text like *kkzzzt*
	if _glitch_strip_regex:
		cleaned = _glitch_strip_regex.sub(cleaned, "", true)
	
	# Only remove obvious XML/HTML tags that shouldn't be in natural text
	for re in _xml_strip_regexes:
		if re:
			cleaned = re.sub(cleaned, "", true)
	
	# Clean up stray markup characters but preserve natural text
	cleaned = cleaned.replace("<", " ")
	cleaned = cleaned.replace(">", " ")
	
	# Clean up whitespace
	while "  " in cleaned:
		cleaned = cleaned.replace("  ", " ")
	cleaned = cleaned.strip_edges()
	
	# If text becomes too short or empty after cleaning, provide fallback
	if cleaned.length() < 5:
		print("ScenSynVoiceBridge: Text too short after cleaning, using fallback")
		cleaned = "The story continues."
	
	return cleaned


func get_character_avatar(character_name: String) -> CharacterAvatar:
	"""Get the avatar for a specific character"""
	return character_avatars.get(character_name, null)

func is_character_speaking(character_name: String) -> bool:
	"""Check if a character is currently speaking"""
	var avatar = get_character_avatar(character_name)
	return avatar and avatar.is_currently_speaking()

func stop_character_speech(character_name: String):
	"""Stop speech for a specific character"""
	var avatar = get_character_avatar(character_name)
	if avatar:
		avatar.stop_speaking()

# Signal handlers
func _on_character_speech_started(character_name: String):
	character_speech_started.emit(character_name)

func _on_character_speech_finished(character_name: String):
	character_speech_finished.emit(character_name)
