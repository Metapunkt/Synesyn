class_name StoryStageLineFeed
extends Node

## Walks the host's log one entry at a time.

var read_pause_scale: float = 1.0

var _stage: Node
var _next_index := 0
var _paused := false
var _waiting_playback := false
var _wait_speaker := ""
var _voiced_ahead := -1
var _hold: Timer
var _watchdog: Timer
var _stuck: Timer
var _synth_duration := -1.0
var _shown_at_msec := 0


func initialize(stage: Node) -> void:
	_stage = stage
	_hold = Timer.new()
	_hold.one_shot = true
	_hold.timeout.connect(_on_hold_done)
	add_child(_hold)
	_watchdog = Timer.new()
	_watchdog.wait_time = 0.5
	_watchdog.timeout.connect(func() -> void: check_story_log_for_new_entries(stage))
	add_child(_watchdog)
	_watchdog.start()
	_stuck = Timer.new()
	_stuck.one_shot = true
	_stuck.timeout.connect(_on_stuck)
	add_child(_stuck)
	if stage.voice:
		stage.voice.playback_finished.connect(_on_playback_finished)
		if stage.voice.has_signal("speech_finished"):
			stage.voice.speech_finished.connect(_on_playback_finished)
		stage.voice.synthesis_completed.connect(_on_synthesis)
		stage.voice.speech_started.connect(_on_speech_started)
	if stage.host and stage.host.has_signal("story_log_changed"):
		stage.host.story_log_changed.connect(_on_log_changed)
	if stage.host and stage.host.has_method("plays_existing_log") and not stage.host.plays_existing_log():
		var existing: Array = stage.host.get_story_log_entries()
		_next_index = existing.size()
		_restage_last(existing)


func queue_next_entry() -> void:
	if _stage == null or _paused:
		return
	# This caption stays until its own playback ends. The next line can be
	# synthesized during that time, and it is not played until it is on screen.
	if _stage.is_displaying_message or _waiting_playback:
		if _waiting_playback:
			_prefetch_upcoming()
		return
	var entries: Array = _stage.host.get_story_log_entries()
	while _next_index < entries.size():
		var index := _next_index
		var entry: Variant = entries[index]
		if _skipped(entry):
			_next_index += 1
			continue
		_show(entry as Dictionary, index)
		return


func reset_story_progress(stage: Node = null) -> void:
	if stage != null:
		_stage = stage
	_next_index = 0
	_waiting_playback = false
	_wait_speaker = ""
	_voiced_ahead = -1
	_synth_duration = -1.0
	_cancel_timers()
	if _stage:
		_stage.last_displayed_index = -1
		_stage.is_displaying_message = false
		_stage.release_line_visuals()


func set_paused(value: bool) -> void:
	_paused = value
	if _hold:
		_hold.paused = value
	if not value:
		queue_next_entry()


func check_story_log_for_new_entries(_stage_node: Node = null) -> void:
	if _paused:
		return
	queue_next_entry()


func arm_playback_wait() -> void:
	_waiting_playback = true


func release_current() -> void:
	_waiting_playback = false
	_cancel_timers()
	_finish()


func abandon_wait() -> void:
	_waiting_playback = false
	_wait_speaker = ""
	_voiced_ahead = -1
	_cancel_timers()


func _show(entry: Dictionary, index: int) -> void:
	var sender := str(entry.get("sender", "")).strip_edges()
	var message := strip_sender_prefix(sender, str(entry.get("message", "")))
	var already_spoken := index == _voiced_ahead
	_voiced_ahead = -1
	_stage.is_displaying_message = true
	_stage.last_displayed_index = index
	_next_index = index + 1
	_shown_at_msec = Time.get_ticks_msec()
	_waiting_playback = false
	_wait_speaker = ""
	if sender != "" and not sender.begins_with("[") and _stage.voice != null and _stage.voice.has_method("enable_character"):
		_stage.voice.enable_character(sender)
	var voiced := _should_voice(sender, message)
	_stage.present_log_line(sender, message, entry, index, voiced)
	if voiced:
		var accepted := already_spoken
		if not already_spoken:
			accepted = bool(_stage.voice.speak(sender, message, str(entry.get("emotion", "neutral"))))
		if not accepted:
			_start_hold(message)
			return
		_waiting_playback = true
		_wait_speaker = sender
		if _stuck:
			_stuck.start(45.0)
		return
	_start_hold(message)


