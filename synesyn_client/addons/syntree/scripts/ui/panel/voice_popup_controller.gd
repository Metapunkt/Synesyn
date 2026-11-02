## Purpose: Minimal SynTree Voice UI (STT mic toggle + assistant-only TTS) without duplicating ScenSyn hamburger
@tool
extends PopupPanel

const MicrophoneRecorder = preload("res://addons/syntree_voice/scripts/services/microphone_recorder.gd")
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")
const ProviderModePolicy = preload("res://addons/synesyn_core/scripts/provider_mode_policy.gd")
const SynesynSessionScript = preload("res://addons/synesyn_core/scripts/synesyn_session.gd")

@onready var mic_toggle: CheckButton = %MicToggle
@onready var auto_send_toggle: CheckButton = %AutoSendToggle
@onready var speak_toggle: CheckButton = %SpeakToggle
@onready var pause_button: Button = %PauseButton
@onready var resume_button: Button = %ResumeButton
@onready var stop_button: Button = %StopButton
@onready var status_label: Label = %StatusLabel

var _tts_player: AudioStreamPlayer = null
var _recorder: Node = null
var _use_hub_direct: bool = false
var _hub_base_url: String = "http://127.0.0.1:17777"
var _hub_save_recordings: bool = false
var _hub_http_inflight: HTTPRequest = null
var _message_input: TextEdit = null
var _send_button: Button = null
var _message_container: Node = null

var _awaiting_assistant_reply: bool = false

const _SPEAK_CHARACTER := "SyntreeAssistant"
const _SESSION_APP_ID := "syntree"

func _ready() -> void:
	_tts_player = AudioStreamPlayer.new()
	add_child(_tts_player)

	_load_prefs()

	if is_instance_valid(mic_toggle):
		mic_toggle.toggled.connect(_on_mic_toggled)
	if is_instance_valid(auto_send_toggle):
		auto_send_toggle.toggled.connect(_persist_prefs)
	if is_instance_valid(speak_toggle):
		speak_toggle.toggled.connect(_persist_prefs)

	if is_instance_valid(pause_button):
		pause_button.pressed.connect(_on_pause_pressed)
	if is_instance_valid(resume_button):
		resume_button.pressed.connect(_on_resume_pressed)
	if is_instance_valid(stop_button):
		stop_button.pressed.connect(_on_stop_pressed)

func on_voice_button_pressed() -> void:
	popup_centered()

func setup(message_input: TextEdit, send_button: Button, message_container: Node) -> void:
	# Deterministic wiring: panel passes us explicit references (same pattern as SendButton wrapper).
	_message_input = message_input
	_send_button = send_button
	_message_container = message_container

	_configure_hub_fallback_from_runtime_config()

	if is_instance_valid(_send_button) and not _send_button.pressed.is_connected(_on_send_pressed_capture):
		_send_button.pressed.connect(_on_send_pressed_capture)

	if is_instance_valid(_message_container) and _message_container.has_signal("assistant_message_added"):
		if not _message_container.assistant_message_added.is_connected(_on_assistant_message_added):
			_message_container.assistant_message_added.connect(_on_assistant_message_added)

	if not is_instance_valid(_message_input) or not is_instance_valid(_send_button) or not is_instance_valid(_message_container) or not _use_hub_direct:
		var missing: Array[String] = []
		if not is_instance_valid(_message_input):
			missing.append("MessageInput")
		if not is_instance_valid(_send_button):
			missing.append("SendButton")
		if not is_instance_valid(_message_container):
			missing.append("MessageContainer")
		if not _use_hub_direct:
			missing.append("HubConfig(voice.provider_mode=hub + hub url)")
		_set_status("Voice: setup failed (missing: %s)" % ", ".join(missing))
		return

	_set_status("")

func _configure_hub_fallback_from_runtime_config() -> void:
	var cfg: Dictionary = RuntimeConfigScript.load_config()
	var mode := String(ProviderModePolicy.get_voice_provider_mode(cfg)).strip_edges()
	_hub_base_url = String(ProviderModePolicy.get_voice_hub_url(cfg)).strip_edges()
	_hub_save_recordings = bool(ProviderModePolicy.get_voice_save_recordings(cfg))
	_use_hub_direct = (mode == "hub") and not _hub_base_url.is_empty()

func _hub_cancel_inflight() -> void:
	if is_instance_valid(_hub_http_inflight):
		_hub_http_inflight.cancel_request()
		_hub_http_inflight.queue_free()
		_hub_http_inflight = null

