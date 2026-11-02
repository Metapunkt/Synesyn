# game_session.gd
extends Node

const MicrophoneRecorder = preload("res://addons/syntree_voice/scripts/services/microphone_recorder.gd")
const NarrationFilterScript = preload("res://ScenSyn/scripts/utils/narration_filter.gd")
const GameSessionStartupUtilsScript = preload("res://ScenSyn/scripts/core/game_session_startup_utils.gd")
const GameSessionStoryLogUtilsScript = preload("res://ScenSyn/scripts/core/game_session_storylog_utils.gd")
const GameSessionAiFlowUtilsScript = preload("res://ScenSyn/scripts/core/game_session_ai_flow_utils.gd")
const GameSessionNarrativeUtilsScript = preload("res://ScenSyn/scripts/core/game_session_narrative_utils.gd")
const GameSessionUiUtilsScript = preload("res://ScenSyn/scripts/core/game_session_ui_utils.gd")
const GameSessionReportUtilsScript = preload("res://ScenSyn/scripts/core/game_session_report_utils.gd")

var game_flow_manager
var conversation_manager
var current_scenario
var player_character
var last_displayed_message_index = 0
var sustainability_tracker
var include_syntree_context: bool = false
var use_clean_game_thread: bool = false
var use_enhanced_narrative_rules: bool = true  # Phase 1: Principle-based rules
var use_theme_creative_missions: bool = true   # Phase 2: Phase-specific missions
var use_dynamic_continuation: bool = true      # Phase 3: Pattern-breaking prompts
var use_pattern_breaking: bool = true          # Phase 3: Anti-repetition system
var recent_response_patterns = {
	"openings": [],      # Last 3 response openings (first 20 chars)
	"emotions": [],      # Last 3 dominant emotions detected
	"structures": [],    # Last 3 dialogue structures
	"narrator_count": 0  # Narrator uses in current phase
}

var filter_stats = {
	"narrator_lines_removed": 0,
	"hijacking_detected": 0,
	"player_dialogue_filtered": 0,
	"quality_improvements_applied": 0,
	"fallbacks_triggered": 0,
	"total_responses_processed": 0
}

var messages = []
var current_turn = 0
var is_host = false
var story_state : Dictionary
var metaprompt_manager  # BaseMetapromptManager - untyped for dynamic dispatch
var is_multiplayer: bool = false
var scroll_tween: Tween

var _hub = null
var _session_id: String = ""
var continuity_service = null
var vis_story_service = null
var render_purpose_service = null
var verse_reading_service = null
var session_digest_service = null
var _last_vis_story_export_packet_id: String = ""

var feedback_manager: FeedbackManager
var analytics_manager: AnalyticsManager

@onready var input_field = %InputField
@onready var send_button = %SendButton
@onready var chat_log = %ChatLog
@onready var chat_scroll = %ChatLogScrollContainer
@onready var scroll_indicator = %ScrollIndicator
@onready var scenario_title_label = %ScenarioTitleLabel
@onready var objective_label = %ScenarioObjectiveLabel
@onready var scenario_pop_up = %ScenarioObjectivePopup
@onready var cancel_scen_popup_btn = %CancelPopupButton
@onready var character_label = %CharacterLabel
@onready var progress_bar: TextureProgressBar = %ProgressBar
@onready var story_log_system = %StoryLogSystem
@onready var scenario_objective_btn = %ScenarioObjectiveBtn
@onready var end_session_button = %EndSessionButton
@onready var sustainability_meter_container = %SustainabilityMeterContainer
@onready var sustainability_meter = %SustainabilityMeter
@onready var feedback_ui = %FeedbackUI
@onready var show_feedback_btn = %ShowFeedbackBtn
@onready var show_sustainability_btn = %ShowSustainabilityMeterBtn
@onready var hamburger_menu_btn = %HamburgerMenuBtn
@onready var hamburger_settings_panel = %HamburgerSettingsPanel
@onready var model_status_label: Label = get_node_or_null("%ModelStatusLabel") as Label
var _header_banner_bg: TextureRect = null
@onready var switch_to_visual_mode_btn = %SwitchToVisualModeBtn
@onready var dual_window_toggle = %DualWindowToggle
@onready var syntree_context_toggle: CheckButton = get_node_or_null("%SyntreeContextToggle")
@onready var save_recordings_toggle: CheckButton = get_node_or_null("%SaveRecordingsToggle")
@onready var services_button_hamburger: Button = get_node_or_null("%ServicesButton")
@onready var back_button_hamburger: Button = get_node_or_null("%BackButton")
@onready var story_progress_label = %StoryProgressLabel
@onready var story_progress_bar = %StoryProgressBar
@onready var about_tab_label: RichTextLabel = get_node_or_null("%AboutTabLabel")
@onready var how_to_tab_label: RichTextLabel = get_node_or_null("%HowToTabLabel")
@onready var workshop_session_record_panel: Control = get_node_or_null("%WorkshopSessionRecordPanel") as Control
@onready var record_button: Button = get_node_or_null("%RecordButton")
@onready var auto_send_voice_button: CheckButton = get_node_or_null("%AutoSendVoice")
@onready var auto_player_input_toggle: CheckButton = get_node_or_null("%AutoPlayerInput")
const TTS_ACTIVE_COLOR := Color(0.85, 1.0, 0.85, 1.0)
const TTS_INACTIVE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
var _pause_tts_button: Button
var _resume_tts_button: Button
var _skip_tts_button: Button
var _pending_scene_switch_target: String = ""
var _pending_emitter_target: String = ""
var _pending_back_to_landing: bool = false
var _microphone_recorder: Node = null
@onready var debug_ai_model_btn = get_node_or_null("%DebugAIModelBtn")

var _progress_tween: Tween = null
var _completion_tween: Tween = null

var phase_display_label: Label = null
var _tts_toggle_story_log: CheckButton = null
var _settings_vbox: VBoxContainer = null
var _is_loading_story_log: bool = false
var _load_log_dialog: FileDialog = null
var dialogue_processor: DialogueProcessingSystem
var ai_model_manager: AIModelManagementSystem
var conversation_system # ConversationManagementSystem

# NEW: Advanced personality modeling system
var personality_system: CharacterPersonalitySystem

# NEW: Real-time quality monitoring system
var quality_system: QualityMonitoringSystem

# NEW: Adaptive response system
var adaptive_system: AdaptiveResponseSystem

# NEW: Phase management system
var phase_system: PhaseManagementSystem

