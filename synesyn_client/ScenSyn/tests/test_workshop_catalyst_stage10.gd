extends SceneTree

const WorkspaceControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_target_surfaces_and_actions()
	_test_no_outbound_seam()
	_test_module_boundaries()
	_finish()


func _test_target_surfaces_and_actions() -> void:
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	var conversation_region_node := TabContainer.new()
	var session_record_region_node := VBoxContainer.new()
	var record_button_node := Button.new()
	var story_log_system_node := Control.new()
	story_log_system_node.name = "StoryLogSystem"
	root.add_child(shell_node)
	root.add_child(conversation_region_node)
	conversation_region_node.add_child(session_record_region_node)
	conversation_region_node.add_child(story_log_system_node)
	root.add_child(record_button_node)
	var workspace_controller: RefCounted = WorkspaceControllerScript.new()
	_expect(
		workspace_controller.mount(
			shell_node,
			conversation_region_node,
			session_record_region_node,
			record_button_node
		),
		"Workspace failed to mount Stage 10 target surfaces"
	)
	workspace_controller.apply_preset("full_dashboard", false)
	await process_frame

	var participants_panel_node: Control = (
		workspace_controller.get_control("ParticipantsPanel") as Control
	)
	var navigation_panel_node: Control = (
		workspace_controller.get_control("SessionMenuPanel") as Control
	)
	var session_header_node: Control = (
		workspace_controller.get_control("SessionHeader") as Control
	)
	var dashboard_body_node: Control = (
		workspace_controller.get_control("DashboardBody") as Control
	)
	var main_split_node: Control = (
		workspace_controller.get_control("MainRegionSplit") as Control
	)
	var right_rail_node: Control = (
		workspace_controller.get_control("RightRailContainer") as Control
	)
	var left_scroll_node: ScrollContainer = (
		workspace_controller.get_control("LeftRailScroll") as ScrollContainer
	)
	var assistant_scroll_node: ScrollContainer = (
		workspace_controller.get_control("AiAssistantScroll") as ScrollContainer
	)
	var record_scroll_node: ScrollContainer = (
		workspace_controller.get_control("SessionRecordScroll") as ScrollContainer
	)
	_assert_every_visible_control_is_bound(navigation_panel_node)
	_expect(
		participants_panel_node.find_children("*", "BaseButton", true, false).is_empty(),
		"Footer facilitator strip should be identity/status only"
	)
	_expect(
		workspace_controller.get_control("SafetyBar").is_ancestor_of(participants_panel_node),
		"Participants are not in the footer status strip"
	)
	_expect(
		navigation_panel_node.get_parent() == dashboard_body_node,
		"Product navigation is not the left dashboard rail"
	)
	_expect(
		dashboard_body_node is HSplitContainer
		and main_split_node is HSplitContainer
		and main_split_node.get_parent() == dashboard_body_node,
		"Stage 10 dashboard does not retain the nested split hierarchy"
	)
	_expect(
		right_rail_node.is_ancestor_of(
			workspace_controller.get_control("SessionRecordPanel")
		),
		"Editable Session Record is not in the right insight rail"
	)
	_expect(
		workspace_controller.get_control("SafetyBar").get_parent() == shell_node,
		"Safety footer is not continuously reachable"
	)
	_expect(
		left_scroll_node != null
		and assistant_scroll_node != null
		and record_scroll_node != null
		and left_scroll_node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and assistant_scroll_node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and record_scroll_node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"Stage 10 rails do not own independent vertical scrolling"
	)
	_expect(
		not record_scroll_node.is_ancestor_of(
			workspace_controller.get_control("EndAndSaveButton")
		),
		"Stage 10 End & Save is not fixed outside right-rail scrolling"
	)

	var target_controller: RefCounted = workspace_controller.get_target_surfaces_controller()
	var invite_button_node: Button = (
		workspace_controller.get_control("InviteParticipantButton") as Button
	)
	invite_button_node.pressed.emit()
	await process_frame
	var invite_dialog_node: AcceptDialog = shell_node.find_child(
		"InviteUnavailableDialog", true, false
	) as AcceptDialog
	_expect(invite_dialog_node.visible, "Invite did not open a real explanatory dialog")
	_expect(
		invite_dialog_node.dialog_text.contains("not implemented")
		and (
			invite_dialog_node.dialog_text.contains("Nothing has been requested or sent")
			or invite_dialog_node.dialog_text.contains("Nothing outbound was sent")
		),
		"Invite dialog did not state its capability boundary"
	)
	_expect(
		target_controller.get_invite_open_count() == 1,
		"Invite action did not resolve through the target controller"
	)
	var dialog_ok_button_node: Button = invite_dialog_node.get_ok_button()
	_expect(
		not dialog_ok_button_node.pressed.get_connections().is_empty(),
		"Visible Invite explanation acknowledgement has no action"
	)
	dialog_ok_button_node.pressed.emit()
	await process_frame
	var participant_status_node: Label = (
		workspace_controller.get_control("ParticipantsActionStatus") as Label
	)
	_expect(
		participant_status_node.text.contains("No invitation")
		and participant_status_node.text.contains("outbound message"),
		"Invite acknowledgement did not resolve to explicit no-send status"
	)

	var plans_button_node: Button = (
		workspace_controller.get_control("PlansPreviewButton") as Button
	)
	plans_button_node.pressed.emit()
	var preview_title_node: Label = (
		workspace_controller.get_control("NavigationPreviewState") as Label
	)
	var unavailable_label_node: Label = (
		workspace_controller.get_control("NavigationPreviewUnavailable") as Label
	)
	_expect(
		target_controller.get_active_section_id() == "plans"
		and preview_title_node.text.contains("Plans preview")
		and preview_title_node.text.contains("coming soon")
		and unavailable_label_node.text.contains("plan execution"),
		"Plans did not open its truthful preview"
	)

	var progress_button_node: Button = (
		workspace_controller.get_control("ProgressPreviewButton") as Button
	)
	progress_button_node.pressed.emit()
	_expect(
		target_controller.get_active_section_id() == "progress"
		and preview_title_node.text.contains("Progress preview")
		and preview_title_node.text.contains("coming soon")
		and unavailable_label_node.text.contains("progress tracking"),
		"Progress did not open its truthful preview"
	)
	_expect(
		target_controller.get_outbound_action_count() == 0,
		"Target UI reported an outbound side effect"
	)

	shell_node.queue_free()
	conversation_region_node.queue_free()
	record_button_node.queue_free()
	await process_frame


