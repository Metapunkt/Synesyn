extends SceneTree

const PresetModelScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_preset_model.gd"
)
const WorkspaceControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)
const UiTokensScript = preload(
	"res://ScenSyn/scripts/core/synesyn_ui_tokens.gd"
)

var _failures: Array[String] = []
var _end_save_requests: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pure_preset_model()
	await _test_scene_controller_and_safety()
	_test_module_boundaries()
	_finish()


func _test_pure_preset_model() -> void:
	var expected_by_preset: Dictionary = {
		"talk": [
			"conversation", "ai_assistant", "session_record",
			"participants", "session_menu",
		],
		"map": [
			"thinking_map", "ai_assistant", "session_record",
			"participants", "session_menu",
		],
		"review": ["session_record", "participants", "session_menu"],
		"full_dashboard": PresetModelScript.GROUP_IDS,
	}
	for preset_id: String in expected_by_preset:
		var visibility_map: Dictionary = PresetModelScript.visibility_for_preset(preset_id, {})
		var expected_groups: Array = expected_by_preset[preset_id]
		for group_id: String in PresetModelScript.GROUP_IDS:
			_expect(
				visibility_map.get(group_id, false) == (group_id in expected_groups),
				"Preset %s has incorrect visibility for %s" % [preset_id, group_id]
			)
	var custom_visibility: Dictionary = PresetModelScript.with_manual_toggle(
		PresetModelScript.visibility_for_preset("talk", {}),
		"session_menu",
		true
	)
	_expect(custom_visibility.get("session_menu", false), "Custom toggle was not retained")
	_expect(
		not custom_visibility.get("thinking_map", true),
		"Custom toggle unexpectedly changed another group"
	)


