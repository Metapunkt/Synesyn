## Purpose: Thin GraphEdit signal bridge used by ContentGraphController
"""
COMPONENT: ContentGraph
RESPONSIBILITY: Thin GraphEdit signal bridge used by ContentGraphController
PUBLIC API:
  - _ready(): Initialize graph
DEPENDENCIES:
  - GraphEdit: Inherits from Godot's GraphEdit
  - ContentGraphController: For graph operations
"""
@tool
class_name ContentGraph
extends GraphEdit

const DEBUG: bool = false

func _dbg(msg: Variant) -> void:
	if DEBUG:
		print(msg)

# Define all custom signals
signal node_moved(node_id: String, position: Vector2)
signal node_connected(from_id: String, from_port: int, to_id: String, to_port: int)
signal node_disconnected(from_id: String, from_port: int, to_id: String, to_port: int)
signal content_node_selected(node_id: String)  # GraphNode -> ContentGraph -> Controller
signal content_node_deselected(node_id: String)  # GraphNode -> ContentGraph -> Controller

func _ready() -> void:
	if not is_inside_tree():
		push_error("GraphView not properly added to scene tree")
		return
	
	# Basic setup
	minimap_enabled = true
	right_disconnects = true
	show_zoom_label = true
	
	# Connect built-in signals
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	node_selected.connect(_on_node_selected)
	node_deselected.connect(_on_node_deselected)
	begin_node_move.connect(_on_begin_node_move)
	end_node_move.connect(_on_end_node_move)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		_navigate_graph(key_event.keycode)
		accept_event()


func fit_visible_nodes() -> void:
	var visible_nodes: Array[GraphNode] = _visible_graph_nodes()
	if visible_nodes.is_empty() or size.x <= 0.0 or size.y <= 0.0:
		return
	var bounds: Rect2 = Rect2(
		visible_nodes[0].position_offset,
		visible_nodes[0].size
	)
	for graph_node in visible_nodes:
		bounds = bounds.merge(Rect2(graph_node.position_offset, graph_node.size))
	var padded_size: Vector2 = bounds.size + Vector2(120.0, 120.0)
	var fit_zoom: float = minf(
		size.x / maxf(padded_size.x, 1.0),
		size.y / maxf(padded_size.y, 1.0)
	)
	zoom = clampf(fit_zoom, zoom_min, zoom_max)
	scroll_offset = bounds.get_center() - (size / (2.0 * zoom))


func _navigate_graph(keycode: Key) -> void:
	var visible_nodes: Array[GraphNode] = _visible_graph_nodes()
	if visible_nodes.is_empty():
		return
	var current_node: GraphNode = null
	for graph_node in visible_nodes:
		if graph_node.selected:
			current_node = graph_node
			break
	if current_node == null:
		_select_graph_node(visible_nodes[0])
		return
	var direction_any: Variant = {
		KEY_LEFT: Vector2.LEFT,
		KEY_RIGHT: Vector2.RIGHT,
		KEY_UP: Vector2.UP,
		KEY_DOWN: Vector2.DOWN,
	}.get(keycode, Vector2.RIGHT)
	var direction: Vector2 = direction_any
	var current_center: Vector2 = (
		current_node.position_offset + current_node.size * 0.5
	)
	var best_node: GraphNode = null
	var best_score: float = INF
	for candidate_node in visible_nodes:
		if candidate_node == current_node:
			continue
		var delta: Vector2 = (
			candidate_node.position_offset
			+ candidate_node.size * 0.5
			- current_center
		)
		var forward_distance: float = delta.dot(direction)
		if forward_distance <= 0.0:
			continue
		var lateral_distance: float = absf(delta.cross(direction))
		var score: float = forward_distance + lateral_distance * 2.0
		if score < best_score:
			best_score = score
			best_node = candidate_node
	if best_node != null:
		_select_graph_node(best_node)


func _select_graph_node(target_node: GraphNode) -> void:
	for graph_node in _visible_graph_nodes():
		graph_node.selected = graph_node == target_node
	target_node.grab_focus()
	content_node_selected.emit(str(target_node.name))
	scroll_offset = target_node.position_offset - size * 0.25


