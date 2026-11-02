## Purpose: Own graph-node state toggles and deletion commands.
extends RefCounted

var _content_state: ContentStateResource = null
var _graph_view: GraphEdit = null
var _host: Node = null
var _resolve_source: Callable
var _get_graph_nodes: Callable
var _refresh_graph: Callable
var _is_stack: bool = false
var _stack_id: String = ""


func setup(
	content_state: ContentStateResource,
	graph_view: GraphEdit,
	host: Node,
	resolve_source: Callable,
	get_graph_nodes: Callable,
	refresh_graph: Callable
) -> void:
	_content_state = content_state
	_graph_view = graph_view
	_host = host
	_resolve_source = resolve_source
	_get_graph_nodes = get_graph_nodes
	_refresh_graph = refresh_graph


func set_context(is_stack: bool, stack_id: String) -> void:
	_is_stack = is_stack
	_stack_id = stack_id


func update_active_source(source_id: String, is_active: bool) -> void:
	if not is_instance_valid(_content_state):
		return
	var normalized_id: String = _content_state.get_normalized_id(source_id)
	for graph_node in _graph_view.get_children():
		if not graph_node is ContentSourceGraphNode:
			continue
		var node_source_id: String = _content_state.get_source_for_node(
			graph_node.node_id
		)
		if (
			not node_source_id.is_empty()
			and _content_state.get_normalized_id(node_source_id) == normalized_id
		):
			graph_node.set_active_state(is_active)


func update_metaprompt_source(
	source_id: String,
	is_metaprompt: bool
) -> void:
	if not is_instance_valid(_content_state):
		return
	var normalized_id: String = _content_state.get_normalized_id(source_id)
	for graph_node in _graph_view.get_children():
		if not graph_node is ContentSourceGraphNode:
			continue
		var node_source_id: String = _content_state.get_source_for_node(
			graph_node.node_id
		)
		if (
			not node_source_id.is_empty()
			and _content_state.get_normalized_id(node_source_id) == normalized_id
		):
			graph_node.set_metaprompt_state(is_metaprompt)


func toggle_active(node_id: String, is_active: bool) -> void:
	var source_id: String = _resolve_source.call(node_id)
	if source_id.is_empty():
		return
	var normalized_id: String = _content_state.get_normalized_id(source_id)
	if normalized_id.is_empty():
		normalized_id = source_id
	if not _content_state.set_source_active_state(normalized_id, is_active):
		push_error("Failed to set Active state: %s" % normalized_id)
		return
	for graph_node_any in _get_graph_nodes.call():
		if graph_node_any is ContentSourceGraphNode:
			var graph_source_id: String = _content_state.get_normalized_id(
				_resolve_source.call(graph_node_any.node_id)
			)
			if graph_source_id == normalized_id:
				graph_node_any.set_active_state(is_active)


func toggle_metaprompt(node_id: String, is_metaprompt: bool) -> void:
	var source_id: String = _resolve_source.call(node_id)
	if source_id.is_empty():
		return
	var normalized_id: String = _content_state.get_normalized_id(source_id)
	if normalized_id.is_empty():
		normalized_id = source_id
	if not _content_state.set_metaprompt_state(normalized_id, is_metaprompt):
		push_error("Failed to set Metaprompt state: %s" % normalized_id)
		return
	for graph_node_any in _get_graph_nodes.call():
		if graph_node_any is ContentSourceGraphNode:
			var graph_source_id: String = _content_state.get_normalized_id(
				_resolve_source.call(graph_node_any.node_id)
			)
			if graph_source_id == normalized_id:
				graph_node_any.set_metaprompt_state(is_metaprompt)


func request_delete(node_id: String) -> void:
	var target: Dictionary = _deletion_target(node_id)
	if target.is_empty():
		return
	var confirm_dialog: ConfirmationDialog = ConfirmationDialog.new()
	confirm_dialog.title = "Confirm Node Deletion"
	confirm_dialog.ok_button_text = "Delete"
	confirm_dialog.cancel_button_text = "Cancel"
	confirm_dialog.dialog_text = (
		"Delete this node?\n\nNode: %s\nSource: %s\n\nThis cannot be undone."
		% [str(target.get("node_id", "")), str(target.get("source_id", ""))]
	)
	confirm_dialog.confirmed.connect(func() -> void:
		delete_node(node_id)
		confirm_dialog.queue_free()
	)
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	_host.add_child(confirm_dialog)
	confirm_dialog.popup_centered()


func delete_node(node_id: String) -> void:
	var target: Dictionary = _deletion_target(node_id)
	if target.is_empty():
		return
	var source_id: String = str(target.get("source_id", ""))
	var raw_node_id: String = str(target.get("node_id", ""))
	if not _content_state.remove_node_from_source(source_id, raw_node_id):
		return
	_refresh_graph.call(_stack_id if _is_stack else source_id)


func _deletion_target(node_id: String) -> Dictionary:
	var normalized_node_id: String = node_id.strip_edges()
	if normalized_node_id.is_empty():
		return {}
	var parsed: Dictionary = _content_state.parse_composed_node_id(
		normalized_node_id
	)
	var source_id: String = ""
	var raw_node_id: String = normalized_node_id
	if bool(parsed.get("is_composed", false)):
		source_id = str(parsed.get("source_id", "")).strip_edges()
		raw_node_id = str(parsed.get("node_id", "")).strip_edges()
	if source_id.is_empty():
		source_id = _resolve_source.call(normalized_node_id)
	if source_id.is_empty():
		source_id = str(
			_content_state.get_source_for_node(normalized_node_id)
		).strip_edges()
	if source_id.is_empty() or raw_node_id.is_empty():
		return {}
	return {"source_id": source_id, "node_id": raw_node_id}
