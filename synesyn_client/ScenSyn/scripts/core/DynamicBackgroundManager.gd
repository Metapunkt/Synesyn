class_name DynamicBackgroundManager
extends RefCounted

## DynamicBackgroundManager
## Metadata-driven background discovery and AI location matching system
## Discovers backgrounds from assets folder and matches AI descriptions to available locations

# Static data for background management
static var available_backgrounds: Dictionary = {}  # filename -> metadata
static var background_descriptions: Dictionary = {}  # description_text -> filename
static var is_initialized: bool = false

## Initialize background system from assets folder
static func initialize_from_assets_folder():
	available_backgrounds.clear()
	background_descriptions.clear()
	
	var assets_dir = "res://ScenSyn/story_stage/assets/images/"
	var dir = DirAccess.open(assets_dir)
	
	if not dir:
		push_warning("DynamicBackgroundManager: Cannot access assets directory: " + assets_dir)
		is_initialized = true  # Mark as initialized to prevent repeated attempts
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var backgrounds_found = 0
	
	while file_name != "":
		if file_name.ends_with(".png") and not file_name.ends_with(".import"):
			var bg_name = file_name.get_basename()
			var metadata_file = assets_dir + bg_name + ".json"
			
			if ResourceLoader.exists(metadata_file):
				load_background_metadata(bg_name, metadata_file)
				backgrounds_found += 1
			else:
				# Create basic entry for backgrounds without metadata
				available_backgrounds[bg_name] = {
					"description": "A location called " + bg_name.replace("_", " "),
					"ai_instructions": "",
					"tags": [],
					"mood": "neutral"
				}
				backgrounds_found += 1
				print("DynamicBackgroundManager: Background found without metadata: ", bg_name)
		
		file_name = dir.get_next()
	
	is_initialized = true
	print("DynamicBackgroundManager: Loaded ", backgrounds_found, " backgrounds")

## Load background metadata from JSON file
static func load_background_metadata(bg_name: String, metadata_path: String):
	var file = FileAccess.open(metadata_path, FileAccess.READ)
	if not file:
		push_warning("DynamicBackgroundManager: Cannot read metadata: " + metadata_path)
		return
	
	var json_string = file.get_as_text()
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("DynamicBackgroundManager: Invalid JSON in: " + metadata_path)
		return
	
	var metadata = json.data
	
	# Validate required fields and set defaults
	if not metadata.has("description"):
		metadata["description"] = "A location called " + bg_name.replace("_", " ")
	if not metadata.has("ai_instructions"):
		metadata["ai_instructions"] = ""
	if not metadata.has("tags"):
		metadata["tags"] = []
	if not metadata.has("mood"):
		metadata["mood"] = "neutral"
	
	available_backgrounds[bg_name] = metadata
	
	# Index by description for AI matching
	background_descriptions[metadata["description"]] = bg_name
	
	print("DynamicBackgroundManager: Loaded metadata for: ", bg_name)

## Detect location change from AI text
static func detect_location_change_from_ai(ai_text: String, current_location: String = "") -> String:
	if not is_initialized:
		initialize_from_assets_folder()
	
	if available_backgrounds.is_empty():
		return current_location
	
	var best_match = ""
	var best_score = 0
	
	# Check each available background against the AI text
	for bg_name in available_backgrounds:
		var metadata = available_backgrounds[bg_name]
		var score = calculate_text_match_score(ai_text, metadata, bg_name)
		
		if score > best_score:
			best_score = score
			best_match = bg_name
	
	# Only change if we have a strong match and it's different from current
	if best_score >= 3 and best_match != current_location:
		print("DynamicBackgroundManager: Location change detected: ", current_location, " → ", best_match, " (score: ", best_score, ")")
		return best_match
	
	return current_location

## Calculate match score between AI text and background metadata
static func calculate_text_match_score(ai_text: String, metadata: Dictionary, bg_name: String) -> int:
	var score = 0
	var text_lower = ai_text.to_lower()
	var bg_name_readable = bg_name.replace("_", " ").to_lower()
	
	# Direct name mention
	if text_lower.contains(bg_name_readable):
		score += 10
	
	# Description keyword matching
	if metadata.has("description"):
		var desc_lower = metadata["description"].to_lower()
		var desc_words = desc_lower.split(" ")
		for word in desc_words:
			if word.length() > 3 and text_lower.contains(word):
				score += 2
	
	# Tag matching
	if metadata.has("tags"):
		for tag in metadata["tags"]:
			if text_lower.contains(tag.to_lower()):
				score += 3
	
	# Movement pattern detection
	var movement_phrases = ["move to", "go to", "head to", "enter", "arrive at", "walk to", "step into"]
	for phrase in movement_phrases:
		if text_lower.contains(phrase):
			# Check if location name appears after movement phrase
			var phrase_pos = text_lower.find(phrase)
			var after_phrase = text_lower.substr(phrase_pos + phrase.length())
			if after_phrase.contains(bg_name_readable):
				score += 8
	
	return score

## Get location context for AI prompts
static func get_location_context_for_ai() -> String:
	if not is_initialized:
		initialize_from_assets_folder()
	
	if available_backgrounds.is_empty():
		return ""
	
	var context = "Available locations for the story:\n"
	
	for bg_name in available_backgrounds:
		var metadata = available_backgrounds[bg_name]
		context += "- " + bg_name.replace("_", " ") + ": " + metadata.get("description", "") + "\n"
		
		if metadata.has("ai_instructions") and metadata["ai_instructions"] != "":
			context += "  (Use for: " + metadata["ai_instructions"] + ")\n"
	
	if should_ai_change_locations():
		context += "\nYou may naturally transition between these locations as the story develops."
	else:
		context += "\nKeep the story in the current location unless there's a compelling narrative reason to change."
	
	return context

## Check if AI should be encouraged to change locations
static func should_ai_change_locations() -> bool:
	if not is_initialized:
		initialize_from_assets_folder()
	
	return available_backgrounds.size() > 1

## Get list of available background names
static func get_available_background_names() -> Array[String]:
	if not is_initialized:
		initialize_from_assets_folder()
	
	return available_backgrounds.keys()

## Get metadata for specific background
static func get_background_metadata(bg_name: String) -> Dictionary:
	if not is_initialized:
		initialize_from_assets_folder()
	
	return available_backgrounds.get(bg_name, {})

## Check if background exists
static func has_background(bg_name: String) -> bool:
	if not is_initialized:
		initialize_from_assets_folder()
	
	return available_backgrounds.has(bg_name)

## Get background count
static func get_background_count() -> int:
	if not is_initialized:
		initialize_from_assets_folder()
	
	return available_backgrounds.size()

## Force re-initialization (for testing or asset updates)
static func reinitialize():
	is_initialized = false
	initialize_from_assets_folder()














