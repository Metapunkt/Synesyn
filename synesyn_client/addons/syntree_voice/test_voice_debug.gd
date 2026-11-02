extends Node

const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")

func _voice_service() -> Node:
	return SynesynAutoloadAccessScript.voice_service()

# ============================================================
# COMPREHENSIVE VOICE PIPELINE DIAGNOSTIC
# Attach to any node, or run via: Godot Editor > Run Current Scene
# after setting this script on a Node in a minimal .tscn.
# Copy the FULL console output and share it for diagnosis.
# ============================================================

func _ready():
	print("\n========== VOICE PIPELINE DIAGNOSTIC ==========\n")
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- STEP 1: Autoload existence ----
	print("[STEP 1] _voice_service() autoload")
	if not _voice_service():
		print("  FAIL: _voice_service() autoload is NULL — addon not registered.")
		_done()
		return
	print("  OK: _voice_service() found")
	print("  is_enabled          = ", _voice_service().is_enabled)
	print("  is_service_running  = ", _voice_service().is_service_running)
	print("  provider_mode       = ", _voice_service().provider_mode)
	print("  hub_voice_url       = ", _voice_service().hub_voice_url)
	print("  voice_service_url   = ", _voice_service().voice_service_url)
	print("  hub_tts_pref        = ", _voice_service().hub_tts_provider_preference)
	print("  character_mappings  = ", _voice_service().character_voice_mapping)

	# ---- STEP 2: VoiceClient existence & state ----
	print("\n[STEP 2] VoiceClient")
	var vc = _voice_service().voice_client
	if not vc:
		print("  FAIL: voice_client is NULL — _setup_voice_client() did not run.")
		_done()
		return
	print("  OK: voice_client exists")
	print("  provider_mode       = ", vc.provider_mode)
	print("  service_url         = ", vc.service_url)
	print("  hub_url             = ", vc.hub_url)
	print("  is_service_available= ", vc.is_service_available)
	print("  is_processing_req   = ", vc.is_processing_request)
	print("  request_queue size  = ", vc.request_queue.size())
	print("  _pending_req_type   = ", vc._pending_request_type)

	# ---- STEP 3: Direct HTTP health probe (bypasses VoiceClient) ----
	print("\n[STEP 3] Raw HTTP health probe")
	var base_url: String = vc.hub_url if vc.provider_mode == "hub" else vc.service_url
	var health_url := base_url.rstrip("/") + "/health"
	print("  Target: ", health_url)

	var http := HTTPRequest.new()
	add_child(http)
	await get_tree().process_frame
	var err := http.request(health_url, ["Content-Type: application/json"], HTTPClient.METHOD_GET)
	if err != OK:
		print("  FAIL: HTTPRequest.request() returned error ", err)
		http.queue_free()
		_done()
		return
	var resp = await http.request_completed
	var h_result: int = resp[0]
	var h_code: int = resp[1]
	var h_body: PackedByteArray = resp[3]
	http.queue_free()
	print("  result=%d  response_code=%d  body_bytes=%d" % [h_result, h_code, h_body.size()])
	if h_code == 200:
		print("  body (first 500 chars): ", h_body.get_string_from_utf8().left(500))
		print("  OK: Health endpoint reachable")
	else:
		print("  FAIL: Health endpoint returned non-200. body: ", h_body.get_string_from_utf8().left(500))
		_done()
		return

	# ---- STEP 4: Direct HTTP synthesis probe (bypasses VoiceClient) ----
	print("\n[STEP 4] Raw HTTP synthesis probe")
	var synth_url := ""
	var synth_payload := {}
	if vc.provider_mode == "hub":
		synth_url = vc.hub_url.rstrip("/") + "/voice/speak"
		synth_payload = {"text": "Hello.", "character": "Narrator", "return_lipsync": false}
	else:
		synth_url = vc.service_url.rstrip("/") + "/synthesize"
		synth_payload = {"text": "Hello.", "character": "Narrator"}
	print("  Target: ", synth_url)
	print("  Payload: ", synth_payload)

	var http2 := HTTPRequest.new()
	http2.timeout = 30.0
	add_child(http2)
	await get_tree().process_frame
	var json_body := JSON.stringify(synth_payload)
	err = http2.request(synth_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, json_body)
	if err != OK:
		print("  FAIL: HTTPRequest.request() returned error ", err)
		http2.queue_free()
		_done()
		return
	resp = await http2.request_completed
	var s_result: int = resp[0]
	var s_code: int = resp[1]
	var s_headers: PackedStringArray = resp[2]
	var s_body: PackedByteArray = resp[3]
	http2.queue_free()
	print("  result=%d  response_code=%d  body_bytes=%d" % [s_result, s_code, s_body.size()])
	# Print content-type header if present
	for h in s_headers:
		if h.to_lower().begins_with("content-type"):
			print("  ", h)

	if s_code != 200:
		print("  FAIL: Synthesis endpoint returned non-200")
		print("  body: ", s_body.get_string_from_utf8().left(1000))
		_done()
		return

	# Determine response format
	var is_wav := _is_riff(s_body)
	var json_parsed: Variant = null
	if not is_wav:
		json_parsed = JSON.parse_string(s_body.get_string_from_utf8())

	if is_wav:
		print("  Response: raw WAV bytes (%d bytes)" % s_body.size())
		print("  OK: Server returned raw audio — VoiceClient should accept this.")
	elif json_parsed != null and typeof(json_parsed) == TYPE_DICTIONARY:
		print("  Response: JSON dictionary")
		print("  Keys: ", (json_parsed as Dictionary).keys())
		var d: Dictionary = json_parsed
		# Check expected keys
		if d.has("audio_url"):
			print("  audio_url = ", str(d.get("audio_url", "")).left(200))
			# Try reading the file
			var fpath = _file_uri_to_path(str(d.get("audio_url", "")))
			print("  Resolved path = ", fpath)
			print("  File exists = ", FileAccess.file_exists(fpath))
			if FileAccess.file_exists(fpath):
				var f = FileAccess.open(fpath, FileAccess.READ)
				if f:
					print("  File size = ", f.get_length(), " bytes")
					f.close()
		if d.has("audio"):
			print("  audio key length = ", str(d.get("audio", "")).length(), " chars (base64)")
		if d.has("audio_data"):
			print("  audio_data key length = ", str(d.get("audio_data", "")).length(), " chars (base64)")
		if d.has("ok"):
			print("  ok = ", d.get("ok"))
		if d.has("success"):
			print("  success = ", d.get("success"))
		if d.has("error"):
			print("  error = ", d.get("error"))
		print("  OK: Synthesis returned JSON.")
	else:
		print("  UNKNOWN RESPONSE FORMAT")
		print("  First 500 chars: ", s_body.get_string_from_utf8().left(500))
		print("  First 16 hex bytes: ", _hex(s_body.slice(0, 16)))
		_done()
		return

	# ---- STEP 5: Audio playback test (synthetic tone) ----
	print("\n[STEP 5] AudioStreamPlayer playback test (synthetic 440 Hz tone)")
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	add_child(player)
	var tone := _make_sine_wav(440.0, 0.5, 24000)
	var stream := AudioStreamWAV.new()
	stream.data = tone
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 24000
	stream.stereo = false
	player.stream = stream
	player.play()
	print("  Playing 0.5s 440 Hz tone now...")
	print("  player.playing = ", player.playing)
	print("  player.stream  = ", player.stream)
	print("  player.bus     = ", player.bus)
	print("  player.volume_db = ", player.volume_db)
	await get_tree().create_timer(1.0).timeout
	print("  After 1s: player.playing = ", player.playing)
	if player.playing:
		print("  WARNING: Player still reports playing after 0.5s tone — may indicate issue")
	else:
		print("  OK: Tone finished. If you heard a beep, audio output works.")
	player.queue_free()

	# ---- STEP 6: Test actual VoiceClient synthesis pipeline ----
	print("\n[STEP 6] VoiceClient pipeline test")
	# Temporarily connect to signals to observe
	var got_completed := [false]
	var got_failed := [false]
	var completed_data := {}
	var failed_reason := ""

	var _on_completed = func(character: String, audio_data: PackedByteArray, lipsync_data: Array, duration: float):
		got_completed[0] = true
		completed_data["character"] = character
		completed_data["audio_bytes"] = audio_data.size()
		completed_data["lipsync_count"] = lipsync_data.size()
		completed_data["duration"] = duration
		completed_data["is_wav"] = _is_riff(audio_data)
		print("  >> synthesis_completed signal received: character=%s bytes=%d lipsync=%d dur=%.2f is_wav=%s" \
				% [character, audio_data.size(), lipsync_data.size(), duration, str(_is_riff(audio_data))])

	var _on_failed = func(character: String, error: String):
		got_failed[0] = true
		failed_reason = error
		print("  >> synthesis_failed signal received: character=%s error=%s" % [character, error])

	vc.synthesis_completed.connect(_on_completed)
	vc.synthesis_failed.connect(_on_failed)

	print("  Calling _voice_service().request_character_speech('Test audio.', 'Narrator')...")
	print("  vc.is_service_available = ", vc.is_service_available)
	print("  vc.is_processing_request = ", vc.is_processing_request)
	var req_result = _voice_service().request_character_speech("Test audio.", "Narrator")
	print("  request_character_speech returned: ", req_result)
	print("  vc.is_processing_request = ", vc.is_processing_request)
	print("  vc.request_queue size = ", vc.request_queue.size())

	# Wait up to 15 seconds for response
	var waited := 0.0
	while waited < 15.0 and not got_completed[0] and not got_failed[0]:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if int(waited * 10) % 50 == 0:
			print("  ... waiting (%.1fs) processing=%s queue=%d" % [waited, str(vc.is_processing_request), vc.request_queue.size()])

	vc.synthesis_completed.disconnect(_on_completed)
	vc.synthesis_failed.disconnect(_on_failed)

	if got_completed[0]:
		print("  OK: Synthesis completed successfully.")
	elif got_failed[0]:
		print("  FAIL: Synthesis failed. Reason: ", failed_reason)
	else:
		print("  FAIL: No signal received after 15s.")
		print("  vc.is_processing_request = ", vc.is_processing_request)
		print("  vc.request_queue size    = ", vc.request_queue.size())
		print("  vc._pending_request_type = ", vc._pending_request_type)
		print("  vc.current_character     = ", vc.current_character)

	# ---- STEP 7: Global audio player check ----
	print("\n[STEP 7] Global audio players")
	print("  Registered players: ", _voice_service().global_audio_players.keys())
	for pname in _voice_service().global_audio_players:
		var p: AudioStreamPlayer = _voice_service().global_audio_players[pname]
		if p and is_instance_valid(p):
			print("  [%s] playing=%s volume_db=%.1f bus=%s stream=%s" % [pname, str(p.playing), p.volume_db, p.bus, str(p.stream)])
		else:
			print("  [%s] INVALID/FREED" % pname)

	_done()


func _done():
	print("\n========== DIAGNOSTIC COMPLETE ==========")
	print("Copy everything above and share for diagnosis.\n")


func _is_riff(data: PackedByteArray) -> bool:
	if data.size() < 12:
		return false
	return data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46


func _hex(data: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for b in data:
		parts.append("%02x" % b)
	return " ".join(parts)


func _file_uri_to_path(uri: String) -> String:
	var s = uri.strip_edges()
	if s.begins_with("file:///"):
		s = s.substr(len("file:///"))
	elif s.begins_with("file://"):
		s = s.substr(len("file://"))
	if s.begins_with("/"):
		s = s.substr(1)
	return s


func _make_sine_wav(freq: float, duration_sec: float, sample_rate: int) -> PackedByteArray:
	var num_samples := int(duration_sec * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_rate)
		var value := sin(t * freq * TAU) * 0.3  # 30% volume
		var sample := int(clamp(value * 32767.0, -32768.0, 32767.0))
		data.encode_s16(i * 2, sample)
	return data
