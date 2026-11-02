## Purpose: Domain-neutral GraphEdit projection for GraphWorkspaceDocument.
##
## Renders nodes/typed edges, selection, and named layout persistence.
## Product adapters own semantics, review actions, and artifact contracts.
extends Control

signal node_selected(node_id: String)
signal selection_cleared
signal layout_changed(canvas_state: Dictionary)
## Facilitator dragged a connection between two nodes. The canvas only reports
## the two workspace node ids — it has no notion of relation types or review
## semantics. The product adapter/controller decides what (if anything) to do
## with the request (see ADR 0008: mechanics are shared, ontology is not).
signal connection_requested(from_node_id: String, to_node_id: String)

const LayoutStoreScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_layout_store.gd"
)
const CanvasNodeScene = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_canvas_node.tscn"
)

const DEFAULT_COLUMN_X: Dictionary = {
	"cause": 40.0,
	"effect": 320.0,
	"opportunity": 600.0,
}
const DEFAULT_ROW_STEP := 130.0
## Frame tint rotation for successive groups (e.g. stage/turn clusters).
## Purely cosmetic — grouping semantics belong to the product adapter.
const _GROUP_TINTS: Array[Color] = [
	Color(0.28, 0.36, 0.48, 0.35),
	Color(0.46, 0.36, 0.24, 0.35),
	Color(0.26, 0.42, 0.34, 0.35),
	Color(0.40, 0.30, 0.46, 0.35),
]
## A group needs at least this many members before a frame is worth drawing;
## a one-node "cluster" is just visual noise.
const _MIN_GROUP_SIZE := 2

var _graph_edit_node: GraphEdit
var _layout_store: RefCounted = LayoutStoreScript.new()
var _layout_owner_id: String = ""
var _layout_label: String = "default"
var _selected_node_id: String = ""
var _is_applying_document: bool = false
var _node_count_by_kind: Dictionary = {}


func _ready() -> void:
	_graph_edit_node = get_node_or_null("GraphEdit") as GraphEdit
	if not _graph_edit_node:
		return
	_graph_edit_node.connection_request.connect(_on_connection_request)
	_graph_edit_node.disconnection_request.connect(_on_disconnection_request)
	_graph_edit_node.node_selected.connect(_on_graph_node_selected)
	_graph_edit_node.node_deselected.connect(_on_graph_node_deselected)
	_graph_edit_node.end_node_move.connect(_on_end_node_move)


func configure_layout_owner(owner_id: String, layout_label: String = "default") -> void:
	_layout_owner_id = owner_id.strip_edges()
	_layout_label = layout_label.strip_edges()
	if _layout_label.is_empty():
		_layout_label = "default"


func get_selected_node_id() -> String:
	return _selected_node_id


func clear_canvas() -> void:
	if not _graph_edit_node:
		return
	_graph_edit_node.clear_connections()
	for child_node: Node in _graph_edit_node.get_children():
		if child_node is GraphNode or child_node is GraphFrame:
			child_node.queue_free()
	_selected_node_id = ""
	_node_count_by_kind.clear()


func set_document(document: Dictionary) -> void:
	if not _graph_edit_node:
		return
	_is_applying_document = true
	clear_canvas()
	var positions: Dictionary = _load_positions()
	_node_count_by_kind.clear()
	var nodes_any: Variant = document.get("nodes", [])
	if typeof(nodes_any) != TYPE_ARRAY:
		_is_applying_document = false
		return
	var group_members: Dictionary = {}
	for node_any: Variant in nodes_any:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any as Dictionary
		var node_name: String = _add_node(node_data, positions)
		if node_name.is_empty():
			continue
		_track_group_membership(group_members, node_data, node_name)
	var edges_any: Variant = document.get("edges", [])
	if typeof(edges_any) == TYPE_ARRAY:
		for edge_any: Variant in edges_any:
			if typeof(edge_any) != TYPE_DICTIONARY:
				continue
			_add_edge(edge_any as Dictionary)
	_apply_groups(group_members)
	_is_applying_document = false


