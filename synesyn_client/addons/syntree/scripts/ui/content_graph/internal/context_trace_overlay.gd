## Purpose: Project execution-trace inclusion states onto graph nodes.
extends RefCounted


func apply(
	graph_view: GraphEdit,
	owner_source_id: String,
	is_stack_graph: bool,
	trace: Dictionary
) -> void:
	if not is_instance_valid(graph_view):
		return
	var included_ids: Array[String] = _node_ids(
		trace.get("included_nodes", [])
	)
	var omitted_ids: Array[String] = _node_ids(
		trace.get("omitted_nodes", [])
	)
	for child in graph_view.get_children():
		if not child.has_method("set_context_trace_state"):
			continue
		var graph_node_id: String = str(child.name)
		var artifact_node_id: String = graph_node_id
		if (
			not is_stack_graph
			and not graph_node_id.contains("::")
			and not owner_source_id.is_empty()
		):
			artifact_node_id = "%s::%s" % [
				owner_source_id,
				graph_node_id,
			]
		var trace_state: String = ""
		if _matches(included_ids, graph_node_id, artifact_node_id):
			trace_state = "included"
		elif _matches(omitted_ids, graph_node_id, artifact_node_id):
			trace_state = "omitted"
		child.call("set_context_trace_state", trace_state)


func apply_diagnostic_ids(
	graph_view: GraphEdit,
	owner_source_id: String,
	is_stack_graph: bool,
	record_ids: Array[String]
) -> void:
	if not is_instance_valid(graph_view):
		return
	for child in graph_view.get_children():
		if not child.has_method("set_diagnostic_highlight"):
			continue
		var graph_node_id: String = str(child.name)
		var artifact_node_id: String = graph_node_id
		if (
			not is_stack_graph
			and not graph_node_id.contains("::")
			and not owner_source_id.is_empty()
		):
			artifact_node_id = "%s::%s" % [
				owner_source_id,
				graph_node_id,
			]
		child.call(
			"set_diagnostic_highlight",
			_matches(record_ids, graph_node_id, artifact_node_id)
		)


func _node_ids(records: Array) -> Array[String]:
	var node_ids: Array[String] = []
	for record_any in records:
		var record: Dictionary = record_any
		var node_id: String = str(record.get("node_id", ""))
		if not node_id.is_empty() and not node_ids.has(node_id):
			node_ids.append(node_id)
	return node_ids


func _matches(
	node_ids: Array[String],
	graph_node_id: String,
	artifact_node_id: String
) -> bool:
	return (
		node_ids.has(graph_node_id)
		or node_ids.has(artifact_node_id)
	)
