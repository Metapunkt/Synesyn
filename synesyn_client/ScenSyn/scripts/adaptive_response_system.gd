extends RefCounted
class_name AdaptiveResponseSystem

# Signal definitions
signal adaptation_applied(character_name: String, adjustments: Array)
signal effectiveness_updated(character_name: String, effectiveness: float)
signal system_health_changed(health_score: float)

# Core adaptive response data
var adaptive_response_system = {}
var response_adjustment_history = []

# Dependencies (injected from game session)
var network_manager = null
var quality_system = null
var personality_system = null

func _init():
	"""Initialize the adaptive response system"""
	initialize_system()

func initialize_system():
	"""Initialize the adaptive response system"""
	adaptive_response_system = {
		"adaptation_level": 0.5,  # 0.0 = minimal adaptation, 1.0 = maximum adaptation
		"response_patterns": {
			"low_quality_detected": "increase_guidance",
			"declining_trend": "enhance_structure",
			"character_inconsistency": "strengthen_voice",
			"repetitive_patterns": "diversify_language",
			"immersion_breaks": "focus_narrative"
		},
		"adaptation_thresholds": {
			"minor_adjustment": 0.3,
			"moderate_adjustment": 0.6,
			"major_adjustment": 0.8
		},
		"current_adaptations": {},
		"adaptation_effectiveness": {}
	}
	
	# Initialize adaptation tracking for each AI character
	if network_manager:
		var ai_controlled_names = network_manager.get_ai_controlled_character_names()
		for character_name in ai_controlled_names:
			adaptive_response_system.current_adaptations[character_name] = {
				"guidance_level": "standard",  # "minimal", "standard", "enhanced", "maximum"
				"structure_emphasis": "balanced",  # "loose", "balanced", "structured", "rigid"
				"voice_reinforcement": "normal",  # "minimal", "normal", "enhanced", "maximum"
				"language_diversity": "standard",  # "basic", "standard", "enhanced", "maximum"
				"narrative_focus": "balanced"  # "loose", "balanced", "focused", "strict"
			}
			
			adaptive_response_system.adaptation_effectiveness[character_name] = {
				"recent_adjustments": [],
				"success_rate": 0.5,
				"quality_improvement": 0.0
			}
	
	print("AdaptiveResponseSystem: System initialized")

func set_dependencies(network_mgr, quality_sys, personality_sys):
	"""Set system dependencies"""
	network_manager = network_mgr
	quality_system = quality_sys
	personality_system = personality_sys
	
	# Re-initialize with proper dependencies
	initialize_system()

func adapt_response_based_on_quality(character_name: String, quality_issues: Array, quality_score: float):
	"""Adapt AI response behavior based on detected quality issues"""
	if not adaptive_response_system.current_adaptations.has(character_name):
		return
	
	var adaptations = adaptive_response_system.current_adaptations[character_name]
	var adjustments_made = []
	
	# Determine adaptation intensity based on quality score
	var adaptation_intensity = "minor"
	if quality_score < adaptive_response_system.adaptation_thresholds.minor_adjustment:
		adaptation_intensity = "major"
	elif quality_score < adaptive_response_system.adaptation_thresholds.moderate_adjustment:
		adaptation_intensity = "moderate"
	
	# Apply specific adaptations based on issues
	for issue in quality_issues:
		match issue:
			"repetitive_patterns":
				var old_level = adaptations.language_diversity
				adaptations.language_diversity = _adjust_adaptation_level(adaptations.language_diversity, adaptation_intensity, "increase")
				if old_level != adaptations.language_diversity:
					adjustments_made.append("Enhanced language diversity: " + old_level + " → " + adaptations.language_diversity)
			
			"character_voice_inconsistency":
				var old_level = adaptations.voice_reinforcement
				adaptations.voice_reinforcement = _adjust_adaptation_level(adaptations.voice_reinforcement, adaptation_intensity, "increase")
				if old_level != adaptations.voice_reinforcement:
					adjustments_made.append("Strengthened voice reinforcement: " + old_level + " → " + adaptations.voice_reinforcement)
			
			"show_tell_violations":
				var old_level = adaptations.structure_emphasis
				adaptations.structure_emphasis = _adjust_adaptation_level(adaptations.structure_emphasis, adaptation_intensity, "increase")
				if old_level != adaptations.structure_emphasis:
					adjustments_made.append("Enhanced structure emphasis: " + old_level + " → " + adaptations.structure_emphasis)
			
			"immersion_breaks":
				var old_level = adaptations.narrative_focus
				adaptations.narrative_focus = _adjust_adaptation_level(adaptations.narrative_focus, adaptation_intensity, "increase")
				if old_level != adaptations.narrative_focus:
					adjustments_made.append("Increased narrative focus: " + old_level + " → " + adaptations.narrative_focus)
			
			"formatting_issues":
				var old_level = adaptations.guidance_level
				adaptations.guidance_level = _adjust_adaptation_level(adaptations.guidance_level, adaptation_intensity, "increase")
				if old_level != adaptations.guidance_level:
					adjustments_made.append("Increased guidance level: " + old_level + " → " + adaptations.guidance_level)
	
	# Record adaptations if any were made
	if adjustments_made.size() > 0:
		var adaptation_record = {
			"character": character_name,
			"timestamp": Time.get_unix_time_from_system(),
			"trigger_score": quality_score,
			"trigger_issues": quality_issues,
			"intensity": adaptation_intensity,
			"adjustments": adjustments_made
		}
		
		response_adjustment_history.append(adaptation_record)
		adaptive_response_system.adaptation_effectiveness[character_name].recent_adjustments.append(adaptation_record)
		
		# Keep only recent adjustments (last 10)
		if adaptive_response_system.adaptation_effectiveness[character_name].recent_adjustments.size() > 10:
			adaptive_response_system.adaptation_effectiveness[character_name].recent_adjustments = adaptive_response_system.adaptation_effectiveness[character_name].recent_adjustments.slice(-10)
		
		print("AdaptiveResponseSystem: Adjustments for ", character_name, ": ", adjustments_made)
		
		# Emit signal for adaptation applied
		adaptation_applied.emit(character_name, adjustments_made)

