extends SceneTree

const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)

var _failures: Array[String] = []
var _global_node: Node = null


class FakeGlobalNode extends Node:
	var current_character: Dictionary = {}
	var selected_characters: Array = [{"name": "Existing stakeholder"}]

	func set_current_character(character_data: Dictionary) -> void:
		current_character = character_data.duplicate(true)

	func set_selected_characters(character_data: Array) -> void:
		selected_characters = character_data.duplicate(true)


class FakeStoryStateNode extends Node:
	var state: Dictionary = {
		"workshop_catalyst": {
			"existing_setting": "preserved",
			"send_as_facilitator": false,
		}
	}

	func get_state() -> Dictionary:
		return state

	func set_state(next_state: Dictionary) -> void:
		state = next_state.duplicate(true)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_global_node = root.get_node_or_null("Global")
	if _global_node == null:
		_failures.append("Global autoload was unavailable")
		_finish()
		return
	_test_explicit_routing()
	_test_route_wiring()
	_test_facilitator_sender_identity()
	_test_display_identity()
	await _test_workshop_scene_entry()
	_finish()


func _test_explicit_routing() -> void:
	_expect(
		FacilitatorSessionSetupScript.should_bypass_character_selection(
			"workshop_catalyst"
		),
		"Workshop Catalyst did not request a character-selection bypass"
	)
	_expect(
		not FacilitatorSessionSetupScript.should_bypass_character_selection(
			"story_catalyst"
		),
		"Story Catalyst requested a character-selection bypass"
	)
	_expect(
		FacilitatorSessionSetupScript.entry_scene_path(
			"workshop_catalyst"
		) == "res://ScenSyn/scenes/game_session.tscn"
		and FacilitatorSessionSetupScript.entry_scene_path(
			"story_catalyst"
		) == "res://ScenSyn/scenes/character_options.tscn",
		"Session Type entry routing does not skip the Workshop character scene"
	)
	_expect(
		FacilitatorSessionSetupScript.is_facilitator_sender("Facilitator")
		and FacilitatorSessionSetupScript.is_facilitator_sender("Alex (Facilitator)")
		and not FacilitatorSessionSetupScript.is_facilitator_sender(
			"Story Stakeholder"
		),
		"Facilitator sender identity was not isolated"
	)


func _test_route_wiring() -> void:
	var route_paths: Array[String] = [
		"res://ScenSyn/scripts/character_options.gd",
		"res://ScenSyn/scripts/character_options_2.gd",
	]
	for route_path in route_paths:
		var route_script: GDScript = load(route_path) as GDScript
		_expect(route_script != null, "Route script did not parse: " + route_path)
		if route_script != null:
			_expect(
				route_script.call(
					"should_bypass_character_selection",
					"workshop_catalyst"
				) == true
				and route_script.call(
					"should_bypass_character_selection",
					"story_catalyst"
				) == false,
				"Route guard behavior changed: " + route_path
			)
		var route_file: FileAccess = FileAccess.open(route_path, FileAccess.READ)
		_expect(route_file != null, "Could not inspect route: " + route_path)
		if route_file == null:
			continue
		var route_source: String = route_file.get_as_text()
		route_file.close()
		_expect(
			route_source.contains(
				"FacilitatorSessionSetupScript.should_bypass_character_selection"
			),
			"Route does not use the explicit Workshop bypass: " + route_path
		)
		_expect(
			route_source.contains("_enter_workshop_facilitator_session"),
			"Route does not enter the facilitator session: " + route_path
		)
	_expect(
		FileAccess.get_file_as_string(
			"res://ScenSyn/scenes/game_session.tscn"
		).contains("unique_name_in_owner = true"),
		"Game session scene does not expose CharacterLabel as a unique node"
	)
	var main_menu_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/main_menu.gd"
	)
	_expect(
		main_menu_source.contains(
			"FacilitatorSessionSetupScript.entry_scene_path"
		),
		"Main menu does not route Workshop directly to the game session"
	)


func _test_facilitator_sender_identity() -> void:
	var fake_global_node := FakeGlobalNode.new()
	var fake_story_state_node := FakeStoryStateNode.new()
	var facilitator_identity: Dictionary = FacilitatorSessionSetupScript.apply(
		fake_global_node,
		fake_story_state_node
	)
	_expect(
		facilitator_identity.get("name", "") == "Facilitator"
		and facilitator_identity.get("is_player", false) == true
		and facilitator_identity.get("is_ai", true) == false,
		"Facilitator identity was not configured as the human participant"
	)
	_expect(
		fake_global_node.current_character.get("name", "") == "Facilitator",
		"Global human identity was not set to Facilitator"
	)
	_expect(
		fake_global_node.selected_characters.is_empty(),
		"Workshop setup retained character-card selections"
	)
	var workshop_state: Dictionary = fake_story_state_node.state.get("workshop_catalyst", {})
	_expect(
		workshop_state.get("send_as_facilitator", false) == true,
		"Existing send_as_facilitator behavior was not enabled"
	)
	_expect(
		workshop_state.get("existing_setting", "") == "preserved",
		"Workshop setup discarded existing Workshop Catalyst state"
	)


