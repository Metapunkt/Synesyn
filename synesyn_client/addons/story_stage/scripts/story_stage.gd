extends Node2D

signal line_displayed(speaker: String, message: String, index: int)

var host: StoryStageHost
var voice: StoryStageVoice
var line_feed: StoryStageLineFeed
var background_controller: StoryStageBackgroundController
var last_displayed_index := -1
var is_displaying_message := false
var is_lull_speaking := false

var imagery: StoryStageImagery
var characters: StoryStageCharacter
var presenter: StoryStagePresenter
var lull: StoryStageLull
var ambient: StoryStageAmbientSoundBridge
var motion: StoryStageMotion
var capabilities: StoryStageCapabilities
var topology: StoryStageTopology
var cues: StoryStageCuePlayer

var motion_rung := 0
var imagery_name := "authored"
var active_stage_id := "main"
var line_provenance: Dictionary = {}

var _current_speaker := ""
var _last_speaker := ""
var _welcome := ""
var _welcome_playing := false
var _opening_done := false
var _initial_log_count := 0
var _line_voiced := false
var _ui: StoryStageUi
var settings_panel: Control
var _settings_vbox: VBoxContainer


func _enter_tree() -> void:
	if host == null:
		host = StoryStageHost.resolve_default()


func _ready() -> void:
	_initial_log_count = host.get_story_log_entries().size()
	_welcome = host.get_opening_welcome_text()
	_ui = $CanvasLayer3/UIControls as StoryStageUi
	settings_panel = get_node_or_null("CanvasLayer3/UIControls/SettingsPanel") as Control
	_settings_vbox = get_node_or_null("CanvasLayer3/UIControls/SettingsPanel/MarginContainer/ScrollContainer/SettingsVBox") as VBoxContainer
	_build_surface()
	characters = StoryStageCharacter.new()
	characters.name = "CharacterRegistry"
	characters.setup(self)
	add_child(characters)
	voice = host.create_voice()
	voice.name = "Voice"
	add_child(voice)
	voice.attach(self)
	imagery = host.create_imagery()
	imagery.name = "Imagery"
	add_child(imagery)
	imagery.attach(self)
	motion = StoryStageMotion.new()
	motion.name = "Motion"
	add_child(motion)
	motion.setup(self)
	presenter = StoryStagePresenter2D.new()
	presenter.name = "Presenter"
	add_child(presenter)
	presenter.setup(self)
	background_controller = StoryStageBackgroundController.new()
	background_controller.name = "BackgroundController"
	background_controller.host = host
	add_child(background_controller)
	background_controller.initialize_with_background(%Background)
	lull = StoryStageLull.new()
	lull.name = "Lull"
	add_child(lull)
	lull.setup(self)
	ambient = StoryStageAmbientSoundBridge.new()
	ambient.name = "Ambient"
	add_child(ambient)
	ambient.setup(self)
	cues = StoryStageCuePlayer.new()
	cues.name = "Cues"
	add_child(cues)
	cues.setup(self)
	topology = StoryStageTopology.new()
	topology.name = "Topology"
	add_child(topology)
	topology.setup(self)
	capabilities = StoryStageCapabilities.new()
	capabilities.name = "Capabilities"
	add_child(capabilities)
	capabilities.setup(self)
	capabilities.publish()
	line_feed = StoryStageLineFeed.new()
	line_feed.name = "LineFeed"
	add_child(line_feed)
	line_feed.initialize(self)
	_bind_render_buttons()
	_ui.bind_runtime(self)
	host.attach_session_services(self)
	if host.supports(StoryStageHost.FEATURE_MODEL_CONTROLS):
		host.populate_settings(self)
	voice.refresh_roster(host.get_scenario())
	if host.has_method("apply_scenario_voices"):
		host.apply_scenario_voices()
	if not voice.ready_to_speak.is_connected(_on_voice_ready):
		voice.ready_to_speak.connect(_on_voice_ready)
	if not voice.playback_finished.is_connected(_on_welcome_playback_finished):
		voice.playback_finished.connect(_on_welcome_playback_finished)
	_on_voice_ready()
	line_feed.queue_next_entry()


func _process(_delta: float) -> void:
	var show: bool = host.is_ai_busy() or (lull != null and lull.loading_visible)
	if _ui:
		_ui.set_loading(show)
	_sync_surface()


func voice_on() -> bool:
	return host != null and host.stage_owns_voice() and voice != null and voice.is_present()


func scenario_section(section_key: String) -> Dictionary:
	var scenario := host.get_scenario()
	var key := section_key.to_lower()
	if not scenario.has(key) or not (scenario[key] is Dictionary):
		return {}
	return scenario[key]


