extends RefCounted
class_name GameSessionUiUtils

const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)
const PORTRAIT_BG_TEXTURES: Array = [
	preload("res://Synesyn_icons/synesyn-backgrounds/bg_portrait_amber.png"),
	preload("res://Synesyn_icons/synesyn-backgrounds/bg_portrait_teal.png"),
	preload("res://Synesyn_icons/synesyn-backgrounds/bg_portrait_violet.png"),
	preload("res://Synesyn_icons/synesyn-backgrounds/bg_portrait_rose.png"),
]

## game_session.tscn uses TextureProgressBar (extends Range), not ProgressBar.
## Casting to ProgressBar always yields null and silently disables wait feedback.
static func _resolve_progress_bar(owner: Node) -> Range:
	var progress_bar_any: Variant = owner.get("progress_bar")
	if typeof(progress_bar_any) != TYPE_OBJECT or not is_instance_valid(progress_bar_any):
		return null
	return progress_bar_any as Range


static func show_bar(owner: Node) -> void:
	var progress_bar: Range = _resolve_progress_bar(owner)
	if progress_bar == null:
		return
	progress_bar.value = 0
	progress_bar.modulate.a = 1.0
	progress_bar.visible = true
	_fit_wait_progress_host(progress_bar, true)

static func hide_bar(owner: Node) -> void:
	var progress_bar: Range = _resolve_progress_bar(owner)
	if progress_bar == null:
		return
	var fade_tween := owner.create_tween()
	fade_tween.tween_property(progress_bar, "modulate:a", 0.0, 0.3)
	progress_bar.visible = false
	progress_bar.value = 0
	_fit_wait_progress_host(progress_bar, false)

static func _fit_wait_progress_host(progress_bar: Range, is_shown: bool) -> void:
	var slot_node: Control = progress_bar.get_parent() as Control
	if slot_node == null or slot_node.name != "WaitProgressSlot":
		# Story Catalyst: keep the corner overlay above session chrome.
		if is_shown:
			progress_bar.z_index = 100
			progress_bar.move_to_front()
		return
	progress_bar.z_index = 0
	slot_node.visible = is_shown
	slot_node.custom_minimum_size = Vector2(0, 16 if is_shown else 0)

static func animate_progress_start(owner: Node) -> void:
	var progress_bar: Range = _resolve_progress_bar(owner)
	if progress_bar == null:
		return
	show_bar(owner)
	var progress_tween: Tween = owner.get("_progress_tween")
	if progress_tween and progress_tween.is_valid():
		progress_tween.kill()
	progress_tween = owner.create_tween()
	progress_tween.set_trans(Tween.TRANS_LINEAR)
	progress_tween.tween_property(progress_bar, "value", 80.0, 1.5)
	progress_tween.tween_property(progress_bar, "value", 95.0, 3.0)
	owner.set("_progress_tween", progress_tween)

static func animate_progress_complete(owner: Node, success: bool) -> void:
	var progress_bar: Range = _resolve_progress_bar(owner)
	if progress_bar == null:
		return
	var progress_tween: Tween = owner.get("_progress_tween")
	if progress_tween and progress_tween.is_valid():
		progress_tween.kill()
	var completion_tween: Tween = owner.get("_completion_tween")
	if completion_tween and completion_tween.is_valid():
		completion_tween.kill()
	completion_tween = owner.create_tween()
	completion_tween.set_trans(Tween.TRANS_SINE)
	if success:
		completion_tween.tween_property(progress_bar, "value", 100.0, 0.2)
	completion_tween.tween_callback(Callable(owner, "_hide_bar")).set_delay(0.1)
	owner.set("_completion_tween", completion_tween)

