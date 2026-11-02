extends Control

signal character_pool_updated

const CharacterScript = preload("res://addons/story_stage/scripts/story_stage_character.gd")
const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)
const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)
const _PORTRAIT_WIDTH := 132
const _PORTRAIT_HEIGHT := 132

const _BG_PORTRAIT_TEXTURES: Array = [
	"res://Synesyn_icons/synesyn-backgrounds/bg_portrait_amber.png",
	"res://Synesyn_icons/synesyn-backgrounds/bg_portrait_teal.png",
	"res://Synesyn_icons/synesyn-backgrounds/bg_portrait_violet.png",
	"res://Synesyn_icons/synesyn-backgrounds/bg_portrait_rose.png",
]

const _BG_DARK := preload("res://Synesyn_icons/synesyn-backgrounds/bg_main_home_dark.png")
const _BG_LIGHT := preload("res://Synesyn_icons/synesyn-backgrounds/bg_main_home_light.png")

@onready var num_characters_spin_box = %SpinBox
@onready var generate_button = %GenerateButton
@onready var character_list = %CharacterList_Container
@onready var confirm_button = %ConfirmButton
@onready var confirm_button2 = %ConfirmButton2
#@onready var Network = %Network
@onready var hamburger_menu_btn = %HamburgerMenuBtn
@onready var hamburger_settings_panel = %HamburgerSettingsPanel
@onready var services_button_hamburger = %ServicesButton
@onready var back_button_hamburger = %BackButton

@onready var scenario_metaprompt_name = Global.get_current_scenario_metaprompt()

var scenario_loader = Global.get_scenario_loader()
var generated_characters = []
var available_characters = []
var selected_characters = []
#var scenario_metaprompt_name = "trondheim_future_scenarios"
var game_flow_manager = Global.get_game_flow_manager()

@onready var _bg_color_rect: ColorRect = $ColorRect
@onready var _bg_image: TextureRect = %BackgroundImage

func _ready():
	await get_tree().create_timer(0.5).timeout

	_update_bg_color()
	if ThemeManager and not ThemeManager.mode_changed.is_connected(_on_theme_changed):
		ThemeManager.mode_changed.connect(_on_theme_changed)

	if should_bypass_character_selection(Global.current_session_type):
		await _enter_workshop_facilitator_session()
		return

	# When Auto Player Input is active, skip character selection entirely
	var pai = Global.get_player_auto_input() if Global and Global.has_method("get_player_auto_input") else null
	if pai and pai.is_enabled():
		_auto_skip_to_game_session()
		return
	
	# Ensure fresh selection state when starting a new lobby
	if Network.is_server():
		Network.reset_character_selection()
	#_generate_multiplayer_characters()
	if not _is_open_play_custom_active():
		scenario_loader.load_scenario(
			scenario_metaprompt_name,
			Global.current_session_type,
			Global.current_collection_id
		)
#	generate_button.pressed.connect(_on_generate_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button2.pressed.connect(_on_confirm_pressed_2)
	
	var multiplayer_status = get_tree().get_multiplayer()
	var unique_id = multiplayer_status.get_unique_id()
	self.set_multiplayer_authority(unique_id)
	
	if Network.is_server():
		_generate_multiplayer_characters()
	elif Network.is_multiplayer():
		Network.rpc_id(1, "request_character_pool")
	else:
		_generate_local_characters()
		
	if not Network.is_connected("character_selection_failed", _on_character_selection_failed):
		Network.connect("character_selection_failed", _on_character_selection_failed)
	
	if not Global.is_connected("character_pool_updated", _on_character_pool_updated):
		Global.connect("character_pool_updated", _on_character_pool_updated)
	
	# CRITICAL FIX: Connect to peer info updates to refresh UI when other players select characters
	if not Network.is_connected("peer_connected", _on_peer_connected):
		Network.connect("peer_connected", _on_peer_connected)
	
	if not Network.is_connected("peer_disconnected", _on_peer_disconnected):
		Network.connect("peer_disconnected", _on_peer_disconnected)
	
	# Connect to peer info updates for real-time UI refresh
	if not Network.is_connected("peer_info_updated", _on_peer_info_updated):
		Network.connect("peer_info_updated", _on_peer_info_updated)
	
	# Wire hamburger menu
	if hamburger_menu_btn:
		hamburger_menu_btn.pressed.connect(_on_hamburger_menu_pressed)
	if services_button_hamburger:
		services_button_hamburger.pressed.connect(_toggle_services_panel)
	if back_button_hamburger:
		back_button_hamburger.pressed.connect(_on_back_pressed)
	if hamburger_settings_panel:
		hamburger_settings_panel.visible = false

