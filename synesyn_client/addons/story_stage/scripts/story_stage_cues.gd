class_name StoryStageCuePlayer
extends Node

## Fires staging cues against the line's audio clock.

var _stage: Node
var _pending: Array = []
var _running := false
var _elapsed := 0.0


func setup(stage: Node) -> void:
	_stage = stage


func start(cues: Variant, voiced: bool) -> void:
	stop()
	if _stage == null or not _stage.scenario_section_enabled("staging", true):
		return
	var list: Array = []
	if cues is Array:
		list = cues
	elif cues is Dictionary and not (cues as Dictionary).is_empty():
		list = [cues]
	for item in list:
		if not (item is Dictionary):
			continue
		var at := float((item as Dictionary).get("at", 0.0))
		if at <= 0.0:
			_stage.presenter.apply_cue(item)
		else:
			_pending.append({"at": at, "cue": item})
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))
	_running = voiced and not _pending.is_empty()


func stop() -> void:
	_running = false
	_pending.clear()
	_elapsed = 0.0


func _process(delta: float) -> void:
	if not _running or _stage == null:
		return
	var position := -1.0
	if _stage.voice:
		position = _stage.voice.playback_position()
	_elapsed = position if position >= 0.0 else _elapsed + delta
	while not _pending.is_empty() and float(_pending[0]["at"]) <= _elapsed:
		var cue: Dictionary = _pending.pop_front()["cue"]
		_stage.presenter.apply_cue(cue)
	if _pending.is_empty():
		_running = false
