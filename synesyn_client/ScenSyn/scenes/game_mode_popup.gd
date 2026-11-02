# game_mode_popup.gd
extends PopupPanel

signal mode_selected(is_multiplayer, players)

const _DEFAULT_POPUP_WIDTH: float = 720.0
const _DEFAULT_POPUP_HEIGHT: float = 720.0
const _MIN_POPUP_WIDTH: float = 360.0
const _MAX_POPUP_WIDTH: float = 960.0
const _MIN_POPUP_HEIGHT: float = 420.0
## Grow with the viewport instead of staying glued to a fixed phone-like width.
const _WIDTH_VIEWPORT_FRACTION: float = 0.62
const _VIEWPORT_MARGIN_X: float = 48.0
const _VIEWPORT_MARGIN_Y: float = 60.0
const _MIN_TAB_HEIGHT: float = 220.0
const _MAX_TAB_HEIGHT: float = 420.0
const _STORY_BUILDER_MARGIN_X: float = 48.0
const _STORY_BUILDER_MARGIN_Y: float = 48.0
const _STORY_BUILDER_MIN_WIDTH: float = 560.0
const _STORY_BUILDER_MIN_HEIGHT: float = 480.0
const _STORY_BUILDER_MAX_WIDTH: float = 1100.0
const _STORY_BUILDER_MAX_HEIGHT: float = 820.0
const WorkshopScenarioContractScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_scenario_contract.gd"
)
const WorkshopSessionScannerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_scanner.gd"
)
const WorkshopMySessionListItemScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_my_session_list_item.tscn"
)
const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)
const OpenPlayModePopupHelpersScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/open_play_mode_popup_helpers.gd"
)
const ScenarioBuilderScene = preload("res://ScenSyn/scenes/scenario_builder.tscn")

@onready var popup_label = %PopUpLabel
@onready var multiplayer_checkbox = %Multiplayer
@onready var ip_input = %IP_Input
@onready var player_list = %PlayerList
@onready var confirm_button = %ConfirmButton
@onready var check_current_scenario_button = %CurrentScenarioButton
@onready var scenario_container = %ScenarioContainer
@onready var scenario_metaprompt_name = Global.get_current_scenario_metaprompt()
@onready var session_type_option_button: OptionButton = %SessionTypeOptionButton
@onready var collection_option_button: OptionButton = %CollectionOptionButton
@onready var scenario_option_button = %ScenarioOptionButton
@onready var scenario_label = %ScenarioLabel
@onready var about_label = %AboutLabel
@onready var how_to_label = %HowToLabel
@onready var scenario_tab_container: TabContainer = %ScenarioTabContainer
@onready var popup_scroll_container: ScrollContainer = $MarginContainer/ScrollContainer
@onready var popup_content_container: VBoxContainer = $MarginContainer/ScrollContainer/ScrollContentMargin/PopUpContainer
@onready var create_workshop_scenario_button: Button = %CreateWorkshopScenarioButton
@onready var create_story_scenario_button: Button = %CreateStoryScenarioButton
@onready var workshop_scenario_editor: Control = %WorkshopScenarioEditor
@onready var my_sessions_button: Button = %MySessionsButton
@onready var my_sessions_dialog: Control = %MySessionsDialog
@onready var my_sessions_list_container: VBoxContainer = %MySessionsListContainer
@onready var my_sessions_empty_state: Label = %MySessionsEmptyState
@onready var my_sessions_close_button: Button = %MySessionsCloseButton
@onready var my_sessions_scrim: ColorRect = %MySessionsScrim
@onready var story_builder_overlay: Control = %StoryBuilderOverlay
@onready var story_builder_card: PanelContainer = %StoryBuilderCard
@onready var story_builder_host: MarginContainer = %StoryBuilderHost
@onready var story_builder_close_button: Button = %StoryBuilderCloseButton
@onready var story_builder_scrim: ColorRect = %StoryBuilderScrim

var selected_players = []
var game_flow_manager
var scenario_loader = Global.get_scenario_loader()
var selected_scenario_name
var selected_session_type_id: String = "workshop_catalyst"
var selected_collection_id: String = "decision_triage"
var default_scenario_name = "karlsruhe_library_future_design"  # Default scenario
var _ai_all_chars_toggle: CheckButton = null
var _uses_custom_workshop_scenario: bool = false
var _uses_custom_story_scenario: bool = false
var _story_builder_instance: Control = null
# Guard to prevent signal handlers from fighting startup defaults
var _is_initializing: bool = true
#var current_scenario

func _select_scenario_in_dropdown(preferred_name: String) -> void:
	if scenario_option_button.get_item_count() <= 0:
		selected_scenario_name = ""
		return
	var pick_name := preferred_name
	var is_open_play: bool = (
		selected_session_type_id == "story_catalyst"
		and selected_collection_id == "open_play"
	)
	var leave_unset: bool = selected_session_type_id == "workshop_catalyst"
	if (pick_name == null or pick_name.is_empty()) and leave_unset:
		scenario_option_button.select(-1)
		selected_scenario_name = ""
		return
	# Open Play: empty preference means "Create new story", not the first library entry.
	if (pick_name == null or pick_name.is_empty()) and is_open_play:
		pick_name = OpenPlayModePopupHelpersScript.CREATE_NEW_SCENARIO_ID
	elif pick_name == null or pick_name.is_empty():
		# Ask the collection first: the fallback below is a workshop scenario, which no story
		# collection contains, so the search missed and landed on whichever was listed first.
		pick_name = Global.get_collection_default_scenario(selected_collection_id)
		if pick_name.is_empty():
			pick_name = default_scenario_name

	var idx := -1
	for i in range(scenario_option_button.get_item_count()):
		var meta: Variant = scenario_option_button.get_item_metadata(i)
		var item_id: String = str(meta) if typeof(meta) == TYPE_STRING else scenario_option_button.get_item_text(i)
		if item_id == pick_name or scenario_option_button.get_item_text(i) == pick_name:
			idx = i
			break

	if idx < 0:
		idx = 0
		var first_metadata: Variant = scenario_option_button.get_item_metadata(0)
		pick_name = (
			str(first_metadata)
			if typeof(first_metadata) == TYPE_STRING
			else scenario_option_button.get_item_text(0)
		)

	scenario_option_button.select(idx)
	selected_scenario_name = pick_name

