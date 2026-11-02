extends Node
class_name EmotionController

# EmotionController - Manages facial expressions and emotional states
# Handles emotion detection from text and expression animation

signal emotion_changed(emotion: String, intensity: float)

# Emotion definitions (expression blendshape targets)
var emotions = {
	"neutral": {
		"eyebrow_raise": 0.0,
		"eyebrow_furrow": 0.0,
		"eye_squint": 0.0,
		"smile": 0.0
	},
	"happy": {
		"eyebrow_raise": 0.2,
		"eyebrow_furrow": 0.0,
		"eye_squint": 0.3,
		"smile": 0.8
	},
	"concerned": {
		"eyebrow_raise": 0.0,
		"eyebrow_furrow": 0.6,
		"eye_squint": 0.2,
		"smile": 0.0
	},
	"determined": {
		"eyebrow_raise": 0.0,
		"eyebrow_furrow": 0.4,
		"eye_squint": 0.1,
		"smile": 0.2
	},
	"surprised": {
		"eyebrow_raise": 0.8,
		"eyebrow_furrow": 0.0,
		"eye_squint": 0.0,
		"smile": 0.1
	}
}

# Emotion keywords for text analysis
var emotion_keywords = {
	"happy": ["happy", "joy", "excited", "pleased", "delighted", "cheerful"],
	"concerned": ["worried", "concerned", "anxious", "troubled", "uneasy"],
	"determined": ["determined", "focused", "resolved", "committed", "decisive"],
	"surprised": ["surprised", "shocked", "amazed", "astonished", "startled"]
}

# Animation settings
@export var blend_speed: float = 6.0  # How fast to blend between emotions
@export var auto_detect_emotion: bool = true  # Automatically detect emotion from text
@export var emotion_intensity: float = 1.0  # Overall emotion intensity

# Current state
var target_avatar: CharacterAvatar
var mesh_instance: MeshInstance3D
var current_emotion: String = "neutral"
var target_blend_values: Dictionary = {}
var current_blend_values: Dictionary = {}

func setup_avatar(avatar: CharacterAvatar):
	"""Initialize with a character avatar"""
	target_avatar = avatar
	_find_mesh_instance()
	_initialize_expressions()

func _find_mesh_instance():
	"""Find the MeshInstance3D node in the avatar"""
	if not target_avatar:
		return
	
	# Look for MeshInstance3D in children
	mesh_instance = _find_node_of_type(target_avatar, "MeshInstance3D")
	
	if not mesh_instance:
		print("EmotionController: No MeshInstance3D found in avatar: ", target_avatar.character_name)
	else:
		print("EmotionController: Found mesh for avatar: ", target_avatar.character_name)

func _find_node_of_type(node: Node, type_name: String) -> Node:
	"""Recursively find a node of specific type"""
	if node.is_class(type_name):
		return node
	
	for child in node.get_children():
		var result = _find_node_of_type(child, type_name)
		if result:
			return result
	
	return null

func _initialize_expressions():
	"""Initialize expression blend shape tracking"""
	if not mesh_instance or not mesh_instance.mesh:
		return
	
	# Initialize current blend values to neutral
	current_blend_values = emotions["neutral"].duplicate()
	target_blend_values = current_blend_values.duplicate()
	
	print("EmotionController: Initialized expressions for: ", target_avatar.character_name)

func set_emotion(emotion: String, intensity: float = 1.0):
	"""Set target emotion with given intensity"""
	if not emotions.has(emotion):
		print("EmotionController: Unknown emotion: ", emotion)
		return
	
	current_emotion = emotion
	var final_intensity = intensity * emotion_intensity
	
	# Set target blend values
	var emotion_data = emotions[emotion]
	for blend_name in emotion_data:
		target_blend_values[blend_name] = emotion_data[blend_name] * final_intensity
	
	emotion_changed.emit(emotion, final_intensity)
	print("EmotionController: ", target_avatar.character_name, " emotion set to: ", emotion)

func detect_emotion_from_text(text: String) -> String:
	"""Analyze text to detect emotional content"""
	if not auto_detect_emotion:
		return "neutral"
	
	var text_lower = text.to_lower()
	var emotion_scores = {}
	
	# Score each emotion based on keyword matches
	for emotion in emotion_keywords:
		var score = 0
		for keyword in emotion_keywords[emotion]:
			if text_lower.find(keyword) != -1:
				score += 1
		emotion_scores[emotion] = score
	
	# Find highest scoring emotion
	var best_emotion = "neutral"
	var best_score = 0
	
	for emotion in emotion_scores:
		if emotion_scores[emotion] > best_score:
			best_score = emotion_scores[emotion]
			best_emotion = emotion
	
	return best_emotion

func set_emotion_from_text(text: String, intensity: float = 1.0):
	"""Detect and set emotion based on text content"""
	var detected_emotion = detect_emotion_from_text(text)
	set_emotion(detected_emotion, intensity)

func _process(delta):
	"""Update expression animations"""
	if not mesh_instance or target_blend_values.is_empty():
		return
	
	# Smoothly blend towards target values
	for blend_name in target_blend_values:
		var current_val = current_blend_values.get(blend_name, 0.0)
		var target_val = target_blend_values[blend_name]
		
		if abs(current_val - target_val) > 0.01:
			var new_val = lerp(current_val, target_val, blend_speed * delta)
			current_blend_values[blend_name] = new_val
			_apply_expression_blend(blend_name, new_val)

func _apply_expression_blend(blend_name: String, value: float):
	"""Apply expression blend shape value to mesh (placeholder)"""
	if not mesh_instance or not mesh_instance.mesh:
		return
	
	# This is a placeholder - in a real implementation you would:
	# 1. Find the blend shape index by name
	# 2. Set the blend shape weight
	# mesh_instance.set_blend_shape_weight(blend_index, value)
	
	# For now, just log for debugging (only significant values)
	if value > 0.1:
		print("EmotionController: ", target_avatar.character_name, " - ", blend_name, ": ", "%.2f" % value)

func reset_emotion():
	"""Reset to neutral emotion"""
	set_emotion("neutral", 0.0)

func get_current_emotion() -> String:
	"""Get current emotion"""
	return current_emotion

func set_blend_speed(speed: float):
	"""Update blend speed"""
	blend_speed = speed

func set_emotion_intensity(intensity: float):
	"""Update overall emotion intensity"""
	emotion_intensity = intensity

func enable_auto_detection(enabled: bool):
	"""Enable/disable automatic emotion detection"""
	auto_detect_emotion = enabled 