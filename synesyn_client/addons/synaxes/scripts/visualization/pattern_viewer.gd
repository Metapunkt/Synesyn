extends Node3D
class_name PatternViewer

# Make sure PatternGraph is loaded
const PatternGraphScript = preload("res://addons/synaxes/scripts/visualization/pattern_graph.gd")

signal pattern_selected(pattern_id)
signal pattern_hovered(pattern_id)
signal pattern_deselected

# Node references
var pattern_container: Node3D = null
var pattern_graph: PatternGraph = null
var camera: Camera3D = null
var debug_info: Label = null

# Scene references
@export var pattern_node_scene: PackedScene
@export var pattern_connection_scene: PackedScene

# Pattern visualization settings
var pattern_scale_factor: float = 1.0
var highlight_color: Color = Color(1.0, 0.8, 0.0)
var selected_color: Color = Color(1.0, 0.2, 0.2)
var hover_color: Color = Color(0.2, 0.8, 1.0)
var connection_colors: Dictionary = {
	"cluster_relation": Color(0.6, 0.6, 0.6),
	"bridge_relation": Color(0.8, 0.4, 0.2),
	"hub_relation": Color(0.4, 0.8, 0.2),
	"temporal_relation": Color(0.2, 0.4, 0.8),
	"default": Color(0.5, 0.5, 0.5)
}

# Camera control parameters
var _orbit_speed: float = 0.005
var _zoom_speed: float = 0.1
var _pan_speed: float = 0.01
var _smooth_zoom_factor: float = 0.1
var _target_zoom: float = 10.0
var _current_zoom: float = 10.0

# Interaction state
var _selected_patterns: Array = []
var _hovered_pattern: PatternGraph.PatternNode = null
var _is_dragging: bool = false
var _is_panning: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _target_camera_position: Vector3 = Vector3(0, 0, 10)
var _target_look_at: Vector3 = Vector3.ZERO
var _camera_rotation: Vector2 = Vector2.ZERO

# Pattern node mapping
var _pattern_nodes: Dictionary = {}  # pattern_id -> PatternNode (scene instance)
var _connection_nodes: Dictionary = {}  # [from_id, to_id] -> ConnectionNode

# Called when the node is added to the scene for the first time
func _enter_tree() -> void:
	print("PatternViewer _enter_tree called: ", get_path())
	
	# Enable processing for this node
	set_process_input(true)
	set_process(true)
	
	# Create pattern container immediately
	if not has_node("PatternContainer"):
		var container = Node3D.new()
		container.name = "PatternContainer"
		add_child(container)
		pattern_container = container
		print("Created PatternContainer in _enter_tree")
	else:
		pattern_container = get_node("PatternContainer")
		print("Found existing PatternContainer in _enter_tree")
	
	# Create pattern graph if it doesn't exist
	if not has_node("PatternGraph"):
		# Load the script first to create the proper type
		var graph_script = load("res://addons/synaxes/scripts/visualization/pattern_graph.gd")
		var graph = graph_script.new()  # Create an instance of PatternGraph directly
		graph.name = "PatternGraph"
		add_child(graph)
		pattern_graph = graph
		print("Created PatternGraph in _enter_tree")
	else:
		# Get the existing node and verify it has the correct script
		var graph_node = get_node("PatternGraph")
		if graph_node is PatternGraph:
			pattern_graph = graph_node
			print("Found existing PatternGraph in _enter_tree")
		else:
			print("Found PatternGraph node but it's not the correct type, updating script...")
			var graph_script = load("res://addons/synaxes/scripts/visualization/pattern_graph.gd")
			graph_node.set_script(graph_script)
			pattern_graph = graph_node
	
	# Create camera if it doesn't exist
	if not has_node("Camera3D"):
		var cam = Camera3D.new()
		cam.name = "Camera3D"
		add_child(cam)
		camera = cam
		print("Created Camera3D in _enter_tree")
	else:
		camera = get_node("Camera3D")
		print("Found existing Camera3D in _enter_tree")

