extends RefCounted
class_name SessionReportingSystem

# Signals for reporting events
signal report_generated(report_type: String, report_data: Dictionary)
signal system_health_updated(health_score: float, status: String)
signal recommendations_generated(recommendations: Array)

# Dependencies
var quality_system = null
var personality_system = null
var adaptive_system = null
var phase_system = null
var sustainability_system = null
var network_manager = null
var story_state = null

func _init(deps: Dictionary):
	"""Initialize with dependency injection"""
	quality_system = deps.get("quality_system")
	personality_system = deps.get("personality_system")
	adaptive_system = deps.get("adaptive_system")
	phase_system = deps.get("phase_system")
	sustainability_system = deps.get("sustainability_system")
	network_manager = deps.get("network_manager")
	story_state = deps.get("story_state")
	
	print("SessionReportingSystem: Initialized with dependencies")

func get_comprehensive_session_report() -> Dictionary:
	"""Generate a comprehensive report of the entire session"""
	var quality_report = get_quality_monitoring_report()
	var report = {
		"session_info": {
			"start_time": quality_report.get("session_start_time", 0),
			"duration": quality_report.get("session_duration", 0),
			"total_messages": quality_report.get("total_messages", 0)
		},
		"phase3_systems": get_phase3_system_status(),
		"character_analysis": get_character_analysis_report(),
		"quality_summary": get_quality_summary_report(),
		"recommendations": get_comprehensive_recommendations()
	}
	
	report_generated.emit("comprehensive", report)
	return report

func get_quality_monitoring_report() -> Dictionary:
	"""Get quality monitoring report from quality system"""
	if not quality_system:
		return {}
	return quality_system.get_quality_monitoring_report()

func generate_quality_recommendations() -> Array:
	"""Generate recommendations based on quality monitoring"""
	if not quality_system:
		return []
	return quality_system.generate_quality_recommendations()

func get_phase3_system_status() -> Dictionary:
	"""Get comprehensive status of all Phase 3 systems"""
	var status = {
		"timestamp": Time.get_unix_time_from_system(),
		"personality_system": get_personality_system_status(),
		"quality_monitoring": get_quality_monitoring_report(),
		"adaptive_response": get_adaptive_response_report(),
		"overall_health": calculate_overall_system_health()
	}
	
	return status

func get_personality_system_status() -> Dictionary:
	"""Get status of the personality modeling system"""
	if not personality_system:
		return {
			"total_characters": 0,
			"characters_with_evolution": 0,
			"characters_with_emotions": 0,
			"total_personality_changes": 0,
			"character_profiles": {},
			"evolution_data": {},
			"emotional_states": {}
		}
	
	return personality_system.get_system_status()

func get_adaptive_response_report() -> Dictionary:
	"""Get adaptive response system report"""
	if not adaptive_system:
		return {}
	return adaptive_system.get_adaptive_response_report()

func calculate_overall_system_health() -> Dictionary:
	"""Calculate overall health of all Phase 3 systems"""
	var personality_health = 1.0 if personality_system and personality_system.get_system_status().total_characters > 0 else 0.0
	var quality_health = quality_system.get_system_health() if quality_system else 0.5
	var adaptive_health = adaptive_system.calculate_overall_adaptation_effectiveness() if adaptive_system else 0.5
	
	var overall_health = (personality_health + quality_health + adaptive_health) / 3.0
	
	var health_status = "excellent"
	if overall_health < 0.3:
		health_status = "critical"
	elif overall_health < 0.5:
		health_status = "poor"
	elif overall_health < 0.7:
		health_status = "fair"
	elif overall_health < 0.9:
		health_status = "good"
	
	var health_data = {
		"overall_score": overall_health,
		"status": health_status,
		"personality_health": personality_health,
		"quality_health": quality_health,
		"adaptive_health": adaptive_health,
		"recommendations": generate_system_health_recommendations(overall_health)
	}
	
	system_health_updated.emit(overall_health, health_status)
	return health_data

func generate_system_health_recommendations(health_score: float) -> Array:
	"""Generate recommendations based on system health"""
	var recommendations = []
	
	if health_score < 0.5:
		recommendations.append("CRITICAL: System health is low. Review all quality metrics and adaptations.")
	
	# Check specific system health
	var personality_health = 1.0 if personality_system and personality_system.get_system_status().total_characters > 0 else 0.0
	if personality_health < 0.5:
		recommendations.append("Personality system needs attention - ensure character profiles are properly initialized.")
	
	var quality_health = quality_system.get_system_health() if quality_system else 0.5
	if quality_health < 0.5:
		recommendations.append("Quality monitoring shows low dialogue quality - review recent messages and adaptations.")
	
	var adaptive_health = adaptive_system.calculate_overall_adaptation_effectiveness() if adaptive_system else 0.5
	if adaptive_health < 0.5:
		recommendations.append("Adaptive response system may not be working effectively - review adaptation triggers.")
	
	if health_score > 0.8:
		recommendations.append("System health is excellent - maintain current quality standards.")
	
	recommendations_generated.emit(recommendations)
	return recommendations

