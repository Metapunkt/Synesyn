extends RefCounted
class_name PhaseManagementSystem

# Signals for phase management events
signal phase_evaluated(phase: String, readiness: float)
signal phase_transition_suggested(phase: String, reason: String)
signal phase_changed(new_phase: String)
signal session_completed()

# Dependencies
var network_manager = null
var story_state = null
var content_bus = null
var conversation_manager = null
var metaprompt_manager = null
var ui_manager = null
var scene_tree = null

# UI elements
var phase_display_label: Label = null
var story_progress_label: Label = null
var story_progress_bar: ProgressBar = null

func _init(deps: Dictionary):
	"""Initialize with dependency injection"""
	network_manager = deps.get("network_manager")
	story_state = deps.get("story_state")
	content_bus = deps.get("content_bus")
	conversation_manager = deps.get("conversation_manager")
	metaprompt_manager = deps.get("metaprompt_manager")
	ui_manager = deps.get("ui_manager")
	scene_tree = deps.get("scene_tree")
	
	print("PhaseManagementSystem: Initialized with dependencies")

# AI evaluation system for phase progression
func run_ai_phase_evaluation():
	"""Run AI evaluation to determine if phase should advance"""
	var current_phase = story_state.get_narrative_phase()
	var turn_in_phase = story_state.get_turn_in_phase()
	
	# Don't evaluate too early or if already at end
	if turn_in_phase < 2 or current_phase == "ended":
		return
	
	# Get recent story context
	var recent_log = story_state.get_recent_log(8)  # Last 8 messages
	var story_context = ""
	for entry in recent_log:
		if entry.has("sender") and entry.has("message"):
			story_context += entry.sender + ": " + entry.message + "\n"
	
	if story_context.strip_edges() == "":
		return
	
	# Build evaluation prompt
	var evaluation_prompt = _build_phase_evaluation_prompt(current_phase, story_context, turn_in_phase)
	
	if not conversation_manager:
		print("PhaseManagementSystem: No conversation manager available for evaluation")
		return
	
	# Temporarily disable content sources for evaluation
	var original_active_sources = []
	var sources_were_disabled = false
	
	if content_bus and content_bus.has_method("get_active_sources"):
		original_active_sources = content_bus.get_active_sources().duplicate()
		if not original_active_sources.is_empty():
			for source_id in original_active_sources:
				content_bus.set_source_active_state(source_id, false)
			sources_were_disabled = true
	
	var response = await conversation_manager.chat(evaluation_prompt)
	
	# Restore content sources
	if sources_were_disabled and content_bus:
		for source_id in original_active_sources:
			content_bus.set_source_active_state(source_id, true)
	
	if response.success:
		var readiness = _parse_phase_readiness_from_ai_response(response.response)
		
		if readiness >= 0.0:  # Valid readiness score
			story_state.set_phase_transition_readiness(readiness)
			phase_evaluated.emit(current_phase, readiness)
		else:
			print("PhaseManagementSystem: Invalid readiness score from AI evaluation")
	else:
		print("PhaseManagementSystem: AI evaluation failed: ", response.error)

func _build_phase_evaluation_prompt(current_phase: String, story_context: String, turn_in_phase: int) -> String:
	"""Build the evaluation prompt for phase readiness assessment"""
	var nl := "\n"
	var prompt := "NARRATIVE PHASE EVALUATION TASK" + nl + nl
	prompt += "You are evaluating whether a story is ready to advance from the current narrative phase to the next phase." + nl + nl
	prompt += "CURRENT PHASE: " + current_phase.to_upper() + nl
	prompt += "TURNS IN PHASE: " + str(turn_in_phase) + nl + nl
	prompt += "PHASE DEFINITIONS:" + nl
	prompt += "- SETUP: Introduction, character establishment, world-building" + nl
	prompt += "- INCIDENT: The inciting incident or main problem is introduced" + nl
	prompt += "- RISING: Complications develop, tensions rise, stakes increase" + nl
	prompt += "- CLIMAX: The main conflict reaches its peak, critical decisions made" + nl
	prompt += "- RESOLUTION: Consequences play out, conflicts resolve, story concludes" + nl + nl
	prompt += "RECENT STORY CONTEXT:" + nl + story_context + nl + nl
	prompt += "EVALUATION CRITERIA:" + nl
	prompt += "Rate readiness to advance (0.0 = not ready, 1.0 = fully ready):" + nl + nl
	prompt += "For " + current_phase.to_upper() + " → " + _get_next_phase_name(current_phase).to_upper() + ":" + nl
	prompt += "- Has the current phase fulfilled its narrative purpose?" + nl
	prompt += "- Are there clear signs the story is naturally progressing toward the next phase?" + nl
	prompt += "- Would advancing now feel organic and well-paced?" + nl + nl
	prompt += "RESPONSE FORMAT:" + nl
	prompt += "Provide ONLY a readiness score between 0.0 and 1.0, followed by a brief explanation." + nl
	prompt += "Example: \"0.7 - The setup is mostly complete but could use one more interaction to establish the main conflict.\"" + nl + nl
	prompt += "READINESS SCORE:"
	return prompt

