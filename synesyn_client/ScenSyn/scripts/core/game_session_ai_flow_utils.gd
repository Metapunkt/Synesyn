extends RefCounted
class_name GameSessionAiFlowUtils

const NarrationFilterScript = preload("res://ScenSyn/scripts/utils/narration_filter.gd")

static func on_player_input_received(owner: Node, sender_id: int, user_input: String) -> void:
	var has_other_peers = Network.get_connected_peers().size() > 0
	var should_process = Network.is_server() or not has_other_peers
	if not should_process:
		return
	var character_name: String = GameSessionUiUtils.resolve_local_speaker_name(sender_id)
	var sustainability_tracker: Node = owner.get("sustainability_tracker")
	if sustainability_tracker:
		sustainability_tracker.analyze_message(character_name, user_input)
	if user_input.strip_edges() == "":
		return
	if Global and Global.current_session_type == "workshop_catalyst":
		var trimmed_input := user_input.strip_edges()
		# Facilitator closure commands: /decide, /risk, /defer
		# These write directly to workshop buckets and post a Session Record confirmation.
		# They do NOT trigger AI character responses.
		if _handle_workshop_closure_command(trimmed_input, owner):
			return
		# /vote command: explicitly call a vote on the current convergence point.
		# Session Record synthesizes a proposal from the recent log and posts it.
		if await _handle_workshop_vote_command(trimmed_input, owner):
			return
		# /synthesis command: recall the most recent hidden specialist synthesis
		# on demand. The full narrative no longer auto-posts every turn.
		if _handle_workshop_synthesis_command(trimmed_input, owner):
			return
		var ws_any: Variant = StoryState.get_state().get("workshop_catalyst", {})
		var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
		var is_note_cmd := false
		var note_text := ""
		if trimmed_input.begins_with("/note"):
			is_note_cmd = true
			note_text = trimmed_input.substr(5).strip_edges()
		elif ws.get("is_note_only_next_input", false) == true:
			is_note_cmd = true
			note_text = trimmed_input
			ws["is_note_only_next_input"] = false
			var s0: Dictionary = StoryState.get_state()
			var s1: Dictionary = s0.duplicate(true)
			s1["workshop_catalyst"] = ws
			StoryState.set_state(s1)
		if is_note_cmd:
			if note_text.is_empty():
				return
			var note_sender := "Facilitator Note"
			var mgr = Global.get_metaprompt_manager() if Global else null
			if mgr and mgr.has_method("get_system_cue_tag"):
				note_sender = String(mgr.get_system_cue_tag())
			StoryState.add_log_entry(note_sender, note_text)
			owner.call("update_display_from_story_state")
			return
		# Prefer live presence display name (ADR 0013) over the legacy
		# send_as_facilitator → literal "Facilitator" override.
		var presence_node: Node = (
			Network.get_workshop_presence() if Network.has_method("get_workshop_presence") else null
		)
		if presence_node and presence_node.has_method("is_active") and presence_node.is_active():
			var store_any: Variant = presence_node.call("get_store")
			if store_any and store_any.has_method("get_display_name"):
				var presence_name: String = String(
					store_any.call("get_display_name", sender_id)
				).strip_edges()
				if not presence_name.is_empty():
					character_name = presence_name
		elif ws.get("send_as_facilitator", false) == true:
			var local_display: String = String(ws.get("local_display_name", "")).strip_edges()
			character_name = local_display if not local_display.is_empty() else "Facilitator"
		# Workshop vote scan: route human input through the theme's dialogue processor.
		# This detects strict-opener Yes/No (and <<YES>>/<<NO>> tokens) when a vote is on
		# the table, strips the tokens, and forwards the vote to the session record.
		var human_mgr = Global.get_metaprompt_manager() if Global else null
		if human_mgr and human_mgr.has_method("process_actor_dialogue"):
			var processed: String = human_mgr.process_actor_dialogue(character_name, user_input)
			if processed != user_input:
				user_input = processed
				if user_input.strip_edges().is_empty():
					owner.call("update_display_from_story_state")
					return
	var current_story_state = StoryState.get_state()
	var story_log = current_story_state.get("story_log", [])
	var last_entry = story_log.back() if not story_log.is_empty() else null
	if last_entry and last_entry.get("sender") == character_name and last_entry.get("message") == user_input:
		return
	StoryState.add_log_entry(character_name, user_input)
	owner.call("_emit_session_turn_async", character_name, user_input, StoryState.get_state().get("current_turn", 0))
	StoryState.advance_turn()
	owner.set("current_turn", StoryState.get_state().get("current_turn", 0))
	var sustainability_system: SustainabilityIntegrationSystem = owner.get("sustainability_system") as SustainabilityIntegrationSystem
	if sustainability_system:
		sustainability_system.set_current_turn(int(owner.get("current_turn")))
	owner.call("update_display_from_story_state")