static func animate_scroll_indicator(owner: Node) -> void:
	var scroll_tween: Tween = owner.get("scroll_tween")
	if scroll_tween:
		scroll_tween.kill()
	var scroll_indicator: Control = owner.get("scroll_indicator") as Control
	if not is_instance_valid(scroll_indicator):
		return
	scroll_indicator.modulate.a = 1.0
	scroll_indicator.visible = true
	scroll_tween = owner.create_tween()
	scroll_tween.tween_property(scroll_indicator, "modulate:a", 0.0, 1.0)
	scroll_tween.tween_property(scroll_indicator, "visible", false, 0.0)
	owner.set("scroll_tween", scroll_tween)

## The configured input source for a scenario that has no human character, or "".
## Scenarios driven by external input skip character selection, so there is nobody to
## announce; naming the source is both true and more use than an error message.
static func external_sender_display() -> String:
	if Global == null or not Global.has_method("get_player_auto_input"):
		return ""
	var auto_input = Global.get_player_auto_input()
	if auto_input == null or not auto_input.has_method("external_sender_name"):
		return ""
	return String(auto_input.external_sender_name())


## Names the network uses when it has nothing for a peer. Two of them, because the
## character lookup and the peer lookup each carry their own, and code that checked only
## one wrote "Unknown Peer" into the story log as the author of a line.
const UNKNOWN_SPEAKER_NAMES: Array[String] = [
	"", "Unknown Character", "Unknown Player", "Unknown Peer"
]


## Who a line typed on this device is from, most specific first: the character the
## network holds for this peer, the peer's own name, a character chosen for this
## scenario, the configured external input source, and failing all of those a plain
## participant. Shared by the session and by Story Stage so the same typed line is not
## credited to two different speakers depending on which view it was typed in.
static func resolve_local_speaker_name(sender_id: int) -> String:
	var from_network: String = String(Network.get_character_name(sender_id)).strip_edges()
	if not (from_network in UNKNOWN_SPEAKER_NAMES):
		return from_network
	var peer_name: String = String(Network.get_peer_name(sender_id)).strip_edges()
	if not (peer_name in UNKNOWN_SPEAKER_NAMES):
		return peer_name
	var chosen_character: Dictionary = Global.get_current_character() if Global else {}
	var chosen: String = String(chosen_character.get("name", "")).strip_edges()
	if not chosen.is_empty():
		return chosen
	var external: String = external_sender_display()
	if not external.is_empty():
		return external
	return "Participant"


static func setup_player_info(owner: Node) -> void:
	var player_char: Dictionary = Global.get_current_character() if Global else {}
	var character_label: Label = owner.get("character_label") as Label
	var session_type_id: String = Global.current_session_type if Global else ""
	character_label.text = FacilitatorSessionSetupScript.character_label_text(
		session_type_id,
		player_char,
		external_sender_display()
	)
	apply_session_type_chrome(owner)
	apply_header_banner(owner, player_char)


static func apply_session_type_chrome(owner: Node) -> void:
	var session_type_id: String = Global.current_session_type if Global else ""
	var is_workshop: bool = session_type_id == "workshop_catalyst"
	var title_label: Label = owner.get_node_or_null("%SessionTypeLabel_1") as Label
	var rider_label: Label = owner.get_node_or_null("%SessionTypeLabel_2") as Label
	if title_label:
		title_label.text = "Workshop Catalyst" if is_workshop else "Story Catalyst"
	if rider_label:
		rider_label.text = (
			"Brainstorming + decision dashboard"
			if is_workshop
			else "Storytelling + character immersion"
		)
	var tab_container: TabContainer = owner.find_child("TabContainer", true, false) as TabContainer
	if tab_container:
		var record_tab: Control = tab_container.get_node_or_null("Session Record") as Control
		if record_tab:
			var record_idx: int = record_tab.get_index()
			tab_container.set_tab_hidden(record_idx, not is_workshop)
	apply_hamburger_panel_style(owner)