# Called when the node enters the scene tree for the first time
func _ready() -> void:
	print("PatternViewer _ready called: ", get_path())
	print("Children: ", get_children())
	
	# Ensure this node can receive input events
	set_process_input(true)
	
	# Find the SubViewportContainer parent and connect to it
	var parent = get_viewport()
	if parent and parent is SubViewport:
		var viewport_container = parent.get_parent()
		if viewport_container and viewport_container is SubViewportContainer:
			print("Found SubViewportContainer parent: ", viewport_container.get_path())
			# Make sure the SubViewportContainer is set up for input handling
			viewport_container.focus_mode = Control.FOCUS_CLICK
			viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
			
			# Connect a gui_input handler to the parent to capture clicks
			if not viewport_container.is_connected("gui_input", _on_parent_gui_input):
				viewport_container.connect("gui_input", _on_parent_gui_input)
				
			# Set parent to accept all input
			viewport_container.set_process_input(true)
			
			# Configure the SubViewport (which does have handle_input_locally)
			var viewport = get_viewport()
			if viewport and viewport is SubViewport:
				viewport.handle_input_locally = true
				print("Configured SubViewport for input handling")
		else:
			print("Could not find SubViewportContainer parent, viewport parent is: ", parent)
	else:
		print("Current viewport is not a SubViewport")
	
	# Double check pattern container
	if not pattern_container:
		if has_node("PatternContainer"):
			pattern_container = get_node("PatternContainer")
			print("Found PatternContainer in _ready")
		else:
			var container = Node3D.new()
			container.name = "PatternContainer"
			add_child(container)
			pattern_container = container
			print("Created PatternContainer in _ready")
	
	# Double check pattern graph
	if not pattern_graph:
		if has_node("PatternGraph"):
			var graph_node = get_node("PatternGraph")
			if graph_node is PatternGraph:
				pattern_graph = graph_node
				print("Found existing PatternGraph in _ready")
			else:
				print("Found PatternGraph node but it's not the correct type, updating script...")
				var graph_script = load("res://addons/synaxes/scripts/visualization/pattern_graph.gd")
				graph_node.set_script(graph_script)
				pattern_graph = graph_node
		else:
			# Load the script first to create the proper type
			var graph_script = load("res://addons/synaxes/scripts/visualization/pattern_graph.gd")
			var graph = graph_script.new()  # Create an instance of PatternGraph directly
			graph.name = "PatternGraph"
			add_child(graph)
			pattern_graph = graph
			print("Created PatternGraph in _ready")
	
	# Double check camera
	if not camera:
		if has_node("Camera3D"):
			camera = get_node("Camera3D")
			print("Found Camera3D in _ready")
		else:
			camera = Camera3D.new()
			camera.name = "Camera3D"
			add_child(camera)
			print("Created Camera3D in _ready")
	
	# Check for debug info
	if has_node("DebugInfo"):
		debug_info = get_node("DebugInfo")
		print("Found DebugInfo in _ready")
	else:
		# Create debug info as a 2D label in the CanvasLayer
		var canvas_layer = CanvasLayer.new()
		canvas_layer.name = "UILayer"
		add_child(canvas_layer)
		
		var label = Label.new()
		label.name = "DebugInfo"
		label.position = Vector2(10, 10)
		label.size = Vector2(300, 100)
		label.add_theme_color_override("font_color", Color(0.2, 0.16, 0.38, 0.9))
		canvas_layer.add_child(label)
		debug_info = label
		print("Created DebugInfo in _ready")
	
	# Load required scenes if not set
	if not pattern_node_scene:
		pattern_node_scene = load("res://addons/synaxes/scenes/pattern_node.tscn")
	
	if not pattern_connection_scene:
		pattern_connection_scene = load("res://addons/synaxes/scenes/pattern_connection.tscn")
	
	# Initialize camera position
	if camera:
		camera.position = Vector3(0, 0, 10)
		camera.look_at(Vector3.ZERO)
		camera.current = true  # Make this the active camera
	
	# Debug info
	print("PatternViewer initialization complete:")
	print("- pattern_container: ", pattern_container)
	print("- pattern_graph: ", pattern_graph)
	print("- camera: ", camera)