static func should_bypass_character_selection(session_type_id: String) -> bool:
	return FacilitatorSessionSetupScript.should_bypass_character_selection(session_type_id)

func _enter_workshop_facilitator_session() -> void:
	print("CharacterOptions: Workshop Catalyst active — entering as Facilitator")
	var was_loaded: bool = scenario_loader.load_scenario(
		scenario_metaprompt_name,
		Global.current_session_type,
		Global.current_collection_id
	)
	if not was_loaded:
		push_error("CharacterOptions: Workshop Catalyst scenario could not be loaded")
		return
	var working_scenario: Dictionary = scenario_loader.get_current_scenario()
	game_flow_manager.set_current_scenario(working_scenario)
	StoryState.reset()
	FacilitatorSessionSetupScript.apply(Global, StoryState)
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")

func _is_open_play_custom_active() -> bool:
	if String(Global.current_collection_id) != "open_play":
		return false
	var current: Dictionary = {}
	if Global.has_method("get_current_scenario"):
		current = Global.get_current_scenario()
	if current.is_empty() and game_flow_manager:
		current = game_flow_manager.get_current_scenario()
	return StoryScenarioContractScript.looks_like_custom(current)


func _open_play_cast_from_scenario() -> Array:
	var current: Dictionary = {}
	if Global.has_method("get_current_scenario"):
		current = Global.get_current_scenario()
	if current.is_empty() and game_flow_manager:
		current = game_flow_manager.get_current_scenario()
	var characters_any: Variant = current.get("characters", [])
	if typeof(characters_any) != TYPE_ARRAY or (characters_any as Array).is_empty():
		return []
	var cast: Array = []
	for character_any: Variant in characters_any:
		if typeof(character_any) != TYPE_DICTIONARY:
			continue
		var character: Dictionary = (character_any as Dictionary).duplicate(true)
		character["is_ai"] = true
		cast.append(character)
	return cast


func _generate_multiplayer_characters():
	if not Network.is_server():
		if not Network.is_multiplayer():
			_generate_local_characters()
			return
		# Request the latest character pool from the server
		Network.rpc_id(1, "request_character_pool")
	else:
		# Open Play custom drafts already carry their cast — do not regenerate
		# from authored templates (there may be none).
		if _is_open_play_custom_active():
			var open_play_cast: Array = _open_play_cast_from_scenario()
			if not open_play_cast.is_empty():
				Network.character_pool = open_play_cast
				Global.set_character_pool(open_play_cast)
				_on_character_pool_updated()
				return
		Network.generate_character_pool()
		Global.set_character_pool(Network.character_pool)
		_on_character_pool_updated()

func _generate_local_characters() -> void:
	if _is_open_play_custom_active():
		var open_play_cast: Array = _open_play_cast_from_scenario()
		if not open_play_cast.is_empty():
			generated_characters = open_play_cast
			Global.set_character_pool(generated_characters)
			_on_character_pool_updated()
			return
	generated_characters = await scenario_loader.generate_characters(4)
	Global.set_character_pool(generated_characters)
	_on_character_pool_updated()
		
func _on_character_pool_updated():
	print("Character Options: Received character_pool update")
	update_character_pool(Global.get_character_pool())
	if get_tree() != null:
		await get_tree().process_frame  # Wait for UI update to complete
	else:
		print("Character Options: WARNING - get_tree() is null, skipping frame wait")
	
