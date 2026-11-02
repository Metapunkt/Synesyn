class_name StoryStageUi
extends Control

var _stage
var _full := ""
var _voiced := false
var _recording := false
var _recorder: Node
var _chrome_tween: Tween
var _chrome_hold: Timer
var _chrome_hover := false
var _scroll_on := false
var _scroll_speaker := ""
var _scroll_span_s := 0.0
var _scroll_from_ms := 0
var _scroll_fraction := 0.0
var _speech_seconds := {}


func _node(unique: String):
	var root = owner if owner != null else self
	if unique == "DialogBox" or unique == "SpeakerBox":
		return root.get_node("CanvasLayer2/DialogUI/" + unique)
	return root.get_node("%" + unique)


func _ready() -> void:
	_stage = owner
	_style()
	_apply_features()
	_node("TextBlipTimer").timeout.connect(_on_blip)
	_node("SentencePauseTimer").timeout.connect(_on_sentence_done)
	_node("TextBlipSound").stream = _blip()
	_node("HamburgerMenuBtn").pressed.connect(_toggle_settings)
	_node("SwitchToChatModeBtn").pressed.connect(func() -> void: _stage.host.navigate(_stage, "story_log"))
	_node("BackButton").pressed.connect(func() -> void: _stage.host.navigate(_stage, "landing"))
	_node("ServicesButton").pressed.connect(_on_services)
	_node("NewStoryLogButton").pressed.connect(_confirm_new_log)
	_node("LoadStoryLogButton").pressed.connect(_load_log)
	_node("DualWindowToggle").toggled.connect(func(on: bool) -> void: _stage.host.set_dual_window(on))
	_node("SaveSttRecordingsToggle").toggled.connect(_on_save_recordings)
	_node("TtsToggleStoryStage").toggled.connect(func(on: bool) -> void: _stage.host.set_stage_owns_voice(on))
	_node("SkipWelcomeToggle").toggled.connect(_on_skip_welcome)
	_node("OutputVolumeSlider").value_changed.connect(_on_output_volume)
	_node("PauseTtsButton").pressed.connect(_on_pause)
	_node("ResumeTtsButton").pressed.connect(_on_resume)
	_node("SkipTtsButton").pressed.connect(_on_skip)
	_node("ShowInputToggle").toggled.connect(func(on: bool) -> void: _node("InputContainer").visible = on)
	_node("SendButton").pressed.connect(_send)
	_node("InputField").text_submitted.connect(func(_t: String) -> void: _send())
	var record := _node("StageRecordButton") as BaseButton
	record.toggle_mode = true
	record.toggled.connect(_on_record_toggled)
	_node("AvatarHealthToggle").toggled.connect(func(on: bool) -> void: _node("AvatarHealthLabel").visible = on)
	_node("StageAutoPlayerInput").toggled.connect(_on_auto_toggled)
	_chrome_hold = Timer.new()
	_chrome_hold.one_shot = true
	_chrome_hold.timeout.connect(_fade_chrome)
	add_child(_chrome_hold)
	if _stage.host.has_signal("voice_owner_changed"):
		_stage.host.voice_owner_changed.connect(func(on: bool) -> void: _node("TtsToggleStoryStage").set_pressed_no_signal(on))


func bind_runtime(stage: Node) -> void:
	_stage = stage
	_node("TtsToggleStoryStage").set_pressed_no_signal(stage.host.stage_owns_voice())
	_node("SaveSttRecordingsToggle").set_pressed_no_signal(stage.host.get_save_recordings())
	_node("SkipWelcomeToggle").set_pressed_no_signal(stage.voice.get_skip_welcome())
	if stage.motion:
		_node("OutputVolumeSlider").set_value_no_signal(stage.motion.output_linear() * 100.0)
	if not stage.voice.transcription_completed.is_connected(_on_transcript):
		stage.voice.transcription_completed.connect(_on_transcript)
	_bind_dialog_scroll(stage)
	_ensure_recorder()
	_bind_auto_input()
	_refresh_health()


func present_line(speaker: String, text: String, voiced: bool, choices: Array = []) -> void:
	_full = text
	_voiced = voiced
	_scroll_on = false
	_scroll_speaker = ""
	_node("SpeakerName").text = speaker
	var label := _node("DialogLine") as RichTextLabel
	# scroll_following would jump to the last line the moment the text is set.
	label.scroll_following = false
	label.text = text
	_show_chrome()
	_fill_choices(choices)
	_park_dialog_top()
	if voiced:
		label.visible_characters = -1
		_node("TextBlipTimer").stop()
		call_deferred("_park_dialog_top")
		return
	label.visible_characters = 0
	_node("TextBlipTimer").start()


