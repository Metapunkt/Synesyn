extends RefCounted
class_name DialogueProcessingSystem

"""
Dialogue Processing System

This system provides:
- Dialogue quality improvement through text processing
- Adverb and emotion tag conversion
- Action tag formatting
- Character voice consistency tracking
- Speech pattern analysis
- Repetitive pattern reduction

Usage:
	var dialogue_processor = DialogueProcessingSystem.new()
	dialogue_processor.initialize()
	var improved_text = dialogue_processor.improve_dialogue_quality(original_text)
"""

# IMPORTANT: This module is scenario-agnostic.
# - Do NOT hardcode character names, scenario terms, or theme-specific diction here.
# - Keep transformations structural (tags/format), not content-styling. Any stylistic shaping
#   should be requested by scenarios via prompts or manager flags outside this file.

# Signal definitions
signal voice_pattern_detected(character_name: String, pattern: String)
signal dialogue_quality_improved(original_length: int, improved_length: int)
signal character_voice_updated(character_name: String, voice_data: Dictionary)

# Core data structures
var character_voice_tracker = {}

# Configuration
var max_voice_patterns = 10
var max_vocabulary_tracking = 100
var sentence_length_threshold_long = 50
var sentence_length_threshold_short = 20
var complex_word_threshold = 6
var complex_word_ratio_threshold = 0.3

func _init():
	"""Initialize the dialogue processing system"""
	initialize()

func initialize():
	"""Initialize the dialogue processing system"""
	character_voice_tracker = {}
	print("DialogueProcessingSystem: Initialized")

# ------------------------------------------------------------------
# PUBLIC API - MAIN PROCESSING FUNCTIONS
# ------------------------------------------------------------------

func improve_dialogue_quality(text: String) -> String:
	"""Apply dialogue quality improvements: adverb reduction, emotion integration,
	character voice consistency, and show-don't-tell enhancements"""
	var original_length = text.length()
	var improved_text = text

	# Phase 0: Clean up malformed tags first
	improved_text = clean_malformed_tags(improved_text)
	
	# Phase 1: Convert common adverb tags to integrated dialogue
	improved_text = convert_adverb_tags(improved_text)
	
	# Phase 2: Convert emotion tags to natural expressions
	improved_text = convert_emotion_tags(improved_text)
	
	# Phase 3: Reduce repetitive speech patterns
	improved_text = reduce_repetitive_patterns(improved_text)
	
	# Phase 4: Convert remaining action tags to bracket format
	improved_text = convert_action_tags_to_brackets(improved_text)
	
	var improved_length = improved_text.length()
	dialogue_quality_improved.emit(original_length, improved_length)
	
	print("DialogueProcessingSystem: Applied dialogue quality improvements")
	return improved_text

func clean_malformed_tags(text: String) -> String:
	"""Clean up malformed or nested tags that could cause processing issues"""
	var cleaned = text
	
	# Remove malformed nested brackets like [[character:.][.]action]
	var malformed_regex = RegEx.new()
	malformed_regex.compile("\\[\\[[^\\]]*\\]\\.[^\\]]*\\]")
	cleaned = malformed_regex.sub(cleaned, "", true)
	
	# Remove double asterisks without content
	cleaned = cleaned.replace("**", "")
	
	# Remove orphaned colons and periods in brackets
	var orphan_regex = RegEx.new()
	orphan_regex.compile("\\[[:\\.\\s]*\\]")
	cleaned = orphan_regex.sub(cleaned, "", true)
	
	# Clean up multiple spaces
	while "  " in cleaned:
		cleaned = cleaned.replace("  ", " ")
	
	return cleaned

