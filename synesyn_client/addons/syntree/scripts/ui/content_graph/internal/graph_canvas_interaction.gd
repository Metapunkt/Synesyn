## Purpose: Own transient visibility, framing, and local canvas layout state.
extends RefCounted

var _graph_view: GraphEdit = null
var _source_id: String = ""
var _is_stack: bool = false


func setup(graph_view: GraphEdit) -> void:
	_graph_view = graph_view


func set_context(source_id: String, is_stack: bool) -> void:
	_source_id = source_id
	_is_stack = is_stack


func apply_focus_filter(result: Dictionary) -> void:
	var visible_ids: Array = result.get("visible_node_ids", [])
	for child in _graph_view.get_children():
		if not child is GraphNode:
			continue
		var graph_node_id: String = str(child.name)
		var artifact_node_id: String = graph_node_id
		if (
			not _is_stack
			and not graph_node_id.contains("::")
			and not _source_id.is_empty()
		):
			artifact_node_id = "%s::%s" % [_source_id, graph_node_id]
		child.visible = (
			visible_ids.has(graph_node_id)
			or visible_ids.has(artifact_node_id)
		)
	_graph_view.queue_redraw()


func reset_focus_filter() -> void:
	for child in _graph_view.get_children():
		if child is GraphNode:
			child.visible = true
	_graph_view.queue_redraw()


func fit_relevant_context() -> void:
	if _graph_view.has_method("fit_visible_nodes"):
		_graph_view.call("fit_visible_nodes")


func capture_layout() -> Dictionary:
	var positions: Dictionary = {}
	for child in _graph_view.get_children():
		if child is GraphNode:
			positions[str(child.name)] = {
				"x": child.position_offset.x,
				"y": child.position_offset.y,
			}
	return {
		"node_positions": positions,
		"viewport": {
			"scroll_x": _graph_view.scroll_offset.x,
			"scroll_y": _graph_view.scroll_offset.y,
			"zoom": _graph_view.zoom,
		},
	}


func apply_layout(layout_data: Dictionary) -> void:
	var positions: Dictionary = layout_data.get("node_positions", {})
	for child in _graph_view.get_children():
		if not child is GraphNode or not positions.has(str(child.name)):
			continue
		var point: Dictionary = positions.get(str(child.name), {})
		child.position_offset = Vector2(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0))
		)
	var viewport_data: Dictionary = layout_data.get("viewport", {})
	_graph_view.zoom = clampf(
		float(viewport_data.get("zoom", 1.0)),
		0.1,
		4.0
	)
	_graph_view.scroll_offset = Vector2(
		float(viewport_data.get("scroll_x", 0.0)),
		float(viewport_data.get("scroll_y", 0.0))
	)
