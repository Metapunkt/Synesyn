class_name SyntreeStageVoice
extends StoryStageVoice

## A Story Stage voice spoken through syntree_voice: the VoiceService autoload for
## synthesis, playback and transcription, and a ScenSynVoiceBridge for per-speaker queues
## and avatars. The bridge is created by attach(), not before, because it resolves its
## avatar container from the stage it is parented to.

const VoiceBridgeScript = preload("res://addons/syntree_voice/scripts/integration/scensyn_voice_bridge.gd")
const MicrophoneRecorderScript = preload("res://addons/syntree_voice/scripts/services/microphone_recorder.gd")

var _bridge: ScenSynVoiceBridge = null


func _ready() -> void:
	var vs: Node = _voice_service()
	if vs == null:
		return
	if not vs.tts_playback_finished.is_connected(_on_playback_finished):
		vs.tts_playback_finished.connect(_on_playback_finished)
	if not vs.voice_synthesis_completed.is_connected(_on_synthesis_completed):
		vs.voice_synthesis_completed.connect(_on_synthesis_completed)
	_connect_transcription()


func _voice_service() -> Node:
	return VoiceService if typeof(VoiceService) != TYPE_NIL else null


func attach(stage: Node) -> void:
	super.attach(stage)
	if _bridge != null and is_instance_valid(_bridge):
		return
	var vs: Node = _voice_service()
	if vs == null:
		return
	_bridge = VoiceBridgeScript.new()
	_bridge.name = "VoiceBridge"
	stage.add_child(_bridge)
	_bridge.voice_integration_ready.connect(func(): ready_to_speak.emit())
	print("StoryStage: VoiceBridge created (VoiceService autoload present)")
	if vs.is_voice_available():
		print("StoryStage: VoiceService available; ready to speak")
	else:
		print("StoryStage: VoiceService present but not available yet; will enable when ready")
	_bridge.character_speech_started.connect(_on_bridge_started)
	_bridge.character_speech_finished.connect(func(speaker: String): speech_finished.emit(speaker))
	print("StoryStage: Connected to VoiceBridge character speech signals.")


func _live_bridge() -> ScenSynVoiceBridge:
	if _bridge != null and is_instance_valid(_bridge):
		return _bridge
	return null


func is_present() -> bool:
	return _live_bridge() != null


func _on_playback_finished(speaker: String) -> void:
	playback_finished.emit(speaker)


func _on_synthesis_completed(speaker: String, _audio: PackedByteArray, _lipsync: Array, duration: float) -> void:
	synthesis_completed.emit(speaker, duration)


func get_skip_welcome() -> bool:
	var vs: Node = _voice_service()
	return vs.get_skip_welcome_speech() if vs else false


func set_skip_welcome(skip: bool) -> void:
	var vs: Node = _voice_service()
	if vs:
		vs.set_skip_welcome_speech(skip)


func refresh_roster(scenario: Dictionary) -> void:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb:
		vb.refresh_voice_roster(scenario)


func enable_character(speaker: String) -> void:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb:
		vb.set_voice_enabled_for_character(speaker, true)


func should_speak(voice_name: String, text: String) -> bool:
	var vb: ScenSynVoiceBridge = _live_bridge()
	return vb != null and vb.should_request_voice_for_message(voice_name, text)


func speak(voice_name: String, text: String, emotion: String = "neutral") -> bool:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb == null:
		return false
	var config := _voice_ready(voice_name)
	_route_playback(voice_name)
	return vb.request_character_speech(voice_name, text, emotion, config)


## Called again at the moment a queued line is actually sent. Returns the config
## the request must carry, so a mapping written later cannot change this line.
func bind_speaker_voice(speaker: String) -> Dictionary:
	return _voice_ready(speaker)