func _on_generate_pressed():
	print("Generate button pressed")
	for child in character_list.get_children():
		child.queue_free()
	
	generated_characters = await scenario_loader.generate_characters(num_characters_spin_box.value)
	
	for i in range(generated_characters.size()):
		var character = generated_characters[i]
		var checkbox = CheckBox.new()		
		checkbox.text = character.get("name", "Unnamed") + " - " + character.get("role", "Unknown Role")
		# Use bind here as well to capture index correctly
		checkbox.toggled.connect(_on_character_toggled.bind(i))		
		character_list.add_child(checkbox)

func _on_character_toggled(is_checked: bool, index: int):
	print("Character toggled: ", index, " Is checked: ", is_checked)

	if is_checked:
		# If a box is checked, this is our new selection.
		# Clear any previous selection.
		selected_characters.clear()
		selected_characters.append(index)

		# Uncheck all other boxes visually.
		for i in range(character_list.get_child_count()):
			if i != index:
				var container = character_list.get_child(i)
				if container and container.get_child_count() > 0:
					var checkbox = container.get_child(0) as CheckBox
					if checkbox:
						checkbox.set_pressed_no_signal(false)
	else:
		# If a box is unchecked, clear the selection.
		selected_characters.erase(index)

	# In multiplayer, broadcast the selection to other players.
	if Network.is_multiplayer():
		var character = {}
		if not selected_characters.is_empty():
			var selected_index = selected_characters[0]
			if selected_index < available_characters.size():
				character = available_characters[selected_index].duplicate()
				character["is_ai"] = false
				character["is_player"] = true
		
		var current_peer_id = multiplayer.get_unique_id()
		Network.sync_peer_character_selection.rpc(current_peer_id, character)
	
	# Finally, update the UI for everyone based on the new state.
	_update_character_checkboxes()

func _auto_skip_to_game_session() -> void:
	print("CharacterOptions: Auto Player Input active — skipping character selection")
	# Mirror the guard in _ready(): a custom Open Play draft has no on-disk
	# .txt file to (re)load by name. Re-loading here would fail silently and
	# fall back to the loader's "Emergency Scenario" stub, clobbering the
	# real custom scenario right before entering game_session.
	var working_scenario: Dictionary
	if not _is_open_play_custom_active():
		scenario_loader.load_scenario(
			scenario_metaprompt_name,
			Global.current_session_type,
			Global.current_collection_id
		)
		working_scenario = scenario_loader.get_current_scenario()
	else:
		working_scenario = Global.get_current_scenario()
	if Network.is_server():
		Network.generate_character_pool()
		Global.set_character_pool(Network.character_pool)
	game_flow_manager.set_current_scenario(working_scenario)
	StoryState.reset()
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")