# NEW: Sustainability integration system
var sustainability_system: SustainabilityIntegrationSystem

# NEW: Session reporting system
var reporting_system: SessionReportingSystem

# Auto player input helper
var player_auto_input: PlayerAutoInput
var _suppress_auto_player_toggle_signal := false
var _suppress_syntree_context_toggle_signal := false
var _suppress_save_recordings_toggle_signal := false
var _save_recordings_enabled: bool = false
var _consent_update_inflight: bool = false

# Helper: normalize loaded text for deduplication
func _normalize_loaded_text(t: String) -> String:
	var s := String(t)
	var bbcode_re := RegEx.new()
	bbcode_re.compile("\\[/?[^\\]]*\\]")
	s = bbcode_re.sub(s, "", true)
	s = s.replace("**", "")
	s = s.strip_edges()
	return s

# Helper: minimal regex escaping for literal names in patterns
func _regex_escape(text: String) -> String:
	var escaped := String(text)
	var specials := ["\\", ".", "+", "*", "?", "^", "$", "(", ")", "[", "]", "{", "}", "|"]
	for ch in specials:
		escaped = escaped.replace(ch, "\\" + ch)
	return escaped

const _LOGO_DARK := preload("res://ScenSyn/scene_images/ScenSyn_logo_2.svg")
const _LOGO_WHITE := preload("res://ScenSyn/scene_images/ScenSyn_logo_2_white.svg")
const _BG_DARK := Color(0.039, 0.055, 0.078, 1)  # navy back plate (not purple)
const _BG_LIGHT := Color(0.953, 0.965, 0.984, 1)

@onready var _scene_logo: TextureRect = %ScenSynLogo
@onready var _bg_rect: ColorRect = %ColorRect
@onready var _theme_toggle_btn: Button = %ThemeToggleButton

func _update_theme_visuals() -> void:
	if not ThemeManager:
		return
	var is_dark_mode: bool = ThemeManager.is_dark()
	if _scene_logo:
		_scene_logo.texture = _LOGO_WHITE if is_dark_mode else _LOGO_DARK
	if _bg_rect:
		var semantic_base: Color = ThemeManager.get_semantic_color("base")
		if semantic_base != Color.MAGENTA:
			_bg_rect.color = semantic_base
		else:
			_bg_rect.color = _BG_DARK if is_dark_mode else _BG_LIGHT

	if is_instance_valid(_theme_toggle_btn):
		_theme_toggle_btn.text = "Switch to Light Mode" if is_dark_mode else "Switch to Dark Mode"
	# In dark mode: override header label colors to crisp white for maximum contrast
	# against the tinted portrait banner. In light mode: remove overrides so the
	# theme's dark-on-light palette applies normally.
	if is_instance_valid(scenario_title_label):
		if is_dark_mode:
			scenario_title_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			scenario_title_label.remove_theme_color_override("font_color")
	if is_instance_valid(character_label):
		if is_dark_mode:
			character_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.88))
		else:
			character_label.remove_theme_color_override("font_color")
	GameSessionUiUtilsScript.apply_hamburger_panel_style(self)
	_apply_header_banner(Global.get_current_character() if Global else {})

func _ready():
	# Theme-aware logo and background
	_update_theme_visuals()
	if ThemeManager:
		ThemeManager.mode_changed.connect(func(_m): _update_theme_visuals())
	if is_instance_valid(_theme_toggle_btn):
		_theme_toggle_btn.pressed.connect(func(): if ThemeManager: ThemeManager.toggle_mode())
	# Apply header banner after layout has settled
	call_deferred("_apply_header_banner",
		Global.get_current_character() if Global else {})
	# Wire hamburger menu navigation buttons
	if services_button_hamburger:
		services_button_hamburger.pressed.connect(_toggle_services_panel)
	if back_button_hamburger:
		back_button_hamburger.pressed.connect(_on_back_to_landing)
	var review_log_btn := get_node_or_null("%ReviewStoryLogButton") as Button
	if review_log_btn:
		review_log_btn.pressed.connect(_on_review_story_log_pressed)
	var export_session_btn := get_node_or_null("%ExportSessionButton") as Button
	if export_session_btn:
		export_session_btn.pressed.connect(_on_open_session_logs_pressed)
	# Temporary sessions spawned by SceneTransitionManager for loading story logs
	# should not run the full startup coroutine (it yields/awaits and can race cleanup).
	if get("_is_temp_story_log_loader") == true:
		print("GameSession: Temp story log loader session - skipping full startup")
		return

	await GameSessionStartupUtilsScript.ready(self)

func _exit_tree():
	if get("_is_temp_story_log_loader") == true:
		return
	if session_digest_service and continuity_service:
		var scenario: Dictionary = current_scenario if typeof(current_scenario) == TYPE_DICTIONARY else {}
		if scenario.is_empty() and game_flow_manager and game_flow_manager.has_method("get_current_scenario"):
			scenario = game_flow_manager.get_current_scenario()
		if not scenario.is_empty():
			session_digest_service.write_digest_sync(scenario, continuity_service)

# Handle text input submission (missing function)
func _on_character_input_text_submitted(text: String):
	# Delegate to the existing send handler
	if text.strip_edges() != "":
		input_field.text = text
		_on_send_pressed()

# Initialize Collection systems for the active Session Type.
func _initialize_session_type_systems():
	print("GameSession: === _initialize_session_type_systems() CALLED ===")
	var session_type_id: String = Global.current_session_type
	var collection_id: String = Global.current_collection_id
	print("GameSession: Session Type/Collection: %s/%s" % [session_type_id, collection_id])
	GameSessionUiUtilsScript.apply_session_type_chrome(self)
	match session_type_id:
		"workshop_catalyst":
			_initialize_workshop_catalyst_system()
		"story_catalyst":
			match collection_id:
				"sustainability": _initialize_sustainability_system()
				"cultural_narratives": _initialize_cultural_system()
				"open_play": _initialize_open_play_system()
				_: push_error("GameSession: Unknown Story Catalyst Collection: " + collection_id)
		_:
			push_error("GameSession: Unknown Session Type: " + session_type_id)

