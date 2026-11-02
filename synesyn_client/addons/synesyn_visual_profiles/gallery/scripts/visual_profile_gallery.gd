extends Control

@onready var profile_label_node: Label = %ProfileLabel
@onready var background_node: ColorRect = %Background
@onready var surface_panel_node: ColorRect = %SurfacePanel

var _preview_profile_mode: String = "dark"
var _theme_manager_node: Node


func _ready() -> void:
	_theme_manager_node = get_node_or_null("/root/ThemeManager")
	%LightButton.pressed.connect(_on_light_pressed)
	%DarkButton.pressed.connect(_on_dark_pressed)
	%ProjectorButton.pressed.connect(_on_projector_pressed)
	%HighContrastButton.pressed.connect(_on_high_contrast_pressed)
	var mode_callback: Callable = Callable(self, "_on_global_mode_changed")
	if (
		_theme_manager_node != null
		and _theme_manager_node.has_signal("mode_changed")
		and not _theme_manager_node.is_connected("mode_changed", mode_callback)
	):
		_theme_manager_node.connect("mode_changed", mode_callback)
	_preview_profile_mode = (
		"dark"
		if _theme_manager_node == null or bool(_theme_manager_node.call("is_dark"))
		else "light"
	)
	_apply_preview()


func _on_light_pressed() -> void:
	_preview_profile_mode = "light"
	if _theme_manager_node != null:
		_theme_manager_node.call("set_mode", "light")
	_apply_preview()


func _on_dark_pressed() -> void:
	_preview_profile_mode = "dark"
	if _theme_manager_node != null:
		_theme_manager_node.call("set_mode", "dark")
	_apply_preview()


func _on_projector_pressed() -> void:
	_preview_profile_mode = "projector"
	_apply_preview()


func _on_high_contrast_pressed() -> void:
	_preview_profile_mode = "high_contrast"
	_apply_preview()


func _on_global_mode_changed(profile_mode: String) -> void:
	if _preview_profile_mode in ["light", "dark"]:
		_preview_profile_mode = profile_mode
		_apply_preview()


func _apply_preview() -> void:
	if _theme_manager_node == null:
		profile_label_node.text = "ThemeManager unavailable"
		return
	var profile_definition: SynesynVisualProfileDefinition = (
		_theme_manager_node.call("get_visual_profile")
	)
	if profile_definition == null:
		profile_label_node.text = "Visual profile unavailable"
		return
	profile_label_node.text = "%s · %s" % [
		profile_definition.profile_id,
		_preview_profile_mode.replace("_", " ").capitalize(),
	]
	var visual_profile_bridge: Variant = _theme_manager_node.get("visual_profile_bridge")
	background_node.color = visual_profile_bridge.get_semantic_color(
		"base",
		_preview_profile_mode
	)
	surface_panel_node.color = visual_profile_bridge.get_semantic_color(
		"surface",
		_preview_profile_mode
	)
	for swatch_node in get_tree().get_nodes_in_group("semantic_swatch"):
		if swatch_node is ColorRect and swatch_node.has_meta("semantic_role"):
			var semantic_role: String = String(swatch_node.get_meta("semantic_role"))
			swatch_node.color = visual_profile_bridge.get_semantic_color(
				semantic_role,
				_preview_profile_mode
			)
