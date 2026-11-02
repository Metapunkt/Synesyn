extends Node3D
class_name CharacterAvatar

const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")

func _voice_service() -> Node:
	return SynesynAutoloadAccessScript.voice_service()

# CharacterAvatar - Base class for speaking character avatars
# Handles voice playback, lip sync animation, and basic expressions

signal speech_started(character_name: String)
signal speech_finished(character_name: String)
signal lip_sync_frame(mouth_shape: String, intensity: float)

@export var character_name: String = "Unknown Character"
@export var enable_lip_sync: bool = true
@export var enable_expressions: bool = true

# Child nodes (DEPRECATED - now using global players from VoiceService)
@onready var audio_player_3d = get_node_or_null("AudioStreamPlayer3D")
@onready var mesh_instance = get_node_or_null("MeshInstance3D")

# Global audio player from VoiceService (survives scene changes)
var global_audio_player: AudioStreamPlayer = null
var _paused: bool = false
var _pending_lipsync_start: bool = false
var _started_emitted: bool = false
var _synthesis_requested: bool = false
var _hold_playback: bool = false
var _held_ready: bool = false
var _audio_start_time: float = 0.0
var _expected_duration: float = 0.0
var _last_playback_position: float = 0.0

# Animation components  
var lipsync_animator: LipSyncAnimator
var emotion_controller: EmotionController

# Current state
var is_speaking: bool = false
var current_audio_stream: AudioStream
var current_lipsync_data: Array = []

func _ready():
	print("CharacterAvatar: Initializing ", character_name)
	
	# Get global audio player from VoiceService (survives scene changes!)
	if _voice_service() and _voice_service().has_method("get_or_create_audio_player"):
		global_audio_player = _voice_service().get_or_create_audio_player(character_name)
		if global_audio_player:
			# CRITICAL: Disconnect any existing connections first (from destroyed avatars)
			# This prevents multiple avatar instances from receiving the same finished signal
			if global_audio_player.finished.is_connected(_on_audio_finished):
				global_audio_player.finished.disconnect(_on_audio_finished)
			
			# Now connect THIS instance
			global_audio_player.finished.connect(_on_audio_finished)
			print("CharacterAvatar: Using global audio player for ", character_name)
			
			# CRITICAL: Check if audio is ALREADY playing (from previous scene)
			# If so, sync our state to match the playing audio
			if global_audio_player.playing and global_audio_player.stream:
				is_speaking = true
				_started_emitted = true
				_audio_start_time = Time.get_ticks_msec() / 1000.0 - global_audio_player.get_playback_position()
				
				# Calculate expected duration from the stream
				_expected_duration = global_audio_player.stream.get_length() if global_audio_player.stream.has_method("get_length") else 0.0
	else:
		# Fallback to local player if VoiceService isn't available (shouldn't happen)
		global_audio_player = AudioStreamPlayer.new()
		global_audio_player.name = "LocalAudioPlayer"
		add_child(global_audio_player)
		global_audio_player.finished.connect(_on_audio_finished)
	
	# Initialize lip sync animator
	if not lipsync_animator:
		lipsync_animator = LipSyncAnimator.new()
		lipsync_animator.name = "LipSyncAnimator"
		add_child(lipsync_animator)
		lipsync_animator.setup_avatar(self)
	
	# Initialize emotion controller
	if not emotion_controller:
		emotion_controller = EmotionController.new()
		emotion_controller.name = "EmotionController"
		add_child(emotion_controller)
		emotion_controller.setup_avatar(self)
	
	# Connect to voice service signals
	if _voice_service():
		_voice_service().voice_synthesis_completed.connect(_on_voice_synthesis_completed)
		_voice_service().voice_service_error.connect(_on_speech_synthesis_failed)

func _exit_tree():
	"""Clean up when avatar is destroyed (e.g., scene change)"""
	# Disconnect from global audio player so destroyed avatars don't receive signals
	if global_audio_player and global_audio_player.finished.is_connected(_on_audio_finished):
		global_audio_player.finished.disconnect(_on_audio_finished)