func _initialize_workshop_catalyst_system():
	print("GameSession: Workshop Catalyst Session Type initialized")
	# Keep this Session Type lightweight: do NOT instantiate Story Catalyst systems.
	# Controller handles direct facilitation responses and settings UI.
	var controller_script = load("res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller.gd")
	if not controller_script:
		push_warning("GameSession: Workshop catalyst controller script not found")
		return
	var controller = controller_script.new()
	controller.name = "WorkshopCatalystController"
	add_child(controller)
	# Add minimal controls into hamburger panel if available
	if hamburger_settings_panel:
		var vbox := _ensure_settings_vbox()
		if vbox and controller.has_method("initialize"):
			controller.initialize(vbox, workshop_session_record_panel)

# Initialize sustainability system (theme-specific)
func _initialize_sustainability_system():
	GameSessionNarrativeUtilsScript.initialize_sustainability_system(self)

# Initialize cultural narratives system (placeholder for future implementation)
func _initialize_cultural_system():
	GameSessionNarrativeUtilsScript.initialize_cultural_system(self)

func _initialize_open_play_system():
	GameSessionNarrativeUtilsScript.initialize_open_play_system(self)

func _on_scenario_objective_btn_toggled(button_pressed):
	if button_pressed:
		scenario_pop_up.show()
	#	objective_label.text = "Hello World"
	else:
		scenario_pop_up.hide()

func _on_cancel_popup_button_pressed():
	scenario_pop_up.hide()

func _on_switch_to_visual_mode_pressed():
	print("GameSession: Switching to visual mode")
	_handle_scene_switch_request("story_stage")

func _on_hamburger_menu_pressed():
	print("GameSession: Hamburger menu pressed")
	var services = get_tree().root.find_child("ServicesPanel", true, false)
	if services and services.has_method("is_panel_open") and services.is_panel_open():
		services.close_panel()
		if hamburger_settings_panel:
			hamburger_settings_panel.visible = false
		return
	if hamburger_settings_panel:
		hamburger_settings_panel.visible = not hamburger_settings_panel.visible
		if hamburger_settings_panel.visible:
			# Layout should be editor-driven. The hamburger menu is now a scene node
			# (including a ScrollContainer) so you can tweak sizing in the inspector.
			_ensure_ai_model_controls()
			# Keep a lightweight clamp to viewport height, but don't shrink the panel below its editor size.
			call_deferred("_resize_hamburger_panel_to_contents")

func _toggle_services_panel():
	# Find Services panel in the scene tree (globally accessible)
	var services = get_tree().root.find_child("ServicesPanel", true, false)
	if services:
		if services.has_method("is_panel_open") and services.is_panel_open():
			if hamburger_settings_panel:
				hamburger_settings_panel.visible = false
			return
		if services.has_method("open_panel"):
			services.open_panel()
		else:
			services.visible = true
		if hamburger_settings_panel:
			hamburger_settings_panel.visible = false

func _on_back_to_landing():
	var services = get_tree().root.find_child("ServicesPanel", true, false)
	if services and services.has_method("is_panel_open") and services.is_panel_open():
		services.close_panel()
	# Check if TTS is playing and show dialog like scene switch
	if _is_voicebridge_playing():
		_show_back_to_landing_dialog()
	else:
		_perform_back_to_landing()

func _show_back_to_landing_dialog():
	var dialog := ConfirmationDialog.new()
	dialog.title = "Audio Playing"
	dialog.dialog_text = "A character is speaking. Stop audio and go back?"
	dialog.ok_button_text = "Stop & Go Back"
	dialog.cancel_button_text = "Wait for Line"
	add_child(dialog)
	dialog.confirmed.connect(func(): 
		_skip_current_tts_and_go_back()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): 
		_wait_for_line_then_go_back()
		dialog.queue_free()
	)
	dialog.popup_centered()

func _wait_for_line_then_go_back():
	_pending_back_to_landing = true
	_maybe_execute_pending_back()

func _maybe_execute_pending_back():
	if not _pending_back_to_landing:
		return
	if _is_voicebridge_playing():
		return
	_pending_back_to_landing = false
	_perform_back_to_landing()

func _skip_current_tts_and_go_back():
	_on_stop_tts_pressed()
	_perform_back_to_landing()

func _perform_back_to_landing():
	# Return to ScenSyn landing scene
	get_tree().change_scene_to_file("res://ScenSyn/scenes/main_menu.tscn")

func _on_dual_window_toggled(button_pressed: bool):
	print("GameSession: Dual window mode toggled: ", button_pressed)
	if button_pressed:
		DualWindowManager.enable_dual_window_mode()
	else:
		DualWindowManager.disable_dual_window_mode()
	# Ensure Story Log owns the emitter when dual window is enabled from this scene.
	if button_pressed and Global and Global.get_tts_emitter() != "story_log":
		_handle_tts_emitter_request("story_log")
	_update_dual_window_toggle_state()

func _on_dual_window_mode_changed(_new_mode):
	_update_dual_window_toggle_state()

func _update_dual_window_toggle_state():
	if not dual_window_toggle:
		return
	var tooltip_text := "Dual Window Mode must be enabled from Story Stage."
	dual_window_toggle.tooltip_text = tooltip_text
	var dual_manager_available := typeof(DualWindowManager) != TYPE_NIL
	var is_dual_active := dual_manager_available and DualWindowManager.is_dual_window_mode()
	dual_window_toggle.disabled = not is_dual_active
	if dual_window_toggle.has_method("set_pressed_no_signal"):
		dual_window_toggle.set_pressed_no_signal(is_dual_active)
	else:
		dual_window_toggle.button_pressed = is_dual_active

func _ensure_settings_vbox() -> VBoxContainer:
	return GameSessionNarrativeUtilsScript.ensure_settings_vbox(self)

func _on_tts_toggle_story_log(pressed: bool):
	if not Global:
		return
	if pressed:
		_handle_tts_emitter_request("story_log")
	else:
		if Global.get_tts_emitter() == "story_log":
			_handle_tts_emitter_request("story_stage")
	# Reflect current emitter in the toggle state for robustness
	if _tts_toggle_story_log:
		_tts_toggle_story_log.button_pressed = (Global and Global.get_tts_emitter() == "story_log")

func _on_global_tts_emitter_changed(new_emitter):
	if _tts_toggle_story_log:
		_tts_toggle_story_log.button_pressed = (new_emitter == "story_log")
	_update_tts_transport_styles()

func _on_skip_welcome_toggled(pressed: bool):
	GameSessionNarrativeUtilsScript.on_skip_welcome_toggled(self, pressed)

func _on_record_button_toggled(button_pressed: bool):
	await GameSessionNarrativeUtilsScript.on_record_button_toggled(self, button_pressed)

