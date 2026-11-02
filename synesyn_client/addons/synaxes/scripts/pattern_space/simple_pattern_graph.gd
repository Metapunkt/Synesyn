@tool
extends Node3D

## Lightweight, Dictionary-based pattern graph used by the editor-plugin scene
## (pattern_viewer.tscn).  For the full class_name PatternGraph implementation
## with inner PatternNode / PatternRelationship classes, see
## res://addons/synaxes/scripts/visualization/pattern_graph.gd.

# Signal when patterns or connections change
signal pattern_added(pattern_id)
signal pattern_removed(pattern_id)
signal connection_added(from_id, to_id)
signal connection_removed(from_id, to_id)

# Patterns collection
var _patterns = {}
var _connections = {}
var _next_pattern_id = 0

# Add a pattern to the graph
func add_pattern(position: Vector3, metadata: Dictionary = {}, pattern_type: String = "default", confidence: float = 1.0) -> int:
	var pattern_id = _next_pattern_id
	_next_pattern_id += 1
	
	var pattern = {
		"id": pattern_id,
		"position": position,
		"type": pattern_type,
		"confidence": confidence,
		"metadata": metadata,
		"connections": []
	}
	
	_patterns[pattern_id] = pattern
	emit_signal("pattern_added", pattern_id)
	return pattern_id

# Remove a pattern from the graph
func remove_pattern(pattern_id: int) -> bool:
	if not _patterns.has(pattern_id):
		return false
	
	# Remove all connections involving this pattern
	var connections_to_remove = []
	for connection in _connections.values():
		if connection.from_id == pattern_id or connection.to_id == pattern_id:
			connections_to_remove.append(connection)
	
	for connection in connections_to_remove:
		remove_connection(connection.from_id, connection.to_id)
	
	_patterns.erase(pattern_id)
	emit_signal("pattern_removed", pattern_id)
	return true

# Add a connection between patterns
func add_connection(from_id: int, to_id: int, connection_type: String = "default", strength: float = 1.0) -> bool:
	if not _patterns.has(from_id) or not _patterns.has(to_id):
		return false
	
	var connection_key = str(from_id) + "_" + str(to_id)
	
	# Check if connection already exists
	if _connections.has(connection_key):
		return false
	
	var connection = {
		"from_id": from_id,
		"to_id": to_id,
		"type": connection_type,
		"strength": strength
	}
	
	_connections[connection_key] = connection
	
	# Add to pattern's connection list
	_patterns[from_id].connections.append(to_id)
	_patterns[to_id].connections.append(from_id)
	
	emit_signal("connection_added", from_id, to_id)
	return true

# Remove a connection
func remove_connection(from_id: int, to_id: int) -> bool:
	var connection_key = str(from_id) + "_" + str(to_id)
	
	if not _connections.has(connection_key):
		# Try reverse order
		connection_key = str(to_id) + "_" + str(from_id)
		if not _connections.has(connection_key):
			return false
	
	var connection = _connections[connection_key]
	
	# Remove from pattern's connection list
	if _patterns.has(connection.from_id):
		_patterns[connection.from_id].connections.erase(connection.to_id)
	
	if _patterns.has(connection.to_id):
		_patterns[connection.to_id].connections.erase(connection.from_id)
	
	_connections.erase(connection_key)
	
	emit_signal("connection_removed", from_id, to_id)
	return true

# Get a pattern by ID
func get_pattern(pattern_id: int) -> Dictionary:
	if _patterns.has(pattern_id):
		return _patterns[pattern_id]
	return {}

# Get a connection
func get_connection(from_id: int, to_id: int) -> Dictionary:
	var connection_key = str(from_id) + "_" + str(to_id)
	
	if _connections.has(connection_key):
		return _connections[connection_key]
	
	# Try reverse order
	connection_key = str(to_id) + "_" + str(from_id)
	if _connections.has(connection_key):
		return _connections[connection_key]
	
	return {}

# Get all patterns
func get_all_patterns() -> Array:
	return _patterns.values()

# Get all connections
func get_all_connections() -> Array:
	return _connections.values()

# Get connected patterns to a given pattern
func get_connected_patterns(pattern_id: int) -> Array:
	if not _patterns.has(pattern_id):
		return []
	
	var connected_patterns = []
	var pattern = _patterns[pattern_id]
	
	for connected_id in pattern.connections:
		if _patterns.has(connected_id):
			connected_patterns.append(_patterns[connected_id])
	
	return connected_patterns

# Clear all patterns and connections
func clear() -> void:
	_patterns.clear()
	_connections.clear()
	_next_pattern_id = 0 