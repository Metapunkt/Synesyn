extends RefCounted
class_name ConversationManagementSystem

"""
Conversation Management System

This system provides:
- Conversation history management and cleanup
- Thread isolation and management
- Player character dialogue filtering
- Content source block removal
- Session isolation and context bleeding prevention
- Conversation flow analysis and topic extraction

Usage:
	var conversation_manager = ConversationManagementSystem.new()
	conversation_manager.initialize(Global.get_conversation_manager())
	var cleaned = conversation_manager.clean_history(4000)
"""

# Signal definitions
signal history_cleaned(cleanup_result: Dictionary)
signal thread_created(thread_name: String)
signal session_isolated(thread_name: String)
signal dialogue_filtered(original_length: int, filtered_length: int)
signal content_blocks_removed(blocks_count: int)

# Dependencies (injected)
var conversation_manager_instance = null
var content_bus_instance = null
var network_instance = null

# Configuration
var default_char_limit = 150000  # INCREASED: Each prompt is 5k-10k chars, need room for 15-20 exchanges
var minimum_message_length = 10
var max_messages_to_keep = 20  # Keep last 20 exchanges
var use_clean_game_thread = false
var enable_session_isolation = true
var enable_content_source_filtering = true

# Internal state
var current_session_thread = ""
var conversation_history_cache = {}
var topic_analysis_cache = {}
var last_cleanup_time = 0.0

func _init():
	"""Initialize the conversation management system"""
	print("ConversationManagementSystem: Initialized")

func initialize(conv_manager, content_bus = null, network = null):
	"""Initialize with required dependencies"""
	conversation_manager_instance = conv_manager
	content_bus_instance = content_bus
	network_instance = network
	print("ConversationManagementSystem: Dependencies set")

# ------------------------------------------------------------------
# PUBLIC API - CONVERSATION HISTORY MANAGEMENT
# ------------------------------------------------------------------

func clean_history(target_char_limit: int = 0) -> Dictionary:
	"""Clean conversation history intelligently"""
	if target_char_limit == 0:
		target_char_limit = default_char_limit
	
	if not _validate_conversation_manager():
		return {"error": "Conversation manager not available"}
	
	var result = clean_conversation_history(conversation_manager_instance, target_char_limit)
	history_cleaned.emit(result)
	last_cleanup_time = Time.get_unix_time_from_system()
	return result