func stop_typewriter() -> void:
	_node("TextBlipTimer").stop()
	_node("SentencePauseTimer").stop()
	_scroll_on = false
	if _node("DialogLine").visible_characters >= 0:
		_node("DialogLine").visible_characters = -1


## The spoken line is taller than the box. Move the scrollbar with the audio
## that is playing, from the first line to the last. A duration learned while
## the line was still held is kept by speaker, so the scroll uses that length
## when playback actually starts.
func _bind_dialog_scroll(stage: Node) -> void:
	var voice: Node = stage.voice
	if voice == null:
		return
	if voice.has_signal("speech_started") and not voice.speech_started.is_connected(_on_speech_scroll_started):
		voice.speech_started.connect(_on_speech_scroll_started)
	if voice.has_signal("speech_finished") and not voice.speech_finished.is_connected(_on_speech_scroll_finished):
		voice.speech_finished.connect(_on_speech_scroll_finished)
	if voice.has_signal("synthesis_completed") and not voice.synthesis_completed.is_connected(_on_speech_duration):
		voice.synthesis_completed.connect(_on_speech_duration)


func _on_speech_duration(speaker: String, duration: float) -> void:
	if duration <= 0.0:
		return
	_speech_seconds[speaker] = duration
	if _scroll_on and speaker == _scroll_speaker:
		_scroll_span_s = duration


func _on_speech_scroll_started(speaker: String) -> void:
	if not _voiced:
		return
	_begin_scroll(speaker, false)


func _on_speech_scroll_finished(speaker: String) -> void:
	if speaker != _scroll_speaker:
		return
	_scroll_on = false


func _begin_scroll(speaker: String, retried: bool) -> void:
	if str(_node("SpeakerName").text) != speaker:
		return
	var label := _node("DialogLine") as RichTextLabel
	if label == null:
		return
	label.scroll_following = false
	var bar := label.get_v_scroll_bar()
	if bar == null or bar.max_value <= bar.page:
		_scroll_on = false
		if not retried:
			call_deferred("_begin_scroll", speaker, true)
		return
	var seconds := float(_speech_seconds.get(speaker, 0.0))
	if seconds <= 0.0:
		seconds = maxf(float(label.get_parsed_text().length()) / 12.5, 3.0)
	_scroll_speaker = speaker
	_scroll_span_s = seconds
	_scroll_from_ms = Time.get_ticks_msec()
	_scroll_fraction = 0.0
	bar.value = 0.0
	_scroll_on = true


func _park_dialog_top() -> void:
	if _scroll_on:
		return
	var label := _node("DialogLine") as RichTextLabel
	if label == null:
		return
	label.scroll_following = false
	var bar := label.get_v_scroll_bar()
	if bar:
		bar.value = 0.0


func _tick_dialog_scroll() -> void:
	if not _scroll_on or _scroll_span_s <= 0.0:
		return
	var label := _node("DialogLine") as RichTextLabel
	if label == null:
		return
	var bar := label.get_v_scroll_bar()
	if bar == null or bar.max_value <= bar.page:
		return
	var position := -1.0
	if _stage and _stage.voice and _stage.voice.has_method("playback_position"):
		position = float(_stage.voice.playback_position())
	if position >= 0.0:
		_scroll_fraction = clampf(position / _scroll_span_s, 0.0, 1.0)
	elif _scroll_fraction <= 0.0:
		var elapsed_s := float(Time.get_ticks_msec() - _scroll_from_ms) / 1000.0
		_scroll_fraction = clampf(elapsed_s / _scroll_span_s, 0.0, 1.0)
	bar.value = _scroll_fraction * (bar.max_value - bar.page)


func fade_if_idle(stage: Node) -> void:
	if stage.is_displaying_message or stage.is_lull_speaking or _chrome_hover:
		return
	_arm_chrome_fade()


