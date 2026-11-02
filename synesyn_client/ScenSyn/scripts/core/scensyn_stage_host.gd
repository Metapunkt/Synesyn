class_name ScenSynStageHost
extends StoryStageHost

## Story Stage inside a ScenSyn session: the live story log, the session's scenario and
## cast, voice routing between the stage and the story log view, and ScenSyn's scenes,
## services and art folders. Named by the story_stage/default_host_script project
## setting, so a stage opened by scene path finds it.

const StageSessionScript = preload("res://ScenSyn/scripts/core/scensyn_stage_session.gd")
const SESSION_NODE_NAME := "ScenSynStageSession"
const LANDING_SCENE := "res://ScenSyn/scenes/main_menu.tscn"
const SPRITES_BASE := "res://ScenSyn/story_stage/sprites"
const GENERATED_SPRITES_BASE := "res://ScenSyn/story_stage/resources/generated/"
const BACKGROUNDS_DIR := "res://ScenSyn/story_stage/assets/images/"
const DialogTheme = preload("res://ScenSyn/themes/SynesynBase_light.tres")

var _workspace_root_cache_abs: String = ""
var _voices_scenario := ""
var _scenario_voices: Dictionary = {}
var _voice_http_owner: Node = null


func _init() -> void:
	if Global and not Global.tts_emitter_changed.is_connected(_on_tts_emitter_changed):
		Global.tts_emitter_changed.connect(_on_tts_emitter_changed)
	if StoryState:
		if not StoryState.visual_presentation_update.is_connected(_on_visual_presentation_update):
			StoryState.visual_presentation_update.connect(_on_visual_presentation_update)
		if not StoryState.phase_changed.is_connected(_on_phase_changed):
			StoryState.phase_changed.connect(_on_phase_changed)


func _on_tts_emitter_changed(new_emitter) -> void:
	voice_owner_changed.emit(String(new_emitter) == "story_stage")

func _on_visual_presentation_update(_ai_response: Dictionary) -> void:
	story_log_changed.emit()

func _on_phase_changed(new_phase: String) -> void:
	phase_changed.emit(new_phase)


func _game_flow_manager() -> Object:
	if Global and Global.has_method("get_game_flow_manager"):
		return Global.get_game_flow_manager()
	return null


# ── Scenario and story log ───────────────────────────────────────────────

func get_scenario() -> Dictionary:
	var gfm: Object = _game_flow_manager()
	if gfm and gfm.has_method("get_current_scenario"):
		var scen: Variant = gfm.get_current_scenario()
		if typeof(scen) == TYPE_DICTIONARY:
			return scen
	return {}

func has_session() -> bool:
	return StoryState != null and not StoryState.get_state().is_empty()

func get_story_log_entries() -> Array:
	if StoryState == null:
		return []
	return StoryState.get_state().get("story_log", [])


func plays_existing_log() -> bool:
	return false

## Only the host, or a player alone, commits a line; otherwise it reaches the story log
## through the host like any other participant's.
func commit_local_line(sender: String, text: String) -> bool:
	var has_other_peers: bool = Network.get_connected_peers().size() > 0
	var should_process: bool = Network.is_server() or not has_other_peers
	if not should_process:
		print("StoryStage: Not processing input (should_process = false, has_other_peers = ", has_other_peers, ")")
		return false
	print("StoryStage: Processing input (should_process = true)")
	StoryState.add_log_entry(sender, text)
	StoryState.advance_turn()
	print("StoryStage: Message added to StoryState - character: ", sender)
	print("StoryStage: Current turn: ", StoryState.get_state().get("current_turn", 0))
	var updated_story_log: Array = get_story_log_entries()
	print("StoryStage: Story log now has ", updated_story_log.size(), " entries")
	if not updated_story_log.is_empty():
		var updated_last_entry: Dictionary = updated_story_log.back()
		print("StoryStage: Last entry - sender: '", updated_last_entry.get("sender", ""), "', message: '", updated_last_entry.get("message", "").substr(0, 50), "...'")
	print("StoryStage: AICharacterAgent singleton exists: ", AICharacterAgent != null)
	if AICharacterAgent:
		print("StoryStage: AICharacterAgent ai_controlled_names: ", AICharacterAgent.ai_controlled_names)
	return true

