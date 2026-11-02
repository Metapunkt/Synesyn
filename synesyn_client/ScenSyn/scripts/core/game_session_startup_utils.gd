extends RefCounted
class_name GameSessionStartupUtils

const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const MicrophoneRecorder = preload("res://addons/syntree_voice/scripts/services/microphone_recorder.gd")
const ScenSynContinuityServiceScript = preload("res://ScenSyn/scripts/services/scensyn_continuity_service.gd")
const ScenSynVisStoryServiceScript = preload("res://ScenSyn/scripts/services/scensyn_vis_story_service.gd")
const ScenSynRenderPurposeServiceScript = preload("res://ScenSyn/scripts/services/scensyn_render_purpose_service.gd")
const ScenSynVerseReadingServiceScript = preload("res://ScenSyn/scripts/services/scensyn_verse_reading_service.gd")
const ScenSynSessionDigestServiceScript = preload("res://ScenSyn/scripts/services/scensyn_session_digest_service.gd")
const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)
const GameSessionStoryLogUtilsScript = preload(
	"res://ScenSyn/scripts/core/game_session_storylog_utils.gd"
)

static func ready(owner: Node) -> void:
	if FacilitatorSessionSetupScript.should_bypass_character_selection(Global.current_session_type):
		# Multiplayer WC: do not stamp every peer as Facilitator (ADR 0013).
		# Identity is claimed in-session via WorkshopPresenceController.
		if Network.is_enet_session():
			var current_any: Variant = Global.get_current_character() if Global else {}
			var current_name: String = ""
			if typeof(current_any) == TYPE_DICTIONARY:
				current_name = String((current_any as Dictionary).get("name", "")).strip_edges()
			if current_name.is_empty() or current_name == "Facilitator":
				FacilitatorSessionSetupScript.apply_participant(
					Global, StoryState, "Participant"
				)
		else:
			FacilitatorSessionSetupScript.apply(Global, StoryState)
	_prepare_pending_workshop_resume(owner)
	owner.set("_session_id", SynesynSession.get_or_create_session_id("scensyn"))
	var hub = HubSubstrateClientScript.new()
	owner.set("_hub", hub)
	owner.add_child(hub)
	hub.configure_from_runtime_config()
	owner.set("continuity_service", ScenSynContinuityServiceScript.new())
	owner.set("session_digest_service", ScenSynSessionDigestServiceScript.new())
	owner.set("vis_story_service", ScenSynVisStoryServiceScript.new())
	var render_purpose_service = ScenSynRenderPurposeServiceScript.new()
	owner.set("render_purpose_service", render_purpose_service)
	owner.add_child(render_purpose_service)
	var verse_reading_service = ScenSynVerseReadingServiceScript.new()
	owner.set("verse_reading_service", verse_reading_service)
	owner.add_child(verse_reading_service)
	_connect_external_vis_story_export(owner)
	_connect_external_verse_reading(owner)
	# Hub disconnect notification comes via the global WorkspaceBootstrapper signal
	# (see _connect_hub_notifications below), not from this per-instance ws_disconnected,
	# so that all active scenes receive the same event regardless of which component's
	# hub client closes first.
	if WorkspaceBootstrapper and WorkspaceBootstrapper.has_signal("hub_connection_changed"):
		var hub_connection_cb := func(is_connected: bool) -> void:
			if not StoryState:
				return
			if is_connected:
				StoryState.add_log_entry(
					"Narrator",
					"[b]Hub back online.[/b] Voice synthesis and workspace features have been restored."
				)
			else:
				StoryState.add_log_entry(
					"Narrator",
					"[b]Hub offline.[/b] Voice synthesis and workspace sync are paused. AI character responses continue normally. Check \u2630 \u2192 Settings if this persists."
				)
			var game_session_node := owner
			if is_instance_valid(game_session_node) and (game_session_node as Object).has_method("update_display_from_story_state"):
				(game_session_node as Object).call("update_display_from_story_state")
		if not WorkspaceBootstrapper.is_connected("hub_connection_changed", hub_connection_cb):
			WorkspaceBootstrapper.connect("hub_connection_changed", hub_connection_cb)
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	if typeof(apps_any) == TYPE_DICTIONARY:
		var apps: Dictionary = apps_any
		var scensyn_cfg_any: Variant = apps.get("scensyn", {})
		if typeof(scensyn_cfg_any) == TYPE_DICTIONARY:
			var scensyn_cfg: Dictionary = scensyn_cfg_any
			owner.set("include_syntree_context", scensyn_cfg.get("include_syntree_context", false) == true)
		else:
			owner.set("include_syntree_context", false)
	var voice_any: Variant = cfg.get("voice", {})
	if typeof(voice_any) == TYPE_DICTIONARY:
		var voice_cfg: Dictionary = voice_any
		owner.set("_save_recordings_enabled", voice_cfg.get("save_recordings", false) == true)
	else:
		owner.set("_save_recordings_enabled", false)
	var current_char = Global.get_current_character()
	if current_char.is_empty():
		print("GameSession: WARNING - No current character set! This will cause issues.")
	owner.add_to_group("game_session")
	if not StoryState:
		print("GameSession: CRITICAL ERROR - StoryState autoload not available!")
		push_error("StoryState autoload not found - check project.godot autoload configuration")
		return
	if StoryState and StoryState.has_method("get_state"):
		pass
	else:
		print("GameSession: ERROR - Failed to get StoryState")
		push_error("StoryState autoload not available - critical error")
		return
	var story_log_system: Node = owner.get("story_log_system")
	if story_log_system:
		var current_story_state = StoryState.get_state()
		if current_story_state and current_story_state.has("story_log"):
			var replayed_count := 0
			for entry in current_story_state.story_log:
				if entry.has("sender") and entry.has("message"):
					story_log_system.add_message(entry.message, entry.sender)
					replayed_count += 1
			# Advance the display cursor so update_display_from_story_state() does not
			# re-render entries that were just replayed here (avoids duplicate display on
			# scene return after switching to Story Stage and back).
			owner.set("last_displayed_message_index", replayed_count)
	else:
		print("GameSession: WARNING - StoryLogSystem not found")
	var input_field: LineEdit = owner.get("input_field")
	if not input_field:
		print("GameSession: WARNING - InputField not found")
	if SceneTransition and SceneTransition.has_method("register_game_session"):
		SceneTransition.register_game_session(owner)
	var progress_bar: TextureProgressBar = owner.get("progress_bar")
	if progress_bar:
		var current_story_state = StoryState.get_state()
		if current_story_state and current_story_state.has("current_turn"):
			var progress_value = min(current_story_state.get("current_turn", 0) * 10, 100)
			progress_bar.value = progress_value
		else:
			progress_bar.value = 0
	else:
		print("GameSession: ERROR - ProgressBar not found! Check that %ProgressBar exists in the scene.")
	if input_field and input_field.has_signal("text_submitted"):
		if not input_field.text_submitted.is_connected(owner._on_character_input_text_submitted):
			input_field.text_submitted.connect(owner._on_character_input_text_submitted)
	var send_button: Button = owner.get("send_button")
	if send_button and send_button.has_signal("pressed"):
		if not send_button.pressed.is_connected(owner._on_send_pressed):
			send_button.pressed.connect(owner._on_send_pressed)
	var record_button: Button = owner.get("record_button")
	if record_button and record_button.has_signal("toggled"):
		if not record_button.toggled.is_connected(owner._on_record_button_toggled):
			record_button.toggled.connect(owner._on_record_button_toggled)
	var scenario_objective_btn: Button = owner.get("scenario_objective_btn")
	if scenario_objective_btn and scenario_objective_btn.has_signal("toggled"):
		if not scenario_objective_btn.toggled.is_connected(owner._on_scenario_objective_btn_toggled):
			scenario_objective_btn.toggled.connect(owner._on_scenario_objective_btn_toggled)
	var show_sustainability_btn: Button = owner.get("show_sustainability_btn")
	if show_sustainability_btn and show_sustainability_btn.has_signal("toggled"):
		if not show_sustainability_btn.toggled.is_connected(owner._on_show_sustainability_btn_toggled):
			show_sustainability_btn.toggled.connect(owner._on_show_sustainability_btn_toggled)
	var show_feedback_btn: Button = owner.get("show_feedback_btn")
	if show_feedback_btn and show_feedback_btn.has_signal("toggled"):
		if not show_feedback_btn.toggled.is_connected(owner._on_show_feedback_btn_toggled):
			show_feedback_btn.toggled.connect(owner._on_show_feedback_btn_toggled)
	var cancel_scen_popup_btn: Button = owner.get("cancel_scen_popup_btn")
	if cancel_scen_popup_btn and cancel_scen_popup_btn.has_signal("pressed"):
		if not cancel_scen_popup_btn.pressed.is_connected(owner._on_cancel_popup_button_pressed):
			cancel_scen_popup_btn.pressed.connect(owner._on_cancel_popup_button_pressed)
	var hamburger_menu_btn: Button = owner.get("hamburger_menu_btn")
	if hamburger_menu_btn:
		if not hamburger_menu_btn.pressed.is_connected(owner._on_hamburger_menu_pressed):
			hamburger_menu_btn.pressed.connect(owner._on_hamburger_menu_pressed)
	var switch_to_visual_mode_btn: Button = owner.get("switch_to_visual_mode_btn")
	if switch_to_visual_mode_btn and switch_to_visual_mode_btn.has_signal("pressed"):
		if not switch_to_visual_mode_btn.pressed.is_connected(owner._on_switch_to_visual_mode_pressed):
			switch_to_visual_mode_btn.pressed.connect(owner._on_switch_to_visual_mode_pressed)
	var dual_window_toggle: BaseButton = owner.get("dual_window_toggle")
	if dual_window_toggle:
		dual_window_toggle.tooltip_text = "Dual Window Mode must be enabled from Story Stage."
		if not dual_window_toggle.toggled.is_connected(owner._on_dual_window_toggled):
			dual_window_toggle.toggled.connect(owner._on_dual_window_toggled)
		owner.call("_update_dual_window_toggle_state")
		if DualWindowManager and not DualWindowManager.window_mode_changed.is_connected(owner._on_dual_window_mode_changed):
			DualWindowManager.window_mode_changed.connect(owner._on_dual_window_mode_changed)
	var syntree_context_toggle: BaseButton = owner.get("syntree_context_toggle")
	if syntree_context_toggle:
		syntree_context_toggle.tooltip_text = "When enabled, SynTree content sources are appended as context blocks for ScenSyn AI calls."
		owner.set("_suppress_syntree_context_toggle_signal", true)
		syntree_context_toggle.button_pressed = (owner.get("include_syntree_context") == true)
		owner.set("_suppress_syntree_context_toggle_signal", false)
		if not syntree_context_toggle.toggled.is_connected(owner._on_syntree_context_toggle_toggled):
			syntree_context_toggle.toggled.connect(owner._on_syntree_context_toggle_toggled)
	var save_recordings_toggle: BaseButton = owner.get("save_recordings_toggle")
	if save_recordings_toggle:
		save_recordings_toggle.tooltip_text = "When enabled, hub STT may persist your mic input as an artifact for this session."
		owner.set("_suppress_save_recordings_toggle_signal", true)
		save_recordings_toggle.button_pressed = (owner.get("_save_recordings_enabled") == true)
		owner.set("_suppress_save_recordings_toggle_signal", false)
		if not save_recordings_toggle.toggled.is_connected(owner._on_save_recordings_toggle_toggled):
			save_recordings_toggle.toggled.connect(owner._on_save_recordings_toggle_toggled)
	if typeof(VoiceService) != TYPE_NIL and VoiceService and VoiceService.has_method("set_save_recordings_enabled"):
		VoiceService.set_save_recordings_enabled(owner.get("_save_recordings_enabled") == true)
	_bind_output_volume(owner)
	var microphone_recorder = MicrophoneRecorder.new()
	owner.set("_microphone_recorder", microphone_recorder)
	owner.add_child(microphone_recorder)
	owner.call("_set_record_button_state", "idle")
	owner.call("_connect_transcription_signals")
	owner.set("player_auto_input", Global.get_player_auto_input())
	owner.call("_configure_auto_player_input_toggle")
	_paint_voice_toggles(owner)
	if typeof(VoiceService) != TYPE_NIL:
		if not owner.has_node("VoiceBridge"):
			var vb = preload("res://addons/syntree_voice/scripts/integration/scensyn_voice_bridge.gd").new()
			vb.name = "VoiceBridge"
			owner.add_child(vb)
			print("GameSession: VoiceBridge created (VoiceService autoload present)")
		owner.call("_connect_voicebridge_scene_switch_signals")
		if VoiceService and VoiceService.has_method("is_voice_available"):
			if VoiceService.is_voice_available():
				print("GameSession: VoiceService available; ready to speak")
			else:
				print("GameSession: VoiceService present but not available yet; will enable when ready")
	var hamburger_settings_panel: Control = owner.get("hamburger_settings_panel")
	if hamburger_settings_panel and owner.get("_tts_toggle_story_log") == null:
		var container = owner.call("_ensure_settings_vbox")
		var tts_toggle_story_log = CheckButton.new()
		tts_toggle_story_log.text = "Enable TTS here (Story Log)"
		tts_toggle_story_log.tooltip_text = "Only one window can speak at a time"
		tts_toggle_story_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tts_toggle_story_log.button_pressed = (Global and Global.get_tts_emitter() == "story_log")
		tts_toggle_story_log.toggled.connect(owner._on_tts_toggle_story_log)
		container.add_child(tts_toggle_story_log)
		owner.set("_tts_toggle_story_log", tts_toggle_story_log)
		var skip_welcome_toggle = CheckButton.new()
		skip_welcome_toggle.text = "Skip Welcome Speech"
		skip_welcome_toggle.tooltip_text = "Disable TTS for the Narrator's welcome message"
		skip_welcome_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		skip_welcome_toggle.button_pressed = VoiceService.get_skip_welcome_speech() if VoiceService else false
		skip_welcome_toggle.toggled.connect(owner._on_skip_welcome_toggled)
		container.add_child(skip_welcome_toggle)
		var story_log_buttons_h := HBoxContainer.new()
		story_log_buttons_h.add_theme_constant_override("separation", 8)
		var load_btn := Button.new()
		load_btn.text = "Load Story Log…"
		load_btn.icon = load("res://Synesyn_icons/synesyn-button-icons/icon_export_download.svg")
		load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_btn.pressed.connect(owner._on_load_story_log_pressed)
		story_log_buttons_h.add_child(load_btn)
		var new_btn := Button.new()
		new_btn.text = "New Story Log"
		new_btn.icon = load("res://Synesyn_icons/synesyn-button-icons/icon_plus.svg")
		new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		new_btn.pressed.connect(owner._on_new_story_log_pressed)
		story_log_buttons_h.add_child(new_btn)
		container.add_child(story_log_buttons_h)
		var tts_controls_h := HBoxContainer.new()
		tts_controls_h.add_theme_constant_override("separation", 8)
		var pause_btn := Button.new()
		pause_btn.text = "Pause TTS"
		pause_btn.icon = load("res://Synesyn_icons/synesyn-button-icons/icon_pause_bars.svg")
		pause_btn.pressed.connect(owner._on_pause_tts_pressed)
		owner.set("_pause_tts_button", pause_btn)
		var resume_btn := Button.new()
		resume_btn.text = "Resume TTS"
		resume_btn.icon = load("res://Synesyn_icons/synesyn-button-icons/icon_play_triangle.svg")
		resume_btn.pressed.connect(owner._on_resume_tts_pressed)
		owner.set("_resume_tts_button", resume_btn)
		var stop_btn := Button.new()
		stop_btn.text = "Skip TTS"
		stop_btn.icon = load("res://Synesyn_icons/synesyn-button-icons/icon_stop_square.svg")
		stop_btn.pressed.connect(owner._on_stop_tts_pressed)
		owner.set("_skip_tts_button", stop_btn)
		tts_controls_h.add_child(pause_btn)
		tts_controls_h.add_child(resume_btn)
		tts_controls_h.add_child(stop_btn)
		container.add_child(tts_controls_h)
		owner.call("_update_tts_transport_styles")
		if Global and not Global.is_connected("tts_emitter_changed", owner._on_global_tts_emitter_changed):
			Global.connect("tts_emitter_changed", owner._on_global_tts_emitter_changed)
	owner.call("setup_player_info")
	owner.set("game_flow_manager", Global.get_game_flow_manager())
	if not owner.get("game_flow_manager"):
		print("GameSession: ERROR - Failed to get game flow manager")
	owner.set("metaprompt_manager", Global.get_metaprompt_manager())
	if not owner.get("metaprompt_manager"):
		print("GameSession: ERROR - Failed to get metaprompt manager")
	var _mpm = owner.get("metaprompt_manager")
	var _vrs = owner.get("verse_reading_service")
	if _mpm != null and _vrs != null and _mpm.has_method("set_verse_reading_service"):
		_mpm.set_verse_reading_service(_vrs)
	var _gfm = owner.get("game_flow_manager")
	if _mpm != null and _gfm != null and _mpm.has_method("load_scenario_obligations"):
		var _scenario: Dictionary = _gfm.get_current_scenario() if _gfm.has_method("get_current_scenario") else {}
		if not _scenario.is_empty():
			_mpm.load_scenario_obligations(_scenario)
	owner.call("setup_scenario_display")
	# setup_scenario_display gives up when the scenario has not resolved yet, and
	# nothing retried it, so a scenario arriving after this point — a slow load, a
	# host's synced choice, or a switch mid-session — left the header showing the
	# scene's "Scenario Label" placeholder for the rest of the session.
	if Global and not Global.is_connected("scenario_changed", owner._on_scenario_changed):
		Global.connect("scenario_changed", owner._on_scenario_changed)
	await _load_scenario_continuity(owner)
	if story_log_system and not (owner.get("_is_loading_story_log") == true):
		var current_story_state = StoryState.get_state()
		if current_story_state and current_story_state.has("story_log") and current_story_state.story_log.size() == 0:
			var game_flow_manager = owner.get("game_flow_manager")
			var scenario_data = game_flow_manager.get_current_scenario() if game_flow_manager else {}
			var welcome_message = ""
			var welcome_sender: String = "Narrator"
			if scenario_data.has("name") and scenario_data.has("objective"):
				if Global.current_session_type == "workshop_catalyst":
					welcome_sender = "Workshop Catalyst"
					var objective_text: String = str(scenario_data.objective).strip_edges()
					welcome_message = (
						"%s\n\n"
						% objective_text
					)
					welcome_message += (
						"[font_size=12][i]Speak or type below. "
						+ "Review Thinking Map and Session Record proposals before committing.[/i][/font_size]"
					)
				else:
					welcome_message = "[font_size=26][b]Welcome to " + scenario_data.name + "[/b][/font_size]\n\n"
					welcome_message += scenario_data.objective + "\n\n"
					welcome_message += "The story begins now. Choose your actions wisely and work together to navigate the challenges ahead."
				if Global:
					Global.opening_welcome_text = welcome_message
					Global.opening_spoken_log = false
					Global.opening_spoken_stage = false
			else:
				welcome_message = "[font_size=16][b]Welcome to the Story[/b][/font_size]\n\nThe narrative begins now. Work together to shape the story through your choices and actions."
			StoryState.add_log_entry(welcome_sender, welcome_message)
	print("GameSession: About to call _initialize_session_type_systems()")
	owner.call("_initialize_session_type_systems")
	print("GameSession: _initialize_session_type_systems() completed")
	print("GameSession: === STARTING AI CHARACTER AGENT INITIALIZATION ===")
	var ai_character_agent = null
	var ai_agent_failed = false
	print("GameSession: Using AICharacterAgent autoload singleton")
	ai_character_agent = AICharacterAgent
	if ai_character_agent:
		print("GameSession: AI Character Agent created successfully")
		if ai_character_agent.get_parent() == null:
			print("GameSession: AI Character Agent has no parent; adding as child.")
			owner.add_child(ai_character_agent)
		else:
			print("GameSession: AI Character Agent already in scene tree under: ", ai_character_agent.get_parent().name)
		print("GameSession: Waiting for process frame...")
		if not is_instance_valid(owner):
			return
		var tree: SceneTree = owner.get_tree()
		await tree.process_frame
		if not is_instance_valid(owner):
			return
		print("GameSession: Process frame complete")
		var agent_nodes = tree.get_nodes_in_group("AICharacterAgent")
		print("GameSession: Found ", agent_nodes.size(), " nodes in AICharacterAgent group")
		if agent_nodes.is_empty():
			print("GameSession: WARNING - AI Character Agent not found in group, may have failed to initialize")
			ai_agent_failed = true
		else:
			print("GameSession: AI Character Agent successfully initialized!")
	else:
		print("GameSession: ERROR - Failed to create AI Character Agent (returned null)")
		ai_agent_failed = true
	if ai_agent_failed:
		print("GameSession: ERROR - AI Character Agent failed to initialize properly")
		print("GameSession: AI responses will not work until this is resolved")
	print("GameSession: === AI CHARACTER AGENT INITIALIZATION COMPLETE ===")
	var phase_system: PhaseManagementSystem = owner.get("phase_system") as PhaseManagementSystem
	var story_progress_label: Label = owner.get("story_progress_label")
	var story_progress_bar: ProgressBar = owner.get("story_progress_bar")
	if phase_system:
		phase_system.setup_phase_display(owner)
		if story_progress_label and story_progress_bar:
			phase_system.setup_story_progress_display(story_progress_label, story_progress_bar)
	if StoryState:
		if StoryState.has_signal("narrative_phase_changed"):
			if not StoryState.narrative_phase_changed.is_connected(owner._on_narrative_phase_changed):
				var connection_result = StoryState.narrative_phase_changed.connect(owner._on_narrative_phase_changed)
				if connection_result != OK:
					print("GameSession: ERROR - Failed to connect to narrative_phase_changed signal: ", connection_result)
			if phase_system and not StoryState.narrative_phase_changed.is_connected(phase_system.on_narrative_phase_changed):
				StoryState.narrative_phase_changed.connect(phase_system.on_narrative_phase_changed)
		else:
			print("GameSession: WARNING - StoryState does not have narrative_phase_changed signal")
	else:
		print("GameSession: WARNING - StoryState not available for signal connection")
	if StoryState.has_signal("state_updated"):
		if not StoryState.state_updated.is_connected(owner._on_story_state_updated):
			StoryState.state_updated.connect(owner._on_story_state_updated)
			print("GameSession: Connected to StoryState.state_updated signal")
	else:
		print("GameSession: ERROR - StoryState does not have state_updated signal")
	if Network.has_signal("player_input_received"):
		if not Network.player_input_received.is_connected(owner._on_player_input_received):
			Network.player_input_received.connect(owner._on_player_input_received)
			print("GameSession: Connected to Network.player_input_received signal")
	owner.call("setup_player_info")
	if not is_instance_valid(owner):
		return
	var tree2: SceneTree = owner.get_tree()
	await tree2.process_frame
	if not is_instance_valid(owner):
		return
	_apply_pending_workshop_resume(owner)
	if not is_instance_valid(owner):
		return
	owner.call("update_display_from_story_state")

