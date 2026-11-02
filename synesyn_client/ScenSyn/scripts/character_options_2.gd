extends Control

## OBSOLETE: orphan prototype. Live Story Catalyst entry is character_options.gd.
## Do not wire new flows through this script.

const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)

@onready var num_characters_spin_box = %SpinBox
@onready var generate_button = %GenerateButton
@onready var character_list = %VBoxContainer
@onready var confirm_button = %ConfirmButton

var scenario_loader = Global.get_scenario_loader()
var generated_characters = []
var selected_characters = []
#var scenario_metaprompt_name = "lost_artifact"  # This can be changed to load different scenarios
var scenario_metaprompt_name = "trondheim_future_scenarios"

#func _init():
	#print("Character options _init called")
	
func _ready():
	#print("Character options entered scene tree")
	#print("Current scene:", get_tree().current_scene.name if get_tree().current_scene else "No current scene")
	#print("Is inside tree:", is_inside_tree())
	if should_bypass_character_selection(Global.current_session_type):
		await _enter_workshop_facilitator_session()
		return
	generate_button.connect("pressed", _on_generate_pressed)
	confirm_button.connect("pressed", _on_confirm_pressed)
	scenario_loader.load_scenario(
		scenario_metaprompt_name,
		Global.current_session_type,
		Global.current_collection_id
	)

static func should_bypass_character_selection(session_type_id: String) -> bool:
	return FacilitatorSessionSetupScript.should_bypass_character_selection(session_type_id)

func _enter_workshop_facilitator_session() -> void:
	var workshop_scenario_id: String = Global.get_current_scenario_metaprompt()
	var was_loaded: bool = scenario_loader.load_scenario(
		workshop_scenario_id,
		Global.current_session_type,
		Global.current_collection_id
	)
	if not was_loaded:
		push_error("CharacterOptions2: Workshop Catalyst scenario could not be loaded")
		return
	var game_flow_manager = Global.get_game_flow_manager()
	game_flow_manager.set_current_scenario(scenario_loader.get_current_scenario())
	StoryState.reset()
	FacilitatorSessionSetupScript.apply(Global, StoryState)
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")

#func _unhandled_input(event):
	##print("Unhandled input in character options:", event)
	#pass
	
#func _enter_tree():
	#print("Character options entered scene tree")
	#print("Character options scene ready")
	#print("Is inside tree:", is_inside_tree())
	#print("Parent node:", get_parent().name if get_parent() else "No parent")
	#print("Child nodes:", get_children())
	#
#func _exit_tree():
	#print("Character options exited scene tree")
	#print("Current scene:", get_tree().current_scene.name if get_tree().current_scene else "No current scene")
	#print("Stack trace:")
	#print_stack()
	
func _on_generate_pressed():
	# Clear existing characters
	for child in character_list.get_children():
		child.queue_free()
	
	generated_characters = scenario_loader.generate_characters(num_characters_spin_box.value)
	
	for character in generated_characters:
		var checkbox = CheckBox.new()
		checkbox.text = character.name + " - " + character.role
		checkbox.connect("toggled", _on_character_toggled.bind(character))
		character_list.add_child(checkbox)

func _on_character_toggled(is_checked, character, index):
	if is_checked and selected_characters.size() < 4:
		selected_characters.append(character)
		rpc("sync_character_selection", index, true)
	elif not is_checked and character in selected_characters:
		selected_characters.erase(character)
		rpc("sync_character_selection", index, false)

func _on_confirm_pressed():
	if selected_characters.size() != 4:
		print("Please select exactly 4 characters.")
		return
	
	# Pass the selected characters to the character selection scene
	Global.set_selected_characters(selected_characters)
	var game_flow_manager = Global.get_game_flow_manager()
	game_flow_manager.set_current_scenario(scenario_loader.get_current_scenario())
	get_tree().change_scene_to_file("res://ScenSyn/scenes/character_selection.tscn")

@rpc("any_peer", "call_local")
func sync_character_selection(character_index, is_selected):
	var checkbox = character_list.get_child(character_index)
	checkbox.disabled = is_selected
	if is_selected:
		checkbox.button_pressed = false
