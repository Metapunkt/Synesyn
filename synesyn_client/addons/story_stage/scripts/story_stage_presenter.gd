class_name StoryStagePresenter
extends Node

## Draws a line. The 2D presenter and a later 3D presenter share this surface.

var sprite: StoryStageCharacterSprite


func setup(_stage: Node) -> void:
	pass


func show_line(_speaker: String, _text: String, _cues: Variant = null, _rung: int = 0) -> void:
	pass


func apply_cue(_cue: Dictionary) -> void:
	pass


func set_mouth(_viseme: String, _intensity: float) -> void:
	pass


func set_gaze(_target: String) -> void:
	pass


func play_gesture(_gesture: String) -> void:
	pass


func set_talking(_speaker: String, _intensity: float) -> void:
	pass


func apply_grant(_rung: int) -> void:
	pass


func on_line_released() -> void:
	pass


func stop_cues() -> void:
	pass