func _test_scene_controller_and_safety() -> void:
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	_expect(
		not shell_node.visible,
		"Workshop shell is visible before its layout owner mounts it"
	)
	var conversation_region_node := TabContainer.new()
	conversation_region_node.custom_minimum_size = Vector2(750, 500)
	var story_tab_node := VBoxContainer.new()
	story_tab_node.name = "StoryLog"
	var chat_scene: PackedScene = load("res://ScenSyn/scenes/chat_system.tscn") as PackedScene
	var transcript_node: Control = chat_scene.instantiate() as Control
	transcript_node.name = "StoryLogSystem"
	var text_input_node := LineEdit.new()
	text_input_node.name = "InputField"
	story_tab_node.add_child(transcript_node)
	story_tab_node.add_child(text_input_node)
	conversation_region_node.add_child(story_tab_node)
	for tab_id: String in ["About", "How To"]:
		var tab_node := VBoxContainer.new()
		tab_node.name = tab_id
		var tab_label_node := RichTextLabel.new()
		tab_label_node.fit_content = true
		tab_label_node.text = "Practical-width workshop guidance"
		tab_node.add_child(tab_label_node)
		conversation_region_node.add_child(tab_node)
	var session_record_region_node := VBoxContainer.new()
	session_record_region_node.custom_minimum_size = Vector2(640, 900)
	var input_actions_node := HBoxContainer.new()
	var voice_actions_node := HBoxContainer.new()
	var record_button_node := Button.new()
	root.add_child(shell_node)
	root.add_child(conversation_region_node)
	conversation_region_node.add_child(session_record_region_node)
	root.add_child(input_actions_node)
	input_actions_node.add_child(voice_actions_node)
	voice_actions_node.add_child(record_button_node)

	var workspace_controller: RefCounted = WorkspaceControllerScript.new()
	workspace_controller.end_and_save_requested.connect(
		func() -> void: _end_save_requests += 1
	)
	_expect(
		workspace_controller.mount(
			shell_node,
			conversation_region_node,
			session_record_region_node,
			record_button_node
		),
		"Workspace controller failed to mount"
	)

	for preset_id: String in ["talk", "map", "review", "how_to", "full_dashboard"]:
		workspace_controller.apply_preset(preset_id, false)
		_expect(
			workspace_controller.safety_controls_are_visible(),
			"Safety controls became hidden in preset: " + preset_id
		)
	workspace_controller.set_how_to_text("Step one. Step two.")
	var how_to_label_node: RichTextLabel = (
		workspace_controller.get_control("HowToContentLabel") as RichTextLabel
	)
	_expect(
		how_to_label_node != null
		and how_to_label_node.text.contains("/synthesis")
		and how_to_label_node.text.contains("Screen layout")
		and how_to_label_node.text.contains("Custom ▾")
		and how_to_label_node.text.contains("This scenario's guidance")
		and how_to_label_node.text.contains("Step one. Step two."),
		"set_how_to_text did not append scenario guidance to the base How To text"
	)
	workspace_controller.set_how_to_text("")
	_expect(
		how_to_label_node.text.contains("/decide")
		and not how_to_label_node.text.contains("This scenario's guidance"),
		"set_how_to_text did not fall back to the base guide alone for empty scenario text"
	)
	workspace_controller.apply_preset("how_to", false)
	_expect(
		workspace_controller.get_control("HowToSurface").visible
		and not workspace_controller.get_control("ThinkingMapPanel").visible
		and not workspace_controller.get_control("ConversationAndDockSplit").visible,
		"How To preset did not take over the main workspace"
	)
	workspace_controller.apply_preset("full_dashboard", false)
	_expect(
		not workspace_controller.get_control("HowToSurface").visible,
		"Full Dashboard did not hide the How To surface again"
	)
	workspace_controller.apply_preset("review", false)
	_expect(
		session_record_region_node.get_parent()
		== workspace_controller.get_control("CenterSessionRecordSlot"),
		"Review did not move the editable Session Record into the center"
	)
	_expect(
		workspace_controller.get_control("WorkshopComparePaths").visible
		and workspace_controller.get_control("CenterReviewSurface").visible,
		"Review did not expose the intentional center review surface"
	)
	workspace_controller.apply_preset("full_dashboard", false)
	_expect(
		session_record_region_node.get_parent()
		== workspace_controller.get_control("SessionRecordContentSlot")
		and not workspace_controller.get_control("WorkshopComparePaths").visible,
		"Full Dashboard did not restore Session Record to the right rail"
	)

	workspace_controller.apply_preset("talk", false)
	var message_box_node: VBoxContainer = transcript_node.get_node_or_null(
		"%VBoxContainer"
	) as VBoxContainer
	message_box_node.custom_minimum_size.y = 300.0
	workspace_controller.set_panel_visible("session_menu", true, false)
	await process_frame
	await process_frame
	_expect(
		workspace_controller.get_active_preset_id() == "custom",
		"Manual panel toggle did not activate Custom"
	)
	_expect(
		message_box_node.custom_minimum_size.y == 0.0
		and workspace_controller.get_control("ConversationPanel").clip_contents
		and workspace_controller.get_control(
			"ConversationTranscriptScroll"
		).clip_contents,
		"Panel toggle restored an overflowing Conversation welcome region"
	)
	var remembered_custom: Dictionary = workspace_controller.get_panel_visibility()
	workspace_controller.apply_preset("full_dashboard", false)
	workspace_controller.apply_preset("custom", false)
	_expect(
		workspace_controller.get_panel_visibility() == remembered_custom,
		"Custom panel visibility was not remembered"
	)

	var persisted_state: Dictionary = workspace_controller.get_persisted_state()
	workspace_controller.apply_preset("map", false)
	workspace_controller.restore_persisted_state(persisted_state)
	_expect(
		workspace_controller.get_active_preset_id() == "custom"
		and workspace_controller.get_panel_visibility() == remembered_custom,
		"Persisted preset/custom state did not restore"
	)
	var expanded_rail_state: Dictionary = (
		workspace_controller.get_persisted_state()
	)
	expanded_rail_state["workshop_workspace_collapsed_rails"] = {
		"left": false,
		"right": false,
	}
	expanded_rail_state["workshop_workspace_split_offsets"] = {
		"left_rail": 0,
		"right_rail": 0,
		"center_vertical": 0,
		"right_vertical": 0,
	}
	workspace_controller.restore_persisted_state(expanded_rail_state)

	var safety_bar_node: Control = workspace_controller.get_control("SafetyBar")
	var dashboard_body_node: Control = workspace_controller.get_control("DashboardBody")
	_expect(
		safety_bar_node.get_parent() == shell_node
		and not dashboard_body_node.is_ancestor_of(safety_bar_node),
		"Safety controls are structurally inside dashboard regions"
	)
	_assert_dashboard_hierarchy(shell_node)
	_assert_scroll_ownership(
		workspace_controller,
		conversation_region_node,
		transcript_node,
		session_record_region_node,
		text_input_node,
		input_actions_node,
		record_button_node
	)

	workspace_controller.update_responsive_layout(1024.0)
	_expect(
		workspace_controller.get_responsive_layout_id() == "medium",
		"1024px viewport did not use the medium dashboard"
	)
	var left_rail_node: Control = workspace_controller.get_control("SessionMenuPanel")
	var right_rail_node: Control = workspace_controller.get_control("RightRailContainer")
	var map_columns_node: GridContainer = shell_node.find_child(
		"MapColumns",
		true,
		false
	) as GridContainer
	_expect(
		left_rail_node.custom_minimum_size.x
		+ right_rail_node.custom_minimum_size.x <= 440.0,
		"1024px rails reserve too much horizontal minimum size"
	)
	# One row whatever the column count. Asserting a literal 3 here let the Outcomes column
	# wrap onto a second row unnoticed: the assertion described the columns that existed when
	# it was written rather than the invariant it meant to protect.
	_expect(
		map_columns_node != null
		and map_columns_node.columns == map_columns_node.get_child_count(),
		"1024px center map stacked the claim columns instead of keeping them side by side"
	)
	await _assert_bounded_viewport(
		workspace_controller, shell_node, transcript_node, Vector2(1024, 576)
	)
	await _assert_bounded_viewport(
		workspace_controller, shell_node, transcript_node, Vector2(1024, 768)
	)
	await _assert_viewport_matrix(
		workspace_controller,
		shell_node
	)
	await _assert_splitter_state(workspace_controller)
	var navigation_toggle_node: CheckButton = (
		workspace_controller.get_control("SessionMenuToggle") as CheckButton
	)
	var insights_toggle_node: CheckButton = (
		workspace_controller.get_control("InsightsToggle") as CheckButton
	)
	navigation_toggle_node.set_pressed_no_signal(false)
	navigation_toggle_node.toggled.emit(false)
	_expect(
		not left_rail_node.visible,
		"Navigation check button did not hide the medium rail"
	)
	navigation_toggle_node.set_pressed_no_signal(true)
	navigation_toggle_node.toggled.emit(true)
	_expect(left_rail_node.visible, "Navigation check button did not show the medium rail")

	workspace_controller.update_responsive_layout(1600.0)
	_expect(
		workspace_controller.get_responsive_layout_id() == "wide"
		and left_rail_node.visible
		and right_rail_node.visible,
		"Wide dashboard did not expose all three regions"
	)
	workspace_controller.update_responsive_layout(700.0)
	_expect(
		workspace_controller.get_responsive_layout_id() == "narrow"
		and not left_rail_node.visible
		and not right_rail_node.visible,
		"Narrow dashboard did not make the center primary"
	)
	navigation_toggle_node.set_pressed_no_signal(true)
	navigation_toggle_node.toggled.emit(true)
	_expect(
		workspace_controller.get_open_narrow_drawer_id() == "left"
		and left_rail_node.visible
		and not workspace_controller.get_control("CenterWorkspace").visible,
		"Navigation check button did not open the narrow panel"
	)
	navigation_toggle_node.set_pressed_no_signal(false)
	navigation_toggle_node.toggled.emit(false)
	_expect(
		workspace_controller.get_open_narrow_drawer_id().is_empty()
		and workspace_controller.get_control("CenterWorkspace").visible,
		"Navigation check button did not close the narrow panel"
	)
	insights_toggle_node.set_pressed_no_signal(true)
	insights_toggle_node.toggled.emit(true)
	_expect(
		workspace_controller.get_open_narrow_drawer_id() == "right"
		and right_rail_node.visible
		and not workspace_controller.get_control("CenterWorkspace").visible,
		"Insights check button did not open the narrow panel"
	)
	insights_toggle_node.set_pressed_no_signal(false)
	insights_toggle_node.toggled.emit(false)
	_expect(
		workspace_controller.get_open_narrow_drawer_id().is_empty()
		and workspace_controller.get_control("CenterWorkspace").visible,
		"Insights check button did not close the narrow panel"
	)
	for removed_control_id: String in [
		"LeftRailToggleButton",
		"RightRailToggleButton",
		"LeftDrawerButton",
		"RightDrawerButton",
	]:
		_expect(
			workspace_controller.get_control(removed_control_id) == null,
			"Duplicate rail control remains: " + removed_control_id
		)
	_expect(
		map_columns_node != null
		and map_columns_node.columns == map_columns_node.get_child_count(),
		"Narrow Thinking Map did not keep columns side by side"
	)
	var diagnostics_toggle_node: CheckButton = workspace_controller.get_control(
		"LayoutDiagnosticsToggle"
	) as CheckButton
	diagnostics_toggle_node.set_pressed_no_signal(true)
	diagnostics_toggle_node.toggled.emit(true)
	var diagnostics_panel_node: PanelContainer = workspace_controller.get_control(
		"LayoutDiagnosticsPanel"
	) as PanelContainer
	var diagnostics_text_node: RichTextLabel = workspace_controller.get_control(
		"LayoutDiagnosticsText"
	) as RichTextLabel
	_expect(
		diagnostics_panel_node.visible
		and diagnostics_text_node.text.contains("Breakpoint:")
		and diagnostics_text_node.text.contains("parent="),
		"Layout diagnostics did not expose breakpoint and ownership data"
	)
	diagnostics_toggle_node.toggled.emit(false)
	_assert_visible_actions_are_bound(shell_node)
	(workspace_controller.get_control("PlansPreviewButton") as Button).pressed.emit()
	var preview_label_node: Label = (
		workspace_controller.get_control("NavigationPreviewState") as Label
	)
	_expect(
		preview_label_node.text.contains("Plans preview")
		and preview_label_node.text.contains("coming soon"),
		"Plans action did not resolve to a labelled preview"
	)
	(workspace_controller.get_control("EndAndSaveButton") as Button).pressed.emit()
	_expect(_end_save_requests == 1, "End & Save action was not routed")

	shell_node.queue_free()
	conversation_region_node.queue_free()
	await process_frame