func _adjust_adaptation_level(current_level: String, intensity: String, direction: String) -> String:
	"""Adjust adaptation level based on intensity and direction"""
	var levels = ["minimal", "standard", "enhanced", "maximum"]
	var current_index = levels.find(current_level)
	if current_index == -1:
		current_index = 1  # Default to standard
	
	var adjustment = 0
	match intensity:
		"minor":
			adjustment = 1
		"moderate":
			adjustment = 2
		"major":
			adjustment = 3
	
	if direction == "decrease":
		adjustment = -adjustment
	
	var new_index = clamp(current_index + adjustment, 0, levels.size() - 1)
	return levels[new_index]

func generate_adaptive_dialogue_guidance(character_name: String) -> String:
	"""Generate dialogue guidance based on current adaptations"""
	if not adaptive_response_system.current_adaptations.has(character_name):
		return ""
	
	var adaptations = adaptive_response_system.current_adaptations[character_name]
	var guidance = "\n[ADAPTIVE GUIDANCE for " + character_name + ": "
	
	# Guidance level adaptations
	match adaptations.guidance_level:
		"enhanced":
			guidance += "Follow dialogue guidelines strictly. Pay close attention to formatting and structure. "
		"maximum":
			guidance += "CRITICAL: Adhere to all dialogue guidelines precisely. Double-check formatting, voice consistency, and narrative flow. "
	
	# Structure emphasis adaptations
	match adaptations.structure_emphasis:
		"structured":
			guidance += "Use clear dialogue structure with proper action descriptions. Avoid run-on sentences. "
		"rigid":
			guidance += "Maintain strict dialogue structure: Character Name: [Action if needed.] \"Dialogue content.\" "
	
	# Voice reinforcement adaptations
	match adaptations.voice_reinforcement:
		"enhanced":
			guidance += "Strongly emphasize character-specific speech patterns and personality traits. "
		"maximum":
			guidance += "CRITICAL: Maintain absolute consistency with established character voice and personality. "
	
	# Language diversity adaptations
	match adaptations.language_diversity:
		"enhanced":
			guidance += "Use varied vocabulary and sentence structures. Avoid repetitive phrases. "
		"maximum":
			guidance += "CRITICAL: Ensure maximum language variety. No repeated phrases or speech patterns. "
	
	# Narrative focus adaptations
	match adaptations.narrative_focus:
		"focused":
			guidance += "Stay focused on the immediate narrative. Avoid meta-commentary or formulaic elements. "
		"strict":
			guidance += "CRITICAL: Maintain strict narrative immersion. No breaking character or story flow. "
	
	guidance += "]"
	return guidance