func _on_confirm_pressed():
	print("Confirm pressed. Selected characters: ", selected_characters)
	
	if selected_characters.size() != 1:
		print("Please select exactly one character")
		return
	
	var selected_index = selected_characters[0]
	if selected_index >= available_characters.size():
		print("Error: Invalid character index")
		return

	var selected_character = available_characters[selected_index].duplicate(true)  # Deep copy to avoid reference issues
	var player_name = selected_character.get("name", "Unnamed Player")
	
	# CRITICAL FIX: Mark this character as player-controlled (not AI) BEFORE any network calls
	selected_character["is_ai"] = false
	selected_character["is_player"] = true
	selected_character["portrait_bg_index"] = selected_index % _BG_PORTRAIT_TEXTURES.size()
	print("Character Options: Marked ", player_name, " as player-controlled (is_ai = false)")
	
	# ALSO update the original character in available_characters to maintain consistency
	available_characters[selected_index]["is_ai"] = false
	available_characters[selected_index]["is_player"] = true
	
	# For custom Open Play scenarios, scenario_loader.scenario_data may have been
	# clobbered by an unrelated file-based load attempt (e.g. game_mode_popup's
	# scenario_changed listener trying to preview the custom scenario's sentinel
	# id as if it were a file). Global.get_current_scenario() holds the
	# authoritative custom scenario dict set when the Story Builder saved it, so
	# prefer that whenever the custom Open Play scenario is active.
	var working_scenario: Dictionary = scenario_loader.get_current_scenario()
	if _is_open_play_custom_active():
		working_scenario = Global.get_current_scenario()
	game_flow_manager.set_current_scenario(working_scenario)

	# Explicitly set each piece of scenario data
	#game_flow_manager.set_current_scenario({
		#"name": working_scenario.get("name", "Unnamed Scenario"),
		#"objective": working_scenario.get("objective", "No objective set"),
		#"description": working_scenario.get("description", "No description available"),
		#"characters": working_scenario.get("characters", [])
	#})
	
	Global.set_selected_characters([selected_character])
	Global.set_current_character(selected_character)
	
	if Network.is_multiplayer():
		var current_peer_id = multiplayer.get_unique_id()
		# Ensure the character data sent to network has is_ai: false
		var character_for_network = selected_character.duplicate(true)
		print("Character Options: Sending character to network with is_ai =", character_for_network.get("is_ai", true))
		
		Network.update_peer_info(current_peer_id, {"selected_character": character_for_network, "player_name": player_name})
		Network.sync_peer_character_selection.rpc(current_peer_id, character_for_network)
		print("Multiplayer: Loading game session")
		print("Debug: Current player character set to:", selected_character)
	else:
		print("Single player: Loading game session")
	
	# ENHANCED DEBUG: Add more detailed debugging around scene change
	print("CharacterOptions: About to change scene to game_session.tscn")
	print("CharacterOptions: Current scene tree: ", get_tree())
	print("CharacterOptions: Scene file exists: ", FileAccess.file_exists("res://ScenSyn/scenes/game_session.tscn"))
	
	StoryState.reset()
	await get_tree().process_frame
	
	print("CharacterOptions: Attempting scene change...")
	var scene_change_result = get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")
	print("CharacterOptions: Scene change result: ", scene_change_result)

func _on_confirm_pressed_2():
	print("Here is a check FOR CURRENT SCENARIO: ", str(game_flow_manager.get_current_scenario()))
					
func sync_peer_info(peer_id: int, info: Dictionary):
	print("Syncing peer info: ", info)
	Network.peer_info[peer_id] = info
	
	var current_peer_id = multiplayer.get_unique_id()
	if peer_id == current_peer_id:
		Global.set_current_character(info)
		print("Debug: Updated current character to:", info)
		
	if Network.peer_info.size() == Network.connected_peers.size():
		if multiplayer.is_server():
			_assign_ai_characters()
		print("All peers ready: Loading game session")
		get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")

func _assign_ai_characters():
	var ai_count = Network.MAX_PEERS - Network.connected_peers.size()
	# FIXED: Don't use 'available_characters' name to avoid shadowing class variable
	var unselected_chars = generated_characters.filter(func(char): 
		return not char in Network.peer_info.values().map(func(info): return info.get("selected_character"))
	)
	
	for i in range(min(ai_count, unselected_chars.size())):
		var ai_id = Network.MAX_PEERS + i + 1
		var ai_character = unselected_chars[i]
		ai_character["is_ai"] = true
		Network.peer_info[ai_id] = {"selected_character": ai_character, "player_name": "AI " + str(i+1)}
	
	Network.rpc("sync_full_peer_info", Network.peer_info)
	
func _on_character_selected(index: int):
	var current_peer_id = multiplayer.get_unique_id()
	var selected_character_data = get_character_data(index)
	
	if selected_character_data:
		# Update the peer info
		Network.update_peer_info(current_peer_id, {"selected_character": selected_character_data[0]})
	else:
		print("Error: Invalid character index")

func get_character_data(index: int) -> Dictionary:
	# Implement this method to return the character data based on the index
	# This could be fetching from a resource, a predefined array, or any other data source
	# Return an empty dictionary if the index is invalid
	# Example:
	var characters = [
		{"name": "Character 1", "class": "Warrior"},
		{"name": "Character 2", "class": "Mage"},
		{"name": "Character 3", "class": "Rogue"}
	]
	
	if index >= 0 and index < characters.size():
		return characters[index]
	else:
		return {}
				
