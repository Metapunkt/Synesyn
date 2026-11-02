extends Node
class_name QualityMonitoringSystem

"""
Real-time Quality Monitoring System

This system provides:
- Real-time message quality scoring and analysis
- Issue detection and categorization
- Character performance tracking
- Quality trend analysis and alerts
- Comprehensive quality reporting

Usage:
	var quality_system = QualityMonitoringSystem.new()
	quality_system.initialize(ai_character_names)
	var result = quality_system.monitor_message("Ingrid Tog", "Hello everyone!")
"""

signal quality_alert_triggered(sender: String, quality_score: float, issues: Array)
signal quality_trend_changed(new_trend: String)
signal character_performance_updated(character_name: String, performance_data: Dictionary)

# Core data structures
var quality_monitor = {}
var quality_alerts = []
var quality_trends = {}

# External dependencies (injected)
var personality_system: CharacterPersonalitySystem
var adaptive_system: AdaptiveResponseSystem
var character_voice_tracker = {}
var get_player_controlled_character_names: Callable
var get_story_state: Callable
var extract_current_topic: Callable
var is_narrator_hijacking: Callable

# Configuration
var max_quality_scores = 50
var max_recent_issues = 10
var max_alerts = 20

func _ready():
	name = "QualityMonitoringSystem"

# ------------------------------------------------------------------
# PUBLIC API
# ------------------------------------------------------------------

func initialize(ai_controlled_names: Array):
	"""Initialize the real-time quality monitoring system"""
	quality_monitor = {
		"session_start_time": Time.get_unix_time_from_system(),
		"total_messages": 0,
		"quality_scores": [],
		"issue_counts": {
			"repetitive_patterns": 0,
			"narrator_hijacking": 0,
			"character_voice_inconsistency": 0,
			"show_tell_violations": 0,
			"formatting_issues": 0,
			"immersion_breaks": 0
		},
		"character_performance": {},
		"conversation_flow_score": 0.0,
		"overall_session_quality": 0.0
	}
	
	# Initialize character performance tracking
	for character_name in ai_controlled_names:
		quality_monitor.character_performance[character_name] = {
			"voice_consistency_score": 1.0,
			"dialogue_quality_score": 1.0,
			"recent_issues": [],
			"improvement_trend": "stable"
		}
	
	quality_trends = {
		"last_10_messages": [],
		"quality_direction": "stable",  # "improving", "declining", "stable"
		"alert_threshold": 0.3,  # Below this triggers alerts
		"excellence_threshold": 0.8  # Above this is excellent
	}
	
	print("QualityMonitoringSystem: Initialized")

func monitor_message(sender: String, message: String) -> Dictionary:
	"""Monitor individual message quality and update tracking"""
	var quality_score = calculate_message_quality(sender, message)
	var issues = detect_quality_issues(sender, message)
	
	# Update quality monitor
	quality_monitor.total_messages += 1
	quality_monitor.quality_scores.append(quality_score)
	
	# Keep only last scores for trending
	if quality_monitor.quality_scores.size() > max_quality_scores:
		quality_monitor.quality_scores = quality_monitor.quality_scores.slice(-max_quality_scores)
	
	# Update issue counts
	for issue in issues:
		if quality_monitor.issue_counts.has(issue):
			quality_monitor.issue_counts[issue] += 1
	
	# Update character performance
	if quality_monitor.character_performance.has(sender):
		var char_perf = quality_monitor.character_performance[sender]
		char_perf.recent_issues.append_array(issues)
		
		# Keep only recent issues
		if char_perf.recent_issues.size() > max_recent_issues:
			char_perf.recent_issues = char_perf.recent_issues.slice(-max_recent_issues)
		
		# Update character quality scores
		char_perf.dialogue_quality_score = calculate_character_dialogue_quality(sender)
		char_perf.voice_consistency_score = calculate_character_voice_consistency(sender)
		
		# Emit performance update signal
		character_performance_updated.emit(sender, char_perf)
	
	# Update trends
	update_quality_trends(quality_score)
	
	# Generate alerts if needed
	check_quality_alerts(sender, quality_score, issues)
	
	# Trigger adaptive response if needed
	if adaptive_system and issues.size() > 0:
		adaptive_system.adapt_response_based_on_quality(sender, issues, quality_score)
	
	return {
		"quality_score": quality_score,
		"issues": issues,
		"trend": quality_trends.quality_direction
	}