func _process(_delta: float) -> void:
	_tick_dialog_scroll()
	if _node("AvatarHealthLabel").visible:
		_refresh_health()
	var over := _pointer_over_chrome()
	if over:
		if not _chrome_hover:
			_chrome_hover = true
			if _chrome_hold:
				_chrome_hold.stop()
			_show_chrome()
	elif _chrome_hover:
		_chrome_hover = false
		if _stage == null or (not _stage.is_displaying_message and not _stage.is_lull_speaking):
			_arm_chrome_fade()


func _pointer_over_chrome() -> bool:
	var mouse := get_viewport().get_mouse_position()
	for box_name in ["DialogBox", "SpeakerBox", "InputContainer"]:
		var box := _node(box_name) as Control
		if box and box.visible and box.get_global_rect().has_point(mouse):
			return true
	return false


func _show_chrome() -> void:
	if _chrome_hold:
		_chrome_hold.stop()
	if _chrome_tween:
		_chrome_tween.kill()
	_node("DialogBox").modulate.a = 1.0
	_node("SpeakerBox").modulate.a = 1.0
	_node("InputContainer").modulate.a = 1.0


func _arm_chrome_fade() -> void:
	if _chrome_hold == null or _chrome_hover:
		return
	_chrome_hold.start(3.0)


func _fade_chrome() -> void:
	if _chrome_hover or _stage == null:
		return
	if _stage.is_displaying_message or _stage.is_lull_speaking:
		return
	if _chrome_tween:
		_chrome_tween.kill()
	_chrome_tween = create_tween()
	_chrome_tween.tween_property(_node("DialogBox"), "modulate:a", 0.4, 0.6)
	_chrome_tween.parallel().tween_property(_node("SpeakerBox"), "modulate:a", 0.4, 0.6)
	_chrome_tween.parallel().tween_property(_node("InputContainer"), "modulate:a", 0.4, 0.6)


func set_loading(show: bool) -> void:
	var label := get_node_or_null("LoadingIndicator") as Label
	if label:
		label.visible = show


func _apply_features() -> void:
	var host: StoryStageHost = _stage.host
	_node("SwitchToChatModeBtn").visible = host.supports(StoryStageHost.FEATURE_STORY_LOG_VIEW)
	_node("BackButton").visible = host.supports(StoryStageHost.FEATURE_LANDING)
	_node("ServicesButton").visible = host.supports(StoryStageHost.FEATURE_SERVICES)
	_node("NewStoryLogButton").visible = host.supports(StoryStageHost.FEATURE_NEW_STORY_LOG)
	_node("LoadStoryLogButton").visible = host.supports(StoryStageHost.FEATURE_LOAD_STORY_LOG)
	_node("DualWindowToggle").visible = host.supports(StoryStageHost.FEATURE_DUAL_WINDOW)
	_node("SaveSttRecordingsToggle").visible = host.supports(StoryStageHost.FEATURE_SAVE_RECORDINGS)
	var typed := host.supports(StoryStageHost.FEATURE_TYPED_INPUT)
	_node("ShowInputToggle").visible = typed
	var show_field: bool = typed and bool(_node("ShowInputToggle").button_pressed)
	_node("InputContainer").visible = show_field
	_node("StageRecordButton").visible = typed
	_node("StageAutoSendVoice").visible = typed
	_node("StageAutoPlayerInput").visible = typed


func _toggle_settings() -> void:
	_node("SettingsPanel").visible = not _node("SettingsPanel").visible


func _on_skip_welcome(on: bool) -> void:
	if _stage.voice:
		_stage.voice.set_skip_welcome(on)
	if on:
		_stage.dismiss_welcome()
	elif _stage.host:
		_stage.host.reset_opening_spoken()


func _on_output_volume(value: float) -> void:
	if _stage and _stage.motion:
		_stage.motion.set_output_linear(value / 100.0)


func current_speaker() -> String:
	return str(_node("SpeakerName").text)


func current_line() -> String:
	return str(_node("DialogLine").text)


func _on_pause() -> void:
	if _stage.voice:
		_stage.voice.pause()


func _on_resume() -> void:
	if _stage.voice:
		_stage.voice.resume()


func _on_skip() -> void:
	_stage.skip_current_line()


func _on_services() -> void:
	if _stage.host.toggle_services(_stage):
		_node("SettingsPanel").visible = false


func _confirm_new_log() -> void:
	var dialog := ConfirmationDialog.new()
	_apply_theme(dialog)
	dialog.dialog_text = "Start a new story log?"
	dialog.confirmed.connect(func() -> void: _stage.host.start_new_story_log(_stage))
	add_child(dialog)
	dialog.popup_centered()