func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Mouse click detected at: ", event.position)

func update_character_pool(characters):
	generated_characters = characters
	_update_available_characters()
	_update_character_list_ui()
	for character in characters:
		print("Have a look at this Character: ", character.get("name"), " Description: ", character.get("description"))

func _update_available_characters():
	# FIXED: Show all characters, not just unselected ones
	# Characters should be visible but marked as "taken" if selected by others
	available_characters = generated_characters.duplicate()
	
	print("Character Options: Available characters count: ", available_characters.size())
	for character in available_characters:
		print("  - ", character.get("name", "Unnamed"), " (ID: ", character.get("id", "no ID"), ")")

func _update_character_list_ui():
	print("Character Options: Updating character list UI")
	if get_tree() == null:
		print("Character Options: get_tree() is null; node probably removed from scene. Skipping UI update.")
		return
	# Clear existing character list UI
	for child in character_list.get_children():
		child.queue_free()
	
	# Wait a frame to ensure UI cleanup
	await get_tree().process_frame
	if get_tree() == null:
		return
	
	# Create checkboxes and labels for each available character
	for i in range(available_characters.size()):
		var character: Dictionary = available_characters[i]
		var is_selected_by_me: bool = i in selected_characters
		var is_taken_by_others: bool = Network.is_character_taken(character) and not is_selected_by_me
		var char_card: PanelContainer = _build_character_card(character, i, is_selected_by_me, is_taken_by_others)
		character_list.add_child(char_card)

func _build_character_card(character: Dictionary, index: int, is_selected_by_me: bool, is_taken_by_others: bool) -> PanelContainer:
	var char_card := PanelContainer.new()
	char_card.custom_minimum_size = Vector2(0, 168)
	char_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_card.add_theme_stylebox_override("panel", _build_character_card_style(is_selected_by_me, is_taken_by_others))

	# Atmospheric background — layered behind content, expands to fill card
	var bg_rect := TextureRect.new()
	bg_rect.layout_mode = 1
	bg_rect.anchors_preset = 15
	bg_rect.anchor_right = 1.0
	bg_rect.anchor_bottom = 1.0
	bg_rect.grow_horizontal = 2
	bg_rect.grow_vertical = 2
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.modulate = Color(1.0, 1.0, 1.0, 0.30 if is_taken_by_others else 0.42)
	var bg_path: String = _BG_PORTRAIT_TEXTURES[index % _BG_PORTRAIT_TEXTURES.size()]
	var bg_tex: Texture2D = load(bg_path) as Texture2D
	if bg_tex:
		bg_rect.texture = bg_tex
	char_card.add_child(bg_rect)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 16)
	card_margin.add_theme_constant_override("margin_top", 16)
	card_margin.add_theme_constant_override("margin_right", 16)
	card_margin.add_theme_constant_override("margin_bottom", 16)
	char_card.add_child(card_margin)

	var card_row := HBoxContainer.new()
	card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	card_row.add_theme_constant_override("separation", 16)
	card_margin.add_child(card_row)

	var portrait_rect := TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(_PORTRAIT_WIDTH, _PORTRAIT_HEIGHT)
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_rect.texture = _get_character_portrait_texture(character)
	card_row.add_child(portrait_rect)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 8)
	card_row.add_child(content_vbox)

	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 12)
	content_vbox.add_child(title_row)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 4)
	title_row.add_child(title_vbox)

	var name_label := Label.new()
	name_label.text = character.get("name", "Unnamed")
	name_label.add_theme_font_size_override("font_size", 24)
	title_vbox.add_child(name_label)

	var role_label := Label.new()
	role_label.text = character.get("role", "Unknown Role")
	role_label.add_theme_font_size_override("font_size", 16)
	title_vbox.add_child(role_label)

	var checkbox := CheckBox.new()
	checkbox.name = "SelectionCheckBox"
	checkbox.text = ""
	checkbox.set_pressed_no_signal(is_selected_by_me)
	checkbox.disabled = is_taken_by_others
	checkbox.toggled.connect(_on_character_toggled.bind(index))
	title_row.add_child(checkbox)

	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 13)
	content_vbox.add_child(status_label)

	var desc_label := Label.new()
	desc_label.name = "DescriptionLabel"
	desc_label.text = character.get("description", "No description available")
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(desc_label)

	_refresh_character_card_state(char_card, character, is_selected_by_me, is_taken_by_others)
	return char_card

