@tool
extends Node3D
class_name PatternGraph

signal pattern_added(pattern)
signal pattern_removed(pattern_id)
signal relationship_added(relationship)
signal relationship_removed(relationship_id)
signal patterns_updated

# Inner classes for data structures
class PatternNode:
	var id: int = -1
	var pattern_type: String = "Generic"
	var position: Vector3 = Vector3.ZERO
	var items: Array = []
	var metadata: Dictionary = {}
	var confidence: float = 0.5
	var color: Color = Color.WHITE
	var size: float = 1.0
	var visual_node: Node3D = null
	
	func _init(p_id: int = -1) -> void:
		id = p_id

class PatternRelationship:
	var id: int = -1
	var source_id: int = -1
	var target_id: int = -1
	var type: String = "default"
	var strength: float = 0.5
	var metadata: Dictionary = {}
	var visual_node: Node3D = null
	
	func _init(p_id: int = -1) -> void:
		id = p_id

# Node references
var _patterns_node: Node3D = null
var _relationships_node: Node3D = null

# Data containers
var _patterns: Dictionary = {}  # id -> PatternNode
var _relationships: Dictionary = {}  # id -> PatternRelationship
var _next_pattern_id: int = 0
var _next_relationship_id: int = 0

# Graph structure
var _pattern_connections: Dictionary = {}  # pattern_id -> [connected_pattern_ids]

# Visual properties
var _pattern_material: StandardMaterial3D = null
var _relationship_material: StandardMaterial3D = null
var _hovering_material: StandardMaterial3D = null
var _selected_material: StandardMaterial3D = null

func _init() -> void:
	_patterns_node = Node3D.new()
	_patterns_node.name = "Patterns"
	add_child(_patterns_node)
	
	_relationships_node = Node3D.new()
	_relationships_node.name = "Relationships"
	add_child(_relationships_node)
	
	_setup_materials()

func _ready() -> void:
	pass

func _setup_materials() -> void:
	_pattern_material = StandardMaterial3D.new()
	_pattern_material.albedo_color = Color(0.2, 0.5, 0.8, 0.9)
	_pattern_material.metallic = 0.3
	_pattern_material.roughness = 0.4
	_pattern_material.emission_enabled = true
	_pattern_material.emission = Color(0.1, 0.2, 0.4)
	_pattern_material.emission_energy = 0.5
	
	_relationship_material = StandardMaterial3D.new()
	_relationship_material.albedo_color = Color(0.8, 0.8, 0.8, 0.5)
	_relationship_material.metallic = 0.0
	_relationship_material.roughness = 0.8
	_relationship_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	_hovering_material = StandardMaterial3D.new()
	_hovering_material.albedo_color = Color(1.0, 0.8, 0.2, 0.9)
	_hovering_material.metallic = 0.3
	_hovering_material.roughness = 0.4
	_hovering_material.emission_enabled = true
	_hovering_material.emission = Color(0.5, 0.4, 0.1)
	_hovering_material.emission_energy = 1.0
	
	_selected_material = StandardMaterial3D.new()
	_selected_material.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
	_selected_material.metallic = 0.3
	_selected_material.roughness = 0.4
	_selected_material.emission_enabled = true
	_selected_material.emission = Color(0.6, 0.3, 0.1)
	_selected_material.emission_energy = 1.5

func clear() -> void:
	# Remove all visual nodes
	for child in _patterns_node.get_children():
		child.queue_free()
	
	for child in _relationships_node.get_children():
		child.queue_free()
	
	# Clear data structures
	_patterns.clear()
	_relationships.clear()
	_pattern_connections.clear()
	
	# Reset IDs
	_next_pattern_id = 0
	_next_relationship_id = 0

# Pattern management

func add_pattern(pattern: PatternNode) -> void:
	if pattern.id < 0:
		pattern.id = get_next_pattern_id()
	
	_patterns[pattern.id] = pattern
	
	# Initialize connections array
	if not _pattern_connections.has(pattern.id):
		_pattern_connections[pattern.id] = []
	
	# Create visual representation
	pattern.visual_node = _create_pattern_visual(pattern)
	_patterns_node.add_child(pattern.visual_node)
	
	emit_signal("pattern_added", pattern)