func _load_log() -> void:
	var dialog := FileDialog.new()
	_apply_theme(dialog)
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Story logs"])
	dialog.current_dir = _stage.host.get_story_log_dir()
	dialog.file_selected.connect(_on_log_picked)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _on_log_picked(path: String) -> void:
	_stage.host.clear_opening_for_loaded_log()
	_stage.host.load_story_log(path)
	_stage.replay_story_log()


func _send() -> void:
	var text := str((_node("InputField") as LineEdit).text).strip_edges()
	if text == "":
		return
	var speaker := str(_stage.host.get_local_speaker_name(1))
	if speaker == "":
		speaker = _stage.host.get_local_character_name()
	if _stage.host.commit_local_line(speaker, text):
		_node("InputField").text = ""


func _on_save_recordings(on: bool) -> void:
	if _stage.host.set_save_recordings(_stage, on):
		_node("SaveSttRecordingsToggle").set_pressed_no_signal(_stage.host.get_save_recordings())
	if _stage.voice:
		_stage.voice.set_save_recordings(on)


## The microphone bus has to exist before the first press. Building it on the
## click itself starts the capture in the same frame the bus is created, and
## that frame records nothing.
func _ensure_recorder() -> Node:
	if _recorder != null and is_instance_valid(_recorder):
		return _recorder
	if _stage == null or _stage.voice == null or not _stage.voice.has_method("create_recorder"):
		return null
	_recorder = _stage.voice.create_recorder()
	if _recorder == null:
		return null
	_recorder.name = "StageMicrophone"
	add_child(_recorder)
	return _recorder


func _on_record_toggled(on: bool) -> void:
	var field := _node("InputField") as LineEdit
	var button := _node("StageRecordButton") as BaseButton
	if on:
		var recorder := _ensure_recorder()
		if recorder == null or not recorder.has_method("start_recording"):
			button.set_pressed_no_signal(false)
			field.placeholder_text = "Recording is not available."
			return
		recorder.start_recording()
		_recording = true
		_set_record_face(true)
		return
	if not _recording:
		_set_record_face(false)
		return
	_recording = false
	button.disabled = true
	button.text = "Transcribing..."
	var path := ""
	if _recorder and _recorder.has_method("stop_recording"):
		path = str(await _recorder.stop_recording())
	button.disabled = false
	_set_record_face(false)
	if path.strip_edges() == "":
		field.placeholder_text = "Recording failed. Try again."
		return
	var started := false
	if _stage.voice and _stage.voice.has_method("transcribe"):
		started = bool(_stage.voice.transcribe(path))
	if not started:
		field.placeholder_text = "Voice service is not ready to transcribe."


func _on_transcript(text: String, error: String) -> void:
	var field := _node("InputField") as LineEdit
	var button := _node("StageRecordButton") as BaseButton
	if button:
		button.disabled = false
		button.set_pressed_no_signal(false)
	_recording = false
	_set_record_face(false)
	var heard := text.strip_edges()
	if error != "" or heard == "":
		field.placeholder_text = "Transcription failed. Try again." if error != "" else "Couldn't hear anything. Try again."
		return
	field.placeholder_text = ""
	field.text = heard
	field.grab_focus()
	field.caret_column = heard.length()
	if _node("StageAutoSendVoice").button_pressed:
		_send()


func _bind_auto_input() -> void:
	var auto: Object = _stage.host.get_player_auto_input()
	if auto == null:
		return
	if auto.has_signal("auto_input_changed") and not auto.auto_input_changed.is_connected(_on_auto_changed):
		auto.auto_input_changed.connect(_on_auto_changed)
	if auto.has_method("is_enabled"):
		var enabled: bool = auto.is_enabled()
		_node("StageAutoPlayerInput").set_pressed_no_signal(enabled)
		_node("InputField").editable = not enabled


func _on_auto_toggled(on: bool) -> void:
	var auto: Object = _stage.host.get_player_auto_input()
	if auto and auto.has_method("set_enabled"):
		auto.set_enabled(on)
	_node("InputField").editable = not on


func _on_auto_changed(on: bool) -> void:
	_node("StageAutoPlayerInput").set_pressed_no_signal(on)
	_node("InputField").editable = not on