func scenario_section_enabled(section_key: String, default_enabled: bool = true) -> bool:
	var scenario := host.get_scenario()
	var key := section_key.to_lower()
	if not scenario.has(key) or not (scenario[key] is Dictionary):
		return false
	var section: Dictionary = scenario[key]
	if section.is_empty():
		return false
	var fallback := "true" if default_enabled else "false"
	return str(section.get("enabled", fallback)).to_lower() == "true"


func notify_turn_started(turn_id: int) -> void:
	if lull:
		lull.note_activity()
	if background_controller:
		background_controller.notify_turn_started(turn_id)
	if ambient:
		ambient.send_turn(turn_id)
	if imagery and scenario_section_enabled("vis_story", false):
		imagery.request_backdrop({"turn_id": turn_id, "cue_id": str(turn_id)})


func refresh_character_art(character_name: String) -> void:
	characters.refresh_character_sprite_frames(character_name)
	if not is_displaying_message and presenter:
		presenter.show_line(character_name, "", null, motion_rung)


func replay_story_log() -> void:
	if voice:
		voice.stop_all()
	if background_controller:
		background_controller.preload_replay_dir()
	if line_feed:
		line_feed.reset_story_progress(self)
		line_feed.queue_next_entry()


func set_render_status(text: String) -> void:
	var label := get_node_or_null("%SynpunktRenderStatusLabel") as RichTextLabel
	if label:
		label.text = text


func current_speaker_for_render() -> String:
	if is_displaying_message and _current_speaker != "":
		return _current_speaker
	return _last_speaker


func test_apply_state(state: Dictionary) -> void:
	var hook := find_child("DevHarnessHooks", true, false)
	if hook and hook.has_method("apply_state"):
		hook.apply_state(state)


func test_dump_logs(output_path: String, since_msec: int = 0) -> void:
	var hook := find_child("DevHarnessHooks", true, false)
	if hook == null:
		return
	if hook.has_method("test_dump_logs"):
		hook.test_dump_logs(output_path, since_msec)
	elif hook.has_method("dump_logs"):
		hook.dump_logs(output_path, since_msec)


func test_dump_ui_metrics(output_path: String) -> void:
	if not OS.has_feature("editor"):
		return
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(collect_ui_metrics(), "\t"))


func collect_ui_metrics() -> Dictionary:
	var controls: Array = []
	_collect_controls(self, controls)
	return {"count": controls.size(), "controls": controls}


func get_speaker_bus(speaker: String) -> String:
	return motion.bus_for(speaker)


func welcome_text() -> String:
	if _welcome != "":
		return _welcome
	return host.get_opening_welcome_text()


func register_scensyn_character(char_data: Dictionary) -> int:
	return characters.register_character(char_data)


func get_enum_from_string(cname: String) -> int:
	return characters.id_for_name(cname)


func get_character_details(id: int) -> Dictionary:
	return characters.get_character_details(id)


func get_character_details_by_name(cname: String) -> Dictionary:
	return characters.get_character_details_by_name(cname)


func clear_all_characters() -> void:
	characters.reset()


func get_surface_texture() -> ViewportTexture:
	return ($StageViewport as SubViewport).get_texture()


func restage_visible_line(speaker: String, text: String) -> void:
	_current_speaker = speaker
	_last_speaker = speaker
	if _ui:
		_ui.present_line(speaker, text, true)
	if presenter:
		presenter.show_line(speaker, text, null, 0)
	is_displaying_message = false


func present_log_line(speaker: String, text: String, entry: Dictionary, index: int, voiced: bool) -> void:
	_current_speaker = speaker
	_last_speaker = speaker
	_line_voiced = voiced
	var rung := _rung_for(entry, index)
	var choices: Array = entry.get("choices", []) if entry.get("choices") is Array else []
	_ui.present_line(speaker, text, voiced, choices)
	presenter.show_line(speaker, text, entry.get("stage_cues"), rung)
	cues.start(entry.get("stage_cues"), voiced)
	if lull:
		lull.note_activity()
	if voiced and ambient:
		ambient.note_speaker(speaker)
	if background_controller:
		background_controller.note_speaker(speaker)
	line_provenance = {"motion_rung": rung, "imagery": imagery_name, "stage_id": active_stage_id}
	line_displayed.emit(speaker, text, index)


func release_line_visuals() -> void:
	if presenter:
		presenter.on_line_released()
		presenter.stop_cues()
	if _ui:
		_ui.stop_typewriter()
		_ui.fade_if_idle(self)
	if _line_voiced and ambient:
		ambient.note_speech_ended()
	_line_voiced = false


