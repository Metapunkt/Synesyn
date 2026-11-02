extends Control
class_name ScenarioBuilder

signal scenario_saved(scenario: Dictionary)
signal builder_cancelled

const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)
const ScenarioBundleScript = preload("res://ScenSyn/scripts/core/scenario_bundle.gd")
const ScenarioShareUiScript = preload("res://ScenSyn/scripts/core/scenario_share_ui.gd")

## When true, Finish emits scenario_saved and does not change scenes.
## Used when mounted as an overlay inside GameModePopup for Open Play.
var embedded_mode: bool = false

var metaprompt_manager  # BaseMetapromptManager - untyped for dynamic dispatch
var current_step = 0
var scenario_data = {}
var scenario_steps = ["setting", "objective", "characters", "plot_twists"]
var previous_response: String = ""
var _selected_tags: Array[String] = []

var setup_steps_text = {
	"setting": "[b][font_size=16]Scenario creation for this game experience.[/font_size][/b]\nYou may edit the text for the scenario name and scenario description below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating the scenario based on your prompt guidance.",
	"objective": "[b][font_size=16]Scenario definition.[/font_size][/b]\nYou may click next if fine with this scenario, or edit the text for the scenario name and scenario description below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating the scenario based on your prompt guidance.",
	"characters": "[b][font_size=16]Character creation for this game scenario.[/font_size][/b]\nYou may edit the text for the character name and character description below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating these characters based on your prompt guidance.",
	"plot_twists": "[b][font_size=16]Plot twists for this game scenario.[/font_size][/b]\nYou may click 'finish' if fine with these plot twists, or edit the text for the plot twists described below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating plot twists based on your prompt guidance."
}

@onready var scenario_name_label: Label = %ScenarioNameLabel
@onready var scenario_name_input: LineEdit = %ScenarioNameInput
@onready var setting_input: TextEdit = %SettingInput
@onready var objective_input: TextEdit = %ObjectiveInput
@onready var player_input_field: LineEdit = %PlayerInputField
@onready var characters_grid: GridContainer = %CharactersGrid
@onready var plot_twists_list: GridContainer = %PlotTwistsList
@onready var next_button: Button = %NextButton
@onready var retry_button: Button = %RetryButton
@onready var previous_button: Button = %PreviousButton
@onready var finish_button: Button = %FinishButton
@onready var prompt_label: RichTextLabel = %PromptLabel
@onready var genre_option_button: OptionButton = %ThemeOptionButton
@onready var customization_input: LineEdit = %CustomizationInput
@onready var progress_bar = %ProgressBar
@onready var _share_button: Button = %ShareStoryButton
@onready var _import_button: Button = %ImportStoryButton
@onready var _share_status_label: Label = %ShareStatusLabel

var _import_dialog: FileDialog = null


func _ready():
	# Open Play crafting always uses the Open Play manager when embedded from
	# the Story Catalyst popup; otherwise honour the current Global collection.
	var session_type_id: String = String(Global.current_session_type)
	var collection_id: String = String(Global.current_collection_id)
	if embedded_mode or collection_id == "open_play":
		session_type_id = "story_catalyst"
		collection_id = "open_play"
	metaprompt_manager = Global.get_metaprompt_manager_for_collection(
		session_type_id,
		collection_id
	)
	populate_genre_options()
	genre_option_button.connect("item_selected", Callable(self, "_on_genre_selected"))
	customization_input.connect("text_changed", Callable(self, "_on_customization_changed"))
	player_input_field.connect("text_submitted", Callable(self, "_on_player_input_submitted"))
	next_button.connect("pressed", Callable(self, "_on_next_pressed"))
	retry_button.connect("pressed", Callable(self, "_on_retry_pressed"))
	previous_button.connect("pressed", Callable(self, "_on_previous_pressed"))
	finish_button.connect("pressed", Callable(self, "_on_finish_pressed"))
	_share_button.pressed.connect(_on_share_pressed)
	_import_button.pressed.connect(_on_import_pressed)
	if not embedded_mode:
		start_scenario_building()


