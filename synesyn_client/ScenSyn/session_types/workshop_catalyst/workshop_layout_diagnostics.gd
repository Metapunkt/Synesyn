extends RefCounted
class_name WorkshopLayoutDiagnostics

## Debug-only presentation of Workshop layout ownership and sizing. It reads
## layout state through the workspace controller and never mutates the layout.

const TRACKED_CONTROL_IDS: Array[String] = [
	"WorkshopWorkspaceShell",
	"DashboardBody",
	"SessionMenuPanel",
	"CenterWorkspace",
	"RightRailContainer",
	"ConversationPanel",
	"ThinkingMapPanel",
	"CenterReviewSurface",
	"AiAssistantPanel",
	"SessionRecordPanel",
]

var _shell_root_node: Control
var _snapshot_provider: Callable
var _toggle_node: CheckButton
var _panel_node: PanelContainer
var _text_node: RichTextLabel


func mount(shell_root_node: Control, snapshot_provider: Callable) -> bool:
	_shell_root_node = shell_root_node
	_snapshot_provider = snapshot_provider
	_toggle_node = shell_root_node.find_child(
		"LayoutDiagnosticsToggle", true, false
	) as CheckButton
	_panel_node = shell_root_node.find_child(
		"LayoutDiagnosticsPanel", true, false
	) as PanelContainer
	_text_node = shell_root_node.find_child(
		"LayoutDiagnosticsText", true, false
	) as RichTextLabel
	if not _toggle_node or not _panel_node or not _text_node:
		return false
	var is_debug_context: bool = OS.is_debug_build() or Engine.is_editor_hint()
	_toggle_node.visible = is_debug_context
	_panel_node.visible = false
	if not _toggle_node.toggled.is_connected(_on_toggled):
		_toggle_node.toggled.connect(_on_toggled)
	# The overlay sits on its own CanvasLayer above the shell, so it outlives the
	# Custom drawer that opened it: shutting that drawer used to leave the panel
	# stranded with no way to dismiss it. Give the overlay its own exit.
	var close_button_node: Button = shell_root_node.find_child(
		"LayoutDiagnosticsCloseButton", true, false
	) as Button
	if close_button_node and not close_button_node.pressed.is_connected(_on_close_pressed):
		close_button_node.pressed.connect(_on_close_pressed)
	return true


## Routes through the toggle rather than hiding the panel directly, so the drawer
## checkbox cannot be left ticked while the overlay is gone.
func _on_close_pressed() -> void:
	if is_instance_valid(_toggle_node):
		_toggle_node.button_pressed = false
		return
	if is_instance_valid(_panel_node):
		_panel_node.visible = false


func refresh() -> void:
	if not is_instance_valid(_panel_node) or not _panel_node.visible:
		return
	var snapshot: Dictionary = (
		_snapshot_provider.call()
		if _snapshot_provider.is_valid()
		else {}
	)
	_text_node.text = format_snapshot(snapshot)


func format_snapshot(snapshot: Dictionary) -> String:
	var lines: Array[String] = [
		"[b]Workshop layout diagnostics[/b]",
		"Breakpoint: %s | viewport: %.0f | drawer: %s" % [
			String(snapshot.get("layout_id", "unknown")),
			float(snapshot.get("viewport_width", 0.0)),
			String(snapshot.get("drawer_id", "none")),
		],
	]
	var split_state_any: Variant = snapshot.get("split_offsets", {})
	if typeof(split_state_any) == TYPE_DICTIONARY:
		lines.append("Splits: " + JSON.stringify(split_state_any))
	var controls_any: Variant = snapshot.get("controls", [])
	if typeof(controls_any) == TYPE_ARRAY:
		for control_any: Variant in controls_any:
			if typeof(control_any) != TYPE_DICTIONARY:
				continue
			var control_data: Dictionary = control_any
			lines.append(
				"%s  actual=%s  minimum=%s  parent=%s  clip=%s  scroll=%s%s"
				% [
					String(control_data.get("id", "")),
					str(control_data.get("actual_size", Vector2.ZERO)),
					str(control_data.get("minimum_size", Vector2.ZERO)),
					String(control_data.get("parent", "")),
					str(bool(control_data.get("clip_contents", false))),
					String(control_data.get("scroll_owner", "none")),
					"  [color=red]OVERFLOW %s[/color]" % String(
						control_data.get("overflow_axes", "")
					)
					if bool(control_data.get("has_overflow", false))
					else "",
				]
			)
	return "\n".join(lines)


func collect_controls() -> Array[Dictionary]:
	var controls: Array[Dictionary] = []
	if not is_instance_valid(_shell_root_node):
		return controls
	var viewport_size: Vector2 = _shell_root_node.get_viewport_rect().size
	for control_id: String in TRACKED_CONTROL_IDS:
		var control_node: Control = (
			_shell_root_node
			if control_id == "WorkshopWorkspaceShell"
			else _shell_root_node.find_child(control_id, true, false) as Control
		)
		if not control_node:
			continue
		var minimum_size: Vector2 = control_node.get_combined_minimum_size()
		var parent_control_node: Control = control_node.get_parent() as Control
		var overflow_axes: String = _overflow_axes(
			control_node, parent_control_node, minimum_size, viewport_size
		)
		controls.append({
			"id": control_id,
			"actual_size": control_node.size,
			"minimum_size": minimum_size,
			"parent": (
				String(control_node.get_parent().name)
				if control_node.get_parent()
				else "none"
			),
			"clip_contents": control_node.clip_contents,
			"scroll_owner": _scroll_owner_path(control_node),
			"overflow_axes": overflow_axes,
			"has_overflow": not overflow_axes.is_empty(),
		})
	return controls


## Names the axes on which a control cannot fit, so a report distinguishes "too
## wide for the viewport" from "demands more height than it was given" — the
## latter starves whatever sits above the shell. Hidden controls are skipped:
## their sizes are stale from the last time they were laid out.
func _overflow_axes(
	control_node: Control,
	parent_control_node: Control,
	minimum_size: Vector2,
	viewport_size: Vector2
) -> String:
	if not control_node.is_visible_in_tree():
		return ""
	var axes: Array[String] = []
	var is_wider_than_parent: bool = (
		parent_control_node != null
		and control_node.size.x > parent_control_node.size.x + 0.5
	)
	if minimum_size.x > viewport_size.x + 0.5 or is_wider_than_parent:
		axes.append("width")
	var is_taller_than_parent: bool = (
		parent_control_node != null
		and control_node.size.y > parent_control_node.size.y + 0.5
	)
	if minimum_size.y > viewport_size.y + 0.5 or is_taller_than_parent:
		axes.append("height")
	return "+".join(axes)


func _scroll_owner_path(control_node: Control) -> String:
	var ancestor_node: Node = control_node.get_parent()
	while ancestor_node:
		if ancestor_node is ScrollContainer:
			return String(_shell_root_node.get_path_to(ancestor_node))
		ancestor_node = ancestor_node.get_parent()
	return "none"


func _on_toggled(is_visible: bool) -> void:
	_panel_node.visible = is_visible
	refresh()
