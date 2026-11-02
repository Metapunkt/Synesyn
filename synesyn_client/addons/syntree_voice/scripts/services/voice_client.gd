extends Node

# VoiceClient - HTTP client for communicating with the external Python TTS service
# Handles all HTTP requests, response parsing, and error handling

signal synthesis_completed(character: String, audio_data: PackedByteArray, lipsync_data: Array, duration: float)
signal synthesis_failed(character: String, error: String)
signal service_status_changed(is_available: bool)
signal transcription_completed(text: String, error: String)

var http_request: HTTPRequest
var _health_request: HTTPRequest
var _health_inflight: bool = false
var service_url: String = "http://127.0.0.1:8000" # legacy direct service
var hub_url: String = "http://127.0.0.1:17777"
var provider_mode: String = "direct" # "direct" | "hub"
var hub_tts_provider_preference: String = "auto" # "auto" | "edge_tts" | "sapi" | "sidecar"
var is_service_available: bool = false
# INCREASED TIMEOUT: 10 seconds is too short for long TTS generation + download
var request_timeout: float = 60.0 

# STT recording persistence (hub only). Default deny for privacy.
var save_recordings: bool = false
var session_app_id: String = "scensyn"

# Request queue to handle multiple synthesis requests
var request_queue: Array = []
var is_processing_request: bool = false
var current_character: String = "" # Track current character being processed
var current_voice: String = ""      # Track requested voice (optional)
var _pending_request_type: String = "" # v1: currently only "speak" on http_request channel
var _active_request: Dictionary = {}

func _disable_proxy_for_local(http: HTTPRequest, url: String) -> void:
	# On some Windows setups, system proxies can interfere even with localhost calls.
	# Mirror HubProcessManager's stabilization.
	if not is_instance_valid(http):
		return
	var u := String(url).strip_edges().to_lower()
	var is_local := (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1) or (u.find("[::1]") != -1)
	if not is_local:
		return
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)

func _normalize_loopback_url(url: String) -> String:
	# Windows/Godot can prefer IPv6 for "localhost" and fail to fall back when
	# the hub only binds IPv4 (127.0.0.1). Normalize localhost and loopback IPv6.
	var u := String(url).strip_edges()
	if u.is_empty():
		return u
	if u.find("://") == -1:
		u = "http://" + u
	var lower := u.to_lower()
	if lower.begins_with("http://localhost"):
		u = "http://127.0.0.1" + u.substr("http://localhost".length())
	elif lower.begins_with("https://localhost"):
		u = "https://127.0.0.1" + u.substr("https://localhost".length())
	elif lower.begins_with("http://[::1]"):
		u = "http://127.0.0.1" + u.substr("http://[::1]".length())
	elif lower.begins_with("https://[::1]"):
		u = "https://127.0.0.1" + u.substr("https://[::1]".length())
	return u

func _ready():
	# Create HTTP request node
	http_request = HTTPRequest.new()
	add_child(http_request)
	
	# Configure HTTP request
	http_request.timeout = request_timeout
	http_request.request_completed.connect(_on_request_completed)

	# Dedicated health channel: synthesis requests should NOT be able to block
	# recovery detection after hub restarts.
	_health_request = HTTPRequest.new()
	add_child(_health_request)
	_health_request.timeout = 2.5
	_health_request.request_completed.connect(_on_health_request_completed)
	
	# NOTE: Do NOT call check_service_availability() here.
	# At this point provider_mode is still the default ("direct") because the
	# VoiceServiceManager hasn't called set_provider_mode() yet.  Firing an
	# early health check to the wrong URL wastes the request slot and blocks
	# correct checks (is_processing_request stays true until the wrong-URL
	# request times out or fails).  The VoiceServiceManager's _setup_voice_client()
	# and health poll timer handle the initial check with the correct URL.

func check_service_availability():
	"""Test if the Python voice service is running and responsive"""
	if _health_inflight:
		return
	if not is_instance_valid(_health_request):
		return
	_health_inflight = true
	var headers = ["Content-Type: application/json"]
	var url := _base_url().rstrip("/") + "/health"
	_disable_proxy_for_local(_health_request, url)
	var error = _health_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_health_inflight = false
		_update_service_status(false)

func _on_health_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_health_inflight = false
	if response_code == 200:
		_handle_health_success(body)
	else:
		_handle_health_error(response_code, body)