func convert_adverb_tags(text: String) -> String:
	"""Convert common adverb tags to integrated dialogue"""
	var conversions = {
		"*analytically*": "",
		"*urgently*": "",  # Remove - urgency should be in content
		"*thoughtfully*": "Let me think about this.",
		"*carefully*": "",  # Remove - precision should be in content
		"*enthusiastically*": "",  # Remove - enthusiasm should be in content
		"*concerned*": "I'm concerned.",
		"*confidently*": "",  # Remove - confidence should be in content
		"*hesitantly*": "I'm not sure, but ",
		"*firmly*": "",  # Remove - firmness should be in content
		"*quietly*": "",  # Remove - unless necessary for scene
		"*loudly*": "",  # Remove - unless necessary for scene
		"*seriously*": "This is important.",
		"*curiously*": "I'm wondering.",
		"*skeptically*": "I have doubts.",
		"*nervously*": "I'm nervous, but ",
		"*calmly*": "",  # Remove - calmness should be in content
		"*angrily*": "",  # Remove - anger should be in word choice
		"*sadly*": "",  # Remove - sadness should be in content
		"*happily*": "",  # Remove - happiness should be in content
		"*excitedly*": "",  # Remove - excitement should be in content
		"*worriedly*": "I'm concerned.",
		"*determinedly*": "",  # Remove - determination should be in content
		"*hopefully*": "I hope.",
		"*doubtfully*": "I'm not sure."
	}
	
	var improved = text
	for tag in conversions.keys():
		var replacement = conversions[tag]
		improved = improved.replace(tag, replacement)
	
	return improved

func convert_emotion_tags(text: String) -> String:
	"""Convert emotion tags to natural dialogue expressions"""
	var conversions = {
		"*worried*": "I'm concerned.",
		"*excited*": "",  # Remove - excitement should be in content
		"*frustrated*": "This is frustrating.",
		"*relieved*": "That's a relief.",
		"*surprised*": "I didn't expect that.",
		"*disappointed*": "That's disappointing.",
		"*hopeful*": "I hope.",
		"*nervous*": "I'm nervous.",
		"*angry*": "",  # Remove - anger should be in word choice
		"*sad*": "",  # Remove - sadness should be in content
		"*confused*": "I don't understand.",
		"*determined*": "",  # Remove - determination should be in content
		"*grateful*": "Thank you.",
		"*impressed*": "That's impressive.",
		"*curious*": "I'm curious.",
		"*skeptical*": "I have doubts.",
		"*pleased*": "I'm glad.",
		"*concerned*": "I'm worried.",
		"*confident*": "",  # Remove - confidence should be in content
		"*uncertain*": "I'm not sure.",
		"*optimistic*": "I think things will work out.",
		"*pessimistic*": "I'm not sure this will work.",
		"*thoughtful*": "Let me consider this.",
		"*amused*": "That's interesting.",
		"*embarrassed*": "This is awkward."
	}
	
	var improved = text
	for tag in conversions.keys():
		var replacement = conversions[tag]
		improved = improved.replace(tag, replacement)
	
	return improved

func reduce_repetitive_patterns(text: String) -> String:
	"""Reduce repetitive speech patterns and overused phrases"""
	var patterns_to_vary = {
		"I think": ["I believe", "It seems to me", "In my view", "My sense is", "I suspect"],
		"I believe": ["I think", "It appears", "I suspect", "I'm convinced", "My view is"],
		"We need to": ["Perhaps we could", "We might", "Consider", "Suppose we", "Maybe we could"],
		"We should": ["Perhaps we could", "We might", "Consider", "Suppose we", "Maybe we could"],
		"What if": ["Suppose", "Consider if", "What about", "How about", "Imagine if"],
		"I understand": ["I see", "I get it", "That makes sense", "I follow", "I comprehend"],
		"Let me": ["I'll", "Allow me to", "Perhaps I could", "Maybe I can", "I might"],
		"You know": ["You see", "You understand", "As you know", "Obviously", "Clearly"],
		"Of course": ["Naturally", "Obviously", "Certainly", "Indeed", "Clearly"],
		"Actually": ["In fact", "Really", "Truth is", "Honestly", "To be honest"],
		"Basically": ["Essentially", "Fundamentally", "In essence", "Simply put", "At its core"],
		"Honestly": ["Truthfully", "Frankly", "To be frank", "Actually", "In reality"]
	}
	
	var improved = text
	var lines = improved.split("\n")
	
	# Track usage counts across the entire response
	var usage_counts = {}
	
	for i in range(lines.size()):
		var line = lines[i]
		for pattern in patterns_to_vary.keys():
			if line.find(pattern) != -1:
				if not usage_counts.has(pattern):
					usage_counts[pattern] = 0
				usage_counts[pattern] += 1
				
				# If this pattern has been used before, vary it
				if usage_counts[pattern] > 1:
					var alternatives = patterns_to_vary[pattern]
					var replacement = alternatives[usage_counts[pattern] % alternatives.size()]
					lines[i] = line.replace(pattern, replacement)
	
	return "\n".join(lines)

