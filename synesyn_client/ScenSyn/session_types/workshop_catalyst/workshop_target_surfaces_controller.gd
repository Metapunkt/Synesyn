extends RefCounted
class_name WorkshopTargetSurfacesController

## Owns truthful, local-only Participant and preview-only Plans/Progress surfaces,
## plus the "My Sessions" local-file browser (list + resume-live action).
## This controller has no Hub, network, email, or persistence dependency.

const SessionScannerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_scanner.gd"
)
const SessionListItemScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_my_session_list_item.tscn"
)

const SECTION_COPY: Dictionary = {
	"plans": {
		"title": "Plans preview — coming soon",
		"available": "Available now: Session Record and Compare Paths.",
		"unavailable": "Not available: plan execution, assignments, or outbound follow-up.",
	},
	"progress": {
		"title": "Progress preview — coming soon",
		"available": "Available now: committed workshop artifacts and Session Record.",
		"unavailable": "Not available: progress tracking, analytics, or follow-up automation.",
	},
}

const DEFAULT_PREVIEW_COPY: Dictionary = {
	"title": "Session shortcuts",
	# Compare Paths is not a peer of the other three: it lives inside the Review
	# preset and needs a reviewed decision before it can do anything, so listing it
	# alongside them sent facilitators hunting for a surface they could not find.
	"available": (
		"Live now: Show Chat, Thinking Map, and Session Record."
		+ " Compare Paths opens under Review, once a decision is recorded."
	),
	"unavailable": "Plans and Progress open labelled previews only.",
}

var _shell_root_node: Control
var _active_section_id: String = ""
var _invite_open_count: int = 0
var _outbound_action_count: int = 0


func mount(shell_root_node: Control) -> bool:
	if not shell_root_node:
		return false
	_shell_root_node = shell_root_node
	var invite_button_node: Button = _find_control("InviteParticipantButton") as Button
	var plans_button_node: Button = _find_control("PlansPreviewButton") as Button
	var progress_button_node: Button = _find_control("ProgressPreviewButton") as Button
	var invite_dialog_node: AcceptDialog = _find_node("InviteUnavailableDialog") as AcceptDialog
	if (
		not invite_button_node
		or not plans_button_node
		or not progress_button_node
		or not invite_dialog_node
		or not _find_control("NavigationPreviewState")
		or not _find_control("NavigationPreviewAvailable")
		or not _find_control("NavigationPreviewUnavailable")
	):
		return false
	invite_button_node.pressed.connect(_on_invite_requested)
	plans_button_node.pressed.connect(_on_section_requested.bind("plans"))
	progress_button_node.pressed.connect(_on_section_requested.bind("progress"))
	invite_dialog_node.confirmed.connect(_on_invite_explanation_acknowledged)
	# Insights and Settings are wired to real behavior in
	# workshop_workspace_controller.gd (toggle the Insights rail / open the
	# hamburger settings drawer). Scenarios was removed as a duplicate of the
	# existing top-bar Scenario objective toggle (shared with Story Catalyst).
	_mount_my_sessions()
	_apply_preview_copy(DEFAULT_PREVIEW_COPY)
	return true


func _mount_my_sessions() -> bool:
	var my_sessions_button_node: Button = _find_control("MySessionsButton") as Button
	# Control overlay (not Window): inherits the shell theme cascade and keeps
	# reliable contrast via the card StyleBox — same lesson as Facilitator.
	var dialog_node: Control = _find_node("MySessionsDialog") as Control
	var list_container_node: VBoxContainer = _find_control("MySessionsListContainer") as VBoxContainer
	var empty_state_node: Label = _find_control("MySessionsEmptyState") as Label
	var close_button_node: Button = _find_control("MySessionsCloseButton") as Button
	var scrim_node: ColorRect = _find_control("MySessionsScrim") as ColorRect
	if (
		not my_sessions_button_node
		or not dialog_node
		or not list_container_node
		or not empty_state_node
		or not close_button_node
	):
		return false
	my_sessions_button_node.pressed.connect(_on_my_sessions_button_pressed)
	close_button_node.pressed.connect(_hide_my_sessions_dialog)
	if scrim_node and not scrim_node.gui_input.is_connected(_on_my_sessions_scrim_gui_input):
		scrim_node.gui_input.connect(_on_my_sessions_scrim_gui_input)
	return true


func get_active_section_id() -> String:
	return _active_section_id


func get_invite_open_count() -> int:
	return _invite_open_count