static func process_ai_response_deprecated(owner: Node, character_name: String, user_input: String) -> void:
	var ai_controlled_names = Network.get_ai_controlled_character_names()
	var player_controlled_names = Network.get_player_controlled_character_names()
	print("GameSession: AI controlled characters: ", ai_controlled_names)
	print("GameSession: Player controlled characters: ", player_controlled_names)
	if ai_controlled_names.is_empty():
		print("GameSession: CRITICAL ERROR - No AI-controlled characters found! This will prevent AI responses.")
		owner.call("_debug_character_control_status")
		if Network.is_server():
			Network.assign_unselected_characters_to_ai()
			ai_controlled_names = Network.get_ai_controlled_character_names()
			if ai_controlled_names.is_empty():
				print("GameSession: CRITICAL - Still no AI characters! Adding generic AI response.")
				var emergency_response = "The atmosphere becomes tense as everyone considers " + character_name + "'s words. The energy crisis looms over their thoughts as they contemplate the next steps."
				StoryState.add_log_entry("Narrator", emergency_response)
				return
	if player_controlled_names.is_empty():
		print("GameSession: WARNING - No player-controlled characters found! This might indicate a setup issue.")
	owner.call("_debug_character_control_status")
	var metaprompt_manager: Node = owner.get("metaprompt_manager")
	var prompt = metaprompt_manager.get_game_session_metaprompt() + "\n\n"
	prompt += "Current AI-Controlled Characters: " + ", ".join(ai_controlled_names) + "\n\n"
	var context = String(owner.call("_build_narrative_context"))
	if context != "":
		prompt += "RECENT CONVERSATION CONTEXT:\n" + context + "\n\n"
	var dialogue_processor: DialogueProcessingSystem = owner.get("dialogue_processor") as DialogueProcessingSystem
	for ai_name in ai_controlled_names:
		var voice_guidance = dialogue_processor.get_character_voice_guidance(ai_name)
		if voice_guidance != "":
			prompt += voice_guidance + "\n"
	prompt += character_name + ": " + user_input + "\n\n"
	prompt += String(owner.call("_build_continuation_instruction", user_input, character_name))
	var response = await owner.call("interact_with_ai", prompt)
	var filter_stats_any: Variant = owner.get("filter_stats")
	var filter_stats: Dictionary = filter_stats_any if typeof(filter_stats_any) == TYPE_DICTIONARY else {}
	filter_stats["total_responses_processed"] = int(filter_stats.get("total_responses_processed", 0)) + 1
	print("GameSession: RAW AI RESPONSE FROM interact_with_ai:")
	print("=".repeat(50))
	print(response)
	print("=".repeat(50))
	var local_player_character = Global.get_current_character()
	var player_character_name = local_player_character.get("name", "Unknown Player") if local_player_character else "Unknown Player"
	var ai_character_names = Network.get_ai_controlled_character_names()
	var narrator_filter_result: Dictionary = NarrationFilterScript.aggressive_narrator_filter(response, player_controlled_names, ai_character_names)
	response = str(narrator_filter_result.get("text", response))
	filter_stats["hijacking_detected"] = int(filter_stats.get("hijacking_detected", 0)) + int(narrator_filter_result.get("hijacking_detected", 0))
	filter_stats["narrator_lines_removed"] = int(filter_stats.get("narrator_lines_removed", 0)) + int(narrator_filter_result.get("narrator_lines_removed", 0))
	print("GameSession: AFTER _aggressive_narrator_filter:")
	print(response.substr(0, 300) + "...")
	print("GameSession: Checking for narrator hijacking with player: ", player_character_name)
	if dialogue_processor.is_narrator_hijacking(response, [player_character_name]):
		print("GameSession Guardrail: Narrator hijacking detected! Filtering output.")
		print("GameSession: Original response: ", response.substr(0, 200) + "...")
		response = dialogue_processor.filter_hijacked_action(response, player_character_name)
		print("GameSession: Filtered response: ", response.substr(0, 200) + "...")
	var processed_response = dialogue_processor.improve_dialogue_quality(response)
	if processed_response != response:
		filter_stats["quality_improvements_applied"] = int(filter_stats.get("quality_improvements_applied", 0)) + 1
	dialogue_processor.track_character_voice_consistency(processed_response)
	var conversation_system: ConversationManagementSystem = owner.get("conversation_system") as ConversationManagementSystem
	if not player_controlled_names.is_empty():
		print("GameSession: Filtering player character dialogue for: ", player_controlled_names)
		print("GameSession: Original response length: ", processed_response.length())
		var pre_filter_length = processed_response.length()
		processed_response = conversation_system.filter_player_character_dialogue(processed_response, player_controlled_names)
		print("GameSession: Filtered response length: ", processed_response.length())
		if processed_response.length() < pre_filter_length:
			filter_stats["player_dialogue_filtered"] = int(filter_stats.get("player_dialogue_filtered", 0)) + 1
	processed_response = String(owner.call("_ensure_character_attribution", processed_response, ai_controlled_names))
	if processed_response.strip_edges().is_empty():
		print("GameSession: WARNING - Processed response is empty! Adding fallback AI character response.")
		filter_stats["fallbacks_triggered"] = int(filter_stats.get("fallbacks_triggered", 0)) + 1
		if not ai_controlled_names.is_empty():
			var fallback_character = ai_controlled_names[0]
			processed_response = fallback_character + ": That's an interesting point, " + character_name + ". Let me think about how we can address that in our current situation."
		else:
			processed_response = "System: Unable to generate AI response - no AI characters available."
	var lines = processed_response.split("\n")
	var has_ai_character_response = false
	var has_narrator_response = false
	for line in lines:
		var trimmed_line = line.strip_edges()
		if trimmed_line.is_empty():
			continue
		if trimmed_line.begins_with("Narrator:"):
			has_narrator_response = true
		else:
			for ai_name in ai_controlled_names:
				if trimmed_line.begins_with(ai_name + ":"):
					has_ai_character_response = true
					break
	if has_narrator_response and not has_ai_character_response:
		print("GameSession: WARNING - Got narrator-only response when AI characters should respond!")
		print("GameSession: Player input was: ", user_input.substr(0, 100))
		print("GameSession: AI controlled names: ", ai_controlled_names)
		print("GameSession: Processed response: ", processed_response.substr(0, 200))
		if not ai_controlled_names.is_empty():
			var fallback_character2 = ai_controlled_names[0]
			processed_response += "\n\n" + fallback_character2 + ": I'd like to hear more about that. What specific aspects should we focus on?"
	owner.set("filter_stats", filter_stats)
	owner.call("parse_ai_response", processed_response)
	if Network.is_server():
		await owner.call("_run_ai_phase_evaluation")
	owner.call("_check_session_completion")


