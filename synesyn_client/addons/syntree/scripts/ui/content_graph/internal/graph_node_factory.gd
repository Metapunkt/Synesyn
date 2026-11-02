## Purpose: Instantiate and wire dynamic Context Graph node scenes.
extends RefCounted

const ContentGraphNodeScene = preload(
	"res://addons/syntree/scenes/content_source_graph_node.tscn"
)

var _content_state: ContentStateResource = null
var _metaprompt_callback: Callable
var _active_callback: Callable
var _delete_callback: Callable


func setup(
	content_state: ContentStateResource,
	metaprompt_callback: Callable,
	active_callback: Callable,
	delete_callback: Callable
) -> void:
	_content_state = content_state
	_metaprompt_callback = metaprompt_callback
	_active_callback = active_callback
	_delete_callback = delete_callback


func create(node_data: Dictionary) -> GraphNode:
	var node_id: String = str(node_data.get("node_id", ""))
	if node_id.is_empty():
		push_error("Cannot create graph node without node_id")
		return null
	var graph_node: GraphNode = ContentGraphNodeScene.instantiate()
	if not graph_node is ContentSourceGraphNode:
		if is_instance_valid(graph_node):
			graph_node.queue_free()
		return null
	graph_node.name = node_id
	graph_node.node_id = node_id
	graph_node.set_resources(_content_state)
	if not graph_node.metaprompt_toggled.is_connected(_metaprompt_callback):
		graph_node.metaprompt_toggled.connect(_metaprompt_callback)
	if not graph_node.active_source_toggled.is_connected(_active_callback):
		graph_node.active_source_toggled.connect(_active_callback)
	if not graph_node.delete_requested.is_connected(_delete_callback):
		graph_node.delete_requested.connect(_delete_callback)
	graph_node.set_node_data(node_data)
	return graph_node