func convert_action_tags_to_brackets(text: String) -> String:
	"""Convert remaining *action* tags to [Action] format with proper capitalization"""
	var regex = RegEx.new()
	regex.compile("\\*([^*]+)\\*")
	
	var improved = text
	var results = regex.search_all(improved)
	
	# Process in reverse order to maintain string positions
	for i in range(results.size() - 1, -1, -1):
		var result = results[i]
		var action = result.get_string(1).strip_edges()
		
		# Skip if this looks like dialogue content rather than action
		if action.find("said") != -1 or action.find("asked") != -1 or action.find("replied") != -1:
			continue
		
		# Skip if action is empty or contains problematic characters
		if action.is_empty() or action.find("[") != -1 or action.find("]") != -1:
			# Just remove the malformed tag
			improved = improved.substr(0, result.get_start()) + improved.substr(result.get_end())
			continue
		
		# Capitalize first letter and add proper punctuation
		var formatted_action = action.capitalize()
		if not formatted_action.ends_with(".") and not formatted_action.ends_with("!") and not formatted_action.ends_with("?"):
			formatted_action += "."
		
		var bracket_format = "[" + formatted_action + "]"
		improved = improved.substr(0, result.get_start()) + bracket_format + improved.substr(result.get_end())
	
	return improved

# ------------------------------------------------------------------
# CHARACTER VOICE CONSISTENCY TRACKING
# ------------------------------------------------------------------

func track_character_voice_consistency(text: String):
	"""Track character speech patterns to maintain voice consistency"""
	var lines = text.split("\n")
	
	for line in lines:
		var parts = line.split(":", true, 1)
		if parts.size() == 2:
			var speaker = parts[0].strip_edges().replace("**", "").replace("[b]", "").replace("[/b]", "")
			var dialogue = parts[1].strip_edges()
			
			if speaker != "Narrator" and speaker != "System" and dialogue.length() > 10:
				if not character_voice_tracker.has(speaker):
					character_voice_tracker[speaker] = {
						"speech_patterns": [],
						"vocabulary_usage": {},
						"sentence_length_avg": 0.0,
						"message_count": 0,
						"last_updated": Time.get_unix_time_from_system()
					}
				
				var tracker = character_voice_tracker[speaker]
				tracker.message_count += 1
				tracker.last_updated = Time.get_unix_time_from_system()
				
				# Track sentence length
				var sentences = dialogue.split(".")
				var total_length = 0
				for sentence in sentences:
					total_length += sentence.length()
				var avg_length = total_length / max(1, sentences.size())
				tracker.sentence_length_avg = (tracker.sentence_length_avg * (tracker.message_count - 1) + avg_length) / tracker.message_count
				
				# Track common speech patterns
				var dialogue_lower = dialogue.to_lower()
				var patterns = ["i think", "i believe", "we should", "we need to", "let's", "what if", "i understand", "you know", "of course", "actually", "basically", "honestly"]
				for pattern in patterns:
					if pattern in dialogue_lower:
						if not tracker.speech_patterns.has(pattern):
							tracker.speech_patterns.append(pattern)
							voice_pattern_detected.emit(speaker, pattern)
						
						# Keep only recent patterns
						if tracker.speech_patterns.size() > max_voice_patterns:
							tracker.speech_patterns = tracker.speech_patterns.slice(-max_voice_patterns)
				
				# Track vocabulary complexity
				var words = dialogue.split(" ")
				for word in words:
					var clean_word = word.to_lower().lstrip(".,!?;:").rstrip(".,!?;:")
					if clean_word.length() > 3:  # Only track longer words
						if not tracker.vocabulary_usage.has(clean_word):
							tracker.vocabulary_usage[clean_word] = 0
						tracker.vocabulary_usage[clean_word] += 1
				
				# Keep vocabulary tracking manageable
				if tracker.vocabulary_usage.size() > max_vocabulary_tracking:
					var sorted_words = tracker.vocabulary_usage.keys()
					sorted_words.sort_custom(func(a, b): return tracker.vocabulary_usage[a] > tracker.vocabulary_usage[b])
					var new_vocab = {}
					for i in range(min(max_vocabulary_tracking, sorted_words.size())):
						new_vocab[sorted_words[i]] = tracker.vocabulary_usage[sorted_words[i]]
					tracker.vocabulary_usage = new_vocab
				
				# Emit voice update signal
				character_voice_updated.emit(speaker, tracker)