## A voice already stored for this speaker, including a hash-pool string.
## An empty result means a request sent now would use the hub default.
func installed_voice_id(speaker: String) -> String:
	var vs: Node = _voice_service()
	if vs == null or not vs.has_method("get_character_voices"):
		return ""
	var raw: Variant = vs.get_character_voices().get(speaker, "")
	if typeof(raw) == TYPE_DICTIONARY:
		return str((raw as Dictionary).get("voice", "")).strip_edges()
	return str(raw).strip_edges()


func _voice_ready(speaker: String) -> Dictionary:
	_apply_voice_for(speaker)
	if _stage == null or _stage.host == null or not _stage.host.has_method("voice_config_for"):
		return {}
	var config: Dictionary = _stage.host.voice_config_for(speaker)
	return config.duplicate(true)


func _apply_voice_for(speaker: String) -> void:
	if _stage == null or _stage.host == null or not _stage.host.has_method("voice_config_for"):
		return
	var config: Dictionary = _stage.host.voice_config_for(speaker)
	var voice_id := str(config.get("voice", "")).strip_edges()
	if voice_id == "":
		push_warning("StoryStage: no scenario voice for %s" % speaker)
		return
	var vs: Node = _voice_service()
	if vs and vs.has_method("set_character_voice_config"):
		vs.set_character_voice_config(speaker, config)
		print("StoryStage: ", speaker, " speaks as ", voice_id)


func _on_bridge_started(speaker: String) -> void:
	_speaker = speaker
	_route_playback(speaker)
	speech_started.emit(speaker)


func _route_playback(speaker: String) -> void:
	if speaker == "" or _stage == null or _stage.motion == null:
		return
	var vs: Node = _voice_service()
	if vs == null or not vs.has_method("get_or_create_audio_player"):
		return
	var player: AudioStreamPlayer = vs.get_or_create_audio_player(speaker)
	if player:
		player.bus = _stage.motion.bus_for(speaker)


func playback_position() -> float:
	var who := speaking_character()
	if who == "":
		who = _speaker
	if who == "":
		return -1.0
	var vs: Node = _voice_service()
	if vs == null or not vs.has_method("get_or_create_audio_player"):
		return -1.0
	var player: AudioStreamPlayer = vs.get_or_create_audio_player(who)
	if player and player.playing:
		return player.get_playback_position()
	return -1.0


func speaking_character() -> String:
	var vb: ScenSynVoiceBridge = _live_bridge()
	return vb.currently_speaking_character if vb else ""


func is_busy() -> bool:
	var vb: ScenSynVoiceBridge = _live_bridge()
	return vb != null and (vb.is_processing_queue or vb.currently_speaking_character != "" or vb.speech_queue.size() > 0)


func pause() -> void:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb:
		vb.pause_queue()


func resume() -> void:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb:
		vb.resume_queue()


func stop_all() -> void:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb:
		vb.stop_all_speech()


func cancel_synthesis() -> void:
	var vs: Node = _voice_service()
	if vs:
		vs.cancel_current_request(true)
		vs.clear_all_synthesis()


func clear_synthesis() -> void:
	var vs: Node = _voice_service()
	if vs:
		vs.clear_all_synthesis()


func clear_activity() -> void:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb:
		vb.clear_all_voice_activity()


func stop_welcome_narration() -> void:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb == null:
		return
	print("StoryStage: Stopping welcome speech playback")
	if vb.character_avatars.has("Narrator"):
		var narrator_avatar = vb.character_avatars["Narrator"]
		if narrator_avatar and narrator_avatar.has_method("stop_speaking"):
			narrator_avatar.stop_speaking()
	vb.speech_queue.clear()
	vb.currently_speaking_character = ""
	vb.is_processing_queue = false


func recover_stuck_speaker() -> String:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb == null or vb.currently_speaking_character == "":
		return ""
	var stuck_char: String = vb.currently_speaking_character
	if vb.character_avatars.has(stuck_char):
		var avatar = vb.character_avatars[stuck_char]
		if avatar and avatar.has_method("stop_speaking"):
			avatar.stop_speaking()
			print("StoryLogTracker: Called stop_speaking() on stuck avatar")
	return stuck_char