## Intercepts facilitator closure commands (/decide, /risk, /defer).
## Writes directly to the workshop bucket and posts a Session Record confirmation.
## Returns true if the command was consumed (caller should return early).
static func _handle_workshop_closure_command(trimmed_input: String, owner: Node) -> bool:
	var lower := trimmed_input.to_lower()
	var bucket_key := ""
	var prefix_len := 0
	var label := ""
	if lower.begins_with("/decide "):
		bucket_key = "decisions"; prefix_len = 8; label = "Decision"
	elif lower.begins_with("/risk "):
		bucket_key = "risks"; prefix_len = 6; label = "Risk"
	elif lower.begins_with("/defer "):
		bucket_key = "open_questions"; prefix_len = 7; label = "Deferred question"
	else:
		return false

	var content := trimmed_input.substr(prefix_len).strip_edges()
	if content.is_empty():
		return true  # Consume but add nothing for blank entries

	# Read current workshop state
	var state: Dictionary = StoryState.get_state()
	var ws_any: Variant = state.get("workshop_catalyst", {})
	var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var items_any: Variant = buckets.get(bucket_key, [])
	var items: Array = items_any if typeof(items_any) == TYPE_ARRAY else []

	# Deduplicate: skip if already recorded
	var already_exists := false
	for existing_any in items:
		if String(existing_any).strip_edges().to_lower() == content.to_lower():
			already_exists = true
			break
	if not already_exists:
		items.append(content)
	buckets[bucket_key] = items
	ws["buckets"] = buckets

	# Persist back through set_state (same pattern as /note one-shot reset)
	var new_state: Dictionary = state.duplicate(true)
	new_state["workshop_catalyst"] = ws
	StoryState.set_state(new_state)

	# Post a Session Record confirmation (visible in transcript, filtered from AI triggers)
	var count: int = items.size()
	var ordinals := ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"]
	var ordinal: String = ordinals[mini(count - 1, ordinals.size() - 1)]
	var confirmation := "%s recorded (%s %s): %s" % [label, ordinal, label.to_lower(), content]
	StoryState.add_log_entry("Session Record", confirmation)
	owner.call("update_display_from_story_state")
	return true


