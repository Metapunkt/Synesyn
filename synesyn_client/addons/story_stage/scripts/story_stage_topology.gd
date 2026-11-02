class_name StoryStageTopology
extends Node

## One shared stage, or one viewport per character when the scenario asks.

var slot_count := 0
var registries: Array[StoryStageCharacter] = []

var _stage: Node


func setup(stage: Node) -> void:
	_stage = stage
	if not stage.scenario_section_enabled("stages", true):
		return
	var section: Dictionary = stage.scenario_section("stages")
	var mode := str(section.get("mode", "shared")).to_lower()
	if mode == "" or mode == "shared":
		return
	var display := str(section.get("display", "viewport")).to_lower()
	var use_window := display == "window" and DisplayServer.get_name() != "headless"
	if display == "window" and not use_window:
		_log_once("topology: window stepped down to viewport")
	var cast := _cast()
	if cast.is_empty():
		return
	var row := HBoxContainer.new()
	row.name = "TopologyRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.get_node("CanvasLayer2").add_child(row)
	row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = 24.0
	row.offset_top = 24.0
	row.offset_right = -24.0
	for member in cast:
		_add_slot(str(member), row, use_window)
	slot_count = registries.size()


func _add_slot(cname: String, row: HBoxContainer, use_window: bool) -> void:
	var registry := StoryStageCharacter.new()
	registry.name = "Registry_%s" % StoryStageCharacter.dir_slug(cname)
	registry.setup(_stage)
	add_child(registry)
	registries.append(registry)
	var viewport := SubViewport.new()
	viewport.name = "SlotViewport"
	viewport.size = Vector2i(320, 420)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var portrait := StoryStageCharacterSprite.new()
	portrait.name = "SlotPortrait"
	viewport.add_child(portrait)
	if use_window:
		var window := Window.new()
		window.title = cname
		window.size = Vector2i(360, 480)
		window.add_child(viewport)
		add_child(window)
	else:
		var box := SubViewportContainer.new()
		box.custom_minimum_size = Vector2(180, 220)
		box.stretch = true
		box.add_child(viewport)
		row.add_child(box)
	portrait.bind_registry(registry)
	portrait.change_character_scensyn(cname, false, "neutral")


func _cast() -> Array:
	var scenario: Dictionary = _stage.host.get_scenario()
	if scenario.get("cast") is Array:
		return scenario["cast"]
	return []


func _log_once(reason: String) -> void:
	print("Story Stage %s" % reason)