func _process(delta: float) -> void:
	# Smooth camera movement
	_update_camera(delta)
	
	# Process direct key inputs for camera control
	_process_direct_key_input()
	
	# Update debug info every 60 frames to avoid excessive updates
	if Engine.get_frames_drawn() % 60 == 0:
		_update_debug_info()

# Process direct key inputs for camera control instead of using input map
func _process_direct_key_input() -> void:
	# Handle only if plugin has focus
	if not has_focus():
		return
		
	# Handle camera rotation (WASD)
	if Input.is_key_pressed(KEY_A):
		_orbit_camera(Vector2(-5, 0))
	if Input.is_key_pressed(KEY_D):
		_orbit_camera(Vector2(5, 0))
	if Input.is_key_pressed(KEY_W):
		_orbit_camera(Vector2(0, -5))
	if Input.is_key_pressed(KEY_S):
		_orbit_camera(Vector2(0, 5))
	
	# Handle zoom (QE)
	if Input.is_key_pressed(KEY_Q):
		_zoom_camera(-1)
	if Input.is_key_pressed(KEY_E):
		_zoom_camera(1)
	
	# Handle panning (arrow keys)
	if Input.is_key_pressed(KEY_LEFT):
		_pan_camera(Vector2(-5, 0))
	if Input.is_key_pressed(KEY_RIGHT):
		_pan_camera(Vector2(5, 0))
	if Input.is_key_pressed(KEY_UP):
		_pan_camera(Vector2(0, -5))
	if Input.is_key_pressed(KEY_DOWN):
		_pan_camera(Vector2(0, 5))
	
	# Handle special functions
	if Input.is_key_pressed(KEY_SPACE):
		_reset_camera()
	if Input.is_key_pressed(KEY_F):
		_focus_on_selection()

