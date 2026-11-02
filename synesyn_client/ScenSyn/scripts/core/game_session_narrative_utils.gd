extends RefCounted
class_name GameSessionNarrativeUtils

const GameSessionScenarioUtilsScript = preload(
	"res://ScenSyn/scripts/core/game_session_scenario_utils.gd"
)

static func initialize_sustainability_system(owner: Node) -> void:
	var sustainability_tracker: Node = owner.get("sustainability_tracker")
	if not sustainability_tracker:
		var tracker_script = load("res://ScenSyn/session_types/story_catalyst/sustainability/sustainability_tracker.gd")
		sustainability_tracker = tracker_script.new()
		owner.set("sustainability_tracker", sustainability_tracker)
		owner.add_child(sustainability_tracker)
	var sustainability_meter: Node = owner.get("sustainability_meter")
	if sustainability_meter and sustainability_meter.has_method("update_metrics"):
		if sustainability_tracker.has_signal("metrics_updated"):
			if not sustainability_tracker.metrics_updated.is_connected(owner._on_sustainability_metrics_updated):
				sustainability_tracker.metrics_updated.connect(owner._on_sustainability_metrics_updated)
			var sustainability_system: SustainabilityIntegrationSystem = owner.get("sustainability_system") as SustainabilityIntegrationSystem
			if sustainability_system and not sustainability_tracker.metrics_updated.is_connected(sustainability_system.on_sustainability_metrics_updated):
				sustainability_tracker.metrics_updated.connect(sustainability_system.on_sustainability_metrics_updated)
		var initial_metrics = sustainability_tracker.get_metrics()
		sustainability_meter.update_metrics(initial_metrics)
	else:
		if sustainability_meter:
			print("GameSession: WARNING - Sustainability meter found but missing update_metrics method")
			print("GameSession: Sustainability meter type: ", sustainability_meter.get_class())
			print("GameSession: Available methods: ", sustainability_meter.get_method_list().map(func(m): return m.name))
		else:
			print("GameSession: WARNING - Sustainability meter not found")
	var personality_system = CharacterPersonalitySystem.new()
	owner.set("personality_system", personality_system)
	owner.add_child(personality_system)
	var ai_controlled_names = Network.get_ai_controlled_character_names()
	personality_system.initialize_character_profiles(ai_controlled_names)
	var dialogue_processor = DialogueProcessingSystem.new()
	owner.set("dialogue_processor", dialogue_processor)
	var quality_system = QualityMonitoringSystem.new()
	owner.set("quality_system", quality_system)
	owner.add_child(quality_system)
	var quality_deps = {
		"personality_system": personality_system,
		"character_voice_tracker": dialogue_processor.get_all_character_voice_data(),
		"get_player_controlled_character_names": func(): return Network.get_player_controlled_character_names(),
		"get_story_state": func(): return StoryState.get_state(),
		"extract_current_topic": owner._extract_current_topic,
		"is_narrator_hijacking": func(text: String, player_names: Array): return dialogue_processor.is_narrator_hijacking(text, player_names)
	}
	quality_system.set_dependencies(quality_deps)
	quality_system.initialize(ai_controlled_names)
	var adaptive_system = AdaptiveResponseSystem.new()
	adaptive_system.set_dependencies(Network, quality_system, personality_system)
	owner.set("adaptive_system", adaptive_system)
	if quality_system:
		quality_system.adaptive_system = adaptive_system
	var ai_model_manager = AIModelManagementSystem.new()
	ai_model_manager.initialize(Global.get_conversation_manager(), PluginManager, Global)
	owner.set("ai_model_manager", ai_model_manager)
	var conversation_system = ConversationManagementSystem.new()
	conversation_system.initialize(Global.get_conversation_manager(), ContentBus, Network)
	owner.set("conversation_system", conversation_system)


## Open Play: narrative-core only — conversation substrate without sustainability
## meters, cultural matrices, or curriculum phase systems.
static func initialize_open_play_system(owner: Node) -> void:
	print("GameSession: Open Play collection initialized (narrative fun / roleplay)")
	var ai_model_manager = AIModelManagementSystem.new()
	ai_model_manager.initialize(Global.get_conversation_manager(), PluginManager, Global)
	owner.set("ai_model_manager", ai_model_manager)
	var conversation_system = ConversationManagementSystem.new()
	conversation_system.initialize(Global.get_conversation_manager(), ContentBus, Network)
	owner.set("conversation_system", conversation_system)
	var personality_system = CharacterPersonalitySystem.new()
	owner.set("personality_system", personality_system)
	owner.add_child(personality_system)
	var ai_controlled_names = Network.get_ai_controlled_character_names()
	personality_system.initialize_character_profiles(ai_controlled_names)
	var meter_container: Control = owner.get("sustainability_meter_container") as Control
	if meter_container:
		meter_container.visible = false
	var show_meter_btn: BaseButton = owner.get("show_sustainability_btn") as BaseButton
	if show_meter_btn:
		show_meter_btn.visible = false
	print("GameSession: Open Play conversation substrate ready")