func configure_for_open_play_overlay() -> void:
	embedded_mode = true
	Global.current_session_type = "story_catalyst"
	Global.current_collection_id = "open_play"
	if metaprompt_manager and is_instance_valid(metaprompt_manager):
		metaprompt_manager.queue_free()
	metaprompt_manager = Global.get_metaprompt_manager_for_collection(
		"story_catalyst",
		"open_play"
	)
	add_child(metaprompt_manager)
	_selected_tags.clear()
	_apply_tags_to_manager()
	# Caller decides whether to start a fresh AI draft or load a saved scenario.

func start_scenario_building():
	current_step = 0
	scenario_data = {}
	if scenario_name_input:
		scenario_name_input.text = ""
	update_ui()
	generate_content_for_current_step()

func update_ui():
	var input_nodes = {
		"setting": setting_input,
		"objective": objective_input,
		"characters": characters_grid,
		"plot_twists": plot_twists_list
	}
	
	for step in scenario_steps:
		if input_nodes.has(step):
			input_nodes[step].visible = (scenario_steps.find(step) == current_step)
		else:
			print("Warning: No input node found for step: ", step)

	# Title is authored with setting/objective — keep it editable on those steps.
	var step_id: String = scenario_steps[current_step]
	var show_title: bool = step_id == "setting" or step_id == "objective"
	if scenario_name_label:
		scenario_name_label.visible = show_title
	if scenario_name_input:
		scenario_name_input.visible = show_title
		if show_title:
			var existing_title: String = String(scenario_data.get("name", "")).strip_edges()
			if scenario_name_input.text.strip_edges().is_empty() and not existing_title.is_empty():
				scenario_name_input.text = existing_title
	
	previous_button.disabled = (current_step == 0)
	next_button.visible = (current_step < scenario_steps.size() - 1)
	finish_button.visible = (current_step == scenario_steps.size() - 1)
	
#	prompt_label.text = metaprompt_manager.get_metaprompt("scenario_creation", current_step)
#	prompt_label.text = setup_steps_text[scenario_steps[current_step]]
	prompt_label.text = get_prompt_text(current_step)

func get_prompt_text(step: int) -> String:
	var prompt_texts = {
		"setting": "[font_size=16][b]Scenario creation for this game experience.[/b][/font_size]\nYou may edit the text for the scenario name and scenario description below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating the scenario based on your prompt guidance.",
		"objective": "[font_size=16][b]Scenario definition.[/b][/font_size]\nYou may click next if fine with this scenario, or edit the text for the scenario name and scenario description below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating the scenario based on your prompt guidance.",
		"characters": "[font_size=16][b]Character creation for this game scenario.[/b][/font_size]\nYou may edit the text for the character name and character description below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating these characters based on your prompt guidance.",
		"plot_twists": "[font_size=16][b]Plot twists for this game scenario.[/b][/font_size]\nYou may click 'finish' if fine with these plot twists, or edit the text for the plot twists described below and click next, or write a prompt in the player input field and press enter to have the AI have another go at creating plot twists based on your prompt guidance."
	}
	return prompt_texts[scenario_steps[step]]
	
func populate_genre_options():
	# Curated Open Play tags: selecting toggles membership (multi-tag).
	genre_option_button.clear()
	genre_option_button.add_item("Tags (tap to toggle)…")
	for tag_label: String in StoryScenarioContractScript.CURATED_TAGS:
		genre_option_button.add_item(tag_label)
	_refresh_tag_button_caption()

func _on_genre_selected(index: int):
	if index <= 0:
		return
	var selected_tag: String = genre_option_button.get_item_text(index)
	if _selected_tags.has(selected_tag):
		_selected_tags.erase(selected_tag)
	else:
		_selected_tags.append(selected_tag)
	_apply_tags_to_manager()
	_refresh_tag_button_caption()
	genre_option_button.select(0)


func _apply_tags_to_manager() -> void:
	if not metaprompt_manager:
		return
	var theme_text: String = (
		", ".join(_selected_tags) if not _selected_tags.is_empty() else "Open Play"
	)
	metaprompt_manager.set_game_theme(theme_text)
	metaprompt_manager.set_additional_customization(
		StoryScenarioContractScript.tags_prompt_fragment(_selected_tags)
		+ (" " + customization_input.text.strip_edges() if customization_input else "")
	)


func _refresh_tag_button_caption() -> void:
	if not genre_option_button:
		return
	if _selected_tags.is_empty():
		genre_option_button.set_item_text(0, "Tags (tap to toggle)…")
	else:
		genre_option_button.set_item_text(0, "Tags: " + ", ".join(_selected_tags))