func speak(text: String, emotion: String = "neutral", voice_config: Dictionary = {}) -> bool:
	"""Request speech synthesis for this character"""
	
	# CRITICAL: Check ALL busy states, not just is_speaking
	if is_speaking or _synthesis_requested or _pending_lipsync_start:
		print("CharacterAvatar: [WARNING] ", character_name, " BUSY - rejected request")
		return false
	
	# Set emotion
	if emotion_controller and enable_expressions:
		emotion_controller.set_emotion(emotion)
	
	# Request voice synthesis.
	# Do not hard-gate on instantaneous availability here: VoiceClient can queue
	# requests and flush when hub/direct service comes online.
	if _voice_service() and _voice_service().has_method("request_character_speech"):
		# Connect to synthesis completion signal
		if not _voice_service().voice_synthesis_completed.is_connected(_on_voice_synthesis_completed):
			_voice_service().voice_synthesis_completed.connect(_on_voice_synthesis_completed)
		
		# Set before the request returns. A cached clip can complete
		# inside that call, and the completion handler ignores audio
		# that arrives with no request in flight.
		# Drop the previous clip now. Releasing a held request before the new
		# audio arrives must not replay the last line under the new text.
		_synthesis_requested = true
		_held_ready = false
		current_audio_stream = null
		var success = _voice_service().request_character_speech(text, character_name, voice_config)
		if success:
			print("CharacterAvatar: Voice synthesis requested for ", character_name, " - waiting for audio")
			return true
		_synthesis_requested = false
		print("CharacterAvatar: Voice synthesis request failed for ", character_name)
		return false
	else:
		print("CharacterAvatar: Voice service not available for ", character_name)
		return false

func _on_voice_synthesis_completed(character: String, audio_data: PackedByteArray, lipsync_data: Array, duration: float):
	"""Handle completed voice synthesis"""
	if character != character_name:
		return  # Not for this character
	if not _synthesis_requested:
		return
	
	print("CharacterAvatar: ", character_name, " received audio data: ", audio_data.size(), " bytes")
	print("CharacterAvatar: Lip sync data sample: ", lipsync_data.slice(0, 3) if lipsync_data.size() > 3 else lipsync_data)
	
	# ── Detect audio format (WAV vs MP3) ──────────────────────────────────
	# Hub edge_tts provider returns MP3 (24 kHz / 48 kbps / mono);
	# SAPI / sidecar return WAV (RIFF).  Detect by magic bytes.
	var is_wav := (audio_data.size() >= 44 \
			and audio_data[0] == 0x52 and audio_data[1] == 0x49 \
			and audio_data[2] == 0x46 and audio_data[3] == 0x46)
	# MP3 sync word: 0xFF followed by 0xFB / 0xFA / 0xF3 / 0xF2 / 0xE3 / 0xE2
	# Also accept ID3 tag header (0x49 0x44 0x33) which precedes some MP3 files.
	var is_mp3 := false
	if not is_wav and audio_data.size() >= 4:
		is_mp3 = (audio_data[0] == 0xFF and (audio_data[1] & 0xE0) == 0xE0) \
				or (audio_data[0] == 0x49 and audio_data[1] == 0x44 and audio_data[2] == 0x33)

	var audio_stream: AudioStream = null

	if is_mp3:
		# ── MP3 path (edge_tts via hub) ──────────────────────────────────
		print("CharacterAvatar: MP3 detected (%d bytes) — using AudioStreamMP3" % audio_data.size())
		var mp3_stream := AudioStreamMP3.new()
		mp3_stream.data = audio_data
		audio_stream = mp3_stream
	else:
		# ── WAV path (SAPI / sidecar / direct mode) ─────────────────────
		var pcm_data: PackedByteArray = audio_data
		var sample_rate: int = 24000
		var bits_per_sample: int = 16
		var num_channels: int = 1

		if is_wav:
			num_channels = audio_data.decode_u16(22)
			sample_rate = audio_data.decode_u32(24)
			bits_per_sample = audio_data.decode_u16(34)
			# Find the "data" sub-chunk.
			var data_offset: int = 12
			while data_offset + 8 < audio_data.size():
				var is_data_chunk := (audio_data[data_offset] == 0x64 and audio_data[data_offset + 1] == 0x61 \
						and audio_data[data_offset + 2] == 0x74 and audio_data[data_offset + 3] == 0x61)
				var chunk_size: int = audio_data.decode_u32(data_offset + 4)
				if is_data_chunk:
					pcm_data = audio_data.slice(data_offset + 8, data_offset + 8 + chunk_size)
					break
				data_offset += 8 + chunk_size
				if chunk_size % 2 != 0:
					data_offset += 1
			print("CharacterAvatar: WAV parsed — rate=%d, bits=%d, channels=%d, pcm_bytes=%d" \
					% [sample_rate, bits_per_sample, num_channels, pcm_data.size()])
		else:
			print("CharacterAvatar: Unknown audio format; treating as raw PCM (%d bytes)" % audio_data.size())

		var wav_stream := AudioStreamWAV.new()
		# PADDING FIX: Append 1.0s of silence to prevent cutoff at the end
		var bytes_per_sample := bits_per_sample / 8
		var silence_bytes := int(1.0 * sample_rate) * bytes_per_sample * num_channels
		var padding := PackedByteArray()
		padding.resize(silence_bytes)
		padding.fill(0)
		var final_audio_data := pcm_data.duplicate()
		final_audio_data.append_array(padding)
		wav_stream.data = final_audio_data
		wav_stream.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
		wav_stream.mix_rate = sample_rate
		wav_stream.stereo = (num_channels >= 2)
		audio_stream = wav_stream
	
	current_audio_stream = audio_stream
	current_lipsync_data = lipsync_data
	_pending_lipsync_start = true
	_started_emitted = false
	
	# Prefer the exact stream length when available, fallback to duration provided
	var stream_length := 0.0
	if audio_stream.has_method("get_length"):
		stream_length = audio_stream.get_length()
	if stream_length > 0.0:
		_expected_duration = stream_length
	else:
		_expected_duration = duration
	
	# Start playback, unless the bridge is still playing the previous line.
	if _hold_playback:
		_held_ready = true
		return
	_start_audio_playback()