static func initialize_cultural_system(owner: Node) -> void:
	print("GameSession: Cultural narratives theme initialized (basic implementation)")
	var ai_model_manager = AIModelManagementSystem.new()
	ai_model_manager.initialize(Global.get_conversation_manager(), PluginManager, Global)
	owner.set("ai_model_manager", ai_model_manager)
	var conversation_system = ConversationManagementSystem.new()
	conversation_system.initialize(Global.get_conversation_manager(), ContentBus, Network)
	owner.set("conversation_system", conversation_system)
	print("GameSession: ConversationManagementSystem initialized for cultural narratives")
	var metaprompt_manager: Node = owner.get("metaprompt_manager")
	var phase_deps = {
		"network_manager": Network,
		"story_state": StoryState,
		"content_bus": ContentBus,
		"conversation_manager": Global.get_conversation_manager(),
		"metaprompt_manager": metaprompt_manager,
		"ui_manager": null
	}
	var phase_system = PhaseManagementSystem.new(phase_deps)
	owner.set("phase_system", phase_system)
	if phase_system:
		phase_system.session_completed.connect(owner._handle_session_ended)
	var sustainability_tracker: Node = owner.get("sustainability_tracker")
	var sustainability_deps = {
		"network_manager": Network,
		"story_state": StoryState,
		"sustainability_tracker": sustainability_tracker,
		"metaprompt_manager": metaprompt_manager,
		"conversation_manager": Global.get_conversation_manager(),
		"content_bus": ContentBus,
		"phase_manager": phase_system
	}
	var sustainability_system = SustainabilityIntegrationSystem.new(sustainability_deps)
	owner.set("sustainability_system", sustainability_system)
	var quality_system: Node = owner.get("quality_system")
	var personality_system: Node = owner.get("personality_system")
	var adaptive_system: AdaptiveResponseSystem = owner.get("adaptive_system") as AdaptiveResponseSystem
	var reporting_deps = {
		"quality_system": quality_system,
		"personality_system": personality_system,
		"adaptive_system": adaptive_system,
		"phase_system": phase_system,
		"sustainability_system": sustainability_system,
		"network_manager": Network,
		"story_state": StoryState
	}
	var reporting_system = SessionReportingSystem.new(reporting_deps)
	owner.set("reporting_system", reporting_system)


static func setup_scenario_display(owner: Node) -> void:
	GameSessionScenarioUtilsScript.setup_scenario_display(owner)


static func apply_character_voice_mappings(owner: Node, scenario: Dictionary) -> void:
	GameSessionScenarioUtilsScript.apply_character_voice_mappings(owner, scenario)


static func collect_declared_speaker_names(scenario: Dictionary) -> Array:
	return GameSessionScenarioUtilsScript.collect_declared_speaker_names(scenario)


static func post_voices_mapping_to_server(owner: Node, voices_mapping: Dictionary) -> void:
	GameSessionScenarioUtilsScript.post_voices_mapping_to_server(owner, voices_mapping)


static func analyze_response_patterns(response: String) -> Dictionary:
	var analysis = {"opening": "", "dominant_emotion": "", "structure_type": "", "has_narrator": false}
	if response.length() > 20:
		analysis.opening = response.substr(0, 20).to_lower()
	var emotion_tags = ["skeptical", "defensive", "hopeful", "concerned", "reporting", "looking at", "interrupting", "defensive", "confident"]
	for tag in emotion_tags:
		if tag in response.to_lower():
			analysis.dominant_emotion = tag
			break
	if response.begins_with("("):
		analysis.structure_type = "emotion_tag_opening"
	elif "Narrator:" in response:
		analysis.structure_type = "narrator_heavy"
		analysis.has_narrator = true
	elif response.count(":") >= 3:
		analysis.structure_type = "multi_character"
	else:
		analysis.structure_type = "single_focus"
	return analysis


static func detect_repetition_level(owner: Node) -> String:
	var recent_response_patterns: Dictionary = owner.get("recent_response_patterns")
	var openings = recent_response_patterns.get("openings", [])
	var emotions = recent_response_patterns.get("emotions", [])
	var opening_repeats = 0
	if openings.size() >= 2:
		for i in range(openings.size() - 1):
			if openings[i] == openings[i + 1]:
				opening_repeats += 1
	var emotion_repeats = 0
	if emotions.size() >= 3:
		var last_emotion = emotions[emotions.size() - 1]
		for em in emotions:
			if em == last_emotion:
				emotion_repeats += 1
	if opening_repeats >= 2 or emotion_repeats >= 3:
		return "high"
	elif opening_repeats >= 1 or emotion_repeats >= 2:
		return "medium"
	return "low"


static func get_continuation_prompt_type(user_input: String) -> String:
	var input_lower = user_input.to_lower().strip_edges()
	if input_lower.length() < 15:
		if input_lower in ["hello", "hi", "hey", "yes", "no", "okay", "ok"]:
			return "greeting"
		return "minimal"
	if "?" in input_lower or input_lower.begins_with("what") or input_lower.begins_with("how") or input_lower.begins_with("why") or input_lower.begins_with("who"):
		return "question"
	if " to " in input_lower or input_lower.begins_with("i ") or input_lower.begins_with("let"):
		return "action"
	return "statement"