func _on_customization_changed(_new_text: String):
	_apply_tags_to_manager()
	
func _on_player_input_submitted(new_text: String):
	generate_content_for_current_step()
	
func _on_next_pressed():
	save_current_step_data()
	if current_step < scenario_steps.size() - 1:
		current_step += 1
		update_ui()
		generate_content_for_current_step()
	else:
		# If it's the last step, just regenerate the current step with the new input
		generate_content_for_current_step()

func _on_retry_pressed():
	generate_content_for_current_step(true)
	
func _on_previous_pressed():
	save_current_step_data()
	if current_step > 0:
		current_step -= 1
		update_ui()
		load_step_data()

func _on_finish_pressed():
	save_current_step_data()
	finalize_scenario()
	
func generate_content_for_current_step(is_retry: bool = false):
	progress_bar.value = 0
	var tween = create_tween()
	tween.tween_property(progress_bar, "value", 75, 5.0)
	
	var prompt = metaprompt_manager.get_metaprompt("scenario_creation", current_step)
	
	var player_input = player_input_field.text.strip_edges()
	if not player_input.is_empty():
		prompt += "\n\nAdditional player input: " + player_input
		player_input_field.clear()
		
	if scenario_data.size() > 0:
		prompt += "\n\nCurrent scenario:\n" + JSON.stringify(scenario_data)
	
	if is_retry:
		prompt += "\n\nPlease provide an alternative response."
		
	print("Generating content for step: ", scenario_steps[current_step])
	var conversation_service = get_conversation_service()
	if conversation_service == null or not conversation_service.has_method("chat"):
		push_error("ScenarioBuilder: Conversation service unavailable")
		tween.kill()
		progress_bar.value = 0
		return
	# ConversationManager.chat returns Dictionary {success, response|error}, not a bare String.
	var chat_result: Variant = await conversation_service.chat(prompt)
	var response_text: String = _chat_response_text(chat_result)
	if response_text.is_empty():
		push_error("ScenarioBuilder: AI chat failed or returned empty text")
		tween.kill()
		progress_bar.value = 0
		return
	print("Received response for step: ", scenario_steps[current_step])

	match scenario_steps[current_step]:
		"setting":
			var parsed_response: Dictionary = parse_setting_response(response_text)
			var parsed_name: String = String(parsed_response.get("name", "")).strip_edges()
			if not parsed_name.is_empty():
				scenario_data["name"] = parsed_name
			call_deferred("set_scenario_name_content", String(scenario_data.get("name", "")))
			call_deferred("set_setting_content", String(parsed_response.get("setting", "")))
		"objective":
			call_deferred("set_objective_content", response_text)
		"characters":
			call_deferred("set_characters_content", response_text)
		"plot_twists":
			print("Raw plot twists response:", response_text)
			call_deferred("set_plot_twists_content", response_text)

	tween.kill()
	progress_bar.value = 100

	var final_tween = create_tween()
	final_tween.tween_property(progress_bar, "value", 100, 0.5)
	await final_tween.finished

	await get_tree().create_timer(0.5).timeout
	progress_bar.value = 0


func _chat_response_text(chat_result: Variant) -> String:
	if typeof(chat_result) == TYPE_STRING:
		return String(chat_result).strip_edges()
	if typeof(chat_result) != TYPE_DICTIONARY:
		return ""
	var result: Dictionary = chat_result
	if not bool(result.get("success", false)):
		print("ScenarioBuilder: chat error: ", result.get("error", "unknown"))
		return ""
	return String(result.get("response", "")).strip_edges()

func set_scenario_name_content(content: String) -> void:
	if scenario_name_input == null:
		return
	scenario_name_input.text = content
	scenario_name_input.visible = true
	if scenario_name_label:
		scenario_name_label.visible = true


func set_setting_content(content: String):
	setting_input.text = content
	setting_input.visible = true
	print("Setting content set: ", content)

func set_objective_content(content: String):
	objective_input.text = content	
	objective_input.visible = true
	print("Objective content set: ", content)

func set_characters_content(content: String):
	var characters = parse_characters(content)
	populate_characters_grid(characters)
	characters_grid.visible = true
	print("Characters content set")

func set_plot_twists_content(content: String):
	print("Raw plot twists response:\n", content)
	var twists = parse_list_response(content)
	populate_plot_twists_list(twists)
	plot_twists_list.visible = true
	print("Plot twists content set")

