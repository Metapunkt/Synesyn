## SynAxes — Pattern discovery, clustering, and 3D visualisation for the Godot editor.
## Copyright © 2026 Ayodele Arigbabu | metapunkt.org | NTNU. All rights reserved.
## Licensed under [licence pending].
## Version: 0.0.3
## Enquiries: metapunkt@metapunkt.org
@tool
extends EditorPlugin

const PLUGIN_NAME = "Synaxes"
const PLUGIN_VERSION = "0.1.0"
const MAIN_SCENE_PATH = "res://addons/synaxes/scenes/synaxes_main.tscn"

# Import necessary classes
const DiscoveryEngine = preload("res://addons/synaxes/scripts/integration/discovery_engine.gd")
const SynTreeConnector = preload("res://addons/synaxes/scripts/integration/syntree_connector.gd")
const TestDataGenerator = preload("res://addons/synaxes/scripts/integration/test_data_generator.gd")
const PatternGraph = preload("res://addons/synaxes/scripts/visualization/pattern_graph.gd")
const UiBinderScript = preload("res://addons/synaxes/scripts/runtime/synaxes_ui_binder.gd")

var main_panel_instance = null
var _editor_interface = null
var _discovery_engine = null
var _syntree_connector = null
var _test_data_generator = null
var _using_test_data = false
var _ui_refs: Dictionary = {}

var _pattern_graph: PatternGraph = null

func _enter_tree() -> void:
	_editor_interface = get_editor_interface()
	
	# Load main scene
	main_panel_instance = load(MAIN_SCENE_PATH).instantiate()
	
	# Add the main panel to the editor UI
	_editor_interface.get_editor_main_screen().add_child(main_panel_instance)
	_make_visible(false)
	
	# Initialize components
	_init_components()

func _exit_tree() -> void:
	if main_panel_instance:
		main_panel_instance.queue_free()

func _export_begin(features: PackedStringArray) -> void:
	pass

func _export_end() -> void:
	pass

func _export_poll(features: PackedStringArray) -> bool:
	return true

func _get_export_options(feature: int) -> Array:
	return []

func _get_export_option_widget(feature: int) -> Control:
	return null

func _get_export_option_visibility(feature: int, option: String) -> bool:
	return true

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if main_panel_instance:
		main_panel_instance.visible = visible

func _get_plugin_name() -> String:
	return PLUGIN_NAME

func _get_plugin_version() -> String:
	return PLUGIN_VERSION

func _get_plugin_icon() -> Texture2D:
	return load("res://addons/synaxes/icon.svg")

func _enable_plugin() -> void:
	print("Synaxes plugin enabled")
	
	# Add the main panel to the editor
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, main_panel_instance)

func _disable_plugin() -> void:
	print("Synaxes plugin disabled")
	
	# Remove the main panel from the editor
	remove_control_from_docks(main_panel_instance)

func _apply_changes() -> void:
	pass

func _get_state() -> Dictionary:
	return {}

func _set_state(state: Dictionary) -> void:
	pass

func _get_unsaved_status(file_path: String) -> String:
	return ""

func _get_unsaved_changes(feature: int) -> Array:
	return []

func _get_breakpoints() -> PackedStringArray:
	return PackedStringArray()

func _set_breakpoint(file_path: String, line: int, enabled: bool) -> void:
	pass

func _get_window_layout(configuration: ConfigFile) -> void:
	pass

func _set_window_layout(configuration: ConfigFile) -> void:
	pass

func _dock_switch_requested(long_name: String) -> void:
	pass

func _get_drag_data_fw(position: Vector2, from: Control) -> Variant:
	return null

func _can_drop_data_fw(position: Vector2, data: Variant, from: Control) -> bool:
	return false

func _drop_data_fw(position: Vector2, data: Variant, from: Control) -> void:
	pass

func _get_filesystem_dock() -> FileSystemDock:
	return null

func _get_editor_paths() -> EditorPaths:
	return null

func _get_editor_settings() -> EditorSettings:
	return null

func _get_editor_theme() -> Theme:
	return null

func _get_editor_base_control() -> Control:
	return null

func _get_editor_main_screen() -> Control:
	return null

func _get_editor_viewport() -> Control:
	return null