static func build_dynamic_continuation(owner: Node) -> String:
	if not (owner.get("use_dynamic_continuation") == true) and not (owner.get("use_pattern_breaking") == true):
		return ""
	var prompt = "\n\n## DYNAMIC CONTINUATION GUIDANCE\n"
	var repetition_level = detect_repetition_level(owner)
	if repetition_level == "high":
		prompt += "\n**ALERT: Pattern repetition detected. Break the mold NOW.**\n- If your last 2 responses opened with emotion tags, try starting with dialogue directly\n- If characters keep expressing the same emotion (skeptical, concerned), flip it - try curiosity, humor, frustration\n- If responses feel like they're in a loop, introduce something NEW: an external event, a shift in topic, or an unexpected character perspective\n"
	elif repetition_level == "medium":
		prompt += "\n**NOTE: Slight pattern forming. Vary your approach.**\n- Mix up response structures: emotion tags vs. direct dialogue vs. environmental description\n- Rotate which character speaks first\n- Vary emotional registers within character consistency\n"
	var current_phase = StoryState.get_current_narrative_phase() if StoryState else "setup"
	var turn_count = StoryState.current_turn if StoryState else 1
	match current_phase:
		"setup":
			if turn_count > 8:
				prompt += "\n**PHASE PROGRESSION**: Setup phase is established. Move toward the INCIDENT that disrupts the status quo.\n"
		"incident":
			if turn_count > 15:
				prompt += "\n**PHASE PROGRESSION**: Incident has occurred. Escalate to RISING ACTION with competing responses.\n"
		"rising":
			if turn_count > 25:
				prompt += "\n**PHASE PROGRESSION**: Tensions are high. Build toward the CLIMAX decision point.\n"
	var recent_response_patterns: Dictionary = owner.get("recent_response_patterns")
	var recent_emotions = recent_response_patterns.get("emotions", [])
	if recent_emotions.size() >= 2:
		var last_emotions_str = ", ".join(recent_emotions.slice(max(0, recent_emotions.size() - 3), recent_emotions.size()))
		prompt += "\n**RECENT EMOTIONS USED**: " + last_emotions_str + " - Consider varying emotional register.\n"
	var narrator_count = int(recent_response_patterns.get("narrator_count", 0))
	if narrator_count >= 3:
		prompt += "\n**NARRATOR USAGE**: High narrator usage detected. Focus on CHARACTER DIALOGUE this turn.\n"
	return prompt


static func track_response_patterns(owner: Node, response: String) -> void:
	var analysis = analyze_response_patterns(response)
	var recent_response_patterns: Dictionary = owner.get("recent_response_patterns")
	var openings = recent_response_patterns.get("openings", [])
	openings.append(analysis.opening)
	if openings.size() > 3:
		openings.pop_front()
	recent_response_patterns.openings = openings
	if analysis.dominant_emotion != "":
		var emotions = recent_response_patterns.get("emotions", [])
		emotions.append(analysis.dominant_emotion)
		if emotions.size() > 3:
			emotions.pop_front()
		recent_response_patterns.emotions = emotions
	var structures = recent_response_patterns.get("structures", [])
	structures.append(analysis.structure_type)
	if structures.size() > 3:
		structures.pop_front()
	recent_response_patterns.structures = structures
	if analysis.has_narrator:
		recent_response_patterns.narrator_count = int(recent_response_patterns.get("narrator_count", 0)) + 1
	owner.set("recent_response_patterns", recent_response_patterns)


static func print_filter_statistics(owner: Node) -> void:
	var filter_stats: Dictionary = owner.get("filter_stats")
	print("\n=== FILTER STATISTICS ===")
	print("Total responses processed: ", filter_stats.total_responses_processed)
	print("Narrator lines removed: ", filter_stats.narrator_lines_removed)
	print("Hijacking attempts detected: ", filter_stats.hijacking_detected)
	print("Player dialogue filtered: ", filter_stats.player_dialogue_filtered)
	print("Quality improvements applied: ", filter_stats.quality_improvements_applied)
	print("Fallbacks triggered: ", filter_stats.fallbacks_triggered)
	if filter_stats.total_responses_processed > 0:
		var total = float(filter_stats.total_responses_processed)
		print("\nPercentages:")
		print("  Responses with narrator removal: ", "%.1f" % ((filter_stats.narrator_lines_removed / total) * 100), "%")
		print("  Responses with hijacking: ", "%.1f" % ((filter_stats.hijacking_detected / total) * 100), "%")
		print("  Responses with player filtering: ", "%.1f" % ((filter_stats.player_dialogue_filtered / total) * 100), "%")
		print("  Responses with quality improvements: ", "%.1f" % ((filter_stats.quality_improvements_applied / total) * 100), "%")
		print("  Responses requiring fallback: ", "%.1f" % ((filter_stats.fallbacks_triggered / total) * 100), "%")
	print("=========================\n")