func evaluate_adaptation_effectiveness():
	"""Evaluate how well adaptations are working"""
	for character_name in adaptive_response_system.adaptation_effectiveness.keys():
		var effectiveness = adaptive_response_system.adaptation_effectiveness[character_name]
		var recent_adjustments = effectiveness.recent_adjustments
		
		if recent_adjustments.size() < 3:
			continue  # Not enough data
		
		# Calculate quality improvement since last adaptation
		var quality_scores_before = []
		var quality_scores_after = []
		
		for adjustment in recent_adjustments:
			var adjustment_time = adjustment.timestamp
			
			# Get quality scores before and after this adjustment
			var before_scores = []
			var after_scores = []
			
			if quality_system:
				var quality_report = quality_system.get_quality_monitoring_report()
				var quality_scores = quality_report.get("quality_scores", [])
				var session_start_time = quality_report.get("session_start_time", 0)
				
				for i in range(quality_scores.size()):
					var score_time = session_start_time + i * 60  # Approximate timing
					if score_time < adjustment_time - 300:  # 5 minutes before
						before_scores.append(quality_scores[i])
					elif score_time > adjustment_time + 300:  # 5 minutes after
						after_scores.append(quality_scores[i])
				
				if before_scores.size() > 0 and after_scores.size() > 0:
					var avg_before = before_scores.reduce(func(a, b): return a + b) / before_scores.size()
					var avg_after = after_scores.reduce(func(a, b): return a + b) / after_scores.size()
					
					quality_scores_before.append(avg_before)
					quality_scores_after.append(avg_after)
		
		# Calculate overall effectiveness
		if quality_scores_before.size() > 0 and quality_scores_after.size() > 0:
			var avg_improvement = 0.0
			for i in range(min(quality_scores_before.size(), quality_scores_after.size())):
				avg_improvement += quality_scores_after[i] - quality_scores_before[i]
			avg_improvement /= min(quality_scores_before.size(), quality_scores_after.size())
			
			effectiveness.quality_improvement = avg_improvement
			effectiveness.success_rate = clamp(0.5 + avg_improvement, 0.0, 1.0)
			
			print("AdaptiveResponseSystem: Effectiveness for ", character_name, ": ", avg_improvement, " (success rate: ", effectiveness.success_rate, ")")
			
			# Emit signal for effectiveness update
			effectiveness_updated.emit(character_name, effectiveness.success_rate)

func get_adaptive_response_report() -> Dictionary:
	"""Generate a report on adaptive response system performance"""
	return {
		"adaptation_level": adaptive_response_system.adaptation_level,
		"total_adaptations": response_adjustment_history.size(),
		"character_adaptations": adaptive_response_system.current_adaptations,
		"effectiveness_scores": adaptive_response_system.adaptation_effectiveness,
		"recent_adjustments": response_adjustment_history.slice(-10),
		"overall_effectiveness": calculate_overall_adaptation_effectiveness()
	}

func calculate_overall_adaptation_effectiveness() -> float:
	"""Calculate overall effectiveness of the adaptive response system"""
	var total_effectiveness = 0.0
	var character_count = 0
	
	for character_name in adaptive_response_system.adaptation_effectiveness.keys():
		var effectiveness = adaptive_response_system.adaptation_effectiveness[character_name]
		total_effectiveness += effectiveness.success_rate
		character_count += 1
	
	return total_effectiveness / character_count if character_count > 0 else 0.5

func get_system_health() -> float:
	"""Get the health of the adaptive response system"""
	var health = calculate_overall_adaptation_effectiveness()
	
	# Factor in number of recent adaptations
	var recent_adaptations = response_adjustment_history.filter(func(record): 
		return Time.get_unix_time_from_system() - record.timestamp < 3600  # Last hour
	).size()
	
	# Adjust health based on adaptation frequency
	if recent_adaptations > 20:
		health *= 0.8  # Too many adaptations might indicate instability
	elif recent_adaptations < 2:
		health *= 0.9  # Too few adaptations might indicate lack of responsiveness
	
	return health

func get_character_adaptations(character_name: String) -> Dictionary:
	"""Get current adaptations for a specific character"""
	if not adaptive_response_system.current_adaptations.has(character_name):
		return {}
	
	return adaptive_response_system.current_adaptations[character_name]

func get_character_effectiveness(character_name: String) -> Dictionary:
	"""Get effectiveness data for a specific character"""
	if not adaptive_response_system.adaptation_effectiveness.has(character_name):
		return {}
	
	return adaptive_response_system.adaptation_effectiveness[character_name]

func reset_character_adaptations(character_name: String):
	"""Reset adaptations for a specific character to defaults"""
	if not adaptive_response_system.current_adaptations.has(character_name):
		return
	
	adaptive_response_system.current_adaptations[character_name] = {
		"guidance_level": "standard",
		"structure_emphasis": "balanced",
		"voice_reinforcement": "normal",
		"language_diversity": "standard",
		"narrative_focus": "balanced"
	}
	
	print("AdaptiveResponseSystem: Reset adaptations for ", character_name)

