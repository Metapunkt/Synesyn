class_name StoryStageAdapter
extends RefCounted

## StoryStageAdapter
## Converts ScenSyn AI responses to story_stage dialogue format
## Maintains compatibility between dynamic AI content and visual novel presentation

## Convert AI response to story_stage format
static func convert_ai_response_to_story_format(ai_response: Dictionary) -> Dictionary:
	var story_entry = {}
	
	# Extract speaker from AI response
	if ai_response.has("character_name"):
		story_entry["speaker"] = ai_response["character_name"]
	elif ai_response.has("speaker"):
		story_entry["speaker"] = ai_response["speaker"]
	elif ai_response.has("name"):
		story_entry["speaker"] = ai_response["name"]
	else:
		story_entry["speaker"] = "Unknown"
	
	# Extract dialogue text
	if ai_response.has("message"):
		story_entry["text"] = ai_response["message"]
	elif ai_response.has("content"):
		story_entry["text"] = ai_response["content"]
	elif ai_response.has("text"):
		story_entry["text"] = ai_response["text"]
	elif ai_response.has("dialogue"):
		story_entry["text"] = ai_response["dialogue"]
	else:
		story_entry["text"] = ""
	
	# Handle location/scene changes from AI narrative descriptions
	var location_change = detect_location_change_from_ai_content(ai_response)
	if location_change != "":
		story_entry["location"] = location_change
		story_entry["location_detected"] = true
	
	# Handle AI-generated emotional context for character expressions
	if ai_response.has("emotion"):
		story_entry["expression"] = ai_response["emotion"]
	elif ai_response.has("mood"):
		story_entry["expression"] = ai_response["mood"]
	elif ai_response.has("expression"):
		story_entry["expression"] = ai_response["expression"]
	else:
		# Default expression based on content analysis
		story_entry["expression"] = analyze_text_emotion(story_entry.get("text", ""))
	
	# Handle scene transitions
	if ai_response.has("scene_transition"):
		story_entry["transition"] = ai_response["scene_transition"]
	elif ai_response.has("transition"):
		story_entry["transition"] = ai_response["transition"]
	
	return story_entry

## Detect location change from AI content using dynamic background system
static func detect_location_change_from_ai_content(ai_response: Dictionary) -> String:
	# Check for explicit location fields first
	if ai_response.has("location"):
		return ai_response["location"]
	elif ai_response.has("setting"):
		return ai_response["setting"]
	elif ai_response.has("scene_location"):
		return ai_response["scene_location"]
	
	# Analyze narrative text for location changes
	var text = ""
	if ai_response.has("message"):
		text = ai_response["message"]
	elif ai_response.has("content"):
		text = ai_response["content"]
	elif ai_response.has("text"):
		text = ai_response["text"]
	elif ai_response.has("scene_description"):
		text = ai_response["scene_description"]
	
	if text != "":
		return DynamicBackgroundManager.detect_location_change_from_ai(text)
	
	return ""

## Analyze text content to determine appropriate expression
static func analyze_text_emotion(text: String) -> String:
	if text.is_empty():
		return "neutral"
	
	var text_lower = text.to_lower()
	
	# Emotion keyword analysis
	var emotion_keywords = {
		"happy": ["happy", "joy", "excited", "wonderful", "great", "amazing", "laugh", "smile"],
		"confident": ["confident", "sure", "certain", "determined", "strong", "bold"],
		"sad": ["sad", "sorry", "disappointed", "upset", "hurt", "cry"],
		"angry": ["angry", "mad", "furious", "annoyed", "frustrated"],
		"surprised": ["surprised", "shocked", "wow", "amazing", "incredible"],
		"worried": ["worried", "concerned", "anxious", "nervous", "afraid"]
	}
	
	# Count emotion indicators
	var emotion_scores = {}
	for emotion in emotion_keywords:
		emotion_scores[emotion] = 0
		for keyword in emotion_keywords[emotion]:
			if text_lower.contains(keyword):
				emotion_scores[emotion] += 1
	
	# Find highest scoring emotion
	var best_emotion = "neutral"
	var best_score = 0
	for emotion in emotion_scores:
		if emotion_scores[emotion] > best_score:
			best_score = emotion_scores[emotion]
			best_emotion = emotion
	
	return best_emotion

## Validate story entry format
static func validate_story_entry(story_entry: Dictionary) -> bool:
	if not story_entry.has("speaker") or story_entry["speaker"] == "":
		push_warning("StoryStageAdapter: Missing or empty speaker in story entry")
		return false
	
	if not story_entry.has("text") or story_entry["text"] == "":
		push_warning("StoryStageAdapter: Missing or empty text in story entry")
		return false
	
	return true

## Get supported expression types
static func get_supported_expressions() -> Array[String]:
	return ["neutral", "happy", "confident", "sad", "angry", "surprised", "worried"]

## Get supported location types
static func get_supported_locations() -> Array[String]:
	return ["courtroom", "office", "home", "street", "restaurant", "park"]
