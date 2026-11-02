# narration_filter.gd
# Location: ScenSyn/scripts/utils/narration_filter.gd
# Minimal Phase-4 filter: trims duplicate narrator lines and overly long text.

extends Node
class_name NarrationFilter

# helper to detect high word-overlap similarity
static func _too_similar(a: String, b: String) -> bool:
	var wa := a.to_lower().split(" ")
	var wb := b.to_lower().split(" ")
	if wa.size() == 0:
		return false
	var overlap := 0
	for w in wa:
		if wb.has(w):
			overlap += 1
	return float(overlap) / wa.size() > 0.6

# Remove exact duplicates of last narrator line to avoid spam
static func clean(text: String, state: Dictionary) -> String:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return ""
	
	# CHECK FOR CHARACTER HIJACKING - this is the critical missing piece!
	if _contains_character_hijacking(cleaned):
		print("NarrationFilter: Blocking character hijacking: ", cleaned)
		return ""  # Block hijacking content entirely
	
	var story_log_entries: Array = state.get("story_log", [])
	var last_text := ""
	if story_log_entries.size() > 0:
		var last_entry: Dictionary = story_log_entries.back()
		if last_entry.get("sender", "") == "Narrator":
			last_text = last_entry.get("message", "").strip_edges()
			if cleaned == last_text or _too_similar(cleaned, last_text):
				return ""  # skip duplicate or too-similar line
	# Limit narrator message length to 400 chars
	var max_len := int(ProjectSettings.get_setting("scensyn/narrator/max_chars", 400))
	if cleaned.length() > max_len:
		cleaned = cleaned.substr(0, max_len) + " …"
	return cleaned

# Check if narrator content contains character hijacking
static func _contains_character_hijacking(text: String) -> bool:
	var text_lower = text.to_lower()
	
	# Character names to check for hijacking
	var character_names = ["astrid", "jason", "ingrid", "nathan", "erik", "marie", "lars", "kari"]
	
	# STRICT hijacking patterns - only block if narrator is making characters SPEAK or make DECISIONS
	var hijacking_patterns = [
		"says", "said", "replies", "replied", "responds", "responded", 
		"asks", "asked", "tells", "told", "explains", "explained",
		"decides", "decided", "chooses", "chose", "thinks", "thought",
		"believes", "felt that", "concluded", "realized"
	]
	
	# Check for character name + hijacking pattern (speaking/deciding)
	for character_name in character_names:
		if character_name in text_lower:
			for pattern in hijacking_patterns:
				if pattern in text_lower:
					# This is likely hijacking - narrator making character speak/decide
					return true
			
			# Also check for direct speech patterns like "Character: dialogue"
			if character_name + ":" in text_lower:
				return true
	
	# Allow environmental descriptions and external observations
	# These are valid narrator content:
	# - "Astrid nods thoughtfully" (external observation)
	# - "The room falls silent as Jason considers" (environmental description)
	# - "Ingrid's expression shows concern" (external observation)
	
	return false 

static func aggressive_narrator_filter(response: String, player_controlled_names: Array, ai_character_names: Array) -> Dictionary:
	var lines := response.split("\n")
	var filtered_lines: Array = []
	var narrator_line_count := 0
	var max_narrator_lines := 2
	var hijacking_detected := 0
	var narrator_removed := 0

	var all_character_names: Array = []
	all_character_names.append_array(player_controlled_names)
	all_character_names.append_array(ai_character_names)

	for line in lines:
		var trimmed_line := line.strip_edges()
		if trimmed_line.is_empty():
			filtered_lines.append(line)
			continue
		if trimmed_line.begins_with("Narrator:"):
			var narrator_content := trimmed_line.substr(9).strip_edges()
			var contains_character_hijacking := false
			for character_name_any in all_character_names:
				var character_name := str(character_name_any).strip_edges()
				if character_name.is_empty():
					continue
				var char_lower := character_name.to_lower()
				var content_lower := narrator_content.to_lower()
				if char_lower in content_lower:
					var hijacking_patterns := [
						char_lower + " smiled",
						char_lower + " leaned",
						char_lower + " looked",
						char_lower + " nodded",
						char_lower + " frowned",
						char_lower + " eyes",
						char_lower + " face",
						char_lower + " voice",
						char_lower + " expression",
						char_lower + " turned",
						char_lower + " moved",
						char_lower + " stepped",
						char_lower + " walked",
						char_lower + " sat",
						char_lower + " stood",
						char_lower + " reached",
						char_lower + " pulled",
						char_lower + " grabbed",
						char_lower + " held",
						char_lower + " spoke",
						char_lower + " said",
						char_lower + " replied",
						char_lower + " responded",
						char_lower + " thought",
						char_lower + " felt",
						char_lower + " considered",
					]
					for pattern in hijacking_patterns:
						if pattern in content_lower:
							contains_character_hijacking = true
							hijacking_detected += 1
							break
				if contains_character_hijacking:
					break
			if contains_character_hijacking:
				continue
			if narrator_line_count >= max_narrator_lines:
				narrator_removed += 1
				continue
			narrator_line_count += 1
		filtered_lines.append(line)

	var filtered_response := "\n".join(filtered_lines)
	return {
		"text": filtered_response,
		"hijacking_detected": hijacking_detected,
		"narrator_lines_removed": narrator_removed,
	}

static func looks_like_environmental_description(text: String) -> bool:
	var text_lower := text.to_lower().strip_edges()
	if text_lower.is_empty() or ":" in text:
		return false
	var environmental_patterns := [
		"as they", "as the", "the lights", "the room", "the air", "the sound",
		"suddenly", "meanwhile", "in the distance", "outside", "nearby",
		"the atmosphere", "the building", "the city", "the grid", "the system",
		"a faint", "a sudden", "a gentle", "a loud", "a soft",
		"flickered", "hummed", "echoed", "emanated", "filled",
		"the group exchanged", "they looked", "everyone turned",
		"silence fell", "tension filled", "the meeting", "the discussion",
	]
	for pattern in environmental_patterns:
		if text_lower.begins_with(pattern):
			return true
	if text_lower.begins_with("the ") or text_lower.begins_with("a ") or text_lower.begins_with("an ") or "began to" in text_lower or "started to" in text_lower or "seemed to" in text_lower:
		return true
	return false

static func split_mixed_narrator_content(text: String, character_names: Array) -> Array:
	var result: Array = []
	var character_name := ""
	var dialogue_text := ""
	var environmental_part := ""

	for candidate_name_any in character_names:
		var candidate_name := str(candidate_name_any).strip_edges()
		if not candidate_name.is_empty() and candidate_name in text:
			character_name = candidate_name
			break

	var quote_start := text.find('"')
	var quote_end := text.rfind('"')
	if quote_start != -1 and quote_end != -1 and quote_start < quote_end:
		dialogue_text = text.substr(quote_start + 1, quote_end - quote_start - 1)
		environmental_part = text.substr(0, quote_start).strip_edges()
		if environmental_part.ends_with(".") and not environmental_part.ends_with("..."):
			environmental_part = environmental_part.substr(0, environmental_part.length() - 1).strip_edges()

	if not character_name.is_empty() and not dialogue_text.is_empty():
		if not environmental_part.is_empty():
			result.append({"speaker": "Narrator", "message": environmental_part})
		result.append({"speaker": character_name, "message": dialogue_text})
	else:
		result.append({"speaker": "Narrator", "message": text})
	return result