func _handle_health_success(body: PackedByteArray) -> void:
	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	# Some direct providers return non-JSON 200 payloads; treat as reachable.
	if typeof(parsed) != TYPE_DICTIONARY:
		print("VoiceClient: Health endpoint returned non-JSON payload; treating service as reachable")
		_update_service_status(true)
		return
	var response_data: Dictionary = parsed as Dictionary
	if provider_mode == "hub":
		var hub_ok := false
		if response_data.has("ok"):
			hub_ok = bool(response_data.get("ok", false))
		elif response_data.has("status"):
			hub_ok = str(response_data.get("status", "")).to_lower() == "ok"
		_update_service_status(hub_ok)
		# Rely on _update_service_status logging; avoid spamming health logs.
		return
	# direct
	if response_data.has("status"):
		var status_ok := str(response_data.get("status", "")).to_lower() == "ok"
		_update_service_status(status_ok)
		return
	if response_data.has("ok"):
		_update_service_status(bool(response_data.get("ok", false)))
		return
	print("VoiceClient: Direct health payload unrecognized but endpoint reachable")
	_update_service_status(true)

func _handle_health_error(response_code: int, body: PackedByteArray) -> void:
	_update_service_status(false)

func synthesize_speech(text: String, character: String = "Narrator", voice: String = "", character_mapping: Dictionary = {}, voice_config: Dictionary = {}) -> bool:
	"""Request speech synthesis for given text and character (optional voice)"""
	# Intent:
	# - When provider_mode == "hub", the hub persists artifacts + provenance in the substrate.
	# - We pass character_mapping (if provided) to allow hub provenance to record the mapping decision:
	#   (character name -> voice id, mapping version/source).
	# - This remains optional so legacy clients and direct-mode users are not forced into new schemas.
	if not is_service_available:
		print("VoiceClient: Service not available, queuing request")
		request_queue.push_back({"text": text, "character": character, "voice": voice, "character_mapping": character_mapping, "voice_config": voice_config})
		# Queued successfully: report accepted so upstream queue/state machines
		# don't treat this as a hard failure and drop the turn.
		return true
	
	if is_processing_request:
		print("VoiceClient: Busy, queuing request")
		request_queue.push_back({"text": text, "character": character, "voice": voice, "character_mapping": character_mapping, "voice_config": voice_config})
		return true
	
	return _send_synthesis_request(text, character, voice, character_mapping, voice_config)

func _send_synthesis_request(text: String, character: String, voice: String = "", character_mapping: Dictionary = {}, voice_config: Dictionary = {}, retried_cache: bool = false) -> bool:
	"""Send the actual synthesis request to the Python service"""
	is_processing_request = true
	_pending_request_type = "speak"
	current_character = character # Store character for response handling
	current_voice = voice
	_active_request = {
		"text": text,
		"character": character,
		"voice": voice,
		"character_mapping": character_mapping,
		"voice_config": voice_config,
		"retried_cache": retried_cache,
	}
	
	# CRITICAL: Ensure timeout is applied (in case script reloaded after _ready)
	if http_request:
		http_request.timeout = request_timeout
	
	var request_data = {"text": text, "character": character}
	var url := ""
	if provider_mode == "hub":
		url = hub_url.rstrip("/") + "/voice/speak"
		request_data["return_lipsync"] = true
		if hub_tts_provider_preference != "" and hub_tts_provider_preference != "auto":
			request_data["provider_preference"] = hub_tts_provider_preference
		if character_mapping != null and typeof(character_mapping) == TYPE_DICTIONARY and not character_mapping.is_empty():
			request_data["character_mapping"] = character_mapping
		var voice_payload: Dictionary = {}
		if voice != "":
			voice_payload["name"] = voice
		if voice_config != null and typeof(voice_config) == TYPE_DICTIONARY and not voice_config.is_empty():
			var cfg: Dictionary = voice_config
			if cfg.has("voice") and String(cfg.get("voice", "")).strip_edges() != "":
				voice_payload["name"] = String(cfg.get("voice", "")).strip_edges()
			if cfg.has("rate"):
				voice_payload["rate"] = String(cfg.get("rate", "+0%"))
			if cfg.has("volume"):
				voice_payload["volume"] = String(cfg.get("volume", "+0%"))
			if cfg.has("pitch"):
				voice_payload["pitch"] = String(cfg.get("pitch", "+0Hz"))
		if not voice_payload.is_empty():
			request_data["voice"] = voice_payload
	else:
		url = service_url.rstrip("/") + "/synthesize"
		if voice != "":
			request_data["voice"] = voice
		if typeof(voice_config) == TYPE_DICTIONARY:
			var direct_cfg: Dictionary = voice_config
			var named := str(direct_cfg.get("voice", "")).strip_edges()
			if named != "":
				request_data["voice"] = named
			for field_name in ["rate", "volume", "pitch"]:
				var field_value := str(direct_cfg.get(field_name, "")).strip_edges()
				if field_value != "":
					request_data[field_name] = field_value
	
	var json_string = JSON.stringify(request_data)
	var headers = ["Content-Type: application/json"]
	
	print("VoiceClient: Sending synthesis request for character: ", character, ", voice: ", str(request_data.get("voice", "<default>")))
	_disable_proxy_for_local(http_request, url)
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_string)
	
	if error != OK:
		print("VoiceClient: Failed to send synthesis request: ", error)
		synthesis_failed.emit(character, "HTTP request failed: " + str(error))
		is_processing_request = false
		_pending_request_type = ""
		current_character = ""
		current_voice = ""
		_process_next_request()
		return false
	
	return true

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	"""Handle HTTP response from the Python service"""
	is_processing_request = false
	
	# Parse response based on the endpoint
	var request_url = http_request.get_http_client_status()
	
	if response_code == 200:
		_handle_successful_response(body)
	else:
		_handle_error_response(response_code, body)
	
	# Process next queued request
	_process_next_request()