func _get_next_phase_name(current_phase: String) -> String:
	"""Get the name of the next phase in the sequence"""
	var next_phase_map = {
		"setup": "incident",
		"incident": "rising", 
		"rising": "climax",
		"climax": "resolution",
		"resolution": "ended"
	}
	return next_phase_map.get(current_phase, "ended")

func _parse_phase_readiness_from_ai_response(ai_response: String) -> float:
	"""Parse readiness score from AI response"""
	var regex = RegEx.new()
	regex.compile("^\\s*([0-9]*\\.?[0-9]+)")
	var result = regex.search(ai_response)
	
	if result:
		var score_str = result.get_string(1)
		var score = float(score_str)
		
		# Validate score is in valid range
		if score >= 0.0 and score <= 1.0:
			return score
		else:
			print("PhaseManagementSystem: Score out of range: ", score)
			return -1.0
	else:
		print("PhaseManagementSystem: Could not parse readiness score from response")
		return -1.0

# Phase transition management
func suggest_phase_transition(suggested_phase: String, reason: String = ""):
	"""Handle phase transition suggestion"""
	if not network_manager or not network_manager.is_server():
		return
	
	print("PhaseManagementSystem: Received phase transition suggestion: ", suggested_phase, " (reason: ", reason, ")")
	phase_transition_suggested.emit(suggested_phase, reason)

func suggest_narrative_phase_transition(phase: String, reason: String = ""):
	"""Client-side method to suggest a phase transition to the server"""
	if not network_manager:
		return
		
	if network_manager.is_server():
		# If we're the server, handle directly
		suggest_phase_transition(phase, reason)
	else:
		# If we're a client, send RPC to server
		# This would need to be implemented in the network manager
		pass

# Session completion management
func check_session_completion():
	"""Check if the session has ended and handle accordingly"""
	var current_phase = story_state.get_narrative_phase()
	if current_phase == "ended":
		handle_session_ended()

func handle_session_ended():
	"""Handle session completion"""
	print("PhaseManagementSystem: Session has ended")
	session_completed.emit()

func start_new_scenario():
	"""Restart the session with a new scenario"""
	# Reset narrative phase to setup
	story_state.set_narrative_phase("setup")
	story_state.reset()
	
	print("PhaseManagementSystem: Ready for new scenario")

# UI Management
func setup_phase_display(parent_node: Node):
	"""Create and position the narrative phase display label"""
	print("PhaseManagementSystem: Setting up phase display...")
	
	# Safety check: Ensure story_state is available
	if not story_state:
		print("PhaseManagementSystem: WARNING - story_state not available, skipping phase display setup")
		return
	
	# Safety check: Ensure story_state methods are available
	if not story_state.has_method("get_narrative_phase") or not story_state.has_method("get_turn_in_phase"):
		print("PhaseManagementSystem: WARNING - story_state methods not available, skipping phase display setup")
		return

	# Prefer a scene-defined label (%PhaseDisplayLabel) so layout/theme is controlled in the editor.
	var existing: Node = parent_node.get_node_or_null("%PhaseDisplayLabel")
	if existing == null or not (existing is Label):
		push_error("PhaseManagementSystem: Missing required %PhaseDisplayLabel (Label) in scene.")
		return

	phase_display_label = existing as Label
	print("PhaseManagementSystem: Using existing %PhaseDisplayLabel from scene.")

	# Keep the label updated even when the phase hasn't changed (turns increment).
	if story_state and story_state.has_signal("state_updated"):
		var cb := Callable(self, "_on_story_state_updated_for_phase_display")
		if not story_state.state_updated.is_connected(cb):
			story_state.state_updated.connect(cb)
	
	print("PhaseManagementSystem: Updating phase display...")
	update_phase_display()
	
	print("PhaseManagementSystem: Phase display setup completed successfully")

