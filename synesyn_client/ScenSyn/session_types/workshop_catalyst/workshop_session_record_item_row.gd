extends HBoxContainer
class_name WorkshopSessionRecordItemRow

signal save_requested(item_id: String, edited_text: String)
signal remove_requested(item_id: String)

var _item_id: String = ""
@onready var _editor_node: LineEdit = %ItemEditor
@onready var _save_button_node: Button = %SaveItemButton
@onready var _remove_button_node: Button = %RemoveItemButton


func _ready() -> void:
	_save_button_node.pressed.connect(_on_save_pressed)
	_remove_button_node.pressed.connect(_on_remove_pressed)


func configure(item: Dictionary) -> void:
	_item_id = String(item.get("id", ""))
	_editor_node.text = String(item.get("text", ""))


func _on_save_pressed() -> void:
	save_requested.emit(_item_id, _editor_node.text)


func _on_remove_pressed() -> void:
	remove_requested.emit(_item_id)
