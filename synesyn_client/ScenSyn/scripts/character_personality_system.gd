extends Node
class_name CharacterPersonalitySystem

"""
Advanced Character Personality Modeling System

This system provides:
- Big Five personality trait modeling for characters
- Dynamic personality evolution based on story events
- Emotional state tracking and management
- Personality-driven dialogue guidance generation
- Character-specific communication style management

Usage:
	var personality_system = CharacterPersonalitySystem.new()
	personality_system.initialize_character_profiles(ai_character_names)
	var guidance = personality_system.get_dialogue_guidance("Ingrid Tog")
"""

signal personality_changed(character_name: String, trait_name: String, old_value: float, new_value: float)
signal emotional_state_changed(character_name: String, emotion: String, intensity: float)

# Core data structures
var character_personality_profiles = {}
var personality_evolution_tracker = {}
var emotional_state_tracker = {}

# Configuration
var max_recent_events = 10
var max_emotion_history = 20
var personality_shift_threshold = 0.05

func _ready():
	name = "CharacterPersonalitySystem"

# ------------------------------------------------------------------
# PUBLIC API
# ------------------------------------------------------------------

func initialize_character_profiles(ai_controlled_names: Array):
	"""Initialize psychological personality profiles for characters based on their descriptions"""
	for character_name in ai_controlled_names:
		if not character_personality_profiles.has(character_name):
			character_personality_profiles[character_name] = _create_personality_profile(character_name)
			personality_evolution_tracker[character_name] = {
				"stress_level": 0.5,  # 0.0 = calm, 1.0 = highly stressed
				"confidence_level": 0.5,  # 0.0 = uncertain, 1.0 = very confident
				"collaboration_tendency": 0.5,  # 0.0 = independent, 1.0 = highly collaborative
				"adaptability": 0.5,  # 0.0 = rigid, 1.0 = highly adaptable
				"recent_events": [],  # Track events that affect personality
				"personality_shifts": []  # Track how personality changes over time
			}
			emotional_state_tracker[character_name] = {
				"current_emotion": "neutral",
				"emotion_intensity": 0.5,  # 0.0 = mild, 1.0 = intense
				"emotion_triggers": [],  # What caused current emotion
				"emotion_history": []  # Track emotional journey
			}

func get_dialogue_guidance(character_name: String) -> String:
	"""Generate dialogue guidance based on current personality state"""
	if not character_personality_profiles.has(character_name):
		return ""
	
	var profile = character_personality_profiles[character_name]
	var evolution = personality_evolution_tracker.get(character_name, {})
	var emotion = emotional_state_tracker.get(character_name, {})
	
	var guidance = "\n[PERSONALITY GUIDANCE for " + character_name + ": "
	
	# Core personality influence
	var communication_style = profile.get("communication_style", "balanced")
	match communication_style:
		"data_driven_diplomatic":
			guidance += "Speak with research-backed authority, but remain diplomatic. "
		"clear_solution_focused":
			guidance += "Focus on practical solutions and clear next steps. "
		"inclusive_persuasive":
			guidance += "Use inclusive language and build consensus through persuasion. "
	
	# Current emotional state influence
	var current_emotion = emotion.get("current_emotion", "neutral")
	var emotion_intensity = emotion.get("emotion_intensity", 0.5)
	
	if current_emotion != "neutral" and emotion_intensity > 0.3:
		match current_emotion:
			"hopeful":
				guidance += "Express optimism and possibility-focused thinking. "
			"concerned":
				guidance += "Show measured worry while maintaining problem-solving focus. "
			"determined":
				guidance += "Speak with conviction and decisive language. "
			"frustrated":
				guidance += "Show tension while maintaining professionalism. "
			"excited":
				guidance += "Use energetic language and forward-looking statements. "
	
	# Stress level influence
	var stress_level = evolution.get("stress_level", 0.5)
	if stress_level > 0.7:
		guidance += "Show signs of pressure - shorter sentences, more urgent tone. "
	elif stress_level < 0.3:
		guidance += "Speak calmly and thoughtfully with measured responses. "
	
	# Confidence level influence
	var confidence_level = evolution.get("confidence_level", 0.5)
	if confidence_level > 0.7:
		guidance += "Express ideas with conviction and take initiative. "
	elif confidence_level < 0.3:
		guidance += "Show some uncertainty, ask for input from others. "
	
	guidance += "]"
	return guidance