func _start_audio_playback():
	"""Start audio playback with lip sync"""
	if not current_audio_stream:
		print("CharacterAvatar: No audio stream to play for ", character_name)
		return
	
	# Choose audio player (prefer 2D for compatibility)
	var audio_player = global_audio_player
	
	if not audio_player:
		return
	
	# Set up audio
	audio_player.stream = current_audio_stream
	# _expected_duration is already set in _on_voice_synthesis_completed from actual audio data size
	_audio_start_time = Time.get_ticks_msec() / 1000.0
	_last_playback_position = 0.0
	audio_player.play()
	
	# Now mark as speaking since audio is actually playing
	is_speaking = true
	_synthesis_requested = false

func pause_speaking():
	"""Pause audio playback and lipsync"""
	var audio_player = global_audio_player
	if audio_player and audio_player.playing and not _paused:
		audio_player.set_stream_paused(true)
		_paused = true
		# Keep animator processing; elapsed time stays constant from playback_position
	_safely_emit_paused()

func resume_speaking():
	"""Resume audio playback and lipsync"""
	var audio_player = global_audio_player
	if audio_player and _paused:
		audio_player.set_stream_paused(false)
		_paused = false
		# Animator will resume advancing as playback_position increases
	_safely_emit_resumed()

func hold_playback() -> void:
	_hold_playback = true
	_held_ready = false


func cancel_hold() -> void:
	_hold_playback = false
	_held_ready = false


func release_held_playback() -> void:
	_hold_playback = false
	if _held_ready and current_audio_stream != null and not is_speaking:
		_held_ready = false
		_start_audio_playback()

func _on_speech_synthesis_failed(error: String):
	"""Handle failed voice synthesis"""
	print("CharacterAvatar: [ERROR] Speech synthesis failed for ", character_name, ": ", error)
	# Reset ALL state on failure so avatar doesn't get stuck
	is_speaking = false
	_synthesis_requested = false
	_pending_lipsync_start = false
	_started_emitted = false
	print("CharacterAvatar: [ERROR] State reset after synthesis failure for ", character_name)
	
	# CRITICAL: Emit speech_finished so the story log tracker can continue
	# even though synthesis failed - this prevents the entire playback from stalling
	speech_finished.emit(character_name)
	print("CharacterAvatar: [ERROR] Emitted speech_finished for ", character_name, " to allow progression")