func _visible_graph_nodes() -> Array[GraphNode]:
	var result: Array[GraphNode] = []
	for child in get_children():
		if child is GraphNode and child.visible:
			result.append(child)
	result.sort_custom(func(left: GraphNode, right: GraphNode) -> bool:
		if not is_equal_approx(left.position_offset.y, right.position_offset.y):
			return left.position_offset.y < right.position_offset.y
		return left.position_offset.x < right.position_offset.x
	)
	return result

# NOTE:
# SynTree uses `ContentGraphController` as the primary graph builder. This script is intentionally
# kept lean: it bridges GraphEdit built-in signals -> custom "content_node_*" signals that the
# controller consumes, plus move/connect events.

# Signal handlers emit pure node events
func _on_node_selected(node) -> void:
	_dbg("ContentGraph: Node selected, type: %s, value: %s" % [str(typeof(node)), str(node)])
	
	# Handle any parameter type that might be passed
	var node_id: String
	
	if typeof(node) == TYPE_STRING or typeof(node) == TYPE_STRING_NAME:
		# It's already a string or string name
		node_id = str(node)
	elif typeof(node) == TYPE_OBJECT and node != null and node is Node:
		# Prefer a node_id property if present (works for controller-built nodes too).
		var prop = node.get("node_id")
		if typeof(prop) == TYPE_STRING or typeof(prop) == TYPE_STRING_NAME:
			node_id = str(prop)
		else:
			# Fallback: use node name if it’s a GraphNode.
			if node is GraphNode:
				node_id = str(node.name)
			else:
				push_error("ContentGraph: Could not resolve node_id for node: " + str(node))
				return
	else:
		push_error("ContentGraph: Unexpected node type in _on_node_selected: " + str(typeof(node)))
		return
	
	# Final guard: never emit empty ids (they spam errors downstream).
	node_id = String(node_id).strip_edges()
	if node_id.is_empty():
		push_warning("ContentGraph: Ignoring node_selected with empty resolved id")
		return
	_dbg("ContentGraph: Emitting content_node_selected with ID: %s" % node_id)
	emit_signal("content_node_selected", node_id)

func _on_node_deselected(node) -> void:
	_dbg("ContentGraph: Node deselected, type: %s, value: %s" % [str(typeof(node)), str(node)])
	
	# Handle any parameter type that might be passed
	var node_id: String
	
	if typeof(node) == TYPE_STRING or typeof(node) == TYPE_STRING_NAME:
		# It's already a string or string name
		node_id = str(node)
	elif typeof(node) == TYPE_OBJECT and node != null and node is Node:
		# Prefer a node_id property if present (works for controller-built nodes too).
		var prop = node.get("node_id")
		if typeof(prop) == TYPE_STRING or typeof(prop) == TYPE_STRING_NAME:
			node_id = str(prop)
		else:
			if node is GraphNode:
				node_id = str(node.name)
			else:
				push_error("ContentGraph: Could not resolve node_id for node: " + str(node))
				return
	else:
		push_error("ContentGraph: Unexpected node type in _on_node_deselected: " + str(typeof(node)))
		return
	
	# Pass the string ID
	_dbg("ContentGraph: Emitting content_node_deselected with ID: %s" % node_id)
	emit_signal("content_node_deselected", node_id)

func _on_begin_node_move() -> void:
	pass  # Track movement start if needed

func _on_end_node_move() -> void:
	# Controller-built graphs do not populate _nodes; iterate children instead.
	for child in get_children():
		if not (child is GraphNode):
			continue
		var n: GraphNode = child
		if not n.selected:
			continue
		var moved_id := str(n.get("node_id")) if (typeof(n.get("node_id")) == TYPE_STRING or typeof(n.get("node_id")) == TYPE_STRING_NAME) else str(n.name)
		node_moved.emit(moved_id, n.position_offset)

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	connect_node(from_node, from_port, to_node, to_port)
	node_connected.emit(from_node, from_port, to_node, to_port)

func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	node_disconnected.emit(from_node, from_port, to_node, to_port)