func clean_conversation_history(conversation_manager, target_char_limit: int = 8000) -> Dictionary:
	"""
	Intelligently clean conversation history by:
	1. Removing content source blocks
	2. Keeping essential game context
	3. Ensuring total character count stays under limit
	"""
	var thread_name = conversation_manager.get_current_thread()
	var thread_messages = conversation_manager.get_thread_messages(thread_name)
	
	if thread_messages.is_empty():
		return {"cleaned": 0, "total_chars": 0, "messages_kept": 0}
	
	print("ConversationManagementSystem: Starting history cleanup - Original messages: ", thread_messages.size())
	
	var cleaned_messages = []
	var total_chars = 0
	var content_blocks_removed = 0
	var messages_removed = 0
	
	# Process messages in reverse order (keep recent ones)
	for i in range(thread_messages.size() - 1, -1, -1):
		var message = thread_messages[i]
		if not message.has("content"):
			continue
			
		var content = str(message.content)
		var original_length = content.length()
		
		# Remove content source blocks (marked with "--- Context from" and "--- End Context ---")
		var cleaned_content = remove_content_source_blocks(content)
		var cleaned_length = cleaned_content.length()
		
		if cleaned_length != original_length:
			content_blocks_removed += 1
			print("ConversationManagementSystem: Removed content block from message (", original_length - cleaned_length, " chars)")
		
		# If message is now too small or empty, skip it entirely
		if cleaned_length < minimum_message_length:
			messages_removed += 1
			continue
		
		# Check if adding this message would exceed limits
		if (total_chars + cleaned_length > target_char_limit) or (cleaned_messages.size() >= max_messages_to_keep):
			print("ConversationManagementSystem: Stopping history inclusion - hit limit (chars or count)")
			break
		
		# Keep this message
		var cleaned_message = message.duplicate()
		cleaned_message.content = cleaned_content
		cleaned_messages.insert(0, cleaned_message)  # Insert at beginning to maintain order
		total_chars += cleaned_length
	
	# Replace the thread messages with cleaned ones
	if cleaned_messages.size() < thread_messages.size():
		print("ConversationManagementSystem: Replacing ", thread_messages.size(), " messages with ", cleaned_messages.size(), " cleaned messages")
		
		# CRITICAL FIX: Use the new set_thread_messages method to properly update the thread
		if conversation_manager.has_method("set_thread_messages"):
			var set_result = conversation_manager.set_thread_messages(thread_name, cleaned_messages)
			if set_result.success:
				print("ConversationManagementSystem: Successfully replaced thread messages via set_thread_messages")
			else:
				print("ConversationManagementSystem: ERROR - Failed to set thread messages: ", set_result.error)
		else:
			print("ConversationManagementSystem: ERROR - ConversationManager doesn't have set_thread_messages method!")
	
	var result = {
		"content_blocks_removed": content_blocks_removed,
		"messages_removed": messages_removed,
		"total_chars": total_chars,
		"messages_kept": cleaned_messages.size(),
		"original_count": thread_messages.size() + messages_removed + content_blocks_removed
	}
	
	print("ConversationManagementSystem: History cleanup complete - ", result)
	if content_blocks_removed > 0:
		content_blocks_removed.emit(content_blocks_removed)
	
	return result

func remove_content_source_blocks(content: String) -> String:
	"""Remove content source blocks while preserving actual conversation content"""
	if not enable_content_source_filtering:
		return content
	
	var lines = content.split("\n")
	var cleaned_lines = []
	var in_content_block = false
	var blocks_found = 0
	
	for line in lines:
		var trimmed = line.strip_edges()
		
		# Check for start of content block
		if trimmed.begins_with("--- Context from"):
			in_content_block = true
			blocks_found += 1
			continue
		
		# Check for end of content block  
		if trimmed.begins_with("--- End Context ---"):
			in_content_block = false
			continue
		
		# Skip lines inside content blocks
		if in_content_block:
			continue
		
		# Keep non-content lines
		cleaned_lines.append(line)
	
	if blocks_found > 0:
		print("ConversationManagementSystem: Removed ", blocks_found, " content source blocks from message")
	
	return "\n".join(cleaned_lines)

func force_clean_current_thread() -> Dictionary:
	"""Force clean the current conversation thread immediately"""
	if not _validate_conversation_manager():
		return {"error": "Conversation manager not available"}
	
	var cleanup_result = clean_conversation_history(conversation_manager_instance, 4000)
	print("ConversationManagementSystem: Force cleaned current thread - ", cleanup_result)
	return cleanup_result

# ------------------------------------------------------------------
# THREAD MANAGEMENT
# ------------------------------------------------------------------

func initialize_clean_game_thread() -> String:
	"""Initialize a clean game thread for session isolation"""
	if not _validate_conversation_manager():
		return ""
	
	var clean_thread_name = "clean_game_" + str(Time.get_unix_time_from_system())
	
	print("ConversationManagementSystem: Creating clean game thread: ", clean_thread_name)
	
	# Create the new thread
	conversation_manager_instance.create_thread(clean_thread_name)
	
	# Switch to the new thread
	conversation_manager_instance.switch_to_thread(clean_thread_name)
	
	current_session_thread = clean_thread_name
	thread_created.emit(clean_thread_name)
	
	return clean_thread_name