static func ensure_character_attribution(response: String, ai_controlled_names: Array) -> String:
	print("GameSession: _ensure_character_attribution called with AI names: ", ai_controlled_names)
	print("GameSession: _ensure_character_attribution input: ", response.substr(0, 200) + "...")
	var lines = response.split("\n")
	var has_character_dialogue = false
	for line in lines:
		var trimmed = line.strip_edges()
		if ":" in trimmed:
			var parts = trimmed.split(":", true, 1)
			if parts.size() >= 2:
				var speaker = parts[0].strip_edges().replace("**", "").replace("*", "")
				if ai_controlled_names.has(speaker):
					has_character_dialogue = true
					print("GameSession: Found AI character dialogue from: ", speaker)
					break
	if not has_character_dialogue and response.strip_edges() != "":
		print("GameSession: No AI character dialogue found, checking for narrator attribution")
		if not response.begins_with("Narrator:"):
			print("GameSession: Adding Narrator: prefix to response")
			response = "Narrator: " + response
	else:
		print("GameSession: Response already has Narrator: prefix")
	print("GameSession: _ensure_character_attribution output: ", response.substr(0, 200) + "...")
	return response


static func build_continuation_instruction(owner: Node, user_input: String, character_name: String) -> String:
	var sustainability_system: SustainabilityIntegrationSystem = owner.get("sustainability_system") as SustainabilityIntegrationSystem
	if sustainability_system:
		return sustainability_system.build_continuation_instruction_with_sustainability(user_input, character_name)
	var instruction = "Please respond as the AI-controlled characters would naturally react to " + character_name + "'s input. "
	instruction += "Maintain character personalities and the current conversation flow. "
	instruction += "Include both character dialogue and narrative description as appropriate. "
	instruction += "Do not speak for " + character_name + " or other player-controlled characters."
	var sustainability_tracker: Node = owner.get("sustainability_tracker")
	var overall_score = sustainability_tracker.get_overall_sustainability_score()
	if overall_score < 0.5:
		instruction += " Consider how the energy crisis and sustainability challenges might influence the characters' responses and actions."
	return instruction


static func ensure_settings_vbox(owner: Node) -> VBoxContainer:
	var settings_vbox: VBoxContainer = owner.get("_settings_vbox")
	if settings_vbox and is_instance_valid(settings_vbox):
		return settings_vbox
	var hamburger_settings_panel: Control = owner.get("hamburger_settings_panel")
	if not hamburger_settings_panel:
		return null
	var vbox_node := owner.get_node_or_null("%HamburgerSettingsVBox") as VBoxContainer
	if vbox_node:
		owner.set("_settings_vbox", vbox_node)
		return vbox_node
	settings_vbox = VBoxContainer.new()
	settings_vbox.name = "HamburgerSettingsVBox"
	settings_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_vbox.add_theme_constant_override("separation", 8)
	hamburger_settings_panel.add_child(settings_vbox)
	owner.set("_settings_vbox", settings_vbox)
	return settings_vbox


static func on_skip_welcome_toggled(owner: Node, pressed: bool) -> void:
	if VoiceService:
		VoiceService.set_skip_welcome_speech(pressed)
		if not pressed and Global:
			print("GameSession: Re-enabling welcome speech - resetting spoken flags")
			Global.opening_spoken_log = false
			Global.opening_spoken_stage = false
		if pressed and owner.has_node("VoiceBridge"):
			var vb = owner.get_node("VoiceBridge")
			if vb and vb.currently_speaking_character == "Narrator" and StoryState:
				var story_log = StoryState.get_state().get("story_log", [])
				if story_log.size() > 0:
					var first_entry = story_log[0]
					if first_entry.get("sender", "") == "Narrator":
						print("GameSession: Stopping welcome speech playback")
						if vb.character_avatars.has("Narrator"):
							var narrator_avatar = vb.character_avatars["Narrator"]
							if narrator_avatar and narrator_avatar.has_method("stop_speaking"):
								narrator_avatar.stop_speaking()
						vb.speech_queue.clear()
						vb.currently_speaking_character = ""
						vb.is_processing_queue = false


static func on_record_button_toggled(owner: Node, button_pressed: bool) -> void:
	var microphone_recorder = owner.get("_microphone_recorder")
	if not microphone_recorder:
		return
	if button_pressed:
		microphone_recorder.start_recording()
		set_record_button_state(owner, "recording")
	else:
		set_record_button_state(owner, "transcribing")
		var audio_path = await microphone_recorder.stop_recording()
		if audio_path.is_empty():
			on_game_session_transcription_completed(owner, "", "Recording failed or was empty.")
			return
		if VoiceService and VoiceService.voice_client:
			VoiceService.voice_client.transcribe_audio(audio_path)
		else:
			push_error("GameSession: VoiceClient not available for transcription.")
			on_game_session_transcription_completed(owner, "", "VoiceClient not found.")