func calculate_message_quality(sender: String, message: String) -> float:
	"""Calculate quality score for a single message (0.0 = poor, 1.0 = excellent)"""
	var score = 1.0
	
	# Check for repetitive patterns
	if has_repetitive_patterns(message):
		score -= 0.2
	
	# Check for show vs tell violations
	if has_show_tell_violations(message):
		score -= 0.15
	
	# Check for character voice consistency
	if sender != "Narrator" and sender != "System":
		if not is_voice_consistent(sender, message):
			score -= 0.2
	
	# Check for formatting issues
	if has_formatting_issues(message):
		score -= 0.1
	
	# Check for immersion breaks
	if has_immersion_breaks(message):
		score -= 0.15
	
	# Check for conversation flow
	if not maintains_conversation_flow(sender, message):
		score -= 0.1
	
	# Bonus for excellent dialogue
	if is_excellent_dialogue(message):
		score += 0.1
	
	return max(0.0, min(1.0, score))

func detect_quality_issues(sender: String, message: String) -> Array:
	"""Detect specific quality issues in a message"""
	var issues = []
	
	if has_repetitive_patterns(message):
		issues.append("repetitive_patterns")
	
	if sender == "Narrator" and is_narrator_hijacking.is_valid() and is_narrator_hijacking.call(message, get_player_controlled_character_names.call()):
		issues.append("narrator_hijacking")
	
	if sender != "Narrator" and sender != "System" and not is_voice_consistent(sender, message):
		issues.append("character_voice_inconsistency")
	
	if has_show_tell_violations(message):
		issues.append("show_tell_violations")
	
	if has_formatting_issues(message):
		issues.append("formatting_issues")
	
	if has_immersion_breaks(message):
		issues.append("immersion_breaks")
	
	return issues

func get_quality_monitoring_report() -> Dictionary:
	"""Get comprehensive quality monitoring report"""
	return {
		"session_duration": Time.get_unix_time_from_system() - quality_monitor.session_start_time,
		"session_start_time": quality_monitor.session_start_time,
		"total_messages": quality_monitor.total_messages,
		"overall_quality": quality_monitor.overall_session_quality,
		"quality_trend": quality_trends.quality_direction,
		"quality_scores": quality_monitor.quality_scores,
		"issue_summary": quality_monitor.issue_counts,
		"character_performance": quality_monitor.character_performance,
		"recent_alerts": quality_alerts.slice(-5),  # Last 5 alerts
		"alert_threshold": quality_trends.alert_threshold,
		"excellence_threshold": quality_trends.excellence_threshold
	}

func get_quality_summary_report() -> Dictionary:
	"""Generate quality summary report"""
	return {
		"overall_quality": quality_monitor.get("overall_session_quality", 0.0),
		"quality_trend": quality_trends.get("quality_direction", "stable"),
		"total_issues": quality_monitor.get("issue_counts", {}),
		"most_common_issue": get_most_common_quality_issue(),
		"quality_alerts": quality_alerts.size(),
		"recent_scores": quality_monitor.get("quality_scores", []).slice(-10)
	}

func get_most_common_quality_issue() -> String:
	"""Get the most common quality issue"""
	var issue_counts = quality_monitor.get("issue_counts", {})
	var max_count = 0
	var most_common = "none"
	
	for issue in issue_counts.keys():
		if issue_counts[issue] > max_count:
			max_count = issue_counts[issue]
			most_common = issue
	
	return most_common if max_count > 0 else "none"