func _handle_successful_response(body: PackedByteArray):
	"""Parse successful response from the voice service"""
	var json = JSON.new()
	var body_text := body.get_string_from_utf8()
	var parse_result = json.parse(body_text)
	
	if parse_result != OK:
		# Direct-mode compatibility: some servers return raw WAV bytes from /synthesize
		# instead of JSON. Accept RIFF payloads as successful synthesis.
		if _pending_request_type == "speak" and _looks_like_wav_bytes(body):
			_pending_request_type = ""
			var character_wav = current_character if current_character != "" else "Unknown"
			print("VoiceClient: Received raw WAV payload (non-JSON) for ", character_wav, ", bytes=", body.size())
			synthesis_completed.emit(character_wav, body, [], 0.0)
			current_character = ""
			current_voice = ""
			return
		print("VoiceClient: Failed to parse JSON response -> treating as synthesis failure")
		var character = current_character if current_character != "" else "unknown"
		synthesis_failed.emit(character, body_text.left(512))
		current_character = ""
		current_voice = ""
		return
	
	var response_data = json.data
	
	# Route response based on tracked request type (avoids misidentifying speak
	# responses as health because both contain an "ok" field in hub mode).
	_pending_request_type = ""
	
	if provider_mode == "hub":
		# Hub response: {ok:true, audio_url:file://..., lipsync_url:file://..., duration_sec:...}
		if typeof(response_data) == TYPE_DICTIONARY and response_data.get("ok", false) and response_data.has("audio_url"):
			var character = current_character if current_character else "Unknown"
			var audio_url: String = str(response_data.get("audio_url", ""))
			var lipsync_url: String = str(response_data.get("lipsync_url", ""))
			var duration = float(response_data.get("duration_sec", 0.0))
			
			var audio_path = _file_uri_to_path(audio_url)
			var used_provider := str(response_data.get("provider_used", "")).strip_edges().to_lower()
			var used_voice := str(response_data.get("voice_used", "")).strip_edges()
			var wanted_voice := current_voice.strip_edges()
			if wanted_voice == "" and typeof(_active_request.get("voice_config")) == TYPE_DICTIONARY:
				wanted_voice = str((_active_request["voice_config"] as Dictionary).get("voice", "")).strip_edges()
			# An earlier Edge failure cached a SAPI default WAV under the neural
			# voice's key. Removing the file makes the hub drop that cache entry
			# and synthesize the line with the requested voice.
			if (
				bool(response_data.get("cached", false))
				and not bool(_active_request.get("retried_cache", false))
				and hub_tts_provider_preference != "sapi"
				and (used_provider == "sapi" or (wanted_voice != "" and used_voice != "" and used_voice != wanted_voice))
			):
				if audio_path != "" and FileAccess.file_exists(audio_path):
					DirAccess.remove_absolute(audio_path)
				var retry := _active_request.duplicate(true)
				retry["retried_cache"] = true
				request_queue.push_front(retry)
				current_character = ""
				current_voice = ""
				return
			var audio_data = _read_file_bytes(audio_path)
			if audio_data.size() == 0:
				synthesis_failed.emit(character, "Hub returned empty audio data")
				current_character = ""
				current_voice = ""
				return
			
			var lipsync_data: Array = []
			if not lipsync_url.is_empty():
				var lipsync_path = _file_uri_to_path(lipsync_url)
				lipsync_data = _read_json_array(lipsync_path)
			
			print("[TTS_PAYLOAD/HUB] character=", character, " bytes=", audio_data.size(), " lipsync=", lipsync_data.size(), " duration_s=", duration)
			synthesis_completed.emit(character, audio_data, lipsync_data, duration)
			
			current_character = ""
			current_voice = ""
			return
		# else: fall through to error
	
	# Handle synthesis response (direct mode / legacy services).
	# Accept both "audio" and "audio_data" payload keys for compatibility.
	if typeof(response_data) == TYPE_DICTIONARY:
		var success_flag := bool(response_data.get("success", response_data.get("ok", false)))
		var audio_base64 := ""
		if response_data.has("audio"):
			audio_base64 = str(response_data.get("audio", ""))
		elif response_data.has("audio_data"):
			audio_base64 = str(response_data.get("audio_data", ""))
		if success_flag and not audio_base64.is_empty():
		# Use the tracked character from the request
			var character = current_character if current_character else "Unknown"
		
			# Decode base64 audio bytes
			var audio_data = Marshalls.base64_to_raw(audio_base64)
		
			# Parse lip sync data
			var lipsync_data = response_data.get("lipsync", [])
		
			var duration = float(response_data.get("duration", 0.0))
		
			print("[TTS_PAYLOAD] character=", character, " bytes=", audio_data.size(), " lipsync=", lipsync_data.size(), " duration_s=", duration)
			synthesis_completed.emit(character, audio_data, lipsync_data, duration)
		
			# Clear the current character/voice
			current_character = ""
			current_voice = ""
			return
		elif response_data.has("success") and not bool(response_data.get("success", true)):
			# Handle error response from Python service
			var error_msg = response_data.get("error", "Unknown error")
			var character2 = current_character if current_character else "unknown"
			print("VoiceClient: Synthesis failed: ", error_msg)
			synthesis_failed.emit(character2, error_msg)
		
			# Clear the current character/voice
			current_character = ""
			current_voice = ""
			return
	
	print("VoiceClient: Invalid synthesis response format")
	print("VoiceClient: Response keys: ", response_data.keys() if typeof(response_data) == TYPE_DICTIONARY else "non-dictionary")
	var character3 = current_character if current_character else "unknown"
	synthesis_failed.emit(character3, "Invalid synthesis response format")
	current_character = ""
	current_voice = ""