func parse_setting_response(response: String) -> Dictionary:
	var lines = response.split("\n")
	var scenario_name = ""
	var setting = ""
	
	for line in lines:
		var cleaned_line: String = line.strip_edges()
		# Accept common AI variants: "Scenario Name:", "**Scenario Name:**", etc.
		var lower_line: String = cleaned_line.to_lower()
		var name_prefix_idx: int = lower_line.find("scenario name:")
		if name_prefix_idx >= 0:
			var after_prefix: String = cleaned_line.substr(name_prefix_idx + "scenario name:".length())
			scenario_name = after_prefix.strip_edges().trim_prefix("*").trim_suffix("*").strip_edges()
			continue
		setting += line + "\n"
	
	setting = setting.strip_edges()
	
	return {
		"name": scenario_name,
		"setting": setting
	}


func _sync_scenario_name_from_ui() -> void:
	if scenario_name_input == null:
		return
	var title_text: String = scenario_name_input.text.strip_edges()
	if not title_text.is_empty():
		scenario_data["name"] = title_text
	
func parse_characters(response: String) -> Array:
	var characters = []
	var lines = response.split("\n")
	var current_character = {}
	
	for line in lines:
		line = line.strip_edges()
		if line.begins_with("Name:"):
			if not current_character.is_empty():
				characters.append(current_character)
			current_character = {
				"name": line.substr(5).strip_edges(),
				"role": "Character",
				"description": "",
			}
		elif line.begins_with("Role:"):
			current_character["role"] = line.substr(5).strip_edges()
		elif line.begins_with("Description:"):
			current_character["description"] = line.substr(12).strip_edges()
		elif not line.is_empty() and not current_character.is_empty():
			current_character["description"] += " " + line

	if not current_character.is_empty():
		characters.append(current_character)

	print("Number of characters parsed: ", characters.size())
	for character in characters:
		print("Parsed character: ", character)
	if characters.is_empty():
		characters.append({
			"name": "Default Character",
			"role": "Character",
			"description": "No description available",
		})
	return characters

func populate_characters_grid(characters: Array):
	for child in characters_grid.get_children():
		child.queue_free()	
	for character in characters:
		# Character Name (Bold)
		var name_edit = TextEdit.new()
		name_edit.text = character.get("name", "Unnamed Character")
		name_edit.add_theme_font_size_override("font_size", 16)
		name_edit.custom_minimum_size = Vector2(250, 32)  # Adjust as needed
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.add_theme_font_override("normal_font", get_theme_font("bold", "TextEdit"))
		name_edit.scroll_fit_content_height = true  # Enable fit content height
		# Set anchor preset to center left
		name_edit.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		# TextEdit draws its own "background_color" theme item on top of any
		# custom StyleBox override, and the active (theme-managed) surface
		# theme's background_color can be white — so the stylebox override
		# alone was getting painted over, leaving white text on a white box.
		# Override both the stylebox AND the background_color explicitly so
		# this stays legible regardless of the active light/dark theme.
		name_edit.add_theme_stylebox_override("normal", create_grey_stylebox(0.2, 0.2, 0.2, 1, 8))
		name_edit.add_theme_stylebox_override("focus", create_grey_stylebox(0.2, 0.2, 0.2, 1, 8))
		name_edit.add_theme_color_override("background_color", Color(0.2, 0.2, 0.2, 1))
		name_edit.add_theme_color_override("font_color", Color.WHITE)
		name_edit.add_theme_color_override("font_selected_color", Color.WHITE)
		name_edit.add_theme_color_override("caret_color", Color.WHITE)
		characters_grid.add_child(name_edit)		
		# Character Description
		var desc_edit = TextEdit.new()
		desc_edit.text = character.get("description", "No description available")
		desc_edit.custom_minimum_size = Vector2(300, 120)  # Adjust as needed
		desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		desc_edit.scroll_fit_content_height = true  # Enable fit content height 
		# Same explicit background_color override — see note above.
		desc_edit.add_theme_stylebox_override("normal", create_grey_stylebox(0.88, 0.88, 0.88, 1, 8))
		desc_edit.add_theme_stylebox_override("focus", create_grey_stylebox(0.88, 0.88, 0.88, 1, 8))
		desc_edit.add_theme_color_override("background_color", Color(0.88, 0.88, 0.88, 1))
		desc_edit.add_theme_color_override("font_color", Color.BLACK)
		characters_grid.add_child(desc_edit)		
		# Add spacing
		var spacing = Control.new()
		spacing.custom_minimum_size = Vector2(0, 12)  # Adjust vertical spacing as needed
		characters_grid.add_child(spacing)	
	print("Number of characters added to grid: ", characters.size())

