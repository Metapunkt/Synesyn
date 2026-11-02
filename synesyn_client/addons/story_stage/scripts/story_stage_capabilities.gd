class_name StoryStageCapabilities
extends Node

var _stage: Node
var _logged: Dictionary = {}


func setup(stage: Node) -> void:
	_stage = stage
	if stage.imagery:
		stage.imagery.portrait_frames_ready.connect(_on_portrait)
		stage.imagery.backdrop_ready.connect(_on_backdrop)
		stage.imagery.line_clip_ready.connect(_on_clip)


func publish() -> void:
	var motion := _grant_motion()
	var portrait: bool = _stage.scenario_section_enabled("vis_portrait", true)
	var slideshow: bool = _stage.scenario_section_enabled("vis_story", false)
	var staging: bool = _stage.scenario_section_enabled("staging", true)
	var topology := "shared"
	if _stage.scenario_section_enabled("stages", true):
		var mode := str(_stage.scenario_section("stages").get("mode", "shared")).to_lower()
		topology = mode if mode != "" else "shared"
	_stage.motion_rung = motion
	if portrait and motion >= 2:
		_stage.imagery_name = "vis_portrait"
	elif slideshow:
		_stage.imagery_name = "vis_story"
	elif motion >= 3:
		_stage.imagery_name = "deform"
	else:
		_stage.imagery_name = "authored"
	var caps := {
		"topology": {"mode": topology},
		"staging": {"enabled": staging},
		"character_motion": {"rung": motion},
		"vis_story": {"enabled": slideshow},
		"vis_portrait": {"enabled": portrait, "rung": 2 if portrait else 0},
	}
	_stage.host.set_granted_capabilities(caps)
	if _stage.presenter:
		_stage.presenter.apply_grant(motion)
	if slideshow:
		_stage.background_controller.enable_slideshow()
	else:
		_stage.background_controller.disable_slideshow()
	if portrait:
		_request_portraits()


func _grant_motion() -> int:
	var requested := 1
	if _stage.scenario_section_enabled("character_motion", true):
		var raw := str(_stage.scenario_section("character_motion").get("rung", "3"))
		requested = int(float(raw))
	else:
		requested = 1
	if requested >= 4:
		_log("rung 4 gated: no warm real-time factor recorded")
		requested = 3
	var grant := requested
	while grant > 0 and not _available(grant):
		_log("motion rung %d stepped down" % grant)
		grant -= 1
	return grant


func _available(rung: int) -> bool:
	if rung <= 0:
		return true
	if rung == 1:
		return _stage.motion != null and _stage.motion.has_capture
	if rung == 2:
		return _stage.scenario_section_enabled("vis_portrait", true)
	if rung == 3:
		return true
	return false


func _request_portraits() -> void:
	var roots: Array[String] = _stage.host.get_sprite_roots()
	var seen: Dictionary = {}
	for member in _cast():
		var cname := str(member)
		if cname == "" or seen.has(cname):
			continue
		seen[cname] = true
		_stage.imagery.request_portrait_frames(cname, roots)


func _cast() -> Array:
	var scenario: Dictionary = _stage.host.get_scenario()
	if scenario.get("cast") is Array:
		return scenario["cast"]
	return []


func _on_portrait(character_id: String, frames: SpriteFrames) -> void:
	if frames == null or _stage.presenter == null or _stage.presenter.sprite == null:
		return
	_stage.presenter.sprite.use_generated(frames)
	_stage.imagery_name = "vis_portrait"
	if _stage.motion_rung < 2:
		_stage.motion_rung = 2
		_log("portrait frames arrived for %s" % character_id)


func _on_backdrop(_cue_id: String, texture: Texture2D) -> void:
	if texture and _stage.background_controller:
		_stage.background_controller.show_texture(texture, true)


func _on_clip(_line_index: int, path: String) -> void:
	if not str(path).to_lower().ends_with(".ogv"):
		return
	var player := VideoStreamPlayer.new()
	var stream := VideoStreamTheora.new()
	stream.file = path
	player.stream = stream
	player.expand = true
	player.finished.connect(player.queue_free)
	var host_node := _stage.get_node_or_null("CanvasLayer2/Control")
	if host_node:
		host_node.add_child(player)
		player.play()


func _log(reason: String) -> void:
	if _logged.has(reason):
		return
	_logged[reason] = true
	print("Story Stage %s" % reason)