## Resolved the same way as a line typed in the session view. A character chosen for a
## different scenario is not a candidate: Global.get_current_character() returns {} for
## one, which used to be written into the story log as the author of the line.
func get_local_speaker_name(peer_id: int) -> String:
	var named := GameSessionUiUtils.resolve_local_speaker_name(peer_id)
	var played := _played_character_name()
	if played == "" or named == played:
		return named
	# A network placeholder ("Player_1", a peer login) is not in [VOICES].
	# The first typed line was then spoken as the hub default, and only later
	# lines — once the name matched the cast — used the scenario voice.
	var voices := _collect_voices(get_scenario(), _loader_scenario())
	if _voice_config(voices, named).is_empty() and not _voice_config(voices, played).is_empty():
		return played
	return named

func get_local_character_name() -> String:
	if Global and Global.has_method("get_current_character"):
		return String(Global.get_current_character().get("name", "")).strip_edges()
	return ""


## The character this person is playing, including the pick Global is still
## hiding because its scenario stamp has not caught up. A name that is not in
## this scenario's [VOICES] block is ignored, so a character from another
## scenario cannot be spoken here.
func _played_character_name() -> String:
	var played := get_local_character_name()
	if played != "":
		return played
	if Global == null:
		return ""
	var picked := String(Global.current_character.get("name", "")).strip_edges()
	if picked == "":
		return ""
	var voices := _collect_voices(get_scenario(), _loader_scenario())
	if _voice_config(voices, picked).is_empty():
		return ""
	return picked

func load_story_log(path: String) -> void:
	if SceneTransition and SceneTransition.has_method("load_story_log_from_path"):
		SceneTransition.load_story_log_from_path(path)

func get_story_log_dir() -> String:
	return RuntimeConfig.get_scensyn_story_log_dir()


# ── Voice ────────────────────────────────────────────────────────────────

func create_voice() -> StoryStageVoice:
	if typeof(VoiceService) != TYPE_NIL:
		return SyntreeStageVoice.new()
	return StoryStageVoice.new()

func stage_owns_voice() -> bool:
	return Global != null and Global.get_tts_emitter() == "story_stage"

func set_stage_owns_voice(owns: bool) -> void:
	if Global:
		Global.set_tts_emitter("story_stage" if owns else "story_log")

## A scenario may lend one speaker another's voice. The pairs come from that
## scenario's [VOICE_OVERRIDES] block, not from a fixed cast.
func resolve_voice_name(speaker: String) -> String:
	var overrides_any: Variant = get_scenario().get("voice_overrides", {})
	if typeof(overrides_any) != TYPE_DICTIONARY:
		return speaker
	var key := _matching_key(overrides_any, speaker)
	if key == "":
		return speaker
	var target := str(overrides_any[key]).strip_edges()
	return target if target != "" else speaker


## Installs the running scenario's [VOICES] block. A later scenario replaces it.
## Speakers the block does not name get the same fallback the session view uses.
func apply_scenario_voices() -> void:
	if typeof(VoiceService) == TYPE_NIL or VoiceService == null:
		return
	var scenario := _scenario_for_voices()
	if scenario.is_empty():
		return
	var ident := _scenario_identity(scenario)
	if ident != "" and ident == _voices_scenario and not _scenario_voices.is_empty():
		return
	_install_scenario_voices(scenario)
	var voices_any: Variant = scenario.get("voices_mapping", {})
	_scenario_voices = voices_any.duplicate(true) if typeof(voices_any) == TYPE_DICTIONARY else {}
	if ident != "" and not _scenario_voices.is_empty():
		_voices_scenario = ident
	print("StoryStage: Voices for ", ident if ident != "" else "the running scenario", ": ", _voice_summary(_scenario_voices))
	_publish_voices_to_direct_server()


func voice_config_for(speaker: String) -> Dictionary:
	var config := _voice_for(speaker)
	if config.is_empty():
		# A cache taken before [VOICES] was attached would otherwise stick, and
		# the first line of that speaker would leave with the hub default.
		_voices_scenario = ""
		_scenario_voices = {}
		config = _voice_for(speaker)
	if config.is_empty():
		config = _voice_config(_collect_voices(get_scenario(), _loader_scenario()), _voice_source(speaker))
	if config.is_empty():
		var played := _played_character_name()
		if played != "" and played != speaker and _is_local_speaker(speaker):
			config = _voice_for(played)
			if config.is_empty():
				config = _voice_config(_collect_voices(get_scenario(), _loader_scenario()), played)
	return config