func _apply_default_session_type_and_scenario() -> void:
	_is_initializing = true
	selected_session_type_id = "workshop_catalyst"
	selected_collection_id = "decision_triage"
	selected_scenario_name = ""
	_uses_custom_workshop_scenario = false
	setup_session_type_buttons()
	setup_collection_buttons()
	setup_scenario_buttons()
	Global.current_session_type = selected_session_type_id
	Global.current_collection_id = selected_collection_id
	scenario_option_button.select(-1)
	_render_no_scenario_selected_state()
	create_workshop_scenario_button.visible = true
	_open_workshop_scenario_editor()
	_is_initializing = false


## Overview/About/How To tabs before any Scenario is chosen or drafted. Kept
## deliberately free of "above"/"below" wording since this pane's position
## relative to the Scenario controls shifts with popup size and session type.
func _render_no_scenario_selected_state() -> void:
	scenario_label.text = (
		"[b]No Scenario selected yet.[/b]\n\n"
		+ "Use \"Create / describe Scenario\" to draft one, choose an authored "
		+ "template from the Scenario dropdown, or resume a previous session.\n\n"
		+ "[i]Multiplayer joiners receive the host Scenario automatically on "
		+ "Confirm — they do not need to draft one unless they intend to host.[/i]"
	)
	if about_label:
		about_label.text = (
			"[i]No Scenario selected yet. Background such as constraints, "
			+ "time horizon, and stakeholder perspectives will appear here "
			+ "once you draft or choose one.[/i]"
		)
	if how_to_label:
		how_to_label.text = (
			"[i]No Scenario selected yet. Desired outcomes and the Workshop "
			+ "agenda will appear here once you draft or choose one.[/i]"
		)

func _ready():
	# Initialize game_flow_manager FIRST
	game_flow_manager = Global.get_game_flow_manager()
	
	Network.connect("scenario_synced", refresh_scenario_display)
	Network.connect("server_scenario_updated", _on_server_scenario_updated)
#	Network.connect("sync_server_scenario", _on_server_scenario_updated)
	#if Network.has_signal("server_scenario_updated"):
		#Network.connect("server_scenario_updated", _on_server_scenario_updated)
	Network.connect("scenario_synced", _on_scenario_changed)
	Global.connect("scenario_changed", _on_scenario_changed)
	if get_viewport() and not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	multiplayer_checkbox.toggled.connect(_on_multiplayer_toggled)
	confirm_button.pressed.connect(_on_confirm_pressed)
	session_type_option_button.item_selected.connect(_on_session_type_selected)
	collection_option_button.item_selected.connect(_on_collection_selected)
	scenario_option_button.connect("item_selected", _on_scenario_selected)
	check_current_scenario_button.pressed.connect(_on_check_current_scenario_button_pressed)
	create_workshop_scenario_button.pressed.connect(_on_create_workshop_scenario_pressed)
	workshop_scenario_editor.connect("scenario_saved", _on_custom_workshop_scenario_saved)
	if create_story_scenario_button:
		create_story_scenario_button.pressed.connect(_on_create_story_scenario_pressed)
	if story_builder_close_button:
		story_builder_close_button.pressed.connect(_hide_story_builder_overlay)
	if story_builder_scrim:
		story_builder_scrim.gui_input.connect(_on_story_builder_scrim_gui_input)
	if my_sessions_button:
		my_sessions_button.pressed.connect(_on_my_sessions_button_pressed)
	if my_sessions_close_button:
		my_sessions_close_button.pressed.connect(_hide_my_sessions_dialog)
	if my_sessions_scrim:
		my_sessions_scrim.gui_input.connect(_on_my_sessions_scrim_gui_input)
	player_list.item_selected.connect(_on_player_slot_selected)
	ip_input.text = "127.0.0.1"
	selected_scenario_name = default_scenario_name
	
	# Deterministic startup selection: Workshop Catalyst, no scenario chosen yet.
	_apply_default_session_type_and_scenario()
	
	player_list.visible = false
	_update_session_label()

	_ai_all_chars_toggle = %AIAllCharactersToggle
	_ai_all_chars_toggle.toggled.connect(_on_ai_all_chars_toggled)
	_ai_all_chars_toggle.visible = false
	# Auto-enable when auto player input is active
	var pai = Global.get_player_auto_input() if Global and Global.has_method("get_player_auto_input") else null
	if pai:
		if pai.is_enabled():
			_ai_all_chars_toggle.button_pressed = true
		if not pai.auto_input_changed.is_connected(_on_pai_changed_for_ai_toggle):
			pai.auto_input_changed.connect(_on_pai_changed_for_ai_toggle)

	if not Network.is_connected("server_scenario_updated", _on_server_scenario_updated):
		Network.connect("server_scenario_updated", _on_server_scenario_updated)
		
	if not Global.is_connected("scenario_changed", _on_scenario_changed):
		Global.connect("scenario_changed", _on_scenario_changed)

func _on_viewport_size_changed() -> void:
	if story_builder_overlay and story_builder_overlay.visible:
		_fit_story_builder_overlay()
	elif visible:
		var popup_size: Vector2i = _compute_popup_size()
		_apply_popup_layout(popup_size)
		OpenPlayModePopupHelpersScript.place_centered(self, popup_size)

func _compute_popup_size() -> Vector2i:
	return OpenPlayModePopupHelpersScript.compute_mode_popup_size(
		get_tree(),
		max_size,
		_DEFAULT_POPUP_WIDTH,
		_DEFAULT_POPUP_HEIGHT,
		_MIN_POPUP_WIDTH,
		_MAX_POPUP_WIDTH,
		_MIN_POPUP_HEIGHT,
		_WIDTH_VIEWPORT_FRACTION,
		_VIEWPORT_MARGIN_X,
		_VIEWPORT_MARGIN_Y
	)