func _on_game_session_transcription_completed(text: String, error: String):
	GameSessionNarrativeUtilsScript.on_game_session_transcription_completed(self, text, error)

func _set_record_button_state(state: String):
	GameSessionNarrativeUtilsScript.set_record_button_state(self, state)
func _update_tts_transport_styles():
	var is_active := Global and Global.get_tts_emitter() == "story_log"
	_apply_tts_button_style(_pause_tts_button, is_active)
	_apply_tts_button_style(_resume_tts_button, is_active)
	_apply_tts_button_style(_skip_tts_button, is_active)

func _connect_transcription_signals():
	GameSessionNarrativeUtilsScript.connect_transcription_signals(self)

func _configure_auto_player_input_toggle() -> void:
	if not auto_player_input_toggle:
		return
	if not auto_player_input_toggle.toggled.is_connected(_on_auto_player_input_toggled):
		auto_player_input_toggle.toggled.connect(_on_auto_player_input_toggled)
	if player_auto_input:
		if not player_auto_input.auto_input_changed.is_connected(_on_global_auto_player_state_changed):
			player_auto_input.auto_input_changed.connect(_on_global_auto_player_state_changed)
		if not player_auto_input.configuration_changed.is_connected(_on_auto_player_config_changed):
			player_auto_input.configuration_changed.connect(_on_auto_player_config_changed)
	_refresh_auto_player_input_toggle()

func _refresh_auto_player_input_toggle(forced_value = null) -> void:
	if not auto_player_input_toggle:
		return
	var available := player_auto_input and player_auto_input.is_available()
	auto_player_input_toggle.disabled = not available
	if available:
		var desired: bool = forced_value if forced_value is bool else player_auto_input.is_enabled()
		_suppress_auto_player_toggle_signal = true
		auto_player_input_toggle.button_pressed = desired
		_suppress_auto_player_toggle_signal = false
		auto_player_input_toggle.tooltip_text = "Use external input to auto-generate the player's line. Disable to type manually."
	else:
		_suppress_auto_player_toggle_signal = true
		auto_player_input_toggle.button_pressed = false
		_suppress_auto_player_toggle_signal = false
		auto_player_input_toggle.tooltip_text = "Auto player input is not configured for this scenario."
	_apply_auto_player_input_ui_state(available and auto_player_input_toggle.button_pressed)

func _apply_auto_player_input_ui_state(auto_enabled: bool) -> void:
	if input_field:
		input_field.editable = not auto_enabled
		input_field.placeholder_text = "Auto player input active — driven by external input." if auto_enabled else "Enter your message..."

func _on_auto_player_input_toggled(toggled_on: bool) -> void:
	if _suppress_auto_player_toggle_signal:
		return
	if not player_auto_input or not player_auto_input.is_available():
		_suppress_auto_player_toggle_signal = true
		auto_player_input_toggle.button_pressed = false
		_suppress_auto_player_toggle_signal = false
		return
	player_auto_input.set_enabled(toggled_on)
	_apply_auto_player_input_ui_state(toggled_on)

func _on_global_auto_player_state_changed(enabled: bool) -> void:
	_refresh_auto_player_input_toggle(enabled)

func _on_auto_player_config_changed(_available: bool) -> void:
	_refresh_auto_player_input_toggle()

func _on_voice_service_ready_for_transcription():
	if typeof(VoiceService) == TYPE_NIL:
		return
	if VoiceService.has_signal("voice_service_ready") and VoiceService.voice_service_ready.is_connected(_on_voice_service_ready_for_transcription):
		VoiceService.voice_service_ready.disconnect(_on_voice_service_ready_for_transcription)
	_connect_transcription_signals()

func _apply_tts_button_style(button: Button, is_active: bool):
	if not button:
		return
	button.modulate = TTS_ACTIVE_COLOR if is_active else TTS_INACTIVE_COLOR

func _handle_scene_switch_request(target_scene: String):
	GameSessionUiUtilsScript.handle_scene_switch_request(self, target_scene)

func _show_scene_switch_dialog(target_scene: String):
	GameSessionNarrativeUtilsScript.show_scene_switch_dialog(self, target_scene)

func _wait_for_line_then_switch(target_scene: String):
	GameSessionUiUtilsScript.wait_for_line_then_switch(self, target_scene)

func _maybe_execute_pending_scene_switch():
	GameSessionUiUtilsScript.maybe_execute_pending_scene_switch(self)

func _skip_current_tts_and_switch(target_scene: String):
	GameSessionUiUtilsScript.skip_current_tts_and_switch(self, target_scene)

func _handle_tts_emitter_request(target_emitter: String):
	GameSessionUiUtilsScript.handle_tts_emitter_request(self, target_emitter)

func _show_emitter_switch_dialog(target_emitter: String):
	GameSessionNarrativeUtilsScript.show_emitter_switch_dialog(self, target_emitter)

func _wait_for_line_then_apply_emitter(target_emitter: String):
	GameSessionUiUtilsScript.wait_for_line_then_apply_emitter(self, target_emitter)

func _maybe_execute_pending_emitter_change():
	GameSessionUiUtilsScript.maybe_execute_pending_emitter_change(self)

func _skip_current_tts_and_apply_emitter(target_emitter: String):
	GameSessionUiUtilsScript.skip_current_tts_and_apply_emitter(self, target_emitter)

func _apply_tts_emitter_change(target_emitter: String):
	GameSessionUiUtilsScript.apply_tts_emitter_change(self, target_emitter)

func _perform_scene_switch(target_scene: String):
	GameSessionUiUtilsScript.perform_scene_switch(target_scene)

func _is_voicebridge_playing() -> bool:
	return GameSessionUiUtilsScript.is_voicebridge_playing(self)

func _get_active_speaker_name() -> String:
	return GameSessionUiUtilsScript.get_active_speaker_name(self)

func _connect_voicebridge_scene_switch_signals():
	GameSessionUiUtilsScript.connect_voicebridge_scene_switch_signals(self)

func _on_voicebridge_scene_switch_finished(_character_name: String):
	_maybe_execute_pending_scene_switch()
	_maybe_execute_pending_emitter_change()

func _on_pause_tts_pressed():
	GameSessionUiUtilsScript.pause_tts(self)

func _on_resume_tts_pressed():
	GameSessionUiUtilsScript.resume_tts(self)

func _on_stop_tts_pressed():
	GameSessionUiUtilsScript.stop_tts(self)

func _on_load_story_log_pressed():
	GameSessionStoryLogUtilsScript.on_load_story_log_pressed(self)

