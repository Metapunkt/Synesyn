## Purpose: Workshop-owned Columns/Graph view switching for Thinking Map.
extends RefCounted

signal manual_edge_requested(from_id: String, to_id: String, relation_id: String)

const CanvasScene = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_canvas.tscn"
)
const MapLayoutUtilsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_map_layout_utils.gd"
)

const VIEW_COLUMNS := "columns"
const VIEW_GRAPH := "graph"
## Mirrors ThinkingMapAdapter.RELATIONS with facilitator-facing labels. Kept
## as its own copy (rather than importing the adapter) so this projection
## stays a thin Columns/Graph switch with no map-semantics dependency.
const RELATION_OPTIONS: Array[Dictionary] = [
	{"relation": "causes", "label": "Causes"},
	{"relation": "supports", "label": "Supports"},
	{"relation": "contradicts", "label": "Contradicts"},
	{"relation": "evidenced_by", "label": "Evidenced by"},
	{"relation": "related_to", "label": "Related to"},
]

var _panel_node: Control
var _canvas_node: Control
var _review_callback: Callable
var _view_mode: String = VIEW_COLUMNS
var _selected_node_id: String = ""
var _selected_label_text: String = ""
var _pending_manual_edge_from: String = ""
var _pending_manual_edge_to: String = ""


func mount(panel_node: Control, review_callback: Callable) -> bool:
	_panel_node = panel_node
	_review_callback = review_callback
	if not is_instance_valid(_panel_node):
		return false
	var host_node: Control = _panel_node.get_node_or_null("%MapGraphHost") as Control
	var columns_button_node: Button = (
		_panel_node.get_node_or_null("%ColumnsViewButton") as Button
	)
	var graph_button_node: Button = (
		_panel_node.get_node_or_null("%GraphViewButton") as Button
	)
	if not host_node or not columns_button_node or not graph_button_node:
		return false
	_canvas_node = host_node.get_node_or_null("GraphWorkspaceCanvas") as Control
	if not _canvas_node:
		_canvas_node = CanvasScene.instantiate() as Control
		_canvas_node.name = "GraphWorkspaceCanvas"
		host_node.add_child(_canvas_node)
	_canvas_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _canvas_node.has_signal("node_selected"):
		_canvas_node.node_selected.connect(_on_node_selected)
	if _canvas_node.has_signal("selection_cleared"):
		_canvas_node.selection_cleared.connect(_on_selection_cleared)
	if _canvas_node.has_signal("connection_requested"):
		_canvas_node.connection_requested.connect(_on_connection_requested)
	var relation_menu_node: PopupMenu = (
		_panel_node.get_node_or_null("%ManualConnectRelationMenu") as PopupMenu
	)
	if relation_menu_node:
		relation_menu_node.clear()
		for option_index: int in range(RELATION_OPTIONS.size()):
			relation_menu_node.add_item(
				String(RELATION_OPTIONS[option_index]["label"]),
				option_index
			)
		if not relation_menu_node.id_pressed.is_connected(_on_relation_picked):
			relation_menu_node.id_pressed.connect(_on_relation_picked)
	columns_button_node.pressed.connect(set_view_mode.bind(VIEW_COLUMNS))
	graph_button_node.pressed.connect(set_view_mode.bind(VIEW_GRAPH))
	var review_buttons: Dictionary = {
		"accepted": "%GraphReviewAcceptedButton",
		"edited": "%GraphReviewEditedButton",
		"rejected": "%GraphReviewRejectedButton",
		"deferred": "%GraphReviewDeferredButton",
	}
	for action_id: String in review_buttons:
		var button_node: Button = _panel_node.get_node_or_null(
			String(review_buttons[action_id])
		) as Button
		if button_node:
			button_node.pressed.connect(_on_review_pressed.bind(action_id))
	set_view_mode(VIEW_COLUMNS)
	return true


func configure_layout_owner(session_id: String) -> void:
	if (
		is_instance_valid(_canvas_node)
		and _canvas_node.has_method("configure_layout_owner")
	):
		_canvas_node.configure_layout_owner(
			"workshop_thinking_map:%s" % session_id.strip_edges(),
			"default"
		)


func get_view_mode() -> String:
	return _view_mode