func _get_editor_scale() -> float:
	return 1.0

# Initialize plugin components
func _init_components() -> void:
	if not main_panel_instance:
		return
	
	# Initialize components with proper error handling
	_init_discovery_engine()
	_init_syntree_connector()
	_init_test_data_generator()
	
	# Connect signals
	_connect_signals()
	
	# Setup UI components
	_setup_ui_components()

# Initialize discovery engine
func _init_discovery_engine() -> void:
	# Use a try-catch block to handle any initialization errors
	var success = false
	
	if ClassDB.class_exists("DiscoveryEngine"):
		_discovery_engine = DiscoveryEngine.new()
		success = true
	else:
		# Try loading the script directly
		var script = load("res://addons/synaxes/scripts/integration/discovery_engine.gd")
		if script:
			_discovery_engine = script.new()
			success = true
	
	if not success or not _discovery_engine:
		push_error("Synaxes Plugin: Failed to create discovery engine")
		# Create a minimal dummy implementation
		_discovery_engine = _create_dummy_discovery_engine()

# Initialize SynTree connector
func _init_syntree_connector() -> void:
	# Use a try-catch block to handle any initialization errors
	var success = false
	
	if ClassDB.class_exists("SynTreeConnector"):
		_syntree_connector = SynTreeConnector.new()
		success = true
	else:
		# Try loading the script directly
		var script = load("res://addons/synaxes/scripts/integration/syntree_connector.gd")
		if script:
			_syntree_connector = script.new()
			success = true
	
	if not success or not _syntree_connector:
		push_error("Synaxes Plugin: Failed to create SynTree connector")

# Initialize test data generator
func _init_test_data_generator() -> void:
	# Use a try-catch block to handle any initialization errors
	var success = false
	
	if ClassDB.class_exists("TestDataGenerator"):
		_test_data_generator = TestDataGenerator.new()
		success = true
	else:
		# Try loading the script directly
		var script = load("res://addons/synaxes/scripts/integration/test_data_generator.gd")
		if script:
			_test_data_generator = script.new()
			success = true
	
	if not success or not _test_data_generator:
		push_error("Synaxes Plugin: Failed to create test data generator")

# Create a minimal dummy discovery engine if the real one fails to initialize
func _create_dummy_discovery_engine():
	# Create an object with the minimal required API
	var dummy = RefCounted.new()
	
	# Add required methods
	dummy.set_data = func(data): 
		print("Dummy discovery engine: set_data called with ", data.size(), " items")
	
	dummy.discover_patterns = func(method_id: int, dim_method_id: int, num_clusters: int):
		print("Dummy discovery engine: discover_patterns called with method_id=", method_id, ", dim_method_id=", dim_method_id, ", num_clusters=", num_clusters)
		# Return some minimal patterns for testing with integer IDs
		return [
			{"id": 0, "type": "cluster", "confidence": 0.9, "position": Vector3(0, 0, 0), "relations": [], "items": ["item1", "item2"]},
			{"id": 1, "type": "bridge", "confidence": 0.8, "position": Vector3(2, 0, 0), "relations": [], "items": ["item3"]},
			{"id": 2, "type": "hub", "confidence": 0.7, "position": Vector3(-2, 0, 0), "relations": [], "items": ["item4", "item5"]},
			{"id": 3, "type": "cluster", "confidence": 0.6, "position": Vector3(0, 2, 0), "relations": [], "items": ["item6"]}
		]
	
	dummy.get_pattern = func(id):
		print("Dummy discovery engine: get_pattern called for ID ", id)
		match id:
			0: return {"id": 0, "type": "cluster", "confidence": 0.9, "position": Vector3(0, 0, 0), "relations": [], "items": ["item1", "item2"]}
			1: return {"id": 1, "type": "bridge", "confidence": 0.8, "position": Vector3(2, 0, 0), "relations": [], "items": ["item3"]}
			2: return {"id": 2, "type": "hub", "confidence": 0.7, "position": Vector3(-2, 0, 0), "relations": [], "items": ["item4", "item5"]}
			3: return {"id": 3, "type": "cluster", "confidence": 0.6, "position": Vector3(0, 2, 0), "relations": [], "items": ["item6"]}
			_: return null
		
	return dummy

