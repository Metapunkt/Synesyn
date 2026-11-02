## Purpose: ui/content_source_list/content_source_item.gd
@tool
extends VBoxContainer

signal select_toggled(source_id: String, selected: bool)
signal delete_requested(source_id: String)
signal metaprompt_toggled(source_id: String, is_metaprompt: bool)
signal active_source_toggled(source_id: String, is_active: bool)
signal view_requested(view_mode: int, source_id: String) # ViewStateResource.ViewMode int
signal source_selected(source_id: String, selected: bool)
signal show_error_requested(title: String, message: String)

@onready var select_check: CheckBox = get_node_or_null("%SelectCheck")
@onready var name_label: Label = get_node_or_null("%NameLabel")
@onready var delete_source_button: Button = get_node_or_null("%Delete_Source_Button")
@onready var metaprompt_check: CheckBox = get_node_or_null("%MetapromptCheck")
@onready var active_source_check: CheckBox = get_node_or_null("%ActiveSourceCheck")
@onready var stack_badge: Label = get_node_or_null("%StackBadge")
@onready var unwired_badge: Label = get_node_or_null("%UnwiredBadge")
@onready var include_unwired_check: CheckBox = get_node_or_null("%IncludeUnwiredCheck")

@onready var graph_view_button: Button = %GraphView_Button
@onready var show_hierarchy_button: Button = %Show_Hierarchy_Button

var _source_id: String = ""
var _initialized: bool = false
var _is_hierarchy_mode: bool = false
var _source_name: String = ""
var _source_path: String = ""
var _setup_data: Dictionary = {}
var _is_updating_metaprompt: bool = false
var _is_updating_active_state: bool = false
var _is_updating_include_unwired: bool = false

# Injected state (preferred). Views/coordinators own ContentBus; items should not.
var _content_state: ContentStateResource = null
var _view_state: ViewStateResource = null

func _ready() -> void:
	# Connect signals
	if not select_check.toggled.is_connected(_on_select_check_toggled):
		select_check.toggled.connect(_on_select_check_toggled)
	
	if not delete_source_button.pressed.is_connected(_on_delete_source_button_pressed):
		delete_source_button.pressed.connect(_on_delete_source_button_pressed)
	
	if not show_hierarchy_button.pressed.is_connected(_on_show_hierarchy_button_pressed):
		show_hierarchy_button.pressed.connect(_on_show_hierarchy_button_pressed)
	
	if not metaprompt_check.toggled.is_connected(_on_metaprompt_check_toggled):
		metaprompt_check.toggled.connect(_on_metaprompt_check_toggled)
		
	if not active_source_check.toggled.is_connected(_on_active_source_check_toggled):
		active_source_check.toggled.connect(_on_active_source_check_toggled)
	
	if not graph_view_button.pressed.is_connected(_on_graph_view_button_pressed):
		graph_view_button.pressed.connect(_on_graph_view_button_pressed)
	
	# Apply any pending setup data
	if not _setup_data.is_empty():
		# Defer to ensure @onready node refs are valid.
		call_deferred("_apply_setup", _setup_data)

func setup(id: String, name: String, path: String = "", initial_metaprompt: bool = false) -> void:
	# Store setup data (without initial_active)
	_setup_data = {
		"id": id,
		"name": name,
		"path": path,
		"is_metaprompt": initial_metaprompt
		# is_active will be fetched from resource
	}
	# Apply setup when we're in the tree and child nodes exist.
	if is_inside_tree():
		call_deferred("_apply_setup", _setup_data)

func set_resources(content_state: ContentStateResource, view_state: ViewStateResource = null) -> void:
	_content_state = content_state
	_view_state = view_state