func _on_new_story_log_pressed():
	GameSessionStoryLogUtilsScript.on_new_story_log_pressed(self)

func _create_new_story_log():
	GameSessionStoryLogUtilsScript.create_new_story_log(self)

func _on_story_log_file_selected(path: String):
	GameSessionStoryLogUtilsScript.on_story_log_file_selected(self, path)

func _apply_story_log_from_json(path: String):
	GameSessionStoryLogUtilsScript.apply_story_log_from_json(self, path)

func _speak_narrator_opening(text: String) -> void:
	# Speak opening narrator text once voice system is ready
	if not has_node("VoiceBridge"):
		return
	var vb = get_node("VoiceBridge")
	if vb and vb.has_method("request_character_speech"):
		# Ensure narrator is enabled for voice
		if vb.has_method("set_voice_enabled_for_character"):
			vb.set_voice_enabled_for_character("Narrator", true)
		vb.request_character_speech("Narrator", text)
		if Global:
			Global.opening_spoken_log = true

func _on_scenario_changed(_new_scenario_name: String):
	# The signal carries a name; current_scenario holds the dictionary, so it is
	# refreshed from the flow manager inside setup_scenario_display (Global sets the
	# flow manager's scenario before emitting) rather than assigned from the signal.
	_last_vis_story_export_packet_id = ""
	setup_scenario_display()
	# A switch can cross session types and leave the header naming the one this scene
	# opened in: Workshop chrome, Session Record tab and all, over a story. Only the
	# chrome goes stale, so the session type's systems are not re-initialised here.
	setup_player_info()
				
func _await_story_state_update() -> void:	
	print("Client: Waiting for story state update")
#	await Network.story_state_updated
	print("Client: Story state update received")
	
func _on_connection_succeeded():
	print("Connection to server succeeded")
	# Request initial game state from server
	Network.rpc_id(1, "request_initial_state")

func request_initial_state():
	print("Client: Requesting initial state")
	Network.request_initial_state.rpc_id(1)
#	await _await_story_state_update()
#	update_display_from_story_state()

func _on_game_ready():
	print("Client: Game ready signal received, requesting initial state")
	Network.rpc_id(1, "request_initial_state")
	
func get_server_peer_id() -> int:
	if Network.is_server():
		return multiplayer.get_unique_id()
	elif Network.is_multiplayer():
		# For clients in a multiplayer game, the server is always peer ID 1
		return 1
	else:
		# This case should never happen in a properly set up game
		print("Error: Not in a multiplayer game")
		return -1
			
func _on_message_received(message_data):
	add_message(message_data.sender_id, message_data.message)
#	display_message(message_data.sender_id, message_data.message)

func _on_send_pressed():
	GameSessionNarrativeUtilsScript.on_send_pressed(self)
						
func _on_player_input_received(sender_id: int, user_input: String):
	GameSessionAiFlowUtilsScript.on_player_input_received(self, sender_id, user_input)

func _emit_session_turn_async(character_name: String, user_input: String, turn_index: int) -> void:
	GameSessionNarrativeUtilsScript.emit_session_turn_async(self, character_name, user_input, turn_index)

# DEPRECATED: AI responses now handled by AI Character Agent
# This function is kept for reference but should not be called
func process_ai_response_deprecated(character_name: String, user_input: String):
	await GameSessionAiFlowUtilsScript.process_ai_response_deprecated(self, character_name, user_input)

# Phase evaluation now handled by PhaseManagementSystem
func _run_ai_phase_evaluation():
	if phase_system:
		phase_system.run_ai_phase_evaluation()

# FIXED: Add handler for StoryState updates
func _on_story_state_updated(_new_state: Dictionary):
	print("GameSession: _on_story_state_updated called")
	update_display_from_story_state()

func load_scenario_continuity() -> Dictionary:
	if continuity_service == null:
		return {"ok": false, "error": "continuity_service unavailable"}
	if _hub == null:
		return {"ok": false, "error": "hub client unavailable"}
	var scenario: Dictionary = current_scenario if typeof(current_scenario) == TYPE_DICTIONARY else {}
	if scenario.is_empty() and game_flow_manager and game_flow_manager.has_method("get_current_scenario"):
		scenario = game_flow_manager.get_current_scenario()
	if scenario.is_empty():
		return {"ok": false, "error": "current scenario unavailable"}
	return await continuity_service.load_into_story_state(_hub, scenario)

func write_session_digest() -> Dictionary:
	if session_digest_service == null:
		return {"ok": false, "error": "session_digest_service unavailable"}
	if continuity_service == null:
		return {"ok": false, "error": "continuity_service unavailable"}
	if _hub == null:
		return {"ok": false, "error": "hub client unavailable"}
	var scenario: Dictionary = current_scenario if typeof(current_scenario) == TYPE_DICTIONARY else {}
	if scenario.is_empty() and game_flow_manager and game_flow_manager.has_method("get_current_scenario"):
		scenario = game_flow_manager.get_current_scenario()
	if scenario.is_empty():
		return {"ok": false, "error": "current scenario unavailable"}
	return await session_digest_service.write_session_digest(_hub, scenario, continuity_service)

func export_vis_story_cycle(cycle_id: int = -1) -> Dictionary:
	if vis_story_service == null:
		return {"ok": false, "error": "vis_story_service unavailable"}
	if _hub == null:
		return {"ok": false, "error": "hub client unavailable"}
	var scenario: Dictionary = current_scenario if typeof(current_scenario) == TYPE_DICTIONARY else {}
	if scenario.is_empty() and game_flow_manager and game_flow_manager.has_method("get_current_scenario"):
		scenario = game_flow_manager.get_current_scenario()
	if scenario.is_empty():
		return {"ok": false, "error": "current scenario unavailable"}
	if StoryState and StoryState.has_method("get_scenario_continuity_state"):
		var continuity_state: Dictionary = StoryState.get_scenario_continuity_state()
		if continuity_state.is_empty() and continuity_service != null:
			var continuity_res: Dictionary = await continuity_service.load_into_story_state(_hub, scenario)
			if not bool(continuity_res.get("ok", false)) and not bool(continuity_res.get("skipped", false)):
				return continuity_res
	return await vis_story_service.export_current_cycle(_hub, scenario, cycle_id)



func update_display_from_story_state():
	GameSessionNarrativeUtilsScript.update_display_from_story_state(self)

func _on_peer_connected(id):
	GameSessionNarrativeUtilsScript.on_peer_connected(self, id)