func adjust_adaptation_level(new_level: float):
	"""Adjust the overall adaptation level"""
	adaptive_response_system.adaptation_level = clamp(new_level, 0.0, 1.0)
	print("AdaptiveResponseSystem: Adaptation level set to ", adaptive_response_system.adaptation_level)

func get_adaptation_thresholds() -> Dictionary:
	"""Get current adaptation thresholds"""
	return adaptive_response_system.adaptation_thresholds

func set_adaptation_thresholds(thresholds: Dictionary):
	"""Set adaptation thresholds"""
	for key in thresholds.keys():
		if adaptive_response_system.adaptation_thresholds.has(key):
			adaptive_response_system.adaptation_thresholds[key] = thresholds[key]
	
	print("AdaptiveResponseSystem: Thresholds updated")

func get_recent_adjustments(limit: int = 10) -> Array:
	"""Get recent adjustment history"""
	return response_adjustment_history.slice(-limit)

func clear_adjustment_history():
	"""Clear adjustment history"""
	response_adjustment_history.clear()
	
	# Clear character-specific histories
	for character_name in adaptive_response_system.adaptation_effectiveness.keys():
		adaptive_response_system.adaptation_effectiveness[character_name].recent_adjustments.clear()
	
	print("AdaptiveResponseSystem: Adjustment history cleared")

func get_adaptation_patterns() -> Dictionary:
	"""Get analysis of adaptation patterns"""
	var patterns = {
		"most_common_issues": {},
		"most_adapted_characters": {},
		"adaptation_frequency": {},
		"effectiveness_trends": {}
	}
	
	# Analyze most common issues
	for record in response_adjustment_history:
		for issue in record.trigger_issues:
			if not patterns.most_common_issues.has(issue):
				patterns.most_common_issues[issue] = 0
			patterns.most_common_issues[issue] += 1
	
	# Analyze most adapted characters
	for record in response_adjustment_history:
		var character = record.character
		if not patterns.most_adapted_characters.has(character):
			patterns.most_adapted_characters[character] = 0
		patterns.most_adapted_characters[character] += 1
	
	# Analyze adaptation frequency over time
	var current_time = Time.get_unix_time_from_system()
	var time_buckets = ["last_hour", "last_day", "last_week"]
	var time_limits = [3600, 86400, 604800]
	
	for i in range(time_buckets.size()):
		var bucket = time_buckets[i]
		var limit = time_limits[i]
		var count = response_adjustment_history.filter(func(record): 
			return current_time - record.timestamp < limit
		).size()
		patterns.adaptation_frequency[bucket] = count
	
	return patterns

func test_with_sample_adaptations():
	"""Test the adaptive response system with sample data"""
	print("AdaptiveResponseSystem: Testing with sample adaptations...")
	
	if not network_manager:
		print("Network manager not available for testing")
		return
	
	var ai_controlled_names = network_manager.get_ai_controlled_character_names()
	if ai_controlled_names.size() == 0:
		print("No AI controlled characters found")
		return
	
	var test_character = ai_controlled_names[0]
	var test_issues = ["repetitive_patterns", "character_voice_inconsistency"]
	var test_quality_score = 0.4
	
	print("Testing adaptation for character: ", test_character)
	print("Test issues: ", test_issues)
	print("Test quality score: ", test_quality_score)
	
	# Apply test adaptation
	adapt_response_based_on_quality(test_character, test_issues, test_quality_score)
	
	# Generate test guidance
	var guidance = generate_adaptive_dialogue_guidance(test_character)
	print("Generated guidance: ", guidance)
	
	# Get report
	var report = get_adaptive_response_report()
	print("System report: ", report)
	
	print("AdaptiveResponseSystem: Test completed")

func debug_system_state():
	"""Debug function to print current system state"""
	print("=== ADAPTIVE RESPONSE SYSTEM DEBUG ===")
	print("Adaptation level: ", adaptive_response_system.adaptation_level)
	print("Total adjustments: ", response_adjustment_history.size())
	print("Character adaptations: ", adaptive_response_system.current_adaptations.keys())
	print("Effectiveness scores: ")
	for character_name in adaptive_response_system.adaptation_effectiveness.keys():
		var effectiveness = adaptive_response_system.adaptation_effectiveness[character_name]
		print("  ", character_name, ": ", effectiveness.success_rate)
	print("Overall effectiveness: ", calculate_overall_adaptation_effectiveness())
	print("System health: ", get_system_health())
	print("=== END DEBUG ===") 