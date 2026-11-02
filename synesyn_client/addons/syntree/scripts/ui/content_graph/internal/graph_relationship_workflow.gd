## Purpose: Own typed relationship editing for the current graph canvas.
extends RefCounted

const GraphPersistenceCommandsScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_persistence_commands.gd"
)

var _content_state: ContentStateResource = null
var _graph_view: GraphEdit = null
var _inspector: Control = null
var _refresh_graph: Callable
var _graph_node_ids: Callable
var _is_stack: bool = false
var _source_id: String = ""
var _stack_id: String = ""
var _pending_connection: Dictionary = {}
var _legacy_commands: RefCounted = GraphPersistenceCommandsScript.new()


func setup(
	content_state: ContentStateResource,
	graph_view: GraphEdit,
	inspector: Control,
	refresh_graph: Callable,
	graph_node_ids: Callable
) -> void:
	_content_state = content_state
	_graph_view = graph_view
	_inspector = inspector
	_refresh_graph = refresh_graph
	_graph_node_ids = graph_node_ids


func set_context(
	is_stack: bool,
	source_id: String,
	stack_id: String
) -> void:
	_is_stack = is_stack
	_source_id = source_id
	_stack_id = stack_id


func connection_requested(
	from_id: String,
	from_port: int,
	to_id: String,
	to_port: int
) -> void:
	if is_instance_valid(_inspector):
		_pending_connection = {
			"from": from_id,
			"from_port": from_port,
			"to": to_id,
			"to_port": to_port,
		}
		_inspector.call("show_new_connection", from_id, to_id)


func disconnection_requested(
	from_id: String,
	from_port: int,
	to_id: String,
	to_port: int
) -> void:
	var edge_data: Dictionary = find_edge_by_endpoints(from_id, to_id)
	if is_instance_valid(_inspector) and not edge_data.is_empty():
		_graph_view.connect_node(from_id, from_port, to_id, to_port)
		_inspector.call("show_edge", edge_data)
		return
	_legacy_commands.call(
		"disconnect_nodes",
		_content_state,
		_is_stack,
		_stack_id,
		from_id,
		to_id
	)


func save(edge_data: Dictionary) -> void:
	var result: Dictionary = {}
	if _is_stack:
		result = _content_state.upsert_stack_context_graph_edge(
			_stack_id,
			edge_data,
			_graph_node_ids.call()
		)
	else:
		result = _content_state.upsert_context_graph_edge(
			_source_id,
			edge_data
		)
	if not bool(result.get("success", false)):
		push_error("Relationship save rejected: %s" % str(
			result.get("errors", [])
		))
		return
	_pending_connection.clear()
	_refresh_graph.call(_source_id)


func cancel_new() -> void:
	if _pending_connection.is_empty():
		return
	var from_id: String = str(_pending_connection.get("from", ""))
	var to_id: String = str(_pending_connection.get("to", ""))
	var from_port: int = int(_pending_connection.get("from_port", 0))
	var to_port: int = int(_pending_connection.get("to_port", 0))
	if _graph_view.is_node_connected(from_id, from_port, to_id, to_port):
		_graph_view.disconnect_node(from_id, from_port, to_id, to_port)
	_pending_connection.clear()


func create_endpoints(from_id: String, to_id: String) -> void:
	if from_id == to_id:
		return
	if not _graph_view.is_node_connected(from_id, 0, to_id, 0):
		_graph_view.connect_node(from_id, 0, to_id, 0)
	connection_requested(from_id, 0, to_id, 0)


func reverse(edge_id: String) -> void:
	var edge_data: Dictionary = find_edge_by_id(edge_id)
	if edge_data.is_empty():
		return
	var old_from_id: String = str(edge_data.get("from", ""))
	edge_data["from"] = str(edge_data.get("to", ""))
	edge_data["to"] = old_from_id
	save(edge_data)


func disconnect_edge(edge_id: String) -> void:
	var result: Dictionary = {}
	if _is_stack:
		result = _content_state.remove_stack_context_graph_edge(
			_stack_id,
			edge_id
		)
	else:
		result = _content_state.remove_context_graph_edge(_source_id, edge_id)
	if not bool(result.get("success", false)):
		push_error("Relationship disconnect failed")
		return
	_refresh_graph.call(_source_id)


func current_edges() -> Array:
	if _is_stack:
		return _content_state.get_stack_context_graph_edges(_stack_id)
	return _content_state.get_context_graph_edges(_source_id, true)


func find_edge_by_id(edge_id: String) -> Dictionary:
	for edge_any in current_edges():
		if (
			typeof(edge_any) == TYPE_DICTIONARY
			and str((edge_any as Dictionary).get("id", "")) == edge_id
		):
			return (edge_any as Dictionary).duplicate(true)
	return {}


func find_edge_by_endpoints(from_id: String, to_id: String) -> Dictionary:
	for edge_any in current_edges():
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if (
			str(edge_data.get("from", "")) == from_id
			and str(edge_data.get("to", "")) == to_id
		):
			return edge_data.duplicate(true)
	return {}
