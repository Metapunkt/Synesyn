class_name StoryStagePresenter2D
extends StoryStagePresenter

var granted_rung := 0

var _stage: Node
var _speaker := ""
var _queued_speaker := ""
var _queued_rung := 0
var _expression := "neutral"
var _voiced := false
var _heard_audio := false
var _level := 0.0
var _marks: Dictionary = {}
var _mark := "center"
var _light: PointLight2D


func setup(stage: Node) -> void:
	_stage = stage
	sprite = stage.get_node("CanvasLayer2/Control/CharacterSprite") as StoryStageCharacterSprite
	sprite.bind_registry(stage.characters)
	_light = sprite.get_node_or_null("CueLight") as PointLight2D
	var control := _stage.get_node("CanvasLayer2/Control") as Control
	if not control.resized.is_connected(_on_stage_resized):
		control.resized.connect(_on_stage_resized)
	_layout_marks()
	_move("center")
	control.call_deferred("emit_signal", "resized")
	if stage.voice:
		if not stage.voice.speech_started.is_connected(_on_speech_started):
			stage.voice.speech_started.connect(_on_speech_started)
		if not stage.voice.playback_finished.is_connected(_on_speech_ended):
			stage.voice.playback_finished.connect(_on_speech_ended)
		if not stage.voice.speech_finished.is_connected(_on_speech_ended):
			stage.voice.speech_finished.connect(_on_speech_ended)


func show_line(speaker: String, _text: String, _cues: Variant = null, rung: int = 0) -> void:
	# The reply text can arrive while the previous voice is still playing.
	# Keep that face until its audio ends, so the mouth stays with the voice.
	if _voiced and _speaker != "" and speaker != _speaker:
		_queued_speaker = speaker
		_queued_rung = rung
		return
	if _voiced and speaker == _speaker:
		return
	_queued_speaker = ""
	_commit_line(speaker, rung)


func _commit_line(speaker: String, rung: int) -> void:
	_speaker = speaker
	_expression = "neutral"
	_voiced = false
	_heard_audio = false
	var line_rung := mini(rung, granted_rung) if granted_rung > 0 else rung
	sprite.allow_big = _stage.scenario_section_enabled("staging", true)
	sprite.enable_deform(line_rung >= 3)
	sprite.change_character_scensyn(speaker, false, "neutral")
	sprite.rotation = 0.0
	_layout_marks()
	if not sprite.allow_big:
		_move("center")
	_feed_spectrum()


func apply_cue(cue: Dictionary) -> void:
	var speaker := str(cue.get("speaker", _speaker))
	if speaker != "":
		_speaker = speaker
	if cue.has("expression"):
		_expression = str(cue["expression"])
	var intensity := float(cue.get("intensity", 0.0))
	if cue.has("mark"):
		_move(str(cue["mark"]))
	if cue.has("target"):
		set_gaze(str(cue["target"]))
	if cue.has("gesture"):
		play_gesture(str(cue["gesture"]))
	sprite.change_character_scensyn(_speaker, intensity > 0.05, _expression)
	sprite.set_talking_intensity(intensity)
	_set_light(intensity)


func set_mouth(viseme: String, intensity: float) -> void:
	sprite.set_mouth(viseme, intensity)


func set_gaze(target: String) -> void:
	var there: Vector2 = _marks.get(StoryStageCharacter.dir_slug(target), _marks.get(target, _marks.get("edge", sprite.position)))
	var dx := there.x - sprite.position.x
	sprite.rotation = clampf(dx / 900.0, -0.18, 0.18)


func play_gesture(gesture: String) -> void:
	var profile: Variant = sprite._details().get("profile") if sprite.has_method("_details") else null
	if profile is StoryStageCharacterProfile and (profile as StoryStageCharacterProfile).gestures.size() > 0:
		if not (profile as StoryStageCharacterProfile).gestures.has(gesture):
			return
	var rest := sprite.rotation
	var tween := create_tween()
	if gesture == "shake":
		tween.tween_property(sprite, "rotation", rest + 0.1, 0.1)
		tween.tween_property(sprite, "rotation", rest - 0.1, 0.12)
		tween.tween_property(sprite, "rotation", rest, 0.1)
	else:
		tween.tween_property(sprite, "rotation", rest - 0.08, 0.12)
		tween.tween_property(sprite, "rotation", rest, 0.16)


