@tool
class_name SynesynSemanticNavigationButton
extends Button

const VariationBuilderScript = preload(
	"res://addons/synesyn_visual_profiles/runtime/theme_variation_builder.gd"
)

@export var is_selected: bool = false:
	set(is_selected_value):
		is_selected = is_selected_value
		_apply_selection()


func _ready() -> void:
	toggle_mode = true
	_apply_selection()


func set_selected(is_selected_value: bool) -> void:
	is_selected = is_selected_value


func _apply_selection() -> void:
	button_pressed = is_selected
	theme_type_variation = VariationBuilderScript.navigation_variation(is_selected)
	set_meta("synesyn_navigation_selected", is_selected)