static func apply_hamburger_panel_style(owner: Node) -> void:
	var hamburger_panel: PanelContainer = owner.get("hamburger_settings_panel") as PanelContainer
	if not is_instance_valid(hamburger_panel):
		return
	var is_dark_mode: bool = ThemeManager != null and ThemeManager.is_dark()
	var panel_style := StyleBoxFlat.new()
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_bottom = 12.0
	# Light mode: fully opaque so the drawer does not wash over the session.
	if is_dark_mode:
		panel_style.bg_color = Color(0.1, 0.14, 0.2, 1)
	else:
		panel_style.bg_color = Color(0.99, 0.994, 1.0, 1)
	panel_style.corner_radius_top_left = 14
	panel_style.corner_radius_top_right = 14
	panel_style.corner_radius_bottom_right = 14
	panel_style.corner_radius_bottom_left = 14
	hamburger_panel.add_theme_stylebox_override("panel", panel_style)

static func ensure_header_banner(owner: Node) -> TextureRect:
	var header_banner_bg: TextureRect = owner.get("_header_banner_bg") as TextureRect
	if is_instance_valid(header_banner_bg):
		return header_banner_bg
	var header_vbox: Control = owner.find_child("VBoxContainer_UpperLabels", true, false) as Control
	if not is_instance_valid(header_vbox):
		return null
	var banner := TextureRect.new()
	banner.name = "HeaderBannerBg"
	banner.layout_mode = 0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate = Color(1.0, 1.0, 1.0, 0.65)
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	owner.add_child(banner)
	var main_margin: Node = owner.get_node_or_null("MarginContainer")
	if is_instance_valid(main_margin):
		owner.move_child(banner, main_margin.get_index())
	owner.set("_header_banner_bg", banner)
	if not header_vbox.is_connected("resized", Callable(owner, "_on_header_vbox_resized")):
		header_vbox.resized.connect(Callable(owner, "_on_header_vbox_resized"))
	owner.call_deferred("_fit_header_banner")
	return banner

static func fit_header_banner(owner: Node) -> void:
	var header_banner_bg: TextureRect = owner.get("_header_banner_bg") as TextureRect
	if not is_instance_valid(header_banner_bg):
		return
	var header_vbox: Control = owner.find_child("VBoxContainer_UpperLabels", true, false) as Control
	if not is_instance_valid(header_vbox) or not header_vbox.is_visible_in_tree():
		header_banner_bg.visible = false
		return
	var new_size: Vector2 = header_vbox.size
	# Wait for layout; do not abandon fit when the header is tall (UI scale /
	# LabelHeader). Skipping left the TextureRect at size 0 → "banner gone".
	if new_size.x < 10.0 or new_size.y < 5.0:
		# Workshop layout passes can briefly zero the header; retry once.
		if not bool(owner.get_meta("_header_banner_fit_retry", false)):
			owner.set_meta("_header_banner_fit_retry", true)
			owner.call_deferred("_fit_header_banner")
		return
	owner.set_meta("_header_banner_fit_retry", false)
	var top_sep_h: float = 15.0
	var bot_sep_h: float = 15.0
	var top_sep: Control = header_vbox.find_child("HSeparator", false, false) as Control
	var bot_sep: Control = header_vbox.find_child("HSeparator2", false, false) as Control
	if is_instance_valid(top_sep) and top_sep.size.y > 1.0:
		top_sep_h = top_sep.size.y
	if is_instance_valid(bot_sep) and bot_sep.size.y > 1.0:
		bot_sep_h = bot_sep.size.y
	var banner_h: float = maxf(new_size.y - top_sep_h - bot_sep_h, 20.0)
	banner_h = minf(banner_h, 220.0)
	var owner_control: Control = owner as Control
	if is_instance_valid(owner_control):
		header_banner_bg.position = (
			header_vbox.global_position
			- owner_control.global_position
			+ Vector2(0.0, top_sep_h)
		)
	else:
		header_banner_bg.global_position = (
			header_vbox.global_position + Vector2(0.0, top_sep_h)
		)
	header_banner_bg.size = Vector2(new_size.x, banner_h)
	header_banner_bg.visible = true
	header_banner_bg.z_index = -1

