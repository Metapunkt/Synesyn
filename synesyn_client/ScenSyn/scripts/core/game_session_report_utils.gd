extends RefCounted
class_name GameSessionReportUtils

static func get_phase_info(phase: String) -> Dictionary:
	var phase_map := {
		"setup": {"name": "Setup", "progress": 20},
		"incident": {"name": "Incident", "progress": 40},
		"rising": {"name": "Rising Action", "progress": 60},
		"climax": {"name": "Climax", "progress": 80},
		"resolution": {"name": "Resolution", "progress": 100},
		"ended": {"name": "Complete", "progress": 100}
	}
	return phase_map.get(phase, {"name": "Unknown", "progress": 0})

static func get_quality_monitoring_report(owner: Node) -> Dictionary:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_quality_monitoring_report()
	var quality_system = owner.get("quality_system")
	if quality_system:
		return quality_system.get_quality_monitoring_report()
	return {}

static func generate_quality_recommendations(owner: Node) -> Array:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.generate_quality_recommendations()
	var quality_system = owner.get("quality_system")
	if quality_system:
		return quality_system.generate_quality_recommendations()
	return []

static func get_phase3_system_status(owner: Node) -> Dictionary:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_phase3_system_status()
	return {}

static func get_personality_system_status(owner: Node) -> Dictionary:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_personality_system_status()
	var personality_system = owner.get("personality_system")
	if personality_system:
		return personality_system.get_system_status()
	return {
		"total_characters": 0,
		"characters_with_evolution": 0,
		"characters_with_emotions": 0,
		"total_personality_changes": 0,
		"character_profiles": {},
		"evolution_data": {},
		"emotional_states": {}
	}

static func calculate_overall_system_health(owner: Node) -> Dictionary:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.calculate_overall_system_health()
	return {"overall_score": 0.5, "status": "unknown"}

static func generate_system_health_recommendations(owner: Node, health_score: float) -> Array:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.generate_system_health_recommendations(health_score)
	return []

static func test_quality_monitoring_with_sample(owner: Node) -> void:
	var quality_system = owner.get("quality_system")
	if not quality_system:
		print("Quality system not initialized")
		return
	quality_system.test_with_sample_messages()

static func get_comprehensive_session_report(owner: Node) -> Dictionary:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_comprehensive_session_report()
	return {}

static func get_character_analysis_report(owner: Node) -> Dictionary:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_character_analysis_report()
	return {}

static func get_quality_summary_report(owner: Node) -> Dictionary:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_quality_summary_report()
	var quality_system = owner.get("quality_system")
	if quality_system:
		return quality_system.get_quality_summary_report()
	return {}

static func get_most_common_quality_issue(owner: Node) -> String:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_most_common_quality_issue()
	var quality_system = owner.get("quality_system")
	if quality_system:
		return quality_system.get_most_common_quality_issue()
	return "none"

static func get_comprehensive_recommendations(owner: Node) -> Array:
	var reporting_system = owner.get("reporting_system")
	if reporting_system:
		return reporting_system.get_comprehensive_recommendations()
	return []

static func build_allowed_character_name_map(owner: Node, current_scenario: Dictionary) -> Dictionary:
	var name_map: Dictionary = {}
	if current_scenario:
		var declared_names: Array = GameSessionNarrativeUtils.collect_declared_speaker_names(current_scenario)
		for speaker_name in declared_names:
			name_map[String(owner.call("_normalize_loaded_text", String(speaker_name).to_lower()))] = speaker_name
	if Network and Network.has_method("get_player_controlled_character_names"):
		for speaker_name in Network.get_player_controlled_character_names():
			if typeof(speaker_name) == TYPE_STRING and speaker_name.strip_edges() != "":
				name_map[String(owner.call("_normalize_loaded_text", speaker_name.to_lower()))] = speaker_name
	return name_map

static func canonicalize_speaker(owner: Node, potential: String, allowed_map: Dictionary) -> String:
	var token: String = String(owner.call("_normalize_loaded_text", potential)).to_lower()
	token = token.strip_edges()
	while token.begins_with("*"):
		token = token.substr(1)
	while token.ends_with("*"):
		token = token.substr(0, token.length() - 1)
	if allowed_map.has(token):
		return String(allowed_map[token])
	return ""

static func build_narrative_context(owner: Node) -> String:
	var current_story_state: Dictionary = StoryState.get_state()
	var recent_messages: Array = current_story_state.get("story_log", [])
	if recent_messages.size() < 2:
		return ""
	var conversation_system = owner.get("conversation_system")
	return conversation_system.build_narrative_context(recent_messages)

static func inject_sustainability_challenge(owner: Node, challenge: String) -> void:
	var sustainability_system = owner.get("sustainability_system")
	if sustainability_system:
		await sustainability_system.inject_sustainability_challenge(challenge)
	else:
		print("GameSession: ERROR - SustainabilityIntegrationSystem not available for challenge injection")
