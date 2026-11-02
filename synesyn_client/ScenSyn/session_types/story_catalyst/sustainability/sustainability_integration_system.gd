extends RefCounted
class_name SustainabilityIntegrationSystem

# Signals for sustainability events
signal sustainability_metrics_updated(metrics: Dictionary)
signal proactive_action_triggered(domain: String, action: String)
signal challenge_injected(challenge: String)
signal sustainability_alert(message: String, severity: String)

# Dependencies
var network_manager = null
var story_state = null
var sustainability_tracker = null
var metaprompt_manager = null
var conversation_manager = null
var content_bus = null
var phase_manager = null

# Configuration
var include_syntree_context: bool = true
var proactive_action_threshold: float = 0.3
var challenge_injection_threshold: float = 0.25
var challenge_injection_probability: float = 0.33  # 1 in 3 chance

# Tracking
var current_turn: int = 0
var last_proactive_turn: int = 0
var last_challenge_turn: int = 0

func _init(deps: Dictionary):
	"""Initialize with dependency injection"""
	network_manager = deps.get("network_manager")
	story_state = deps.get("story_state")
	sustainability_tracker = deps.get("sustainability_tracker")
	metaprompt_manager = deps.get("metaprompt_manager")
	conversation_manager = deps.get("conversation_manager")
	content_bus = deps.get("content_bus")
	phase_manager = deps.get("phase_manager")
	
	print("SustainabilityIntegrationSystem: Initialized with dependencies")

func set_current_turn(turn: int):
	"""Update current turn counter"""
	current_turn = turn

func on_sustainability_metrics_updated(metrics: Dictionary):
	"""Handle sustainability metrics updates"""
	sustainability_metrics_updated.emit(metrics)
	
	# Enhanced: Dynamic character behavior based on metrics
	if network_manager and network_manager.is_server() and current_turn > 2:
		var overall_score = sustainability_tracker.get_overall_sustainability_score()
		
		# Make AI characters more proactive when sustainability focus is low
		if overall_score < proactive_action_threshold and current_turn % 4 == 0: # Every 4th turn when score is low
			if current_turn != last_proactive_turn:  # Avoid duplicate actions
				trigger_proactive_character_action(metrics)
				last_proactive_turn = current_turn
		
		# Inject sustainability challenges when focus is very low
		if overall_score < challenge_injection_threshold:
			# Only inject challenges occasionally
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			if rng.randi_range(1, 3) == 1 and current_turn != last_challenge_turn:
				var challenge = metaprompt_manager.generate_sustainability_challenge(metrics)
				inject_sustainability_challenge(challenge)
				last_challenge_turn = current_turn

func trigger_proactive_character_action(metrics: Dictionary):
	"""Make AI characters take initiative when sustainability focus is low"""
	# Find the domain that needs the most attention
	var lowest_domain = -1
	var lowest_score = 1.0
	for domain in metrics:
		if metrics[domain] < lowest_score:
			lowest_score = metrics[domain]
			lowest_domain = domain
	
	var proactive_prompt = metaprompt_manager.get_game_session_metaprompt() + "\n\n"
	proactive_prompt += "Current story context: " + build_narrative_context() + "\n\n"
	
	# Get current narrative phase to make content phase-appropriate
	var current_phase = story_state.get_narrative_phase()
	var phase_context = get_phase_appropriate_context(current_phase)
	
	# Build domain-specific proactive action that fits the current narrative phase
	var domain_name = get_domain_name(lowest_domain)
	var action_prompt = build_domain_specific_prompt(lowest_domain, phase_context)
	
	proactive_prompt += action_prompt
	proactive_prompt += "\n\nIMPORTANT: Make this character action feel natural and story-driven, not forced. The character should have a clear motivation for their initiative."
	
	inject_character_action(proactive_prompt, domain_name)

func get_domain_name(domain_index: int) -> String:
	"""Get domain name from index"""
	var domain_names = ["Energy", "Community", "Innovation", "Environment", "Equity"]
	if domain_index >= 0 and domain_index < domain_names.size():
		return domain_names[domain_index]
	return "Sustainability"

func build_domain_specific_prompt(domain_index: int, phase_context: String) -> String:
	"""Build domain-specific proactive action prompt"""
	match domain_index:
		0: # Energy
			return "Have an AI character take initiative regarding energy issues. " + phase_context + " Perhaps they notice something about the power grid, suggest visiting an energy facility, or mention recent energy news affecting Trondheim."
		1: # Community
			return "Have an AI character engage the group about community perspectives. " + phase_context + " Perhaps they suggest meeting with local residents, mention a community event, or bring up neighborhood concerns."
		2: # Innovation
			return "Have an AI character introduce innovative ideas or mention new research from NTNU. " + phase_context + " Perhaps they suggest exploring new technology or propose an innovative solution."
		3: # Environment
			return "Have an AI character draw attention to environmental factors. " + phase_context + " Perhaps they comment on the weather, notice environmental changes, or suggest an outdoor sustainability activity."
		4: # Equity
			return "Have an AI character raise social justice concerns. " + phase_context + " Perhaps they mention how different communities are affected, or suggest ensuring fair access to sustainability benefits."
		_:
			return "Have an AI character take initiative to advance the sustainability discussion in an engaging way that moves the story forward. " + phase_context