## Facilitator /vote command: asks the Session Record to synthesize a Yes/No proposal
## from the recent log. The proposal becomes pending_vote; participants then open
## their next utterances with Yes or No (or use <<YES>>/<<NO>> tokens) to vote.
static func _handle_workshop_vote_command(trimmed_input: String, owner: Node) -> bool:
	var lower := trimmed_input.to_lower()
	if not (lower == "/vote" or lower.begins_with("/vote ")):
		return false
	# Look up the session record via the workshop controller (added as child of the
	# GameSession by _initialize_workshop_catalyst_system) or via the manager wiring.
	var session_record: Variant = null
	if owner and owner.has_method("find_child"):
		var controller_node: Variant = owner.find_child("WorkshopCatalystController", true, false)
		if controller_node and "_session_record" in controller_node:
			session_record = controller_node.get("_session_record")
	if session_record == null:
		var mgr = Global.get_metaprompt_manager() if Global else null
		if mgr and "_session_record" in mgr:
			session_record = mgr.get("_session_record")
	if session_record == null or not session_record.has_method("call_vote_from_recent_log"):
		StoryState.add_log_entry("Session Record", "/vote requested but the Session Record is not available.")
		owner.call("update_display_from_story_state")
		return true
	await session_record.call_vote_from_recent_log("facilitator_vote_command")
	owner.call("update_display_from_story_state")
	return true


## Facilitator /synthesis command: recalls the most recent hidden specialist
## synthesis (the Session Record narrative). The narrative is cached every
## turn by ai_character_agent.gd but only posted to the visible log on demand,
## keeping the transcript from filling with a wall of text after every turn.
static func _handle_workshop_synthesis_command(trimmed_input: String, owner: Node) -> bool:
	var lower := trimmed_input.to_lower()
	if not (lower == "/synthesis" or lower.begins_with("/synthesis ")):
		return false
	var ws_any: Variant = StoryState.get_state().get("workshop_catalyst", {})
	var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	var latest_text: String = String(ws.get("session_record_latest_text", "")).strip_edges()
	if latest_text.is_empty():
		StoryState.add_log_entry(
			"Session Record",
			"No synthesis is available yet — send a facilitator turn first, then try /synthesis again."
		)
	else:
		StoryState.add_log_entry("Session Record", latest_text)
	owner.call("update_display_from_story_state")
	return true