func _assert_every_visible_control_is_bound(surface_root_node: Control) -> void:
	var action_nodes: Array[Node] = surface_root_node.find_children("*", "BaseButton", true, false)
	_expect(not action_nodes.is_empty(), "Target surface contains no actionable controls")
	for action_node: Node in action_nodes:
		var action_button_node: BaseButton = action_node as BaseButton
		if not action_button_node.is_visible_in_tree():
			continue
		var has_action: bool = (
			not action_button_node.pressed.get_connections().is_empty()
			or not action_button_node.toggled.get_connections().is_empty()
		)
		_expect(has_action, "Visible target control has no action: " + action_button_node.name)


func _test_no_outbound_seam() -> void:
	var script_path := (
		"res://ScenSyn/session_types/workshop_catalyst/workshop_target_surfaces_controller.gd"
	)
	var source_text: String = FileAccess.get_file_as_string(script_path)
	for forbidden_call: String in [
		"HTTPRequest.new(",
		".request(",
		"create_artifact",
		"send_email",
		"OS.create_process(",
		"HubSubstrateClient",
	]:
		_expect(
			not source_text.contains(forbidden_call),
			"Target controller contains an outbound seam: " + forbidden_call
		)


func _test_module_boundaries() -> void:
	for script_path: String in [
		"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd",
		"res://ScenSyn/session_types/workshop_catalyst/workshop_target_surfaces_controller.gd",
	]:
		var parsed_script: GDScript = load(script_path) as GDScript
		_expect(parsed_script != null, "Script did not parse: " + script_path)
		var source_text: String = FileAccess.get_file_as_string(script_path)
		_expect(
			source_text.count("\n") + 1 <= 900,
			"Workshop module exceeds 900 lines: " + script_path
		)
	var target_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/session_types/workshop_catalyst/workshop_target_surfaces_controller.gd"
	)
	for static_constructor: String in [
		"Label.new()",
		"Button.new()",
		"PanelContainer.new()",
		"VBoxContainer.new()",
		"HBoxContainer.new()",
	]:
		_expect(
			not target_source.contains(static_constructor),
			"Target controller builds static UI: " + static_constructor
		)


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 10 tests: all passed")
		quit(0)
	else:
		push_error("Workshop Catalyst Stage 10: %d failure(s)" % _failures.size())
		quit(1)
