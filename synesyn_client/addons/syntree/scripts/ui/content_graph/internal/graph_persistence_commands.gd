## Purpose: Route Context Graph layout and connection edits to ContentStateResource.
##
## This is a SynTree adapter helper, not part of the shared Graph Workspace.
## It preserves legacy child-edge behavior until typed relationship selection is
## introduced by the Context Graph implementation plan.
extends RefCounted


func persist_node_position(
	content_state: Object,
	is_stack_mode: bool,
	stack_id: String,
	node_id: String,
	node_position: Vector2
) -> bool:
	if not is_instance_valid(content_state):
		return false
	if is_stack_mode:
		if stack_id.is_empty() or not content_state.has_method(
			"set_stack_layout_position"
		):
			return false
		return bool(content_state.call(
			"set_stack_layout_position",
			stack_id,
			node_id,
			node_position
		))
	if not content_state.has_method("update_node_position"):
		return false
	return bool(content_state.call(
		"update_node_position",
		node_id,
		node_position
	))


func connect_nodes(
	content_state: Object,
	is_stack_mode: bool,
	stack_id: String,
	from_id: String,
	to_id: String
) -> bool:
	if not is_instance_valid(content_state):
		return false
	if is_stack_mode:
		return _connect_stack_nodes(content_state, stack_id, from_id, to_id)
	if content_state.has_method("add_edge"):
		return bool(content_state.call("add_edge", "child", from_id, to_id))
	if content_state.has_method("add_relationship"):
		return bool(content_state.call("add_relationship", from_id, to_id))
	return false


func disconnect_nodes(
	content_state: Object,
	is_stack_mode: bool,
	stack_id: String,
	from_id: String,
	to_id: String
) -> bool:
	if not is_instance_valid(content_state):
		return false
	if is_stack_mode:
		return _disconnect_stack_nodes(content_state, stack_id, from_id, to_id)
	if content_state.has_method("remove_edge"):
		return bool(content_state.call("remove_edge", "child", from_id, to_id))
	if content_state.has_method("remove_relationship"):
		return bool(content_state.call("remove_relationship", from_id, to_id))
	return false


func _connect_stack_nodes(
	content_state: Object,
	stack_id: String,
	from_id: String,
	to_id: String
) -> bool:
	if stack_id.is_empty():
		return false
	if content_state.has_method("add_stack_edge"):
		return bool(content_state.call(
			"add_stack_edge",
			stack_id,
			from_id,
			to_id
		))
	if not content_state.has_method("get_stack_edges") or not content_state.has_method(
		"set_stack_edges"
	):
		return false
	var edges: Array = content_state.call("get_stack_edges", stack_id)
	for edge_any in edges:
		if edge_any is Dictionary:
			var edge_data: Dictionary = edge_any
			if (
				str(edge_data.get("from", "")) == from_id
				and str(edge_data.get("to", "")) == to_id
			):
				return true
	edges.append({"from": from_id, "to": to_id})
	return bool(content_state.call("set_stack_edges", stack_id, edges))


func _disconnect_stack_nodes(
	content_state: Object,
	stack_id: String,
	from_id: String,
	to_id: String
) -> bool:
	if stack_id.is_empty():
		return false
	if content_state.has_method("remove_stack_edge"):
		return bool(content_state.call(
			"remove_stack_edge",
			stack_id,
			from_id,
			to_id
		))
	if not content_state.has_method("get_stack_edges") or not content_state.has_method(
		"set_stack_edges"
	):
		return false
	var edges: Array = content_state.call("get_stack_edges", stack_id)
	var kept_edges: Array = []
	for edge_any in edges:
		if edge_any is Dictionary:
			var edge_data: Dictionary = edge_any
			if (
				str(edge_data.get("from", "")) == from_id
				and str(edge_data.get("to", "")) == to_id
			):
				continue
		kept_edges.append(edge_any)
	return bool(content_state.call("set_stack_edges", stack_id, kept_edges))