func _apply_popup_layout(popup_size: Vector2i) -> void:
	var popup_width: float = float(popup_size.x)
	var popup_height: float = float(popup_size.y)
	var content_width: float = maxf(0.0, popup_width - 56.0)
	if popup_content_container:
		popup_content_container.custom_minimum_size = Vector2(content_width, 0.0)
		popup_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if scenario_tab_container:
		var tab_height: float = clampf(popup_height * 0.42, _MIN_TAB_HEIGHT, _MAX_TAB_HEIGHT)
		scenario_tab_container.custom_minimum_size = Vector2(0.0, tab_height)
		scenario_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if popup_scroll_container:
		popup_scroll_container.scroll_vertical = 0
		popup_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func open_fitted() -> void:
	_apply_default_session_type_and_scenario()
	var popup_size: Vector2i = _compute_popup_size()
	_apply_popup_layout(popup_size)
	popup_centered(popup_size)
	call_deferred("_on_viewport_size_changed")

func _on_ai_all_chars_toggled(enabled: bool) -> void:
	if AICharacterAgent and AICharacterAgent.has_method("set_allow_ai_for_player_characters"):
		AICharacterAgent.set_allow_ai_for_player_characters(enabled)

func _on_pai_changed_for_ai_toggle(enabled: bool) -> void:
	if _ai_all_chars_toggle:
		_ai_all_chars_toggle.button_pressed = enabled

func _update_session_label() -> void:
	if not popup_label or not multiplayer_checkbox:
		return
	var is_multi: bool = multiplayer_checkbox.button_pressed
	popup_label.text = "Start Single Multi-Player Session" if is_multi else "Start Single Player Session"

func _on_multiplayer_toggled(button_pressed):
	player_list.visible = button_pressed
	_update_session_label()
	if button_pressed:
		_setup_player_list()
	else:
		player_list.clear()
		selected_players.clear()
	if selected_session_type_id == "workshop_catalyst" and workshop_scenario_editor.visible:
		_open_workshop_scenario_editor()
	_refresh_create_scenario_button_label()

#func setup_scenario_buttons():
	#for scenario in Global.get_scenario_names("story_catalyst", "sustainability"):
		#var check_button = CheckButton.new()
		#check_button.text = scenario
		#check_button.toggled.connect(_on_scenario_toggled.bind(scenario))
		#scenario_container.add_child(check_button)
		
#func setup_scenario_buttons():
	## Clear existing buttons first
	#for child in scenario_container.get_children():
		#child.queue_free()
#
	#var current_scenario = Global.get_current_scenario_metaprompt()
	#
	#if not Global.has_scenario_been_selected() or Network.is_server():
		#print("GLOBAL SCENARIO SELECTED? : ", str(Global.is_scenario_selected))
		#for scenario in Global.get_scenario_names("story_catalyst", "sustainability"):
			#var check_button = CheckButton.new()
			#check_button.text = scenario
			#check_button.toggled.connect(_on_scenario_toggled.bind(scenario))
			#scenario_container.add_child(check_button)
	#else:
		#var info_label = Label.new()
		#info_label.text = "Scenario selected by host: " + Global.get_current_scenario_metaprompt()
		#scenario_container.add_child(info_label)

#func setup_scenario_buttons():
	#for child in scenario_container.get_children():
		#child.queue_free()
#
	#if Global.get_current_scenario_metaprompt().is_empty():
		#print("GameModePopup: No scenario selected, showing options")
		## Show scenario options
		#for scenario in Global.get_scenario_names("story_catalyst", "sustainability"):
			#var check_button = CheckButton.new()
			#check_button.text = scenario
			#check_button.toggled.connect(_on_scenario_toggled.bind(scenario))
			#scenario_container.add_child(check_button)
	#else:
		#print("GameModePopup: Scenario already selected: ", Global.get_current_scenario_metaprompt())
		## Show selected scenario
		#var info_label = Label.new()
		#info_label.text = "Selected scenario: " + Global.get_current_scenario_metaprompt()
		#scenario_container.add_child(info_label)
	#
	#var info_label2 = Label.new()
	#var current_scenario = Global.get_game_flow_manager().get_current_scenario()
	#print("GameModePopup: Current scenario (name only): ", current_scenario.get("name", "No name"))
	#info_label2.text = "The Selected scenario: " + str(current_scenario)
	#scenario_container.add_child(info_label2)

#func setup_scenario_buttons():
	#for child in scenario_container.get_children():
		#child.queue_free()
#
	#if Network.is_multiplayer() or Network.is_server():
		#for scenario in Global.get_scenario_names("story_catalyst", "sustainability"):
			#var check_button = CheckButton.new()
			#check_button.text = scenario
			#check_button.toggled.connect(_on_scenario_toggled.bind(scenario))
			#scenario_container.add_child(check_button)
	#else:
		#var info_label = Label.new()
		#var current_scenario = Global.get_current_scenario()
		#if Network.current_scenario.is_empty():
			#info_label.text = "Waiting for host to select scenario..."
		#else:
			#info_label.text = "Selected scenario: " + Network.current_scenario.get("name", "Unknown")
		#scenario_container.add_child(info_label)

func setup_session_type_buttons() -> void:
	session_type_option_button.clear()
	session_type_option_button.add_item("Workshop Catalyst")
	session_type_option_button.set_item_metadata(0, "workshop_catalyst")
	session_type_option_button.add_item("Story Catalyst")
	session_type_option_button.set_item_metadata(1, "story_catalyst")
	session_type_option_button.select(
		1 if selected_session_type_id == "story_catalyst" else 0
	)
	session_type_option_button.disabled = false

func setup_collection_buttons() -> void:
	collection_option_button.clear()
	var collection_ids: Array[String] = Global.get_collection_ids(selected_session_type_id)
	for collection_id in collection_ids:
		var display_name: String = Global.get_collection_display_name(collection_id)
		collection_option_button.add_item(display_name)
		collection_option_button.set_item_metadata(
			collection_option_button.item_count - 1,
			collection_id
		)
	var selected_index: int = collection_ids.find(selected_collection_id)
	if selected_index < 0 and not collection_ids.is_empty():
		selected_index = 0
		selected_collection_id = collection_ids[0]
	if selected_index >= 0:
		collection_option_button.select(selected_index)
	collection_option_button.disabled = collection_ids.size() <= 1