# Connect signals between components
func _connect_signals() -> void:
	if not main_panel_instance:
		return

	_ensure_ui_refs()
	var pattern_viewer: Node = _ui_refs.get("PatternViewer") as Node

	# Note: Camera control buttons (Reset, Focus, Rotate, Zoom)
	# are now connected in _connect_camera_controls() called from _setup_ui_components()
	# Do not connect them here to avoid duplicate connections

	# Connect importer signals
	if _syntree_connector:
		_syntree_connector.connect("data_imported", Callable(self, "_on_data_imported"))
		_syntree_connector.connect("import_error", Callable(self, "_on_import_error"))

	if _test_data_generator:
		_test_data_generator.connect("data_generated", Callable(self, "_on_data_imported"))

	# Connect pattern viewer signals
	if pattern_viewer:
		pattern_viewer.connect("pattern_selected", Callable(self, "_on_pattern_selected"))
		pattern_viewer.connect("pattern_hovered", Callable(self, "_on_pattern_hovered"))
		pattern_viewer.connect("pattern_deselected", Callable(self, "_on_pattern_deselected"))

	# Note: No need to connect editor interface gui_input here
	# as it will be connected in _setup_ui_components()

func _ensure_ui_refs() -> void:
	if main_panel_instance == null:
		_ui_refs = {}
		return
	if not _ui_refs.is_empty():
		return
	_ui_refs = UiBinderScript.resolve(main_panel_instance)


func _bound_node(node_key: String) -> Node:
	## Resolve a common main-scene control from the shared binder cache.
	_ensure_ui_refs()
	return _ui_refs.get(node_key) as Node


func _bound_pattern_viewer() -> Node:
	return _bound_node("PatternViewer")

# Connect camera control buttons
func _connect_camera_controls() -> void:
	if not main_panel_instance:
		return

	_ensure_ui_refs()
	var reset_view: Button = _ui_refs.get("ResetViewButton") as Button
	var focus_selection: Button = _ui_refs.get("FocusSelectionButton") as Button
	var rotate_left: Button = _ui_refs.get("RotateLeft") as Button
	var rotate_right: Button = _ui_refs.get("RotateRight") as Button
	var rotate_up: Button = _ui_refs.get("RotateUp") as Button
	var rotate_down: Button = _ui_refs.get("RotateDown") as Button
	var zoom_in: Button = _ui_refs.get("ZoomIn") as Button
	var zoom_out: Button = _ui_refs.get("ZoomOut") as Button

	# Connect control buttons
	if reset_view:
		reset_view.connect("pressed", Callable(self, "_on_reset_view_pressed"))
	if focus_selection:
		focus_selection.connect("pressed", Callable(self, "_on_focus_selection_pressed"))
	if rotate_left:
		rotate_left.connect("pressed", Callable(self, "_on_rotate_left_pressed"))
	if rotate_right:
		rotate_right.connect("pressed", Callable(self, "_on_rotate_right_pressed"))
	if rotate_up:
		rotate_up.connect("pressed", Callable(self, "_on_rotate_up_pressed"))
	if rotate_down:
		rotate_down.connect("pressed", Callable(self, "_on_rotate_down_pressed"))
	if zoom_in:
		zoom_in.connect("pressed", Callable(self, "_on_zoom_in_pressed"))
	if zoom_out:
		zoom_out.connect("pressed", Callable(self, "_on_zoom_out_pressed"))

	print("Camera control buttons connected")