static func on_game_session_transcription_completed(owner: Node, text: String, error: String) -> void:
	set_record_button_state(owner, "idle")
	var workshop_controller_node: Node = owner.find_child("WorkshopCatalystController", true, false)
	if workshop_controller_node and workshop_controller_node.has_method(
		"handle_transcription_completed"
	):
		if bool(workshop_controller_node.call("handle_transcription_completed", text, error)):
			return
	var input_field: LineEdit = owner.get("input_field")
	if not error.is_empty():
		input_field.placeholder_text = "Transcription failed. Try again."
		push_error("GameSession: Transcription failed: %s" % error)
		return
	var trimmed_text := text.strip_edges()
	if trimmed_text.is_empty():
		input_field.placeholder_text = "Couldn't hear anything. Try again."
		return
	input_field.text = trimmed_text
	input_field.grab_focus()
	input_field.caret_column = trimmed_text.length()
	var auto_send_voice_button: BaseButton = owner.get("auto_send_voice_button")
	if auto_send_voice_button and auto_send_voice_button.button_pressed:
		owner.call("_on_send_pressed")


static func set_record_button_state(owner: Node, state: String) -> void:
	var record_button: Button = owner.get("record_button")
	var auto_send_voice_button: BaseButton = owner.get("auto_send_voice_button")
	if not record_button:
		return
	match state:
		"recording":
			record_button.button_pressed = true
			record_button.text = "Stop"
			var red_tint = Color(1, 0.6, 0.6)
			record_button.modulate = red_tint
			if auto_send_voice_button:
				auto_send_voice_button.modulate = red_tint
			record_button.disabled = false
		"transcribing":
			record_button.button_pressed = false
			record_button.disabled = true
			record_button.text = "Transcribing..."
		"idle":
			record_button.button_pressed = false
			record_button.disabled = false
			record_button.text = "Record"
			record_button.modulate = Color(1, 1, 1)
			if auto_send_voice_button:
				auto_send_voice_button.modulate = Color(1, 1, 1)


static func connect_transcription_signals(owner: Node) -> void:
	if typeof(VoiceService) == TYPE_NIL:
		return
	var vs = VoiceService
	if vs.has_signal("transcription_completed") and not vs.transcription_completed.is_connected(owner._on_game_session_transcription_completed):
		vs.transcription_completed.connect(owner._on_game_session_transcription_completed)
	var voice_client = vs.voice_client
	if voice_client and voice_client.has_signal("transcription_completed"):
		if not voice_client.transcription_completed.is_connected(owner._on_game_session_transcription_completed):
			voice_client.transcription_completed.connect(owner._on_game_session_transcription_completed)
	elif vs.has_signal("voice_service_ready"):
		if not vs.voice_service_ready.is_connected(owner._on_voice_service_ready_for_transcription):
			vs.voice_service_ready.connect(owner._on_voice_service_ready_for_transcription)


static func on_send_pressed(owner: Node) -> void:
	var input_field: LineEdit = owner.get("input_field")
	var user_input = input_field.text.strip_edges()
	if user_input == "":
		return
	input_field.text = ""
	var sender_id = owner.multiplayer.get_unique_id()
	var has_other_peers = Network.get_connected_peers().size() > 0
	if has_other_peers:
		if Network.is_server():
			owner.call("_on_player_input_received", sender_id, user_input)
		else:
			Network.rpc_id(1, "process_player_input", sender_id, user_input)
	else:
		owner.call("_on_player_input_received", sender_id, user_input)


static func update_display_from_story_state(owner: Node) -> void:
	var current_story_state = StoryState.get_state()
	if not current_story_state:
		print("GameSession: ERROR - StoryState.get_state() returned null!")
		return
	var story_messages = current_story_state.get("story_log", [])
	var last_displayed_message_index: int = owner.get("last_displayed_message_index")
	for i in range(last_displayed_message_index, story_messages.size()):
		var entry = story_messages[i]
		if typeof(entry) == TYPE_DICTIONARY and "sender" in entry and "message" in entry:
			if entry["message"].strip_edges() != "":
				owner.call("display_message", entry["sender"], entry["message"])
		else:
			print("GameSession: Invalid entry in story_log at index ", i, ": ", entry)
	owner.set("last_displayed_message_index", story_messages.size())


static func on_peer_connected(owner: Node, id: int) -> void:
	print("Peer connected: ", id)
	if Network.is_server():
		Network.reconnect_peer(id)
		var current_story_state = StoryState.get_state()
		var story_log = current_story_state.get("story_log", [])
		for message in story_log:
			Network.rpc_id(id, "sync_story_log", message["sender"], message["message"])
		Network.rpc_id(id, "sync_story_state", current_story_state)


static func on_peer_disconnected(owner: Node, id: int) -> void:
	print("Peer disconnected: ", id)
	if Network.is_server():
		await owner.get_tree().create_timer(0.1).timeout
		var metaprompt_manager: Node = owner.get("metaprompt_manager")
		var current_scenario = owner.get("current_scenario")
		var player_character = owner.get("player_character")
		metaprompt_manager.generate_game_session_metaprompt(current_scenario, current_scenario.get("characters", []), player_character)


static func set_syntree_context_enabled(owner: Node, enabled: bool) -> void:
	owner.set("include_syntree_context", enabled)
	var cm = Global.get_conversation_manager()
	if cm and cm.has_method("set_include_content_bus_context"):
		cm.set_include_content_bus_context(enabled)
	var sustainability_system: SustainabilityIntegrationSystem = owner.get("sustainability_system") as SustainabilityIntegrationSystem
	if sustainability_system:
		sustainability_system.set_syntree_context_enabled(enabled)
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	apps["scensyn"] = {"include_syntree_context": enabled}
	cfg["apps"] = apps
	RuntimeConfig.save_config(cfg)