func get_phase_appropriate_context(phase: String) -> String:
	"""Get phase-appropriate context for sustainability content"""
	if phase_manager:
		return phase_manager.get_phase_appropriate_context(phase)
	
	# Fallback implementation
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

func build_narrative_context() -> String:
	"""Build narrative context from recent story events"""
	var current_story_state = story_state.get_state()
	var recent_messages = current_story_state.get("story_log", [])
	if recent_messages.size() < 2:
		return ""
	
	# Simple context building - could be enhanced with conversation system
	var context = ""
	var recent_count = min(6, recent_messages.size())  # Last 6 messages
	for i in range(recent_messages.size() - recent_count, recent_messages.size()):
		var entry = recent_messages[i]
		if entry.has("sender") and entry.has("message"):
			context += entry.sender + ": " + entry.message + "\n"
	
	return context

func inject_character_action(prompt: String, domain: String):
	"""Inject proactive character actions"""
	if not conversation_manager:
		print("SustainabilityIntegrationSystem: ERROR - ConversationManager not available for character action")
		return
	
	# Temporarily manage SynTree content sources based on toggle
	var original_active_sources = []
	var sources_were_disabled = false
	
	if not include_syntree_context and content_bus and content_bus.has_method("get_active_sources"):
		original_active_sources = content_bus.get_active_sources().duplicate()
		if not original_active_sources.is_empty():
			for source_id in original_active_sources:
				content_bus.set_source_active_state(source_id, false)
			sources_were_disabled = true
	
	var response = await conversation_manager.chat(prompt)
	
	# Restore original active sources if they were disabled
	if sources_were_disabled and content_bus:
		for source_id in original_active_sources:
			content_bus.set_source_active_state(source_id, true)
	
	if response.success:
		proactive_action_triggered.emit(domain, response.response)
		print("SustainabilityIntegrationSystem: Proactive action triggered for domain: ", domain)
	else:
		print("SustainabilityIntegrationSystem: Failed to inject character action: ", response.error)

func inject_sustainability_challenge(challenge: String):
	"""Inject sustainability challenges into the narrative"""
	if not metaprompt_manager or not conversation_manager:
		print("SustainabilityIntegrationSystem: ERROR - Required managers not available for challenge injection")
		return
	
	var prompt = metaprompt_manager.get_game_session_metaprompt()
	prompt += "\n\nPlease introduce this event into the narrative: " + challenge
	
	var response = await conversation_manager.chat(prompt)
	if response.success:
		challenge_injected.emit(challenge)
		print("SustainabilityIntegrationSystem: Challenge injected: ", challenge)
	else:
		print("SustainabilityIntegrationSystem: Failed to inject sustainability challenge: ", response.error)

func analyze_ai_response_for_sustainability(response: String):
	"""Analyze AI response for sustainability content"""
	if sustainability_tracker:
		sustainability_tracker.analyze_ai_response(response)

func get_overall_sustainability_score() -> float:
	"""Get overall sustainability score"""
	if sustainability_tracker:
		return sustainability_tracker.get_overall_sustainability_score()
	return 0.5  # Default neutral score

func build_continuation_instruction_with_sustainability(user_input: String, character_name: String) -> String:
	"""Build continuation instruction with sustainability context"""
	var instruction = "Please respond as the AI-controlled characters would naturally react to " + character_name + "'s input. "
	instruction += "Maintain character personalities and the current conversation flow. "
	instruction += "Include both character dialogue and narrative description as appropriate. "
	instruction += "Do not speak for " + character_name + " or other player-controlled characters."
	
	# Add sustainability context if score is low
	var overall_score = get_overall_sustainability_score()
	if overall_score < 0.5:
		instruction += " Consider how the energy crisis and sustainability challenges might influence the characters' responses and actions."
	
	return instruction

# Configuration management
func set_syntree_context_enabled(enabled: bool):
	"""Enable or disable SynTree context inclusion"""
	include_syntree_context = enabled

func get_syntree_context_enabled() -> bool:
	"""Get SynTree context inclusion status"""
	return include_syntree_context

func set_proactive_action_threshold(threshold: float):
	"""Set threshold for triggering proactive actions"""
	proactive_action_threshold = clamp(threshold, 0.0, 1.0)

func get_proactive_action_threshold() -> float:
	"""Get proactive action threshold"""
	return proactive_action_threshold

func set_challenge_injection_threshold(threshold: float):
	"""Set threshold for injecting challenges"""
	challenge_injection_threshold = clamp(threshold, 0.0, 1.0)