func get_current_thread_info() -> Dictionary:
	"""Get information about the current conversation thread"""
	if not _validate_conversation_manager():
		return {"error": "Conversation manager not available"}
	
	var thread_name = conversation_manager_instance.get_current_thread()
	var thread_messages = conversation_manager_instance.get_thread_messages(thread_name)
	
	var total_chars = _calculate_thread_character_count(thread_messages)
	
	return {
		"thread_name": thread_name,
		"message_count": thread_messages.size(),
		"total_characters": total_chars,
		"is_isolated": thread_name.begins_with("clean_game_"),
		"last_cleanup": last_cleanup_time
	}

func isolate_current_session() -> Dictionary:
	"""Isolate the current session by creating a clean thread"""
	if not enable_session_isolation:
		return {"error": "Session isolation is disabled"}
	
	var clean_thread = initialize_clean_game_thread()
	if clean_thread == "":
		return {"error": "Failed to create clean thread"}
	
	session_isolated.emit(clean_thread)
	return {"success": true, "thread": clean_thread}

func debug_session_isolation() -> Dictionary:
	"""Debug session isolation status"""
	if not _validate_conversation_manager():
		return {"error": "Conversation manager not available"}
	
	var thread_info = get_current_thread_info()
	var thread_name = thread_info.thread_name
	
	# Check for potential context bleeding
	var bleeding_indicators = []
	
	# Check if thread has too much history
	if thread_info.total_characters > default_char_limit * 2:
		bleeding_indicators.append("Excessive history length")
	
	# Check if thread name suggests it's not isolated
	if not thread_name.begins_with("clean_game_"):
		bleeding_indicators.append("Thread not using clean naming convention")
	
	# Check message count
	if thread_info.message_count > 100:
		bleeding_indicators.append("High message count suggests context accumulation")
	
	return {
		"thread_info": thread_info,
		"isolation_enabled": enable_session_isolation,
		"bleeding_detected": not bleeding_indicators.is_empty(),
		"bleeding_indicators": bleeding_indicators,
		"recommendations": _generate_isolation_recommendations(bleeding_indicators)
	}

func _generate_isolation_recommendations(bleeding_indicators: Array) -> Array:
	"""Generate recommendations for session isolation"""
	var recommendations = []
	
	for indicator in bleeding_indicators:
		if indicator == "Excessive history length":
			recommendations.append("Run clean_history() to reduce conversation length")
		elif indicator == "Thread not using clean naming convention":
			recommendations.append("Call isolate_current_session() to create clean thread")
		elif indicator == "High message count suggests context accumulation":
			recommendations.append("Consider more aggressive message cleanup or thread isolation")
	
	if recommendations.is_empty():
		recommendations.append("Session isolation is working properly")
	
	return recommendations

# ------------------------------------------------------------------
# DIALOGUE FILTERING
# ------------------------------------------------------------------