func capture_canvas_state() -> Dictionary:
	var node_positions: Dictionary = {}
	if _graph_edit_node:
		for child_node: Node in _graph_edit_node.get_children():
			if not (child_node is GraphNode):
				continue
			var workspace_node_id: String = String(
				child_node.get("workspace_node_id")
			).strip_edges()
			if workspace_node_id.is_empty():
				continue
			var offset: Vector2 = (child_node as GraphNode).position_offset
			node_positions[workspace_node_id] = {
				"x": offset.x,
				"y": offset.y,
			}
	var viewport_state: Dictionary = {
		"scroll_x": 0.0,
		"scroll_y": 0.0,
		"zoom": 1.0,
	}
	if _graph_edit_node:
		viewport_state = {
			"scroll_x": _graph_edit_node.scroll_offset.x,
			"scroll_y": _graph_edit_node.scroll_offset.y,
			"zoom": _graph_edit_node.zoom,
		}
	return {
		"node_positions": node_positions,
		"viewport": viewport_state,
	}


func persist_layout() -> Dictionary:
	if _layout_owner_id.is_empty():
		return {"ok": false, "error": "layout_owner_required"}
	var canvas_state: Dictionary = capture_canvas_state()
	var result: Dictionary = _layout_store.save_layout(
		_layout_owner_id,
		_layout_label,
		canvas_state
	)
	if bool(result.get("ok", false)):
		layout_changed.emit(canvas_state)
	return result


func _add_node(node_data: Dictionary, positions: Dictionary) -> String:
	var node_id: String = String(node_data.get("id", "")).strip_edges()
	if node_id.is_empty() or not _graph_edit_node:
		return ""
	var canvas_node: GraphNode = CanvasNodeScene.instantiate() as GraphNode
	if not canvas_node:
		return ""
	canvas_node.name = _safe_node_name(node_id)
	if canvas_node.has_method("configure"):
		canvas_node.call("configure", node_data)
	var kind_text: String = String(node_data.get("kind", "")).strip_edges()
	var kind_index: int = int(_node_count_by_kind.get(kind_text, 0))
	_node_count_by_kind[kind_text] = kind_index + 1
	# NOTE: default must be a non-Dictionary sentinel. An empty Dictionary `{}`
	# default would itself satisfy `typeof(...) == TYPE_DICTIONARY` below, so
	# every node missing a saved position collapsed onto the same (0,0) point
	# instead of falling through to its staggered per-kind default.
	var position_any: Variant = positions.get(node_id, null)
	if typeof(position_any) == TYPE_DICTIONARY and (position_any as Dictionary).has("x"):
		var point: Dictionary = position_any
		canvas_node.position_offset = Vector2(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0))
		)
	else:
		canvas_node.position_offset = _default_position(kind_text, kind_index)
	_graph_edit_node.add_child(canvas_node)
	return String(canvas_node.name)


## Generic clustering mechanic: any node whose annotations carry a
## "group_key" is clustered with every other node sharing that same key,
## titled from "group_label" (falling back to the key itself). The canvas has
## no opinion on what a group_key means semantically — that is entirely the
## product adapter's call (e.g. Workshop Catalyst uses "stage:<name>").
func _track_group_membership(
	group_members: Dictionary,
	node_data: Dictionary,
	node_name: String
) -> void:
	var annotations_any: Variant = node_data.get("annotations", {})
	if typeof(annotations_any) != TYPE_DICTIONARY:
		return
	var annotations: Dictionary = annotations_any
	var group_key: String = String(annotations.get("group_key", "")).strip_edges()
	if group_key.is_empty():
		return
	if not group_members.has(group_key):
		group_members[group_key] = {
			"label": String(annotations.get("group_label", group_key)).strip_edges(),
			"node_names": [],
		}
	(group_members[group_key]["node_names"] as Array).append(node_name)


func _apply_groups(group_members: Dictionary) -> void:
	if not _graph_edit_node:
		return
	var group_index: int = 0
	for group_key_any: Variant in group_members:
		var group_data: Dictionary = group_members[group_key_any]
		var node_names: Array = group_data.get("node_names", [])
		if node_names.size() < _MIN_GROUP_SIZE:
			group_index += 1
			continue
		var frame_node := GraphFrame.new()
		frame_node.name = _safe_frame_name(String(group_key_any))
		frame_node.title = String(group_data.get("label", group_key_any))
		frame_node.autoshrink_enabled = true
		frame_node.tint_color_enabled = true
		frame_node.tint_color = _GROUP_TINTS[group_index % _GROUP_TINTS.size()]
		_graph_edit_node.add_child(frame_node)
		var frame_name := StringName(frame_node.name)
		for node_name_any: Variant in node_names:
			_graph_edit_node.attach_graph_element_to_frame(
				StringName(String(node_name_any)),
				frame_name
			)
		_add_collapse_toggle(frame_node, node_names)
		group_index += 1


