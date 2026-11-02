@tool
extends EditorPlugin

var _panel = null

func _create_required_directories() -> void:
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("res://addons/syntree/content_source_lists")
		dir.make_dir_recursive("res://addons/syntree/threads")

func _setup_window() -> void:
	if _panel:
		_panel.name = "SynTreePanel"

func _connect_signals() -> void:
	if _panel:
		_panel.operation_failed.connect(_on_operation_failed)

func _on_operation_failed(operation: String, error: String) -> void:
	push_error("SynTree operation failed: " + operation + " - " + error)

func _enter_tree() -> void:
	print("=== GodotSynTreePlugin _enter_tree START ===")
	
	print("Creating required directories...")
	_create_required_directories()
	
	print("Instantiating SynTreePanel...")
	_panel = preload("res://addons/syntree/scenes/syntree_panel.tscn").instantiate()
	
	print("Adding custom type...")
	add_custom_type("SynTreePlugin", "EditorPlugin", preload("res://addons/syntree/plugin.gd"), null)
	
	print("Setting up window...")
	_setup_window()
	
	print("Connecting signals...")
	_connect_signals()
	print("Signal connected successfully")
	
	print("Adding panel to bottom panel...")
	add_control_to_bottom_panel(_panel, "SynTree")
	
	print("=== GodotSynTreePlugin initialization complete ===")

func _exit_tree() -> void:
	if _panel:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
	
	remove_custom_type("SynTreePlugin") 