static func apply_header_banner(owner: Node, player_char: Dictionary) -> void:
	var banner: TextureRect = ensure_header_banner(owner)
	if not is_instance_valid(banner):
		return
	var char_name: String = str(player_char.get("name", ""))
	var bg_idx: int = int(player_char.get("portrait_bg_index", stable_index_from_name(char_name, PORTRAIT_BG_TEXTURES.size())))
	bg_idx = bg_idx % PORTRAIT_BG_TEXTURES.size()
	var tex: Texture2D = PORTRAIT_BG_TEXTURES[bg_idx] as Texture2D
	if tex:
		banner.texture = tex
		banner.visible = true
	var is_dark: bool = ThemeManager.is_dark() if ThemeManager else true
	banner.modulate = Color(1.0, 1.0, 1.0, 0.82) if is_dark else Color(1.0, 1.0, 1.0, 0.65)
	owner.call_deferred("_fit_header_banner")

static func stable_index_from_name(speaker_name: String, modulo: int) -> int:
	if modulo <= 0:
		return 0
	var total := 0
	for i in range(speaker_name.length()):
		total += int(speaker_name.unicode_at(i))
	return int(total % modulo)

static func enable_voice_for_scenario_characters(owner: Node, current_scenario: Dictionary) -> void:
	if not owner.has_node("VoiceBridge"):
		return
	var voice_bridge = owner.get_node("VoiceBridge")
	if current_scenario.is_empty():
		return
	if not voice_bridge.has_method("set_voice_enabled_for_character"):
		return
	var speaker_names: Array = GameSessionNarrativeUtils.collect_declared_speaker_names(current_scenario)
	for speaker_name in speaker_names:
		voice_bridge.set_voice_enabled_for_character(speaker_name, true)

static func handle_scene_switch_request(owner: Node, target_scene: String) -> void:
	if is_voicebridge_playing(owner):
		owner.call("_show_scene_switch_dialog", target_scene)
	else:
		perform_scene_switch(target_scene)

static func wait_for_line_then_switch(owner: Node, target_scene: String) -> void:
	owner.set("_pending_scene_switch_target", target_scene)
	owner.call("_maybe_execute_pending_scene_switch")

static func maybe_execute_pending_scene_switch(owner: Node) -> void:
	var pending_target: String = str(owner.get("_pending_scene_switch_target"))
	if pending_target.is_empty():
		return
	if is_voicebridge_playing(owner):
		return
	owner.set("_pending_scene_switch_target", "")
	perform_scene_switch(pending_target)
	owner.call("_maybe_execute_pending_emitter_change")
	owner.call("_maybe_execute_pending_back")

static func skip_current_tts_and_switch(owner: Node, target_scene: String) -> void:
	owner.call("_on_stop_tts_pressed")
	perform_scene_switch(target_scene)

static func handle_tts_emitter_request(owner: Node, target_emitter: String) -> void:
	if not Global:
		return
	if Global.get_tts_emitter() == target_emitter:
		return
	if is_voicebridge_playing(owner):
		owner.call("_show_emitter_switch_dialog", target_emitter)
	else:
		apply_tts_emitter_change(owner, target_emitter)

static func wait_for_line_then_apply_emitter(owner: Node, target_emitter: String) -> void:
	owner.set("_pending_emitter_target", target_emitter)
	owner.call("_maybe_execute_pending_emitter_change")

static func maybe_execute_pending_emitter_change(owner: Node) -> void:
	var pending_target: String = str(owner.get("_pending_emitter_target"))
	if pending_target.is_empty():
		return
	if is_voicebridge_playing(owner):
		return
	owner.set("_pending_emitter_target", "")
	apply_tts_emitter_change(owner, pending_target)

static func skip_current_tts_and_apply_emitter(owner: Node, target_emitter: String) -> void:
	owner.call("_on_stop_tts_pressed")
	apply_tts_emitter_change(owner, target_emitter)