static func on_save_recordings_toggle_toggled(owner: Node, enabled: bool) -> void:
	if owner.get("_suppress_save_recordings_toggle_signal") == true:
		return
	owner.set("_save_recordings_enabled", enabled == true)
	var cfg: Dictionary = RuntimeConfig.load_config()
	var voice_any: Variant = cfg.get("voice", {})
	var voice_cfg: Dictionary = voice_any if typeof(voice_any) == TYPE_DICTIONARY else {}
	voice_cfg["save_recordings"] = (owner.get("_save_recordings_enabled") == true)
	cfg["voice"] = voice_cfg
	RuntimeConfig.save_config(cfg)
	if typeof(VoiceService) != TYPE_NIL and VoiceService and VoiceService.has_method("set_save_recordings_enabled"):
		VoiceService.set_save_recordings_enabled(owner.get("_save_recordings_enabled") == true)
	var mode := str(voice_cfg.get("provider_mode", "direct")).strip_edges().to_lower()
	if mode != "hub":
		return
	var hub = owner.get("_hub")
	if not hub or owner.get("_consent_update_inflight") == true:
		return
	owner.set("_consent_update_inflight", true)
	var res: Dictionary = await hub.set_session_consent_save_recordings(owner.get("_session_id"), owner.get("_save_recordings_enabled") == true)
	if not (res.get("ok", false) == true):
		push_warning("GameSession: Failed to update hub consent: %s" % str(res.get("error", "unknown error")))
	owner.set("_consent_update_inflight", false)


static func on_narrative_phase_changed(owner: Node, new_phase: String) -> void:
	print("GameSession: Narrative phase changed to: ", new_phase)
	var phase_system: PhaseManagementSystem = owner.get("phase_system") as PhaseManagementSystem
	if phase_system:
		phase_system.update_story_progress_display(new_phase)
		print("GameSession: Updated story progress display for phase: ", new_phase)
	var story_progress_bar: ProgressBar = owner.get("story_progress_bar")
	if story_progress_bar:
		var phase_info = owner.call("_get_phase_info", new_phase)
		story_progress_bar.value = phase_info.progress
		print("GameSession: Updated story log progress bar to: ", phase_info.progress, "%")


static func handle_session_ended(owner: Node) -> void:
	print("GameSession: Session has ended - disabling input and showing completion options")
	var input_field: LineEdit = owner.get("input_field")
	var send_button: Button = owner.get("send_button")
	if input_field:
		input_field.editable = false
		input_field.placeholder_text = "Session Complete - Story has ended"
	if send_button:
		send_button.disabled = true
	await _write_session_digest_if_available(owner)
	show_session_completion_ui(owner)

static func _write_session_digest_if_available(owner: Node) -> void:
	if not owner.has_method("write_session_digest"):
		return
	print("GameSession: Writing session digest for cross-session continuity...")
	var result: Dictionary = await owner.write_session_digest()
	if bool(result.get("ok", false)):
		print("GameSession: Session digest written successfully")
	elif bool(result.get("skipped", false)):
		print("GameSession: Session digest skipped — %s" % str(result.get("reason", "")))
	else:
		print("GameSession: Session digest failed — %s" % str(result.get("error", "unknown")))


static func show_session_completion_ui(owner: Node) -> void:
	var completion_message = "=== SESSION COMPLETE ===\nThe story has reached its conclusion. Thank you for participating!"
	var sustainability_tracker: Node = owner.get("sustainability_tracker")
	if sustainability_tracker:
		var overall_score = sustainability_tracker.get_overall_sustainability_score()
		completion_message += "\n\nOverall Sustainability Score: " + str(int(overall_score * 100)) + "%"
	owner.call("display_message", "System", completion_message)
	print("GameSession: Session completion UI displayed")


static func start_new_scenario(owner: Node) -> void:
	var phase_system: PhaseManagementSystem = owner.get("phase_system") as PhaseManagementSystem
	if phase_system:
		phase_system.start_new_scenario()
	var input_field: LineEdit = owner.get("input_field")
	var send_button: Button = owner.get("send_button")
	if input_field:
		input_field.editable = true
		input_field.placeholder_text = "Enter your message..."
	if send_button:
		send_button.disabled = false
	print("GameSession: Ready for new scenario")