# Setup UI components
func _setup_ui_components() -> void:
	if not main_panel_instance:
		return

	_ensure_ui_refs()

	# Connect camera control buttons
	_connect_camera_controls()

	var clusters_slider: HSlider = _ui_refs.get("ClustersSlider") as HSlider
	var clusters_value: Label = _ui_refs.get("ClustersValue") as Label
	var import_button: Button = _ui_refs.get("ImportButton") as Button
	var refresh_button: Button = _ui_refs.get("RefreshButton") as Button
	var discover_button: Button = _ui_refs.get("DiscoverButton") as Button
	var clear_button: Button = _ui_refs.get("ClearButton") as Button

	# Connect UI controls
	if clusters_slider and clusters_value:
		clusters_slider.connect("value_changed", Callable(self, "_on_clusters_value_changed"))

	if import_button:
		import_button.connect("pressed", Callable(self, "_on_import_button_pressed"))

	if refresh_button:
		refresh_button.connect("pressed", Callable(self, "_on_refresh_button_pressed"))

	if discover_button:
		discover_button.connect("pressed", Callable(self, "_on_discover_button_pressed"))

	if clear_button:
		clear_button.connect("pressed", Callable(self, "_on_clear_button_pressed"))

	# Initialize values
	if clusters_value and clusters_slider:
		clusters_value.text = str(int(clusters_slider.value))

	# Connect to editor for key inputs
	_editor_interface.get_base_control().connect("gui_input", Callable(self, "_on_editor_gui_input"))

	print("UI components connected")

# Handle import button press
func _on_import_button_pressed() -> void:
	_ensure_ui_refs()
	var source_list: ItemList = _ui_refs.get("SourceList") as ItemList
	if not source_list or source_list.get_selected_items().size() == 0:
		_show_error("Please select a source type first")
		return

	var selected_idx = source_list.get_selected_items()[0]
	var selected_source = source_list.get_item_text(selected_idx)
	
	# Reset the test data flag
	_using_test_data = false
	
	# Try using SynTree connector first
	if _syntree_connector:
		# Import will trigger error signal if SynTree isn't found
		_syntree_connector.import_data()
		
		# Allow a short time for any error signal to be processed
		await get_tree().create_timer(0.2).timeout
		
		# If we're still not using test data, generate some now
		if not _using_test_data and _test_data_generator:
			# Generate test data based on selected source
			match selected_source:
				"Text Source":
					_test_data_generator.set_data_type("text")
				"Semantic Source":
					_test_data_generator.set_data_type("semantic")
				"Image Source":
					_test_data_generator.set_data_type("image")
				_:
					_test_data_generator.set_data_type("text")
			
			_using_test_data = true
			var data = _test_data_generator.generate_test_data()
			print("Synaxes: Generated " + str(data.size()) + " test data items directly")

# Handle editor UI input events
func _on_editor_gui_input(event: InputEvent) -> void:
	# Forward key events to the pattern viewer
	if event is InputEventKey and event.pressed:
		var pattern_viewer: Node = _bound_pattern_viewer()
		if pattern_viewer and main_panel_instance and main_panel_instance.visible:
			pattern_viewer._handle_keyboard(event)

# Handle pattern viewer button clicks
func _on_reset_view_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		pattern_viewer._reset_camera()

func _on_focus_selection_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		pattern_viewer._focus_on_selection()

# Camera control methods
func _on_rotate_left_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		# Simulate mouse movement for rotation
		var delta := Vector2(-50, 0)  # Move left by 50 pixels
		pattern_viewer._orbit_camera(delta)

func _on_rotate_right_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		# Simulate mouse movement for rotation
		var delta := Vector2(50, 0)  # Move right by 50 pixels
		pattern_viewer._orbit_camera(delta)

func _on_rotate_up_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		# Simulate mouse movement for rotation
		var delta := Vector2(0, -30)  # Move up by 30 pixels
		pattern_viewer._orbit_camera(delta)

func _on_rotate_down_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		# Simulate mouse movement for rotation
		var delta := Vector2(0, 30)  # Move down by 30 pixels
		pattern_viewer._orbit_camera(delta)

func _on_zoom_in_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		pattern_viewer._zoom_camera(-1)

func _on_zoom_out_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		pattern_viewer._zoom_camera(1)

# Signal handlers
func _on_data_imported(data: Array) -> void:
	# Handle imported data
	_discovery_engine.set_data(data)
	_show_notification("Imported " + str(data.size()) + " items")

