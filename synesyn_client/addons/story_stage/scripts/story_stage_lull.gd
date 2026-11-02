class_name StoryStageLull
extends Node

## Five-tier silence clock. Runs only when the scenario declares it.

var active := false
var elapsed := 0.0
var cycle_count := 0
var tiers_fired: Array[int] = []
var lines_spoken: Array[String] = []
var loading_trace: Array = []
var loading_visible := false

var _stage: Node
var _fired: Array[bool] = [false, false, false, false, false]
var _murmur_i := 0
var _welcome := ""
var _speech_timer: Timer


func setup(stage: Node) -> void:
	_stage = stage
	_welcome = str(stage.host.get_opening_welcome_text())
	_speech_timer = Timer.new()
	_speech_timer.one_shot = true
	_speech_timer.timeout.connect(_end_speech)
	add_child(_speech_timer)
	active = stage.scenario_section_enabled("lull_protocol", true)


func note_activity() -> void:
	elapsed = 0.0
	_fired = [false, false, false, false, false]
	_end_speech()


func advance(seconds: float) -> void:
	if not _timing_allowed():
		return
	elapsed += maxf(seconds, 0.0)
	_dispatch()


func _process(delta: float) -> void:
	if not _timing_allowed():
		return
	elapsed += delta
	_dispatch()


func _timing_allowed() -> bool:
	if not active or _stage == null:
		return false
	if _stage.is_lull_speaking or _stage.is_displaying_message:
		return false
	if _stage.voice and _stage.voice.is_present() and _stage.voice.is_busy():
		return false
	return true


func _thresholds() -> Array:
	var section: Dictionary = _stage.scenario_section("lull_protocol")
	return [
		_num(section, "tier0_slideshow_s", 10.0),
		_num(section, "tier1_arcs_s", 45.0),
		_num(section, "tier2_murmur_s", 90.0),
		_num(section, "tier3_welcome_s", 180.0),
		_num(section, "tier4_cycle_s", 240.0),
	]


func _dispatch() -> void:
	var guard := 0
	while guard < 8:
		guard += 1
		var thresholds := _thresholds()
		var fired_any := false
		for i in 5:
			if _fired[i]:
				continue
			if elapsed + 0.00001 < float(thresholds[i]):
				break
			_fire(i)
			fired_any = true
			if i == 4:
				cycle_count += 1
				elapsed = float(thresholds[0])
				_fired[0] = true
				_fired[1] = false
				_fired[2] = false
				_fired[3] = false
				_fired[4] = false
				return
		if not fired_any:
			return


func _fire(tier: int) -> void:
	_fired[tier] = true
	tiers_fired.append(tier)
	var ambient := _stage.get_node_or_null("Ambient")
	if ambient and ambient.has_method("send_lull"):
		ambient.send_lull(tier, elapsed)
	match tier:
		0:
			var slides := _stage.get_node_or_null("BackgroundController")
			if slides and slides.has_method("start_lull_cycle"):
				slides.start_lull_cycle()
		1:
			loading_visible = true
			loading_trace.append(true)
			_stage.set_loading_indicator(true)
		2:
			loading_visible = false
			loading_trace.append(false)
			_stage.set_loading_indicator(false)
			_speak_murmur()
		3:
			if _welcome != "":
				_speak(_welcome)
		4:
			pass


func _speak_murmur() -> void:
	var raw: Variant = _stage.host.get_scenario().get("lull_murmurs", [])
	if not (raw is Array) or (raw as Array).is_empty():
		return
	var murmurs: Array = raw
	var line := str(murmurs[_murmur_i % murmurs.size()])
	_murmur_i += 1
	if line == "":
		return
	_speak(line)


func _speak(line: String) -> void:
	lines_spoken.append(line)
	_stage.is_lull_speaking = true
	_stage.show_lull_line(line)
	if _stage.voice and _stage.voice.is_present():
		_stage.voice.speak(_stage.host.resolve_voice_name("Narrator"), line, "neutral")
	var animation := 0.0
	if _stage.has_method("_calculate_text_animation_duration"):
		animation = float(_stage._calculate_text_animation_duration(line))
	_speech_timer.start(maxf(animation + 3.0, 1.5))


func _end_speech() -> void:
	if _stage:
		_stage.is_lull_speaking = false


func _num(section: Dictionary, key: String, fallback: float) -> float:
	return float(str(section.get(key, fallback)))