func _process(_delta):
	"""Update lip sync animation during speech AND poll for completion"""
	if not is_speaking:
		return
	
	# Get audio player reference
	var audio_player = global_audio_player
	if not audio_player:
		return
	
	if audio_player.playing and audio_player.has_method("get_playback_position"):
		_last_playback_position = audio_player.get_playback_position()
	
	# Get playback position
	var elapsed: float = audio_player.get_playback_position() if audio_player.playing else 0.0
	
	# CRITICAL: Handle speech start - use elapsed > 0 OR audio_player.playing as triggers
	# Some systems report playback_position as 0 even when audio is playing
	if _pending_lipsync_start and (elapsed > 0.0 or audio_player.playing):
		# Start lipsync if enabled
		if enable_lip_sync and lipsync_animator and current_lipsync_data.size() > 0:
			lipsync_animator.start_lipsync_animation(current_lipsync_data)
		
		_pending_lipsync_start = false
		_started_emitted = true
		speech_started.emit(character_name)
	
	# Update lipsync if enabled
	if enable_lip_sync and lipsync_animator:
		lipsync_animator.set_external_elapsed_time(elapsed)
	
	# POLLING-BASED COMPLETION: ALWAYS check this, regardless of lipsync
	# This is CRITICAL - without this, is_currently_speaking() never becomes false!
	if _started_emitted and not _paused:
		var current_time = Time.get_ticks_msec() / 1000.0
		var real_elapsed = current_time - _audio_start_time
		var stream_length = _get_stream_length()
		
		if not audio_player.playing:
			# If the player has stopped, we are generally done.
			# Only ignore if it's a clear startup glitch (stopped almost instantly).
			var is_startup_glitch = (real_elapsed < 0.1 and stream_length > 0.5)
			
			if not is_startup_glitch:
				_complete_playback()
			# If it WAS a startup glitch, we might be stuck unless we restart play? 
			# But usually audio_player.playing won't flicker to false then true. 
			# So assuming it's done is safer than stalling forever.

func _update_lip_sync(playback_position: float):
	"""Update lip sync based on current audio position"""
	if not lipsync_animator or current_lipsync_data.is_empty():
		return
	
	# Let the LipSyncAnimator handle the timing and animation
	# This is called from _process if needed for manual sync
	pass

func _viseme_to_mouth_shape(viseme: String, mouth_open: float) -> String:
	"""Convert viseme and mouth_open value to mouth shape name"""
	# Use viseme information for better mouth shapes
	match viseme:
		"mouth_e":
			return "open" if mouth_open > 0.5 else "slightly_open"
		"mouth_s":
			return "slightly_open"
		"mouth_o":
			return "wide_open" if mouth_open > 0.6 else "open"
		"mouth_u":
			return "open"
		_:
			# Fallback to mouth_open intensity
			if mouth_open < 0.1:
				return "closed"
			elif mouth_open < 0.4:
				return "slightly_open"
			elif mouth_open < 0.7:
				return "open"
			else:
				return "wide_open"

func _get_stream_length() -> float:
	if global_audio_player and global_audio_player.stream and global_audio_player.stream.has_method("get_length"):
		return global_audio_player.stream.get_length()
	if current_audio_stream and current_audio_stream.has_method("get_length"):
		return current_audio_stream.get_length()
	return 0.0

func _has_reached_stream_end(stream_length: float) -> bool:
	if stream_length <= 0.0:
		return false
	# Relaxed tolerance to 0.2 seconds (200ms)
	var tolerance := 0.2
	var position := _last_playback_position
	if global_audio_player and global_audio_player.playing and global_audio_player.has_method("get_playback_position"):
		position = global_audio_player.get_playback_position()
	return position >= stream_length - tolerance

func _on_audio_finished():
	"""Handle audio playback completion signal"""
	print("CharacterAvatar: [SIGNAL] Received finished signal for ", character_name)
	
	# Validate this is a legitimate completion, not a spurious signal
	if not is_speaking:
		print("CharacterAvatar: [SIGNAL] Ignoring finished signal - not speaking")
		return
	
	# TRUST THE SIGNAL: If Godot says it's finished, it's finished.
	# We only guard against instant startup glitches (< 0.1s).
	# Checking against stream length caused stalls when playback position was slightly off (e.g. buffering).
	
	var stream_length = _get_stream_length()
	var current_time = Time.get_ticks_msec() / 1000.0
	var actual_elapsed = current_time - _audio_start_time
	
	# Only ignore if it finished instantly (likely a glitch) while expecting longer audio
	if actual_elapsed < 0.1 and stream_length > 0.5:
		print("CharacterAvatar: [SIGNAL] Ignoring premature finished signal (elapsed: ", actual_elapsed, "s)")
		return
	
	# Otherwise, accept it. If the player stopped, we can't make it play more anyway.
	print("CharacterAvatar: [SIGNAL] Legitimate completion detected")
	_complete_playback()

