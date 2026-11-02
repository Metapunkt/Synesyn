@tool
class_name SynesynSemanticStatusBadge
extends PanelContainer

const VariationBuilderScript = preload(
	"res://addons/synesyn_visual_profiles/runtime/theme_variation_builder.gd"
)

@export_enum("proposed", "reviewed", "committed", "rejected", "deferred", "read_only", "degraded")
var semantic_role: String = "proposed":
	set(role_id):
		semantic_role = role_id
		_apply_semantic_role()

@export var display_text: String = "":
	set(label_text):
		display_text = label_text
		_apply_label()


func _ready() -> void:
	_apply_semantic_role()
	_apply_label()


func _apply_semantic_role() -> void:
	theme_type_variation = VariationBuilderScript.badge_variation(semantic_role)
	set_meta("synesyn_semantic_role", semantic_role)
	if is_node_ready():
		var label_node: Label = get_node_or_null("%Label")
		if label_node != null:
			label_node.theme_type_variation = (
				VariationBuilderScript.badge_label_variation(semantic_role)
			)


func _apply_label() -> void:
	if not is_node_ready():
		return
	var label_node: Label = get_node_or_null("%Label")
	if label_node == null:
		return
	label_node.text = (
		display_text
		if not display_text.is_empty()
		else semantic_role.replace("_", " ").capitalize()
	)
