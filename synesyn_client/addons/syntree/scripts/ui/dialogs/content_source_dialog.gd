## Purpose: ui/dialogs/content_source_dialog.gd
@tool
extends PopupPanel

signal source_confirmed(source_data: Dictionary)
signal sources_confirmed(sources_data: Array)
signal source_cancelled
signal operation_failed(operation: String, error: String)

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

const SUPPORTED_EXTENSIONS = ["txt", "md", "json", "gd", "cfg", "ini", "yaml", "yml", "toml", "csv", "rst", "py", "cs", "tscn"]
const DEFAULT_CONTENT_SOURCES_DIR = "res://addons/syntree/content_source_lists"

@onready var _file_name_input: LineEdit = %FileNameInput
@onready var _path_input: LineEdit = %PathInput
@onready var _save_all_from_folder_checkbox: BaseButton = %SaveAllFromFolderCheckbox
@onready var _set_path_button: Button = %SetPathButton
@onready var _metaprompt_checkbox: CheckBox = get_node_or_null("%MetapromptCheckBox")
@onready var _active_checkbox: CheckBox = get_node_or_null("%ActiveSourceCheckBox")
@onready var _confirm_button: Button = %ConfirmSaveButton
@onready var _cancel_button: Button = %CancelSaveButton

# Optional edit-mode state. When set, confirm emits extra keys but remains backward compatible.
var _dialog_mode: String = "create" # "create" | "edit"
var _edit_source_id: String = ""

func _ready() -> void:
	# Connect path and folder signals
	if _set_path_button and not _set_path_button.pressed.is_connected(_on_set_path_pressed):
		_set_path_button.pressed.connect(_on_set_path_pressed)
	if _save_all_from_folder_checkbox and not _save_all_from_folder_checkbox.toggled.is_connected(_on_batch_folder_toggled):
		_save_all_from_folder_checkbox.toggled.connect(_on_batch_folder_toggled)
	
	# Connect save/cancel buttons
	if _confirm_button and not _confirm_button.pressed.is_connected(_on_confirm_pressed):
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _cancel_button and not _cancel_button.pressed.is_connected(_on_cancel_pressed):
		_cancel_button.pressed.connect(_on_cancel_pressed)
	
	_setup_dialog()

func show_dialog() -> void:
	_dialog_mode = "create"
	_edit_source_id = ""
	_setup_dialog()
	popup_centered()

func show_edit_dialog(source_id: String, name: String, path: String) -> void:
	# Reuse the same UI as create, but prefilled and with batch features disabled.
	_dialog_mode = "edit"
	_edit_source_id = String(source_id).strip_edges()
	_setup_dialog()
	if _file_name_input:
		_file_name_input.text = String(name).strip_edges()
		_file_name_input.editable = true
	if _path_input:
		_path_input.text = String(path).strip_edges()
	if _metaprompt_checkbox:
		_metaprompt_checkbox.button_pressed = false
	if _active_checkbox:
		_active_checkbox.button_pressed = false
	# Editing a single source only; disable batch toggle.
	if _save_all_from_folder_checkbox:
		_save_all_from_folder_checkbox.set_block_signals(true)
		_save_all_from_folder_checkbox.button_pressed = false
		_save_all_from_folder_checkbox.disabled = true
		_save_all_from_folder_checkbox.set_block_signals(false)
	popup_centered()

func show_edit_dialog_full(source_id: String, name: String, path: String, is_active: bool, is_metaprompt: bool) -> void:
	show_edit_dialog(source_id, name, path)
	if _metaprompt_checkbox:
		_metaprompt_checkbox.button_pressed = is_metaprompt
	if _active_checkbox:
		_active_checkbox.button_pressed = is_active

func _setup_dialog() -> void:
	if _file_name_input:
		_file_name_input.text = ""
		_file_name_input.editable = true
	if _path_input:
		_path_input.text = ""
	if _save_all_from_folder_checkbox:
		_save_all_from_folder_checkbox.disabled = false
		_save_all_from_folder_checkbox.button_pressed = false
	if _metaprompt_checkbox:
		_metaprompt_checkbox.button_pressed = false
	if _active_checkbox:
		_active_checkbox.button_pressed = false