func get_challenge_injection_threshold() -> float:
	"""Get challenge injection threshold"""
	return challenge_injection_threshold

func set_challenge_injection_probability(probability: float):
	"""Set probability for challenge injection"""
	challenge_injection_probability = clamp(probability, 0.0, 1.0)

func get_challenge_injection_probability() -> float:
	"""Get challenge injection probability"""
	return challenge_injection_probability

# System health and reporting
func get_system_status() -> Dictionary:
	"""Get comprehensive system status"""
	var overall_score = get_overall_sustainability_score()
	var metrics = sustainability_tracker.get_current_metrics() if sustainability_tracker else {}
	
	return {
		"overall_score": overall_score,
		"current_metrics": metrics,
		"configuration": {
			"include_syntree_context": include_syntree_context,
			"proactive_action_threshold": proactive_action_threshold,
			"challenge_injection_threshold": challenge_injection_threshold,
			"challenge_injection_probability": challenge_injection_probability
		},
		"tracking": {
			"current_turn": current_turn,
			"last_proactive_turn": last_proactive_turn,
			"last_challenge_turn": last_challenge_turn
		},
		"system_health": {
			"status": "healthy" if sustainability_tracker else "error",
			"dependencies": {
				"sustainability_tracker": sustainability_tracker != null,
				"metaprompt_manager": metaprompt_manager != null,
				"conversation_manager": conversation_manager != null,
				"content_bus": content_bus != null,
				"phase_manager": phase_manager != null
			}
		}
	}

func get_sustainability_integration_report() -> Dictionary:
	"""Generate comprehensive sustainability integration report"""
	var status = get_system_status()
	
	return {
		"sustainability_integration": {
			"overall_score": status.overall_score,
			"score_category": get_score_category(status.overall_score),
			"current_metrics": status.current_metrics,
			"proactive_actions_triggered": current_turn - last_proactive_turn,
			"challenges_injected": current_turn - last_challenge_turn,
			"configuration": status.configuration,
			"system_health": status.system_health
		},
		"recommendations": _generate_sustainability_recommendations(status)
	}

func get_score_category(score: float) -> String:
	"""Get category description for sustainability score"""
	if score >= 0.8:
		return "Excellent"
	elif score >= 0.6:
		return "Good"
	elif score >= 0.4:
		return "Fair"
	elif score >= 0.2:
		return "Poor"
	else:
		return "Critical"

func _generate_sustainability_recommendations(status: Dictionary) -> Array:
	"""Generate recommendations for sustainability integration"""
	var recommendations = []
	
	var overall_score = status.overall_score
	var config = status.configuration
	var tracking = status.tracking
	var health = status.system_health
	
	# Score-based recommendations
	if overall_score < 0.3:
		recommendations.append("Sustainability score is very low - consider more proactive character actions")
	elif overall_score < 0.5:
		recommendations.append("Sustainability score is below average - encourage more sustainability-focused dialogue")
	elif overall_score > 0.8:
		recommendations.append("Excellent sustainability focus - maintain current engagement level")
	
	# Configuration recommendations
	if config.proactive_action_threshold < 0.2:
		recommendations.append("Proactive action threshold is very low - may trigger too frequently")
	elif config.proactive_action_threshold > 0.5:
		recommendations.append("Proactive action threshold is high - may not trigger enough actions")
	
	# Activity recommendations
	var turns_since_proactive = tracking.current_turn - tracking.last_proactive_turn
	if turns_since_proactive > 10:
		recommendations.append("No proactive actions in " + str(turns_since_proactive) + " turns - consider lowering threshold")
	
	var turns_since_challenge = tracking.current_turn - tracking.last_challenge_turn
	if turns_since_challenge > 20:
		recommendations.append("No challenges injected in " + str(turns_since_challenge) + " turns - consider lowering threshold")
	
	# Health recommendations
	if not health.dependencies.sustainability_tracker:
		recommendations.append("Sustainability tracker is missing - sustainability features will not work")
	if not health.dependencies.metaprompt_manager:
		recommendations.append("Metaprompt manager is missing - cannot generate sustainability challenges")
	if not health.dependencies.conversation_manager:
		recommendations.append("Conversation manager is missing - cannot inject sustainability content")
	
	return recommendations

func get_domain_metrics() -> Dictionary:
	"""Get detailed domain metrics"""
	if sustainability_tracker:
		return sustainability_tracker.get_domain_metrics()
	return {}

func get_sustainability_trends() -> Dictionary:
	"""Get sustainability trends over time"""
	if sustainability_tracker:
		return sustainability_tracker.get_trends()
	return {}

func reset_tracking():
	"""Reset tracking counters"""
	current_turn = 0
	last_proactive_turn = 0
	last_challenge_turn = 0
	print("SustainabilityIntegrationSystem: Tracking reset") 