func _on_blip() -> void:
	var label := _node("DialogLine") as RichTextLabel
	var parsed := ""
	if label.has_method("get_parsed_text"):
		parsed = label.get_parsed_text()
	else:
		parsed = label.text
	var shown := label.visible_characters
	if shown < 0 or shown >= parsed.length():
		_node("TextBlipTimer").stop()
		return
	var ch := parsed.substr(shown, 1)
	label.visible_characters = shown + 1
	if _blip_ok(ch):
		_node("TextBlipSound").play()
	if ch == "." or ch == "!" or ch == "?":
		_node("TextBlipTimer").stop()
		_node("SentencePauseTimer").start()


func _on_sentence_done() -> void:
	if not _voiced:
		_node("TextBlipTimer").start()


func _fill_choices(choices: Array) -> void:
	for child in _node("ChoiceList").get_children():
		child.queue_free()
	_node("ChoiceList").visible = not choices.is_empty()
	for choice in choices:
		var button := Button.new()
		button.text = str(choice)
		button.pressed.connect(func() -> void:
			_node("InputField").text = button.text
			_send()
		)
		_node("ChoiceList").add_child(button)


func _refresh_health() -> void:
	if _stage.voice == null:
		return
	_node("AvatarHealthLabel").text = "\n".join(_stage.voice.health_lines())


func _apply_theme(dialog: AcceptDialog) -> void:
	var theme: Theme = _stage.host.get_dialog_theme()
	if theme:
		dialog.theme = theme


func _style() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.05, 0.07, 0.88)
	panel.corner_radius_top_left = 10
	panel.corner_radius_top_right = 10
	panel.corner_radius_bottom_left = 10
	panel.corner_radius_bottom_right = 10
	panel.content_margin_left = 16
	panel.content_margin_right = 16
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	_node("DialogBox").add_theme_stylebox_override("panel", panel)
	var speaker := panel.duplicate() as StyleBoxFlat
	speaker.bg_color = Color(0.16, 0.12, 0.1, 0.92)
	_node("SpeakerBox").add_theme_stylebox_override("panel", speaker)
	_node("DialogLine").add_theme_color_override("default_color", Color(0.95, 0.92, 0.86))
	_node("SpeakerName").add_theme_color_override("font_color", Color(0.98, 0.9, 0.75))
	_paint_toggle(_node("StageAutoSendVoice"))
	_paint_toggle(_node("StageAutoPlayerInput"))
	_paint_toggle(_node("StageRecordButton"))


func _paint_toggle(button: BaseButton) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override("normal", _toggle_plate(Color(0.16, 0.12, 0.1, 0.96)))
	button.add_theme_stylebox_override("hover", _toggle_plate(Color(0.28, 0.2, 0.14, 1)))
	button.add_theme_stylebox_override("pressed", _toggle_plate(Color(0.55, 0.36, 0.18, 1)))
	button.add_theme_stylebox_override("hover_pressed", _toggle_plate(Color(0.62, 0.42, 0.22, 1)))
	button.add_theme_stylebox_override("disabled", _toggle_plate(Color(0.16, 0.12, 0.1, 0.55)))
	button.add_theme_stylebox_override("focus", _toggle_plate(Color(0.28, 0.2, 0.14, 1)))
	button.add_theme_color_override("font_color", Color(0.98, 0.9, 0.75))
	button.add_theme_color_override("font_hover_color", Color(1, 0.96, 0.88))
	button.add_theme_color_override("font_pressed_color", Color(1, 0.96, 0.88))


func _toggle_plate(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_right = 8
	box.corner_radius_bottom_left = 8
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _set_record_face(stopping: bool) -> void:
	var button := _node("StageRecordButton") as BaseButton
	if button == null:
		return
	button.text = "Stop" if stopping else "Record"
	button.modulate = Color(1, 0.62, 0.55) if stopping else Color.WHITE
	var key := "stop_icon" if stopping else "record_icon"
	if button.has_meta(key):
		button.icon = button.get_meta(key)


func _blip_ok(ch: String) -> bool:
	if ch.strip_edges() == "":
		return false
	return ".,!?;:'\"-()[]…".find(ch) == -1


func _blip() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	var count := 700
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var env := 1.0 - float(i) / float(count)
		var sample := int(9000.0 * env * sin(TAU * 740.0 * float(i) / 22050.0))
		data.encode_s16(i * 2, sample)
	stream.data = data
	return stream