func _assert_scroll_ownership(
	workspace_controller: RefCounted,
	conversation_region_node: Control,
	transcript_node: Control,
	session_record_region_node: Control,
	text_input_node: Control,
	input_actions_node: Control,
	record_button_node: Control
) -> void:
	var transcript_scroll_node: ScrollContainer = (
		workspace_controller.get_control("ConversationTranscriptScroll") as ScrollContainer
	)
	var input_dock_node: Control = workspace_controller.get_control("ConversationInputDock")
	var right_record_scroll_node: ScrollContainer = (
		workspace_controller.get_control("SessionRecordScroll") as ScrollContainer
	)
	var review_scroll_node: ScrollContainer = (
		workspace_controller.get_control("ReviewScroll") as ScrollContainer
	)
	var left_scroll_node: ScrollContainer = (
		workspace_controller.get_control("LeftRailScroll") as ScrollContainer
	)
	var assistant_scroll_node: ScrollContainer = (
		workspace_controller.get_control("AiAssistantScroll") as ScrollContainer
	)
	var end_button_node: Control = workspace_controller.get_control("EndAndSaveButton")
	_expect(
		transcript_scroll_node.is_ancestor_of(transcript_node)
		and not transcript_scroll_node.is_ancestor_of(conversation_region_node)
		and not conversation_region_node.visible,
		"Workshop mounted or exposed the legacy conversation TabContainer"
	)
	_expect(
		input_dock_node.is_ancestor_of(text_input_node)
		and not transcript_scroll_node.is_ancestor_of(text_input_node),
		"Center text input is not docked outside transcript scrolling"
	)
	_expect(
		input_dock_node.is_ancestor_of(record_button_node)
		and not input_actions_node.visible,
		"Voice/text actions were not moved into the center input dock"
	)
	_expect(
		right_record_scroll_node.is_ancestor_of(session_record_region_node),
		"Right Session Record is not owned by its bounded scroll"
	)
	_expect(
		not right_record_scroll_node.is_ancestor_of(end_button_node),
		"End & Save is incorrectly inside right-rail scrolling content"
	)
	_expect(
		review_scroll_node != null and left_scroll_node != null and assistant_scroll_node != null,
		"One or more scene-authored bounded scroll regions are missing"
	)
	_expect(
		transcript_node.custom_minimum_size == Vector2.ZERO
		and session_record_region_node.custom_minimum_size == Vector2.ZERO
		and transcript_node.size_flags_horizontal == Control.SIZE_EXPAND_FILL,
		"Reparented live regions retained overflow-causing minimum sizes"
	)