func _on_import_error(error_message: String) -> void:
	# Check if error is related to SynTree missing - this is an expected case
	if error_message == "SynTree_NOT_FOUND" and _test_data_generator:
		var source_list: ItemList = _bound_node("SourceList") as ItemList
		if source_list and source_list.get_selected_items().size() > 0:
			var selected_idx = source_list.get_selected_items()[0]
			var selected_source = source_list.get_item_text(selected_idx)
			
			# Generate test data based on selected source
			match selected_source:
				"Text Source":
					_test_data_generator.set_data_type("text")
				"Semantic Source":
					_test_data_generator.set_data_type("semantic")
				"Image Source":
					_test_data_generator.set_data_type("image")
				_:
					_test_data_generator.set_data_type("text")
			
			_using_test_data = true
			var test_data = _test_data_generator.generate_test_data()
			_show_notification("Generated " + str(test_data.size()) + " test data items")
	else:
		# This is an actual error, not just missing SynTree
		push_error("Synaxes Error: " + error_message)
		_show_error(error_message)

# NOTE: _on_discover_pressed / _on_clear_pressed removed — they were unreachable
# duplicates of _on_discover_button_pressed / _on_clear_button_pressed (the
# actual button signal targets, see _connect_signals).

func _on_pattern_selected(pattern_id: int) -> void:
	# Update detail panel with pattern info
	var detail_content = main_panel_instance.find_child("DetailContent", true, false)
	if not detail_content:
		return
	
	var pattern = _discovery_engine.get_pattern(pattern_id)
	if not pattern:
		return
	
	# Update detail fields
	var name_value = detail_content.find_child("PatternName").find_child("Value")
	var type_value = detail_content.find_child("PatternType").find_child("Value")
	var confidence_value = detail_content.find_child("PatternConfidence").find_child("Value")
	var position_value = detail_content.find_child("PatternPosition").find_child("Value")
	
	if name_value:
		name_value.text = str(pattern.get("id", "Unknown"))
	
	if type_value:
		type_value.text = str(pattern.get("type", "Unknown"))
	
	if confidence_value:
		confidence_value.text = str(pattern.get("confidence", 0.0))
	
	if position_value:
		var pos = pattern.get("position", Vector3.ZERO)
		position_value.text = "(%0.2f, %0.2f, %0.2f)" % [pos.x, pos.y, pos.z]
	
	# Update related patterns
	var related_patterns = detail_content.find_child("RelatedPatterns")
	if related_patterns:
		related_patterns.clear()
		
		var relations = pattern.get("relations", [])
		for relation in relations:
			related_patterns.add_item(str(relation.get("id", "Unknown")))
	
	# Update pattern items
	var pattern_items = detail_content.find_child("PatternItems")
	if pattern_items:
		pattern_items.clear()
		
		var items = pattern.get("items", [])
		for item in items:
			pattern_items.add_item(str(item))

func _on_pattern_hovered(pattern_id: int) -> void:
	# Update status bar with pattern info
	var pattern = _discovery_engine.get_pattern(pattern_id)
	if pattern:
		var status_bar = _editor_interface.get_base_control().find_child("StatusBar", true, false)
		if status_bar:
			status_bar.push_text("Pattern: " + str(pattern.get("id", "Unknown")))

func _on_pattern_deselected() -> void:
	# Clear detail panel
	var detail_content = main_panel_instance.find_child("DetailContent", true, false)
	if not detail_content:
		return
	
	var name_value = detail_content.find_child("PatternName").find_child("Value")
	if name_value:
		name_value.text = "No Selection"
	
	var type_value = detail_content.find_child("PatternType").find_child("Value")
	if type_value:
		type_value.text = "-"
	
	var confidence_value = detail_content.find_child("PatternConfidence").find_child("Value")
	if confidence_value:
		confidence_value.text = "-"
	
	var position_value = detail_content.find_child("PatternPosition").find_child("Value")
	if position_value:
		position_value.text = "-"
	
	var related_patterns = detail_content.find_child("RelatedPatterns")
	if related_patterns:
		related_patterns.clear()
	
	var pattern_items = detail_content.find_child("PatternItems")
	if pattern_items:
		pattern_items.clear()

func _on_clusters_value_changed(value: float) -> void:
	_ensure_ui_refs()
	var clusters_value: Label = _ui_refs.get("ClustersValue") as Label
	if clusters_value:
		clusters_value.text = str(int(value))