static func debug_phase3_systems(owner: Node) -> Dictionary:
	print("=== PHASE 3 SYSTEMS DEBUG ===")
	print("\n--- Personality System ---")
	var personality_system: Node = owner.get("personality_system")
	if personality_system:
		var status = personality_system.get_system_status()
		print("Character profiles: ", status.character_profiles.keys())
		print("Evolution trackers: ", status.evolution_data.keys())
		print("Emotional states: ", status.emotional_data.keys())
	else:
		print("Personality system not initialized")
	print("\n--- Quality Monitoring ---")
	var quality_system: Node = owner.get("quality_system")
	if quality_system:
		var quality_report = quality_system.get_quality_monitoring_report()
		print("Total messages monitored: ", quality_report.get("total_messages", 0))
		print("Overall session quality: ", quality_report.get("overall_quality", 0.0))
		print("Quality trend: ", quality_report.get("quality_trend", "unknown"))
		print("Recent alerts: ", quality_report.get("recent_alerts", []).size())
	else:
		print("Quality system not initialized")
	print("\n--- Adaptive Response ---")
	var adaptive_system: AdaptiveResponseSystem = owner.get("adaptive_system") as AdaptiveResponseSystem
	if adaptive_system:
		var adaptive_report = adaptive_system.get_adaptive_response_report()
		print("Total adaptations: ", adaptive_report.get("total_adaptations", 0))
		print("Character adaptations: ", adaptive_report.get("character_adaptations", {}).keys())
		print("Overall effectiveness: ", adaptive_report.get("overall_effectiveness", 0.0))
	else:
		print("Adaptive system not initialized")
	print("\n--- System Integration ---")
	var system_status = owner.call("_get_phase3_system_status")
	print("Overall system health: ", system_status.overall_health.overall_score)
	print("Health status: ", system_status.overall_health.status)
	print("Recommendations: ", system_status.overall_health.recommendations)
	print("\n=== END DEBUG ===")
	return system_status


static func debug_character_control_status() -> void:
	print("=== CHARACTER CONTROL DEBUG ===")
	var peer_info = Network.get_peer_info()
	for peer_id in peer_info:
		var info = peer_info[peer_id]
		var character = info.get("selected_character", {})
		if character:
			var peer_character_name = character.get("name", "Unknown")
			var is_ai = character.get("is_ai", true)
			print("Peer ", peer_id, ": ", peer_character_name, " (is_ai: ", is_ai, ")")
	var ai_names = Network.get_ai_controlled_character_names()
	var player_names = Network.get_player_controlled_character_names()
	print("AI controlled names from Network: ", ai_names)
	print("Player controlled names from Network: ", player_names)
	print("=== END DEBUG ===")


static func emit_session_turn_async(owner: Node, character_name: String, user_input: String, turn_index: int) -> void:
	var hub = owner.get("_hub")
	if not hub:
		return
	var app_id := "scensyn"
	var turn_id := "turn_%s_%d" % [app_id, int(Time.get_ticks_usec())]
	SynesynSession.set_current_turn_id(app_id, turn_id)
	var payload := {
		"turn_id": turn_id,
		"turn_index": turn_index,
		"role": "user",
		"character_name": character_name,
		"text": user_input,
		"t_client": float(Time.get_unix_time_from_system()),
	}
	var prov := {"component": "scensyn", "app_id": app_id}
	hub.create_event_fire_and_forget("session.turn", payload, prov, app_id, 0, owner.get("_session_id"))


static func handle_player_action(owner: Node, action: String) -> void:
	if action.strip_edges() == "":
		return
	if not (owner.get("is_multiplayer") == true) or Network.is_server():
		debug_character_control_status()
		var current_story_state = StoryState.get_state()
		if current_story_state.is_empty():
			print("GameSession: ERROR - StoryState is empty, cannot handle player action")
			return
		var metaprompt_manager: Node = owner.get("metaprompt_manager")
		var metaprompt = metaprompt_manager.get_game_session_metaprompt()
		var recent_context = String(owner.call("_build_narrative_context"))
		var player_character = owner.get("player_character")
		var user_message = """
		Previous context: {recent_log}
		
		Current player action from {player_name}: {action}
		
		Please provide a response from the AI-controlled characters and/or narrator that reacts to this action naturally.
		""".format({
			"recent_log": recent_context,
			"player_name": player_character.get("name", "Player") if player_character else "Player",
			"action": action
		})
		var combined_prompt = metaprompt + "\n\n" + user_message
		var response = await owner.call("interact_with_ai", combined_prompt)
		var sustainability_system: SustainabilityIntegrationSystem = owner.get("sustainability_system") as SustainabilityIntegrationSystem
		var sustainability_tracker: Node = owner.get("sustainability_tracker")
		if response != "":
			if sustainability_system:
				sustainability_system.analyze_ai_response_for_sustainability(response)
		else:
			sustainability_tracker.analyze_ai_response(response)
			owner.call("parse_ai_response", response)


static func show_feedback_btn_toggled(owner: Node, button_pressed) -> void:
	print("GameSession: Influence sliders toggle: ", button_pressed)
	var feedback_ui: Control = owner.get("feedback_ui")
	if feedback_ui:
		feedback_ui.visible = button_pressed
		print("GameSession: Influence sliders visibility set to: ", button_pressed)
	else:
		print("GameSession: WARNING - Feedback UI not found")


static func show_scene_switch_dialog(owner: Node, target_scene: String) -> void:
	var active_char := String(owner.call("_get_active_speaker_name"))
	var dialog := ConfirmationDialog.new()
	dialog.title = "Audio Playing"
	var speaker_text := active_char if active_char != "" else "A character"
	dialog.dialog_text = "%s is currently speaking. What would you like to do before switching views?" % speaker_text
	dialog.ok_button_text = "Skip TTS"
	dialog.cancel_button_text = "Let it finish"
	dialog.confirmed.connect(func():
		owner.call("_skip_current_tts_and_switch", target_scene)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		owner.call("_wait_for_line_then_switch", target_scene)
		dialog.queue_free()
	)
	owner.add_child(dialog)
	dialog.popup_centered_ratio(0.4)