static func _prepare_pending_workshop_resume(owner: Node) -> void:
	if typeof(Global) == TYPE_NIL or not Global:
		return
	if not Global.has_method("peek_pending_workshop_resume_path"):
		return
	var resume_path: String = Global.peek_pending_workshop_resume_path()
	if resume_path.is_empty():
		return
	GameSessionStoryLogUtilsScript.prepare_workshop_resume(owner, resume_path)

static func _apply_pending_workshop_resume(owner: Node) -> void:
	if typeof(Global) == TYPE_NIL or not Global:
		return
	if not Global.has_method("take_pending_workshop_resume_path"):
		return
	var resume_path: String = Global.take_pending_workshop_resume_path()
	if resume_path.is_empty():
		return
	GameSessionStoryLogUtilsScript.on_story_log_file_selected(owner, resume_path)

static func _load_scenario_continuity(owner: Node) -> void:
	var continuity_service = owner.get("continuity_service")
	if continuity_service == null:
		return
	var hub = owner.get("_hub")
	if hub == null:
		return
	var game_flow_manager = owner.get("game_flow_manager")
	var scenario: Dictionary = game_flow_manager.get_current_scenario() if game_flow_manager else {}
	if scenario.is_empty():
		return
	var cfg_any: Variant = scenario.get("memory_continuity", {})
	var cfg: Dictionary = cfg_any if typeof(cfg_any) == TYPE_DICTIONARY else {}
	if cfg.is_empty() or String(cfg.get("enabled", "false")).to_lower() != "true":
		return
	var result: Dictionary = await continuity_service.load_into_story_state(hub, scenario)
	if not bool(result.get("ok", false)) and not bool(result.get("skipped", false)):
		print("GameSession: Memory continuity load skipped due to error: ", result)