func generate_quality_recommendations() -> Array:
	"""Generate recommendations based on quality analysis"""
	var recommendations = []
	
	# Check overall quality trend
	if quality_trends.quality_direction == "declining":
		recommendations.append("Quality is declining - review recent dialogue patterns and consider adjustments.")
	elif quality_trends.quality_direction == "improving":
		recommendations.append("Quality is improving - maintain current dialogue strategies.")
	
	# Check for specific issues
	var issue_counts = quality_monitor.issue_counts
	var max_issue_count = 0
	var most_common_issue = ""
	
	for issue in issue_counts.keys():
		if issue_counts[issue] > max_issue_count:
			max_issue_count = issue_counts[issue]
			most_common_issue = issue
	
	if max_issue_count > 5:
		match most_common_issue:
			"repetitive_patterns":
				recommendations.append("High repetitive patterns detected - encourage more varied language.")
			"character_voice_inconsistency":
				recommendations.append("Character voice inconsistency - review personality profiles and dialogue guidance.")
			"show_tell_violations":
				recommendations.append("Show vs tell violations - encourage more descriptive, immersive writing.")
			"formatting_issues":
				recommendations.append("Formatting issues detected - review action bracket usage and formatting rules.")
			"immersion_breaks":
				recommendations.append("Immersion breaks detected - avoid meta-commentary and formulaic language.")
			"narrator_hijacking":
				recommendations.append("Narrator hijacking detected - ensure narrator doesn't control player characters.")
	
	# Check character performance
	for character_name in quality_monitor.character_performance.keys():
		var char_perf = quality_monitor.character_performance[character_name]
		if char_perf.dialogue_quality_score < 0.4:
			recommendations.append("Character " + character_name + " has low dialogue quality - review voice consistency.")
		if char_perf.voice_consistency_score < 0.6:
			recommendations.append("Character " + character_name + " voice inconsistency - strengthen personality adherence.")
	
	return recommendations

func get_system_health() -> float:
	"""Get overall system health score"""
	return quality_monitor.get("overall_session_quality", 0.5)

func set_dependencies(deps: Dictionary):
	"""Set external dependencies"""
	if deps.has("personality_system"):
		personality_system = deps.personality_system
	if deps.has("character_voice_tracker"):
		character_voice_tracker = deps.character_voice_tracker
	if deps.has("get_player_controlled_character_names"):
		get_player_controlled_character_names = deps.get_player_controlled_character_names
	if deps.has("get_story_state"):
		get_story_state = deps.get_story_state
	if deps.has("extract_current_topic"):
		extract_current_topic = deps.extract_current_topic
	if deps.has("is_narrator_hijacking"):
		is_narrator_hijacking = deps.is_narrator_hijacking

func test_with_sample_messages():
	"""Test quality monitoring with sample messages"""
	print("=== TESTING QUALITY MONITORING ===")
	
	var test_messages = [
		{"sender": "Ingrid Tog", "message": "Based on our research data, I think we should perhaps consider implementing renewable energy solutions for our community."},
		{"sender": "Jason Olivier", "message": "I think that we should probably maybe look into this issue. I think that it might be something we could try to fix."},
		{"sender": "Astrid Olavson", "message": "*nervously* I feel worried about this situation. *sadly* Everyone was feeling anxious about the outcome."},
		{"sender": "Narrator", "message": "The group continues their discussion. What will they decide next? The story awaits your input."},
		{"sender": "Ingrid Tog", "message": "Let's focus on the technical specifications. We need concrete data on energy efficiency and cost-effectiveness."}
	]
	
	for msg in test_messages:
		var quality_result = monitor_message(msg.sender, msg.message)
		print("Message from ", msg.sender, ": Quality score ", quality_result.quality_score, ", Issues: ", quality_result.issues)
	
	print("=== END TESTING ===")

# ------------------------------------------------------------------
# PRIVATE METHODS
# ------------------------------------------------------------------

func has_repetitive_patterns(message: String) -> bool:
	"""Check for repetitive language patterns"""
	var message_lower = message.to_lower()
	
	# Check for repeated phrases
	var words = message_lower.split(" ")
	var phrase_counts = {}
	
	# Check 3-word phrases
	for i in range(words.size() - 2):
		var phrase = words[i] + " " + words[i+1] + " " + words[i+2]
		if not phrase_counts.has(phrase):
			phrase_counts[phrase] = 0
		phrase_counts[phrase] += 1
	
	# If any phrase appears more than once, it's repetitive
	for count in phrase_counts.values():
		if count > 1:
			return true
	
	# Check for common filler patterns
	var filler_patterns = [
		"i think that", "we should probably", "it seems like", "i believe that",
		"perhaps we could", "maybe we should", "it might be", "we could try"
	]
	
	var filler_count = 0
	for pattern in filler_patterns:
		if pattern in message_lower:
			filler_count += 1
	
	return filler_count > 2

