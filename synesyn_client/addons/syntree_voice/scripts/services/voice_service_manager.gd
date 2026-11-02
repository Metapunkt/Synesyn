extends Node

# VoiceServiceManager - Central coordinator for the voice synthesis system
# This is registered as an autoload and provides the main API for voice synthesis

const SynesynAutoloadAccessScript = preload("res://addons/synesyn_core/scripts/synesyn_autoload_access.gd")

signal voice_synthesis_completed(character: String, audio_data: PackedByteArray, lipsync_data: Array, duration: float)
signal voice_service_ready()
signal voice_service_error(error: String)
signal transcription_completed(text: String, error: String)

# New: Global playback signals so other systems (e.g., Story Stage) can sync visuals
signal tts_playback_started(character: String)
signal tts_playback_finished(character: String)
signal tts_playback_paused(character: String)
signal tts_playback_resumed(character: String)

var voice_client: Node
var is_enabled: bool = false
var is_service_running: bool = false

# Global audio players that survive scene changes
var global_audio_players: Dictionary = {}  # character_name -> AudioStreamPlayer

# Global TTS preferences that persist across scenes
var skip_welcome_speech: bool = false  # Toggle to skip Narrator welcome message

# Configuration
var voice_service_url: String = "http://127.0.0.1:8000"
var hub_voice_url: String = "http://127.0.0.1:17777"
var provider_mode: String = "direct" # "direct" | "hub"
var hub_tts_provider_preference: String = "auto" # "auto" | "edge_tts" | "sapi" | "sidecar"
var character_voice_mapping: Dictionary = {}
var _character_voices_version: int = 1
var _character_voices_updated_at: Variant = null
var save_recordings: bool = false # Consent-controlled; default false

var _hub_client: Node = null
var _health_poll_timer: Timer = null

# Best-effort local hub autostart when ScenSyn is run directly (no Launcher scene).
var _hub_pid_started_here: int = -1
var _hub_autostart_http: HTTPRequest = null
var _last_hub_autostart_attempt_ms: int = -999999
const _HUB_AUTOSTART_MIN_INTERVAL_MS := 15000

func _ready():
	# Set up project setting if it doesn't exist
	if not ProjectSettings.has_setting("syntree_voice/enabled"):
		ProjectSettings.set_setting("syntree_voice/enabled", true)
		ProjectSettings.save()
		print("VoiceService: Created project setting syntree_voice/enabled = true")

	# Provider selection (keep default direct for compatibility)
	if not ProjectSettings.has_setting("syntree_voice/provider_mode"):
		ProjectSettings.set_setting("syntree_voice/provider_mode", "direct")
		ProjectSettings.save()
	if not ProjectSettings.has_setting("syntree_voice/hub_url"):
		ProjectSettings.set_setting("syntree_voice/hub_url", "http://127.0.0.1:17777")
		ProjectSettings.save()
	
	# Only initialize if enabled in project settings
	is_enabled = ProjectSettings.get_setting("syntree_voice/enabled", true)  # Default to true
	if not is_enabled:
		print("VoiceService: Disabled in project settings")
		return
	
	print("VoiceService: Initializing voice synthesis system...")
	# Provider config is centralized via RuntimeConfig + ProviderModePolicy (prevents per-app drift).
	# Note: RuntimeConfig.default_config() already pulls ProjectSettings values as the base layer.
	var ProviderModePolicy = preload("res://addons/synesyn_core/scripts/provider_mode_policy.gd")
	var cfg: Dictionary = RuntimeConfig.load_config()

	provider_mode = String(ProviderModePolicy.get_voice_provider_mode(cfg))
	hub_voice_url = String(ProviderModePolicy.get_voice_hub_url(cfg))
	voice_service_url = String(ProviderModePolicy.get_voice_service_url(cfg))
	hub_tts_provider_preference = String(ProviderModePolicy.get_voice_hub_tts_provider_preference(cfg))
	save_recordings = bool(ProviderModePolicy.get_voice_save_recordings(cfg))

	# If ScenSyn is launched directly (bypassing `synesyn_launcher.tscn`), the hub
	# autostart orchestration won't run. In hub voice mode, that can lead to
	# repeated "HTTP 0" until the user manually starts/restarts the hub.
	# This is a best-effort local autostart that only runs for localhost URLs.
	call_deferred("_autostart_local_hub_if_configured")

	_setup_voice_client()
	_load_character_voice_mapping()
	
	# Check service health immediately
	await get_tree().process_frame
	check_service_health()
	print("VoiceService: Health check initiated")
	_setup_health_poll_timer()