func get_outbound_action_count() -> int:
	return _outbound_action_count


func get_control(control_id: String) -> Control:
	return _find_control(control_id)


func _on_invite_requested() -> void:
	var invite_dialog_node: AcceptDialog = _find_node("InviteUnavailableDialog") as AcceptDialog
	if not invite_dialog_node:
		return
	_invite_open_count += 1
	invite_dialog_node.popup_centered()


func _on_invite_explanation_acknowledged() -> void:
	var participant_status_node: Label = _find_control("ParticipantsActionStatus") as Label
	if participant_status_node:
		participant_status_node.text = (
			"Invite remains unavailable. No invitation or outbound message was sent."
		)


func _on_my_sessions_button_pressed() -> void:
	var dialog_node: Control = _find_node("MySessionsDialog") as Control
	var list_container_node: VBoxContainer = _find_control("MySessionsListContainer") as VBoxContainer
	var empty_state_node: Label = _find_control("MySessionsEmptyState") as Label
	if not dialog_node or not list_container_node or not empty_state_node:
		return
	for child_node: Node in list_container_node.get_children():
		child_node.queue_free()
	var sessions: Array[Dictionary] = SessionScannerScript.scan_workshop_catalyst_sessions()
	empty_state_node.visible = sessions.is_empty()
	for session_entry: Dictionary in sessions:
		var session_button_node: Button = SessionListItemScene.instantiate() as Button
		session_button_node.text = SessionScannerScript.format_session_label(session_entry)
		session_button_node.pressed.connect(_on_session_selected.bind(session_entry))
		list_container_node.add_child(session_button_node)
	dialog_node.visible = true
	WorkshopPresenceController.fit_viewport_overlay(dialog_node)


func _hide_my_sessions_dialog() -> void:
	var dialog_node: Control = _find_node("MySessionsDialog") as Control
	if dialog_node:
		dialog_node.visible = false


func _on_my_sessions_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_my_sessions_dialog()


func _on_session_selected(session_entry: Dictionary) -> void:
	_hide_my_sessions_dialog()
	var json_path: String = String(session_entry.get("json_path", ""))
	if json_path.is_empty() or not _shell_root_node:
		return
	var scene_tree: SceneTree = _shell_root_node.get_tree()
	if not scene_tree:
		return
	var game_session_node: Node = scene_tree.get_first_node_in_group("game_session")
	if game_session_node and game_session_node.has_method("_on_story_log_file_selected"):
		game_session_node.call("_on_story_log_file_selected", json_path)


func _on_unavailable_navigation_requested(button_id: String) -> void:
	var dialog_node: AcceptDialog = (
		_shell_root_node.find_child("NavigationUnavailableDialog", true, false)
		as AcceptDialog
	)
	if not dialog_node:
		return
	var destination_label: String = button_id.trim_suffix("Button")
	dialog_node.title = destination_label + " unavailable"
	dialog_node.dialog_text = (
		"%s is not available inside the live workshop. "
		+ "No external action was started."
	) % destination_label
	dialog_node.popup_centered()


func _on_section_requested(section_id: String) -> void:
	if not SECTION_COPY.has(section_id):
		return
	_active_section_id = section_id
	_apply_preview_copy(SECTION_COPY[section_id])


func _apply_preview_copy(section_data: Dictionary) -> void:
	var preview_card_node: Control = _find_control("MenuPreviewCard")
	var title_label_node: Label = _find_control("NavigationPreviewState") as Label
	var available_label_node: Label = _find_control("NavigationPreviewAvailable") as Label
	var unavailable_label_node: Label = _find_control("NavigationPreviewUnavailable") as Label
	if title_label_node:
		title_label_node.text = String(section_data.get("title", "Preview unavailable"))
	if available_label_node:
		var available_text: String = String(section_data.get("available", "")).strip_edges()
		available_label_node.text = available_text
		available_label_node.visible = not available_text.is_empty()
	if unavailable_label_node:
		var unavailable_text: String = String(section_data.get("unavailable", "")).strip_edges()
		unavailable_label_node.text = unavailable_text
		unavailable_label_node.visible = not unavailable_text.is_empty()
	if preview_card_node:
		preview_card_node.visible = true


func _find_control(control_id: String) -> Control:
	return _find_node(control_id) as Control


func _find_node(node_id: String) -> Node:
	if not _shell_root_node:
		return null
	return _shell_root_node.find_child(node_id, true, false)