func setup_scenario_buttons():
	scenario_option_button.clear()
	var is_open_play: bool = (
		selected_session_type_id == "story_catalyst"
		and selected_collection_id == "open_play"
	)
	if is_open_play:
		# Player-authored library (Finished drafts), newest first.
		OpenPlayModePopupHelpersScript.populate_scenario_dropdown(scenario_option_button)
	else:
		var scenario_names: Array[String] = Global.get_scenario_names(
			selected_session_type_id,
			selected_collection_id
		)
		var wip_set: Array[String] = Global.wip_scenarios if Global and "wip_scenarios" in Global else []
		for scenario_name in scenario_names:
			var label: String = str(scenario_name)
			if scenario_name in wip_set:
				label = "\u26a0 [WIP] " + scenario_name
			scenario_option_button.add_item(label)
			# Store the actual scenario name as item metadata so selection still works.
			scenario_option_button.set_item_metadata(scenario_option_button.item_count - 1, scenario_name)
	
	scenario_option_button.set_disabled(false)
	create_workshop_scenario_button.visible = selected_session_type_id == "workshop_catalyst"
	_refresh_story_create_button()
	if my_sessions_button:
		my_sessions_button.visible = selected_session_type_id == "workshop_catalyst"
	if _ai_all_chars_toggle:
		_ai_all_chars_toggle.visible = selected_session_type_id == "story_catalyst"


func refresh_scenario_display():
	_is_initializing = true
	setup_session_type_buttons()
	setup_collection_buttons()
	setup_scenario_buttons()
	# Keep dropdown + preview aligned after any refresh (e.g. Network scenario_synced).
	_select_scenario_in_dropdown(selected_scenario_name)
	if _uses_custom_workshop_scenario or _uses_custom_story_scenario:
		# Custom/library ids have no authored .txt — skip file reload.
		_is_initializing = false
		return
	Global.set_current_scenario_metaprompt(selected_scenario_name)
	update_scenario_display(selected_scenario_name)
	_is_initializing = false
			
func _on_session_type_selected(index: int) -> void:
	if _is_initializing:
		return
	selected_session_type_id = String(session_type_option_button.get_item_metadata(index))
	_is_initializing = true
	var collection_ids: Array[String] = Global.get_collection_ids(selected_session_type_id)
	selected_collection_id = collection_ids[0] if not collection_ids.is_empty() else ""
	setup_collection_buttons()
	setup_scenario_buttons()
	_uses_custom_workshop_scenario = false
	_uses_custom_story_scenario = false
	_hide_story_builder_overlay()
	if selected_session_type_id == "workshop_catalyst":
		selected_scenario_name = ""
		scenario_option_button.select(-1)
		_render_no_scenario_selected_state()
		_open_workshop_scenario_editor()
	else:
		_select_scenario_in_dropdown("")
		workshop_scenario_editor.visible = false
		if selected_collection_id == "open_play":
			_activate_open_play_collection_selection()
	_refresh_create_scenario_button_label()
	Global.current_session_type = selected_session_type_id
	Global.current_collection_id = selected_collection_id
	if (
		not selected_scenario_name.is_empty()
		and not (
			selected_session_type_id == "story_catalyst"
			and selected_collection_id == "open_play"
		)
	):
		Global.set_current_scenario_metaprompt(selected_scenario_name)
		update_scenario_display(selected_scenario_name)
	_is_initializing = false

func _on_collection_selected(index: int) -> void:
	if _is_initializing:
		return
	selected_collection_id = String(collection_option_button.get_item_metadata(index))
	_is_initializing = true
	_uses_custom_story_scenario = false
	_hide_story_builder_overlay()
	setup_scenario_buttons()
	_select_scenario_in_dropdown("")
	Global.current_session_type = selected_session_type_id
	Global.current_collection_id = selected_collection_id
	if selected_collection_id == "open_play":
		_activate_open_play_collection_selection()
	else:
		Global.set_current_scenario_metaprompt(selected_scenario_name)
		update_scenario_display(selected_scenario_name)
	_refresh_story_create_button()
	_is_initializing = false

func _on_scenario_selected(index):
	if _is_initializing:
		return
	# Use metadata (actual scenario id) rather than display text, which may have WIP prefix.
	# Open Play's create-new sentinel uses a non-empty metadata id — prefer metadata
	# whenever it is a String (including that sentinel).
	var meta: Variant = scenario_option_button.get_item_metadata(index)
	if typeof(meta) == TYPE_STRING:
		selected_scenario_name = str(meta)
	else:
		selected_scenario_name = scenario_option_button.get_item_text(index)
	_uses_custom_workshop_scenario = false
	_uses_custom_story_scenario = false
	workshop_scenario_editor.visible = false
	# Open Play library entries have no authored .txt — load from the saved JSON library.
	if (
		selected_session_type_id == "story_catalyst"
		and selected_collection_id == "open_play"
	):
		_load_open_play_scenario_selection(selected_scenario_name)
		return
	Global.set_current_scenario_metaprompt(selected_scenario_name)
	# If in multiplayer, sync this choice
	#if Network.is_multiplayer():
	if Network.is_server():
		Network.rpc("sync_selected_scenario", selected_scenario_name)
#	Global.emit_signal("scenario_changed", selected_scenario)
	update_scenario_display(selected_scenario_name)
	print("Scenario set in Network:", Network.get_server_scenario())
	# Note: update_scenario_buttons() is for old CheckButton system, not OptionButton dropdowns
	# Dropdown state is managed by setup_scenario_buttons() only

# Add a method to get the selected scenario
func get_selected_scenario() -> String:
	for child in scenario_container.get_children():
		if child is CheckButton and child.toggled:
			return child.text
	return "" # Return empty string if no scenario is selected
	
func _setup_player_list():
	player_list.clear()
	for i in range(4):
		player_list.add_item("Player " + str(i + 1))
	player_list.select(0)
	player_list.set_item_disabled(0, true)
	selected_players = [0]
	popup_label.text = "Start new multiplayer game session"

func _on_player_slot_selected(index):
	if index in selected_players:
		selected_players.erase(index)
		player_list.set_item_disabled(index, false)
	else:
		selected_players.append(index)
		player_list.set_item_disabled(index, true)
	
	if selected_players.size() == 4:
		popup_label.text = "All Players Assigned"
	else:
		popup_label.text = "Choose Player to Join Game"

#func _on_confirm_pressed():
	#var is_multiplayer = multiplayer_checkbox.button_pressed
	#selected_players.clear()
	#for i in range(player_list.get_item_count()):
		#if player_list.is_item_disabled(i):
			#selected_players.append(i)
			#
	#var selected_scenario = Global.get_current_scenario()