func get_character_voice_guidance(speaker: String) -> String:
	"""Get voice consistency guidance for a specific character"""
	if not character_voice_tracker.has(speaker):
		return ""
	
	var tracker = character_voice_tracker[speaker]
	var guidance = "\n[VOICE CONSISTENCY for " + speaker + ": "
	
	# Sentence length guidance
	if tracker.sentence_length_avg > sentence_length_threshold_long:
		guidance += "Tends to speak in longer, more complex sentences. "
	elif tracker.sentence_length_avg < sentence_length_threshold_short:
		guidance += "Tends to speak in short, direct sentences. "
	
	# Speech pattern guidance
	if tracker.speech_patterns.size() > 0:
		guidance += "Common patterns: " + ", ".join(tracker.speech_patterns.slice(0, 3)) + ". "
	
	# Vocabulary complexity
	var complex_words = 0
	for word in tracker.vocabulary_usage.keys():
		if word.length() > complex_word_threshold:
			complex_words += 1
	
	if complex_words > tracker.vocabulary_usage.size() * complex_word_ratio_threshold:
		guidance += "Uses technical/complex vocabulary. "
	else:
		guidance += "Uses simpler, more accessible language. "
	
	guidance += "]"
	return guidance

# ------------------------------------------------------------------
# ANALYSIS AND REPORTING
# ------------------------------------------------------------------

func get_character_voice_analysis(character_name: String) -> Dictionary:
	"""Get detailed voice analysis for a specific character"""
	if not character_voice_tracker.has(character_name):
		return {}
	
	var tracker = character_voice_tracker[character_name]
	var analysis = {
		"character_name": character_name,
		"message_count": tracker.message_count,
		"average_sentence_length": tracker.sentence_length_avg,
		"speech_patterns": tracker.speech_patterns,
		"vocabulary_size": tracker.vocabulary_usage.size(),
		"last_updated": tracker.last_updated
	}
	
	# Calculate vocabulary complexity
	var complex_words = 0
	var total_word_usage = 0
	for word in tracker.vocabulary_usage.keys():
		if word.length() > complex_word_threshold:
			complex_words += 1
		total_word_usage += tracker.vocabulary_usage[word]
	
	analysis["vocabulary_complexity"] = float(complex_words) / tracker.vocabulary_usage.size() if tracker.vocabulary_usage.size() > 0 else 0.0
	analysis["total_word_usage"] = total_word_usage
	
	# Determine speech style
	if tracker.sentence_length_avg > sentence_length_threshold_long:
		analysis["speech_style"] = "verbose"
	elif tracker.sentence_length_avg < sentence_length_threshold_short:
		analysis["speech_style"] = "concise"
	else:
		analysis["speech_style"] = "balanced"
	
	return analysis