func _input(event: InputEvent) -> void:
	# Only print input events when debugging is needed
	# print("PatternViewer received input: ", event)
	if event is InputEventMouseButton:
		# print("Mouse button event: ", event.button_index, " pressed: ", event.pressed)
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		# Capture arrow keys to prevent focus navigation
		if event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT or event.keycode == KEY_UP or event.keycode == KEY_DOWN:
			_handle_keyboard(event)
			# Mark event as handled to prevent it from being used for focus navigation
			get_viewport().set_input_as_handled()
		else:
			_handle_keyboard(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# Ensure focus is grabbed
	var viewport = get_viewport()
	if viewport and viewport is SubViewport:
		var container = viewport.get_parent()
		if container and container is SubViewportContainer and event.pressed:
			container.grab_focus()
	
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				if not event.shift_pressed:
					_is_dragging = true
					_last_mouse_pos = event.position
					_select_pattern_at_position(event.position)
				else:
					_is_panning = true
					_last_mouse_pos = event.position
			else:
				_is_dragging = false
				_is_panning = false
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_clear_selection()
		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_panning = true
				_last_mouse_pos = event.position
			else:
				_is_panning = false
		MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# Remove excessive debug output
	# print("PatternViewer: Mouse motion, relative: ", event.relative)
	
	if _is_dragging:
		var delta = event.relative
		_orbit_camera(delta)
		_last_mouse_pos = event.position
	elif _is_panning:
		var delta = event.relative
		_pan_camera(delta)
		_last_mouse_pos = event.position
	
	_update_hovered_pattern(event.position)

func _handle_keyboard(event: InputEventKey) -> void:
	if event.pressed:
		match event.keycode:
			KEY_SPACE:
				_reset_camera()
			KEY_ESCAPE:
				_clear_selection()
			KEY_F:
				if _selected_patterns.size() > 0:
					_focus_on_selection()

func _select_pattern_at_position(pos: Vector2) -> void:
	if not camera:
		printerr("PatternViewer: Cannot select pattern, camera is null")
		return
		
	if not pattern_graph:
		printerr("PatternViewer: Cannot select pattern, pattern_graph is null")
		return
	
	print("PatternViewer: Attempting to select pattern at screen position: ", pos)
	
	# Get the physics space state for ray casting
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		printerr("PatternViewer: Cannot select pattern, space_state is null")
		return
	
	# Create ray from camera
	var from = camera.project_ray_origin(pos)
	var to = from + camera.project_ray_normal(pos) * 1000  # Longer ray for better detection
	
	print("PatternViewer: Ray from ", from, " to ", to)
	
	# Set up the physics ray query
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # Match the collision layer we set earlier
	query.collide_with_bodies = true  # Make sure we collide with StaticBody3D nodes
	
	# Cast the ray
	var result = space_state.intersect_ray(query)
	print("PatternViewer: Ray cast result: ", result)
	
	if result.size() > 0:
		# Success! We hit something
		var collider = result.collider
		print("PatternViewer: Collided with: ", collider, ", class: ", collider.get_class())
		
		# Try to find the node with the pattern_id metadata
		# This could be the collider itself or a parent node
		var pattern_node = collider
		while pattern_node and not pattern_node.has_meta("pattern_id"):
			pattern_node = pattern_node.get_parent()
			if pattern_node:
				print("PatternViewer: Checking parent: ", pattern_node)
		
		if pattern_node and pattern_node.has_meta("pattern_id"):
			var pattern_id = pattern_node.get_meta("pattern_id")
			print("PatternViewer: Found pattern ID: ", pattern_id)
			
			var pattern = pattern_graph.get_pattern(pattern_id)
			if pattern:
				print("PatternViewer: Selected pattern: ", pattern.id, ", type: ", pattern.pattern_type)
				_select_pattern(pattern)
				emit_signal("pattern_selected", pattern_id)
				return
		else:
			print("PatternViewer: Could not find node with pattern_id metadata")
	else:
		print("PatternViewer: Ray cast did not hit anything")
	
	# If we get here, we didn't select a pattern
	print("PatternViewer: No pattern selected, clearing selection")
	_clear_selection()
	emit_signal("pattern_deselected")

func _select_pattern(pattern: PatternGraph.PatternNode) -> void:
	if not pattern:
		return
		
	if not pattern.position:
		return
		
	_clear_selection()
	_selected_patterns.append(pattern)
	_update_pattern_visualization()
	# Selection only highlights — no camera movement.
	# Use Focus Selection (F key or button) to move the camera to the selected pattern.

func _update_hovered_pattern(pos: Vector2) -> void:
	if not camera:
		return
		
	if not pattern_graph:
		return
	
	# Get the physics space state for ray casting
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	
	# Create ray from camera
	var from = camera.project_ray_origin(pos)
	var to = from + camera.project_ray_normal(pos) * 1000
	
	# Set up the physics ray query
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_bodies = true
	
	# Cast the ray
	var result = space_state.intersect_ray(query)
	
	if result.size() > 0:
		var collider = result.collider
		
		# Try to find the node with the pattern_id metadata
		var pattern_node = collider
		while pattern_node and not pattern_node.has_meta("pattern_id"):
			pattern_node = pattern_node.get_parent()
		
		if pattern_node and pattern_node.has_meta("pattern_id"):
			var pattern_id = pattern_node.get_meta("pattern_id")
			var pattern = pattern_graph.get_pattern(pattern_id)
			
			if pattern and pattern != _hovered_pattern:
				if _hovered_pattern != null:
					emit_signal("pattern_hovered", -1)  # Signal hover end
				
				_hovered_pattern = pattern
				emit_signal("pattern_hovered", pattern_id)
				_update_pattern_visualization()
	elif _hovered_pattern != null:
		_hovered_pattern = null
		emit_signal("pattern_hovered", -1)
		_update_pattern_visualization()

func _update_pattern_visualization() -> void:
	# Update visual representation of patterns based on selection and hover states
	if not pattern_graph:
		return
		
	for pattern_id in _pattern_nodes:
		var node = _pattern_nodes[pattern_id]
		if not node:
			continue
			
		var pattern = pattern_graph.get_pattern(pattern_id)
		if not pattern:
			continue
		
		if pattern in _selected_patterns:
			_update_pattern_material(node, selected_color, 1.5, 1.2)
		elif pattern == _hovered_pattern:
			_update_pattern_material(node, hover_color, 0.8, 0.7)
		else:
			# Default color based on pattern type
			var color = _get_pattern_color(pattern.pattern_type)
			_update_pattern_material(node, color)

func _update_pattern_material(node: Node3D, color: Color, emission_mult: float = 0.3, emission_energy: float = 0.5) -> void:
	if not node:
		return
		
	# Try to get CSGSphere3D from the pattern node
	var sphere = node.get_node_or_null("CSGSphere3D")
	if not sphere:
		return
		
	# Create a new material
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.3
	material.roughness = 0.7
	material.emission_enabled = true
	material.emission = color * emission_mult
	material.emission_energy = emission_energy
	
	# Apply the material to the sphere
	sphere.material = material
	
	# Scale selected nodes slightly larger for visual distinction
	if emission_energy > 1.0:
		node.scale = Vector3.ONE * pattern_scale_factor * 1.3
	else:
		node.scale = Vector3.ONE * pattern_scale_factor

func _get_pattern_color(pattern_type: String) -> Color:
	# Return color based on pattern type
	if pattern_type.begins_with("cluster_"):
		var cluster_idx = pattern_type.split("_")[1].to_int()
		# Generate colors using hue rotation
		var hue = (cluster_idx * 0.1) % 1.0
		return Color.from_hsv(hue, 0.7, 0.9)
	elif pattern_type == "bridge":
		return Color(0.9, 0.5, 0.1)
	elif pattern_type == "hub":
		return Color(0.1, 0.9, 0.3)
	elif pattern_type == "temporal":
		return Color(0.2, 0.5, 0.9)
	else:
		return Color(0.9, 0.9, 0.9)

func _orbit_camera(delta: Vector2) -> void:
	# Use relative motion for smoother control
	_camera_rotation.x -= delta.x * _orbit_speed * 0.5
	_camera_rotation.y -= delta.y * _orbit_speed * 0.5
	
	# Clamp vertical rotation to prevent flipping
	_camera_rotation.y = clamp(_camera_rotation.y, -PI/2 + 0.1, PI/2 - 0.1)
	
	_update_camera_target()

func _pan_camera(delta: Vector2) -> void:
	if not camera:
		return
	
	# Scale panning based on distance (zoom level)
	var scale_factor = _current_zoom * 0.01
	
	var right = camera.global_transform.basis.x
	var up = camera.global_transform.basis.y
	
	_target_look_at -= right * delta.x * _pan_speed * scale_factor
	_target_look_at += up * delta.y * _pan_speed * scale_factor
	
	_update_camera_target()

func _zoom_camera(direction: int) -> void:
	_target_zoom += direction * _zoom_speed * _target_zoom * 0.1
	_target_zoom = clamp(_target_zoom, 1.0, 50.0)

func _update_camera_target() -> void:
	var offset = Vector3(
		cos(_camera_rotation.x) * cos(_camera_rotation.y),
		sin(_camera_rotation.y),
		sin(_camera_rotation.x) * cos(_camera_rotation.y)
	) * _target_zoom
	
	_target_camera_position = _target_look_at + offset

func _update_camera(delta: float) -> void:
	# Smooth camera movement — use delta for frame-rate-independent lerp
	var smooth_t := 1.0 - exp(-5.0 * delta)  # ~0.08 at 60fps, smooth exponential decay
	_current_zoom = lerp(_current_zoom, _target_zoom, smooth_t)
	
	var offset = Vector3(
		cos(_camera_rotation.x) * cos(_camera_rotation.y),
		sin(_camera_rotation.y),
		sin(_camera_rotation.x) * cos(_camera_rotation.y)
	) * _current_zoom
	
	camera.position = lerp(camera.position, _target_look_at + offset, smooth_t)
	camera.look_at(_target_look_at)

func _reset_camera() -> void:
	_target_camera_position = Vector3(0, 0, 10)
	_target_look_at = Vector3.ZERO
	_target_zoom = 10.0
	_camera_rotation = Vector2.ZERO
	_update_camera_target()

func _clear_selection() -> void:
	_selected_patterns.clear()
	_hovered_pattern = null
	_update_pattern_visualization()

func _highlight_pattern(pattern_id: int) -> void:
	if not pattern_graph:
		return
		
	var pattern = pattern_graph.get_pattern(pattern_id)
	if not pattern:
		return
		
	# Clear previous selection first
	_selected_patterns.clear()
	
	# Add this pattern to selected patterns
	_selected_patterns.append(pattern)
	
	# Update visuals only — no camera movement on highlight.
	_update_pattern_visualization()

func _focus_on_selection() -> void:
	if _selected_patterns.size() > 0:
		_target_look_at = _selected_patterns[0].position
		# Zoom in closer for focus — but not too close
		_target_zoom = clamp(_current_zoom * 0.6, 2.0, 15.0)
		_update_camera_target()

func _update_debug_info() -> void:
	if not debug_info:
		return
		
	var fps = Engine.get_frames_per_second()
	var pattern_count = 0
	var selected_count = 0
	
	if pattern_graph:
		pattern_count = pattern_graph.get_all_patterns().size()
		
	selected_count = _selected_patterns.size()
	
	debug_info.text = "Patterns: %d\nSelected: %d\nFPS: %d" % [pattern_count, selected_count, fps]

# API for pattern visualization

func create_pattern_visualization(pattern_id: int) -> void:
	if not pattern_container:
		printerr("PatternViewer: Cannot create visualization, pattern_container is null")
		return
		
	if not pattern_graph:
		printerr("PatternViewer: Cannot create visualization, pattern_graph is null")
		return
		
	if not pattern_node_scene:
		printerr("PatternViewer: Cannot create visualization, pattern_node_scene is null")
		return
	
	var pattern = pattern_graph.get_pattern(pattern_id)
	if not pattern:
		printerr("PatternViewer: Cannot create visualization, pattern with id ", pattern_id, " not found")
		return
		
	if pattern.position == null:
		printerr("PatternViewer: Cannot create visualization, pattern position is invalid")
		return
		
	if pattern.pattern_type.is_empty():
		printerr("PatternViewer: Cannot create visualization, pattern type is missing")
		return
	
	print("PatternViewer: Creating visualization for pattern ID ", pattern_id)
	
	if not _pattern_nodes.has(pattern_id):
		var node = pattern_node_scene.instantiate()
		if not node:
			printerr("PatternViewer: Failed to instantiate pattern node scene")
			return
			
		pattern_container.add_child(node)
		
		node.position = pattern.position
		node.scale = Vector3.ONE * pattern_scale_factor
		
		# Set meta data to identify this pattern
		node.set_meta("pattern_id", pattern_id)
		
		# Update label — show pattern type + short preview from items
		var label_node = node.get_node_or_null("Label3D")
		if label_node:
			var label_text: String = pattern.pattern_type if not pattern.pattern_type.is_empty() else "P%d" % pattern_id
			# Try to get a content preview from the first item
			if pattern.items.size() > 0:
				var first_item: Variant = pattern.items[0]
				if typeof(first_item) == TYPE_DICTIONARY:
					var content := str((first_item as Dictionary).get("content", ""))
					if content.length() > 25:
						content = content.left(22) + "..."
					if not content.is_empty():
						label_text = content
			label_node.text = label_text
		
		# Set up collision for picking
		var body = node.get_node_or_null("PatternBody")
		if body:
			body.collision_layer = 1
			body.collision_mask = 0
			body.input_ray_pickable = true
			print("PatternViewer: Configured StaticBody3D for pattern ID ", pattern_id)
		else:
			printerr("PatternViewer: Warning - PatternBody not found in pattern node")
		
		# Set initial color based on pattern type
		var color = _get_pattern_color(pattern.pattern_type)
		_update_pattern_material(node, color)
		
		_pattern_nodes[pattern_id] = node
		print("PatternViewer: Created pattern node for ID ", pattern_id)

func create_connection_visualization(from_id: int, to_id: int, relation_type: String = "default") -> void:
	if not pattern_container:
		printerr("PatternViewer: Cannot create connection, pattern_container is null")
		return
		
	if not pattern_graph:
		printerr("PatternViewer: Cannot create connection, pattern_graph is null")
		return
		
	if not pattern_connection_scene:
		printerr("PatternViewer: Cannot create connection, pattern_connection_scene is null")
		return
	
	var key = "%d_%d" % [from_id, to_id]
	
	if _connection_nodes.has(key):
		return
	
	var from_pattern = pattern_graph.get_pattern(from_id)
	var to_pattern = pattern_graph.get_pattern(to_id)
	
	if from_pattern and to_pattern:
		# Check if position values exist
		if not from_pattern.position or not to_pattern.position:
			printerr("PatternViewer: Cannot create connection, pattern positions are invalid")
			return
			
		var start_pos = from_pattern.position
		var end_pos = to_pattern.position
		
		if not start_pos or not end_pos:
			printerr("PatternViewer: Cannot create connection, pattern positions are null")
			return
		
		var connection = pattern_connection_scene.instantiate()
		pattern_container.add_child(connection)
		
		# Position at midpoint
		connection.position = (start_pos + end_pos) / 2.0
		
		# Orient towards target
		var direction = (end_pos - start_pos).normalized()
		if direction.length() > 0.001:
			connection.look_at(end_pos, Vector3.UP)
		
		# Scale to match distance
		var distance = start_pos.distance_to(end_pos)
		connection.scale = Vector3(1, 1, distance)
		
		# Set color based on relation type
		var cylinder = connection.get_node("CSGCylinder3D")
		var material = StandardMaterial3D.new()
		material.albedo_color = connection_colors.get(relation_type, connection_colors.default)
		material.metallic = 0.5
		material.roughness = 0.8
		cylinder.material = material
		
		_connection_nodes[key] = connection

func update_pattern_position(pattern_id: int, new_position: Vector3) -> void:
	if not pattern_graph:
		printerr("PatternViewer: Cannot update pattern position, pattern_graph is null")
		return
		
	pattern_graph.update_pattern_position(pattern_id, new_position)
	
	if _pattern_nodes.has(pattern_id):
		_pattern_nodes[pattern_id].position = new_position
		
		# Update connections
		for key in _connection_nodes:
			var ids = key.split("_")
			if ids.size() < 2:
				continue
				
			var from_id = int(ids[0])
			var to_id = int(ids[1])
			
			if from_id == pattern_id or to_id == pattern_id:
				var connection = _connection_nodes[key]
				if not connection:
					continue
					
				var from_pattern = pattern_graph.get_pattern(from_id)
				var to_pattern = pattern_graph.get_pattern(to_id)
				
				if not from_pattern or not to_pattern:
					continue
					
				if not from_pattern.position or not to_pattern.position:
					continue
				
				var from_pos = from_pattern.position
				var to_pos = to_pattern.position
				
				if not from_pos or not to_pos:
					continue
				
				connection.position = (from_pos + to_pos) / 2.0
				var direction = (to_pos - from_pos).normalized()
				if direction.length() > 0.001:
					connection.look_at(to_pos, Vector3.UP)
				
				var distance = from_pos.distance_to(to_pos)
				connection.scale = Vector3(1, 1, distance)

func clear_visualization() -> void:
	if not pattern_container:
		printerr("PatternViewer: Cannot clear visualization, pattern_container is null")
		return
	
	for node in _pattern_nodes.values():
		node.queue_free()
	
	for connection in _connection_nodes.values():
		connection.queue_free()
	
	_pattern_nodes.clear()
	_connection_nodes.clear()
	_selected_patterns.clear()
	_hovered_pattern = null

func visualize_patterns(patterns: Array) -> void:
	if not pattern_container:
		printerr("PatternViewer: Cannot visualize patterns, pattern_container is null")
		return
		
	if not pattern_graph:
		printerr("PatternViewer: Cannot visualize patterns, pattern_graph is null")
		return
		
	for pattern in patterns:
		create_pattern_visualization(pattern.id)

func visualize_relationships(relationships: Array) -> void:
	if not pattern_container:
		printerr("PatternViewer: Cannot visualize relationships, pattern_container is null")
		return
		
	if not pattern_graph:
		printerr("PatternViewer: Cannot visualize relationships, pattern_graph is null")
		return
		
	for relationship in relationships:
		create_connection_visualization(
			relationship.from, 
			relationship.to, 
			relationship.type
		)

func _exit_tree() -> void:
	# Clean up any resources
	for material in get_tree().get_nodes_in_group("pattern_materials"):
		material.free()
	
	for material in get_tree().get_nodes_in_group("connection_materials"):
		material.free()

# Public method for displaying patterns and relationships
func display_patterns(patterns: Array) -> void:
	if not pattern_container:
		printerr("PatternViewer: Cannot display patterns, pattern_container is null")
		return
		
	if not pattern_graph:
		printerr("PatternViewer: Cannot display patterns, pattern_graph is null")
		return
		
	clear_visualization()
	
	# First add all patterns
	for pattern in patterns:
		if pattern is Dictionary and pattern.has("id"):
			create_pattern_visualization(pattern.id)
		elif pattern.id != null:
			create_pattern_visualization(pattern.id)
	
	# Then add relationships between patterns
	for pattern in patterns:
		var relations = []
		if pattern is Dictionary and pattern.has("relations"):
			relations = pattern.get("relations", [])
		elif pattern.metadata.has("relations"):
			relations = pattern.metadata.get("relations", [])
		
		for relation in relations:
			var to_id = relation.get("id", -1)
			var rel_type = relation.get("type", "default")
			
			if to_id >= 0:
				if pattern is Dictionary and pattern.has("id"):
					create_connection_visualization(pattern.id, to_id, rel_type)
				elif pattern.id != null:
					create_connection_visualization(pattern.id, to_id, rel_type)

# Public method for clearing patterns
func clear_patterns() -> void:
	clear_visualization()
	
	# Also clear the pattern graph if it exists
	if pattern_graph:
		pattern_graph.clear()
	else:
		printerr("PatternViewer: Cannot clear pattern graph, pattern_graph is null")

func _on_pattern_selected(pattern_id: int) -> void:
	if not pattern_graph:
		printerr("PatternViewer: Cannot select pattern, pattern_graph is null")
		return
		
	var pattern = pattern_graph.get_pattern(pattern_id)
	if not pattern:
		printerr("PatternViewer: Cannot select pattern, pattern not found")
		return
		
	# Try to get metadata relationships to show
	var relations = []
	if pattern is Dictionary and pattern.has("relations"):
		relations = pattern.get("relations", [])
	elif pattern.metadata.has("relations"):
		relations = pattern.metadata.get("relations", [])
		
	# Highlight pattern
	_highlight_pattern(pattern_id)
	
	emit_signal("pattern_selected", pattern_id)

# Check if the pattern viewer has focus
func has_focus() -> bool:
	var viewport = get_viewport()
	if viewport and viewport is SubViewport:
		var container = viewport.get_parent()
		if container and container is SubViewportContainer:
			return container.has_focus()
	
	# If we're not in a SubViewportContainer or we couldn't determine focus,
	# default to allowing input processing in editor context
	return true

# New function to handle parent container input
func _on_parent_gui_input(event):
	# Automatically capture focus when clicked
	var viewport = get_viewport()
	if viewport and viewport is SubViewport:
		var container = viewport.get_parent()
		if container and container is SubViewportContainer:
			if event is InputEventMouseButton:
				if event.pressed:
					container.grab_focus()
					print("Grabbing focus for SubViewportContainer")
			
			# Forward the event to our own input handler
			_input(event)
			
			# Prevent arrow keys from navigating away by consuming them
			if event is InputEventKey:
				if event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT or event.keycode == KEY_UP or event.keycode == KEY_DOWN:
					get_viewport().set_input_as_handled() 