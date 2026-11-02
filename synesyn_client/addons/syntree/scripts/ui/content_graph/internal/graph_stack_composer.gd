## Purpose: Compose a stack's member-source nodes onto the Context Graph canvas.
##
## The controller retains signal ownership and supplies the node factory.
## This collaborator owns stack read/composition orchestration only.
@tool
class_name GraphStackComposer
extends RefCounted


func build_stack_graph(
	content_state: ContentStateResource,
	graph_view: GraphEdit,
	stack_id: String,
	data_builder: GraphDataBuilder,
	renderer: GraphRenderer,
	create_node_fn: Callable
) -> Dictionary:
	if not is_instance_valid(content_state) or not is_instance_valid(graph_view):
		return {}
	if not create_node_fn.is_valid():
		return {}

	var member_ids: Array[String] = []
	if content_state.has_method("get_stack_member_source_ids"):
		member_ids = content_state.get_stack_member_source_ids(stack_id)
	var layout_positions: Dictionary = {}
	if content_state.has_method("get_stack_layout_positions"):
		layout_positions = content_state.get_stack_layout_positions(stack_id)
	var edges: Array = []
	var has_typed_edges: bool = content_state.has_method(
		"get_stack_context_graph_edges"
	)
	if has_typed_edges:
		edges = content_state.get_stack_context_graph_edges(stack_id)
	elif content_state.has_method("get_stack_edges"):
		edges = content_state.get_stack_edges(stack_id)

	var created_nodes: Dictionary = {}
	var node_index: int = 0
	for member_id in member_ids:
		var source_data: Dictionary = content_state.get_source_data(member_id)
		if source_data.is_empty():
			continue
		var nodes_any: Variant = source_data.get("content", {}).get("nodes", [])
		if typeof(nodes_any) != TYPE_ARRAY:
			continue
		for node_any in (nodes_any as Array):
			if typeof(node_any) != TYPE_DICTIONARY:
				continue
			var node_data: Dictionary = node_any
			var raw_node_id: String = str(
				node_data.get("node_id", "")
			).strip_edges()
			if raw_node_id.is_empty():
				continue
			var composed_id: String = _make_composed_id(
				content_state,
				member_id,
				raw_node_id
			)
			if created_nodes.has(composed_id):
				continue

			var complete_node_data: Dictionary = node_data.duplicate(true)
			complete_node_data["node_id"] = composed_id
			var built: Dictionary = {}
			if is_instance_valid(data_builder):
				built = data_builder.build_node_payload(
					composed_id,
					member_id,
					source_data,
					node_data,
					false,
					true
				)
			var enriched: Dictionary = built.get(
				"complete_node_data",
				complete_node_data
			)
			var is_active: bool = bool(built.get("is_active", false))
			var is_metaprompt: bool = bool(
				built.get("is_metaprompt", false)
			)
			var graph_node_any: Variant = create_node_fn.call(enriched)
			if not is_instance_valid(graph_node_any):
				continue
			var graph_node: GraphNode = graph_node_any
			var node_position: Vector2 = _resolve_position(
				layout_positions,
				composed_id,
				node_index
			)
			if is_instance_valid(renderer):
				renderer.add_node_to_graph(
					graph_view,
					graph_node,
					node_position,
					is_active,
					is_metaprompt
				)
			else:
				_add_node_fallback(
					graph_view,
					graph_node,
					node_position,
					is_active,
					is_metaprompt
				)
			created_nodes[composed_id] = graph_node
			node_index += 1

	if is_instance_valid(renderer):
		if has_typed_edges:
			renderer.connect_typed_edges(graph_view, created_nodes, edges)
		else:
			renderer.connect_stack_edges(graph_view, created_nodes, edges)
	else:
		_connect_edges_fallback(graph_view, created_nodes, edges)
	if not created_nodes.is_empty():
		graph_view.scroll_offset = Vector2.ZERO
	return created_nodes


func _make_composed_id(
	content_state: ContentStateResource,
	source_id: String,
	node_id: String
) -> String:
	if content_state.has_method("make_composed_node_id"):
		return content_state.make_composed_node_id(source_id, node_id)
	return "%s__%s" % [source_id, node_id]


func _resolve_position(
	layout_positions: Dictionary,
	composed_id: String,
	node_index: int
) -> Vector2:
	var node_position := Vector2(
		80 + (node_index % 6) * 420,
		80 + int(node_index / 6) * 240
	)
	if not layout_positions.has(composed_id):
		return node_position
	var stored_position: Variant = layout_positions[composed_id]
	if stored_position is Vector2:
		return stored_position
	if (
		stored_position is Dictionary
		and stored_position.has("x")
		and stored_position.has("y")
	):
		return Vector2(
			float(stored_position.get("x")),
			float(stored_position.get("y"))
		)
	return node_position


func _add_node_fallback(
	graph_view: GraphEdit,
	graph_node: GraphNode,
	node_position: Vector2,
	is_active: bool,
	is_metaprompt: bool
) -> void:
	if graph_node.get_parent() != graph_view:
		graph_view.add_child(graph_node)
	graph_node.position_offset = node_position
	if graph_node is ContentSourceGraphNode:
		graph_node.set_active_state(is_active)
		graph_node.set_metaprompt_state(is_metaprompt)


func _connect_edges_fallback(
	graph_view: GraphEdit,
	created_nodes: Dictionary,
	edges: Array
) -> void:
	for edge_any in edges:
		if not edge_any is Dictionary:
			continue
		var edge_data: Dictionary = edge_any
		var from_id: String = str(edge_data.get("from", "")).strip_edges()
		var to_id: String = str(edge_data.get("to", "")).strip_edges()
		if (
			from_id.is_empty()
			or to_id.is_empty()
			or not created_nodes.has(from_id)
			or not created_nodes.has(to_id)
		):
			continue
		graph_view.connect_node(
			created_nodes[from_id].name,
			0,
			created_nodes[to_id].name,
			0
		)