func _apply_setup(data: Dictionary) -> void:
	_source_id = data.get("id", "")
	_source_name = data.get("name", "")
	_source_path = data.get("path", "")
	
	# <<< FORCE MINIMUM SIZE >>>
	custom_minimum_size.y = 50 # Or another appropriate value
	
	# Set initial button states
	if show_hierarchy_button:
		show_hierarchy_button.visible = true  # Always visible in list view
	if graph_view_button:
		graph_view_button.visible = false  # Hidden by default
	
	# Update name label with the name
	if name_label:
		name_label.text = _source_name.strip_edges()
	
	# Set tooltips and path label
	if not _source_path.is_empty():
		if name_label:
			name_label.tooltip_text = _source_path.strip_edges()
		# Update the path label with the path
		var path_label = get_node_or_null("%PathLabel")
		if path_label:
			path_label.text = _source_path.strip_edges()
	
	# Mark as initialized BEFORE setting checkbox states programmatically
	_initialized = true
	_setup_data.clear() # Clear pending data now

	# Fetch and apply CURRENT states from the resource DEFINITIVELY
	if (_source_id.is_empty()):
		push_warning("ContentSourceItem: Cannot fetch states, _source_id is empty during setup.")
		# Set defaults - flag prevents handler from emitting signals
		_is_updating_metaprompt = true
		_is_updating_active_state = true
		if metaprompt_check:
			metaprompt_check.button_pressed = false
		if active_source_check:
			active_source_check.button_pressed = false
		_is_updating_metaprompt = false
		_is_updating_active_state = false
		return
		
	if not is_instance_valid(_content_state):
		push_warning("ContentSourceItem: Could not get ContentStateResource to check states for %s" % _source_id)
		_is_updating_metaprompt = true
		_is_updating_active_state = true
		if metaprompt_check:
			metaprompt_check.button_pressed = false
		if active_source_check:
			active_source_check.button_pressed = false
		_is_updating_metaprompt = false
		_is_updating_active_state = false
		return
	
	# Fetch definitive states
	var current_active_state = _content_state.get_source_active_state(_source_id)
	var current_metaprompt_state = _content_state.get_metaprompt_state(_source_id)

	# Stack UI indicators (badge + unwired count + include_unwired toggle)
	var is_stack := false
	var unwired_count := 0
	var include_unwired := true
	if _content_state.has_method("is_stack_source"):
		is_stack = bool(_content_state.is_stack_source(_source_id))
	if is_stack:
		if _content_state.has_method("get_stack_unwired_member_count"):
			unwired_count = int(_content_state.get_stack_unwired_member_count(_source_id))
		if _content_state.has_method("get_stack_include_unwired_nodes"):
			include_unwired = bool(_content_state.get_stack_include_unwired_nodes(_source_id))
	if stack_badge:
		stack_badge.visible = is_stack
		stack_badge.tooltip_text = "This content source is a STACK (orchestration asset)" if is_stack else ""
	if unwired_badge:
		unwired_badge.visible = is_stack and unwired_count > 0
		if is_stack:
			unwired_badge.text = "Unwired: %d" % unwired_count
			unwired_badge.tooltip_text = "Members with no precedence edges in this stack"
	if include_unwired_check:
		include_unwired_check.visible = is_stack
		include_unwired_check.tooltip_text = "When off, this stack acts like a strict pipeline: only wired members are included in context compilation."
		_is_updating_include_unwired = true
		include_unwired_check.button_pressed = include_unwired
		_is_updating_include_unwired = false
	
	# Apply the definitive fetched states - flags prevent handlers from emitting signals
	_is_updating_metaprompt = true
	_is_updating_active_state = true
	if metaprompt_check:
		metaprompt_check.button_pressed = current_metaprompt_state
	if active_source_check:
		active_source_check.button_pressed = current_active_state
	_is_updating_metaprompt = false
	_is_updating_active_state = false

func _on_select_check_toggled(button_pressed: bool) -> void:
	if not _initialized:
		return
		
	print("ContentSourceItem: Selection toggled for %s to %s" % [_source_id, str(button_pressed)])
	select_toggled.emit(_source_id, button_pressed)

func _on_delete_source_button_pressed() -> void:
	if not _initialized:
		return
	delete_requested.emit(_source_id)

func _on_show_hierarchy_button_pressed() -> void:
	if not _initialized:
		return
		
	view_requested.emit(1, _source_id) # ViewStateResource.ViewMode.HIERARCHY

func _on_graph_view_button_pressed() -> void:
	if not _initialized:
		return
		
	view_requested.emit(2, _source_id) # ViewStateResource.ViewMode.GRAPH

func _on_metaprompt_check_toggled(button_pressed: bool) -> void:
	if _source_id.is_empty():
		print("ERROR: Empty source ID")
		return

	if not _initialized:
		print("WARNING: Not initialized yet, deferring toggle")
		await self.ready
		if not _initialized:
			print("ERROR: Still not initialized after ready")
			return

	if _is_updating_metaprompt:
		print("SKIPPED: Recursive metaprompt toggle prevented")
		return

	_is_updating_metaprompt = true
	metaprompt_toggled.emit(_source_id, button_pressed)
	_is_updating_metaprompt = false