func _on_story_state_updated_for_phase_display(_new_state: Dictionary) -> void:
	# Refresh label on every state update so "(X turns)" increments.
	update_phase_display()

func update_phase_display():
	"""Update the phase display label with the current narrative phase"""
	if not phase_display_label:
		print("PhaseManagementSystem: Phase display label not available")
		return
	
	# Safety check: Ensure story_state is available
	if not story_state:
		print("PhaseManagementSystem: WARNING - story_state not available for phase display update")
		phase_display_label.text = "Phase: Unknown"
		return
	
	# Safety check: Ensure story_state methods are available
	if not story_state.has_method("get_narrative_phase") or not story_state.has_method("get_turn_in_phase"):
		print("PhaseManagementSystem: WARNING - story_state methods not available for phase display update")
		phase_display_label.text = "Phase: Unknown"
		return
	
	var current_phase = story_state.get_narrative_phase()
	var turn_in_phase = story_state.get_turn_in_phase()
	
	# Capitalize and format phase name
	var formatted_phase = current_phase.capitalize()
	phase_display_label.text = "Phase: " + formatted_phase + " (" + str(turn_in_phase) + " turns)"
	
	print("PhaseManagementSystem: Phase display updated to: ", phase_display_label.text)

func on_narrative_phase_changed(new_phase: String):
	"""Handle narrative phase changes"""
	print("PhaseManagementSystem: Narrative phase changed to: ", new_phase)
	update_phase_display()
	update_story_progress_display(new_phase)
	
	# Trigger visual presentation transitions for phase changes
	_trigger_visual_phase_transition(new_phase)
	
	phase_changed.emit(new_phase)

func setup_story_progress_display(progress_label: Label, progress_bar: ProgressBar):
	"""Initialize story progress display elements"""
	print("PhaseManagementSystem: Setting up story progress display...")
	story_progress_label = progress_label
	story_progress_bar = progress_bar
	
	if story_progress_label and story_progress_bar:
		# Initialize with current phase
		var current_phase = story_state.get_narrative_phase() if story_state else "setup"
		update_story_progress_display(current_phase)
		print("PhaseManagementSystem: Story progress display initialized with phase: ", current_phase)
	else:
		print("PhaseManagementSystem: WARNING - Story progress elements not found")

func update_story_progress_display(phase: String):
	"""Update story progress display based on narrative phase"""
	if not story_progress_label or not story_progress_bar:
		return
	
	var phase_info = _get_phase_info(phase)
	story_progress_label.text = "Story progress: " + str(phase_info.progress) + "% (" + phase_info.name + ")"
	story_progress_bar.value = phase_info.progress

func _get_phase_info(phase: String) -> Dictionary:
	"""Get phase information for display"""
	var phase_map = {
		"setup": {"name": "Setup", "progress": 20},
		"incident": {"name": "Incident", "progress": 40},
		"rising": {"name": "Rising Action", "progress": 60},
		"climax": {"name": "Climax", "progress": 80},
		"resolution": {"name": "Resolution", "progress": 100},
		"ended": {"name": "Complete", "progress": 100}
	}
	return phase_map.get(phase, {"name": "Unknown", "progress": 0})

func get_phase_appropriate_context(phase: String) -> String:
	"""Get context appropriate for the current narrative phase"""
	match phase:
		"setup":
			return "Keep this introduction-level and exploratory, setting up the foundation for later conflict."
		"incident":
			return "Present this as the central crisis or challenge that requires immediate attention."
		"rising":
			return "Escalate the complexity and show competing perspectives or difficult trade-offs."
		"climax":
			return "Make this urgent and decisive - characters must choose their course of action now."
		"resolution":
			return "Focus on the consequences and outcomes of previous decisions."
		"ended":
			return "Provide closure and reflection on the overall experience."
		_:
			return "Integrate this naturally into the current story flow."