func create_grey_stylebox(r, g, b, a, m) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(r, g, b, a)
	style.content_margin_left = m
	style.content_margin_right = m
	style.content_margin_top = m
	style.content_margin_bottom = m
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

func parse_list_response(response: String) -> Array:
	var items = []
	var lines = response.split("\n")
	for line in lines:
		line = line.strip_edges()
		if line.match("*. *"):  # Matches any numbered list item
			items.append(line.substr(line.find(" ") + 1))  # Remove the number and period
	print("Parsed plot twists:", items)
	return items

#func populate_plot_twists_list(twists: Array):
	#plot_twists_list.clear()
	#for twist in twists:
		#plot_twists_list.add_item(twist)
	#print("Number of plot twists added to list:", plot_twists_list.get_item_count())

func populate_plot_twists_list(twists: Array):
	# Clear existing children
	for child in plot_twists_list.get_children():
		child.queue_free()
	
	for twist in twists:
		var twist_edit = TextEdit.new()
		twist_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		twist_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		twist_edit.custom_minimum_size = Vector2(300, 60)  # Adjust size as needed
		twist_edit.text = twist
		twist_edit.add_theme_stylebox_override("normal", create_grey_stylebox(0.88, 0.88, 0.88, 1, 8))
		twist_edit.add_theme_stylebox_override("focus", create_grey_stylebox(0.88, 0.88, 0.88, 1, 8))
		twist_edit.add_theme_color_override("background_color", Color(0.88, 0.88, 0.88, 1))
		twist_edit.add_theme_color_override("font_color", Color.BLACK)
		twist_edit.scroll_fit_content_height = true
		plot_twists_list.add_child(twist_edit)
	
	print("Number of plot twists added:", plot_twists_list.get_child_count())
	
func save_current_step_data():
	match scenario_steps[current_step]:
		"setting":
			_sync_scenario_name_from_ui()
			scenario_data["setting"] = setting_input.text
		"objective":
			_sync_scenario_name_from_ui()
			scenario_data["objective"] = objective_input.text
			print("Saved objective: ", scenario_data["objective"])
		"characters":
			scenario_data["characters"] = []
			for i in range(0, characters_grid.get_child_count(), 3):
				var name_edit = characters_grid.get_child(i)
				var desc_edit = characters_grid.get_child(i + 1)
				var character = {
					"name": name_edit.text,
					"role": "Character",
					"description": desc_edit.text,
				}
				scenario_data["characters"].append(character)
		"plot_twists":
			scenario_data["plot_twists"] = []
			for child in plot_twists_list.get_children():
				if child is TextEdit:
					scenario_data["plot_twists"].append(child.text)
			#for i in range(plot_twists_list.get_item_count()):
				#scenario_data["plot_twists"].append(plot_twists_list.get_item_text(i))
				
func load_step_data():
	match scenario_steps[current_step]:
		"setting":
			if scenario_name_input:
				scenario_name_input.text = String(scenario_data.get("name", ""))
			setting_input.text = scenario_data.get("setting", "")
		"objective":
			if scenario_name_input:
				scenario_name_input.text = String(scenario_data.get("name", ""))
			objective_input.text = scenario_data.get("objective", "")
		"characters":
			populate_characters_grid(scenario_data.get("characters", []))
		"plot_twists":
			populate_plot_twists_list(scenario_data.get("plot_twists", []))

## The Story as currently described in the wizard, without persisting anything.
## Finish and Share both work from this so they can never disagree about what
## the user has authored.
func _build_custom_scenario() -> Dictionary:
	save_current_step_data()
	_sync_scenario_name_from_ui()
	scenario_data["tags"] = _selected_tags.duplicate()
	var scenario_title: String = String(scenario_data.get("name", "")).strip_edges()
	if scenario_title.is_empty():
		scenario_title = "Untitled Story"
	return StoryScenarioContractScript.create_custom({
		"id": String(scenario_data.get("id", "")).strip_edges(),
		"name": scenario_title,
		"setting": String(scenario_data.get("setting", "")),
		"objective": String(scenario_data.get("objective", "")),
		"characters": scenario_data.get("characters", []),
		"plot_twists": scenario_data.get("plot_twists", []),
		"tags": _selected_tags,
	})