func _assert_bounded_viewport(
	workspace_controller: RefCounted,
	shell_node: Control,
	transcript_node: Control,
	viewport_size: Vector2
) -> void:
	workspace_controller.update_responsive_layout(viewport_size.x)
	shell_node.size = viewport_size
	await process_frame
	await process_frame
	shell_node.size = viewport_size
	await process_frame
	var body_node: Control = workspace_controller.get_control("DashboardBody")
	var center_node: Control = workspace_controller.get_control("CenterWorkspace")
	var transcript_scroll_node: Control = workspace_controller.get_control(
		"ConversationTranscriptScroll"
	)
	var input_dock_node: Control = workspace_controller.get_control("ConversationInputDock")
	var chat_scroll_node: ScrollContainer = transcript_node.find_child(
		"ScrollContainer", true, false
	) as ScrollContainer
	var messages_node: VBoxContainer = transcript_node.find_child(
		"VBoxContainer", true, false
	) as VBoxContainer
	var shell_minimum: Vector2 = shell_node.get_combined_minimum_size()
	_expect(
		shell_minimum.x <= viewport_size.x,
		"%dx%d layout forces root horizontal overflow (minimum %.1f)"
		% [int(viewport_size.x), int(viewport_size.y), shell_minimum.x]
	)
	_expect(
		body_node.size.x <= viewport_size.x + 0.5
		and body_node.size.y <= viewport_size.y + 0.5,
		"%dx%d dashboard body escaped the viewport" % [
			int(viewport_size.x), int(viewport_size.y)
		]
	)
	_expect(
		not transcript_scroll_node.get_global_rect().intersects(input_dock_node.get_global_rect()),
		"%dx%d transcript and input rectangles overlap" % [
			int(viewport_size.x), int(viewport_size.y)
		]
	)
	var practical_width: float = center_node.size.x * 0.6
	for practical_node: Control in [
		transcript_node,
		chat_scroll_node,
		messages_node,
	]:
		_expect(
			practical_node != null
			and practical_node.size.x > practical_width
			and practical_node.size.x > 160.0,
			"%dx%d %s collapsed below practical center width (%.1f / %.1f)"
			% [
				int(viewport_size.x), int(viewport_size.y),
				practical_node.name if practical_node else "missing node",
				practical_node.size.x if practical_node else 0.0,
				center_node.size.x,
			]
		)
	_expect(
		chat_scroll_node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"ChatSystem introduced a conflicting horizontal scroll"
	)