func _build_character_card_style(is_selected_by_me: bool, is_taken_by_others: bool) -> StyleBoxFlat:
	var is_dark: bool = ThemeManager.is_dark()
	var style_box := StyleBoxFlat.new()
	style_box.content_margin_left = 0.0
	style_box.content_margin_top = 0.0
	style_box.content_margin_right = 0.0
	style_box.content_margin_bottom = 0.0
	style_box.corner_radius_top_left = 18
	style_box.corner_radius_top_right = 18
	style_box.corner_radius_bottom_right = 18
	style_box.corner_radius_bottom_left = 18
	style_box.shadow_color = Color(0.08, 0.06, 0.18, 0.25)
	style_box.shadow_size = 4
	style_box.shadow_offset = Vector2(0, 2)
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	if is_dark:
		if is_taken_by_others:
			style_box.bg_color = Color(0.12, 0.10, 0.20, 0.82)
			style_box.border_color = Color(0.35, 0.30, 0.55, 0.6)
		elif is_selected_by_me:
			style_box.bg_color = Color(0.14, 0.10, 0.30, 0.88)
			style_box.border_color = Color(0.55, 0.35, 0.95, 1.0)
		else:
			style_box.bg_color = Color(0.10, 0.08, 0.18, 0.78)
			style_box.border_color = Color(0.28, 0.24, 0.50, 0.7)
	else:
		if is_taken_by_others:
			style_box.bg_color = Color(0.965, 0.965, 0.972, 0.88)
			style_box.border_color = Color(0.78, 0.78, 0.84, 1.0)
		elif is_selected_by_me:
			style_box.bg_color = Color(0.96, 0.94, 1.0, 0.92)
			style_box.border_color = Color(0.37, 0.27, 0.86, 1.0)
		else:
			style_box.bg_color = Color(1.0, 1.0, 1.0, 0.86)
			style_box.border_color = Color(0.84, 0.84, 0.9, 1.0)
	return style_box

func _refresh_character_card_state(card_node: PanelContainer, character: Dictionary, is_selected_by_me: bool, is_taken_by_others: bool) -> void:
	card_node.add_theme_stylebox_override("panel", _build_character_card_style(is_selected_by_me, is_taken_by_others))
	# Update background opacity too
	var bg_rect_node: TextureRect = card_node.get_child(0) as TextureRect
	if bg_rect_node and bg_rect_node is TextureRect:
		bg_rect_node.modulate = Color(1.0, 1.0, 1.0, 0.30 if is_taken_by_others else 0.42)
	var checkbox_node: CheckBox = card_node.find_child("SelectionCheckBox", true, false) as CheckBox
	if checkbox_node:
		checkbox_node.set_pressed_no_signal(is_selected_by_me)
		checkbox_node.disabled = is_taken_by_others
		checkbox_node.tooltip_text = "Taken by another player." if is_taken_by_others else "Select this character."
	var is_dark: bool = ThemeManager.is_dark()
	var status_label: Label = card_node.find_child("StatusLabel", true, false) as Label
	if status_label:
		if is_taken_by_others:
			status_label.text = "Taken"
			status_label.modulate = Color(0.65, 0.60, 0.70, 1) if is_dark else Color(0.55, 0.55, 0.6, 1)
		elif is_selected_by_me:
			status_label.text = "Selected"
			status_label.modulate = Color(0.75, 0.55, 1.0, 1) if is_dark else Color(0.34, 0.25, 0.83, 1)
		else:
			status_label.text = "Available"
			status_label.modulate = Color(0.70, 0.68, 0.78, 1) if is_dark else Color(0.43, 0.43, 0.5, 1)
	var description_label: Label = card_node.find_child("DescriptionLabel", true, false) as Label
	if description_label:
		if is_dark:
			description_label.modulate = Color(0.60, 0.58, 0.68, 1) if is_taken_by_others else Color(0.88, 0.86, 0.94, 1)
		else:
			description_label.modulate = Color(0.4, 0.4, 0.44, 1) if is_taken_by_others else Color(0.2, 0.2, 0.24, 1)