func has_show_tell_violations(message: String) -> bool:
	"""Check for show vs tell violations"""
	var message_lower = message.to_lower()
	
	# Check for emotion tags
	if "*" in message and ("*nervously*" in message_lower or "*excitedly*" in message_lower or "*sadly*" in message_lower):
		return true
	
	# Check for telling instead of showing emotions
	var telling_patterns = [
		"he felt", "she felt", "they felt", "feeling anxious", "feeling excited",
		"was worried", "was happy", "was sad", "was angry", "was confused"
	]
	
	for pattern in telling_patterns:
		if pattern in message_lower:
			return true
	
	return false

func is_voice_consistent(sender: String, message: String) -> bool:
	"""Check if message is consistent with character's established voice"""
	if not personality_system or not personality_system.get_character_profile(sender):
		return true  # No profile to check against
	
	var profile = personality_system.get_character_profile(sender)
	var communication_style = profile.get("communication_style", "")
	var message_lower = message.to_lower()
	
	# Check style consistency
	match communication_style:
		"data_driven_diplomatic":
			# Should have research/data references and diplomatic language
			var has_data_language = "research" in message_lower or "data" in message_lower or "study" in message_lower or "evidence" in message_lower
			var has_diplomatic_language = "perhaps" in message_lower or "might" in message_lower or "could" in message_lower
			return has_data_language or has_diplomatic_language
		"clear_solution_focused":
			# Should have action-oriented language
			var has_action_language = "should" in message_lower or "need to" in message_lower or "let's" in message_lower or "can" in message_lower
			return has_action_language
		"inclusive_persuasive":
			# Should have inclusive language
			var has_inclusive_language = "we" in message_lower or "our" in message_lower or "together" in message_lower or "all" in message_lower
			return has_inclusive_language
	
	return true

func has_formatting_issues(message: String) -> bool:
	"""Check for formatting issues"""
	# Check for mismatched action brackets
	var open_brackets = message.count("[")
	var close_brackets = message.count("]")
	
	if open_brackets != close_brackets:
		return true
	
	# Check for old-style action asterisks
	if "*" in message and not message.begins_with("*") and not message.ends_with("*"):
		# Check if it's an action tag
		var asterisk_content = message.get_slice("*", 1)
		if asterisk_content.length() > 0 and asterisk_content.length() < 30:
			return true
	
	return false

func has_immersion_breaks(message: String) -> bool:
	"""Check for immersion-breaking elements"""
	var message_lower = message.to_lower()
	
	# Check for meta-commentary
	var meta_patterns = [
		"this is a story", "in this narrative", "for the purpose of", "as characters",
		"the player", "the user", "the ai", "the game", "this scenario"
	]
	
	for pattern in meta_patterns:
		if pattern in message_lower:
			return true
	
	# Check for formulaic endings
	var formulaic_endings = [
		"what will happen next", "what will they do", "awaits your decision",
		"the story continues", "what happens now"
	]
	
	for ending in formulaic_endings:
		if ending in message_lower:
			return true
	
	return false

func maintains_conversation_flow(sender: String, message: String) -> bool:
	"""Check if message maintains natural conversation flow"""
	if not get_story_state.is_valid():
		return true
	
	var current_story_state = get_story_state.call()
	var recent_messages = current_story_state.get("story_log", [])
	
	if recent_messages.size() < 2:
		return true
	
	# Get last few messages for context
	var last_messages = recent_messages.slice(-3)
	var current_topic = ""
	
	if extract_current_topic.is_valid():
		current_topic = extract_current_topic.call(last_messages)
	
	if current_topic == "":
		return true
	
	# Check if message relates to current topic
	var message_lower = message.to_lower()
	var topic_keywords = current_topic.split(" ")
	
	for keyword in topic_keywords:
		if keyword in message_lower:
			return true
	
	# Check for topic transitions
	var transition_phrases = [
		"speaking of", "that reminds me", "on that note", "related to that",
		"building on", "following up", "in addition"
	]
	
	for phrase in transition_phrases:
		if phrase in message_lower:
			return true
	
	return false

func is_excellent_dialogue(message: String) -> bool:
	"""Check for markers of excellent dialogue"""
	var message_lower = message.to_lower()
	
	# Check for specific, concrete details
	var has_specifics = false
	var specific_patterns = [
		"\\d+", "specific", "exactly", "precisely", "particularly"
	]
	
	for pattern in specific_patterns:
		var regex = RegEx.new()
		regex.compile(pattern)
		if regex.search(message_lower):
			has_specifics = true
			break
	
	# Check for natural dialogue markers
	var natural_markers = [
		"you know", "i mean", "well", "actually", "honestly", "frankly"
	]
	
	var has_natural_speech = false
	for marker in natural_markers:
		if marker in message_lower:
			has_natural_speech = true
			break
	
	# Check for character-specific expertise
	var has_expertise = "research" in message_lower or "technical" in message_lower or "community" in message_lower
	
	return has_specifics or has_natural_speech or has_expertise