func get_all_character_voice_data() -> Dictionary:
	"""Get voice data for all tracked characters"""
	var all_data = {}
	for character_name in character_voice_tracker.keys():
		all_data[character_name] = get_character_voice_analysis(character_name)
	return all_data

func get_dialogue_processing_report() -> Dictionary:
	"""Generate a comprehensive dialogue processing report"""
	var report = {
		"total_characters_tracked": character_voice_tracker.size(),
		"character_voice_data": get_all_character_voice_data(),
		"system_config": {
			"max_voice_patterns": max_voice_patterns,
			"max_vocabulary_tracking": max_vocabulary_tracking,
			"sentence_length_threshold_long": sentence_length_threshold_long,
			"sentence_length_threshold_short": sentence_length_threshold_short,
			"complex_word_threshold": complex_word_threshold,
			"complex_word_ratio_threshold": complex_word_ratio_threshold
		}
	}
	
	# Add summary statistics
	var total_messages = 0
	var total_patterns = 0
	var total_vocabulary = 0
	
	for character_name in character_voice_tracker.keys():
		var tracker = character_voice_tracker[character_name]
		total_messages += tracker.message_count
		total_patterns += tracker.speech_patterns.size()
		total_vocabulary += tracker.vocabulary_usage.size()
	
	report["summary"] = {
		"total_messages_processed": total_messages,
		"total_speech_patterns": total_patterns,
		"total_vocabulary_words": total_vocabulary,
		"average_messages_per_character": float(total_messages) / character_voice_tracker.size() if character_voice_tracker.size() > 0 else 0.0
	}
	
	return report

# ------------------------------------------------------------------
# UTILITY AND MANAGEMENT FUNCTIONS
# ------------------------------------------------------------------

func reset_character_voice_data(character_name: String):
	"""Reset voice tracking data for a specific character"""
	if character_voice_tracker.has(character_name):
		character_voice_tracker.erase(character_name)
		print("DialogueProcessingSystem: Reset voice data for ", character_name)

func clear_all_voice_data():
	"""Clear all character voice tracking data"""
	character_voice_tracker.clear()
	print("DialogueProcessingSystem: Cleared all voice tracking data")

func update_configuration(config: Dictionary):
	"""Update system configuration"""
	if config.has("max_voice_patterns"):
		max_voice_patterns = config.max_voice_patterns
	if config.has("max_vocabulary_tracking"):
		max_vocabulary_tracking = config.max_vocabulary_tracking
	if config.has("sentence_length_threshold_long"):
		sentence_length_threshold_long = config.sentence_length_threshold_long
	if config.has("sentence_length_threshold_short"):
		sentence_length_threshold_short = config.sentence_length_threshold_short
	if config.has("complex_word_threshold"):
		complex_word_threshold = config.complex_word_threshold
	if config.has("complex_word_ratio_threshold"):
		complex_word_ratio_threshold = config.complex_word_ratio_threshold
	
	print("DialogueProcessingSystem: Configuration updated")

func get_configuration() -> Dictionary:
	"""Get current system configuration"""
	return {
		"max_voice_patterns": max_voice_patterns,
		"max_vocabulary_tracking": max_vocabulary_tracking,
		"sentence_length_threshold_long": sentence_length_threshold_long,
		"sentence_length_threshold_short": sentence_length_threshold_short,
		"complex_word_threshold": complex_word_threshold,
		"complex_word_ratio_threshold": complex_word_ratio_threshold
	}

func get_character_names() -> Array:
	"""Get list of all tracked character names"""
	return character_voice_tracker.keys()

func has_character_data(character_name: String) -> bool:
	"""Check if we have voice data for a specific character"""
	return character_voice_tracker.has(character_name)