func _get_character_portrait_texture(character: Dictionary) -> Texture2D:
	var char_name: String = str(character.get("name", "")).strip_edges()
	if char_name.is_empty():
		return _create_blank_portrait_texture()
	var portrait_path: String = _find_character_idle_portrait_path(char_name)
	if portrait_path.is_empty():
		return _create_blank_portrait_texture()
	var texture_any: Variant = CharacterScript._load_texture_any(portrait_path)
	if texture_any is Texture2D:
		return texture_any
	return _create_blank_portrait_texture()

func _find_character_idle_portrait_path(char_name: String) -> String:
	var roots: Array[String] = CharacterScript._get_sprite_roots_for_current_scenario()
	var char_dir_name: String = CharacterScript._dir_slug(char_name)
	var allowed_exts: Array[String] = [".png", ".jpg", ".jpeg", ".webp"]
	for root_path_any in roots:
		var root_path: String = str(root_path_any).strip_edges()
		if root_path.is_empty():
			continue
		var idle_dir_path: String = root_path.path_join(char_dir_name).path_join("idle")
		var dir_access: DirAccess = DirAccess.open(idle_dir_path)
		if dir_access == null:
			continue
		var frame_paths: Array[String] = []
		dir_access.list_dir_begin()
		var file_name: String = dir_access.get_next()
		while file_name != "":
			if not dir_access.current_is_dir() and not file_name.begins_with("."):
				var lowered_name: String = file_name.to_lower()
				for ext in allowed_exts:
					if lowered_name.ends_with(ext):
						frame_paths.append(idle_dir_path.path_join(file_name))
						break
			file_name = dir_access.get_next()
		dir_access.list_dir_end()
		frame_paths.sort()
		if not frame_paths.is_empty():
			var first_frame_path: String = frame_paths[0]
			if root_path.begins_with("res://"):
				return first_frame_path.replace("\\", "/")
			return first_frame_path.replace("\\", "/")
	return ""

func _create_blank_portrait_texture() -> Texture2D:
	var image := Image.create(_PORTRAIT_WIDTH, _PORTRAIT_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.93, 0.93, 0.95, 1.0))
	var border_color := Color(0.8, 0.8, 0.85, 1.0)
	for x_idx in range(_PORTRAIT_WIDTH):
		image.set_pixel(x_idx, 0, border_color)
		image.set_pixel(x_idx, _PORTRAIT_HEIGHT - 1, border_color)
	for y_idx in range(_PORTRAIT_HEIGHT):
		image.set_pixel(0, y_idx, border_color)
		image.set_pixel(_PORTRAIT_WIDTH - 1, y_idx, border_color)
	return ImageTexture.create_from_image(image)
	
func _on_character_selection_failed(reason: String):
	print("Character selection failed: ", reason)
	# Uncheck all characters
	for container in character_list.get_children():
		var checkbox: CheckBox = container.find_child("SelectionCheckBox", true, false) as CheckBox
		if checkbox:
			checkbox.set_pressed_no_signal(false)
	selected_characters.clear()
	# Display an error message using OS alert
	OS.alert(reason, "Character Selection Failed")
	# Update the available characters and UI
	_update_available_characters()
	_update_character_list_ui()

func display_error_message(message: String):
	# Implement this function to display the error message in your UI
	# For example, you could use a Label or a popup dialog
	pass

