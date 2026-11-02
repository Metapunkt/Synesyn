## Purpose: Incrementally mutate a large GraphEdit canvas on the main thread.
extends Node

signal source_render_completed(generation: int, result: Dictionary)

const DEFAULT_BATCH_SIZE: int = 24

var _job: Dictionary = {}


func begin_source_render(
	graph_view: GraphEdit,
	source_id: String,
	source_data: Dictionary,
	data_builder: RefCounted,
	renderer: RefCounted,
	create_node: Callable,
	generation: int,
	batch_size: int = DEFAULT_BATCH_SIZE
) -> void:
	cancel()
	var nodes_any: Variant = source_data.get("content", {}).get(
		"nodes",
		[]
	)
	if typeof(nodes_any) != TYPE_ARRAY:
		source_render_completed.emit(
			generation,
			{"ok": false, "error": "invalid_source_data"}
		)
		return
	var existing_ids: Dictionary = {}
	for child_node in graph_view.get_children():
		if child_node is ContentSourceGraphNode:
			existing_ids[child_node.node_id] = true
	_job = {
		"graph_view": graph_view,
		"source_id": source_id,
		"source_data": source_data,
		"nodes": (nodes_any as Array).duplicate(true),
		"data_builder": data_builder,
		"renderer": renderer,
		"create_node": create_node,
		"generation": generation,
		"batch_size": maxi(1, batch_size),
		"next_index": 0,
		"canvas_index": 0,
		"created_nodes": {},
		"existing_ids": existing_ids,
	}
	set_process(true)


func cancel() -> void:
	_job.clear()
	set_process(false)


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if _job.is_empty():
		set_process(false)
		return
	var graph_view: GraphEdit = _job.get("graph_view")
	if not is_instance_valid(graph_view):
		cancel()
		return
	var nodes: Array = _job.get("nodes", [])
	var processed_count: int = 0
	while (
		int(_job.get("next_index", 0)) < nodes.size()
		and processed_count < int(_job.get("batch_size", DEFAULT_BATCH_SIZE))
	):
		var node_index: int = int(_job.get("next_index", 0))
		_job["next_index"] = node_index + 1
		processed_count += 1
		_render_record(nodes[node_index])
	if int(_job.get("next_index", 0)) < nodes.size():
		return
	_finish_job()


func _render_record(node_any: Variant) -> void:
	if typeof(node_any) != TYPE_DICTIONARY:
		return
	var node_data: Dictionary = node_any
	var node_id: String = str(node_data.get("node_id", ""))
	var existing_ids: Dictionary = _job.get("existing_ids", {})
	if node_id.is_empty() or existing_ids.has(node_id):
		return
	var data_builder: RefCounted = _job.get("data_builder")
	var built: Dictionary = data_builder.call(
		"build_node_payload",
		node_id,
		str(_job.get("source_id", "")),
		_job.get("source_data", {}),
		node_data,
		true,
		false
	)
	var complete_data: Dictionary = built.get(
		"complete_node_data",
		node_data.duplicate()
	)
	var create_node: Callable = _job.get("create_node")
	var graph_node: GraphNode = create_node.call(complete_data)
	if not is_instance_valid(graph_node):
		return
	var canvas_index: int = int(_job.get("canvas_index", 0))
	var canvas_point: Vector2 = Vector2(
		80 + (canvas_index % 6) * 420,
		80 + int(canvas_index / 6) * 240
	)
	var stored_point: Variant = node_data.get("position", null)
	if stored_point is Vector2:
		canvas_point = stored_point
	elif stored_point is Dictionary:
		canvas_point = Vector2(
			float((stored_point as Dictionary).get("x", 0.0)),
			float((stored_point as Dictionary).get("y", 0.0))
		)
	var renderer: RefCounted = _job.get("renderer")
	renderer.call(
		"add_node_to_graph",
		_job.get("graph_view"),
		graph_node,
		canvas_point,
		bool(built.get("is_active", false)),
		bool(built.get("is_metaprompt", false))
	)
	var created_nodes: Dictionary = _job.get("created_nodes", {})
	created_nodes[node_id] = graph_node
	existing_ids[node_id] = true
	_job["canvas_index"] = canvas_index + 1


func _finish_job() -> void:
	var graph_view: GraphEdit = _job.get("graph_view")
	var renderer: RefCounted = _job.get("renderer")
	var created_nodes: Dictionary = _job.get("created_nodes", {})
	var nodes: Array = _job.get("nodes", [])
	renderer.call(
		"connect_children_edges",
		graph_view,
		created_nodes,
		nodes
	)
	var source_data: Dictionary = _job.get("source_data", {})
	var rich_edges: Variant = source_data.get("content", {}).get(
		"context_graph_edges",
		[]
	)
	if typeof(rich_edges) == TYPE_ARRAY:
		renderer.call(
			"connect_typed_edges",
			graph_view,
			created_nodes,
			rich_edges
		)
	if not created_nodes.is_empty():
		graph_view.scroll_offset = Vector2.ZERO
	var generation: int = int(_job.get("generation", 0))
	var result: Dictionary = {
		"ok": true,
		"created_nodes": created_nodes,
	}
	cancel()
	source_render_completed.emit(generation, result)
