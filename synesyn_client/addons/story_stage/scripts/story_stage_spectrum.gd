class_name StoryStageSpectrum
extends Node2D

## Stands in for a speaker who has no portrait folder.

var _levels := PackedFloat32Array()
var _active := true


func set_levels(levels: PackedFloat32Array) -> void:
	_levels = levels
	queue_redraw()


func set_active(active: bool) -> void:
	_active = active
	visible = active
	if active:
		queue_redraw()


func _process(_delta: float) -> void:
	if _active:
		queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var count := 16
	var width := 8.0
	var gap := 4.0
	var origin := Vector2(-((width + gap) * count) * 0.5, 40.0)
	for i in count:
		var level := 0.08
		if i < _levels.size():
			level = maxf(_levels[i], 0.08)
		else:
			level = 0.08 + 0.06 * absf(sin(Time.get_ticks_msec() / 320.0 + float(i)))
		var height := 28.0 + level * 140.0
		var rect := Rect2(origin + Vector2(float(i) * (width + gap), -height), Vector2(width, height))
		draw_rect(rect, Color(0.93, 0.86, 0.72, 0.9), true)