static func display_message(owner: Node, sender: String, message: String) -> void:
	if message.strip_edges() == "":
		print("GameSession: Attempted to display empty message, ignoring")
		return
	var formatted_message = ""
	var cleaned_message = message
	cleaned_message = cleaned_message.replace("**" + sender + ":**", "")
	cleaned_message = cleaned_message.replace("**Narrator:**", "")
	cleaned_message = cleaned_message.replace("**", "")
	var re_plain := RegEx.new()
	re_plain.compile("^\\s*" + String(owner.call("_regex_escape", sender)) + ":\\s*")
	cleaned_message = re_plain.sub(cleaned_message, "", true)
	var re_bbcode := RegEx.new()
	re_bbcode.compile("^\\s*(\\[font_size=\\d+\\]\\[b\\]" + String(owner.call("_regex_escape", sender)) + ":\\[\\/b\\]\\[\\/font_size\\]\\s*)+")
	cleaned_message = re_bbcode.sub(cleaned_message, "", true)
	if sender == "Narrator":
		var re_narr := RegEx.new()
		re_narr.compile("^\\s*(Narrator:)+\\s*")
		cleaned_message = re_narr.sub(cleaned_message, "", true)
	var re_empty_label := RegEx.new()
	re_empty_label.compile("\\[font_size=\\d+\\]\\[b\\]\\[\\/b\\]\\[\\/font_size\\]")
	cleaned_message = re_empty_label.sub(cleaned_message, "", true)
	while "\n\n\n" in cleaned_message:
		cleaned_message = cleaned_message.replace("\n\n\n", "\n\n")
	cleaned_message = cleaned_message.strip_edges()
	formatted_message += cleaned_message
	var story_log_system: Node = owner.get("story_log_system")
	if story_log_system:
		story_log_system.add_message(formatted_message, sender)
	else:
		print("GameSession: ERROR - story_log_system is null!")
	if owner.has_node("VoiceBridge"):
		var voice_bridge = owner.get_node("VoiceBridge")
		var should_request = false
		if sender == "Narrator" and message.find("Welcome to") != -1:
			should_request = true
		elif Global and Global.get_tts_emitter() == "story_log":
			should_request = voice_bridge.should_request_voice_for_message(sender, message)
		var workshop_controller_node: Node = owner.find_child(
			"WorkshopCatalystController", true, false
		)
		if (
			workshop_controller_node
			and workshop_controller_node.has_method("should_speak_workshop_message")
		):
			should_request = (
				should_request
				and bool(workshop_controller_node.call(
					"should_speak_workshop_message",
					sender
				))
			)
		if should_request:
			var character_name = voice_bridge.extract_character_name_from_sender(sender)
			var regex = RegEx.new()
			regex.compile("\\[/?[^\\]]*\\]")
			var clean_message = regex.sub(message, "", true).strip_edges()
			var voice_character_name = character_name
			if Global.has_method("get_game_flow_manager"):
				var gfm = Global.get_game_flow_manager()
				if gfm and gfm.has_method("get_metaprompt_manager"):
					var manager = gfm.get_metaprompt_manager()
					if manager and manager.has_method("get_voice_overrides"):
						var current_scenario: Dictionary = owner.get("current_scenario")
						var overrides = manager.get_voice_overrides(current_scenario)
						if overrides.has(character_name):
							voice_character_name = overrides[character_name]
			voice_bridge.request_character_speech(voice_character_name, clean_message)