func _assert_viewport_matrix(
	workspace_controller: RefCounted,
	shell_node: Control
) -> void:
	var viewport_cases: Array[Dictionary] = [
		{"size": Vector2(700, 768), "layout_id": "narrow"},
		{"size": Vector2(899, 768), "layout_id": "narrow"},
		{"size": Vector2(900, 576), "layout_id": "medium"},
		{"size": Vector2(1200, 768), "layout_id": "medium"},
		{"size": Vector2(1399, 900), "layout_id": "medium"},
		{"size": Vector2(1400, 900), "layout_id": "wide"},
		{"size": Vector2(1920, 1080), "layout_id": "wide"},
	]
	for viewport_case: Dictionary in viewport_cases:
		var viewport_size: Vector2 = viewport_case.get(
			"size",
			Vector2(1024, 768)
		)
		for preset_id: String in [
			"talk",
			"map",
			"review",
			"full_dashboard",
		]:
			workspace_controller.apply_preset(preset_id, false)
			shell_node.size = viewport_size
			await process_frame
			await process_frame
			workspace_controller.update_responsive_layout(viewport_size.x)
			var body_node: Control = workspace_controller.get_control(
				"DashboardBody"
			)
			_expect(
				workspace_controller.get_responsive_layout_id()
				== String(viewport_case.get("layout_id", ""))
				and shell_node.get_combined_minimum_size().x
				<= viewport_size.x + 0.5
				and workspace_controller.safety_controls_are_visible(),
				(
					"%s preset escaped/misclassified %dx%d "
					+ "(layout=%s shell_min=%.1f body=%.1f safety=%s)"
				)
				% [
					preset_id,
					int(viewport_size.x),
					int(viewport_size.y),
					workspace_controller.get_responsive_layout_id(),
					shell_node.get_combined_minimum_size().x,
					body_node.size.x,
					str(workspace_controller.safety_controls_are_visible()),
				]
			)