static func _connect_external_verse_reading(owner: Node) -> void:
	if typeof(Global) == TYPE_NIL or not Global or not Global.has_method("get_external_input_listener"):
		return
	var listener = Global.get_external_input_listener()
	if listener == null or not listener.has_signal("data_received"):
		return
	var cb := Callable(GameSessionStartupUtils, "_on_external_input_for_verse").bind(owner)
	if not listener.data_received.is_connected(cb):
		listener.data_received.connect(cb)
	var verse_svc = owner.get("verse_reading_service")
	if verse_svc != null and verse_svc.has_signal("heartbeat_rumination_available"):
		var hb_cb := Callable(GameSessionStartupUtils, "_on_heartbeat_rumination")
		if not verse_svc.heartbeat_rumination_available.is_connected(hb_cb):
			verse_svc.heartbeat_rumination_available.connect(hb_cb)

static func _on_heartbeat_rumination(speaker: String, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	if StoryState and StoryState.has_method("add_system_event"):
		StoryState.add_system_event(speaker, text)

static func _on_external_input_for_verse(data: Dictionary, owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var verse_svc = owner.get("verse_reading_service")
	if verse_svc == null or not is_instance_valid(verse_svc):
		return
	if not verse_svc.is_enabled():
		var hub = owner.get("_hub")
		var scenario: Dictionary = {}
		if Global and Global.has_method("get_game_flow_manager") and Global.get_game_flow_manager():
			scenario = Global.get_game_flow_manager().get_current_scenario()
		if not scenario.is_empty() and hub != null:
			verse_svc.configure(hub, scenario)
	verse_svc.on_external_input(data)

static func _connect_external_vis_story_export(owner: Node) -> void:
	if typeof(Global) == TYPE_NIL or not Global or not Global.has_method("get_external_input_listener"):
		return
	var listener = Global.get_external_input_listener()
	if listener == null or not listener.has_signal("data_received"):
		return
	var cb := Callable(GameSessionStartupUtils, "_on_external_input_for_vis_story").bind(owner)
	if not listener.data_received.is_connected(cb):
		listener.data_received.connect(cb)

static func _on_external_input_for_vis_story(data: Dictionary, owner: Node) -> void:
	await _maybe_export_vis_story_for_external_input(owner, data)

static func _maybe_export_vis_story_for_external_input(owner: Node, data: Dictionary) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return
	if not data.has("turn_packet") and not data.has("matrix_resolution"):
		return

	var game_flow_manager = owner.get("game_flow_manager")
	var scenario: Dictionary = game_flow_manager.get_current_scenario() if game_flow_manager else {}
	if scenario.is_empty():
		var current_any: Variant = owner.get("current_scenario")
		scenario = current_any if typeof(current_any) == TYPE_DICTIONARY else {}
	if scenario.is_empty():
		return

	var vis_any: Variant = scenario.get("vis_story", {})
	var vis_cfg: Dictionary = vis_any if typeof(vis_any) == TYPE_DICTIONARY else {}
	if vis_cfg.is_empty() or String(vis_cfg.get("enabled", "false")).strip_edges().to_lower() != "true":
		return

	var packet_id := _external_payload_packet_id(data)
	if packet_id.is_empty():
		return
	var last_packet_id := str(owner.get("_last_vis_story_export_packet_id")).strip_edges()
	if packet_id == last_packet_id:
		return
	owner.set("_last_vis_story_export_packet_id", packet_id)

	var cycle_id := _external_payload_cycle_id(data)
	if cycle_id <= 0 and StoryState and StoryState.has_method("get_current_turn"):
		cycle_id = max(1, int(StoryState.get_current_turn()) + 1)
	if cycle_id <= 0:
		cycle_id = 1

	var vis_story_service = owner.get("vis_story_service")
	var hub = owner.get("_hub")
	if vis_story_service == null or hub == null:
		return
	if StoryState and StoryState.has_method("get_scenario_continuity_state"):
		var continuity_state: Dictionary = StoryState.get_scenario_continuity_state()
		if continuity_state.is_empty():
			var continuity_service = owner.get("continuity_service")
			if continuity_service != null and is_instance_valid(continuity_service):
				var continuity_res: Dictionary = await continuity_service.load_into_story_state(hub, scenario)
				if not bool(continuity_res.get("ok", false)) and not bool(continuity_res.get("skipped", false)):
					print("GameSession: vis_story continuity preload failed: ", continuity_res)
	var result: Dictionary = await vis_story_service.export_current_cycle(
		hub,
		scenario,
		cycle_id,
		{"external_input": data}
	)
	if bool(result.get("ok", false)):
		print("GameSession: vis_story cycle exported: ", result.get("path", ""))
		var cfg: Dictionary = vis_story_service.get_effective_config(scenario)
		var vis_version := str(cfg.get("version", "v1")).strip_edges().to_lower()
		var render_on_export := bool(cfg.get("render_on_export", false))
		print("GameSession: vis_story export config resolved: ", {
			"version": vis_version,
			"render_on_export": render_on_export,
			"render_purpose": str(cfg.get("render_purpose", "")),
			"render_submission_mode": str(cfg.get("render_submission_mode", "")),
		})
		if vis_version == "v2" and render_on_export:
			var render_purpose_service = owner.get("render_purpose_service")
			if render_purpose_service != null and is_instance_valid(render_purpose_service):
				print("GameSession: vis_story v2 render submission starting for cycle ", cycle_id)
				var submit_res: Dictionary = await render_purpose_service.submit_vis_story_v2_turn_render(
					str(result.get("path", "")).strip_edges(),
					int(cycle_id),
					{
						"render_purpose": str(cfg.get("render_purpose", "vis_story_v2_turn")).strip_edges(),
						"render_submission_mode": str(cfg.get("render_submission_mode", "scheduler")).strip_edges(),
						"scheduler_workflow_path": str(cfg.get("scheduler_workflow_path", "")).strip_edges(),
						"scheduler_presets_path": str(cfg.get("scheduler_presets_path", "")).strip_edges(),
						"scheduler_output_root": str(cfg.get("scheduler_output_root", "")).strip_edges(),
						"scheduler_throttle_ms": int(cfg.get("scheduler_throttle_ms", 300)),
						"scenario": scenario,
						"translator_payload": result.get("translator_payload", {}),
					}
				)
				if bool(submit_res.get("ok", false)):
					print("GameSession: vis_story v2 render submitted: ", submit_res.get("job_id", ""))
				else:
					print("GameSession: vis_story v2 render submission failed: ", submit_res)
			else:
				print("GameSession: vis_story v2 render skipped because render_purpose_service is unavailable")
		else:
			print("GameSession: vis_story render submission skipped by config gate")
	elif not bool(result.get("skipped", false)):
		print("GameSession: vis_story export skipped due to error: ", result)

static func _external_payload_cycle_id(data: Dictionary) -> int:
	if data.has("window_id"):
		var window_any: Variant = data.get("window_id")
		if typeof(window_any) == TYPE_INT:
			return maxi(1, int(window_any))
		if typeof(window_any) == TYPE_FLOAT:
			return maxi(1, int(window_any))
		var window_text := str(window_any).strip_edges()
		if window_text.is_valid_int():
			return maxi(1, int(window_text))
		if window_text.is_valid_float():
			return maxi(1, int(float(window_text)))
	return 0

static func _external_payload_packet_id(data: Dictionary) -> String:
	if data.has("window_id"):
		var wid := str(data.get("window_id", "")).strip_edges()
		if not wid.is_empty():
			return "window:%s" % wid
	var source_id := str(data.get("source_id", "")).strip_edges()
	var label := str(data.get("label", "")).strip_edges()
	var timestamp := str(data.get("timestamp", "")).strip_edges()
	if source_id != "" or label != "" or timestamp != "":
		return "src:%s|label:%s|ts:%s" % [source_id, label, timestamp]
	return "hash:%s" % str(hash(JSON.stringify(data)))


const OUTPUT_BUS := "ScenSyn"


static func _paint_voice_toggles(owner: Node) -> void:
	var auto_send := owner.get_node_or_null("%AutoSendVoice") as BaseButton
	var auto_player := owner.get_node_or_null("%AutoPlayerInput") as BaseButton
	_paint_toggle(auto_send, "res://Synesyn_icons/synesyn-button-icons/icon_auto_send_radio.svg")
	_paint_toggle(auto_player, "res://Synesyn_icons/synesyn-button-icons/icon_person_silhouette.svg")


static func _paint_toggle(button: BaseButton, icon_path: String) -> void:
	if button == null:
		return
	var tex: Texture2D = load(icon_path)
	if tex:
		button.icon = tex
	button.add_theme_stylebox_override("normal", _toggle_plate(Color(0.106, 0.172, 0.227, 1)))
	button.add_theme_stylebox_override("hover", _toggle_plate(Color(0.16, 0.24, 0.32, 1)))
	button.add_theme_stylebox_override("pressed", _toggle_plate(Color(0.22, 0.42, 0.68, 1)))
	button.add_theme_stylebox_override("hover_pressed", _toggle_plate(Color(0.28, 0.48, 0.74, 1)))
	button.add_theme_stylebox_override("disabled", _toggle_plate(Color(0.106, 0.172, 0.227, 0.55)))
	button.add_theme_stylebox_override("focus", _toggle_plate(Color(0.16, 0.24, 0.32, 1)))


static func _toggle_plate(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_right = 8
	box.corner_radius_bottom_left = 8
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


static func _bind_output_volume(owner: Node) -> void:
	var slider := owner.get_node_or_null("%OutputVolumeSlider") as HSlider
	if slider == null:
		return
	_ensure_output_bus()
	_park_story_log_players()
	slider.set_value_no_signal(_output_linear() * 100.0)
	if not slider.value_changed.is_connected(_on_output_volume_changed):
		slider.value_changed.connect(_on_output_volume_changed)


static func _on_output_volume_changed(value: float) -> void:
	_set_output_linear(value / 100.0)


static func _ensure_output_bus() -> int:
	var idx := AudioServer.get_bus_index(OUTPUT_BUS)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, OUTPUT_BUS)
	AudioServer.set_bus_send(idx, "Master")
	return idx


static func _set_output_linear(linear: float) -> void:
	var idx := _ensure_output_bus()
	if idx < 0:
		return
	var level := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, level <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(level, 0.0001)))


static func _output_linear() -> float:
	var idx := AudioServer.get_bus_index(OUTPUT_BUS)
	if idx < 0:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


static func _park_story_log_players() -> void:
	# Story Stage routes a speaker onto a short-lived bus that already sends here.
	# Story Log players are created on Master, so move those onto the same bus.
	if typeof(VoiceService) == TYPE_NIL or VoiceService == null:
		return
	var players: Variant = VoiceService.get("global_audio_players")
	if typeof(players) != TYPE_DICTIONARY:
		return
	for key in players:
		var player: Variant = players[key]
		if not (player is AudioStreamPlayer):
			continue
		var bus_name := str((player as AudioStreamPlayer).bus)
		if bus_name.begins_with("SS") and AudioServer.get_bus_index(bus_name) >= 0:
			continue
		(player as AudioStreamPlayer).bus = OUTPUT_BUS