# System health and reporting
func get_system_status() -> Dictionary:
	"""Get comprehensive system status"""
	var current_phase = story_state.get_narrative_phase() if story_state else "unknown"
	var turn_in_phase = story_state.get_turn_in_phase() if story_state else 0
	var readiness = story_state.get_phase_transition_readiness() if story_state else 0.0
	
	return {
		"current_phase": current_phase,
		"turn_in_phase": turn_in_phase,
		"transition_readiness": readiness,
		"next_phase": _get_next_phase_name(current_phase),
		"phase_info": _get_phase_info(current_phase),
		"system_health": {
			"status": "healthy" if story_state else "error",
			"ui_elements": {
				"phase_display": phase_display_label != null,
				"progress_display": story_progress_label != null and story_progress_bar != null
			}
		}
	}

func get_phase_management_report() -> Dictionary:
	"""Generate comprehensive phase management report"""
	var status = get_system_status()
	
	return {
		"phase_management": {
			"current_phase": status.current_phase,
			"phase_progress": status.phase_info.progress,
			"turns_in_phase": status.turn_in_phase,
			"transition_readiness": status.transition_readiness,
			"next_phase": status.next_phase,
			"system_health": status.system_health
		},
		"recommendations": _generate_phase_recommendations(status)
	}

func _generate_phase_recommendations(status: Dictionary) -> Array:
	"""Generate recommendations for phase management"""
	var recommendations = []
	
	var current_phase = status.current_phase
	var turn_in_phase = status.turn_in_phase
	var readiness = status.transition_readiness
	
	# Phase-specific recommendations
	if current_phase == "setup" and turn_in_phase > 8:
		recommendations.append("Setup phase has been running for many turns - consider advancing to incident phase")
	elif current_phase == "incident" and readiness > 0.8:
		recommendations.append("Incident phase shows high readiness - story may be ready for rising action")
	elif current_phase == "rising" and turn_in_phase > 10:
		recommendations.append("Rising action has been extended - consider building toward climax")
	elif current_phase == "climax" and readiness > 0.7:
		recommendations.append("Climax phase shows readiness - story may be ready for resolution")
	
	# System health recommendations
	if not status.system_health.ui_elements.phase_display:
		recommendations.append("Phase display UI element is missing - consider recreating")
	if not status.system_health.ui_elements.progress_display:
		recommendations.append("Progress display UI elements are missing - consider recreating")
	
	return recommendations

## Trigger visual presentation transitions for narrative phase changes
func _trigger_visual_phase_transition(new_phase: String):
	"""Trigger visual effects when narrative phases change"""
	
	# Check if scene tree is available
	if not scene_tree:
		print("PhaseManagementSystem: No scene tree available for phase transition")
		return
	
	# Find visual integration system
	var visual_integration = scene_tree.get_first_node_in_group("visual_integration")
	if not visual_integration:
		print("PhaseManagementSystem: No visual integration found for phase transition")
		return
	
	# Get visual presentation manager
	if not visual_integration.has_method("is_visual_presentation_ready") or not visual_integration.is_visual_presentation_ready():
		print("PhaseManagementSystem: Visual presentation not ready for phase transition")
		return
	
	var visual_manager = visual_integration.visual_presentation_manager
	if not visual_manager:
		return
	
	# Get scene manager for transitions
	var scene_manager = visual_manager.scene_manager
	if scene_manager and scene_manager.has_method("transition_for_narrative_phase"):
		var transition_context = {
			"phase": new_phase,
			"trigger": "narrative_phase_change",
			"timestamp": Time.get_unix_time_from_system()
		}
		scene_manager.transition_for_narrative_phase(new_phase, transition_context)
		print("PhaseManagementSystem: Triggered visual transition for phase: ", new_phase)
	else:
		print("PhaseManagementSystem: Scene manager not available for phase transitions") 