func filter_player_character_dialogue(response: String, player_character_names: Array) -> String:
	"""Filter out narrator descriptions of player character actions and dialogue"""
	if player_character_names.is_empty():
		return response
	
	print("ConversationManagementSystem: Starting player character filtering...")
	print("ConversationManagementSystem: Player character names: ", player_character_names)
	print("ConversationManagementSystem: Original response length: ", response.length())
	
	var original_length = response.length()
	var filtered_lines = []
	var lines = response.split("\n")
	
	for line in lines:
		var should_keep = true
		var trimmed = line.strip_edges()
		
		# Skip empty lines
		if trimmed == "":
			filtered_lines.append(line)
			continue
		
		print("ConversationManagementSystem: Processing line: ", trimmed)
		
		# Check each player character name
		for char_name in player_character_names:
			var char_lower = char_name.to_lower()
			var line_lower = trimmed.to_lower()
			
			# Pattern 1: MOST IMPORTANT - Direct character dialogue
			if line_lower.begins_with(char_lower + ":"):
				should_keep = false
				print("ConversationManagementSystem: Filtered direct player character dialogue: ", char_name)
				break
			
			# Pattern 2: Direct character dialogue attribution by narrator
			if line_lower.begins_with("narrator:") and char_lower in line_lower:
				should_keep = false
				break
			
			# Pattern 3: Character action descriptions
			if ("**" + char_lower + "**") in line_lower:
				should_keep = false
				break
			
			# Pattern 4: Narrator describing character actions
			var narrator_patterns = [
				"narrator: " + char_lower,
				"the narrator: " + char_lower,
				char_lower + " nods",
				char_lower + " shakes",
				char_lower + " pulls out",
				char_lower + " starts",
				char_lower + " begins",
				char_lower + " looks"
			]
			
			for pattern in narrator_patterns:
				if pattern in line_lower:
					should_keep = false
					break
			
			if not should_keep:
				break
		
		if should_keep:
			filtered_lines.append(line)
		else:
			print("ConversationManagementSystem: Filtered player character line: ", trimmed)
	
	var filtered_response = "\n".join(filtered_lines)
	var filtered_length = filtered_response.length()
	
	if filtered_length != original_length:
		dialogue_filtered.emit(original_length, filtered_length)
		print("ConversationManagementSystem: Filtered dialogue - removed ", original_length - filtered_length, " characters")
	
	return filtered_response

# ------------------------------------------------------------------
# NARRATIVE CONTEXT BUILDING
# ------------------------------------------------------------------

func build_narrative_context(recent_messages: Array) -> String:
	"""Build narrative context from recent story events"""
	if recent_messages.size() < 2:
		return ""
	
	# INCREASED FROM 6 TO 15: Longer memory prevents conceptual repetition
	# Short context windows cause characters to forget their own previous arguments
	var recent_count = min(15, recent_messages.size())
	
	# Build message history
	var context = ""
	for i in range(recent_messages.size() - recent_count, recent_messages.size()):
		var entry = recent_messages[i]
		if entry.has("sender") and entry.has("message"):
			if _should_skip_context_entry(entry):
				continue
			context += entry.sender + ": " + entry.message + "\n"
	
	# Extract key arguments per character for conversational continuity
	var character_arguments = _extract_character_arguments(recent_messages, recent_count)
	if not character_arguments.is_empty():
		context += "\n[RECENT POSITIONS TAKEN]:\n"
		for character in character_arguments:
			var args = character_arguments[character]
			if args.size() > 0:
				context += "- " + character + ": " + ", ".join(args) + "\n"
	
	return context

func _extract_character_arguments(messages: Array, count: int) -> Dictionary:
	"""Extract key arguments/positions per character to prevent repetition"""
	var arguments = {}
	var start_index = max(0, messages.size() - count)
	
	for i in range(start_index, messages.size()):
		var entry = messages[i]
		if not entry.has("sender") or not entry.has("message"):
			continue
		if _should_skip_context_entry(entry):
			continue
			
		var sender = entry.sender
		var message = entry.message.to_lower()
		
		# Skip narrator
		if sender == "Narrator":
			continue
		
		# Extract key phrases (sentences containing strong verbs or important nouns)
		var key_phrases = []
		var sentences = message.split(".")
		for sentence in sentences:
			sentence = sentence.strip_edges()
			if sentence.length() < 10:  # Skip very short fragments
				continue
				
			# Look for argument indicators
			if ("need" in sentence or "should" in sentence or "must" in sentence or 
			    "think" in sentence or "believe" in sentence or "suggest" in sentence or
			    "can't" in sentence or "won't" in sentence or "why" in sentence):
				# Trim to first 60 chars for brevity
				var trimmed = sentence.substr(0, min(60, sentence.length()))
				if trimmed.length() < sentence.length():
					trimmed += "..."
				key_phrases.append(trimmed)
		
		# Store unique arguments per character
		if key_phrases.size() > 0:
			if not arguments.has(sender):
				arguments[sender] = []
			# Only keep last 2 arguments per character to avoid bloat
			for phrase in key_phrases:
				if not arguments[sender].has(phrase):
					arguments[sender].append(phrase)
			if arguments[sender].size() > 2:
				arguments[sender] = arguments[sender].slice(-2, arguments[sender].size())

	return arguments