func _complete_playback():
	"""Complete the playback and emit finished signal (called by polling in _process)"""
	if not is_speaking:
		return  # Already completed
	
	print("CharacterAvatar: [TRACE] Completing playback for ", character_name)
	
	# Stop lip sync animation
	if lipsync_animator:
		lipsync_animator.stop_lipsync_animation()
	
	# Update state
	is_speaking = false
	_pending_lipsync_start = false
	_started_emitted = false
	_synthesis_requested = false
	_audio_start_time = 0.0
	_expected_duration = 0.0
	_last_playback_position = 0.0
	
	print("CharacterAvatar: [TRACE] Emitting speech_finished for ", character_name)
	speech_finished.emit(character_name)
	print("CharacterAvatar: [TRACE] ", character_name, " finished speaking")

func stop_speaking():
	"""Stop current speech"""
	var audio_player = global_audio_player
	
	# Track if we were actually speaking before stopping
	var was_speaking = is_speaking or _synthesis_requested
	
	if was_speaking:
		var caller := ""
		var stack := get_stack()
		if stack.size() > 1:
			var frame = stack[1]
			if typeof(frame) == TYPE_DICTIONARY:
				caller = "%s:%s" % [frame.get("source", "unknown"), frame.get("function", "unknown")]
		var playback_pos := 0.0
		if audio_player and audio_player.has_method("get_playback_position"):
			playback_pos = audio_player.get_playback_position()
		print("[TTS_STOP] character=", character_name, " position_s=", playback_pos, " caller=", caller)
	
	if audio_player and audio_player.playing:
		audio_player.stop()
	
	if lipsync_animator:
		lipsync_animator.stop_lipsync_animation()
	
	is_speaking = false
	_pending_lipsync_start = false
	_started_emitted = false
	_synthesis_requested = false
	_hold_playback = false
	_held_ready = false
	current_audio_stream = null
	_audio_start_time = 0.0
	_expected_duration = 0.0
	_last_playback_position = 0.0
	print("CharacterAvatar: Stopped speaking for ", character_name)
	
	# Emit finished signal so UI can return to idle state
	if was_speaking:
		speech_finished.emit(character_name)

func set_character_name(name: String):
	"""Set character name"""
	character_name = name
	print("CharacterAvatar: Character name set to: ", character_name)

func is_currently_speaking() -> bool:
	"""Check if character is currently speaking or waiting for audio to arrive
	
	Returns true in ALL these states:
	1. Synthesis requested but audio not yet received (_synthesis_requested=true)
	2. Audio received, playback starting (_pending_lipsync_start=true)
	3. Audio actively playing (is_speaking=true)
	
	Only returns false when:
	- All flags are false (completely idle)
	- OR a stuck state is detected (safety valve)
	"""
	
	# STATE 1: Waiting for synthesis to complete
	if _synthesis_requested:
		return true
	
	# STATE 2: Audio received, waiting to start playback
	if _pending_lipsync_start:
		return true
	
	# STATE 3: Audio is actively playing
	if is_speaking:
		# Double-check we're not in a stuck state
		var audio_player = global_audio_player
		if audio_player and not audio_player.playing and not _paused:
			# Audio stopped - check if this is expected (near completion) or stuck
			if _audio_start_time > 0 and _expected_duration > 0:
				var current_time = Time.get_ticks_msec() / 1000.0
				var elapsed = current_time - _audio_start_time
				
				# If we're past expected duration + 2 seconds, we're stuck
				if elapsed > (_expected_duration + 2.0):
					print("CharacterAvatar: [WARNING] ", character_name, " STUCK STATE detected (elapsed: ", elapsed, "s, expected: ", _expected_duration, "s)")
					# Force cleanup
					_complete_playback()
					return false
		
		# Not stuck, still speaking
		return true
	
	# All flags false - completely idle
	return false

func get_character_name() -> String:
	"""Get character name"""
	return character_name 

func _safely_emit_started():
	# No-op: started is now emitted in _process when playback actually begins
	pass

func _safely_emit_paused():
	# No specific signal for pause in this version
	pass

func _safely_emit_resumed():
	# No specific signal for resume in this version
	pass