func _disable_proxy_for_local(http: HTTPRequest, url: String) -> void:
	# Mirror HubProcessManager's behavior: on some Windows setups system proxies
	# can interfere even with localhost calls.
	if not is_instance_valid(http):
		return
	var u := String(url).strip_edges().to_lower()
	var is_local := (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1) or (u.find("[::1]") != -1)
	if not is_local:
		return
	http.set_http_proxy("", -1)
	http.set_https_proxy("", -1)

func _autostart_local_hub_if_configured() -> void:
	# Only autostart for hub mode.
	if provider_mode != "hub":
		return

	var cfg: Dictionary = RuntimeConfig.load_config()
	var hub_cfg_any: Variant = cfg.get("hub", {})
	var hub_cfg: Dictionary = hub_cfg_any as Dictionary if typeof(hub_cfg_any) == TYPE_DICTIONARY else {}
	if not bool(hub_cfg.get("autostart", true)):
		return

	var base_url := String(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()
	if base_url.is_empty():
		return
	# Only start a local hub process for localhost configs.
	var lower := base_url.to_lower()
	var is_local := lower.begins_with("http://127.0.0.1") or lower.begins_with("https://127.0.0.1") \
		or lower.begins_with("http://localhost") or lower.begins_with("https://localhost") \
		or lower.begins_with("http://[::1]") or lower.begins_with("https://[::1]")
	if not is_local:
		return

	# Throttle autostart attempts so periodic health failures don't spam process creation.
	var now_ms := int(Time.get_ticks_msec())
	if now_ms - _last_hub_autostart_attempt_ms < _HUB_AUTOSTART_MIN_INTERVAL_MS:
		return
	_last_hub_autostart_attempt_ms = now_ms

	# If hub is already reachable, do nothing (avoid spawning duplicates).
	# Use a short grace window so if another system (e.g. Synesyn Launcher) is
	# already starting the hub, we don't race and attempt to spawn a second copy.
	# This keeps startup deterministic even if ScenSyn boots quickly.
	for i in range(20): # ~5s total
		var reachable := await _ping_hub_health_ok_async(base_url)
		if reachable:
			return
		await get_tree().create_timer(0.25).timeout

	var exec_path := HubLocator.find_hub_exe(cfg)
	if exec_path.is_empty():
		print("VoiceService: Hub autostart skipped (hub not found). Expected %s" % HubLocator.describe_expected_location())
		return

	_hub_pid_started_here = OS.create_process(exec_path, [], false)
	if _hub_pid_started_here > 0:
		print("VoiceService: Autostarted local hub (pid=%s): %s" % [str(_hub_pid_started_here), exec_path])
		# Register PID for deterministic stop_on_exit (autoload survives scene changes).
		var bootstrapper := SynesynAutoloadAccessScript.workspace_bootstrapper()
		if is_instance_valid(bootstrapper) and bootstrapper.has_method("register_hub_process"):
			bootstrapper.register_hub_process(_hub_pid_started_here, exec_path)
	else:
		print("VoiceService: Hub autostart failed (create_process returned %s): %s" % [str(_hub_pid_started_here), exec_path])
		_hub_pid_started_here = -1

func _ping_hub_health_ok_async(base_url: String) -> bool:
	if not is_inside_tree():
		return false
	if not _hub_autostart_http or not is_instance_valid(_hub_autostart_http):
		_hub_autostart_http = HTTPRequest.new()
		add_child(_hub_autostart_http)
	_hub_autostart_http.timeout = 1.5
	_disable_proxy_for_local(_hub_autostart_http, base_url)

	var url := base_url.rstrip("/") + "/health"
	var err := _hub_autostart_http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		return false

	var completed = await _hub_autostart_http.request_completed
	var result_code: int = completed[0]
	var response_code: int = completed[1]
	var body: PackedByteArray = completed[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return false
	if response_code != 200:
		return false
	# Accept either JSON {ok:true,...} or any non-empty 200 response as "reachable".
	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return bool((parsed as Dictionary).get("ok", false))
	return true

func _exit_tree() -> void:
	# Best-effort cleanup: only stop the hub if runtime config says so AND we
	# started it from this process.
	var cfg: Dictionary = RuntimeConfig.load_config()
	var hub_cfg_any: Variant = cfg.get("hub", {})
	var hub_cfg: Dictionary = hub_cfg_any as Dictionary if typeof(hub_cfg_any) == TYPE_DICTIONARY else {}
	if not bool(hub_cfg.get("stop_on_exit", true)):
		return
	if _hub_pid_started_here > 0 and OS.has_method("is_process_running") and OS.is_process_running(_hub_pid_started_here):
		OS.kill(_hub_pid_started_here)
		_hub_pid_started_here = -1

func apply_runtime_config(provider_mode_in: String, hub_url_in: String, service_url_in: String, hub_tts_pref_in: String = "") -> void:
	# Runtime override (preferred for exports): values come from Documents/Synesyn config
	# This does NOT persist back to ProjectSettings.
	provider_mode = provider_mode_in if not provider_mode_in.is_empty() else provider_mode
	hub_voice_url = hub_url_in if not hub_url_in.is_empty() else hub_voice_url
	voice_service_url = service_url_in if not service_url_in.is_empty() else voice_service_url
	if not hub_tts_pref_in.is_empty():
		hub_tts_provider_preference = hub_tts_pref_in.strip_edges().to_lower()

	if voice_client:
		voice_client.set_service_url(voice_service_url)
		voice_client.set_hub_url(hub_voice_url)
		voice_client.set_provider_mode(provider_mode)
		if voice_client.has_method("set_hub_tts_provider_preference"):
			voice_client.set_hub_tts_provider_preference(hub_tts_provider_preference)
		if voice_client.has_method("set_save_recordings_enabled"):
			voice_client.set_save_recordings_enabled(save_recordings)

	# Re-check health after config changes.
	check_service_health()

func set_save_recordings_enabled(enabled: bool) -> void:
	save_recordings = bool(enabled)
	if voice_client and voice_client.has_method("set_save_recordings_enabled"):
		voice_client.set_save_recordings_enabled(save_recordings)

func _setup_voice_client():
	"""Initialize the voice client for HTTP communication"""
	voice_client = preload("res://addons/syntree_voice/scripts/services/voice_client.gd").new()
	add_child(voice_client)
	
	# Connect voice client signals
	voice_client.synthesis_completed.connect(_on_synthesis_completed)
	voice_client.synthesis_failed.connect(_on_synthesis_failed)
	voice_client.service_status_changed.connect(_on_service_status_changed)
	voice_client.transcription_completed.connect(_on_transcription_completed)
	
	# Configure service URL
	voice_client.set_service_url(voice_service_url)
	voice_client.set_hub_url(hub_voice_url)
	voice_client.set_provider_mode(provider_mode)
	if voice_client.has_method("set_hub_tts_provider_preference"):
		voice_client.set_hub_tts_provider_preference(hub_tts_provider_preference)
	
	print("VoiceService: Voice client initialized")

func _setup_health_poll_timer() -> void:
	# Continuous health refresh prevents stale "unavailable" state after hub autostart/workspace selection.
	if _health_poll_timer and is_instance_valid(_health_poll_timer):
		return
	_health_poll_timer = Timer.new()
	_health_poll_timer.wait_time = 2.0
	_health_poll_timer.one_shot = false
	_health_poll_timer.timeout.connect(func() -> void:
		if not is_enabled:
			return
		check_service_health()
	)
	add_child(_health_poll_timer)
	_health_poll_timer.start()

func _scensyn_output_bus() -> String:
	var bus_name := "ScenSyn"
	if AudioServer.get_bus_index(bus_name) < 0:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return bus_name

func get_or_create_audio_player(character_name: String) -> AudioStreamPlayer:
	"""Get or create a global AudioStreamPlayer for a character
	These players are children of VoiceService (autoload) so they survive scene changes"""
	if global_audio_players.has(character_name):
		return global_audio_players[character_name]
	
	# Create new global audio player
	var player = AudioStreamPlayer.new()
	player.name = "AudioPlayer_" + character_name
	player.bus = _scensyn_output_bus()
	add_child(player)
	global_audio_players[character_name] = player
	return player

func _load_character_voice_mapping():
	"""Load character-to-voice mappings from configuration"""
	# Default character voice mappings for SynTree characters (minimal seed)
	character_voice_mapping = {
		"Narrator": "en-US-AriaNeural"
	}
	
	# v1: Standard location (local-first) for character voices.
	# Accept either:
	# - {"character_voices": {...}, "version": N, ...}
	# - { "Narrator": "...", ... } (legacy/flat)
	var file_any: Variant = _load_character_voices_file()
	if typeof(file_any) == TYPE_DICTIONARY:
		var obj: Dictionary = file_any
		_character_voices_version = int(obj.get("version", 1))
		_character_voices_updated_at = obj.get("updated_at", null)
		var mapping_any: Variant = obj.get("character_voices", null)
		if typeof(mapping_any) == TYPE_DICTIONARY:
			character_voice_mapping.merge(mapping_any, true)
		else:
			# Flat mapping
			character_voice_mapping.merge(obj, true)

	# Try to load custom mappings from project settings (legacy support)
	var custom_mapping = ProjectSettings.get_setting("syntree_voice/character_voices", {})
	if not custom_mapping.is_empty():
		character_voice_mapping.merge(custom_mapping, true)

	# If no file exists yet, create it from the merged mapping (versioned local artifact).
	_ensure_character_voices_file_exists()
	
	print("VoiceService: Loaded character voice mappings: ", character_voice_mapping)

func _character_voices_path() -> String:
	var dest: String = RuntimeConfig.get_character_voices_path()
	RuntimeConfig.migrate_file_if_needed(
		dest,
		["user://syntree_voice/character_voices.json"]
	)
	return dest

func _ensure_character_voices_file_exists() -> void:
	var voices_path: String = _character_voices_path()
	if FileAccess.file_exists(voices_path):
		return
	var dir_path := voices_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var obj := {
		"version": 1,
		"updated_at": Time.get_unix_time_from_system(),
		"character_voices": character_voice_mapping.duplicate(),
	}
	_save_character_voices_file(obj)

func _load_character_voices_file() -> Variant:
	var voices_path: String = _character_voices_path()
	if not FileAccess.file_exists(voices_path):
		return null
	var f := FileAccess.open(voices_path, FileAccess.READ)
	if not f:
		return null
	var raw := f.get_as_text()
	f.close()
	if raw.strip_edges().is_empty():
		return null
	return JSON.parse_string(raw)

func _save_character_voices_file(obj: Dictionary) -> void:
	var voices_path: String = _character_voices_path()
	DirAccess.make_dir_recursive_absolute(voices_path.get_base_dir())
	var f := FileAccess.open(voices_path, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(obj, "\t"))
	f.close()

func save_character_voices_to_file() -> void:
	# Optional v1 API: explicitly persist current mapping (does NOT auto-save on scenario overrides).
	var existing_any: Variant = _load_character_voices_file()
	var version := 1
	if typeof(existing_any) == TYPE_DICTIONARY:
		version = int((existing_any as Dictionary).get("version", 1)) + 1
	var obj := {
		"version": version,
		"updated_at": Time.get_unix_time_from_system(),
		"character_voices": character_voice_mapping.duplicate(),
	}
	_save_character_voices_file(obj)

func _get_hub_client() -> Node:
	if _hub_client and is_instance_valid(_hub_client):
		return _hub_client
	var HubSubstrateClient = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
	_hub_client = HubSubstrateClient.new()
	add_child(_hub_client)
	if _hub_client.has_method("configure_from_runtime_config"):
		_hub_client.configure_from_runtime_config()
	return _hub_client

func publish_character_voices_to_substrate(app_id: String = "scensyn") -> Dictionary:
	# "Later" item: persist voice mapping into substrate for auditability.
	# Explicit action only (no auto-publish) to avoid bloat.
	if provider_mode.strip_edges().to_lower() != "hub":
		return {"ok": false, "error": "publish requires provider_mode=hub"}

	var existing_any: Variant = _load_character_voices_file()
	if typeof(existing_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "character_voices.json not found or invalid; save first"}
	var obj: Dictionary = existing_any
	if not obj.has("character_voices"):
		obj = {"version": 1, "updated_at": Time.get_unix_time_from_system(), "character_voices": character_voice_mapping.duplicate()}

	var session_id := SynesynSession.get_or_create_session_id(app_id)

	var hub = _get_hub_client()
	var meta := {
		"provenance": {
			"generated_by": "voice.character_voices",
			"session_id": session_id,
			"source": _character_voices_path(),
		},
		"version": int(obj.get("version", 1)),
		"updated_at": obj.get("updated_at", null),
	}

	if hub and hub.has_method("create_artifact_inline_json"):
		var res: Dictionary = await hub.create_artifact_inline_json("json.character_voices", obj, meta)
		return res
	return {"ok": false, "error": "HubSubstrateClient unavailable"}

func request_character_speech(text: String, character: String = "Narrator", voice_override: Dictionary = {}) -> bool:
	"""Main API function - request speech synthesis for a character"""
	if not is_enabled:
		print("VoiceService: Voice synthesis disabled")
		return false
	
	if not voice_client:
		print("VoiceService: Voice client not initialized")
		return false
	# The line carries the scenario voice it was resolved with. Writing it
	# here means the hub request cannot fall back to the default voice just
	# because the shared mapping was still empty when this character first spoke.
	if typeof(voice_override) == TYPE_DICTIONARY and str(voice_override.get("voice", "")).strip_edges() != "":
		set_character_voice_config(character, voice_override)
	# Optional project-level aliasing only
	var send_character := _get_server_character_name(character)
	print("VoiceService: Requesting speech for '", character, "'", (" (alias->" + send_character + ")" if send_character != character else ""), ": ", text.substr(0, 50), "...")
	var voice_cfg := _get_character_voice_config(character)
	var voice := String(voice_cfg.get("voice", ""))
	# Intent: pass a compact "character_mapping" object through to the hub so TTS artifact provenance can record:
	# - which mapping source/version was consulted (character_voices.json),
	# - which character was requested (and any alias applied),
	# - which voice id was selected.
	var mapping_used := {
		"source": _character_voices_path(),
		"version": _character_voices_version,
		"updated_at": _character_voices_updated_at,
		"character": character,
		"server_character": send_character,
		"voice": voice,
		"voice_config": voice_cfg,
		"hub_tts_provider_preference": hub_tts_provider_preference,
	}
	return voice_client.synthesize_speech(text, send_character, voice, mapping_used, voice_cfg)

func get_service_status() -> bool:
	"""Check if the voice service is available"""
	if not voice_client:
		return false
	return voice_client.get_service_status()

func check_service_health():
	"""Trigger a health check of the voice service"""
	if voice_client:
		voice_client.check_service_availability()

func enable_voice_service(enabled: bool):
	"""Enable or disable the voice service"""
	is_enabled = enabled
	if not enabled and voice_client:
		voice_client.clear_request_queue()
	print("VoiceService: Voice service ", "enabled" if enabled else "disabled")

func set_character_voice(character: String, voice: String):
	"""Update the voice mapping for a character"""
	character_voice_mapping[character] = voice
	print("VoiceService: Set voice for ", character, " to ", voice)

func set_character_voice_config(character: String, config: Dictionary) -> void:
	"""Update the full voice config for a character (voice + optional rate/volume/pitch)."""
	if typeof(config) != TYPE_DICTIONARY or config.is_empty():
		return
	character_voice_mapping[character] = config.duplicate(true)
	print("VoiceService: Set voice config for ", character, " to ", config)

func clear_all_synthesis():
	"""Clear any ongoing voice synthesis requests"""
	if voice_client:
		voice_client.clear_request_queue()
	print("VoiceService: Cleared all voice synthesis requests")

func cancel_current_request(clear_queue: bool = true) -> void:
	# v1: cancel in-flight HTTP request (hub/service). This complements stop-all-speech playback controls.
	if voice_client and voice_client.has_method("cancel_current_request"):
		voice_client.cancel_current_request(clear_queue)

func stop_all_audio():
	"""Stop all currently playing audio"""
	# This will be handled by individual avatars
	print("VoiceService: Requested stop of all audio playback")

# Signal handlers for voice client events

func _on_synthesis_completed(character: String, audio_data: PackedByteArray, lipsync_data: Array, duration: float):
	"""Handle successful voice synthesis completion"""
	print("VoiceService: Speech synthesis completed for ", character)
	voice_synthesis_completed.emit(character, audio_data, lipsync_data, duration)

func _on_synthesis_failed(character: String, error: String):
	"""Handle voice synthesis failure"""
	print("VoiceService: Speech synthesis failed for ", character, " - ", error)
	voice_service_error.emit("Synthesis failed for " + character + ": " + error)

func _on_service_status_changed(is_available: bool):
	"""Handle voice service availability changes"""
	var was_running := is_service_running
	is_service_running = is_available
	if is_available:
		print("VoiceService: External voice service is available (was_running=%s)" % str(was_running))
		voice_service_ready.emit()
		# When recovering from a down state (or first-time availability after
		# launch), schedule a full config re-apply.  This replicates exactly
		# what the "Save & Apply Providers" button does and ensures the
		# VoiceClient's provider_mode, URLs, and TTS preference are correct.
		#
		# We use a short timer (0.5 s) instead of plain call_deferred so the
		# HTTPRequest node is fully idle and the hub has had a moment to
		# finish its own startup (health passes before voice providers are
		# completely ready on some builds).
		if not was_running:
			_schedule_recovery_reapply()
	else:
		print("VoiceService: External voice service is unavailable")
		voice_service_error.emit("Voice service unavailable")
		# If we're in hub mode and the hub is local/autostart-enabled, try to bring it back.
		# This makes hub restarts/crashes self-heal without requiring "Save & Apply".
		call_deferred("_autostart_local_hub_if_configured")

func _schedule_recovery_reapply() -> void:
	"""Schedule apply_runtime_config 0.5 s after service recovery."""
	if not is_inside_tree():
		return
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(_deferred_reapply_client_config, CONNECT_ONE_SHOT)

func _deferred_reapply_client_config() -> void:
	"""Re-apply full config to VoiceClient after service recovery.
	Calls the exact same apply_runtime_config() path that 'Save & Apply' uses."""
	if not voice_client:
		return
	print("VoiceService: Service recovered — re-applying full config")
	# Use the same entry-point that "Save & Apply Providers" uses so the
	# behaviour is identical: re-set manager vars, push to VoiceClient
	# via setters, then fire an explicit health check at the end.
	apply_runtime_config(provider_mode, hub_voice_url, voice_service_url, hub_tts_provider_preference)

func _on_transcription_completed(text: String, error: String):
	print("VoiceService: Transcription completed. Error: ", error)
	transcription_completed.emit(text, error)

# Utility functions

func get_character_voices() -> Dictionary:
	"""Get the current character voice mappings"""
	return character_voice_mapping.duplicate()

func is_voice_available() -> bool:
	"""Check if voice synthesis is available and enabled"""
	return is_enabled and is_service_running

func set_skip_welcome_speech(skip: bool) -> void:
	"""Set whether to skip welcome speech TTS (persists across scenes)"""
	skip_welcome_speech = skip
	print("VoiceService: Skip welcome speech set to ", skip)

func get_skip_welcome_speech() -> bool:
	"""Get current skip welcome speech setting"""
	return skip_welcome_speech

func _get_server_character_name(character: String) -> String:
	"""Optional project-level aliasing only (no built-in defaults)."""
	var aliases_raw = ProjectSettings.get_setting("syntree_voice/character_aliases", {})
	if typeof(aliases_raw) == TYPE_DICTIONARY and aliases_raw.has(character):
		return String(aliases_raw.get(character))
	return character

func _get_character_voice_config(character: String) -> Dictionary:
	var raw: Variant = character_voice_mapping.get(character, "")
	if typeof(raw) == TYPE_STRING and String(raw).is_empty():
		# Exact key not found — try common article variants ("The Narrator" vs "Narrator")
		if character.begins_with("The "):
			raw = character_voice_mapping.get(character.trim_prefix("The ").strip_edges(), "")
		else:
			raw = character_voice_mapping.get("The " + character, "")
	if typeof(raw) == TYPE_DICTIONARY:
		var cfg: Dictionary = raw
		var out := cfg.duplicate(true)
		if not out.has("voice"):
			out["voice"] = ""
		return out
	return {"voice": String(raw)}