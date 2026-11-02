@tool
class_name SynesynOrientationIndicator
extends PanelContainer

@export var surface_label: String = "Overview":
	set(label_text):
		surface_label = label_text
		_update_label()

@export var slot_index: int = 1:
	set(slot_index_value):
		slot_index = maxi(1, slot_index_value)
		_update_label()

@export var slot_count: int = 6:
	set(slot_count_value):
		slot_count = maxi(1, slot_count_value)
		_update_label()


func _ready() -> void:
	_update_label()


func _update_label() -> void:
	if not is_node_ready():
		return
	var label_node: Label = get_node_or_null("%Label")
	if label_node != null:
		label_node.text = "%s · %d/%d" % [surface_label, slot_index, slot_count]