func _assert_splitter_state(workspace_controller: RefCounted) -> void:
	var main_split_node: HSplitContainer = (
		workspace_controller.get_control("MainRegionSplit") as HSplitContainer
	)
	workspace_controller.set_split_offset("right_rail", 64)
	await process_frame
	_expect(
		workspace_controller.get_split_offset("right_rail") == 64,
		"Deterministic splitter change was not applied"
	)
	main_split_node.dragged.emit(main_split_node.split_offset)
	var dragged_state: Dictionary = workspace_controller.get_persisted_state()
	var dragged_offsets: Dictionary = dragged_state.get(
		"workshop_workspace_split_offsets", {}
	)
	_expect(
		dragged_offsets.get("right_rail", 0) == 64,
		"Dragged splitter offset was not persisted"
	)
	dragged_state["workshop_workspace_split_offsets"] = {
		"left_rail": 999999,
		"right_rail": "invalid",
		"center_vertical": -999999,
		"right_vertical": 0,
	}
	workspace_controller.restore_persisted_state(dragged_state)
	await process_frame
	await process_frame
	_expect(
		workspace_controller.get_split_offset("right_rail") == 0,
		"Invalid persisted splitter offset did not restore a safe default"
	)
	workspace_controller.set_split_offset("right_rail", 999999)
	_expect(
		absi(workspace_controller.get_split_offset("right_rail"))
		< int(main_split_node.size.x),
		"Splitter offset was not clamped to the current viewport"
	)
	(workspace_controller.get_control("ResetPanelSizesButton") as Button).pressed.emit()
	_expect(
		workspace_controller.get_split_offset("right_rail") == 0,
		"Reset panel sizes did not restore preset defaults"
	)