static func interact_with_ai(owner: Node, prompt: String) -> String:
	if owner.get("is_multiplayer") == true and not Network.is_server():
		return ""
	print("GameSession: interact_with_ai called with prompt length: ", prompt.length())
	owner.call("animate_progress_start")
	var current_conversation_manager = Global.get_conversation_manager()
	if not current_conversation_manager:
		print("GameSession: ERROR - conversation_manager is null!")
		owner.call("animate_progress_complete", false)
		return "I'm sorry, the conversation service is not available."
	print("GameSession: conversation_manager instance ID: ", current_conversation_manager.get_instance_id())
	print("GameSession: conversation_manager api_service: ", current_conversation_manager.api_service)
	print("GameSession: conversation_manager ai_model_manager: ", current_conversation_manager.ai_model_manager)
	if not current_conversation_manager.api_service:
		print("GameSession: ERROR - ConversationManager has no api_service!")
		owner.call("animate_progress_complete", false)
		return "I'm sorry, the API service is not configured."
	if not current_conversation_manager.ai_model_manager:
		print("GameSession: CRITICAL - ai_model_manager is null at call time!")
		owner.call("animate_progress_complete", false)
		return "I'm sorry, the AI system is not properly configured."
	var sustainability_tracker: Node = owner.get("sustainability_tracker")
	var metaprompt_manager: Node = owner.get("metaprompt_manager")
	var overall_score = sustainability_tracker.get_overall_sustainability_score()
	var intensity = "low"
	if overall_score < 0.2:
		intensity = "high"
	elif overall_score < 0.4:
		intensity = "medium"
	if overall_score < 0.5:
		prompt = metaprompt_manager.inject_theme_focus(prompt, intensity, sustainability_tracker.get_domain_feedback())
	var include_syntree_context: bool = (owner.get("include_syntree_context") == true)
	var original_active_sources = []
	var sources_were_disabled = false
	if not include_syntree_context and ContentBus and ContentBus.has_method("get_active_sources"):
		original_active_sources = ContentBus.get_active_sources().duplicate()
		if not original_active_sources.is_empty():
			for source_id in original_active_sources:
				ContentBus.set_source_active_state(source_id, false)
			sources_were_disabled = true
	if current_conversation_manager.ai_model_manager:
		var current_model_name = current_conversation_manager.ai_model_manager.get_current_model()
		current_conversation_manager.ai_model_manager.get_provider_for_model(current_model_name)
		current_conversation_manager.ai_model_manager.validate_api_key_for_model(current_model_name)
	else:
		print("GameSession: CRITICAL - ai_model_manager is null at call time!")
		owner.call("animate_progress_complete", false)
		return "I'm sorry, the AI system is not properly configured."
	var thread_name_before = current_conversation_manager.get_current_thread()
	var messages_before = current_conversation_manager.get_thread_messages(thread_name_before)
	print("GameSession DEBUG BEFORE CLEAN: Thread '", thread_name_before, "' has ", messages_before.size(), " messages")
	var cleanup_result = owner.call("clean_conversation_history", current_conversation_manager, 150000)
	var thread_name_after = current_conversation_manager.get_current_thread()
	var messages_after = current_conversation_manager.get_thread_messages(thread_name_after)
	print("GameSession DEBUG AFTER CLEAN: Thread '", thread_name_after, "' has ", messages_after.size(), " messages")
	print("GameSession DEBUG: Cleanup reported keeping ", cleanup_result.messages_kept, " messages")
	if owner.get("use_dynamic_continuation") == true or owner.get("use_pattern_breaking") == true:
		var dynamic_continuation = String(owner.call("_build_dynamic_continuation"))
		if dynamic_continuation != "":
			prompt += dynamic_continuation
			print("GameSession: Added dynamic continuation guidance to prompt")
	var response = await current_conversation_manager.chat(prompt)
	if sources_were_disabled and ContentBus:
		for source_id in original_active_sources:
			ContentBus.set_source_active_state(source_id, true)
	if response.success:
		owner.call("animate_progress_complete", true)
		var thread_name_end = current_conversation_manager.get_current_thread()
		var messages_end = current_conversation_manager.get_thread_messages(thread_name_end)
		print("GameSession DEBUG AFTER RESPONSE: Thread '", thread_name_end, "' NOW has ", messages_end.size(), " messages")
		if owner.get("use_pattern_breaking") == true:
			owner.call("_track_response_patterns", response.response)
		return response.response
	owner.call("animate_progress_complete", false)
	print("GameSession: AI chat failed with error: ", response.error)
	if response.has("details"):
		print("GameSession: Additional error details: ", response.details)
	var error_msg = str(response.error)
	print("GameSession: AI chat failed — error: ", error_msg)
	if "API key" in error_msg or "authentication" in error_msg.to_lower() or "unauthorized" in error_msg.to_lower():
		print("GameSession: Auth/API-key error detected — returning empty string (caller will use fallback)")
		owner.call("animate_progress_complete", false)
		return ""
	owner.call("animate_progress_complete", false)
	return ""


