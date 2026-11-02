class_name ScenSynVisualIntegration
extends Node

## ScenSynVisualIntegration
## Connects ScenSyn's AI-driven narrative system with story_stage visual presentation
## Manages the integration lifecycle and coordinates between systems

signal integration_ready()
signal character_setup_complete()
signal visual_presentation_active()

# Integration components
var visual_presentation_manager: VisualPresentationManager = null
var story_state_connection_active: bool = false

# Character setup tracking
var characters_registered: Dictionary = {}
var setup_complete: bool = false

func _ready():
	print("ScenSynVisualIntegration: Initializing...")
	
	# Add to group for easy finding by metaprompt system
	add_to_group("visual_integration")
	
	# Connect to StoryState signals
	if StoryState:
		StoryState.visual_presentation_update.connect(_on_visual_presentation_update)
		story_state_connection_active = true
		print("ScenSynVisualIntegration: Connected to StoryState")
	else:
		push_error("ScenSynVisualIntegration: StoryState not available")

## Initialize visual presentation system
func initialize_visual_presentation(parent_scene: Node) -> bool:
	if visual_presentation_manager:
		push_warning("ScenSynVisualIntegration: Already initialized")
		return true
	
	# Create and initialize visual presentation manager
	visual_presentation_manager = VisualPresentationManager.new()
	add_child(visual_presentation_manager)
	
	if not visual_presentation_manager.initialize():
		push_error("ScenSynVisualIntegration: Failed to initialize VisualPresentationManager")
		return false
	
	# Setup story_stage UI in the parent scene
	if not visual_presentation_manager.setup_story_stage_ui(parent_scene):
		push_error("ScenSynVisualIntegration: Failed to setup story_stage UI")
		return false
	
	print("ScenSynVisualIntegration: Visual presentation initialized")
	integration_ready.emit()
	return true

## Register characters from ScenSyn scenario setup
func register_scenario_characters(characters_data: Array) -> bool:
	if not visual_presentation_manager:
		push_error("ScenSynVisualIntegration: Visual presentation not initialized")
		return false
	
	var success_count = 0
	for character_data in characters_data:
		if visual_presentation_manager.register_character(character_data):
			var char_name = character_data.get("name", "Unknown")
			characters_registered[char_name] = character_data
			success_count += 1
		else:
			push_warning("ScenSynVisualIntegration: Failed to register character: " + str(character_data))
	
	print("ScenSynVisualIntegration: Registered ", success_count, "/", characters_data.size(), " characters")
	
	if success_count > 0:
		setup_complete = true
		character_setup_complete.emit()
	
	return success_count == characters_data.size()

## Handle visual presentation updates from StoryState
func _on_visual_presentation_update(ai_response: Dictionary):
	if not visual_presentation_manager or not visual_presentation_manager.is_ready():
		# Queue the response for when system is ready
		call_deferred("_process_queued_response", ai_response)
		return
	
	# Process AI response for visual presentation
	var success = visual_presentation_manager.process_ai_response(ai_response)
	if success:
		visual_presentation_active.emit()
	else:
		push_warning("ScenSynVisualIntegration: Failed to process AI response for visual presentation")

## Process queued responses when system becomes ready
func _process_queued_response(ai_response: Dictionary):
	if visual_presentation_manager and visual_presentation_manager.is_ready():
		_on_visual_presentation_update(ai_response)

## Get location context for AI prompts
func get_location_context_for_ai() -> String:
	if visual_presentation_manager:
		return visual_presentation_manager.get_location_context_for_ai()
	return ""

## Check if visual presentation is ready
func is_visual_presentation_ready() -> bool:
	return visual_presentation_manager != null and visual_presentation_manager.is_ready()

## Get registered character names
func get_registered_characters() -> Array[String]:
	return characters_registered.keys()

## Check if character is registered
func is_character_registered(character_name: String) -> bool:
	return characters_registered.has(character_name)

## Get integration status
func get_integration_status() -> Dictionary:
	return {
		"story_state_connected": story_state_connection_active,
		"visual_manager_ready": visual_presentation_manager != null and visual_presentation_manager.is_ready(),
		"characters_registered": characters_registered.size(),
		"setup_complete": setup_complete
	}

## Enable ScenSyn mode on story_stage components
func enable_scensyn_mode():
	if not visual_presentation_manager:
		push_warning("ScenSynVisualIntegration: Cannot enable ScenSyn mode - visual manager not available")
		return
	
	# Enable ScenSyn mode on dialog UI
	var dialog_ui = visual_presentation_manager.dialog_ui
	if dialog_ui and dialog_ui.has_method("enable_scensyn_mode"):
		dialog_ui.enable_scensyn_mode()
	
	# Enable ScenSyn mode on scene manager
	var scene_manager = visual_presentation_manager.scene_manager
	if scene_manager and scene_manager.has_method("enable_scensyn_mode"):
		scene_manager.enable_scensyn_mode()
	
	print("ScenSynVisualIntegration: ScenSyn mode enabled on story_stage components")

## Cleanup integration
func cleanup():
	if visual_presentation_manager:
		visual_presentation_manager.cleanup()
		visual_presentation_manager = null
	
	characters_registered.clear()
	setup_complete = false
	story_state_connection_active = false
	
	print("ScenSynVisualIntegration: Cleaned up")