func _on_peer_disconnected(id):
	await GameSessionNarrativeUtilsScript.on_peer_disconnected(self, id)

func _on_character_control_changed(_peer_id: int, _character_data: Dictionary):
	# Regenerate metaprompt with updated character assignments
	metaprompt_manager.generate_game_session_metaprompt(
		current_scenario, 
		current_scenario.get("characters", []), 
		player_character
	)

# Sustainability functions now handled by SustainabilityIntegrationSystem
func _on_sustainability_metrics_updated(metrics):
	if sustainability_meter and sustainability_meter.has_method("update_metrics"):
		sustainability_meter.update_metrics(metrics)
	else:
		print("GameSession: Cannot update sustainability meter - method not available")

func handle_player_action(action: String):
	await GameSessionNarrativeUtilsScript.handle_player_action(self, action)

func _on_node_visibility_toggled(is_checked: bool, node_a: Node):
	# Toggle visibility of Node A based on CheckButton state
	node_a.visible = is_checked

# NEW: Helper functions for SynTree content source management
func set_syntree_context_enabled(enabled: bool):
	GameSessionNarrativeUtilsScript.set_syntree_context_enabled(self, enabled)

func _on_save_recordings_toggle_toggled(enabled: bool) -> void:
	await GameSessionNarrativeUtilsScript.on_save_recordings_toggle_toggled(self, enabled)

func _on_syntree_context_toggle_toggled(enabled: bool) -> void:
	if _suppress_syntree_context_toggle_signal:
		return
	set_syntree_context_enabled(enabled)

func get_syntree_context_enabled() -> bool:
	return include_syntree_context

# NEW: Control clean thread usage - moved to ConversationManagementSystem
func set_clean_thread_enabled(enabled: bool):
	conversation_system.set_clean_thread_enabled(enabled)

func get_clean_thread_enabled() -> bool:
	return conversation_system.get_clean_thread_enabled()

# NEW: Force clean the current conversation thread immediately - moved to ConversationManagementSystem
func force_clean_current_thread():
	return conversation_system.force_clean_current_thread()

# NEW: Filter AI response to remove player character dialogue - moved to ConversationManagementSystem
func filter_player_character_dialogue(response: String, player_controlled_characters: Array) -> String:
	"""Remove any dialogue generated for player-controlled characters from AI response"""
	return conversation_system.filter_player_character_dialogue(response, player_controlled_characters)

func debug_current_content_sources():
	if ContentBus and ContentBus.has_method("get_active_sources"):
		var active_sources = ContentBus.get_active_sources()
		print("GameSession: Current active content sources (", active_sources.size(), "): ", active_sources)
		return active_sources
	else:
		print("GameSession: ContentBus not available")
		return []

# NEW: Smart conversation history management - moved to ConversationManagementSystem
func clean_conversation_history(_conversation_manager, target_char_limit: int = 8000) -> Dictionary:
	"""Intelligently clean conversation history"""
	return conversation_system.clean_conversation_history(_conversation_manager, target_char_limit)

func remove_content_source_blocks(content: String) -> String:
	"""Remove content source blocks while preserving actual conversation content"""
	return conversation_system.remove_content_source_blocks(content)

# NEW: Initialize clean game conversation thread - moved to ConversationManagementSystem
func initialize_clean_game_thread(_conversation_manager) -> String:
	"""Create or clean a dedicated game thread, ensuring it starts fresh"""
	return conversation_system.initialize_clean_game_thread()

# NEW: Initialize session isolation to prevent context bleeding - moved to ConversationManagementSystem
func initialize_session_isolation():
	"""Create a completely isolated conversation thread for this game session"""
	return conversation_system.initialize_session_isolation()

# NEW: Debug function to verify session isolation - moved to ConversationManagementSystem
func debug_session_isolation():
	"""Debug function to check current conversation thread and verify isolation"""
	return conversation_system.debug_session_isolation()

# NEW: Extract current conversation topic for flow analysis - moved to ConversationManagementSystem
func _extract_current_topic(recent_messages: Array) -> String:
	"""Extract current conversation topic for flow analysis"""
	return conversation_system.extract_current_topic(recent_messages)
							
func add_message(sender_id, message):
	messages.append({"sender_id": sender_id, "message": message})
	update_chat_display()
	
	# Track sustainability metrics
	# Only analyze non-player messages
	if sender_id != multiplayer.get_unique_id():  #This assumes that player messages have the local peer's ID
		var sender_name = Network.get_peer_name(sender_id)
		sustainability_tracker.analyze_message(sender_name, message)

func update_chat_display():
	chat_log.text = ""
	for msg in messages:
		var sender_name = "" if msg.sender_id == 1 else Network.get_peer_name(msg.sender_id)
		chat_log.text += sender_name + ": " + msg.message + "\n"

func display_message(sender: String, message: String):
	GameSessionAiFlowUtilsScript.display_message(self, sender, message)

func interact_with_ai(prompt: String) -> String:
	return await GameSessionAiFlowUtilsScript.interact_with_ai(self, prompt)

func start_game():
	await GameSessionAiFlowUtilsScript.start_game(self)
	
func start_game_session():
	return await GameSessionAiFlowUtilsScript.start_game_session(self)

# -----------------------------------------------------------------------------
# Improved Progress Bar Helpers (adapted from SynTree ToolbarControls)
# -----------------------------------------------------------------------------

func _show_bar():
	GameSessionUiUtilsScript.show_bar(self)

func _hide_bar():
	GameSessionUiUtilsScript.hide_bar(self)

func animate_progress_start():
	GameSessionUiUtilsScript.animate_progress_start(self)

func animate_progress_complete(success: bool):
	GameSessionUiUtilsScript.animate_progress_complete(self, success)



func animate_scroll_indicator():
	GameSessionUiUtilsScript.animate_scroll_indicator(self)

func setup_scenario_display():
	GameSessionNarrativeUtilsScript.setup_scenario_display(self)
	
func setup_player_info():
	GameSessionUiUtilsScript.setup_player_info(self)

func _ensure_header_banner() -> TextureRect:
	return GameSessionUiUtilsScript.ensure_header_banner(self)

func _on_header_vbox_resized() -> void:
	call_deferred("_fit_header_banner")

func _fit_header_banner() -> void:
	GameSessionUiUtilsScript.fit_header_banner(self)

func _apply_header_banner(player_char: Dictionary) -> void:
	GameSessionUiUtilsScript.apply_header_banner(self, player_char)