##	Global.set_current_scenario_metaprompt(scenario)
	#
	#if is_multiplayer:
		#print("Multiplayer mode selected")
		#var error = await Network.join_server("127.0.0.1", Network.DEFAULT_PORT)
		#if error != OK:
			#print("Failed to join server. Attempting to create one...")
			#error = Network.create_server()
			#if error != OK:
				#OS.alert("Failed to create or join server. Error code: " + str(error), "Network Error")
				#return
		## If this instance became the server, set and notify the scenario
##		if Network.is_server():
##			Global.set_current_scenario_metaprompt(selected_scenario)
##		Network.rpc("notify_scenario_loaded", selected_scenario)
	#else:
		#print("Single player mode selected")
		#Global.set_current_scenario_metaprompt(selected_scenario)
	#
	#print("Emitting mode_selected signal")
	#emit_signal("mode_selected", is_multiplayer, selected_players)
	#hide()
	#print("Game mode selection complete")

#func _on_confirm_pressed():
	#var is_multiplayer = multiplayer_checkbox.button_pressed
	#selected_players.clear()
	#for i in range(player_list.get_item_count()):
		#if player_list.is_item_disabled(i):
			#selected_players.append(i)
	#
	#var selected_scenario_name = get_selected_scenario()
	#var selected_scenario = Global.get_current_scenario()
	#Global.emit_signal("scenario_changed", selected_scenario)
	#
	#if is_multiplayer:
		#print("Multiplayer mode selected")
		#var error = await Network.join_server("127.0.0.1", Network.DEFAULT_PORT)
		#if error != OK:
			#print("Failed to join server. Attempting to create one...")
			#error = Network.create_server()
			#if error != OK:
				#OS.alert("Failed to create or join server. Error code: " + str(error), "Network Error")
				#return
	#else:
		#print("Single player mode selected")
		#Global.set_current_scenario_metaprompt(selected_scenario_name)
	#
	#print("Emitting mode_selected signal")
	#emit_signal("mode_selected", is_multiplayer, selected_players)
	#hide()
	#print("Game mode selection complete")

func _on_confirm_pressed():
	var is_multiplayer = multiplayer_checkbox.button_pressed
	selected_players.clear()
	for i in range(player_list.get_item_count()):
		if player_list.is_item_disabled(i):
			selected_players.append(i)

	var is_workshop: bool = selected_session_type_id == "workshop_catalyst"
	var is_open_play: bool = (
		selected_session_type_id == "story_catalyst"
		and selected_collection_id == "open_play"
	)
	# Multiplayer clients join the host's Scenario — they do not need a local
	# selection (especially for custom drafts that only exist on the host).
	var allow_join_without_local_scenario: bool = (
		is_multiplayer and (is_workshop or is_open_play)
	)

	var current_scenario_name = Global.get_current_scenario_metaprompt()
	var has_local_scenario: bool = (
		_uses_custom_workshop_scenario
		or _uses_custom_story_scenario
		or (current_scenario_name != null and String(current_scenario_name).strip_edges() != "")
	)
	if (
		current_scenario_name
		and not _uses_custom_workshop_scenario
		and not _uses_custom_story_scenario
	):
		update_scenario_display(current_scenario_name)
	elif not has_local_scenario and not allow_join_without_local_scenario:
		scenario_label.text = "[color=red]Create or select a Scenario before starting.[/color]"
		return

	var joined_as_client: bool = false
	if is_multiplayer:
		print("Multiplayer mode selected")
		var error = await Network.join_server("127.0.0.1", Network.DEFAULT_PORT)
		if error != OK:
			print("Failed to join server. Attempting to create one...")
			error = Network.create_server()
			if error != OK:
				OS.alert("Failed to create or join server. Error code: " + str(error), "Network Error")
				return

		if Network.is_server():
			if not has_local_scenario:
				scenario_label.text = "[color=red]Create or select a Scenario before hosting.[/color]"
				return
			if (
				selected_scenario_name
				and not _uses_custom_workshop_scenario
				and not _uses_custom_story_scenario
			):
				Global.set_current_scenario_metaprompt(selected_scenario_name)
				Network.rpc("sync_selected_scenario", selected_scenario_name)
			elif _uses_custom_workshop_scenario or _uses_custom_story_scenario:
				var host_scenario: Dictionary = Global.get_current_scenario()
				Network.set_server_scenario(host_scenario)
				Network.rpc("sync_server_scenario", host_scenario)
		else:
			joined_as_client = true
			# Prefer full-dict sync so custom drafts travel with the host.
			Network.rpc_id(1, "request_scenario_sync")
			var received: bool = await _await_server_scenario(6.0)
			if not received or Network.get_server_scenario().is_empty():
				OS.alert(
					"Could not receive the host Scenario. Confirm the first instance is hosting, then try again.",
					"Scenario Sync"
				)
				return
	else:
		print("Single player mode selected")
		if (
			selected_scenario_name
			and not _uses_custom_workshop_scenario
			and not _uses_custom_story_scenario
		):
			Global.set_current_scenario_metaprompt(selected_scenario_name)

	if joined_as_client:
		var server_scenario: Dictionary = Network.get_server_scenario()
		game_flow_manager.set_current_scenario(server_scenario)
	else:
		if not _uses_custom_workshop_scenario and not _uses_custom_story_scenario:
			scenario_loader.load_scenario(
				selected_scenario_name,
				selected_session_type_id,
				selected_collection_id
			)
		var working_scenario: Dictionary = Global.get_current_scenario()
		if not _uses_custom_workshop_scenario and not _uses_custom_story_scenario:
			working_scenario = scenario_loader.get_current_scenario()
		game_flow_manager.set_current_scenario(working_scenario)

	print("Emitting mode_selected signal")
	emit_signal("mode_selected", is_multiplayer, selected_players)
	hide()
	print("Game mode selection complete")


func _await_server_scenario(timeout_sec: float) -> bool:
	if not Network.get_server_scenario().is_empty():
		return true
	var remaining: float = timeout_sec
	while remaining > 0.0:
		if Network.get_server_scenario().is_empty() == false:
			return true
		await get_tree().create_timer(0.1).timeout
		remaining -= 0.1
	return not Network.get_server_scenario().is_empty()
	