func get_lipsync_frames(voice_name: String, speaker: String) -> Array:
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb == null:
		return []
	var avatar = null
	if voice_name != "" and vb.character_avatars.has(voice_name):
		avatar = vb.character_avatars[voice_name]
	elif speaker != "" and vb.character_avatars.has(speaker):
		avatar = vb.character_avatars[speaker]
	if avatar and is_instance_valid(avatar) and avatar is CharacterAvatar:
		var frames_any: Variant = (avatar as CharacterAvatar).current_lipsync_data
		if typeof(frames_any) == TYPE_ARRAY:
			return frames_any
	return []


func health_lines() -> Array[String]:
	var lines: Array[String] = []
	var vb: ScenSynVoiceBridge = _live_bridge()
	if vb == null:
		lines.append("VoiceBridge: (none)")
		return lines
	lines.append("VoiceBridge:")
	lines.append("- speaking=%s paused=%s processing=%s queue=%d" % [
		vb.currently_speaking_character,
		str(vb.is_queue_paused),
		str(vb.is_processing_queue),
		int(vb.speech_queue.size()),
	])
	lines.append("- avatars=%d" % int(vb.character_avatars.size()))
	var shown := 0
	for char_key in vb.character_avatars.keys():
		if shown >= 12:
			lines.append("  ...")
			break
		var avatar = vb.character_avatars[char_key]
		if avatar == null or not is_instance_valid(avatar):
			continue
		var is_speaking_flag := false
		var pending_lipsync_flag := false
		var synth_flag := false
		if avatar is CharacterAvatar:
			var char_avatar: CharacterAvatar = avatar as CharacterAvatar
			is_speaking_flag = (char_avatar.is_speaking == true)
			pending_lipsync_flag = (char_avatar._pending_lipsync_start == true)
			synth_flag = (char_avatar._synthesis_requested == true)
		lines.append("  %s speak=%s synth=%s lipsync=%s" % [str(char_key), str(is_speaking_flag), str(synth_flag), str(pending_lipsync_flag)])
		shown += 1
	return lines


func set_save_recordings(enabled: bool) -> void:
	var vs: Node = _voice_service()
	if vs and vs.has_method("set_save_recordings_enabled"):
		vs.set_save_recordings_enabled(enabled)


func create_recorder() -> Node:
	return MicrophoneRecorderScript.new()


func transcribe(audio_path: String) -> bool:
	if audio_path.strip_edges() == "":
		transcription_completed.emit("", "Recording failed or was empty.")
		return false
	var vs: Node = _voice_service()
	var voice_client: Node = vs.voice_client if vs else null
	if voice_client == null or not voice_client.has_method("transcribe_audio"):
		transcription_completed.emit("", "Voice service is not ready to transcribe.")
		return false
	voice_client.transcribe_audio(audio_path)
	return true


## The service already forwards the client's transcript. Listening to both
## delivered the same result twice, and Auto send then posted the line twice.
func _connect_transcription() -> void:
	var vs: Node = _voice_service()
	if vs == null:
		return
	if vs.has_signal("transcription_completed") and not vs.transcription_completed.is_connected(_on_transcription_completed):
		vs.transcription_completed.connect(_on_transcription_completed)
	if vs.voice_client == null and vs.has_signal("voice_service_ready"):
		if not vs.voice_service_ready.is_connected(_on_voice_service_ready):
			vs.voice_service_ready.connect(_on_voice_service_ready)


func _on_voice_service_ready() -> void:
	var vs: Node = _voice_service()
	if vs and vs.voice_service_ready.is_connected(_on_voice_service_ready):
		vs.voice_service_ready.disconnect(_on_voice_service_ready)
	_connect_transcription()


func _on_transcription_completed(text: String, error: String) -> void:
	transcription_completed.emit(text, error)
