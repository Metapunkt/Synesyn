extends Node
class_name LipSyncAnimator

# LipSyncAnimator - Controls mouth blendshapes for lip sync animation
# Maps mouth shapes to blendshape values and handles smooth transitions

signal mouth_shape_changed(shape: String, intensity: float)

# Mouth shape definitions (blendshape targets)
var mouth_shapes = {
	"closed": {"mouth_open": 0.0, "mouth_wide": 0.0},
	"slightly_open": {"mouth_open": 0.3, "mouth_wide": 0.1},
	"open": {"mouth_open": 0.6, "mouth_wide": 0.3},
	"wide_open": {"mouth_open": 0.9, "mouth_wide": 0.6},
}

# Animation settings
@export var blend_speed: float = 8.0  # How fast to blend between shapes
@export var intensity_multiplier: float = 1.0  # Overall intensity scaling

# Current state
var target_avatar: CharacterAvatar
var mesh_instance: MeshInstance3D
var current_shape: String = "closed"
var current_intensity: float = 0.0
var target_blend_values: Dictionary = {}
var current_blend_values: Dictionary = {}

# Lip sync animation state
var lipsync_data: Array = []
var lipsync_start_time: float = 0.0
var is_animating: bool = false
var current_frame_index: int = 0
var external_elapsed_time: float = -1.0

func setup_avatar(avatar: CharacterAvatar):
	"""Initialize with a character avatar"""
	target_avatar = avatar
	_find_mesh_instance()
	_initialize_blend_shapes()

func _find_mesh_instance():
	"""Find the MeshInstance3D node in the avatar"""
	if not target_avatar:
		return
	
	# Look for MeshInstance3D in children
	mesh_instance = _find_node_of_type(target_avatar, "MeshInstance3D")
	
	if not mesh_instance:
		print("LipSyncAnimator: No MeshInstance3D found in avatar: ", target_avatar.character_name)
	else:
		print("LipSyncAnimator: Found mesh for avatar: ", target_avatar.character_name)

func _find_node_of_type(node: Node, type_name: String) -> Node:
	"""Recursively find a node of specific type"""
	if node.is_class(type_name):
		return node
	
	for child in node.get_children():
		var result = _find_node_of_type(child, type_name)
		if result:
			return result
	
	return null

func _initialize_blend_shapes():
	"""Initialize blend shape tracking"""
	if not mesh_instance or not mesh_instance.mesh:
		return
	
	# Initialize current blend values to zero
	current_blend_values = {"mouth_open": 0.0, "mouth_wide": 0.0}
	target_blend_values = current_blend_values.duplicate()
	
	print("LipSyncAnimator: Initialized blend shapes for: ", target_avatar.character_name)

func set_mouth_shape(shape: String, intensity: float = 1.0):
	"""Set target mouth shape with given intensity"""
	if not mouth_shapes.has(shape):
		print("LipSyncAnimator: Unknown mouth shape: ", shape)
		return
	
	current_shape = shape
	current_intensity = intensity * intensity_multiplier
	
	# Set target blend values
	var shape_data = mouth_shapes[shape]
	for blend_name in shape_data:
		target_blend_values[blend_name] = shape_data[blend_name] * current_intensity
	
	mouth_shape_changed.emit(shape, current_intensity)

func _process(delta):
	"""Update blend shape animations"""
	# Update lip sync animation first
	_update_lipsync_animation()
	
	if not mesh_instance or target_blend_values.is_empty():
		return
	
	# Smoothly blend towards target values
	var changed = false
	for blend_name in target_blend_values:
		var current_val = current_blend_values.get(blend_name, 0.0)
		var target_val = target_blend_values[blend_name]
		
		if abs(current_val - target_val) > 0.01:
			var new_val = lerp(current_val, target_val, blend_speed * delta)
			current_blend_values[blend_name] = new_val
			_apply_blend_shape(blend_name, new_val)
			changed = true