func set_view_mode(view_mode: String) -> void:
	_view_mode = (
		VIEW_GRAPH if view_mode == VIEW_GRAPH else VIEW_COLUMNS
	)
	var columns_node: Control = _panel_node.get_node_or_null("%MapColumns") as Control
	var host_node: Control = _panel_node.get_node_or_null("%MapGraphHost") as Control
	var review_node: Control = (
		_panel_node.get_node_or_null("%MapGraphReview") as Control
	)
	var relationship_node: Control = (
		_panel_node.get_node_or_null("%RelationshipStatus") as Control
	)
	var columns_button_node: Button = (
		_panel_node.get_node_or_null("%ColumnsViewButton") as Button
	)
	var graph_button_node: Button = (
		_panel_node.get_node_or_null("%GraphViewButton") as Button
	)
	if columns_node:
		columns_node.visible = _view_mode == VIEW_COLUMNS
	if host_node:
		host_node.visible = _view_mode == VIEW_GRAPH
		host_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if relationship_node:
		relationship_node.visible = _view_mode == VIEW_COLUMNS
	if review_node:
		review_node.visible = (
			_view_mode == VIEW_GRAPH and not _selected_node_id.is_empty()
		)
	if columns_button_node:
		columns_button_node.set_pressed_no_signal(_view_mode == VIEW_COLUMNS)
	if graph_button_node:
		graph_button_node.set_pressed_no_signal(_view_mode == VIEW_GRAPH)
	_request_header_banner_refit()


func refresh_document(document: Dictionary) -> void:
	if (
		is_instance_valid(_canvas_node)
		and _canvas_node.has_method("set_document")
	):
		_canvas_node.set_document(document)
	if not _selected_node_id.is_empty():
		_sync_selected_label(document)


func _on_node_selected(node_id: String) -> void:
	_selected_node_id = node_id.strip_edges()
	var review_node: Control = (
		_panel_node.get_node_or_null("%MapGraphReview") as Control
	)
	if review_node:
		review_node.visible = (
			_view_mode == VIEW_GRAPH and not _selected_node_id.is_empty()
		)
	var selected_label_node: Label = (
		_panel_node.get_node_or_null("%GraphSelectedLabel") as Label
	)
	if selected_label_node:
		selected_label_node.text = (
			"Selected: " + _selected_node_id
			if not _selected_label_text.is_empty()
			else "Selected: " + _selected_node_id
		)


func _on_selection_cleared() -> void:
	_selected_node_id = ""
	_selected_label_text = ""
	var review_node: Control = (
		_panel_node.get_node_or_null("%MapGraphReview") as Control
	)
	if review_node:
		review_node.visible = false


func _sync_selected_label(document: Dictionary) -> void:
	_selected_label_text = ""
	for node_any: Variant in document.get("nodes", []):
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		if String(node_data.get("id", "")) != _selected_node_id:
			continue
		_selected_label_text = String(node_data.get("label", "")).strip_edges()
		break
	var selected_label_node: Label = (
		_panel_node.get_node_or_null("%GraphSelectedLabel") as Label
	)
	if selected_label_node:
		if _selected_label_text.is_empty():
			selected_label_node.text = "Selected: " + _selected_node_id
		else:
			selected_label_node.text = _selected_label_text


func _on_connection_requested(from_id: String, to_id: String) -> void:
	_pending_manual_edge_from = from_id
	_pending_manual_edge_to = to_id
	var relation_menu_node: PopupMenu = (
		_panel_node.get_node_or_null("%ManualConnectRelationMenu") as PopupMenu
	)
	if relation_menu_node:
		relation_menu_node.popup_centered(Vector2i(200, 160))


func _on_relation_picked(option_id: int) -> void:
	if option_id < 0 or option_id >= RELATION_OPTIONS.size():
		return
	if _pending_manual_edge_from.is_empty() or _pending_manual_edge_to.is_empty():
		return
	var relation_id: String = String(RELATION_OPTIONS[option_id]["relation"])
	manual_edge_requested.emit(_pending_manual_edge_from, _pending_manual_edge_to, relation_id)
	_pending_manual_edge_from = ""
	_pending_manual_edge_to = ""


func _on_review_pressed(action_id: String) -> void:
	if _selected_node_id.is_empty() or not _review_callback.is_valid():
		return
	var edited_text: String = _selected_label_text
	_review_callback.call(_selected_node_id, action_id, edited_text)


func _request_header_banner_refit() -> void:
	MapLayoutUtilsScript.request_header_banner_refit(_panel_node)
