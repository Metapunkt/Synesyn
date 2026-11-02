## Purpose: Build an ordinary source canvas from deterministic source data.
extends RefCounted


func build(
	graph_view: GraphEdit,
	source_id: String,
	source_data: Dictionary,
	data_builder: RefCounted,
	renderer: RefCounted,
	create_node: Callable
) -> Dictionary:
	if not source_data.has("content") or not source_data.content.has("nodes"):
		return {"ok": false, "error": "invalid_source_data"}
	var nodes: Array = source_data.content.nodes
	var created_nodes: Dictionary = {}
	var existing_ids: Dictionary = {}
	for child in graph_view.get_children():
		if child is ContentSourceGraphNode:
			existing_ids[child.node_id] = true
	var canvas_index: int = 0
	for node_any in nodes:
		if typeof(node_any) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = node_any
		var node_id: String = str(node_data.get("node_id", ""))
		if node_id.is_empty() or existing_ids.has(node_id):
			continue
		var built: Dictionary = data_builder.call(
			"build_node_payload",
			node_id,
			source_id,
			source_data,
			node_data,
			true,
			false
		)
		var complete_data: Dictionary = built.get(
			"complete_node_data",
			node_data.duplicate()
		)
		var graph_node: GraphNode = create_node.call(complete_data)
		if not is_instance_valid(graph_node):
			continue
		var canvas_point: Vector2 = Vector2(
			80 + (canvas_index % 6) * 420,
			80 + int(canvas_index / 6) * 240
		)
		var legacy_point_any: Variant = node_data.get("position", null)
		if legacy_point_any is Vector2:
			canvas_point = legacy_point_any
		elif legacy_point_any is Dictionary:
			var legacy_point: Dictionary = legacy_point_any
			canvas_point = Vector2(
				float(legacy_point.get("x", 0.0)),
				float(legacy_point.get("y", 0.0))
			)
		elif legacy_point_any is Array and legacy_point_any.size() >= 2:
			canvas_point = Vector2(
				float(legacy_point_any[0]),
				float(legacy_point_any[1])
			)
		renderer.call(
			"add_node_to_graph",
			graph_view,
			graph_node,
			canvas_point,
			bool(built.get("is_active", false)),
			bool(built.get("is_metaprompt", false))
		)
		created_nodes[node_id] = graph_node
		existing_ids[node_id] = true
		canvas_index += 1
	renderer.call("connect_children_edges", graph_view, created_nodes, nodes)
	var rich_edges_any: Variant = source_data.get("content", {}).get(
		"context_graph_edges",
		[]
	)
	if typeof(rich_edges_any) == TYPE_ARRAY:
		renderer.call(
			"connect_typed_edges",
			graph_view,
			created_nodes,
			rich_edges_any
		)
	if not created_nodes.is_empty():
		graph_view.scroll_offset = Vector2.ZERO
	return {"ok": true, "created_nodes": created_nodes}