func _hub_post_json(path: String, payload: Dictionary) -> Dictionary:
	_hub_cancel_inflight()
	var http := HTTPRequest.new()
	_hub_http_inflight = http
	add_child(http)
	http.timeout = 30.0
	var url := _hub_base_url.rstrip("/") + path
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify(payload)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		_hub_http_inflight = null
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err)}
	var completed = await http.request_completed
	http.queue_free()
	if _hub_http_inflight == http:
		_hub_http_inflight = null
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var resp_body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "HTTP request failed: %s" % result_code}
	var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": {"status": response_code, "body": parsed}}
	return {"ok": true, "data": parsed}

func _file_uri_to_path(uri: String) -> String:
	var s := String(uri).strip_edges()
	if s.begins_with("file:///"):
		s = s.substr(len("file:///"))
	elif s.begins_with("file://"):
		s = s.substr(len("file://"))
	# /C:/... -> C:/...
	if s.length() > 2 and s[0] == "/" and s[2] == ":":
		s = s.substr(1)
	return s

func _read_file_bytes(path: String) -> PackedByteArray:
	var p := String(path).strip_edges()
	if p.is_empty() or not FileAccess.file_exists(p):
		return PackedByteArray()
	var f := FileAccess.open(p, FileAccess.READ)
	if not f:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b

func _hub_speak(text: String, voice_name: String) -> void:
	var payload: Dictionary = {
		"text": text,
		"character": _SPEAK_CHARACTER,
		"return_lipsync": false,
		"session_id": SynesynSessionScript.get_or_create_session_id(_SESSION_APP_ID),
	}
	if not voice_name.is_empty():
		payload["voice"] = {"name": voice_name}
	var res: Dictionary = await _hub_post_json("/voice/speak", payload)
	if not bool(res.get("ok", false)):
		_set_status("Voice: TTS failed: %s" % str(res.get("error", "unknown error")))
		return
	var data: Variant = res.get("data", null)
	if typeof(data) != TYPE_DICTIONARY:
		_set_status("Voice: TTS invalid response.")
		return
	var d: Dictionary = data
	if not bool(d.get("ok", false)):
		_set_status("Voice: TTS error.")
		return
	var audio_url := String(d.get("audio_url", "")).strip_edges()
	var audio_path := _file_uri_to_path(audio_url)
	var audio_bytes := _read_file_bytes(audio_path)
	if audio_bytes.is_empty():
		_set_status("Voice: TTS audio missing.")
		return
	_on_synthesis_completed(_SPEAK_CHARACTER, audio_bytes, [], float(d.get("duration_sec", 0.0)))

func _hub_transcribe(audio_path: String) -> void:
	var audio_bytes := _read_file_bytes(audio_path)
	if audio_bytes.is_empty():
		_set_status("Voice: STT audio missing.")
		return
	var payload: Dictionary = {
		"audio_base64": Marshalls.raw_to_base64(audio_bytes),
		"audio_format": "wav",
		"language": "en",
		"session_id": SynesynSessionScript.get_or_create_session_id(_SESSION_APP_ID),
		"save_recordings": bool(_hub_save_recordings),
	}
	var res: Dictionary = await _hub_post_json("/voice/transcribe", payload)
	if not bool(res.get("ok", false)):
		_set_status("Voice: STT failed: %s" % str(res.get("error", "unknown error")))
		return
	var data: Variant = res.get("data", null)
	if typeof(data) != TYPE_DICTIONARY:
		_set_status("Voice: STT invalid response.")
		return
	var d: Dictionary = data
	if not bool(d.get("ok", false)):
		_set_status("Voice: STT error.")
		return
	_on_transcription_completed(String(d.get("text", "")), "")

func _ensure_recorder() -> void:
	if is_instance_valid(_recorder):
		return
	_recorder = MicrophoneRecorder.new()
	add_child(_recorder)

func _on_send_pressed_capture() -> void:
	# Gate auto-speak so history loads don't trigger speech.
	if speak_toggle and speak_toggle.button_pressed:
		_awaiting_assistant_reply = true

func _on_assistant_message_added(content: String) -> void:
	if not (speak_toggle and speak_toggle.button_pressed):
		return
	if not _awaiting_assistant_reply:
		return
	_awaiting_assistant_reply = false

	var text := _strip_fenced_code_blocks(String(content))
	text = text.strip_edges()
	if text.is_empty():
		return
	_request_tts(text)