static func start_game(owner: Node) -> void:
	var current_scenario: Dictionary = owner.get("current_scenario")
	var intro_message = "Welcome to " + current_scenario.get("name", "the game") + "!"
	Network.send_message(intro_message)
	if Network.is_server():
		await owner.get_tree().create_timer(0.5).timeout
		Network.assign_unselected_characters_to_ai()
		print("GameSession: Validating AI character assignment after start_game...")
		owner.call("_debug_character_control_status")
		var ai_names = Network.get_ai_controlled_character_names()
		if ai_names.is_empty():
			print("GameSession: CRITICAL ERROR - No AI characters found after assignment!")
			print("GameSession: This will prevent AI from responding to player actions.")
		else:
			print("GameSession: AI character assignment successful - AI controls: ", ai_names)
	owner.call("animate_progress_start")
	var initial_response = await start_game_session(owner)
	owner.call("animate_progress_complete", true)
	if initial_response:
		owner.call("parse_ai_response", initial_response)
		StoryState.advance_turn()
	print("Server: Game session started, updating story state")
	var current_story_state = StoryState.get_state()
	Network.update_story_state(current_story_state)
	Network.notify_clients_game_ready()
	print("Server: Notifying clients that game is ready")
	Network.rpc("notify_game_ready")


static func start_game_session(owner: Node) -> String:
	print("GameSession: Starting game session...")
	var current_conversation_manager = Global.get_conversation_manager()
	if not current_conversation_manager:
		print("GameSession: ERROR - ConversationManager not available for game start")
		return "Welcome to the game! Let's begin your adventure."
	if not current_conversation_manager.ai_model_manager:
		print("GameSession: ERROR - AIModelManager not available for game start")
		return "Welcome to the game! Let's begin your adventure."
	if not current_conversation_manager.api_service:
		print("GameSession: ERROR - APIService not available for game start")
		return "Welcome to the game! Let's begin your adventure."
	var current_model_name = current_conversation_manager.ai_model_manager.get_current_model()
	if current_model_name.is_empty():
		print("GameSession: ERROR - No AI model selected for game start")
		return "Welcome to the game! Let's begin your adventure."
	print("GameSession: Using AI model for game start: ", current_model_name)
	var metaprompt_manager: Node = owner.get("metaprompt_manager")
	var intro_prompt = metaprompt_manager.get_game_session_metaprompt() + "\n\nBegin the story and set the scene for the players."
	print("GameSession: Generated intro prompt length: ", intro_prompt.length())
	var original_active_sources = []
	var sources_were_disabled = false
	if not (owner.get("include_syntree_context") == true) and ContentBus and ContentBus.has_method("get_active_sources"):
		original_active_sources = ContentBus.get_active_sources().duplicate()
		if not original_active_sources.is_empty():
			print("GameSession: Temporarily disabling ", original_active_sources.size(), " content sources for game start")
			for source_id in original_active_sources:
				ContentBus.set_source_active_state(source_id, false)
			sources_were_disabled = true
	var cleanup_result = owner.call("clean_conversation_history", current_conversation_manager, 150000)
	print("GameSession: Game start history cleanup - kept ", cleanup_result.messages_kept, " messages, ", cleanup_result.total_chars, " chars")
	var response = await current_conversation_manager.chat(intro_prompt)
	if sources_were_disabled and ContentBus:
		print("GameSession: Restoring ", original_active_sources.size(), " content sources after game start")
		for source_id in original_active_sources:
			ContentBus.set_source_active_state(source_id, true)
	if response.success:
		print("GameSession: Game session started successfully with AI response")
		return response.response
	print("GameSession: Failed to start game session with AI: ", response.error)
	if response.has("details"):
		print("GameSession: Additional error details: ", response.details)
	return "Welcome to the game! Let's begin your adventure."