func _assert_dashboard_hierarchy(shell_node: Control) -> void:
	var header_node: Control = shell_node.find_child("SessionHeader", true, false) as Control
	var body_node: HSplitContainer = shell_node.find_child(
		"DashboardBody", true, false
	) as HSplitContainer
	var main_split_node: HSplitContainer = shell_node.find_child(
		"MainRegionSplit", true, false
	) as HSplitContainer
	var center_split_node: VSplitContainer = shell_node.find_child(
		"CenterVerticalSplit", true, false
	) as VSplitContainer
	var right_split_node: VSplitContainer = shell_node.find_child(
		"RightVerticalSplit", true, false
	) as VSplitContainer
	var left_rail_node: Control = shell_node.find_child("SessionMenuPanel", true, false) as Control
	var center_node: Control = shell_node.find_child("CenterWorkspace", true, false) as Control
	var right_rail_node: Control = shell_node.find_child(
		"RightRailContainer", true, false
	) as Control
	var map_node: Control = shell_node.find_child("ThinkingMapPanel", true, false) as Control
	var review_node: Control = shell_node.find_child(
		"CenterReviewSurface", true, false
	) as Control
	var record_node: Control = shell_node.find_child("SessionRecordPanel", true, false) as Control
	var end_button_node: Control = shell_node.find_child("EndAndSaveButton", true, false) as Control
	_expect(header_node != null, "Top session header is missing")
	_expect(
		body_node != null
		and body_node.get_child_count() == 2
		and main_split_node != null
		and main_split_node.get_child_count() == 2,
		"Dashboard does not use the nested two-pane split hierarchy"
	)
	_expect(left_rail_node.get_parent() == body_node, "Left rail is not a primary region")
	_expect(center_node.get_parent() == main_split_node, "Center is not in the nested split")
	_expect(right_rail_node.get_parent() == main_split_node, "Right rail is not nested")
	_expect(
		center_split_node != null and right_split_node != null,
		"Center/right vertical split panes are missing"
	)
	_expect(center_node.is_ancestor_of(map_node), "Thinking Map is not in center workspace")
	_expect(center_node.is_ancestor_of(review_node), "Review surface is not in center workspace")
	_expect(right_rail_node.is_ancestor_of(record_node), "Session Record is not in right rail")
	_expect(
		shell_node.find_child("SessionMenuPanel", true, false).is_ancestor_of(end_button_node),
		"End & Save is not anchored in the Session Menu panel"
	)
	_expect(
		body_node.clip_contents
		and left_rail_node.clip_contents
		and center_node.clip_contents
		and right_rail_node.clip_contents,
		"Primary dashboard regions do not clip overflowing children"
	)
	_expect(
		body_node.size_flags_vertical == Control.SIZE_EXPAND_FILL
		and left_rail_node.size_flags_vertical == Control.SIZE_EXPAND_FILL
		and center_node.size_flags_vertical == Control.SIZE_EXPAND_FILL
		and right_rail_node.size_flags_vertical == Control.SIZE_EXPAND_FILL,
		"Primary dashboard body/rails are not bounded expand-fill regions"
	)
	_expect(
		shell_node.find_child("WorkspacePanels", true, false) == null,
		"Generic six-panel GridContainer composition still exists"
	)
	_expect(
		body_node.find_children("*", "GridContainer", true, false).size() <= 1,
		"Dashboard regions are still composed as a generic grid"
	)


func _assert_visible_actions_are_bound(shell_node: Control) -> void:
	var visible_buttons: Array[Node] = shell_node.find_children("*", "Button", true, false)
	for action_node: Node in visible_buttons:
		var action_button_node: Button = action_node as Button
		if action_button_node.is_visible_in_tree():
			var has_binding: bool = (
				not action_button_node.pressed.get_connections().is_empty()
				or not action_button_node.toggled.get_connections().is_empty()
			)
			_expect(has_binding, "Visible shell button has no action: " + action_button_node.name)


func _test_module_boundaries() -> void:
	var script_paths: Array[String] = [
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_preset_model.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_split_layout_state.gd",
	]
	for script_path: String in script_paths:
		var parsed_script: GDScript = load(script_path) as GDScript
		_expect(parsed_script != null, "Script did not parse: " + script_path)
		var source_text: String = FileAccess.get_file_as_string(script_path)
		_expect(
			source_text.count("\n") + 1 <= 900,
			"Workshop module exceeds 900 lines: " + script_path
		)
	var workspace_source: String = FileAccess.get_file_as_string(script_paths[1])
	_expect(
		workspace_source.contains("synesyn_ui_tokens.gd")
		and not workspace_source.contains("const MEDIUM_BREAKPOINT"),
		"Workspace structural values are not owned by shared UI tokens"
	)
	var transcript_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_transcript_controller.gd"
	)
	_expect(
		transcript_source.contains("set_conversation_overlay")
		and not transcript_source.contains("_preview_panel_node.visible")
		and not transcript_source.contains("_correction_panel_node.visible"),
		"Transcript controller still competes for layout visibility ownership"
	)
	_expect(
		UiTokensScript.BREAKPOINT_MEDIUM == 900.0
		and UiTokensScript.BREAKPOINT_WIDE == 1400.0
		and UiTokensScript.SPLIT_MIN_PANE_EXTENT == 72,
		"Shared structural UI tokens changed unexpectedly"
	)
	for static_constructor: String in [
		"Label.new()",
		"Button.new()",
		"CheckButton.new()",
		"PanelContainer.new()",
		"VBoxContainer.new()",
		"HBoxContainer.new()",
	]:
		_expect(
			not workspace_source.contains(static_constructor),
			"Workspace controller builds static UI: " + static_constructor
		)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 4 tests: all passed")
		quit(0)
		return
	for failure_message: String in _failures:
		push_error(failure_message)
	quit(1)