func _voice_source(speaker: String) -> String:
	var source := resolve_voice_name(speaker)
	return source if source != "" else speaker


func _is_local_speaker(speaker: String) -> bool:
	if speaker == "":
		return false
	if speaker == get_local_character_name() or speaker == _played_character_name():
		return true
	# The raw network name, before it is rewritten to the cast name. Resolving
	# through get_local_speaker_name here would call back into voice lookup.
	var network_name := GameSessionUiUtils.resolve_local_speaker_name(1)
	if network_name != "" and speaker == network_name:
		return true
	return speaker in ["Participant", "Unknown Character", "Unknown Player", "Unknown Peer"]


func _voice_for(speaker: String) -> Dictionary:
	apply_scenario_voices()
	var source := resolve_voice_name(speaker)
	var config := _voice_config(_scenario_voices, source)
	if config.is_empty() and source != speaker:
		config = _voice_config(_scenario_voices, speaker)
	return config


func _install_scenario_voices(scenario: Dictionary) -> void:
	var scenario_voices: Dictionary = {}
	var voices_any: Variant = scenario.get("voices_mapping", {})
	if typeof(voices_any) == TYPE_DICTIONARY:
		scenario_voices = voices_any
	var declared: Array = GameSessionScenarioUtils.collect_declared_speaker_names(scenario)
	if declared.is_empty():
		for voice_key_any in scenario_voices.keys():
			declared.append(str(voice_key_any))
	if declared.is_empty():
		return
	# An empty block means the scenario voices are not loaded yet. Stamping the
	# fallback pool here overwrites the voices the session already installed,
	# so the first line of a character speaks as the wrong person.
	if scenario_voices.is_empty():
		return
	var voice_pool: Array[String] = [
		"en-US-JennyNeural",
		"en-GB-RyanNeural",
		"en-US-GuyNeural",
		"en-US-ChristopherNeural",
		"en-US-AriaNeural",
	]
	for speaker_name_any in declared:
		var speaker_name := String(speaker_name_any)
		var selected_voice := ""
		var selected_config: Dictionary = {}
		var voice_key := _matching_key(scenario_voices, speaker_name)
		if voice_key != "":
			var config_any: Variant = scenario_voices[voice_key]
			if typeof(config_any) == TYPE_DICTIONARY and (config_any as Dictionary).has("voice"):
				selected_voice = String((config_any as Dictionary)["voice"])
				selected_config = (config_any as Dictionary).duplicate(true)
			else:
				selected_voice = String(config_any)
		else:
			# A full config is already stored. The pool must not replace it:
			# that replacement was the player's first line speaking as the default.
			if _installed_config_is_dict(speaker_name):
				continue
			var voice_index := GameSessionUiUtils.stable_index_from_name(speaker_name, voice_pool.size())
			selected_voice = voice_pool[voice_index]
		if not selected_config.is_empty() and VoiceService.has_method("set_character_voice_config"):
			VoiceService.set_character_voice_config(speaker_name, selected_config)
		elif selected_voice != "":
			VoiceService.set_character_voice(speaker_name, selected_voice)


func _installed_config_is_dict(speaker_name: String) -> bool:
	if typeof(VoiceService) == TYPE_NIL or VoiceService == null:
		return false
	if not VoiceService.has_method("get_character_voices"):
		return false
	var voices: Dictionary = VoiceService.get_character_voices()
	return typeof(voices.get(speaker_name, "")) == TYPE_DICTIONARY


func _scenario_for_voices() -> Dictionary:
	var scenario := get_scenario()
	var loaded := _loader_scenario()
	var base := scenario if not scenario.is_empty() else loaded
	if base.is_empty():
		return {}
	var voices := _collect_voices(scenario, loaded)
	if voices.is_empty():
		return base
	var donor := loaded.duplicate(false)
	donor["voices_mapping"] = voices
	var live_overrides: Variant = scenario.get("voice_overrides", {})
	if typeof(live_overrides) == TYPE_DICTIONARY and not (live_overrides as Dictionary).is_empty():
		donor["voice_overrides"] = live_overrides
	return _with_voices(base, donor)