#func _on_server_scenario_updated(scenario: Dictionary):
	#update_scenario_display(scenario)
	#Global.emit_signal("scenario_changed", scenario.get("name", "Unknown"))
	#Global.get_game_flow_manager().set_current_scenario(scenario)

func _on_server_scenario_updated():
	var scenario = Network.get_server_scenario()
	if selected_scenario_name == null or selected_scenario_name.is_empty():
		selected_scenario_name = default_scenario_name
		print("No scenario selected, default scenario assigned")
	#	OS.alert("Default scenario assigned.", "No scenario selected.")
		return
	update_scenario_display(selected_scenario_name)
	update_scenario_buttons()
	Global.emit_signal("scenario_changed", scenario.get("name", "Unknown"))
	Global.get_game_flow_manager().set_current_scenario(scenario)

func load_scenario(scenario_name):
	scenario_loader.load_scenario(
		scenario_name,
		selected_session_type_id,
		selected_collection_id
	)
	var full_scenario = scenario_loader.get_current_scenario()
	return full_scenario
		
func update_scenario_display(scenario_display_name: String):
	# Ensure the dropdown UI matches the scenario being previewed.
	_is_initializing = true
	_select_scenario_in_dropdown(scenario_display_name)
	_is_initializing = false
	var loaded_scenario = load_scenario(scenario_display_name)
	print("THE NEW SCENARIO IS: ", str(loaded_scenario))
	scenario_label.text = "Selected scenario: " + "\n" + "[font_size=16][b]" + loaded_scenario.get("name", "Unknown") + "[/b][/font_size]" + "\n\n"
	scenario_label.text += "Objective: " + "\n" + loaded_scenario.get("objective", "No objective set")
	
	# Update About and How To tabs if content exists
	if about_label:
		var about_text = loaded_scenario.get("about_text", "").strip_edges()
		if about_text.is_empty():
			about_label.text = "[i]No additional information available for this scenario.[/i]"
		else:
			about_label.text = about_text
	
	if how_to_label:
		var how_to_text = loaded_scenario.get("how_to_text", "").strip_edges()
		if how_to_text.is_empty():
			how_to_label.text = "[i]No how-to guidance available for this scenario.[/i]"
		else:
			how_to_label.text = how_to_text

func update_scenario_buttons():
	# DEPRECATED: This function was for the old CheckButton-based scenario selection system.
	# The current system uses OptionButton dropdowns managed by setup_scenario_buttons().
	# Kept for backward compatibility with any multiplayer Network calls, but does nothing now.
	pass


func _on_create_workshop_scenario_pressed() -> void:
	_open_workshop_scenario_editor()


func _on_create_story_scenario_pressed() -> void:
	# Shift+click or dropdown on "Create new" avoids library name/id bleed.
	var selected_id: String = (
		String(selected_scenario_name) if selected_scenario_name != null else ""
	)
	if (
		Input.is_key_pressed(KEY_SHIFT)
		or OpenPlayModePopupHelpersScript.is_create_new_id(selected_id)
	):
		_prepare_open_play_create_new()
	_open_story_builder_overlay()


func _render_open_play_empty_state() -> void:
	OpenPlayModePopupHelpersScript.render_empty_state(scenario_label, about_label, how_to_label)


func _prepare_open_play_create_new() -> void:
	_uses_custom_story_scenario = false
	_uses_custom_workshop_scenario = false
	selected_scenario_name = OpenPlayModePopupHelpersScript.CREATE_NEW_SCENARIO_ID
	if scenario_option_button and scenario_option_button.get_item_count() > 0:
		scenario_option_button.select(0)
	OpenPlayModePopupHelpersScript.clear_global_story_session(Global)
	_render_open_play_empty_state()
	_refresh_story_create_button()


func _activate_open_play_collection_selection() -> void:
	## Default to "Create new story" — never auto-pick a library entry.
	if scenario_option_button.get_item_count() <= 0:
		selected_scenario_name = ""
		_uses_custom_story_scenario = false
		_render_open_play_empty_state()
		_refresh_story_create_button()
		return
	_prepare_open_play_create_new()


func _load_open_play_scenario_selection(scenario_id: String) -> void:
	if OpenPlayModePopupHelpersScript.is_create_new_id(scenario_id):
		_prepare_open_play_create_new()
		return
	var result: Dictionary = OpenPlayModePopupHelpersScript.load_saved_into_session(scenario_id)
	if not bool(result.get("ok", false)):
		_uses_custom_story_scenario = false
		scenario_label.text = String(result.get("error_text", ""))
		return
	var loaded: Dictionary = result.get("scenario", {}) as Dictionary
	_uses_custom_story_scenario = true
	_uses_custom_workshop_scenario = false
	selected_scenario_name = String(loaded.get("id", scenario_id))
	selected_session_type_id = "story_catalyst"
	selected_collection_id = "open_play"
	_render_story_tabs_for_draft(loaded)
	_refresh_story_create_button()
	if Network.is_server():
		Network.set_server_scenario(loaded)
		Network.rpc("sync_server_scenario", loaded)


func _fit_story_builder_overlay() -> void:
	if not story_builder_card:
		return
	var window_size: Vector2i = OpenPlayModePopupHelpersScript.compute_story_builder_popup_size(
		get_tree(),
		max_size,
		_STORY_BUILDER_MARGIN_X,
		_STORY_BUILDER_MARGIN_Y,
		_STORY_BUILDER_MIN_WIDTH,
		_STORY_BUILDER_MIN_HEIGHT,
		_STORY_BUILDER_MAX_WIDTH,
		_STORY_BUILDER_MAX_HEIGHT
	)
	OpenPlayModePopupHelpersScript.place_centered(self, window_size)
	story_builder_card.custom_minimum_size = Vector2(
		maxf(200.0, float(window_size.x) - 24.0),
		maxf(200.0, float(window_size.y) - 24.0)
	)
	if _story_builder_instance and is_instance_valid(_story_builder_instance):
		_story_builder_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_story_builder_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _open_story_builder_overlay() -> void:
	if not story_builder_overlay or not story_builder_host:
		return
	if _story_builder_instance and is_instance_valid(_story_builder_instance):
		_story_builder_instance.queue_free()
		_story_builder_instance = null
	_story_builder_instance = OpenPlayModePopupHelpersScript.mount_story_builder(
		story_builder_host,
		ScenarioBuilderScene,
		_uses_custom_story_scenario,
		String(selected_scenario_name) if selected_scenario_name != null else "",
		Callable(self, "_on_custom_story_scenario_saved"),
		Callable(self, "_hide_story_builder_overlay")
	)
	if _story_builder_instance == null:
		return
	_fit_story_builder_overlay()
	story_builder_overlay.visible = true
	OpenPlayModePopupHelpersScript.fit_control_overlay(story_builder_overlay)
	for _frame_index in range(2):
		await get_tree().process_frame
		if not story_builder_overlay or not story_builder_overlay.visible:
			return
		_fit_story_builder_overlay()