func _on_active_source_check_toggled(button_pressed: bool) -> void:
	if _source_id.is_empty():
		print("ERROR: Empty source ID")
		return

	if not _initialized:
		print("WARNING: Not initialized yet, deferring toggle")
		await self.ready
		if not _initialized:
			print("ERROR: Still not initialized after ready")
			return

	if _is_updating_active_state:
		print("SKIPPED: Recursive active state toggle prevented")
		return

	_is_updating_active_state = true
	active_source_toggled.emit(_source_id, button_pressed)
	_is_updating_active_state = false

func _on_include_unwired_check_toggled(button_pressed: bool) -> void:
	if _source_id.is_empty() or not _initialized:
		return
	if _is_updating_include_unwired:
		return
	if not is_instance_valid(_content_state):
		return
	if not _content_state.has_method("set_stack_include_unwired_nodes"):
		return
	# Only applicable to stacks; ignore for non-stacks defensively.
	if _content_state.has_method("is_stack_source") and not bool(_content_state.is_stack_source(_source_id)):
		return
	_is_updating_include_unwired = true
	_content_state.set_stack_include_unwired_nodes(_source_id, button_pressed)
	# Refresh unwired indicator after change (strict mode may render all members unwired).
	if unwired_badge and _content_state.has_method("get_stack_unwired_member_count"):
		var c := int(_content_state.get_stack_unwired_member_count(_source_id))
		unwired_badge.visible = c > 0
		unwired_badge.text = "Unwired: %d" % c
	_is_updating_include_unwired = false

# Handler for ContentBus metaprompt state changes
func _on_metaprompt_state_changed(source_id: String, is_metaprompt: bool) -> void:
	# Skip if not initialized or already updating
	if not _initialized or _is_updating_metaprompt:
		return
		
	# Direct comparison is sufficient as _source_id always holds the parent source ID
	if source_id == _source_id:
		update_metaprompt_state(is_metaprompt)
	else:
		pass

# Update metaprompt state - flag prevents handler from emitting signal
func update_metaprompt_state(is_metaprompt: bool) -> void:
	if not _initialized or not metaprompt_check:
		return
	_is_updating_metaprompt = true
	metaprompt_check.button_pressed = is_metaprompt
	_is_updating_metaprompt = false

func set_hierarchy_mode(enabled: bool) -> void:
	_is_hierarchy_mode = enabled
	
	# Update UI elements for hierarchy mode
	if show_hierarchy_button:
		show_hierarchy_button.visible = not enabled
	if graph_view_button:
		graph_view_button.visible = enabled
	if delete_source_button:
		delete_source_button.visible = enabled
		# Keep label as plain “Delete” (preferred), but behavior is node-scoped in hierarchy view.
		delete_source_button.tooltip_text = ("Delete this node from the hierarchy (does not delete the source file)." if enabled else "")
	
	# In hierarchy mode, we want to show both checkboxes
	if metaprompt_check:
		metaprompt_check.visible = true
	if active_source_check:
		active_source_check.visible = true

func _update_source() -> void:
	if _source_id.is_empty():
		return
		
	if not is_instance_valid(_content_state):
		push_error("ContentSourceItem: ContentStateResource not available for update.")
		return
		
	var source_data = _content_state.get_source_data(_source_id)
	if source_data.is_empty():
		push_error("ContentSourceItem: No source data found for ID: " + _source_id)
		return
		
	var err = _content_state.update_source(_source_id, source_data)
	if err != OK:
		push_error("ContentSourceItem: Failed to update source: " + _source_id)

# Get source ID for external queries
func get_source_id() -> String:
	return _source_id

func _on_active_state_changed(source_id: String, is_active: bool) -> void:
	# Skip if not initialized or already updating
	if not _initialized or _is_updating_active_state:
		return
		
	# Direct comparison is sufficient
	if source_id == _source_id:
		update_active_state(is_active)
	else:
		pass

func update_active_state(is_active: bool) -> void:
	if not _initialized or not active_source_check:
		return
	_is_updating_active_state = true
	active_source_check.button_pressed = is_active
	_is_updating_active_state = false