func _should_skip_context_entry(entry: Dictionary) -> bool:
	var sender: String = String(entry.get("sender", "")).strip_edges()
	if sender.is_empty():
		return false
	if sender == "Facilitator Note":
		return true
	return false

func extract_current_topic(recent_messages: Array) -> String:
	"""Extract current conversation topic for flow analysis"""
	if recent_messages.is_empty():
		return ""
	
	# Extract topics from recent messages
	var topics = extract_conversation_topics(recent_messages, 1)
	
	# Return the most prominent topic, or a general description if no topics found
	if topics.size() > 0:
		return topics[0]
	
	# Fallback: try to extract topic from the most recent message
	if recent_messages.size() > 0:
		var last_message = recent_messages[recent_messages.size() - 1]
		var content = str(last_message.get("message", ""))
		if content.length() > 0:
			# Simple topic extraction - look for key nouns
			var words = content.to_lower().split(" ")
			var topic_words = []
			var stop_words = ["the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "a", "an", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "can", "this", "that", "these", "those", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them"]
			
			for word in words:
				word = word.to_lower().lstrip(".,!?;:").rstrip(".,!?;:")
				if word.length() >= 4 and not word in stop_words:
					topic_words.append(word)
			
			if topic_words.size() > 0:
				return topic_words[0]
	
	return "general_conversation"

# ------------------------------------------------------------------
# CONVERSATION FLOW ANALYSIS
# ------------------------------------------------------------------

func analyze_conversation_flow(messages: Array) -> Dictionary:
	"""Analyze conversation flow and quality"""
	if messages.is_empty():
		return {"error": "No messages to analyze"}
	
	var analysis = {
		"total_messages": messages.size(),
		"speakers": {},
		"topics": [],
		"flow_quality": 0.0,
		"coherence_score": 0.0,
		"engagement_level": 0.0
	}
	
	# Analyze speaker distribution
	for message in messages:
		var sender = message.get("sender", "unknown")
		analysis.speakers[sender] = analysis.speakers.get(sender, 0) + 1
	
	# Calculate flow quality
	analysis.flow_quality = _calculate_conversation_health(messages)
	
	# Analyze topic coherence (simplified)
	var content_words = []
	for message in messages:
		var content = str(message.get("content", ""))
		var words = content.split(" ")
		for word in words:
			if word.length() > 4:  # Focus on meaningful words
				content_words.append(word.to_lower())
	
	# Simple coherence based on word repetition
	var word_counts = {}
	for word in content_words:
		word_counts[word] = word_counts.get(word, 0) + 1
	
	var repeated_words = 0
	for word in word_counts:
		if word_counts[word] > 1:
			repeated_words += 1
	
	analysis.coherence_score = float(repeated_words) / max(1, word_counts.size())
	
	# Calculate engagement (based on message length variety)
	var message_lengths = []
	for message in messages:
		var content = str(message.get("content", ""))
		message_lengths.append(content.length())
	
	if message_lengths.size() > 1:
		var avg_length = 0
		for length in message_lengths:
			avg_length += length
		avg_length /= message_lengths.size()
		
		var variance = 0
		for length in message_lengths:
			variance += (length - avg_length) * (length - avg_length)
		variance /= message_lengths.size()
		
		# Higher variance suggests more engagement
		analysis.engagement_level = min(1.0, variance / 10000.0)
	
	return analysis