func _update_character_checkboxes():
	print("=== _update_character_checkboxes called ===")
	print("Available characters count: ", available_characters.size())
	print("Selected characters: ", selected_characters)
	print("Character list children count: ", character_list.get_child_count())
	print("Network peer info: ", Network.get_peer_info())
	
	# Safely update the enabled / disabled state of every checkbox based on Network data
	for i in range(character_list.get_child_count()):
		var container: Node = character_list.get_child(i)
		if not (container is PanelContainer):
			print("Skipping container ", i, " - invalid structure")
			continue
		var checkbox: CheckBox = container.find_child("SelectionCheckBox", true, false) as CheckBox
		if not checkbox:
			print("Skipping container ", i, " - no checkbox found")
			continue
		if i >= available_characters.size():
			print("Skipping container ", i, " - index exceeds available characters")
			continue
			
		var character: Dictionary = available_characters[i]
		var is_selected_by_me: bool = i in selected_characters
		var is_taken_by_others: bool = Network.is_character_taken(character) and not is_selected_by_me
		
		_refresh_character_card_state(container as PanelContainer, character, is_selected_by_me, is_taken_by_others)
		
		print("Character ", i, " '", character.get("name", "Unnamed"), "':")
		print("  - Selected by me: ", is_selected_by_me)
		print("  - Taken by others: ", is_taken_by_others) 
		print("  - Checkbox disabled: ", checkbox.disabled)
		print("  - Checkbox pressed: ", checkbox.button_pressed)
	
	print("=== _update_character_checkboxes completed ===")

func _on_peer_connected(peer_id: int):
	print("Character Options: Peer connected, refreshing UI")
	if get_tree() == null:
		return
	await get_tree().create_timer(0.1).timeout
	if get_tree() == null:
		return
	_update_character_checkboxes()

func _on_peer_disconnected(peer_id: int):
	print("Character Options: Peer disconnected, refreshing UI") 
	if get_tree() == null:
		return
	await get_tree().create_timer(0.1).timeout
	if get_tree() == null:
		return
	_update_character_checkboxes()

func _on_peer_info_updated():
	print("Character Options: Peer info updated, refreshing UI")
	# If node is no longer in scene tree, skip to prevent null errors
	if get_tree() == null:
		print("Character Options: Node no longer in scene tree; skipping UI refresh")
		return
	# Small delay to ensure peer info is synced
	await get_tree().create_timer(0.1).timeout
	if get_tree() == null:
		return
	_update_character_checkboxes()

func _on_hamburger_menu_pressed():
	var services = get_tree().root.find_child("ServicesPanel", true, false)
	if services and services.has_method("is_panel_open") and services.is_panel_open():
		services.close_panel()
		if hamburger_settings_panel:
			hamburger_settings_panel.visible = false
		return
	if hamburger_settings_panel:
		hamburger_settings_panel.visible = not hamburger_settings_panel.visible

func _toggle_services_panel():
	# Find Services panel in the scene tree (globally accessible)
	var services = get_tree().root.find_child("ServicesPanel", true, false)
	if services:
		if services.has_method("is_panel_open") and services.is_panel_open():
			if hamburger_settings_panel:
				hamburger_settings_panel.visible = false
			return
		if services.has_method("open_panel"):
			services.open_panel()
		else:
			services.visible = true
		if hamburger_settings_panel:
			hamburger_settings_panel.visible = false

func _on_back_pressed():
	var services = get_tree().root.find_child("ServicesPanel", true, false)
	if services and services.has_method("is_panel_open") and services.is_panel_open():
		services.close_panel()
	# Return to ScenSyn landing scene
	get_tree().change_scene_to_file("res://ScenSyn/scenes/main_menu.tscn")

func _update_bg_color() -> void:
	if _bg_color_rect == null:
		return
	var is_dark: bool = ThemeManager.is_dark()
	if is_dark:
		_bg_color_rect.color = Color(0.039, 0.055, 0.078, 1.0)
	else:
		_bg_color_rect.color = Color(0.953, 0.965, 0.984, 1.0)
	if is_instance_valid(_bg_image):
		_bg_image.texture = _BG_DARK if is_dark else _BG_LIGHT
		_bg_image.modulate.a = 1.0
		_bg_image.visible = true

func _on_theme_changed() -> void:
	_update_bg_color()
	_update_character_list_ui()