func _hide_story_builder_overlay() -> void:
	if story_builder_overlay:
		story_builder_overlay.visible = false
	if _story_builder_instance and is_instance_valid(_story_builder_instance):
		_story_builder_instance.queue_free()
		_story_builder_instance = null
	if visible:
		var popup_size: Vector2i = _compute_popup_size()
		_apply_popup_layout(popup_size)
		OpenPlayModePopupHelpersScript.place_centered(self, popup_size)


func _on_story_builder_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_story_builder_overlay()


func _on_custom_story_scenario_saved(scenario: Dictionary) -> void:
	_uses_custom_story_scenario = true
	_uses_custom_workshop_scenario = false
	if not Global.set_custom_story_scenario(scenario):
		_uses_custom_story_scenario = false
		scenario_label.text = "[color=red]The Open Play story draft could not be loaded.[/color]"
		return
	selected_scenario_name = String(scenario.get("id", "custom_open_play_scenario"))
	selected_session_type_id = "story_catalyst"
	selected_collection_id = "open_play"
	# Refresh dropdown so the just-finished story is selectable, then select it.
	_is_initializing = true
	setup_scenario_buttons()
	_select_scenario_in_dropdown(selected_scenario_name)
	_is_initializing = false
	_render_story_tabs_for_draft(scenario)
	_hide_story_builder_overlay()
	_refresh_story_create_button()


func _render_story_tabs_for_draft(scenario: Dictionary) -> void:
	var is_multiplayer_host_note: bool = (
		multiplayer_checkbox != null and multiplayer_checkbox.button_pressed
	)
	OpenPlayModePopupHelpersScript.render_story_tabs(
		scenario,
		scenario_label,
		about_label,
		how_to_label,
		is_multiplayer_host_note
	)


func _refresh_story_create_button() -> void:
	var is_open_play: bool = (
		selected_session_type_id == "story_catalyst"
		and selected_collection_id == "open_play"
	)
	OpenPlayModePopupHelpersScript.refresh_create_button(
		create_story_scenario_button,
		is_open_play,
		_uses_custom_story_scenario,
		String(selected_scenario_name) if selected_scenario_name != null else "",
		_network_server_scenario()
	)


func _on_my_sessions_button_pressed() -> void:
	if not my_sessions_dialog or not my_sessions_list_container or not my_sessions_empty_state:
		return
	for child_node: Node in my_sessions_list_container.get_children():
		child_node.queue_free()
	var sessions: Array[Dictionary] = WorkshopSessionScannerScript.scan_workshop_catalyst_sessions()
	my_sessions_empty_state.visible = sessions.is_empty()
	for session_entry: Dictionary in sessions:
		var session_button_node: Button = WorkshopMySessionListItemScene.instantiate() as Button
		session_button_node.text = WorkshopSessionScannerScript.format_session_label(session_entry)
		session_button_node.pressed.connect(_on_my_session_selected.bind(session_entry))
		my_sessions_list_container.add_child(session_button_node)
	# Control overlay (not Window): inherits GameModePopup's theme cascade and
	# keeps reliable contrast via the card StyleBox — same lesson as the
	# Facilitator dialog fix. Avoid nested Window theming.
	my_sessions_dialog.visible = true
	OpenPlayModePopupHelpersScript.fit_control_overlay(my_sessions_dialog)


func _hide_my_sessions_dialog() -> void:
	if my_sessions_dialog:
		my_sessions_dialog.visible = false


func _on_my_sessions_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_my_sessions_dialog()


func _on_my_session_selected(session_entry: Dictionary) -> void:
	var json_path: String = String(session_entry.get("json_path", "")).strip_edges()
	if json_path.is_empty():
		return
	_hide_my_sessions_dialog()
	# Resuming replaces whatever Scenario is loaded once the story log applies,
	# but Confirm still validates a Scenario is present, so seed a placeholder
	# that passes that check without implying a real draft was authored here.
	selected_session_type_id = "workshop_catalyst"
	session_type_option_button.select(0)
	Global.set_custom_workshop_scenario(WorkshopScenarioContractScript.create_custom({
		"title": "Resumed session",
		"objective": "Resumed from a previously saved story log.",
		"context": "Loaded from: " + String(session_entry.get("file_stem", json_path)),
	}))
	_uses_custom_workshop_scenario = true
	selected_scenario_name = "custom_workshop_scenario"
	workshop_scenario_editor.visible = false
	scenario_label.text = (
		"[b]Resuming previous session:[/b] %s\n\n"
		+ "[i]The saved story log will load once the session starts.[/i]"
	) % WorkshopSessionScannerScript.format_session_label(session_entry)
	Global.set_pending_workshop_resume_path(json_path)
	_on_confirm_pressed()


func _on_custom_workshop_scenario_saved(scenario: Dictionary) -> void:
	_uses_custom_workshop_scenario = true
	if not Global.set_custom_workshop_scenario(scenario):
		_uses_custom_workshop_scenario = false
		scenario_label.text = "[color=red]The local Scenario draft could not be loaded.[/color]"
		return
	selected_scenario_name = String(scenario.get("id", "custom_workshop_scenario"))
	_render_scenario_tabs_for_draft(scenario)
	workshop_scenario_editor.visible = false
	_refresh_create_scenario_button_label()