func _on_share_pressed() -> void:
	var scenario: Dictionary = _build_custom_scenario()
	if String(scenario.get("name", "")).strip_edges() == "Untitled Story":
		_share_status_label.text = "Give the Story a name before sharing it."
		return
	var export_result: Dictionary = ScenarioBundleScript.export_scenarios([scenario])
	_share_status_label.text = ScenarioShareUiScript.export_message(export_result)
	if bool(export_result.get("ok", false)):
		ScenarioShareUiScript.reveal_exports_dir()


func _on_import_pressed() -> void:
	if _import_dialog == null:
		_import_dialog = ScenarioShareUiScript.make_import_dialog(self)
		_import_dialog.file_selected.connect(_on_import_file_selected)
	_import_dialog.popup_centered()


func _on_import_file_selected(path: String) -> void:
	var import_result: Dictionary = ScenarioBundleScript.import_bundle(
		path,
		[ScenarioBundleScript.SESSION_TYPE_STORY]
	)
	var message: String = ScenarioShareUiScript.import_message(import_result)
	if bool(import_result.get("ok", false)):
		message += " Pick it from the Story list to play it."
	_share_status_label.text = message


func finalize_scenario():
	var custom_scenario: Dictionary = _build_custom_scenario()
	# Finish writes into the selectable Open Play library (and refreshes the
	# working draft). Re-finishing a library id updates that entry in place.
	var save_result: Dictionary = StoryScenarioContractScript.save_to_library(custom_scenario)
	if bool(save_result.get("ok", false)):
		custom_scenario = save_result.get("scenario", custom_scenario) as Dictionary
	else:
		# Fall back to draft-only so the session can still proceed.
		var draft_result: Dictionary = StoryScenarioContractScript.save_local_draft(custom_scenario)
		if bool(draft_result.get("ok", false)):
			custom_scenario = draft_result.get("scenario", custom_scenario) as Dictionary

	if embedded_mode:
		scenario_saved.emit(custom_scenario)
		return

	# Standalone / legacy entry: load Open Play draft and go to character_options.
	if Global and Global.has_method("set_custom_story_scenario"):
		Global.set_custom_story_scenario(custom_scenario)
	elif Global:
		Global.get_game_flow_manager().set_current_scenario(custom_scenario)
	get_tree().change_scene_to_file("res://ScenSyn/scenes/character_options.tscn")


## Prefill the builder from a saved Open Play scenario (review / resume edit).
func load_existing_open_play_scenario(scenario: Dictionary) -> void:
	if scenario.is_empty():
		start_scenario_building()
		return
	current_step = 0
	scenario_data = {
		"id": String(scenario.get("id", "")),
		"name": String(scenario.get("name", "Untitled Story")),
		"setting": String(scenario.get("setting", scenario.get("description", ""))),
		"objective": String(scenario.get("objective", "")),
		"characters": scenario.get("characters", []),
		"plot_twists": scenario.get("plot_twists", []),
		"tags": scenario.get("tags", []),
	}
	_selected_tags.clear()
	var tags_any: Variant = scenario.get("tags", [])
	if typeof(tags_any) == TYPE_ARRAY:
		for tag_any: Variant in tags_any:
			var tag_text: String = String(tag_any).strip_edges()
			if not tag_text.is_empty() and not _selected_tags.has(tag_text):
				_selected_tags.append(tag_text)
	_apply_tags_to_manager()
	update_ui()
	load_step_data()
	if scenario_name_input:
		scenario_name_input.text = String(scenario_data.get("name", ""))


func request_cancel() -> void:
	builder_cancelled.emit()

# ADDED: Helper function to access SynTree conversation functionality
func get_conversation_service():
	# Try to get conversation capability through SynTree services
	if Global:
		var plugin_manager = Global.get_plugin_manager()
		if plugin_manager and plugin_manager.has_method("get_conversation_manager"):
			return plugin_manager.get_conversation_manager()
		
		# Fallback to Global's conversation manager
		return Global.get_conversation_manager()
	
	# Final fallback - return null if Global not available
	return null