static func apply_tts_emitter_change(owner: Node, target_emitter: String) -> void:
	if not Global:
		return
	Global.set_tts_emitter(target_emitter)
	owner.call("_update_tts_transport_styles")

static func perform_scene_switch(target_scene: String) -> void:
	match target_scene:
		"story_stage":
			print("GameSession: Switching to visual mode")
			SceneTransition.switch_to_story_stage()
		"story_log":
			print("GameSession: Switching to story log")
			SceneTransition.switch_to_story_log()
		_:
			print("GameSession: Switching to visual mode")
			SceneTransition.switch_to_story_stage()

static func is_voicebridge_playing(owner: Node) -> bool:
	if owner.has_node("VoiceBridge"):
		var voice_bridge = owner.get_node("VoiceBridge")
		if voice_bridge and voice_bridge.currently_speaking_character != "":
			return true
	return false

static func get_active_speaker_name(owner: Node) -> String:
	if owner.has_node("VoiceBridge"):
		var voice_bridge = owner.get_node("VoiceBridge")
		if voice_bridge:
			return voice_bridge.currently_speaking_character
	return ""

static func connect_voicebridge_scene_switch_signals(owner: Node) -> void:
	if not owner.has_node("VoiceBridge"):
		return
	var voice_bridge = owner.get_node("VoiceBridge")
	var callback := Callable(owner, "_on_voicebridge_scene_switch_finished")
	if voice_bridge and not voice_bridge.character_speech_finished.is_connected(callback):
		voice_bridge.character_speech_finished.connect(callback)

static func pause_tts(owner: Node) -> void:
	if owner.has_node("VoiceBridge"):
		var voice_bridge = owner.get_node("VoiceBridge")
		if voice_bridge and voice_bridge.has_method("pause_queue"):
			voice_bridge.pause_queue()

static func resume_tts(owner: Node) -> void:
	if owner.has_node("VoiceBridge"):
		var voice_bridge = owner.get_node("VoiceBridge")
		if voice_bridge and voice_bridge.has_method("resume_queue"):
			voice_bridge.resume_queue()

static func stop_tts(owner: Node) -> void:
	if owner.has_node("VoiceBridge"):
		var voice_bridge = owner.get_node("VoiceBridge")
		if voice_bridge and voice_bridge.has_method("stop_all_speech"):
			voice_bridge.stop_all_speech()
	if VoiceService and VoiceService.has_method("cancel_current_request"):
		VoiceService.cancel_current_request(true)
	if VoiceService and VoiceService.has_method("clear_all_synthesis"):
		VoiceService.clear_all_synthesis()

static func update_provider_label(owner: Node) -> void:
	var model_selector: OptionButton = owner.get("_model_selector") as OptionButton
	if not model_selector:
		return
	var model_id: String = model_selector.get_item_text(model_selector.selected)
	var plugin_manager = Global.get_plugin_manager() if Global and Global.has_method("get_plugin_manager") else null
	var ai_manager = plugin_manager.get_ai_model_manager() if plugin_manager and plugin_manager.has_method("get_ai_model_manager") else null
	var provider_id := ""
	if ai_manager and ai_manager.has_method("get_provider_for_model"):
		provider_id = String(ai_manager.get_provider_for_model(model_id))
	var provider_label: Label = owner.get("_provider_label") as Label
	if provider_label:
		provider_label.text = "Provider: " + (provider_id if provider_id != "" else "unknown")
	var model_status_label: Label = owner.get("model_status_label") as Label
	if is_instance_valid(model_status_label):
		var cfg: Dictionary = RuntimeConfig.load_config()
		var voice_cfg: Dictionary = cfg.get("voice", {})
		var voice_mode_id: String = str(voice_cfg.get("provider_mode", "?"))
		model_status_label.text = "Model: %s  |  Voice: %s" % [model_id, voice_mode_id]