func _handle_error_response(response_code: int, body: PackedByteArray):
	"""Handle error responses from the service"""
	_pending_request_type = ""

	var error_message = "HTTP " + str(response_code)
	
	if body.size() > 0:
		var body_text = body.get_string_from_utf8()
		error_message += ": " + body_text
	
	print("VoiceClient: Request failed - ", error_message)
	
	if response_code == 0 or response_code >= 500:
		# Service might be down
		_update_service_status(false)
	
	# This handler is only used for the synthesis channel (health checks have
	# a dedicated HTTPRequest). Only emit failures when we have a character.
	if current_character.is_empty():
		current_voice = ""
		return
	var character = current_character
	current_character = ""
	current_voice = ""
	synthesis_failed.emit(character, error_message)

func _process_next_request():
	"""Process the next queued request if any.
	Defers to next frame so the HTTPRequest node is fully idle after its
	request_completed callback.  Calling request() from inside that callback
	can return ERR_BUSY in Godot 4."""
	if request_queue.is_empty():
		return
	call_deferred("_process_next_request_deferred")

func _process_next_request_deferred():
	"""Actually send the next queued request (runs one frame after _process_next_request)."""
	if request_queue.is_empty():
		return
	if is_processing_request:
		return  # Another request started in the meantime; will be picked up later.
	# IMPORTANT: Do not pop+send queued synthesis requests while the service is
	# unavailable. During hub restarts, requests should remain queued until a
	# health check confirms recovery; otherwise we "burn" queued requests into
	# long timeouts (HTTP 0) and make it look like TTS is broken until the user
	# manually clicks "Save & Apply Providers".
	if not is_service_available:
		# Best-effort: trigger a health check so availability can flip back to true,
		# at which point _update_service_status() will flush the queue.
		check_service_availability()
		return
	var next_request = request_queue.pop_front()
	var next_voice = next_request.get("voice", "")
	var next_mapping: Dictionary = next_request.get("character_mapping", {}) if typeof(next_request.get("character_mapping", {})) == TYPE_DICTIONARY else {}
	var next_voice_cfg: Dictionary = next_request.get("voice_config", {}) if typeof(next_request.get("voice_config", {})) == TYPE_DICTIONARY else {}
	var retried_cache := bool(next_request.get("retried_cache", false))
	_send_synthesis_request(next_request.text, next_request.character, next_voice, next_mapping, next_voice_cfg, retried_cache)