func set_talking(speaker: String, intensity: float) -> void:
	_speaker = speaker
	sprite.change_character_scensyn(speaker, intensity > 0.05, _expression)
	sprite.set_talking_intensity(intensity)


func apply_grant(rung: int) -> void:
	granted_rung = rung
	sprite.enable_deform(rung >= 3)


func on_line_released() -> void:
	_voiced = false
	_heard_audio = false
	if _speaker != "":
		sprite.change_character_scensyn(_speaker, false, "neutral")
		sprite.set_talking_intensity(0.0)
	_set_light(0.2)


func stop_cues() -> void:
	if _stage and _stage.cues:
		_stage.cues.stop()


func _on_speech_started(speaker: String) -> void:
	_voiced = true
	_heard_audio = false
	if _queued_speaker == speaker:
		_queued_speaker = ""
	if _speaker != speaker:
		sprite.change_character_scensyn(speaker, false, _expression)
	_speaker = speaker
	_stage.motion.bus_for(speaker)
	sprite.play_authored_talking()


func _on_speech_ended(_ended: String) -> void:
	_voiced = false
	_heard_audio = false
	_level = 0.0
	if sprite:
		sprite.set_talking_intensity(0.0)
	if _queued_speaker != "":
		var next := _queued_speaker
		var rung := _queued_rung
		_queued_speaker = ""
		_commit_line(next, rung)


func _process(delta: float) -> void:
	if sprite == null or _stage == null or _stage.motion == null:
		return
	_feed_spectrum()
	if not _voiced or _speaker == "":
		return
	var raw: float = _stage.motion.intensity(_speaker)
	var follow := 6.0
	if raw > _level:
		follow = 12.0
	_level = lerpf(_level, raw, clampf(delta * follow, 0.0, 1.0))
	if raw > 0.05:
		_heard_audio = true
	if not _heard_audio:
		return
	sprite.set_speech_level(_level)
	set_mouth(_viseme_now(_level), _level)
	_set_light(_level)


func _viseme_now(level: float) -> String:
	var frames: Array = _stage.voice.get_lipsync_frames(_speaker, _speaker)
	if frames.is_empty():
		return StoryStageViseme.from_intensity(level)
	var t: float = _stage.voice.playback_position()
	if t < 0.0:
		return StoryStageViseme.from_intensity(level)
	var chosen := "rest"
	for frame in frames:
		if frame is Dictionary and float(frame.get("time", 0.0)) <= t:
			chosen = str(frame.get("mouth_shape", "rest"))
	return StoryStageViseme.canonical(chosen)


func _feed_spectrum() -> void:
	var bars := sprite.get_node_or_null("Spectrum")
	if bars is StoryStageSpectrum and _stage.motion:
		bars.set_levels(_stage.motion.spectrum(_speaker))


func _on_stage_resized() -> void:
	_layout_marks()
	_move(_mark)


func _layout_marks() -> void:
	var control := _stage.get_node("CanvasLayer2/Control") as Control
	var size := control.size
	if size.x < 32.0 or size.y < 32.0:
		size = control.get_viewport_rect().size
	if size.x < 32.0 or size.y < 32.0:
		size = Vector2(1280, 720)
	if sprite:
		sprite.fit_portrait(size)
	var cy := size.y * 0.46
	var spots := {
		"center": Vector2(size.x * 0.50, cy),
		"left": Vector2(size.x * 0.30, cy),
		"right": Vector2(size.x * 0.70, cy),
		"window": Vector2(size.x * 0.16, size.y * 0.42),
		"edge": Vector2(size.x * 0.84, size.y * 0.48),
	}
	for mark_name in spots:
		var marker := control.get_node_or_null(mark_name) as Marker2D
		if marker == null:
			marker = Marker2D.new()
			marker.name = mark_name
			control.add_child(marker)
		marker.position = spots[mark_name]
		_marks[mark_name] = marker.position


func _move(mark_name: String) -> void:
	if not _marks.has(mark_name):
		return
	_mark = mark_name
	sprite.set_base_position(_marks[mark_name])


func _set_light(intensity: float) -> void:
	if _light:
		_light.energy = lerpf(0.35, 1.5, clampf(intensity, 0.0, 1.0))
