## Purpose: ui/content_source_editor/content_source_editor.gd
@tool
extends Node

# Signals
signal source_saved(source: Dictionary)
signal source_cancelled(source: Dictionary)
signal operation_failed(operation: String, error: String)

# References
var content_service: Node

# State
var _current_source: Dictionary = {}
var _is_editing: bool = false
var _editor_dialog: AcceptDialog

func setup(service: Node) -> Dictionary:
	if not service:
		return {"success": false, "error": "Invalid service"}
	
	content_service = service
	return {"success": true, "error": ""}

func edit_source(source_data: Dictionary = {}) -> Dictionary:
	if _is_editing:
		return {"success": false, "error": "Already editing a source"}
		
	_current_source = source_data.duplicate() if not source_data.is_empty() else {
		"id": "",
		"name": "",
		"path": "",
		"type": "file"
	}
	
	_is_editing = true
	_show_editor_dialog()
	return {"success": true, "error": ""}

func _show_editor_dialog() -> void:
	# Create dialog if it doesn't exist
	if not _editor_dialog:
		_editor_dialog = AcceptDialog.new()
		_editor_dialog.title = "Edit Content Source"
		add_child(_editor_dialog)
		
		var container = VBoxContainer.new()
		_editor_dialog.add_child(container)
		
		# Name field
		var name_container = HBoxContainer.new()
		container.add_child(name_container)
		
		var name_label = Label.new()
		name_label.text = "Name:"
		name_container.add_child(name_label)
		
		var name_edit = LineEdit.new()
		name_edit.name = "name_edit"
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_container.add_child(name_edit)
		
		# Path field
		var path_container = HBoxContainer.new()
		container.add_child(path_container)
		
		var path_label = Label.new()
		path_label.text = "Path:"
		path_container.add_child(path_label)
		
		var path_edit = LineEdit.new()
		path_edit.name = "path_edit"
		path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		path_container.add_child(path_edit)
		
		# Type selector
		var type_container = HBoxContainer.new()
		container.add_child(type_container)
		
		var type_label = Label.new()
		type_label.text = "Type:"
		type_container.add_child(type_label)
		
		var type_option = OptionButton.new()
		type_option.name = "type_option"
		type_option.add_item("File")
		type_option.add_item("URL")
		type_container.add_child(type_option)
		
		# Connect signals
		_editor_dialog.confirmed.connect(_on_dialog_confirmed)
		_editor_dialog.canceled.connect(_on_dialog_cancelled)
	
	# Update fields with current source data
	var name_edit = _editor_dialog.get_node("name_edit")
	var path_edit = _editor_dialog.get_node("path_edit")
	var type_option = _editor_dialog.get_node("type_option")
	
	name_edit.text = _current_source.get("name", "")
	path_edit.text = _current_source.get("path", "")
	type_option.selected = 1 if _current_source.get("type", "file") == "url" else 0
	
	_editor_dialog.popup_centered()

func _on_dialog_confirmed() -> void:
	var name_edit = _editor_dialog.get_node("name_edit")
	var path_edit = _editor_dialog.get_node("path_edit")
	var type_option = _editor_dialog.get_node("type_option")
	
	var validation = _validate_input(name_edit.text, path_edit.text)
	if not validation.success:
		operation_failed.emit("validation", validation.error)
		return
		
	_current_source["name"] = name_edit.text
	_current_source["path"] = path_edit.text
	_current_source["type"] = "url" if type_option.selected == 1 else "file"
	
	if content_service:
		var result = content_service.save_content_source(_current_source)
		if result.success:
			_is_editing = false
			source_saved.emit(_current_source)
		else:
			operation_failed.emit("save", result.error)
	else:
		operation_failed.emit("save", "Content service not available")

func _on_dialog_cancelled() -> void:
	_is_editing = false
	source_cancelled.emit(_current_source)

func _validate_input(name: String, path: String) -> Dictionary:
	if name.strip_edges().is_empty():
		return {"success": false, "error": "Name cannot be empty"}
		
	if path.strip_edges().is_empty():
		return {"success": false, "error": "Path cannot be empty"}
		
	if path.begins_with("http"):
		var regex = RegEx.new()
		regex.compile("^https?://[\\w\\d\\-\\.]+\\.\\w+")
		if not regex.search(path):
			return {"success": false, "error": "Invalid URL format"}
			
	return {"success": true, "error": ""}