func _test_display_identity() -> void:
	_expect(
		FacilitatorSessionSetupScript.character_label_text(
			"workshop_catalyst",
			{"name": "Stale stakeholder"}
		) == "Facilitator",
		"Workshop CharacterLabel did not display Facilitator"
	)
	_expect(
		FacilitatorSessionSetupScript.character_label_text(
			"story_catalyst",
			{"name": "Story Stakeholder"}
		) == "You are playing as: Story Stakeholder",
		"Story Catalyst CharacterLabel behavior changed"
	)


func _test_workshop_scene_entry() -> void:
	_global_node.set("current_session_type", "workshop_catalyst")
	_global_node.call(
		"set_current_scenario_metaprompt",
		"karlsruhe_library_future_design"
	)
	FacilitatorSessionSetupScript.apply(_global_node, root.get_node_or_null("StoryState"))
	var workshop_entry_path: String = (
		FacilitatorSessionSetupScript.entry_scene_path("workshop_catalyst")
	)
	_expect(
		workshop_entry_path != "res://ScenSyn/scenes/character_options.tscn"
		and workshop_entry_path != "res://ScenSyn/scenes/character_selection.tscn",
		"Workshop entry still routes through a character scene"
	)
	var scene_result: Error = change_scene_to_file(
		workshop_entry_path
	)
	_expect(scene_result == OK, "Could not enter the Workshop game session directly")
	if scene_result != OK:
		return
	await process_frame
	await create_timer(1.5).timeout
	var active_scene: Node = current_scene
	_expect(active_scene != null, "Workshop entry left no active scene")
	if active_scene == null:
		return
	_expect(
		active_scene.scene_file_path == "res://ScenSyn/scenes/game_session.tscn",
		"Workshop entry still required the character-options scene"
	)
	var character_label_node: Label = active_scene.find_child(
		"CharacterLabel",
		true,
		false
	) as Label
	_expect(
		character_label_node != null
		and character_label_node.text == "Facilitator",
		"Entered Workshop session did not show Facilitator in CharacterLabel"
	)
	var current_identity: Dictionary = _global_node.call("get_current_character")
	_expect(
		current_identity.get("name", "") == "Facilitator",
		"Entered Workshop session did not retain Facilitator identity"
	)
	var story_state_node: Node = root.get_node_or_null("StoryState")
	var story_entries: Array = story_state_node.call("get_state").get(
		"story_log",
		[]
	)
	var welcome_entry: Dictionary = (
		story_entries[0] if not story_entries.is_empty() else {}
	)
	_expect(
		welcome_entry.get("sender", "") == "Workshop Catalyst"
		and not str(welcome_entry.get("message", "")).contains(
			"The story begins now"
		),
		"Workshop entry retained the oversized Story Catalyst welcome"
	)
	var story_log_system_node: Control = active_scene.find_child(
		"StoryLogSystem",
		true,
		false
	) as Control
	var legacy_tabs_node: TabContainer = active_scene.get_node_or_null(
		"%TabContainer"
	) as TabContainer
	_expect(
		story_log_system_node != null
		and story_log_system_node.get_parent().name == "ConversationContentSlot"
		and legacy_tabs_node != null
		and not legacy_tabs_node.visible,
		"Workshop exposed the legacy StoryLog/About/How To tab surface"
	)
	var message_box_node: VBoxContainer = (
		story_log_system_node.get_node_or_null("%VBoxContainer")
		as VBoxContainer
	)
	var welcome_card_node: Control = null
	if message_box_node != null and message_box_node.get_child_count() > 0:
		welcome_card_node = message_box_node.get_child(
			message_box_node.get_child_count() - 1
		) as Control
	_expect(
		welcome_card_node != null
		and (
			welcome_card_node.size_flags_vertical
			& Control.SIZE_EXPAND
		) == 0,
		"Workshop welcome card still expands over adjacent controls"
	)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop facilitator entry tests: all passed")
		quit(0)
		return
	for failure_message in _failures:
		push_error(failure_message)
	quit(1)