## The running scenario, the loader, and the scenario file can each be missing
## speakers the others have. Names already collected are left as they are, so a
## live block is not replaced by a fallback.
func _collect_voices(scenario: Dictionary, loaded: Dictionary) -> Dictionary:
	var voices: Dictionary = {}
	_merge_voice_block(voices, scenario.get("voices_mapping", {}))
	_merge_voice_block(voices, loaded.get("voices_mapping", {}))
	var path := str(scenario.get("_scenario_file", "")).strip_edges()
	if path == "":
		path = str(loaded.get("_scenario_file", "")).strip_edges()
	if path != "" and FileAccess.file_exists(path):
		_merge_voice_block(voices, _voices_in_file(path))
	return voices


func _merge_voice_block(into: Dictionary, raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	for key_any in (raw as Dictionary).keys():
		var key := str(key_any).strip_edges()
		if key == "" or _matching_key(into, key) != "":
			continue
		into[key] = (raw as Dictionary)[key_any]


func _loader_scenario() -> Dictionary:
	if Global == null or not Global.has_method("get_scenario_loader"):
		return {}
	var loader: Object = Global.get_scenario_loader()
	if loader == null or not loader.has_method("get_current_scenario"):
		return {}
	var raw: Variant = loader.get_current_scenario()
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


func _with_voices(scenario: Dictionary, loaded: Dictionary) -> Dictionary:
	var merged := scenario.duplicate(false)
	merged["voices_mapping"] = (loaded["voices_mapping"] as Dictionary).duplicate(true)
	if typeof(scenario.get("voice_overrides")) != TYPE_DICTIONARY and typeof(loaded.get("voice_overrides")) == TYPE_DICTIONARY:
		merged["voice_overrides"] = loaded["voice_overrides"]
	if str(merged.get("_scenario_file", "")).strip_edges() == "":
		merged["_scenario_file"] = str(loaded.get("_scenario_file", ""))
	return merged


func _scenario_identity(scenario: Dictionary) -> String:
	var path := str(scenario.get("_scenario_file", "")).strip_edges()
	if path != "":
		return path
	var collection := str(scenario.get("_collection_id", "")).strip_edges()
	var scenario_name := str(scenario.get("_scenario_name", scenario.get("name", ""))).strip_edges()
	if collection == "" and scenario_name == "":
		return ""
	return collection + "/" + scenario_name


func _voices_in_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var voices: Dictionary = {}
	var in_voices := false
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("[") and line.ends_with("]") and line.find("[", 1) == -1:
			in_voices = line == "[VOICES]"
			continue
		if not in_voices or line == "" or line.begins_with("#"):
			continue
		var parts := line.split(":", true, 1)
		if parts.size() != 2:
			continue
		var speaker := parts[0].strip_edges()
		var rhs := parts[1].strip_edges()
		if speaker == "" or rhs == "":
			continue
		var config: Dictionary = {}
		if rhs.find("=") == -1:
			config["voice"] = rhs
		else:
			for token_any in rhs.split(","):
				var token := str(token_any).strip_edges()
				var pair := token.split("=", true, 1)
				if pair.size() == 2:
					config[pair[0].strip_edges().to_lower()] = pair[1].strip_edges()
		if config.has("voice") and str(config["voice"]).strip_edges() != "":
			voices[speaker] = config
	return voices


func _voice_config(voices: Dictionary, speaker: String) -> Dictionary:
	var key := _matching_key(voices, speaker)
	if key == "":
		return {}
	var config_any: Variant = voices[key]
	if typeof(config_any) == TYPE_DICTIONARY and (config_any as Dictionary).has("voice"):
		return (config_any as Dictionary).duplicate(true)
	var voice_id := str(config_any).strip_edges()
	if voice_id == "":
		return {}
	return {"voice": voice_id}


func _matching_key(mapping: Dictionary, speaker: String) -> String:
	if speaker == "" or mapping.is_empty():
		return ""
	if mapping.has(speaker):
		return speaker
	var folded := _folded_key(mapping, speaker)
	if folded != "":
		return folded
	var want := speaker.strip_edges().to_lower()
	var alternate := speaker.trim_prefix("The ").strip_edges() if speaker.begins_with("The ") else "The " + speaker
	var alternate_lower := alternate.strip_edges().to_lower()
	for key_any in mapping.keys():
		var key := str(key_any).strip_edges()
		var lowered := key.to_lower()
		if lowered == want or lowered == alternate_lower:
			return key
	return ""


func _publish_voices_to_direct_server() -> void:
	if _voice_http_owner == null or not is_instance_valid(_voice_http_owner) or _scenario_voices.is_empty():
		return
	if typeof(VoiceService) == TYPE_NIL or VoiceService == null:
		return
	var mode := str(VoiceService.get("provider_mode")).strip_edges().to_lower()
	if mode != "" and mode != "direct":
		return
	GameSessionScenarioUtils.post_voices_mapping_to_server(_voice_http_owner, _scenario_voices)


## A leading "The" matches the other form only when the scenario wrote just one of them.
func _folded_key(mapping: Dictionary, speaker: String) -> String:
	if speaker == "":
		return ""
	var alternate := speaker.trim_prefix("The ").strip_edges() if speaker.begins_with("The ") else "The " + speaker
	if alternate != speaker and mapping.has(alternate) and not mapping.has(speaker):
		return alternate
	return ""


func _voice_summary(voices: Dictionary) -> String:
	var parts: PackedStringArray = []
	for speaker_any in voices.keys():
		var speaker := str(speaker_any)
		var config := _voice_config(voices, speaker)
		parts.append("%s=%s" % [speaker, str(config.get("voice", ""))])
	return ", ".join(parts)

## Consent to keep recordings lives in the runtime config and, when voice goes through
## the hub, with the hub session too.
func get_save_recordings() -> bool:
	var voice_any: Variant = RuntimeConfig.load_config().get("voice", {})
	if typeof(voice_any) == TYPE_DICTIONARY:
		return (voice_any as Dictionary).get("save_recordings", false) == true
	return false

func set_save_recordings(stage: Node, enabled: bool) -> bool:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var voice_any: Variant = cfg.get("voice", {})
	var voice_cfg: Dictionary = voice_any if typeof(voice_any) == TYPE_DICTIONARY else {}
	voice_cfg["save_recordings"] = enabled
	cfg["voice"] = voice_cfg
	RuntimeConfig.save_config(cfg)
	var provider_mode: String = str(voice_cfg.get("provider_mode", "direct")).strip_edges().to_lower()
	if provider_mode != "hub":
		return false
	var session: Node = _session_node(stage)
	if session == null:
		return false
	var res: Dictionary = await session.hub().set_session_consent_save_recordings(SynesynSession.get_or_create_session_id("scensyn"), enabled)
	if not (res.get("ok", false) == true):
		push_warning("StoryStage: Failed to update hub consent: %s" % str(res.get("error", "unknown error")))
	return true


# ── Opening narration ────────────────────────────────────────────────────

func get_opening_welcome_text() -> String:
	return Global.opening_welcome_text if Global else ""

func mark_opening_spoken_on_stage() -> void:
	if Global:
		Global.opening_spoken_stage = true

func reset_opening_spoken() -> void:
	if Global:
		Global.opening_spoken_log = false
		Global.opening_spoken_stage = false

func clear_opening_for_loaded_log() -> void:
	if Global:
		Global.opening_welcome_text = ""
		Global.opening_spoken_stage = true
		Global.opening_spoken_log = true


# ── Input and generation ─────────────────────────────────────────────────

func get_player_auto_input() -> Object:
	return Global.get_player_auto_input() if Global else null

func is_ai_busy() -> bool:
	return AICharacterAgent != null and AICharacterAgent.is_busy()


# ── Optional features ────────────────────────────────────────────────────

func supports(_feature: StringName) -> bool:
	return true

func _session_node(stage: Node) -> Node:
	return stage.get_node_or_null(SESSION_NODE_NAME) if stage else null

func attach_session_services(stage: Node) -> void:
	_voice_http_owner = stage
	_decorate_stage_buttons(stage)
	if _session_node(stage) != null:
		return
	var session: Node = StageSessionScript.new()
	session.name = SESSION_NODE_NAME
	stage.add_child(session)
	session.setup(stage)

func _decorate_stage_buttons(stage: Node) -> void:
	var icons := {
		"StageRecordButton": "res://Synesyn_icons/synesyn-button-icons/icon_record_circle.svg",
		"StageAutoSendVoice": "res://Synesyn_icons/synesyn-button-icons/icon_auto_send_radio.svg",
		"StageAutoPlayerInput": "res://Synesyn_icons/synesyn-button-icons/icon_person_silhouette.svg",
		"SendButton": "res://Synesyn_icons/synesyn-button-icons/icon_send_paper_plane.svg",
	}
	for node_name in icons:
		var button := stage.get_node_or_null("%" + str(node_name)) as BaseButton
		if button == null:
			continue
		var tex: Texture2D = load(str(icons[node_name]))
		if tex:
			button.icon = tex
		button.add_theme_constant_override("icon_max_width", 16)
		var icon_tint := Color(1, 1, 1, 0.72)
		for color_name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(color_name, icon_tint)
		button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
	var record := stage.get_node_or_null("%StageRecordButton") as BaseButton
	if record == null:
		return
	record.set_meta("record_icon", record.icon)
	var stop_tex: Texture2D = load("res://Synesyn_icons/synesyn-button-icons/icon_stop_square.svg")
	if stop_tex:
		record.set_meta("stop_icon", stop_tex)


func populate_settings(stage: Node) -> void:
	var session: Node = _session_node(stage)
	if session:
		session.ensure_model_controls()

func navigate(stage: Node, target: String) -> void:
	match target:
		"landing":
			stage.get_tree().change_scene_to_file(LANDING_SCENE)
		"story_stage":
			print("StoryStage: Switching to story stage")
			SceneTransition.switch_to_story_stage()
		_:
			print("StoryStage: Switching to chat mode")
			SceneTransition.switch_to_story_log()

func _services_panel(stage: Node) -> Node:
	return stage.get_tree().root.find_child("ServicesPanel", true, false)

func toggle_services(stage: Node) -> bool:
	var services: Node = _services_panel(stage)
	if not services:
		return false
	if services.has_method("is_panel_open") and services.is_panel_open():
		return true
	if services.has_method("open_panel"):
		services.open_panel()
	else:
		services.visible = true
	return true

func close_services(stage: Node) -> bool:
	var services: Node = _services_panel(stage)
	if services and services.has_method("is_panel_open") and services.is_panel_open():
		services.close_panel()
		return true
	return false

func start_new_story_log(stage: Node) -> bool:
	var sessions: Array = stage.get_tree().get_nodes_in_group("game_session")
	if sessions.is_empty():
		return false
	var game_session_node: Node = sessions[0]
	if game_session_node and game_session_node.has_method("_create_new_story_log"):
		game_session_node._create_new_story_log()
		return true
	return false

func request_render(stage: Node, kind: String) -> void:
	var session: Node = _session_node(stage)
	if session:
		await session.request_render(kind)

func set_dual_window(enabled: bool) -> void:
	print("StoryStage: Dual window mode toggled: ", enabled)
	print("StoryStage: DualWindowManager exists: ", DualWindowManager != null)
	if enabled:
		print("StoryStage: Calling enable_dual_window_mode")
		DualWindowManager.enable_dual_window_mode()
	else:
		print("StoryStage: Calling disable_dual_window_mode")
		DualWindowManager.disable_dual_window_mode()

func get_dialog_theme() -> Theme:
	return DialogTheme


# ── Art ──────────────────────────────────────────────────────────────────

## Sprite art is filed by collection and scenario slug, with a shared default:
##   <workspace>/scensyn/sprites_generated/<collection>/<scenario>/  (rendered at runtime)
##   sprites/<collection>/<scenario>/
##   sprites/default/
func _sprite_context_dirs() -> Array[String]:
	var collection_dir: String = "default"
	var scenario_dir: String = "default"
	if Global:
		collection_dir = StoryStageCharacter._dir_slug(String(Global.current_collection_id))
		if Global.has_method("get_current_scenario"):
			var scen: Variant = Global.get_current_scenario()
			var scen_name: String = ""
			if typeof(scen) == TYPE_DICTIONARY:
				scen_name = String((scen as Dictionary).get("_scenario_name", (scen as Dictionary).get("name", ""))).strip_edges()
			if not scen_name.is_empty():
				scenario_dir = StoryStageCharacter._dir_slug(scen_name)
	return [collection_dir, scenario_dir]

func get_sprite_roots() -> Array[String]:
	var dirs: Array[String] = _sprite_context_dirs()
	var roots: Array[String] = []
	var ws_root_abs: String = _get_workspace_root_abs_best_effort()
	if not ws_root_abs.is_empty():
		var gen_root: String = ws_root_abs.path_join("scensyn").path_join("sprites_generated").path_join(dirs[0]).path_join(dirs[1])
		roots.append(gen_root.replace("\\", "/"))
	roots.append(SPRITES_BASE.path_join(dirs[0]).path_join(dirs[1]))
	roots.append(SPRITES_BASE.path_join("default"))
	return roots

## Generated SpriteFrames are namespaced by the root they were built from, so they do
## not collide across scenarios: resources/generated/<collection>/<scenario>/<char>_sprites.tres
func get_generated_sprite_resource_path(root_path: String, char_dir_name: String) -> String:
	var rel: String = String(root_path).replace(SPRITES_BASE, "").strip_edges()
	rel = rel.trim_prefix("/").trim_suffix("/")
	if rel.is_empty():
		rel = "legacy"
	return GENERATED_SPRITES_BASE + rel + "/" + char_dir_name + "_sprites.tres"

## The session scenario's own art, keyed by the scenario's collection and scenario_key
## (or its slugged name), which is not always the slug the sprite folders use.
func get_scenario_art_dir() -> String:
	var collection_slug: String = ""
	var scenario_slug: String = ""
	var scen: Dictionary = get_scenario()
	if not scen.is_empty():
		collection_slug = str(scen.get("_collection_id", Global.current_collection_id if Global else "default")).strip_edges()
		scenario_slug = str(scen.get("scenario_key", "")).strip_edges()
		if scenario_slug.is_empty():
			scenario_slug = str(scen.get("name", "")).strip_edges().to_lower().replace(" ", "_")
	if collection_slug.is_empty() and Global:
		collection_slug = str(Global.current_collection_id).strip_edges()
	return "%s/%s/%s" % [SPRITES_BASE, collection_slug, scenario_slug]

func get_backgrounds_dir() -> String:
	return BACKGROUNDS_DIR

func get_replay_backgrounds_dir() -> String:
	var ws_root: String = ScenSynGeneratedSpriteStore.get_workspace_root_abs()
	if ws_root.is_empty():
		return ""
	var scenario_key: String = String(get_scenario().get("name", "")).strip_edges().to_lower().replace(" ", "_")
	if scenario_key.is_empty():
		return ""
	return ws_root.replace("\\", "/").path_join("scensyn").path_join("vis_story_backgrounds").path_join(scenario_key)

func forget_cached_paths() -> void:
	_workspace_root_cache_abs = ""


func _workspace_state_candidates_abs() -> Array[String]:
	var candidates: Array[String] = []
	var cfg_path_abs: String = str(RuntimeConfig.get_config_path_abs()).strip_edges()
	if not cfg_path_abs.is_empty():
		candidates.append(cfg_path_abs.get_base_dir().path_join("workspace_state.json"))
	candidates.append(ProjectSettings.globalize_path("user://workspace_state.json"))
	return candidates

func _get_workspace_root_abs_best_effort() -> String:
	if not _workspace_root_cache_abs.is_empty():
		return _workspace_root_cache_abs
	for p in _workspace_state_candidates_abs():
		if p.strip_edges().is_empty() or (not FileAccess.file_exists(p)):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if not f:
			continue
		var raw: String = f.get_as_text()
		f.close()
		var parsed_any: Variant = JSON.parse_string(raw)
		if typeof(parsed_any) != TYPE_DICTIONARY:
			continue
		var st: Dictionary = parsed_any
		var base_root: String = str(st.get("root_base", "")).strip_edges()
		var slug: String = str(st.get("slug", "")).strip_edges()
		if base_root.is_empty() or slug.is_empty():
			continue
		_workspace_root_cache_abs = base_root.path_join(slug).replace("\\", "/")
		return _workspace_root_cache_abs
	return ""