func remove_pattern(pattern_id: int) -> void:
	if _patterns.has(pattern_id):
		var pattern = _patterns[pattern_id]
		
		# Remove visual node
		if pattern.visual_node:
			pattern.visual_node.queue_free()
		
		# Remove connections
		if _pattern_connections.has(pattern_id):
			# Find relationships involving this pattern and remove them
			var relationships_to_remove = []
			
			for rel_id in _relationships.keys():
				var rel = _relationships[rel_id]
				if rel.source_id == pattern_id or rel.target_id == pattern_id:
					relationships_to_remove.append(rel_id)
			
			for rel_id in relationships_to_remove:
				remove_relationship(rel_id)
			
			# Remove from connections dictionary
			_pattern_connections.erase(pattern_id)
			
			# Remove from other patterns' connections
			for other_id in _pattern_connections.keys():
				if pattern_id in _pattern_connections[other_id]:
					_pattern_connections[other_id].erase(pattern_id)
		
		# Remove from patterns dictionary
		_patterns.erase(pattern_id)
		
		emit_signal("pattern_removed", pattern_id)

func get_pattern(pattern_id: int) -> PatternNode:
	if _patterns.has(pattern_id):
		return _patterns[pattern_id]
	return null

func get_all_patterns() -> Array:
	return _patterns.values()

func get_pattern_count() -> int:
	return _patterns.size()

func get_next_pattern_id() -> int:
	var id = _next_pattern_id
	_next_pattern_id += 1
	return id

func update_pattern_position(pattern_id: int, position: Vector3) -> void:
	if _patterns.has(pattern_id):
		var pattern = _patterns[pattern_id]
		pattern.position = position
		
		if pattern.visual_node:
			pattern.visual_node.position = position
		
		# Update connections
		_update_pattern_relationships(pattern_id)

func update_pattern_visual(pattern_id: int, is_hovered: bool = false, is_selected: bool = false) -> void:
	if _patterns.has(pattern_id):
		var pattern = _patterns[pattern_id]
		var mesh_instance = _get_pattern_mesh_instance(pattern.visual_node)
		
		if mesh_instance:
			if is_selected:
				mesh_instance.material_override = _selected_material
			elif is_hovered:
				mesh_instance.material_override = _hovering_material
			else:
				# Create pattern-specific material if needed
				var base_material = _pattern_material.duplicate()
				
				# Adjust color based on pattern type
				match pattern.pattern_type:
					"Cluster":
						base_material.albedo_color = Color(0.2, 0.5, 0.8, 0.9)
					"Bridge":
						base_material.albedo_color = Color(0.8, 0.2, 0.5, 0.9)
					"Hub":
						base_material.albedo_color = Color(0.2, 0.8, 0.5, 0.9)
					_:
						base_material.albedo_color = Color(0.5, 0.5, 0.5, 0.9)
				
				# Adjust size based on confidence
				pattern.size = 0.8 + pattern.confidence * 0.6
				if mesh_instance.mesh is SphereMesh:
					mesh_instance.mesh.radius = pattern.size / 2.0
					mesh_instance.mesh.height = pattern.size
				
				mesh_instance.material_override = base_material

func notify_patterns_updated() -> void:
	# Update all pattern visuals
	for pattern_id in _patterns.keys():
		update_pattern_visual(pattern_id)
	
	emit_signal("patterns_updated")

# Relationship management

func add_relationship(relationship: PatternRelationship) -> void:
	if relationship.id < 0:
		relationship.id = get_next_relationship_id()
	
	if relationship.source_id < 0 or relationship.target_id < 0:
		push_error("Invalid relationship source or target ID")
		return
	
	if not _patterns.has(relationship.source_id) or not _patterns.has(relationship.target_id):
		push_error("Relationship references non-existent pattern")
		return
	
	_relationships[relationship.id] = relationship
	
	# Update connections
	if not _pattern_connections.has(relationship.source_id):
		_pattern_connections[relationship.source_id] = []
	if not _pattern_connections.has(relationship.target_id):
		_pattern_connections[relationship.target_id] = []
	
	if not relationship.target_id in _pattern_connections[relationship.source_id]:
		_pattern_connections[relationship.source_id].append(relationship.target_id)
	
	if not relationship.source_id in _pattern_connections[relationship.target_id]:
		_pattern_connections[relationship.target_id].append(relationship.source_id)
	
	# Create visual representation
	relationship.visual_node = _create_relationship_visual(relationship)
	_relationships_node.add_child(relationship.visual_node)
	
	emit_signal("relationship_added", relationship)