func _update_service_status(available: bool):
	"""Update service availability status"""
	if is_service_available != available:
		is_service_available = available
		service_status_changed.emit(available)
		print("VoiceClient: Service status changed - Available: ", available)
		# If service just recovered, flush any queued synthesis requests.
		if available and not is_processing_request and not request_queue.is_empty():
			_process_next_request()

func get_service_status() -> bool:
	"""Get current service availability status"""
	return is_service_available

func set_service_url(url: String):
	"""Update the service URL (useful for configuration)"""
	service_url = _normalize_loopback_url(url)
	check_service_availability()

func set_hub_url(url: String):
	hub_url = _normalize_loopback_url(url)
	check_service_availability()

func set_provider_mode(mode: String):
	provider_mode = mode
	check_service_availability()

func set_hub_tts_provider_preference(pref: String) -> void:
	var p := String(pref).strip_edges().to_lower()
	if p in ["", "auto", "edge", "edge_tts", "edgetts"]:
		hub_tts_provider_preference = "edge_tts" if p in ["edge", "edge_tts", "edgetts"] else "auto"
	elif p in ["sapi", "pyttsx3"]:
		hub_tts_provider_preference = "sapi"
	elif p in ["sidecar", "voice_sidecar"]:
		hub_tts_provider_preference = "sidecar"
	else:
		hub_tts_provider_preference = "auto"

func set_save_recordings_enabled(enabled: bool) -> void:
	save_recordings = bool(enabled)

func set_session_app_id(app_id: String) -> void:
	var a := String(app_id).strip_edges()
	if not a.is_empty():
		session_app_id = a

func cancel_current_request(clear_queue: bool = true) -> void:
	# v1: cancel in-flight HTTP request to hub/service (distinct from stopping playback).
	if http_request and http_request.has_method("cancel_request"):
		http_request.cancel_request()
	# Notify listeners that the current synthesis was cancelled (best-effort).
	if not current_character.is_empty():
		synthesis_failed.emit(current_character, "cancelled")
	is_processing_request = false
	_pending_request_type = ""
	current_character = ""
	current_voice = ""
	if clear_queue:
		request_queue.clear()
	# Continue with any queued work if not clearing.
	if not clear_queue:
		_process_next_request()

func clear_request_queue():
	"""Clear all pending synthesis requests"""
	request_queue.clear()
	print("VoiceClient: Request queue cleared") 