func _on_set_path_pressed() -> void:
	var dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	
	if _save_all_from_folder_checkbox and _save_all_from_folder_checkbox.button_pressed:
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dialog.title = "Select Folder for Content Sources"
	else:
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.title = "Select Content Source File"
		dialog.filters = _get_file_filters()
	
	# Connect appropriate signal based on mode
	if _save_all_from_folder_checkbox and _save_all_from_folder_checkbox.button_pressed:
		dialog.dir_selected.connect(_on_folder_selected)
	else:
		dialog.file_selected.connect(_on_file_selected)
	
	add_child(dialog)
	dialog.popup_centered(Vector2(800, 600))

func _get_file_filters() -> PackedStringArray:
	var filters = []
	for ext in SUPPORTED_EXTENSIONS:
		filters.append("*." + ext + " ; " + ext.to_upper() + " Files")
	return PackedStringArray(filters)

func _on_file_selected(path: String) -> void:
	_path_input.text = path
	# Auto-fill name from file name if name is empty
	if _file_name_input and _file_name_input.text.is_empty():
		_file_name_input.text = path.get_file().get_basename()

func _on_folder_selected(path: String) -> void:
	_path_input.text = path
	if _file_name_input:
		_file_name_input.text = path.get_file()  # Use folder name as base name
		_file_name_input.editable = false  # Disable name editing for batch processing

func _on_batch_folder_toggled(button_pressed: bool) -> void:
	if _file_name_input:
		_file_name_input.editable = !button_pressed
		_file_name_input.placeholder_text = "Folder name will be used as prefix" if button_pressed else "Enter name for content source"
	
	# Clear path when switching modes
	if _path_input:
		_path_input.text = ""

# --- SIMPLIFIED VALIDATION: Just check if fields are filled --- 
func validate_and_get_source() -> Dictionary:
	var file_name = _file_name_input.text.strip_edges() if _file_name_input else ""
	var path = _path_input.text.strip_edges() if _path_input else ""
	var is_batch = _save_all_from_folder_checkbox and _save_all_from_folder_checkbox.button_pressed
	var is_metaprompt = _metaprompt_checkbox.button_pressed if _metaprompt_checkbox else false
	var is_active = _active_checkbox.button_pressed if _active_checkbox else false
	
	# Basic validation
	if file_name.is_empty():
		return {"success": false, "error": "Please enter a name for the source."}
	if path.is_empty():
		return {"success": false, "error": "Please provide a path or URL."}
		
	# Return raw data - Let the caller handle processing
	return {
		"success": true,
		"data": {
			"name": file_name,
			"path": path,
			"is_batch": is_batch, # Pass batch flag to caller
			"mode": _dialog_mode,
			"source_id": _edit_source_id,
			"is_metaprompt": is_metaprompt,
			"is_active": is_active,
		}
	}
# --- END SIMPLIFIED VALIDATION --- 

func _on_confirm_pressed() -> void:
	# Call the simplified validation
	var result = validate_and_get_source()
	
	if result.has("success") and result["success"]:
		var source_data = result["data"]
		# Emit based on batch flag (handle potential batch logic elsewhere if needed)
		if source_data.get("is_batch", false):
			# If batch is still needed, the caller needs to implement folder scanning.
			# For now, maybe emit an error or handle as single source?
			push_warning("ContentSourceDialog: Batch folder processing requested but not currently handled by caller.")
			# Temporarily handle as single source confirm for the folder path itself?
			source_confirmed.emit({"name": source_data.name, "path": source_data.path})
		else:
			source_confirmed.emit({"name": source_data.name, "path": source_data.path}) # Emit raw name/path
		hide()
	else:
		var error = result.get("error", "Unknown validation error")
		operation_failed.emit("validate_source", error) # Use the internal signal
		# Optionally show an error popup here within the dialog too
		var error_dialog = AcceptDialog.new()
		error_dialog.title = "Validation Error"
		error_dialog.dialog_text = error
		add_child(error_dialog)
		error_dialog.popup_centered()
		error_dialog.confirmed.connect(error_dialog.queue_free)

func _on_cancel_pressed() -> void:
	source_cancelled.emit()
	hide()

func _on_source_selected(display_name: String):
	var source_id = display_name.to_lower().replace(" ", "_")
	var bus := SynTreeAutoloads.content_bus()
	if is_instance_valid(bus):
		bus.request_hierarchy(source_id)
