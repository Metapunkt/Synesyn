@tool
class_name SynesynSemanticPanel
extends PanelContainer

const VariationBuilderScript = preload(
	"res://addons/synesyn_visual_profiles/runtime/theme_variation_builder.gd"
)

@export_enum("surface", "raised", "dialog", "drawer", "status")
var semantic_role: String = "surface":
	set(role_id):
		semantic_role = role_id
		_apply_semantic_role()


func _ready() -> void:
	_apply_semantic_role()


func _apply_semantic_role() -> void:
	theme_type_variation = VariationBuilderScript.panel_variation(semantic_role)
	set_meta("synesyn_semantic_role", semantic_role)