# ------------------------------------------------------------------
# TESTING AND DEBUGGING
# ------------------------------------------------------------------

func test_with_sample_dialogue():
	"""Test the dialogue processing system with sample data"""
	print("DialogueProcessingSystem: Testing with sample dialogue...")
	
	var sample_texts = [
		"Ingrid Tog: *thoughtfully* I think we should *carefully* consider this proposal. *worried* What if it doesn't work?",
		"Marcus Chen: *enthusiastically* I believe this is the right approach! *confidently* We need to move forward.",
		"Dr. Sarah Kim: *analytically* Looking at the data, I think we should proceed. *hesitantly* I'm not sure about the timeline though.",
		"Narrator: *The group pauses to consider the implications.*"
	]
	
	for text in sample_texts:
		print("Original: ", text)
		var improved = improve_dialogue_quality(text)
		print("Improved: ", improved)
		track_character_voice_consistency(improved)
		print("---")
	
	# Test voice guidance
	for character_name in character_voice_tracker.keys():
		var guidance = get_character_voice_guidance(character_name)
		print("Voice guidance for ", character_name, ": ", guidance)
	
	print("DialogueProcessingSystem: Test completed")

func debug_system_state():
	"""Debug function to print current system state"""
	print("=== DIALOGUE PROCESSING SYSTEM DEBUG ===")
	print("Characters tracked: ", character_voice_tracker.size())
	print("Configuration: ", get_configuration())
	
	for character_name in character_voice_tracker.keys():
		var analysis = get_character_voice_analysis(character_name)
		print("Character: ", character_name)
		print("  Messages: ", analysis.message_count)
		print("  Avg sentence length: ", analysis.average_sentence_length)
		print("  Speech patterns: ", analysis.speech_patterns)
		print("  Vocabulary size: ", analysis.vocabulary_size)
		print("  Speech style: ", analysis.speech_style)
		print("  Vocabulary complexity: ", analysis.vocabulary_complexity)
	
	print("=== END DEBUG ===")

func get_system_health() -> float:
	"""Get the health of the dialogue processing system"""
	var health = 1.0
	
	# Check if we have character data
	if character_voice_tracker.size() == 0:
		health *= 0.5
	
	# Check for recent activity
	var current_time = Time.get_unix_time_from_system()
	var recent_activity = false
	
	for character_name in character_voice_tracker.keys():
		var tracker = character_voice_tracker[character_name]
		if current_time - tracker.last_updated < 3600:  # Activity in last hour
			recent_activity = true
			break
	
	if not recent_activity and character_voice_tracker.size() > 0:
		health *= 0.8
	
	return health

func get_system_status() -> Dictionary:
	"""Get system status for reporting"""
	var total_messages = 0
	var total_patterns = 0
	
	# Calculate totals from character voice tracker
	for character_name in character_voice_tracker.keys():
		var tracker = character_voice_tracker[character_name]
		total_messages += tracker.message_count
		total_patterns += tracker.speech_patterns.size()
	
	return {
		"dialogue_processor": {
			"status": "healthy",
			"total_processed": total_messages,
			"voice_patterns_tracked": total_patterns,
			"characters_tracked": character_voice_tracker.size(),
			"last_processing_time": Time.get_unix_time_from_system()
		}
	}