func _apply_blend_shape(blend_name: String, value: float):
	"""Apply blend shape value to mesh (placeholder for actual implementation)"""
	if not mesh_instance or not mesh_instance.mesh:
		return
	
	# This is a placeholder - in a real implementation you would:
	# 1. Find the blend shape index by name
	# 2. Set the blend shape weight
	# mesh_instance.set_blend_shape_weight(blend_index, value)
	
	# For now, just log for debugging
	if value > 0.1:  # Only log significant values to reduce spam
		print("LipSyncAnimator: ", target_avatar.character_name, " - ", blend_name, ": ", "%.2f" % value)

func reset_mouth():
	"""Reset mouth to closed position"""
	set_mouth_shape("closed", 0.0)

func get_current_shape() -> String:
	"""Get current mouth shape"""
	return current_shape

func get_current_intensity() -> float:
	"""Get current intensity"""
	return current_intensity

func set_blend_speed(speed: float):
	"""Update blend speed"""
	blend_speed = speed

func set_intensity_multiplier(multiplier: float):
	"""Update intensity scaling"""
	intensity_multiplier = multiplier

func start_lipsync_animation(sync_data: Array):
	"""Start lip sync animation with timed data"""
	lipsync_data = sync_data
	lipsync_start_time = Time.get_ticks_msec() / 1000.0
	is_animating = true
	current_frame_index = 0
	external_elapsed_time = -1.0
	
	print("LipSyncAnimator: Started lip sync animation with ", sync_data.size(), " frames for ", target_avatar.character_name if target_avatar else "unknown")

func stop_lipsync_animation():
	"""Stop lip sync animation and reset to closed mouth"""
	is_animating = false
	lipsync_data.clear()
	current_frame_index = 0
	reset_mouth()
	external_elapsed_time = -1.0
	
	print("LipSyncAnimator: Stopped lip sync animation for ", target_avatar.character_name if target_avatar else "unknown")

func set_external_elapsed_time(seconds: float):
	"""Provide audio-driven elapsed time for frame-accurate sync"""
	external_elapsed_time = max(0.0, seconds)

func _update_lipsync_animation():
	"""Update lip sync animation based on current time"""
	if not is_animating or lipsync_data.is_empty():
		return
	
	var elapsed_time = 0.0
	if external_elapsed_time >= 0.0:
		elapsed_time = external_elapsed_time
	else:
		var current_time = Time.get_ticks_msec() / 1000.0
		elapsed_time = current_time - lipsync_start_time
	
	# Find the appropriate frame for current time
	while current_frame_index < lipsync_data.size():
		var frame_data = lipsync_data[current_frame_index]
		var frame_time = frame_data.get("time", 0.0)
		
		if frame_time > elapsed_time:
			break
		
		# Apply this frame's lip sync data
		var mouth_open = frame_data.get("mouth_open", 0.0)
		var viseme = frame_data.get("viseme", "closed")
		var mouth_shape = _viseme_to_mouth_shape(viseme, mouth_open)
		
		set_mouth_shape(mouth_shape, mouth_open)
		
		current_frame_index += 1
	
	# Check if animation is complete
	if current_frame_index >= lipsync_data.size():
		stop_lipsync_animation()

func _viseme_to_mouth_shape(viseme: String, mouth_open: float) -> String:
	"""Convert viseme and mouth_open value to mouth shape name"""
	match viseme:
		"mouth_e":
			return "open" if mouth_open > 0.5 else "slightly_open"
		"mouth_s":
			return "slightly_open"
		"mouth_o":
			return "wide_open" if mouth_open > 0.6 else "open"
		"mouth_u":
			return "open"
		_:
			# Fallback to mouth_open intensity
			if mouth_open < 0.1:
				return "closed"
			elif mouth_open < 0.4:
				return "slightly_open"
			elif mouth_open < 0.7:
				return "open"
			else:
				return "wide_open" 