func remove_relationship(relationship_id: int) -> void:
	if _relationships.has(relationship_id):
		var relationship = _relationships[relationship_id]
		
		# Remove visual node
		if relationship.visual_node:
			relationship.visual_node.queue_free()
		
		# Update connections
		var source_id = relationship.source_id
		var target_id = relationship.target_id
		
		if _pattern_connections.has(source_id) and target_id in _pattern_connections[source_id]:
			_pattern_connections[source_id].erase(target_id)
		
		if _pattern_connections.has(target_id) and source_id in _pattern_connections[target_id]:
			_pattern_connections[target_id].erase(source_id)
		
		# Remove from relationships dictionary
		_relationships.erase(relationship_id)
		
		emit_signal("relationship_removed", relationship_id)

func get_relationship(relationship_id: int) -> PatternRelationship:
	if _relationships.has(relationship_id):
		return _relationships[relationship_id]
	return null

func get_all_relationships() -> Array:
	return _relationships.values()

func get_relationship_count() -> int:
	return _relationships.size()

func get_next_relationship_id() -> int:
	var id = _next_relationship_id
	_next_relationship_id += 1
	return id

func get_connected_patterns(pattern_id: int) -> Array:
	var result = []
	
	if _pattern_connections.has(pattern_id):
		for connected_id in _pattern_connections[pattern_id]:
			if _patterns.has(connected_id):
				result.append(_patterns[connected_id])
	
	return result

# Visual representation

func _create_pattern_visual(pattern: PatternNode) -> Node3D:
	var node = Node3D.new()
	node.name = "Pattern" + str(pattern.id)
	node.position = pattern.position
	
	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "PatternMesh"
	
	var sphere = SphereMesh.new()
	sphere.radius = pattern.size / 2.0
	sphere.height = pattern.size
	sphere.material = _pattern_material
	
	mesh_instance.mesh = sphere
	node.add_child(mesh_instance)
	
	# Update visual properties
	update_pattern_visual(pattern.id)
	
	return node

func _create_relationship_visual(relationship: PatternRelationship) -> Node3D:
	var node = Node3D.new()
	node.name = "Relationship" + str(relationship.id)
	
	var source_pattern = _patterns[relationship.source_id]
	var target_pattern = _patterns[relationship.target_id]
	
	var source_pos = source_pattern.position
	var target_pos = target_pattern.position
	
	# Create line mesh
	var line = _create_line_mesh(source_pos, target_pos, relationship.strength)
	node.add_child(line)
	
	return node

func _create_line_mesh(start_pos: Vector3, end_pos: Vector3, strength: float = 1.0) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "LineMesh"
	
	# Calculate direction and length
	var direction = end_pos - start_pos
	var length = direction.length()
	var center = (start_pos + end_pos) / 2.0
	
	# Create line mesh
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.05 * strength
	cylinder.bottom_radius = 0.05 * strength
	cylinder.height = length
	cylinder.material = _relationship_material
	
	mesh_instance.mesh = cylinder
	mesh_instance.position = center
	
	# Orient the cylinder to point from start to end
	if not direction.is_zero_approx():
		var y_axis = Vector3(0, 1, 0)
		var rotation_axis = y_axis.cross(direction.normalized())
		var rotation_angle = acos(y_axis.dot(direction.normalized()))
		
		if not rotation_axis.is_zero_approx():
			mesh_instance.global_transform.basis = Basis(rotation_axis.normalized(), rotation_angle)
	
	return mesh_instance

func _update_pattern_relationships(pattern_id: int) -> void:
	# Update all relationships involving this pattern
	for rel_id in _relationships.keys():
		var rel = _relationships[rel_id]
		
		if rel.source_id == pattern_id or rel.target_id == pattern_id:
			# Remove old visual
			if rel.visual_node:
				rel.visual_node.queue_free()
			
			# Create new visual
			rel.visual_node = _create_relationship_visual(rel)
			_relationships_node.add_child(rel.visual_node)

func _get_pattern_mesh_instance(node: Node) -> MeshInstance3D:
	if not node:
		return null
		
	if node is MeshInstance3D:
		return node
	
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		
		var mesh_instance = _get_pattern_mesh_instance(child)
		if mesh_instance:
			return mesh_instance
	
	return null 