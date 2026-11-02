@tool
extends RefCounted


## Routes Context Graph node selection without making the view own source state.
func select_node(
	content_state: Object,
	view_state: Object,
	node_id: String,
	source_id: String,
	is_stack_graph: bool
) -> void:
	if not is_stack_graph and not source_id.is_empty() and is_instance_valid(view_state):
		if view_state.has_method("select_source"):
			view_state.call("select_source", source_id, true)

	if is_instance_valid(content_state) and content_state.has_method("select_node"):
		content_state.call("select_node", node_id)