static func on_model_selected_scensyn(owner: Node) -> void:
	var model_selector: OptionButton = owner.get("_model_selector") as OptionButton
	var model_id: String = model_selector.get_item_text(model_selector.selected)
	var plugin_manager = Global.get_plugin_manager() if Global and Global.has_method("get_plugin_manager") else null
	var ai_manager = plugin_manager.get_ai_model_manager() if plugin_manager and plugin_manager.has_method("get_ai_model_manager") else null
	if ai_manager and ai_manager.has_method("set_current_model"):
		var res = ai_manager.set_current_model(model_id)
		if res is Dictionary and res.get("success", false):
			owner.call("_update_provider_label")
		else:
			push_warning("GameSession: Failed to set model '" + model_id + "': " + String(res.get("error", "unknown")))

static func on_api_key_save_pressed(owner: Node) -> void:
	var api_key_edit: LineEdit = owner.get("_api_key_edit") as LineEdit
	var key_text: String = String(api_key_edit.text).strip_edges()
	if key_text == "":
		return
	var model_selector: OptionButton = owner.get("_model_selector") as OptionButton
	var model_id: String = model_selector.get_item_text(model_selector.selected)
	var plugin_manager = Global.get_plugin_manager() if Global and Global.has_method("get_plugin_manager") else null
	var ai_manager = plugin_manager.get_ai_model_manager() if plugin_manager and plugin_manager.has_method("get_ai_model_manager") else null
	if not ai_manager:
		return
	var provider_id: String = String(ai_manager.get_provider_for_model(model_id)) if ai_manager.has_method("get_provider_for_model") else ""
	if provider_id != "" and ai_manager.has_method("set_api_key"):
		var res = ai_manager.set_api_key(provider_id, key_text)
		if not (res is Dictionary and res.get("success", false)):
			push_warning("GameSession: Failed to save API key for provider '" + provider_id + "'")

static func on_temp_override_toggled(owner: Node, enabled: bool) -> void:
	owner.set("_temp_override_enabled", enabled)
	var temp_model_selector: OptionButton = owner.get("_temp_model_selector") as OptionButton
	if temp_model_selector:
		temp_model_selector.disabled = not enabled

static func on_temp_model_selected(owner: Node) -> void:
	var temp_model_selector: OptionButton = owner.get("_temp_model_selector") as OptionButton
	owner.set("_temp_model_name", temp_model_selector.get_item_text(temp_model_selector.selected))

static func review_story_log(owner: Node) -> void:
	var hamburger_settings_panel: Control = owner.get("hamburger_settings_panel") as Control
	if hamburger_settings_panel:
		hamburger_settings_panel.visible = false
	var story_log_system: Node = owner.get("story_log_system") as Node
	if not is_instance_valid(story_log_system):
		return
	if story_log_system.has_method("save_story_log"):
		story_log_system.call("save_story_log")
	var html_path := ""
	if story_log_system.has_method("get_current_html_story_log_path"):
		html_path = str(story_log_system.call("get_current_html_story_log_path"))
	if html_path != "" and FileAccess.file_exists(html_path):
		OS.shell_open(html_path)
		return
	var markdown_path := ""
	if story_log_system.has_method("get_current_markdown_story_log_path"):
		markdown_path = str(story_log_system.call("get_current_markdown_story_log_path"))
	if markdown_path != "" and FileAccess.file_exists(markdown_path):
		OS.shell_open(markdown_path)
		return
	owner.call("_on_open_session_logs_pressed")

static func open_session_logs(owner: Node) -> void:
	var logs_path: String = RuntimeConfig.get_scensyn_story_log_dir()
	if not DirAccess.dir_exists_absolute(logs_path):
		DirAccess.make_dir_recursive_absolute(logs_path)
	OS.shell_open(logs_path)
	var hamburger_settings_panel: Control = owner.get("hamburger_settings_panel") as Control
	if hamburger_settings_panel:
		hamburger_settings_panel.visible = false
