@tool
extends BTTask
class_name AdvanceStoryPhaseTask

# Analyzes story state and advances narrative phases when transition criteria are met.
# Uses text-based detection to maintain immersion while preventing endless loops.

# Phase transition constants
const MIN_TURNS_PER_PHASE = 2  # Minimum turns before considering transition
const GRACE_PERIOD_TURNS = 2   # Extra turns allowed before forced transition
const MAX_TURNS_SETUP = 4      # Maximum turns in setup phase
const MAX_TURNS_INCIDENT = 5   # Maximum turns in incident phase
const MAX_TURNS_RISING = 6     # Maximum turns in rising action
const MAX_TURNS_CLIMAX = 3     # Maximum turns in climax
const MAX_TURNS_RESOLUTION = 3 # Maximum turns in resolution

# Keywords for transition detection
const TRANSITION_KEYWORDS = {
	"setup_to_incident": ["crisis", "problem", "challenge", "urgent", "emergency", "conflict"],
	"incident_to_rising": ["decide", "choose", "options", "what if", "consider", "debate"],
	"rising_to_climax": ["vote", "decision", "agree", "consensus", "final", "choose now"],
	"climax_to_resolution": ["decided", "chosen", "resolved", "outcome", "result"],
	"resolution_to_ended": ["complete", "finished", "end", "conclusion", "summary", "done"]
}

func _tick(_delta: float) -> int:
	# Only run on server to prevent conflicts
	if not _is_server():
		return BT.Status.SUCCESS
	
	var state: Dictionary = StoryState.get_state()
	var current_phase: String = state.get("current_narrative_phase", "setup")
	var turn_in_phase: int = state.get("turn_in_phase", 0)
	var current_turn: int = state.get("current_turn", 0)
	
	# Skip if not enough turns in current phase
	if turn_in_phase < MIN_TURNS_PER_PHASE:
		return BT.Status.SUCCESS
	
	# Check for transition readiness
	var should_transition = false
	var next_phase = ""
	
	match current_phase:
		"setup":
			should_transition = _check_setup_transition(state, turn_in_phase)
			next_phase = "incident"
		"incident":
			should_transition = _check_incident_transition(state, turn_in_phase)
			next_phase = "rising"
		"rising":
			should_transition = _check_rising_transition(state, turn_in_phase)
			next_phase = "climax"
		"climax":
			should_transition = _check_climax_transition(state, turn_in_phase)
			next_phase = "resolution"
		"resolution":
			should_transition = _check_resolution_transition(state, turn_in_phase)
			next_phase = "ended"
		"ended":
			# Stay in ended phase
			return BT.Status.SUCCESS
	
	if should_transition and next_phase != "":
		print("AdvanceStoryPhaseTask: Transitioning from ", current_phase, " to ", next_phase)
		StoryState.set_narrative_phase(next_phase)
		
		# Trigger phase transition event for other systems
		StoryState.trigger_event("phase_transition", {
			"from": current_phase,
			"to": next_phase,
			"turn": current_turn
		})
	
	return BT.Status.SUCCESS

func _check_setup_transition(state: Dictionary, turn_in_phase: int) -> bool:
	# Transition when first dilemma is injected OR max turns reached
	var dilemmas = state.get("dilemmas", [])
	if dilemmas.size() > 0:
		return true
	
	# Force transition after max turns
	if turn_in_phase >= MAX_TURNS_SETUP:
		return true
		
	# Check for crisis keywords in recent dialogue
	return _has_transition_keywords(state, "setup_to_incident")

func _check_incident_transition(state: Dictionary, turn_in_phase: int) -> bool:
	# Transition when sustainability drops OR unresolved challenges exist
	var sustainability = state.get("sustainability", {})
	var energy_level = sustainability.get("energy_level", 100)
	if energy_level < 40:  # 40% threshold
		return true
	
	var challenges = state.get("unresolved_challenges", [])
	if challenges.size() > 0:
		return true
	
	# Force transition after max turns
	if turn_in_phase >= MAX_TURNS_INCIDENT:
		return true
		
	# Check for decision keywords
	return _has_transition_keywords(state, "incident_to_rising")

func _check_rising_transition(state: Dictionary, turn_in_phase: int) -> bool:
	# Transition when decision keywords appear OR player choice is logged
	var choices = state.get("player_choices", [])
	if choices.size() > 0:
		# Check if any choice was made in recent turns
		var recent_choices = choices.filter(func(choice): return choice.get("turn", 0) >= StoryState.get_state().get("current_turn", 0) - 3)
		if recent_choices.size() > 0:
			return true
	
	# Force transition after max turns
	if turn_in_phase >= MAX_TURNS_RISING:
		return true
		
	# Check for consensus/decision keywords
	return _has_transition_keywords(state, "rising_to_climax")

func _check_climax_transition(state: Dictionary, turn_in_phase: int) -> bool:
	# Transition after 1 turn of climax narration OR max turns
	if turn_in_phase >= MAX_TURNS_CLIMAX:
		return true
		
	# Check for resolution keywords
	return _has_transition_keywords(state, "climax_to_resolution")

func _check_resolution_transition(state: Dictionary, turn_in_phase: int) -> bool:
	# Transition when no new challenges for 2 turns OR narrator provides summary
	var challenges = state.get("unresolved_challenges", [])
	var inactive_turns = state.get("inactive_turns", 0)
	
	if challenges.size() == 0 and inactive_turns >= 2:
		return true
	
	# Force transition after max turns
	if turn_in_phase >= MAX_TURNS_RESOLUTION:
		return true
		
	# Check for ending keywords
	return _has_transition_keywords(state, "resolution_to_ended")

func _has_transition_keywords(state: Dictionary, transition_type: String) -> bool:
	var keywords = TRANSITION_KEYWORDS.get(transition_type, [])
	if keywords.is_empty():
		return false
	
	# Check recent log entries for keywords
	var recent_log = state.get("story_log", [])
	if recent_log.size() < 3:
		return false
	
	var recent_entries = recent_log.slice(-3)  # Last 3 entries
	for entry in recent_entries:
		var message = entry.get("message", "").to_lower()
		for keyword in keywords:
			if keyword in message:
				return true
	
	return false

func _is_server() -> bool:
	# Check if we're running on server (for multiplayer compatibility)
	if not Network:
		return true  # Single player
	return Network.is_server()

# Handle client-suggested transitions (called via RPC)
func handle_client_suggestion(suggested_phase: String, reason: String) -> void:
	if not _is_server():
		return
	
	var current_phase = StoryState.get_narrative_phase()
	var turn_in_phase = StoryState.get_turn_in_phase()
	
	# Validate suggestion (must be next logical phase)
	var valid_suggestion = false
	match current_phase:
		"setup":
			valid_suggestion = suggested_phase == "incident"
		"incident":
			valid_suggestion = suggested_phase == "rising"
		"rising":
			valid_suggestion = suggested_phase == "climax"
		"climax":
			valid_suggestion = suggested_phase == "resolution"
		"resolution":
			valid_suggestion = suggested_phase == "ended"
	
	# Accept suggestion if valid and minimum turns met
	if valid_suggestion and turn_in_phase >= MIN_TURNS_PER_PHASE:
		print("AdvanceStoryPhaseTask: Accepting client suggestion to transition to ", suggested_phase, " (reason: ", reason, ")")
		StoryState.set_narrative_phase(suggested_phase)
		StoryState.trigger_event("phase_transition", {
			"from": current_phase,
			"to": suggested_phase,
			"turn": StoryState.get_state().get("current_turn", 0),
			"client_suggested": true,
			"reason": reason
		}) 