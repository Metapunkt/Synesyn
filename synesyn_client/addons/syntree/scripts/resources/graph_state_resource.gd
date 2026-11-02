## Purpose: GraphStateResource (script)
@tool
extends Resource
class_name GraphStateResource

# Node position storage {source_id: {node_id: Vector2}}
@export var node_positions: Dictionary = {}

# View state
@export var zoom_level: float = 1.0
@export var scroll_offset: Vector2 = Vector2.ZERO

# Visible nodes set {source_id: [node_id1, node_id2, ...]}
@export var visible_nodes: Dictionary = {}

signal positions_changed(source_id: String)

func _init() -> void:
	# Connect to our own signals to mark resource as changed when data changes
	positions_changed.connect(func(_source_id): emit_changed())

# Node position management
func save_node_position(source_id: String, node_id: String, position: Vector2) -> void:
	"""
	Save the position of a node in a source
	"""
	if not node_positions.has(source_id):
		node_positions[source_id] = {}
		
	node_positions[source_id][node_id] = position
	
	positions_changed.emit(source_id)

func get_node_position(source_id: String, node_id: String) -> Vector2:
	"""
	Get the position of a node in a source
	Returns Vector2.ZERO if not found
	"""
	if not node_positions.has(source_id) or not node_positions[source_id].has(node_id):
		return Vector2.ZERO
		
	return node_positions[source_id][node_id]

func has_stored_positions(source_id: String) -> bool:
	"""
	Check if positions are stored for a source
	"""
	return node_positions.has(source_id) and not node_positions[source_id].is_empty()

func clear_node_positions(source_id: String) -> void:
	"""
	Clear all node positions for a source
	"""
	if node_positions.has(source_id):
		node_positions.erase(source_id)
		
	positions_changed.emit(source_id)

# View state management
func save_view_state(zoom: float, offset: Vector2) -> void:
	"""
	Save the current view state (zoom and scroll offset)
	"""
	zoom_level = zoom
	scroll_offset = offset
	
	emit_changed()

func reset_view_state() -> void:
	"""
	Reset the view state to default values
	"""
	zoom_level = 1.0
	scroll_offset = Vector2.ZERO
	
	emit_changed()

# Visibility management
func set_visible_nodes(source_id: String, nodes: Array) -> void:
	"""
	Set which nodes are visible for a source
	"""
	visible_nodes[source_id] = nodes.duplicate()
	
	emit_changed()

func is_node_visible(source_id: String, node_id: String) -> bool:
	"""
	Check if a node is visible for a source
	Returns true if no visibility constraints are set
	"""
	if not visible_nodes.has(source_id) or visible_nodes[source_id].is_empty():
		return true  # No constraints, all nodes visible
		
	return node_id in visible_nodes[source_id]

# Getters
func get_zoom_level() -> float:
	return zoom_level

func get_scroll_offset() -> Vector2:
	return scroll_offset 