func _prefetch_upcoming() -> void:
	if _voiced_ahead >= 0 or _stage == null or _stage.voice == null:
		return
	var entries: Array = _stage.host.get_story_log_entries()
	var index := _next_index
	while index < entries.size():
		var entry: Variant = entries[index]
		if _skipped(entry):
			index += 1
			continue
		var sender := str(entry.get("sender", "")).strip_edges()
		var message := strip_sender_prefix(sender, str(entry.get("message", "")))
		if sender != "" and not sender.begins_with("[") and _stage.voice.has_method("enable_character"):
			_stage.voice.enable_character(sender)
		if not _should_voice(sender, message):
			return
		if _stage.voice.speak(sender, message, str(entry.get("emotion", "neutral"))):
			_voiced_ahead = index
		return


func _should_voice(sender: String, message: String) -> bool:
	if not _stage.voice_on():
		return false
	if _stage.voice.get_skip_welcome() and sender == "Narrator" and message == _stage.welcome_text():
		return false
	return _stage.voice.should_speak(sender, message)


func _start_hold(message: String) -> void:
	var animation := 0.0
	if _stage.has_method("_calculate_text_animation_duration"):
		animation = float(_stage._calculate_text_animation_duration(message))
	var scale := read_pause_scale
	var hold := maxf(animation + 3.0 * scale, maxf(1.5 * minf(scale, 1.0), 0.05))
	_hold.start(hold)


func _on_hold_done() -> void:
	if _waiting_playback:
		return
	_finish()


func _on_playback_finished(speaker: String) -> void:
	if not _waiting_playback:
		return
	# The line on screen may already be the reply. The player's audio ending
	# must not dismiss that reply.
	if _wait_speaker != "" and speaker != _wait_speaker:
		return
	_waiting_playback = false
	_wait_speaker = ""
	_stuck.stop()
	_finish()


func _on_speech_started(_speaker: String) -> void:
	_stage.note_speech_started(_speaker)


func _on_synthesis(speaker: String, duration: float) -> void:
	if _wait_speaker != "" and speaker != _wait_speaker:
		return
	_synth_duration = duration
	if duration > 0.0 and _stuck:
		_stuck.start(duration + 20.0)
	_stage.note_synthesis(speaker, duration)


func _on_stuck() -> void:
	if _stage.is_lull_speaking:
		return
	_stage.voice.recover_stuck_speaker()
	_waiting_playback = false
	_wait_speaker = ""
	_voiced_ahead = -1
	_stage.is_displaying_message = false
	_finish()


func _finish() -> void:
	if _stage == null:
		return
	_stage.is_displaying_message = false
	_stage.release_line_visuals()
	queue_next_entry()


func _on_log_changed() -> void:
	check_story_log_for_new_entries(_stage)


func _restage_last(entries: Array) -> void:
	for i in range(entries.size() - 1, -1, -1):
		if _skipped(entries[i]):
			continue
		var entry: Dictionary = entries[i]
		var sender := str(entry.get("sender", "")).strip_edges()
		var message := strip_sender_prefix(sender, str(entry.get("message", "")))
		_stage.restage_visible_line(sender, message)
		return


func _cancel_timers() -> void:
	if _hold:
		_hold.stop()
	if _stuck:
		_stuck.stop()


func _skipped(entry: Variant) -> bool:
	if not (entry is Dictionary):
		return true
	var sender := str(entry.get("sender", "")).strip_edges()
	var message := str(entry.get("message", "")).strip_edges()
	return sender == "" or sender == "_meta" or message == ""


func strip_sender_prefix(sender: String, message: String) -> String:
	var text := message
	var bbcode := "[font_size=16][b]%s:[/b][/font_size]" % sender
	if text.begins_with(bbcode):
		text = text.substr(bbcode.length())
	var plain := sender + ":"
	if text.begins_with(plain):
		text = text.substr(plain.length())
	return text.strip_edges()
