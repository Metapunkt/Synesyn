# character_selection.gd
extends Control

var game_flow_manager
var current_scenario: Dictionary
var selected_character: Dictionary
var selected_characters: Array

@onready var character_list = %CharacterList
@onready var character_description: RichTextLabel = %CharacterDescription
@onready var confirm_button = %ConfirmButton

@onready var profile_sprite = %Profile_Sprite
var path_to_profile_images: String = "res://ScenSyn/profile_images/"
var images = []

func _ready():
	game_flow_manager = Global.get_game_flow_manager()
	current_scenario = game_flow_manager.get_current_scenario()
	selected_characters = Global.get_selected_characters()
	populate_character_list()
	print("Current scenario type: ", typeof(current_scenario))
	print("Current scenario content: ", current_scenario)
	confirm_button.connect("pressed", Callable(self, "_on_confirm_pressed"))
	confirm_button.disabled = true
	load_profiles()

func load_profiles():
	var dir = DirAccess.open(path_to_profile_images)
	if dir != null:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") or file_name.ends_with(".jpg") or file_name.ends_with(".jpeg"):  # Add more extensions if needed
				images.append(path_to_profile_images + file_name)
			file_name = dir.get_next()
	print("Image Paths: ", images)
			
func set_profile():
	# Load a random image into the sprite
	var rng = RandomNumberGenerator.new()
	if images.size() > 0:
 #   var last_element = array[array.size() - 1]	
		var image_path = images[rng.randi_range(0, images.size() - 1)]
		profile_sprite.texture = load(image_path)
				
#func populate_character_list():
	#for character in current_scenario.get("characters", []):
		#var button = Button.new()
		#button.text = character.get("name", "Unnamed")
		#button.connect("pressed", Callable(self, "_on_character_selected").bind(character))
		#character_list.add_child(button)
		
func populate_character_list():
	var characters = current_scenario.get("characters", [])
	print("Populating character list with: ", characters)
	if characters.is_empty():
		print("CharacterSelection: No characters found in the current scenario!")
		return

	for character in characters:
		var button = Button.new()
		button.text = character.get("name", "Unnamed")
		
		# Prevent already selected characters from being displayed
		var is_already_selected = false
		for selected_char in selected_characters:
			if selected_char.get("name") == character.get("name"):
				is_already_selected = true
				break
		
		if is_already_selected:
			button.disabled = true
			button.text += " (Taken)"
		
		button.connect("pressed", Callable(self, "_on_character_selected").bind(character))
		character_list.add_child(button)

func _on_character_selected(character):
	selected_character = character
	var description = "Name: [font_size=16][b]%s[/b][/font_size]\nRole: %s\nDescription: %s" % [
		character.get("name", "Unnamed"),
		character.get("role", "Unknown"),
		character.get("description", "No description available")
	]
	character_description.text = description
	set_profile()
	confirm_button.disabled = false
	
func _on_confirm_pressed():
	if selected_character:
		StoryState.reset()
		Global.set_current_character(selected_character)
		get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")