func analyze_story_events_for_personality_impact(recent_messages: Array):
	"""Analyze recent story events and update personality evolution accordingly"""
	for message in recent_messages:
		if not message.has("sender") or not message.has("message"):
			continue
		
		var sender = message.sender
		var content = message.message.to_lower()
		
		# Skip system messages and narrator
		if sender == "System" or sender == "Narrator":
			continue
		
		# Analyze content for personality-affecting events
		if "crisis" in content or "emergency" in content or "urgent" in content:
			update_personality_evolution(sender, "crisis_response", 0.8)
		elif "together" in content or "collaborate" in content or "team" in content:
			update_personality_evolution(sender, "successful_collaboration", 0.6)
		elif "solution" in content or "fix" in content or "resolve" in content:
			update_personality_evolution(sender, "conflict_resolution", 0.7)
		elif "lead" in content or "decide" in content or "plan" in content:
			update_personality_evolution(sender, "leadership_moment", 0.6)
		elif "community" in content or "help" in content or "support" in content:
			update_personality_evolution(sender, "community_support", 0.5)
		elif "technical" in content or "system" in content or "data" in content:
			update_personality_evolution(sender, "technical_challenge", 0.4)

func update_personality_evolution(character_name: String, event_type: String, intensity: float):
	"""Update character personality based on story events"""
	if not personality_evolution_tracker.has(character_name):
		return
	
	var tracker = personality_evolution_tracker[character_name]
	var profile = character_personality_profiles.get(character_name, {})
	
	# Record the event
	tracker.recent_events.append({
		"type": event_type,
		"intensity": intensity,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	# Keep only recent events
	if tracker.recent_events.size() > max_recent_events:
		tracker.recent_events = tracker.recent_events.slice(-max_recent_events)
	
	# Update personality dimensions based on event type
	match event_type:
		"crisis_response":
			tracker.stress_level = min(1.0, tracker.stress_level + intensity * 0.3)
			if intensity > 0.7:
				tracker.confidence_level = max(0.0, tracker.confidence_level - 0.1)
		"successful_collaboration":
			tracker.collaboration_tendency = min(1.0, tracker.collaboration_tendency + intensity * 0.2)
			tracker.confidence_level = min(1.0, tracker.confidence_level + intensity * 0.1)
		"conflict_resolution":
			tracker.adaptability = min(1.0, tracker.adaptability + intensity * 0.15)
			tracker.stress_level = max(0.0, tracker.stress_level - intensity * 0.2)
		"leadership_moment":
			tracker.confidence_level = min(1.0, tracker.confidence_level + intensity * 0.2)
			if profile.get("core_traits", {}).get("extraversion", 0.5) < 0.7:
				# Introverted characters become more extraverted through leadership
				record_personality_shift(character_name, "extraversion", 0.1)
		"community_support":
			tracker.collaboration_tendency = min(1.0, tracker.collaboration_tendency + intensity * 0.15)
			update_emotional_state(character_name, "hopeful", intensity * 0.8)
		"technical_challenge":
			if character_name == "Jason Olivier":
				tracker.confidence_level = min(1.0, tracker.confidence_level + intensity * 0.1)
			tracker.stress_level = min(1.0, tracker.stress_level + intensity * 0.2)

func update_emotional_state(character_name: String, emotion: String, intensity: float):
	"""Update character's current emotional state"""
	if not emotional_state_tracker.has(character_name):
		return
	
	var tracker = emotional_state_tracker[character_name]
	
	# Record previous emotion in history
	if tracker.current_emotion != "neutral":
		tracker.emotion_history.append({
			"emotion": tracker.current_emotion,
			"intensity": tracker.emotion_intensity,
			"duration": Time.get_unix_time_from_system() - tracker.get("emotion_start_time", 0)
		})
	
	# Update current emotion
	tracker.current_emotion = emotion
	tracker.emotion_intensity = intensity
	tracker.emotion_start_time = Time.get_unix_time_from_system()
	
	# Keep emotion history manageable
	if tracker.emotion_history.size() > max_emotion_history:
		tracker.emotion_history = tracker.emotion_history.slice(-max_emotion_history)
	
	# Emit signal for external listeners
	emotional_state_changed.emit(character_name, emotion, intensity)

func record_personality_shift(character_name: String, trait_name: String, change: float):
	"""Record permanent personality changes"""
	if not personality_evolution_tracker.has(character_name):
		return
	
	var tracker = personality_evolution_tracker[character_name]
	tracker.personality_shifts.append({
		"trait": trait_name,
		"change": change,
		"timestamp": Time.get_unix_time_from_system(),
		"context": "story_evolution"
	})
	
	# Apply the change to the actual personality profile
	if character_personality_profiles.has(character_name):
		var profile = character_personality_profiles[character_name]
		if profile.has("core_traits") and profile.core_traits.has(trait_name):
			var old_value = profile.core_traits[trait_name]
			var new_value = clamp(old_value + change, 0.0, 1.0)
			profile.core_traits[trait_name] = new_value
			
			# Emit signal for external listeners
			personality_changed.emit(character_name, trait_name, old_value, new_value)

func get_character_profile(character_name: String) -> Dictionary:
	"""Get complete personality profile for a character"""
	return character_personality_profiles.get(character_name, {})

func get_character_evolution_data(character_name: String) -> Dictionary:
	"""Get personality evolution tracking data for a character"""
	return personality_evolution_tracker.get(character_name, {})

func get_character_emotional_state(character_name: String) -> Dictionary:
	"""Get current emotional state data for a character"""
	return emotional_state_tracker.get(character_name, {})

func get_system_status() -> Dictionary:
	"""Get status of the personality modeling system"""
	var total_characters = character_personality_profiles.size()
	var characters_with_evolution = personality_evolution_tracker.size()
	var characters_with_emotions = emotional_state_tracker.size()
	
	var personality_changes = 0
	for character_name in personality_evolution_tracker.keys():
		var tracker = personality_evolution_tracker[character_name]
		personality_changes += tracker.get("personality_shifts", []).size()
	
	return {
		"total_characters": total_characters,
		"characters_with_evolution": characters_with_evolution,
		"characters_with_emotions": characters_with_emotions,
		"total_personality_changes": personality_changes,
		"character_profiles": character_personality_profiles,
		"evolution_data": personality_evolution_tracker,
		"emotional_data": emotional_state_tracker
	}

# ------------------------------------------------------------------
# PRIVATE METHODS
# ------------------------------------------------------------------

func _create_personality_profile(character_name: String) -> Dictionary:
	"""Creates a rich psychological profile for any character name"""
	# Hand-crafted profiles for key story characters
	var base_profiles: Dictionary = {
		"Ingrid Tog": {
			"personality_type": "analytical_leader",
			"core_traits": {
				"openness":         0.8,  # embraces new ideas / research
				"conscientiousness":0.9,  # highly organised & methodical
				"extraversion":     0.6,  # moderately social, comfortable leading
				"agreeableness":    0.7,  # collaborative but can be assertive
				"neuroticism":      0.3   # generally stable under pressure
			},
			"communication_style": "data_driven_diplomatic",
			"decision_making":     "evidence_based_consensus",
			"stress_responses": [
				"becomes more methodical",
				"seeks additional data",
				"increases collaboration"
			],
			"motivation_drivers": [
				"scientific accuracy",
				"community benefit",
				"research advancement"
			],
			"conflict_approach": "mediation_through_facts"
		},

		"Jason Olivier": {
			"personality_type": "practical_problem_solver",
			"core_traits": {
				"openness":         0.6,
				"conscientiousness":0.8,
				"extraversion":     0.5,
				"agreeableness":    0.8,
				"neuroticism":      0.4
			},
			"communication_style": "clear_solution_focused",
			"decision_making":     "pragmatic_efficiency",
			"stress_responses": [
				"focuses on immediate solutions",
				"becomes more directive",
				"seeks technical clarity"
			],
			"motivation_drivers": [
				"system efficiency",
				"practical outcomes",
				"helping others"
			],
			"conflict_approach": "problem_solving_mediation"
		},

		"Astrid Olavson": {
			"personality_type": "empathetic_advocate",
			"core_traits": {
				"openness":         0.7,
				"conscientiousness":0.7,
				"extraversion":     0.8,
				"agreeableness":    0.9,
				"neuroticism":      0.5
			},
			"communication_style": "inclusive_persuasive",
			"decision_making":     "consensus_building",
			"stress_responses": [
				"increases community outreach",
				"becomes more emotional",
				"seeks group support"
			],
			"motivation_drivers": [
				"community wellbeing",
				"social justice",
				"inclusive solutions"
			],
			"conflict_approach": "empathetic_facilitation"
		}
	}

	# Return a handcrafted profile if we have one
	if base_profiles.has(character_name):
		return base_profiles[character_name]

	# Otherwise build a balanced default profile
	return {
		"personality_type": "balanced_contributor",
		"core_traits": {
			"openness":         0.6,
			"conscientiousness":0.6,
			"extraversion":     0.6,
			"agreeableness":    0.7,
			"neuroticism":      0.4
		},
		"communication_style": "collaborative_balanced",
		"decision_making":     "group_oriented",
		"stress_responses": [
			"seeks group input",
			"becomes more cautious"
		],
		"motivation_drivers": [
			"group success",
			"problem resolution"
		],
		"conflict_approach": "diplomatic_compromise"
	} 