## Populates Overview/About/How To for a custom draft immediately after it is
## used, so those tabs reflect the actual Scenario instead of stale
## design-time placeholder copy ("About information will appear here").
func _render_scenario_tabs_for_draft(scenario: Dictionary) -> void:
	var packet_any: Variant = scenario.get("workshop_packet", {})
	var packet: Dictionary = packet_any if typeof(packet_any) == TYPE_DICTIONARY else {}
	var multiplayer_note: String = ""
	if multiplayer_checkbox and multiplayer_checkbox.button_pressed:
		multiplayer_note = (
			"\n\n[i]Hosting will sync this Scenario to joining instances on Confirm.[/i]"
		)
	scenario_label.text = (
		"[b]Scenario draft in use:[/b] %s\n\nObjective: %s\n\n"
		+ "[i]Local draft only — not published or committed.[/i]"
		+ multiplayer_note
	) % [
		String(scenario.get("name", "Untitled Scenario")),
		String(scenario.get("objective", "")),
	]
	if about_label:
		var about_parts: Array[String] = []
		var time_horizon: String = String(packet.get("time_horizon", "")).strip_edges()
		if not time_horizon.is_empty():
			about_parts.append("[b]Time horizon:[/b] " + time_horizon)
		var constraints_text: String = _bullet_list(packet.get("constraints", []))
		if not constraints_text.is_empty():
			about_parts.append("[b]Constraints:[/b]\n" + constraints_text)
		var perspectives_text: String = _bullet_list(packet.get("relevant_perspectives", []))
		if not perspectives_text.is_empty():
			about_parts.append("[b]Perspectives:[/b]\n" + perspectives_text)
		var evidence_text: String = String(packet.get("evidence_notes", "")).strip_edges()
		if not evidence_text.is_empty():
			about_parts.append("[b]Evidence notes:[/b] " + evidence_text)
		about_label.text = (
			"\n\n".join(about_parts) if not about_parts.is_empty()
			else "[i]No additional background was added for this draft.[/i]"
		)
	if how_to_label:
		var how_parts: Array[String] = []
		var outcomes_text: String = _bullet_list(packet.get("desired_outcomes", []))
		if not outcomes_text.is_empty():
			how_parts.append("[b]Desired outcomes:[/b]\n" + outcomes_text)
		var agenda_lines: Array[String] = []
		for stage_entry: Dictionary in WorkshopScenarioContractScript.DEFAULT_AGENDA:
			agenda_lines.append(String(stage_entry.get("name", "")))
		how_parts.append("[b]Workshop agenda:[/b]\n" + _bullet_list(agenda_lines))
		how_to_label.text = "\n\n".join(how_parts)


func _bullet_list(values_any: Variant) -> String:
	if typeof(values_any) != TYPE_ARRAY:
		return ""
	var lines: Array[String] = []
	for value_any: Variant in (values_any as Array):
		var value_text: String = String(value_any).strip_edges()
		if not value_text.is_empty():
			lines.append("- " + value_text)
	return "\n".join(lines)


func _open_workshop_scenario_editor() -> void:
	var show_join_hint: bool = (
		multiplayer_checkbox != null and multiplayer_checkbox.button_pressed
	)
	var host_scenario: Dictionary = _network_server_scenario()
	if not host_scenario.is_empty() and _looks_like_workshop_scenario(host_scenario):
		workshop_scenario_editor.call(
			"open_editor", host_scenario, "host_synced", show_join_hint
		)
		_refresh_create_scenario_button_label()
		return
	var current: Dictionary = {}
	var global_node: Node = _autoload_node("Global")
	if global_node and global_node.has_method("get_current_scenario"):
		current = global_node.call("get_current_scenario") as Dictionary
	if _uses_custom_workshop_scenario and not current.is_empty():
		workshop_scenario_editor.call("open_editor", current, "session", show_join_hint)
		_refresh_create_scenario_button_label()
		return
	workshop_scenario_editor.call("open_editor", {}, "", show_join_hint)
	_refresh_create_scenario_button_label()


func _looks_like_workshop_scenario(scenario: Dictionary) -> bool:
	if scenario.is_empty():
		return false
	return (
		scenario.has("workshop_packet")
		or String(scenario.get("id", "")) == "custom_workshop_scenario"
		or String(scenario.get("_session_type_id", "")) == "workshop_catalyst"
	)


func _refresh_create_scenario_button_label() -> void:
	if my_sessions_button:
		my_sessions_button.visible = selected_session_type_id == "workshop_catalyst"
	_refresh_story_create_button()
	if not create_workshop_scenario_button:
		return
	if selected_session_type_id != "workshop_catalyst":
		create_workshop_scenario_button.visible = false
		return
	create_workshop_scenario_button.visible = true
	var local_draft: Dictionary = WorkshopScenarioContractScript.load_local_draft()
	var has_host: bool = _looks_like_workshop_scenario(_network_server_scenario())
	if has_host:
		create_workshop_scenario_button.text = "Review host Scenario"
	elif not local_draft.is_empty() or _uses_custom_workshop_scenario:
		create_workshop_scenario_button.text = "Review Scenario draft"
	else:
		create_workshop_scenario_button.text = "Create / describe Scenario"


func _network_server_scenario() -> Dictionary:
	var network_node: Node = _autoload_node("Network")
	if network_node == null or not network_node.has_method("get_server_scenario"):
		return {}
	var scenario_any: Variant = network_node.call("get_server_scenario")
	if typeof(scenario_any) != TYPE_DICTIONARY:
		return {}
	return scenario_any as Dictionary


func _autoload_node(autoload_name: String) -> Node:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null(autoload_name)


func _on_scenario_changed(new_scenario: String):
	if _is_initializing:
		return
	if _uses_custom_workshop_scenario and new_scenario == "custom_workshop_scenario":
		return
	if (
		_uses_custom_story_scenario
		and (
			new_scenario == StoryScenarioContractScript.CUSTOM_SCENARIO_ID
			or StoryScenarioContractScript.is_library_id(new_scenario)
		)
	):
		return
	_is_initializing = true
	setup_scenario_buttons()
	_select_scenario_in_dropdown(new_scenario)
	_is_initializing = false
	update_scenario_display(new_scenario)
	_refresh_create_scenario_button_label()
	
func _on_check_current_scenario_button_pressed():
	print("GameModePopup: Current metaprompt scenario: ", str(Global.get_current_scenario_metaprompt()))
	var current_scenario_name = Global.get_current_scenario_metaprompt()
	print("CURRENT SCENARIO NAME:", current_scenario_name)