func _request_tts(text: String) -> void:
	if not _use_hub_direct:
		_set_status("Voice: Voice unavailable.")
		return

	# Stop any current playback + cancel in-flight request.
	_on_stop_pressed()

	var voice_name := ""
	_set_status("Speaking…")
	await _hub_speak(text, voice_name)

func _on_synthesis_completed(character: String, audio_data: PackedByteArray, _lipsync_data: Array, _duration: float) -> void:
	if String(character) != _SPEAK_CHARACTER:
		return
	if audio_data.is_empty():
		_set_status("Voice: empty audio payload.")
		return

	var stream := AudioStreamWAV.new()
	stream.data = audio_data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	_tts_player.stream = stream
	_tts_player.play()
	_set_status("")

func _on_pause_pressed() -> void:
	if _tts_player:
		_tts_player.set_stream_paused(true)

func _on_resume_pressed() -> void:
	if _tts_player:
		_tts_player.set_stream_paused(false)

func _on_stop_pressed() -> void:
	if _tts_player and _tts_player.playing:
		_tts_player.stop()
	_hub_cancel_inflight()

func _on_mic_toggled(enabled: bool) -> void:
	_ensure_recorder()
	if not is_instance_valid(_recorder):
		_set_status("Voice: Recorder unavailable.")
		return

	if enabled:
		if _recorder.has_method("start_recording"):
			_set_status("Recording…")
			_recorder.start_recording()
	else:
		if _recorder.has_method("stop_recording"):
			_set_status("Transcribing…")
			var audio_path: String = await _recorder.stop_recording()
			if audio_path.is_empty():
				_set_status("Voice: recording failed/empty.")
				return
			if not _use_hub_direct:
				_set_status("Voice: STT unavailable (hub mode required).")
				return
			await _hub_transcribe(audio_path)

func _on_transcription_completed(text: String, error: String) -> void:
	if not String(error).strip_edges().is_empty():
		_set_status("Voice: " + String(error))
		return
	var t := String(text).strip_edges()
	if t.is_empty():
		_set_status("Voice: empty transcript.")
		return

	if is_instance_valid(_message_input):
		_message_input.text = t
	if is_instance_valid(_send_button):
		_send_button.disabled = false

	_set_status("")

	if auto_send_toggle and auto_send_toggle.button_pressed and is_instance_valid(_send_button):
		# Ensure TTS gating works for voice-send too.
		if speak_toggle and speak_toggle.button_pressed:
			_awaiting_assistant_reply = true
		_send_button.emit_signal("pressed")

func _strip_fenced_code_blocks(s: String) -> String:
	# Remove markdown ``` fenced code blocks (TTS ignores code).
	var out := ""
	var in_fence := false
	var lines := s.split("\n", false)
	for line in lines:
		var l := String(line)
		var trimmed := l.strip_edges()
		if trimmed.begins_with("```"):
			in_fence = not in_fence
			continue
		if in_fence:
			continue
		out += l + "\n"
	return out.strip_edges()

func _load_prefs() -> void:
	var cfg: Dictionary = RuntimeConfigScript.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	if typeof(apps_any) != TYPE_DICTIONARY:
		return
	var apps: Dictionary = apps_any
	var syntree_any: Variant = apps.get("syntree", {})
	var syntree_cfg: Dictionary = syntree_any if typeof(syntree_any) == TYPE_DICTIONARY else {}
	if is_instance_valid(auto_send_toggle):
		auto_send_toggle.button_pressed = bool(syntree_cfg.get("voice_auto_send", false))
	if is_instance_valid(speak_toggle):
		speak_toggle.button_pressed = bool(syntree_cfg.get("voice_tts_autospeak", false))

func _persist_prefs(_v: Variant = null) -> void:
	var cfg: Dictionary = RuntimeConfigScript.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var syntree_any: Variant = apps.get("syntree", {})
	var syntree_cfg: Dictionary = syntree_any if typeof(syntree_any) == TYPE_DICTIONARY else {}
	syntree_cfg["voice_auto_send"] = bool(auto_send_toggle.button_pressed) if auto_send_toggle else false
	syntree_cfg["voice_tts_autospeak"] = bool(speak_toggle.button_pressed) if speak_toggle else false
	apps["syntree"] = syntree_cfg
	cfg["apps"] = apps
	RuntimeConfigScript.save_config(cfg)

func _set_status(msg: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = msg