## GraphFrame does not natively support collapsing its members (as of Godot
## 4.7), so this adds a small toggle to the frame's own titlebar that hides
## the member GraphNodes — a literal "collapse this stage's cluster" affordance.
func _add_collapse_toggle(frame_node: GraphFrame, node_names: Array) -> void:
	var titlebar_node: HBoxContainer = frame_node.get_titlebar_hbox()
	if not titlebar_node:
		return
	var toggle_button := CheckButton.new()
	toggle_button.text = "Collapse"
	toggle_button.button_pressed = false
	var member_names: Array = node_names.duplicate()
	toggle_button.toggled.connect(_on_group_collapse_toggled.bind(member_names))
	titlebar_node.add_child(toggle_button)


func _on_group_collapse_toggled(is_collapsed: bool, member_names: Array) -> void:
	if not _graph_edit_node:
		return
	for node_name_any: Variant in member_names:
		var member_node: Node = _graph_edit_node.get_node_or_null(
			NodePath(String(node_name_any))
		)
		if member_node:
			member_node.visible = not is_collapsed


func _safe_frame_name(group_key: String) -> String:
	return "gwf_" + group_key.replace("/", "_").replace(":", "_").replace(" ", "_")


func _add_edge(edge_data: Dictionary) -> void:
	if not _graph_edit_node:
		return
	var from_id: String = String(edge_data.get("from", "")).strip_edges()
	var to_id: String = String(edge_data.get("to", "")).strip_edges()
	if from_id.is_empty() or to_id.is_empty():
		return
	var from_name: String = _safe_node_name(from_id)
	var to_name: String = _safe_node_name(to_id)
	if (
		not _graph_edit_node.has_node(NodePath(from_name))
		or not _graph_edit_node.has_node(NodePath(to_name))
	):
		return
	_graph_edit_node.connect_node(from_name, 0, to_name, 0)


func _default_position(kind_text: String, kind_index: int) -> Vector2:
	var column_x: float = float(DEFAULT_COLUMN_X.get(kind_text, 880.0))
	return Vector2(column_x, 40.0 + float(kind_index) * DEFAULT_ROW_STEP)


func _load_positions() -> Dictionary:
	if _layout_owner_id.is_empty():
		return {}
	var layouts: Array[Dictionary] = _layout_store.list_layouts(_layout_owner_id)
	for layout_data: Dictionary in layouts:
		if String(layout_data.get("label", "")) != _layout_label:
			continue
		var positions_any: Variant = layout_data.get("node_positions", {})
		if typeof(positions_any) == TYPE_DICTIONARY:
			return positions_any
	return {}


func _safe_node_name(node_id: String) -> String:
	return "gw_" + node_id.replace("/", "_").replace(":", "_").replace(" ", "_")


func _on_connection_request(
	from_node: StringName,
	_from_port: int,
	to_node: StringName,
	_to_port: int
) -> void:
	# The canvas never draws the connection itself: it only reports the
	# request. The document redraws the edge (or doesn't) once the adapter
	# decides and the resulting document flows back through set_document().
	var from_id: String = _workspace_node_id_for(from_node)
	var to_id: String = _workspace_node_id_for(to_node)
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return
	connection_requested.emit(from_id, to_id)


func _workspace_node_id_for(node_name: StringName) -> String:
	if not _graph_edit_node:
		return ""
	var target_node: Node = _graph_edit_node.get_node_or_null(NodePath(String(node_name)))
	if not target_node:
		return ""
	return String(target_node.get("workspace_node_id")).strip_edges()


func _on_disconnection_request(
	_from_node: StringName,
	_from_port: int,
	_to_node: StringName,
	_to_port: int
) -> void:
	pass


func _on_graph_node_selected(node: Node) -> void:
	if not (node is GraphNode):
		return
	_selected_node_id = String(node.get("workspace_node_id")).strip_edges()
	if _selected_node_id.is_empty():
		return
	node_selected.emit(_selected_node_id)


func _on_graph_node_deselected(_node: Node) -> void:
	_selected_node_id = ""
	selection_cleared.emit()


func _on_end_node_move() -> void:
	if _is_applying_document:
		return
	persist_layout()