# Handle refresh button press
func _on_refresh_button_pressed() -> void:
	# Update source list or refresh available data
	if _syntree_connector:
		_syntree_connector.refresh_sources()
		_show_notification("Sources refreshed")
	else:
		_show_notification("Using test data")
		
	# If we're using test data, regenerate it
	if _using_test_data and _test_data_generator:
		var data = _test_data_generator.regenerate_test_data()
		_discovery_engine.set_data(data)
		_show_notification("Regenerated " + str(data.size()) + " test data items")

# Handle discover button press
func _on_discover_button_pressed() -> void:
	if not _discovery_engine:
		_show_error("Discovery engine not available")
		return

	_ensure_ui_refs()
	var discovery_method: OptionButton = _ui_refs.get("DiscoveryMethod") as OptionButton
	var dim_reduction_method: OptionButton = _ui_refs.get("DimReductionMethod") as OptionButton
	var clusters_slider: HSlider = _ui_refs.get("ClustersSlider") as HSlider

	# Use method ID (integer) instead of string
	var method_id = 0 # Default to clustering (0)
	var dim_method_id = 0 # Default to PCA (0)
	var num_clusters = 5

	if discovery_method:
		method_id = discovery_method.selected

	if dim_reduction_method:
		dim_method_id = dim_reduction_method.selected

	if clusters_slider:
		num_clusters = int(clusters_slider.value)

	# Perform pattern discovery using integer method IDs
	var patterns = _discovery_engine.discover_patterns(method_id, dim_method_id, num_clusters)

	# Get pattern viewer and display patterns
	var pattern_viewer: Node = _ui_refs.get("PatternViewer") as Node
	if pattern_viewer:
		print("Synaxes: Displaying ", patterns.size(), " patterns in viewer")
		
		# First, get a reference to the pattern graph
		var pattern_graph = pattern_viewer.pattern_graph
		if not pattern_graph:
			printerr("Synaxes Plugin: PatternGraph not found in PatternViewer")
			_show_notification("Error: Pattern graph not found")
			return
		
		# Clear existing patterns at the viewer level
		pattern_viewer.clear_patterns()
		
		# Convert discovered patterns to PatternNode objects and add them to the graph
		for disc_pattern in patterns:
			# Ensure pattern ID is an integer
			var pattern_id = disc_pattern.id
			if typeof(pattern_id) != TYPE_INT:
				if typeof(pattern_id) == TYPE_STRING and pattern_id.is_valid_int():
					pattern_id = pattern_id.to_int()
				else:
					# Assign a new integer ID if the existing ID is not an integer
					pattern_id = patterns.find(disc_pattern)
					disc_pattern.id = pattern_id
			
			# Create a PatternNode object from the discovered pattern
			var pattern_node = pattern_graph.PatternNode.new(pattern_id)
			pattern_node.pattern_type = disc_pattern.get("type", "unknown")
			pattern_node.position = disc_pattern.get("position", Vector3.ZERO)
			pattern_node.items = disc_pattern.get("items", [])
			pattern_node.confidence = disc_pattern.get("confidence", 0.5)
			
			# Add metadata
			if disc_pattern.has("metadata"):
				pattern_node.metadata = disc_pattern.metadata
			
			# Add the pattern to the graph
			pattern_graph.add_pattern(pattern_node)
			print("Added pattern with ID: ", pattern_id, " to the graph")
			
		# Pass the original array to display_patterns for visualization
		pattern_viewer.display_patterns(patterns)
		_show_notification("Discovered " + str(patterns.size()) + " patterns")
	else:
		printerr("Synaxes Plugin: PatternViewer not found")
		_show_notification("Error: Pattern viewer not found")

# Handle clear button press
func _on_clear_button_pressed() -> void:
	var pattern_viewer: Node = _bound_pattern_viewer()
	if pattern_viewer:
		pattern_viewer.clear_patterns()
		_show_notification("Cleared patterns")

# Helper functions
func _show_notification(message: String) -> void:
	print("Synaxes: " + message)
	_update_debug_label(message)

func _show_error(message: String) -> void:
	push_error("Synaxes Error: " + message)
	_update_debug_label("[ERROR] " + message)

func _update_debug_label(message: String) -> void:
	if not main_panel_instance:
		return
	var debug_label: Label = _bound_node("DebugInfo") as Label
	if debug_label:
		debug_label.text = message