func extract_conversation_topics(messages: Array, max_topics: int = 5) -> Array:
	"""Extract main topics from conversation"""
	if messages.is_empty():
		return []
	
	var topic_keywords = {}
	var stop_words = ["the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "a", "an", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "can", "this", "that", "these", "those", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them"]
	
	for message in messages:
		var content = str(message.get("content", "")).to_lower()
		var words = content.split(" ")
		
		for word in words:
			# Clean word
			word = word.to_lower().lstrip(".,!?;:").rstrip(".,!?;:")
			
			# Skip short words and stop words
			if word.length() < 4 or word in stop_words:
				continue
			
			topic_keywords[word] = topic_keywords.get(word, 0) + 1
	
	# Sort by frequency
	var sorted_topics = []
	for word in topic_keywords:
		sorted_topics.append({"word": word, "count": topic_keywords[word]})
	
	sorted_topics.sort_custom(func(a, b): return a.count > b.count)
	
	# Return top topics
	var topics = []
	for i in range(min(max_topics, sorted_topics.size())):
		topics.append(sorted_topics[i].word)
	
	return topics

# ------------------------------------------------------------------
# CONFIGURATION AND SETTINGS
# ------------------------------------------------------------------

func set_clean_thread_enabled(enabled: bool):
	"""Enable or disable clean thread usage"""
	use_clean_game_thread = enabled
	print("ConversationManagementSystem: Clean thread usage ", "enabled" if enabled else "disabled")

func get_clean_thread_enabled() -> bool:
	"""Check if clean thread usage is enabled"""
	return use_clean_game_thread

func set_session_isolation_enabled(enabled: bool):
	"""Enable or disable session isolation"""
	enable_session_isolation = enabled
	print("ConversationManagementSystem: Session isolation ", "enabled" if enabled else "disabled")

func set_content_filtering_enabled(enabled: bool):
	"""Enable or disable content source filtering"""
	enable_content_source_filtering = enabled
	print("ConversationManagementSystem: Content source filtering ", "enabled" if enabled else "disabled")

func set_default_char_limit(limit: int):
	"""Set the default character limit for history cleanup"""
	default_char_limit = max(1000, limit)
	print("ConversationManagementSystem: Default character limit set to ", default_char_limit)

func set_minimum_message_length(length: int):
	"""Set the minimum message length to keep during cleanup"""
	minimum_message_length = max(1, length)
	print("ConversationManagementSystem: Minimum message length set to ", minimum_message_length)

func get_configuration() -> Dictionary:
	"""Get current system configuration"""
	return {
		"default_char_limit": default_char_limit,
		"minimum_message_length": minimum_message_length,
		"max_messages_to_keep": max_messages_to_keep,
		"use_clean_game_thread": use_clean_game_thread,
		"enable_session_isolation": enable_session_isolation,
		"enable_content_source_filtering": enable_content_source_filtering,
		"current_session_thread": current_session_thread
	}

# ------------------------------------------------------------------
# UTILITY AND TESTING FUNCTIONS
# ------------------------------------------------------------------

func test_conversation_management() -> Dictionary:
	"""Test conversation management functionality with sample data"""
	print("ConversationManagementSystem: Running test...")
	
	var test_results = {
		"conversation_manager_available": _validate_conversation_manager(),
		"thread_info": {},
		"isolation_test": {},
		"filtering_test": {},
		"cleanup_test": {}
	}
	
	if test_results.conversation_manager_available:
		test_results.thread_info = get_current_thread_info()
		test_results.isolation_test = debug_session_isolation()
		
		# Test dialogue filtering
		var test_response = "**Alice**: I think we should focus on renewable energy.\n**Bob**: That's a great idea, Alice!\nNarrator: The discussion continues."
		var filtered = filter_player_character_dialogue(test_response, ["Alice"])
		test_results.filtering_test = {
			"original_length": test_response.length(),
			"filtered_length": filtered.length(),
			"filtering_worked": filtered.length() < test_response.length()
		}
		
		# Test cleanup (with small limit to see effect)
		var cleanup_result = clean_history(500)
		test_results.cleanup_test = cleanup_result
	
	print("ConversationManagementSystem: Test completed - ", test_results)
	return test_results