func is_narrator_hijacking(text: String, player_names: Array) -> bool:
	"""Check if narrator is hijacking player character actions"""
	# If there are no players, there's nothing to hijack.
	if player_names.is_empty():
		return false

	var patterns = [
		# Original action verbs - more comprehensive
		"(?i)Narrator:[^\\n]*%s\\s+(leaves|strides|decides|walks|runs|storms out|turns|stands|remains|asserts|refuses|says|thinks|feels|wonders|departs|exits|goes away|walks away|moves|steps|approaches|retreats|gestures|points|reaches|grabs|takes|holds|picks up|puts down|opens|closes)",
		
		# Emotional expressions and reactions
		"(?i)Narrator:[^\\n]*%s\\s+(smiles|frowns|laughs|cries|sighs|gasps|nods|shakes|shrugs|winces|grimaces|beams|grins|scowls|glares|stares|looks|glances|peers|squints)",
		
		# Speech and communication actions
		"(?i)Narrator:[^\\n]*%s\\s+(suggests|mentions|proposes|recommends|indicates|implies|notes|observes|points out|brings up|explains|continues|adds|responds|replies|answers|questions|speaks|talks|whispers|shouts|calls out|interrupts|interjects)",
		
		# Internal state descriptions - expanded
		"(?i)Narrator:[^\\n]*%s's\\s+(eyes|face|expression|voice|thoughts|mind|attention|heart|soul|spirit|feelings|emotions|mood|demeanor|attitude|posture|stance)",
		
		# Physical descriptions and actions
		"(?i)Narrator:[^\\n]*%s\\s+(sits|stands|leans|bends|stretches|relaxes|tenses|straightens|slouches|crosses|uncrosses|folds|unfolds)",
		
		# Character dialogue attribution by narrator
		"(?i)%s:\\s*[^\\n]*\\s*Narrator:",
		
		# General pattern: Narrator mentions player character doing anything
		"(?i)Narrator:[^\\n]*%s\\s+[a-z]+",
		
		# Pattern for when narrator describes player character with descriptive phrases
		"(?i)Narrator:[^\\n]*%s,\\s+[a-z]+",
		
		# Pattern for possessive descriptions (Astrid's tablet, etc.)
		"(?i)Narrator:[^\\n]*%s's\\s+[a-z]+",
		
		# Pattern for any narrator description starting with player name
		"(?i)Narrator:\\s*%s\\s+[a-z]+",
		
		# Pattern for narrator describing what player character "pulled out", "began to", etc.
		"(?i)Narrator:[^\\n]*%s\\s+(pulled out|began to|started to|proceeded to|went on to|continued to)"
	]
	
	var regex = RegEx.new()
	
	# Loop through each player-controlled character name.
	for player_name in player_names:
		# For each name, check against all hijacking patterns.
		for pattern_str in patterns:
			# Format the pattern with the current player's name.
			regex.compile(pattern_str % player_name)
			var result = regex.search(text)
			
			# If a match is found for ANY player, we have detected a hijack.
			# Return true immediately.
			if result != null:
				print("DialogueProcessor: Narrator hijacking detected - Pattern: ", pattern_str % player_name)
				print("DialogueProcessor: Matched text: ", result.get_string())
				return true
	
	# If the loops complete without finding any matches, no hijacking occurred.
	return false

func filter_hijacked_action(text: String, player_name: String) -> String:
	"""Filter out hijacked actions from narrator text"""
	# Split by lines instead of sentences to better handle multi-line narrator descriptions
	var lines = text.split("\n")
	var filtered_lines = []
	
	# More comprehensive pattern for filtering
	var patterns = [
		"(?i)Narrator:[^\\n]*%s\\s+[a-z]+",
		"(?i)Narrator:[^\\n]*%s,\\s+[a-z]+",
		"(?i)Narrator:[^\\n]*%s's\\s+[a-z]+",
		"(?i)Narrator:\\s*%s\\s+[a-z]+"
	]
	
	for line in lines:
		var should_keep = true
		var trimmed_line = line.strip_edges()
		
		# Skip empty lines
		if trimmed_line == "":
			filtered_lines.append(line)
			continue
		
		# Check each pattern
		for pattern_str in patterns:
			var regex = RegEx.new()
			regex.compile(pattern_str % player_name)
			if regex.search(trimmed_line) != null:
				print("DialogueProcessor: Filtering out hijacked line: '", trimmed_line, "'")
				should_keep = false
				break
		
		if should_keep:
			filtered_lines.append(line)
	
	return "\n".join(filtered_lines) 