func get_character_analysis_report() -> Dictionary:
	"""Generate detailed character analysis report"""
	var character_report = {}
	
	if not personality_system:
		return character_report
	
	var status = personality_system.get_system_status()
	var quality_report = get_quality_monitoring_report()
	
	for character_name in status.character_profiles.keys():
		var profile = status.character_profiles[character_name]
		var evolution = status.evolution_data.get(character_name, {})
		var emotions = status.emotional_data.get(character_name, {})
		var quality_perf = quality_report.get("character_performance", {}).get(character_name, {})
		
		character_report[character_name] = {
			"personality_type": profile.get("personality_type", "unknown"),
			"communication_style": profile.get("communication_style", "unknown"),
			"current_stress_level": evolution.get("stress_level", 0.5),
			"current_confidence": evolution.get("confidence_level", 0.5),
			"current_emotion": emotions.get("current_emotion", "neutral"),
			"dialogue_quality": quality_perf.get("dialogue_quality_score", 0.5),
			"voice_consistency": quality_perf.get("voice_consistency_score", 1.0),
			"recent_personality_shifts": evolution.get("personality_shifts", []).size(),
			"recent_issues": quality_perf.get("recent_issues", [])
		}
	
	return character_report

func get_quality_summary_report() -> Dictionary:
	"""Generate quality summary report"""
	if not quality_system:
		return {}
	return quality_system.get_quality_summary_report()

func get_most_common_quality_issue() -> String:
	"""Get the most common quality issue"""
	if not quality_system:
		return "none"
	return quality_system.get_most_common_quality_issue()

func get_comprehensive_recommendations() -> Array:
	"""Generate comprehensive recommendations for session improvement"""
	var recommendations = []
	
	# Add quality recommendations
	recommendations.append_array(generate_quality_recommendations())
	
	# Add system health recommendations
	var system_health = calculate_overall_system_health()
	recommendations.append_array(system_health.recommendations)
	
	# Add character-specific recommendations
	if personality_system and quality_system:
		var status = personality_system.get_system_status()
		var quality_report = get_quality_monitoring_report()
		for character_name in status.character_profiles.keys():
			var quality_perf = quality_report.get("character_performance", {}).get(character_name, {})
			var recent_issues = quality_perf.get("recent_issues", [])
			
			if recent_issues.size() > 3:
				recommendations.append("Character " + character_name + " has frequent quality issues - review dialogue patterns")
			
			var dialogue_quality = quality_perf.get("dialogue_quality_score", 0.5)
			if dialogue_quality < 0.4:
				recommendations.append("Character " + character_name + " dialogue quality is low - enhance voice consistency")
	
	# Add phase management recommendations
	if phase_system:
		var phase_report = phase_system.get_phase_management_report()
		recommendations.append_array(phase_report.get("recommendations", []))
	
	# Add sustainability recommendations only for sustainability theme
	if Global and Global.current_collection_id == "sustainability" and sustainability_system:
		var sustainability_report = sustainability_system.get_sustainability_integration_report()
		recommendations.append_array(sustainability_report.get("recommendations", []))
	
	return recommendations

# System health and status monitoring
func get_system_status() -> Dictionary:
	"""Get comprehensive system status"""
	return {
		"reporting_system": {
			"status": "healthy",
			"dependencies": {
				"quality_system": quality_system != null,
				"personality_system": personality_system != null,
				"adaptive_system": adaptive_system != null,
				"phase_system": phase_system != null,
				"sustainability_system": sustainability_system != null,
				"network_manager": network_manager != null,
				"story_state": story_state != null
			}
		},
		"overall_health": calculate_overall_system_health(),
		"last_report_time": Time.get_unix_time_from_system()
	}

func get_session_analytics() -> Dictionary:
	"""Get session analytics data"""
	var analytics = {
		"session_duration": 0,
		"total_interactions": 0,
		"system_performance": {},
		"quality_trends": {},
		"character_activity": {}
	}
	
	# Get data from quality system
	if quality_system:
		var quality_report = get_quality_monitoring_report()
		analytics.session_duration = quality_report.get("session_duration", 0)
		analytics.total_interactions = quality_report.get("total_messages", 0)
		analytics.quality_trends = quality_report.get("quality_trends", {})
	
	# Get character activity from personality system
	if personality_system:
		var personality_status = personality_system.get_system_status()
		analytics.character_activity = personality_status.get("character_profiles", {})
	
	# Get system performance metrics
	analytics.system_performance = calculate_overall_system_health()
	
	return analytics

func generate_session_summary() -> String:
	"""Generate a human-readable session summary"""
	var report = get_comprehensive_session_report()
	var summary = "=== SESSION SUMMARY ===\n\n"
	
	# Session info
	var session_info = report.get("session_info", {})
	summary += "Duration: " + str(session_info.get("duration", 0)) + " minutes\n"
	summary += "Total Messages: " + str(session_info.get("total_messages", 0)) + "\n\n"
	
	# System health
	var health = report.get("phase3_systems", {}).get("overall_health", {})
	summary += "Overall System Health: " + health.get("status", "unknown").capitalize() + "\n"
	summary += "Health Score: " + str(int(health.get("overall_score", 0.0) * 100)) + "%\n\n"
	
	# Key recommendations
	var recommendations = report.get("recommendations", [])
	if recommendations.size() > 0:
		summary += "Key Recommendations:\n"
		for i in range(min(3, recommendations.size())):  # Top 3 recommendations
			summary += "- " + recommendations[i] + "\n"
	
	return summary 