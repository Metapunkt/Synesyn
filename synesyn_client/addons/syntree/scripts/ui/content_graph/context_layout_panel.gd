## Purpose: Present named visual layouts stored separately from graph semantics.
extends PanelContainer

signal save_requested(label_text: String, layout_id: String)
signal load_requested(layout_id: String)
signal delete_requested(layout_id: String)

@onready var layout_selector: OptionButton = %LayoutSelector
@onready var label_edit: LineEdit = %LayoutNameEdit
@onready var status_label: Label = %LayoutStatus


func _ready() -> void:
	%SaveLayoutButton.pressed.connect(_on_save_pressed)
	%LoadLayoutButton.pressed.connect(_on_load_pressed)
	%DeleteLayoutButton.pressed.connect(_on_delete_pressed)


func set_layouts(layouts: Array[Dictionary]) -> void:
	layout_selector.clear()
	layout_selector.add_item("New layout…")
	layout_selector.set_item_metadata(0, "")
	for layout_data in layouts:
		layout_selector.add_item(str(layout_data.get("label", "Unnamed")))
		layout_selector.set_item_metadata(
			layout_selector.item_count - 1,
			str(layout_data.get("id", ""))
		)


func show_status(status_text: String) -> void:
	status_label.text = status_text


func _selected_layout_id() -> String:
	if layout_selector.selected < 0:
		return ""
	return str(layout_selector.get_item_metadata(layout_selector.selected))


func _on_save_pressed() -> void:
	save_requested.emit(label_edit.text, _selected_layout_id())


func _on_load_pressed() -> void:
	var layout_id: String = _selected_layout_id()
	if not layout_id.is_empty():
		load_requested.emit(layout_id)


func _on_delete_pressed() -> void:
	var layout_id: String = _selected_layout_id()
	if not layout_id.is_empty():
		delete_requested.emit(layout_id)