func calculate_character_dialogue_quality(character_name: String) -> float:
	"""Calculate overall dialogue quality for a character"""
	if not quality_monitor.character_performance.has(character_name):
		return 0.5
	
	var char_perf = quality_monitor.character_performance[character_name]
	var recent_issues = char_perf.recent_issues
	
	# Start with perfect score
	var score = 1.0
	
	# Deduct for recent issues
	for issue in recent_issues:
		match issue:
			"repetitive_patterns":
				score -= 0.05
			"character_voice_inconsistency":
				score -= 0.1
			"show_tell_violations":
				score -= 0.05
			"formatting_issues":
				score -= 0.02
			"immersion_breaks":
				score -= 0.08
	
	return max(0.0, min(1.0, score))

func calculate_character_voice_consistency(character_name: String) -> float:
	"""Calculate voice consistency score for a character"""
	if not character_voice_tracker.has(character_name):
		return 1.0
	
	var tracker = character_voice_tracker[character_name]
	var consistency_score = 1.0
	
	# Check recent voice guidance compliance
	var recent_guidance = tracker.get("recent_voice_guidance", [])
	for guidance in recent_guidance:
		if guidance.get("compliance", 1.0) < 0.8:
			consistency_score -= 0.1
	
	return max(0.0, min(1.0, consistency_score))

func update_quality_trends(new_score: float):
	"""Update quality trends based on new score"""
	quality_trends.last_10_messages.append(new_score)
	
	# Keep only last 10 scores
	if quality_trends.last_10_messages.size() > 10:
		quality_trends.last_10_messages = quality_trends.last_10_messages.slice(-10)
	
	# Calculate trend direction
	if quality_trends.last_10_messages.size() >= 5:
		var recent_avg = 0.0
		var older_avg = 0.0
		var half_point = quality_trends.last_10_messages.size() / 2
		
		# Recent half
		for i in range(half_point, quality_trends.last_10_messages.size()):
			recent_avg += quality_trends.last_10_messages[i]
		recent_avg /= (quality_trends.last_10_messages.size() - half_point)
		
		# Older half
		for i in range(half_point):
			older_avg += quality_trends.last_10_messages[i]
		older_avg /= half_point
		
		# Determine trend
		var old_trend = quality_trends.quality_direction
		if recent_avg > older_avg + 0.1:
			quality_trends.quality_direction = "improving"
		elif recent_avg < older_avg - 0.1:
			quality_trends.quality_direction = "declining"
		else:
			quality_trends.quality_direction = "stable"
		
		# Emit signal if trend changed
		if old_trend != quality_trends.quality_direction:
			quality_trend_changed.emit(quality_trends.quality_direction)
	
	# Update overall session quality
	if quality_monitor.quality_scores.size() > 0:
		var total_score = 0.0
		for score in quality_monitor.quality_scores:
			total_score += score
		quality_monitor.overall_session_quality = total_score / quality_monitor.quality_scores.size()

func check_quality_alerts(sender: String, quality_score: float, issues: Array):
	"""Generate quality alerts if needed"""
	var alert_threshold = quality_trends.alert_threshold
	
	# Check for low quality score
	if quality_score < alert_threshold:
		var alert = {
			"type": "low_quality_score",
			"sender": sender,
			"score": quality_score,
			"threshold": alert_threshold,
			"timestamp": Time.get_unix_time_from_system(),
			"message": "Low quality score detected for " + sender
		}
		quality_alerts.append(alert)
		quality_alert_triggered.emit(sender, quality_score, issues)
	
	# Check for declining trend
	if quality_trends.quality_direction == "declining":
		var alert = {
			"type": "declining_trend",
			"sender": "System",
			"trend": quality_trends.quality_direction,
			"timestamp": Time.get_unix_time_from_system(),
			"message": "Quality trend is declining - review recent dialogue"
		}
		quality_alerts.append(alert)
	
	# Keep alerts manageable
	if quality_alerts.size() > max_alerts:
		quality_alerts = quality_alerts.slice(-max_alerts) 