func _apply_character_voice_mappings(scenario: Dictionary) -> void:
	GameSessionNarrativeUtilsScript.apply_character_voice_mappings(self, scenario)

func _stable_index_from_name(speaker_name: String, modulo: int) -> int:
	return GameSessionUiUtilsScript.stable_index_from_name(speaker_name, modulo)

func _collect_declared_speaker_names(scenario: Dictionary) -> Array:
	return GameSessionNarrativeUtilsScript.collect_declared_speaker_names(scenario)

func _enable_voice_for_scenario_characters() -> void:
	GameSessionUiUtilsScript.enable_voice_for_scenario_characters(self, current_scenario)

func _post_voices_mapping_to_server(voices_mapping: Dictionary) -> void:
	GameSessionNarrativeUtilsScript.post_voices_mapping_to_server(self, voices_mapping)

# ===== PHASE 3: PATTERN ANALYSIS & DYNAMIC CONTINUATION =====

func _analyze_response_patterns(response: String) -> Dictionary:
	return GameSessionNarrativeUtilsScript.analyze_response_patterns(response)

func _detect_repetition_level() -> String:
	return GameSessionNarrativeUtilsScript.detect_repetition_level(self)

func _get_continuation_prompt_type(user_input: String) -> String:
	return GameSessionNarrativeUtilsScript.get_continuation_prompt_type(user_input)

func _build_dynamic_continuation() -> String:
	return GameSessionNarrativeUtilsScript.build_dynamic_continuation(self)

func _track_response_patterns(response: String):
	GameSessionNarrativeUtilsScript.track_response_patterns(self, response)

# ===== END PHASE 3 METHODS =====

# ===== PHASE 4: FILTER STATISTICS REPORTING =====

func get_filter_statistics() -> Dictionary:
	"""Get current filter statistics for monitoring."""
	return filter_stats.duplicate()

func print_filter_statistics():
	GameSessionNarrativeUtilsScript.print_filter_statistics(self)

func reset_filter_statistics():
	"""Reset filter statistics (useful for testing or new game sessions)."""
	filter_stats = {
		"narrator_lines_removed": 0,
		"hijacking_detected": 0,
		"player_dialogue_filtered": 0,
		"quality_improvements_applied": 0,
		"fallbacks_triggered": 0,
		"total_responses_processed": 0
	}
	print("GameSession: Filter statistics reset")

# ===== END PHASE 4 METHODS =====

func parse_ai_response(ai_response: String):
	GameSessionAiFlowUtilsScript.parse_ai_response(self, ai_response)



# NEW: Debug function to check AI model synchronization - moved to AIModelManagementSystem
func debug_ai_model_sync():
	"""Debug function to check if GameSession and SynTree panel are using the same AI model manager"""
	return ai_model_manager.debug_synchronization()

# NEW: Functions to manage AI model for GameSession independently - moved to AIModelManagementSystem
func get_available_ai_models() -> Array:
	"""Get list of available AI models for the GameSession"""
	return ai_model_manager.get_available_models()

func get_current_ai_model() -> String:
	"""Get the currently selected AI model for the GameSession"""
	return ai_model_manager.get_current_model()

func set_ai_model(model_name: String) -> Dictionary:
	"""Set the AI model for the GameSession. Returns: {"success": bool, "error": String}"""
	return ai_model_manager.set_model(model_name)

func list_ai_models_with_status():
	"""Print a detailed list of available AI models with their status"""
	ai_model_manager.list_models_with_status()

# NEW: Console-friendly wrapper functions
func set_model(model_name: String):
	"""Simple wrapper for console use: set_model("model_name")"""
	var result = ai_model_manager.set_model(model_name)
	if not result.success:
		print("Failed to set model: ", result.error)

func list_models():
	"""Simple wrapper for console use: list_models()"""
	ai_model_manager.list_models_with_status()

func current_model():
	"""Simple wrapper for console use: current_model()"""
	var model = ai_model_manager.get_current_model()
	if model.is_empty():
		print("No model currently selected")
	else:
		print("Current model: ", model)

# NEW: Debug button handler for AI model management
func _on_debug_ai_model_pressed():
	"""Handler for debug AI model button - shows current model and available options"""
	ai_model_manager.debug_model_status()
	print("")
	print("To change model, use console commands:")
	print("  game_session.set_model(\"model_name\")")
	print("  game_session.list_models()")
	print("  game_session.current_model()")

# Simple functions for setting and checking AI model - moved to AIModelManagementSystem
func set_game_model(model_name: String):
	"""Set the AI model for the game session"""
	ai_model_manager.set_model_simple(model_name)

func check_current_model():
	"""Print the current AI model being used by the game"""
	ai_model_manager.debug_model_status()

# RPC method for client-suggested phase transitions
# Phase transition functions now handled by PhaseManagementSystem
@rpc("any_peer", "call_remote")
func suggest_phase_transition(suggested_phase: String, reason: String = ""):
	"""RPC method allowing clients to suggest narrative phase transitions to the server"""
	if phase_system:
		phase_system.suggest_phase_transition(suggested_phase, reason)

func suggest_narrative_phase_transition(phase: String, reason: String = ""):
	"""Client-side method to suggest a phase transition to the server"""
	if phase_system:
		phase_system.suggest_narrative_phase_transition(phase, reason)

func _check_session_completion():
	"""Check if the current narrative phase indicates the session has ended"""
	if phase_system:
		phase_system.check_session_completion()

func _handle_session_ended():
	GameSessionNarrativeUtilsScript.handle_session_ended(self)

func _show_session_completion_ui():
	GameSessionNarrativeUtilsScript.show_session_completion_ui(self)

func start_new_scenario():
	GameSessionNarrativeUtilsScript.start_new_scenario(self)

# Phase display functions now handled by PhaseManagementSystem
func _on_narrative_phase_changed(new_phase: String):
	GameSessionNarrativeUtilsScript.on_narrative_phase_changed(self, new_phase)

func _get_phase_info(phase: String) -> Dictionary:
	return GameSessionReportUtilsScript.get_phase_info(phase)

func _on_show_sustainability_btn_toggled(button_pressed):
	print("GameSession: Sustainability meter toggle: ", button_pressed)
	if sustainability_meter_container:
		sustainability_meter_container.visible = button_pressed
		print("GameSession: Sustainability meter visibility set to: ", button_pressed)
	else:
		print("GameSession: WARNING - Sustainability meter container not found")

