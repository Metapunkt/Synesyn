class_name VisualPresentationManager
extends Node

## VisualPresentationManager
## Coordinates between ScenSyn AI responses and story_stage visual presentation
## Manages parallel Story Log and visual presentation streams

signal character_registered(character_name: String)
signal visual_presentation_ready()

# References to story_stage UI components
var dialog_ui: Control = null
var character_sprite: Node2D = null

# Character management
var registered_characters: Dictionary = {}
var current_speaker: String = ""

# Integration state
var is_initialized: bool = false
var story_stage_scene: PackedScene = null

## Initialize the visual presentation system
func initialize() -> bool:
	print("VisualPresentationManager: Initializing...")
	
	# Load story_stage scene
	var scene_path = "res://ScenSyn/scenes/scensyn_story_stage.tscn"
	if ResourceLoader.exists(scene_path):
		story_stage_scene = load(scene_path)
		if story_stage_scene == null:
			push_error("VisualPresentationManager: Failed to load story_stage scene")
			return false
	else:
		push_error("VisualPresentationManager: story_stage scene not found at " + scene_path)
		return false
	
	is_initialized = true
	print("VisualPresentationManager: Initialized successfully")
	visual_presentation_ready.emit()
	return true

## Setup story_stage UI components
func setup_story_stage_ui(parent_node: Node) -> bool:
	if not is_initialized:
		push_error("VisualPresentationManager: Not initialized")
		return false
	
	if story_stage_scene == null:
		push_error("VisualPresentationManager: story_stage scene not loaded")
		return false
	
	# Instantiate story_stage UI
	var story_stage_instance = story_stage_scene.instantiate()
	if story_stage_instance == null:
		push_error("VisualPresentationManager: Failed to instantiate story_stage scene")
		return false
	
	parent_node.add_child(story_stage_instance)
	
	# Get references to UI components
	dialog_ui = story_stage_instance.get_node("%DialogUI")
	character_sprite = story_stage_instance.get_node("%CharacterSprite")
	
	if dialog_ui == null:
		push_error("VisualPresentationManager: Failed to find DialogUI component")
		return false
	
	if character_sprite == null:
		push_error("VisualPresentationManager: Failed to find CharacterSprite component")
		return false
	
	print("VisualPresentationManager: story_stage UI setup complete")
	return true

## Register a character from ScenSyn character setup
func register_character(character_data: Dictionary) -> bool:
	if not character_data.has("name"):
		push_error("VisualPresentationManager: Character data missing name")
		return false
	
	var char_name = character_data["name"]
	
	# Register with story_stage Character system
	var char_id = StoryStageCharacter.register_scensyn_character(character_data)
	if char_id == -1:
		push_error("VisualPresentationManager: Failed to register character: " + char_name)
		return false
	registered_characters[char_name] = character_data
	
	print("VisualPresentationManager: Registered character: ", char_name)
	character_registered.emit(char_name)
	return true

## Process AI response for visual presentation
func process_ai_response(ai_response: Dictionary) -> bool:
	if not is_initialized or dialog_ui == null:
		push_warning("VisualPresentationManager: Not ready for AI response processing")
		return false
	
	# Convert AI response to story_stage format
	var story_entry = StoryStageAdapter.convert_ai_response_to_story_format(ai_response)
	
	# Validate the converted entry
	if not StoryStageAdapter.validate_story_entry(story_entry):
		push_warning("VisualPresentationManager: Invalid story entry from AI response")
		return false
	
	# Handle location changes before displaying dialogue
	if story_entry.has("location"):
		handle_location_change(story_entry["location"])
	
	# Display in visual presentation
	return display_story_entry(story_entry)

## Display story entry in visual presentation
func display_story_entry(story_entry: Dictionary) -> bool:
	if dialog_ui == null or character_sprite == null:
		push_error("VisualPresentationManager: UI components not available")
		return false
	
	var speaker_name = story_entry.get("speaker", "Unknown")
	var dialogue_text = story_entry.get("text", "")
	var expression = story_entry.get("expression", "neutral")
	
	# Handle location changes
	if story_entry.has("location"):
		handle_location_change(story_entry["location"])
	
	# Get character enum from name
	var character_enum = StoryStageCharacter.get_enum_from_string(speaker_name)
	if character_enum == -1:
		# Character not found, ensure it's registered
		if not registered_characters.has(speaker_name):
			# Create basic character data for unregistered characters
			var basic_char_data = {
				"name": speaker_name,
				"gender": "neutral",
				"personality": {}
			}
			register_character(basic_char_data)
			character_enum = StoryStageCharacter.get_enum_from_string(speaker_name)
		
		if character_enum == -1:
			push_warning("VisualPresentationManager: Could not resolve character: " + speaker_name)
			return false
	
	# Update character sprite using ScenSyn-enhanced method
	if character_sprite.has_method("change_character_scensyn"):
		character_sprite.change_character_scensyn(speaker_name, true, expression)
	elif character_sprite.has_method("change_character"):
		character_sprite.change_character(character_enum, true, expression)
	
	# Update dialogue UI using ScenSyn-enhanced method
	if dialog_ui.has_method("display_story_entry"):
		dialog_ui.display_story_entry(story_entry)
	elif dialog_ui.has_method("change_line_scensyn"):
		dialog_ui.change_line_scensyn(speaker_name, dialogue_text)
	elif dialog_ui.has_method("change_line"):
		dialog_ui.change_line(character_enum, dialogue_text)
	
	current_speaker = speaker_name
	
	return true

## Handle location/background changes using dynamic system
func handle_location_change(location: String) -> void:
	if location.is_empty():
		return
	
	# Check if background exists in dynamic system
	if not DynamicBackgroundManager.has_background(location):
		print("VisualPresentationManager: Background not available: ", location)
		return
	
	_change_background_direct(location)

## Direct background change fallback
func _change_background_direct(location: String):
	var background_path = "res://ScenSyn/story_stage/assets/images/" + location + ".png"
	
	if not ResourceLoader.exists(background_path):
		push_warning("VisualPresentationManager: Background file not found: " + background_path)
		return
	
	var background_node = get_background_node()
	if background_node and background_node.has_method("set_texture"):
		var texture = load(background_path)
		if texture:
			background_node.texture = texture
			print("VisualPresentationManager: Changed background to: ", location)

## Get background node from story_stage UI
func get_background_node() -> Node:
	if dialog_ui == null:
		return null
	
	# Search for background node in the scene tree
	var root = dialog_ui.get_tree().current_scene
	if root:
		return root.find_child("Background", true, false)
	
	return null

## Get list of registered characters
func get_registered_characters() -> Array[String]:
	return registered_characters.keys()

## Check if character is registered
func is_character_registered(character_name: String) -> bool:
	return registered_characters.has(character_name)

## Get current speaker
func get_current_speaker() -> String:
	return current_speaker

## Cleanup and reset
func cleanup() -> void:
	registered_characters.clear()
	current_speaker = ""
	dialog_ui = null
	character_sprite = null
	is_initialized = false
	print("VisualPresentationManager: Cleaned up")

## Get initialization status
func is_ready() -> bool:
	return is_initialized and dialog_ui != null and character_sprite != null

## Get location context for AI prompts (ScenSyn integration)
func get_location_context_for_ai() -> String:
	return DynamicBackgroundManager.get_location_context_for_ai()

## Check if location changes should be encouraged
func should_encourage_location_changes() -> bool:
	return DynamicBackgroundManager.should_ai_change_locations()

## Get available background names
func get_available_backgrounds() -> Array[String]:
	return DynamicBackgroundManager.get_available_background_names()