func get_system_health() -> float:
	"""Get the health of the conversation management system"""
	var health = 1.0
	
	# Check if conversation manager is available
	if not _validate_conversation_manager():
		return 0.0
	
	var thread_info = get_current_thread_info()
	var thread_messages = conversation_manager_instance.get_thread_messages(thread_info.thread_name)
	
	# Check message count (too many might indicate cleanup issues)
	if thread_messages.size() > 50:
		health *= 0.7
	elif thread_messages.size() > 100:
		health *= 0.5
	
	# Check character count
	if thread_info.total_characters > default_char_limit * 2:
		health *= 0.6
	
	# Check isolation status
	if enable_session_isolation and not thread_info.is_isolated:
		health *= 0.8
	
	# Check for bleeding indicators
	var isolation_debug = debug_session_isolation()
	if isolation_debug.bleeding_detected:
		health *= 0.7
	
	return health

# ------------------------------------------------------------------
# PRIVATE HELPER FUNCTIONS
# ------------------------------------------------------------------

func _validate_conversation_manager() -> bool:
	"""Validate that conversation manager is available"""
	if not conversation_manager_instance:
		print("ConversationManagementSystem: ERROR - No conversation manager set")
		return false
	
	return true

func _calculate_thread_character_count(messages: Array) -> int:
	"""Calculate total character count for thread messages"""
	var total = 0
	for message in messages:
		var content = str(message.get("content", ""))
		total += content.length()
	return total

func _calculate_conversation_health(messages: Array) -> float:
	"""Calculate health score for conversation (0-1)"""
	if messages.is_empty():
		return 0.0
	
	var health = 1.0
	
	# Check message distribution
	var speakers = {}
	for message in messages:
		var sender = message.get("sender", "")
		if sender != "":
			speakers[sender] = speakers.get(sender, 0) + 1
	
	# Penalize if one speaker dominates
	var max_speaker_count = 0
	for speaker in speakers:
		max_speaker_count = max(max_speaker_count, speakers[speaker])
	
	var speaker_balance = 1.0 - (float(max_speaker_count) / messages.size())
	health *= (0.5 + speaker_balance * 0.5)
	
	# Check for appropriate message length distribution
	var very_short_messages = 0
	var very_long_messages = 0
	for message in messages:
		var content = str(message.get("content", ""))
		if content.length() < 10:
			very_short_messages += 1
		elif content.length() > 1000:
			very_long_messages += 1
	
	if very_short_messages > messages.size() * 0.3:
		health *= 0.8
	if very_long_messages > messages.size() * 0.2:
		health *= 0.9
	
	return health

func _generate_conversation_recommendations(thread_info: Dictionary, flow_analysis: Dictionary) -> Array:
	"""Generate recommendations for conversation improvement"""
	var recommendations = []
	
	# Check character limit
	if thread_info.total_characters > default_char_limit:
		recommendations.append("Consider cleaning conversation history - currently at " + str(thread_info.total_characters) + " characters")
	
	# Check message count
	if thread_info.message_count > 50:
		recommendations.append("High message count (" + str(thread_info.message_count) + ") - consider more aggressive cleanup")
	
	# Check isolation
	if enable_session_isolation and not thread_info.is_isolated:
		recommendations.append("Session isolation is enabled but current thread is not isolated")
	
	# Check flow quality
	if flow_analysis.has("flow_quality") and flow_analysis.flow_quality < 0.5:
		recommendations.append("Conversation flow quality is low - consider encouraging more diverse participation")
	
	# Check coherence
	if flow_analysis.has("coherence_score") and flow_analysis.coherence_score < 0.3:
		recommendations.append("Topic coherence is low - conversation may be scattered")
	
	if recommendations.is_empty():
		recommendations.append("Conversation management is operating optimally")
	
	return recommendations 