func _on_show_feedback_btn_toggled(button_pressed):
	GameSessionNarrativeUtilsScript.show_feedback_btn_toggled(self, button_pressed)

# Story progress display functions now handled by PhaseManagementSystem

# Personality system functions have been moved to CharacterPersonalitySystem class

# Quality monitoring functions have been moved to QualityMonitoringSystem class

# Quality calculation and detection functions moved to QualityMonitoringSystem class

# Quality helper functions have been moved to QualityMonitoringSystem class

# Character dialogue quality calculation moved to QualityMonitoringSystem class

# Character voice consistency calculation moved to QualityMonitoringSystem class

# Quality trend and alert functions moved to QualityMonitoringSystem class

func _get_quality_monitoring_report() -> Dictionary:
	return GameSessionReportUtilsScript.get_quality_monitoring_report(self)

func _generate_quality_recommendations() -> Array:
	return GameSessionReportUtilsScript.generate_quality_recommendations(self)

# NEW: Phase 3 Integration and Testing System
func _get_phase3_system_status() -> Dictionary:
	return GameSessionReportUtilsScript.get_phase3_system_status(self)

func _get_personality_system_status() -> Dictionary:
	return GameSessionReportUtilsScript.get_personality_system_status(self)

func _calculate_overall_system_health() -> Dictionary:
	return GameSessionReportUtilsScript.calculate_overall_system_health(self)

func _generate_system_health_recommendations(health_score: float) -> Array:
	return GameSessionReportUtilsScript.generate_system_health_recommendations(self, health_score)

func debug_phase3_systems():
	return GameSessionNarrativeUtilsScript.debug_phase3_systems(self)

func test_quality_monitoring_with_sample():
	GameSessionReportUtilsScript.test_quality_monitoring_with_sample(self)

func get_comprehensive_session_report() -> Dictionary:
	return GameSessionReportUtilsScript.get_comprehensive_session_report(self)

func _get_character_analysis_report() -> Dictionary:
	return GameSessionReportUtilsScript.get_character_analysis_report(self)

func _get_quality_summary_report() -> Dictionary:
	return GameSessionReportUtilsScript.get_quality_summary_report(self)

func _get_most_common_quality_issue() -> String:
	return GameSessionReportUtilsScript.get_most_common_quality_issue(self)

func _get_comprehensive_recommendations() -> Array:
	return GameSessionReportUtilsScript.get_comprehensive_recommendations(self)

# NEW: Debug function to log character control status
func _debug_character_control_status():
	GameSessionNarrativeUtilsScript.debug_character_control_status()

func _ensure_character_attribution(response: String, ai_controlled_names: Array) -> String:
	return GameSessionNarrativeUtilsScript.ensure_character_attribution(response, ai_controlled_names)

# Map of normalized name -> canonical name for current scenario (includes Narrator)
func _get_allowed_character_name_map() -> Dictionary:
	return GameSessionReportUtilsScript.build_allowed_character_name_map(self, current_scenario)

# Convert a potential speaker token to a canonical allowed name or empty string if unrecognized
func _canonicalize_speaker(potential: String, allowed_map: Dictionary) -> String:
	return GameSessionReportUtilsScript.canonicalize_speaker(self, potential, allowed_map)

# ENHANCED: Build narrative context with conversation flow analysis
func _build_narrative_context() -> String:
	return GameSessionReportUtilsScript.build_narrative_context(self)

# Build context-aware continuation instruction
func _build_continuation_instruction(user_input: String, character_name: String) -> String:
	return GameSessionNarrativeUtilsScript.build_continuation_instruction(self, user_input, character_name)

# Function to inject sustainability challenges - now handled by SustainabilityIntegrationSystem
func _inject_sustainability_challenge(challenge: String):
	await GameSessionReportUtilsScript.inject_sustainability_challenge(self, challenge)

# === ScenSyn AI Model (per-app) controls ===
var _model_selector: OptionButton = null
var _provider_label: Label = null
var _api_key_edit: LineEdit = null
var _api_key_save_btn: Button = null
var _temp_override_check: CheckBox = null
var _temp_model_selector: OptionButton = null
var _temp_override_enabled := false
var _temp_model_name := ""

func _ensure_ai_model_controls() -> void:
	GameSessionNarrativeUtilsScript.ensure_ai_model_controls(self)

func _resize_hamburger_panel_to_contents() -> void:
	GameSessionNarrativeUtilsScript.resize_hamburger_panel_to_contents(self)

func _refresh_model_options(selector: OptionButton) -> void:
	GameSessionNarrativeUtilsScript.refresh_model_options(self, selector)

func _update_provider_label() -> void:
	GameSessionUiUtilsScript.update_provider_label(self)

func _on_model_selected_scensyn(_index: int) -> void:
	GameSessionUiUtilsScript.on_model_selected_scensyn(self)

func _on_api_key_save_pressed() -> void:
	GameSessionUiUtilsScript.on_api_key_save_pressed(self)

func _on_temp_override_toggled(enabled: bool) -> void:
	GameSessionUiUtilsScript.on_temp_override_toggled(self, enabled)

func _on_temp_model_selected(_index: int) -> void:
	GameSessionUiUtilsScript.on_temp_model_selected(self)

func get_temp_model_override() -> Dictionary:
	return {"enabled": _temp_override_enabled, "model": _temp_model_name}

func _on_review_story_log_pressed() -> void:
	GameSessionUiUtilsScript.review_story_log(self)

func _on_open_session_logs_pressed() -> void:
	GameSessionUiUtilsScript.open_session_logs(self)

# --- Dev Agent / Harness test hooks (best-effort, editor-friendly) ---
func test_apply_state(state: Dictionary) -> void:
	var hooks_node := get_node_or_null("DevHarnessHooks")
	if is_instance_valid(hooks_node) and (hooks_node as Object).has_method("apply_state"):
		(hooks_node as Object).call("apply_state", state)


func test_dump_logs(output_path: String, since_msec: int = 0) -> void:
	var hooks_node := get_node_or_null("DevHarnessHooks")
	if is_instance_valid(hooks_node) and (hooks_node as Object).has_method("dump_logs"):
		(hooks_node as Object).call("dump_logs", output_path, since_msec)

func test_send_user_message(message_text: String) -> void:
	var hooks_node := get_node_or_null("DevHarnessHooks")
	if is_instance_valid(hooks_node) and (hooks_node as Object).has_method("send_user_message"):
		(hooks_node as Object).call("send_user_message", message_text)