func transcribe_audio(audio_path: String) -> void:
	"""
	Reads a WAV audio file, encodes it, and sends it to the server for transcription.
	Emits the 'transcription_completed' signal with the resulting text.
	"""
	if not FileAccess.file_exists(audio_path):
		push_error("VoiceClient: Audio file not found for transcription at path: " + audio_path)
		transcription_completed.emit("", "Error: Audio file not found.")
		return

	var file = FileAccess.open(audio_path, FileAccess.READ)
	if not file:
		push_error("VoiceClient: Failed to open audio file at path: " + audio_path)
		transcription_completed.emit("", "Error: Could not open audio file.")
		return

	var audio_bytes = file.get_buffer(file.get_length())
	file.close()

	var audio_base64 = Marshalls.raw_to_base64(audio_bytes)

	var payload = {
		"audio_base64": audio_base64,
		"audio_format": "wav"
	}
	var body = JSON.stringify(payload)
	
	var http := HTTPRequest.new()
	add_child(http)
	# Wait a frame to ensure the HTTPRequest node is processed in the scene tree
	await get_tree().process_frame
	var url := ""
	if provider_mode == "hub":
		url = hub_url.rstrip("/") + "/voice/transcribe"
		payload["language"] = "en"
		payload["session_id"] = SynesynSession.get_or_create_session_id(session_app_id)
		payload["save_recordings"] = bool(save_recordings)
		body = JSON.stringify(payload)
	else:
		url = service_url.rstrip("/") + "/transcribe" # Use service_url for transcription.
	var headers := ["Content-Type: application/json"]
	
	print("VoiceClient: Sending transcription request to: ", url)
	var err = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("VoiceClient: Transcription HTTP request failed with error: " + str(err))
		transcription_completed.emit("", "Error: HTTP request failed.")
		http.queue_free()
		return
		
	var response = await http.request_completed
	var result = response[0]
	var response_code = response[1]
	var response_body_bytes = response[3]
	
	print("VoiceClient: Transcription response received. Result: ", result, ", Code: ", response_code)
	
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var response_body = response_body_bytes.get_string_from_utf8()
		var json = JSON.parse_string(response_body)
		if provider_mode == "hub":
			if json and json.get("ok"):
				var text = json.get("text", "")
				print("VoiceClient: Hub transcription OK. Text: '", text, "'")
				transcription_completed.emit(text, "")
			else:
				var error_msg = json.get("detail", "Unknown transcription error from hub.") if json else "Invalid JSON response from hub."
				push_error("VoiceClient: " + str(error_msg))
				transcription_completed.emit("", str(error_msg))
		else:
			if json and json.get("success"):
				var text = json.get("text", "")
				print("VoiceClient: Transcription successful. Text: '", text, "'")
				# DEBUG: Print all active connections to this signal
				print("VoiceClient: Emitting 'transcription_completed'. Connections: ", transcription_completed.get_connections())
				transcription_completed.emit(text, "")
			else:
				var error_msg = json.get("error", "Unknown transcription error from server.") if json else "Invalid JSON response from server."
				push_error("VoiceClient: " + error_msg)
				transcription_completed.emit("", error_msg)
	else:
		var response_body: String = (
			response_body_bytes.get_string_from_utf8()
		)
		var error_detail: String = ""
		var error_json_any: Variant = JSON.parse_string(response_body)
		if typeof(error_json_any) == TYPE_DICTIONARY:
			var error_json: Dictionary = error_json_any
			error_detail = str(
				error_json.get(
					"detail",
					error_json.get("error", "")
				)
			).strip_edges()
		var error_msg: String = (
			"Transcription request failed with code: "
			+ str(response_code)
			+ " and result: "
			+ str(result)
		)
		if not error_detail.is_empty():
			error_msg += ". " + error_detail
		push_error("VoiceClient: " + error_msg)
		transcription_completed.emit("", error_msg)
		
	http.queue_free() 

func _base_url() -> String:
	return hub_url if provider_mode == "hub" else service_url

func _file_uri_to_path(uri: String) -> String:
	# Hub returns file:// URIs. Convert to OS path.
	var s = uri.strip_edges()
	if s.begins_with("file:///"):
		s = s.substr(len("file:///"))
		# Windows: "C:/..." — leave as-is.
		# Linux:   "home/..." — restore the leading "/" that was part of the absolute path.
		if s.length() < 2 or s[1] != ":":
			s="/" + s
	elif s.begins_with("file://"):
		s = s.substr(len("file://"))
	return s

func _read_file_bytes(path: String) -> PackedByteArray:
	if path.is_empty() or not FileAccess.file_exists(path):
		return PackedByteArray()
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return PackedByteArray()
	var data = f.get_buffer(f.get_length())
	f.close()
	return data

func _read_json_array(path: String) -> Array:
	if path.is_empty() or not FileAccess.file_exists(path):
		return []
	var txt = FileAccess.get_file_as_string(path)
	var v = JSON.parse_string(txt)
	if typeof(v) == TYPE_ARRAY:
		return v
	return []

func _looks_like_wav_bytes(data: PackedByteArray) -> bool:
	# RIFF/WAVE magic
	if data.size() < 12:
		return false
	return data[0] == 0x52 and data[1] == 0x49 and data[2] == 0x46 and data[3] == 0x46 \
		and data[8] == 0x57 and data[9] == 0x41 and data[10] == 0x56 and data[11] == 0x45
