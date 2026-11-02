@tool
extends BTAction
class_name DetermineNarratorIntentTask

# Decides narrator intent each tick and triggers narration via agent.

# Phases thresholds (mirroring previous constants)
const PHASE_INTRO_END_TURN := 3

func _tick(_delta: float) -> int:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var story_state_node: Variant = tree.root.get_node_or_null("StoryState") if tree else null
	if not story_state_node or not story_state_node.has_method("get_state"):
		return BT.Status.FAILURE
	var state: Dictionary = story_state_node.get_state()
	var turn: int = int(state.get("current_turn", 0))
	var phase: String = state.get("current_phase", "introduction")
	var narrative_phase: String = state.get("current_narrative_phase", "setup")
	var intent: String = "SILENT"
	
	# Map narrative phases to specific intents
	match narrative_phase:
		"setup":
			if turn >= 2:  # Allow some setup time
				intent = "SETUP_SCENE"
		"incident":
			intent = "INCIDENT_BEAT"
		"rising":
			if turn % 2 == 0:  # Periodic tension building
				intent = "RISING_TENSION"
		"climax":
			intent = "CLIMAX_BEAT"
		"resolution":
			intent = "RESOLUTION_BEAT"
		"ended":
			intent = "SILENT"  # Don't narrate ended stories
	
	# Legacy phase handling for backward compatibility
	if intent == "SILENT":
		if phase == "introduction" and turn >= PHASE_INTRO_END_TURN:
			intent = "SET_SCENE_TRANSITION"
		elif phase == "crisis":
			if turn % 3 == 0:
				intent = "ESCALATE_TENSION"
	
	# Access NarratorAgent via blackboard
	var narrator = blackboard.get_var("narrator_node")
	if narrator and narrator.has_method("_maybe_generate_narration"):
		narrator._maybe_generate_narration(intent, state)
	return BT.Status.SUCCESS 