func show_lull_line(line: String) -> void:
	if _ui:
		_ui.present_line("Narrator", line, voice_on())


func set_loading_indicator(show: bool) -> void:
	if _ui:
		_ui.set_loading(show)


func note_speech_started(speaker: String) -> void:
	_current_speaker = speaker
	motion.bus_for(speaker)


func note_synthesis(_speaker: String, _duration: float) -> void:
	pass


func skip_current_line() -> void:
	if voice:
		voice.stop_all()
	if line_feed:
		line_feed.release_current()


func _calculate_text_animation_duration(text: String) -> float:
	if text.is_empty():
		return 0.0
	var punct := text.count(".") + text.count("!") + text.count("?")
	return text.length() / 30.0 + 0.2 * float(punct)


func _rung_for(entry: Dictionary, index: int) -> int:
	if entry.has("motion_rung"):
		return int(entry["motion_rung"])
	if index < _initial_log_count:
		return 0
	entry["motion_rung"] = motion_rung
	entry["imagery"] = imagery_name
	entry["stage_id"] = active_stage_id
	return motion_rung


func _on_voice_ready() -> void:
	if _opening_done or not voice_on():
		return
	_opening_done = true
	_welcome = host.get_opening_welcome_text()
	if _welcome == "" or voice.get_skip_welcome() or host.opening_was_spoken():
		return
	is_displaying_message = true
	_ui.present_line("Narrator", _welcome, true)
	var accepted := voice.speak(host.resolve_voice_name("Narrator"), _welcome, "neutral")
	host.mark_opening_spoken_on_stage()
	if accepted and line_feed:
		_welcome_playing = true
		line_feed.arm_playback_wait()
	else:
		is_displaying_message = false


func dismiss_welcome() -> void:
	var welcome := welcome_text().strip_edges()
	var on_screen := false
	if _ui and welcome != "":
		on_screen = _ui.current_speaker() == "Narrator" and _ui.current_line().strip_edges() == welcome
	if not _welcome_playing and not on_screen:
		return
	_welcome_playing = false
	if line_feed:
		line_feed.abandon_wait()
	if voice and voice.has_method("stop_welcome_narration"):
		voice.stop_welcome_narration()
	elif voice:
		voice.stop_all()
	is_displaying_message = false


func _on_welcome_playback_finished(_speaker: String) -> void:
	_welcome_playing = false


func _bind_render_buttons() -> void:
	var kinds := {
		"EnqueueBackgroundRenderBtn": "background",
		"EnqueuePortraitRenderBtn": "portrait",
		"EnqueuePropCardRenderBtn": "prop_card",
	}
	for node_name in kinds:
		var button := get_node_or_null("%" + str(node_name)) as BaseButton
		if button == null:
			continue
		var kind := str(kinds[node_name])
		button.pressed.connect(_request_render.bind(kind))
		button.visible = host.supports(StoryStageHost.FEATURE_RENDER)


func _request_render(kind: String) -> void:
	host.request_render(self, kind)


func _build_surface() -> void:
	var viewport := $StageViewport as SubViewport
	var world := Node2D.new()
	world.name = "StageWorld"
	viewport.add_child(world)
	var backdrop := Sprite2D.new()
	backdrop.name = "Backdrop"
	backdrop.centered = false
	world.add_child(backdrop)
	var portrait := Sprite2D.new()
	portrait.name = "SurfacePortrait"
	portrait.position = Vector2(640, 400)
	world.add_child(portrait)
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	world.add_child(camera)
	camera.make_current()


func _sync_surface() -> void:
	var portrait := get_node_or_null("StageViewport/StageWorld/SurfacePortrait") as Sprite2D
	if portrait and presenter and presenter.sprite:
		var texture := presenter.sprite.current_texture()
		if texture:
			portrait.texture = texture


func _collect_controls(node: Node, controls: Array) -> void:
	if node is Control:
		var control := node as Control
		var item := {
			"path": str(control.get_path()),
			"type": control.get_class(),
			"visible": control.visible,
			"pos": {"x": control.position.x, "y": control.position.y},
			"size": {"x": control.size.x, "y": control.size.y},
			"mouse_filter": int(control.mouse_filter),
			"focus_mode": int(control.focus_mode),
		}
		for prop in control.get_property_list():
			if str(prop.name) == "disabled":
				item["disabled"] = bool(control.get("disabled"))
			elif str(prop.name) == "editable":
				item["editable"] = bool(control.get("editable"))
		controls.append(item)
	for child in node.get_children():
		_collect_controls(child, controls)