static func parse_ai_response(owner: Node, ai_response: String) -> void:
	print("GameSession: Parsing AI response for multiple speakers")
	print("GameSession: RAW AI RESPONSE:")
	print("=".repeat(50))
	print(ai_response)
	print("=".repeat(50))
	var allowed_map: Dictionary = owner.call("_get_allowed_character_name_map")
	var lines = ai_response.split("\n")
	var current_speaker = ""
	var current_message = ""
	var parsed_messages = []
	for line in lines:
		line = line.strip_edges()
		if line == "":
			if current_speaker != "" and current_message != "":
				current_message = current_message.strip_edges()
				print("GameSession: Parsed message for ", current_speaker, ": ", current_message.substr(0, 50) + "...")
				parsed_messages.append({"sender": current_speaker, "message": current_message})
				current_message = ""
			continue
		if ":" in line:
			var colon_pos = line.find(":")
			var potential_speaker = line.substr(0, colon_pos).strip_edges()
			var canonical := String(owner.call("_canonicalize_speaker", potential_speaker, allowed_map))
			if canonical != "":
				if current_speaker != "" and current_message != "":
					current_message = current_message.strip_edges()
					print("GameSession: Parsed message for ", current_speaker, ": ", current_message.substr(0, 50) + "...")
					parsed_messages.append({"sender": current_speaker, "message": current_message})
				current_speaker = canonical
				current_message = line.substr(colon_pos + 1).strip_edges()
				while current_message.begins_with("(") and ")" in current_message:
					var close_idx2 := current_message.find(")")
					if close_idx2 == -1:
						break
					var after2 := current_message.substr(close_idx2 + 1).strip_edges()
					if after2 == "":
						break
					current_message = after2
				continue
		if NarrationFilterScript.looks_like_environmental_description(line):
			if current_speaker != "" and current_message != "":
				current_message = current_message.strip_edges()
				print("GameSession: Parsed message for ", current_speaker, ": ", current_message.substr(0, 50) + "...")
				parsed_messages.append({"sender": current_speaker, "message": current_message})
			var current_scenario: Dictionary = owner.get("current_scenario")
			var scenario_character_names: Array = owner.call("_collect_declared_speaker_names", current_scenario) if current_scenario else []
			var split_content = NarrationFilterScript.split_mixed_narrator_content(line, scenario_character_names)
			if split_content.size() > 1:
				print("GameSession: Mixed content detected, splitting...")
				for content_piece in split_content:
					if content_piece.has("speaker") and content_piece.has("message"):
						print("GameSession: Split piece - ", content_piece.speaker, ": ", content_piece.message.substr(0, 50) + "...")
						parsed_messages.append({"sender": content_piece.speaker, "message": content_piece.message})
			else:
				print("GameSession: Detected environmental description, attributing to Narrator: ", line.substr(0, 50) + "...")
				parsed_messages.append({"sender": "Narrator", "message": line})
			current_speaker = ""
			current_message = ""
		else:
			if current_message != "":
				current_message += "\n" + line
			else:
				var cont: String = line
				while cont.begins_with("(") and ")" in cont:
					var ci := cont.find(")")
					if ci == -1:
						break
					var rest := cont.substr(ci + 1).strip_edges()
					if rest == "":
						break
					cont = rest
				var re := RegEx.new()
				if re.compile("\\([^)]{1,60}\\)") == OK:
					cont = re.sub(cont, "", true).strip_edges()
				current_message = cont
	if current_speaker != "" and current_message != "":
		current_message = current_message.strip_edges()
		print("GameSession: Parsed message for ", current_speaker, ": ", current_message.substr(0, 50) + "...")
		parsed_messages.append({"sender": current_speaker, "message": current_message})
	for msg in parsed_messages:
		StoryState.add_log_entry(msg.sender, msg.message)
		print("GameSession: Added message to StoryState: ", msg.sender, " - ", msg.message.substr(0, 50) + "...")
		var quality_system: Node = owner.get("quality_system")
		quality_system.monitor_message(msg.sender, msg.message)
		var personality_system: Node = owner.get("personality_system")
		personality_system.analyze_story_events_for_personality_impact(parsed_messages)
	print("GameSession: Calling update_display_from_story_state to display ", parsed_messages.size(), " new messages")
	owner.call("update_display_from_story_state")