static func show_emitter_switch_dialog(owner: Node, target_emitter: String) -> void:
	var active_char := String(owner.call("_get_active_speaker_name"))
	var dialog := ConfirmationDialog.new()
	dialog.title = "Audio Playing"
	var speaker_text := active_char if active_char != "" else "A character"
	dialog.dialog_text = "%s is currently speaking. What would you like to do before transferring TTS here?" % speaker_text
	dialog.ok_button_text = "Skip TTS"
	dialog.cancel_button_text = "Let it finish"
	dialog.confirmed.connect(func():
		owner.call("_skip_current_tts_and_apply_emitter", target_emitter)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		owner.call("_wait_for_line_then_apply_emitter", target_emitter)
		dialog.queue_free()
	)
	owner.add_child(dialog)
	dialog.popup_centered_ratio(0.4)


static func ensure_ai_model_controls(owner: Node) -> void:
	var vbox := ensure_settings_vbox(owner)
	if not vbox:
		return
	var model_selector: OptionButton = owner.get("_model_selector")
	var temp_model_selector: OptionButton = owner.get("_temp_model_selector")
	if model_selector and is_instance_valid(model_selector):
		refresh_model_options(owner, model_selector)
		refresh_model_options(owner, temp_model_selector)
		owner.call("_update_provider_label")
		return
	var section_label := Label.new()
	section_label.text = "AI Model (ScenSyn)"
	vbox.add_child(section_label)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(row)
	model_selector = OptionButton.new()
	model_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(model_selector)
	model_selector.item_selected.connect(owner._on_model_selected_scensyn)
	refresh_model_options(owner, model_selector)
	owner.set("_model_selector", model_selector)
	var provider_label := Label.new()
	provider_label.text = "Provider:"
	row.add_child(provider_label)
	owner.set("_provider_label", provider_label)
	owner.call("_update_provider_label")
	var key_row := HBoxContainer.new()
	key_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(key_row)
	var api_key_edit := LineEdit.new()
	api_key_edit.placeholder_text = "API Key (optional; Ollama requires none)"
	api_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	api_key_edit.secret = true  # Mask the key — same behaviour as other key fields in the app.
	key_row.add_child(api_key_edit)
	owner.set("_api_key_edit", api_key_edit)
	var api_key_save_btn := Button.new()
	api_key_save_btn.text = "Save"
	api_key_save_btn.pressed.connect(owner._on_api_key_save_pressed)
	key_row.add_child(api_key_save_btn)
	owner.set("_api_key_save_btn", api_key_save_btn)
	var temp_override_check := CheckBox.new()
	temp_override_check.text = "Use temp model per turn"
	temp_override_check.toggled.connect(func(pressed): owner.call("_on_temp_override_toggled", pressed))
	vbox.add_child(temp_override_check)
	owner.set("_temp_override_check", temp_override_check)
	var temp_row := HBoxContainer.new()
	temp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(temp_row)
	temp_model_selector = OptionButton.new()
	temp_model_selector.disabled = true
	temp_model_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	temp_model_selector.item_selected.connect(owner._on_temp_model_selected)
	temp_row.add_child(temp_model_selector)
	owner.set("_temp_model_selector", temp_model_selector)
	refresh_model_options(owner, temp_model_selector)


static func resize_hamburger_panel_to_contents(owner: Node) -> void:
	var vbox := ensure_settings_vbox(owner)
	var hamburger_settings_panel: Control = owner.get("hamburger_settings_panel")
	if not vbox or not hamburger_settings_panel:
		return
	vbox.minimum_size_changed.emit()
	var desired_height := vbox.get_combined_minimum_size().y + 20.0
	var margin_node := hamburger_settings_panel.get_parent()
	if not (margin_node and margin_node is Control):
		return
	var margin_ctrl: Control = margin_node
	var top: float = float(margin_ctrl.offset_top)
	var viewport_h := owner.get_viewport().get_visible_rect().size.y
	var max_height: float = max(120.0, viewport_h - top - 20.0)
	var current_height: float = float(margin_ctrl.size.y)
	var min_height: float = max(240.0, current_height)
	var final_height: float = min(max(desired_height, min_height), max_height)
	margin_ctrl.offset_bottom = top + final_height


static func refresh_model_options(owner: Node, selector: OptionButton) -> void:
	if not selector:
		return
	selector.clear()
	var pm = Global.get_plugin_manager() if Global and Global.has_method("get_plugin_manager") else null
	var aim = pm.get_ai_model_manager() if pm and pm.has_method("get_ai_model_manager") else null
	var models: Array = []
	if aim and aim.has_method("get_available_models"):
		models = aim.get_available_models()
	for m in models:
		selector.add_item(String(m))
	if aim and aim.has_method("get_current_model"):
		var cur := String(aim.get_current_model())
		for i in range(selector.item_count):
			if selector.get_item_text(i) == cur:
				selector.select(i)
				break
