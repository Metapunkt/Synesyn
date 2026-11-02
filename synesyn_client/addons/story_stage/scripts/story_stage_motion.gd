class_name StoryStageMotion
extends Node

## One audio bus per speaker so mouth, bob, and ducking read the real voice.
## Speaker buses send to ScenSyn, and the hamburger slider sets that bus.

const OUTPUT_BUS := "ScenSyn"

var has_capture := false

var _stage: Node
var _buses: Dictionary = {}
var _used: Array[String] = []


func setup(stage: Node) -> void:
	_stage = stage
	has_capture = AudioServer != null
	if has_capture:
		_ensure_output_bus()


func set_output_linear(linear: float) -> void:
	if not has_capture:
		return
	var idx := _ensure_output_bus()
	if idx < 0:
		return
	var level := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, level <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(level, 0.0001)))


func output_linear() -> float:
	if not has_capture:
		return 1.0
	var idx := AudioServer.get_bus_index(OUTPUT_BUS)
	if idx < 0:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func bus_for(speaker: String) -> String:
	if _buses.has(speaker):
		return str(_buses[speaker])
	var slug := StoryStageCharacter.dir_slug(speaker)
	if slug == "":
		slug = "narrator"
	var bus_name := "SS%d_%s" % [_stage.get_instance_id(), slug]
	_buses[speaker] = bus_name
	if has_capture:
		_ensure_bus(bus_name)
	return bus_name


func intensity(speaker: String) -> float:
	if not has_capture or speaker == "":
		return 0.0
	var bus_name := bus_for(speaker)
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 0.0
	var effect := AudioServer.get_bus_effect_instance(idx, 0)
	if effect == null or not effect.has_method("get_magnitude_for_frequency_range"):
		return 0.0
	var mag: Vector2 = effect.get_magnitude_for_frequency_range(80.0, 3000.0)
	var level := (mag.x + mag.y) * 4.0
	return clampf(level, 0.0, 1.0)


func spectrum(speaker: String) -> PackedFloat32Array:
	var levels := PackedFloat32Array()
	var count := 16
	var effect: Object = null
	if has_capture and speaker != "":
		var idx := AudioServer.get_bus_index(bus_for(speaker))
		if idx >= 0:
			effect = AudioServer.get_bus_effect_instance(idx, 0)
	var low := 80.0
	var high := 4000.0
	for i in count:
		var start := lerpf(low, high, pow(float(i) / float(count), 1.4))
		var finish := lerpf(low, high, pow(float(i + 1) / float(count), 1.4))
		var level := 0.04
		if effect != null and effect.has_method("get_magnitude_for_frequency_range"):
			var mag: Vector2 = effect.get_magnitude_for_frequency_range(start, maxf(finish, start + 20.0))
			level = clampf((mag.x + mag.y) * 5.0, 0.04, 1.0)
		levels.append(level)
	return levels


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, OUTPUT_BUS)
	AudioServer.add_bus_effect(idx, AudioEffectSpectrumAnalyzer.new())
	_used.append(bus_name)


func _ensure_output_bus() -> int:
	var idx := AudioServer.get_bus_index(OUTPUT_BUS)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, OUTPUT_BUS)
	AudioServer.set_bus_send(idx, "Master")
	return idx


func _exit_tree() -> void:
	for bus_name in _used:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.remove_bus(idx)
	_used.clear()
