## Purpose: Manages UI view switching (via TabContainer) and display logic
"""
COMPONENT: ContentViewManager
RESPONSIBILITY: Manages UI view switching (via TabContainer) and display logic
PUBLIC API:
  - setup(ui_references): Initialize with external references
  - update_content_source_options(): Update source list UI
DEPENDENCIES:
  - ContentBus: For signals and view state
  - External UI references (TabContainer, content nodes): Passed in via setup()
  - ContentGraphController: For graph operations

VIEW SWITCHING ARCHITECTURE (TabContainer):
- Uses a TabContainer to manage visibility of List, Hierarchy, and Graph views.
- Tab indices assumed: List=0, Hierarchy=1, Graph=2.
- Connects to TabContainer's `tab_selected` signal for user interaction.
- Manages the `disabled` state of Hierarchy (1) and Graph (2) tabs based on source selection.
- Updates TabContainer's `current_tab` property in response to ContentBus signals.
- Calls methods on content nodes (Hierarchy, Graph) when their tabs become active.
"""
@tool
extends Control

# Preloaded resources
const ContentGraphController = preload("res://addons/syntree/scripts/ui/content_graph/content_graph_controller.gd")
const ContentSourceItem = preload("res://addons/syntree/scripts/ui/content_source_list/content_source_item.gd")
const ContentSourceItemScene = preload("res://addons/syntree/scenes/content_source_item.tscn")

# Signals
signal show_error_requested(title: String, message: String, details: String)

# --- NEW UI REFERENCES (set by SyntreePanel) ---
var _sources_tab_container: TabContainer = null
var _content_list_container: Container = null   # Container within the List tab
var _content_hierarchy_node: Control = null     # The actual hierarchy view node (in Hierarchy tab)
var _graph_view_node: GraphEdit = null          # The actual GraphEdit node (in Graph tab)
var _conversation_manager: Object = null

# Graph references
var _graph_controller: Node = null

# State tracking
var _current_source_id: String = ""
var _current_view_mode: int = 0 # ViewStateResource.ViewMode.LIST
var _is_ready: bool = false
var _is_transitioning: bool = false # Used to prevent loops during state changes
var _debug_name: String = "ContentViewManager"

# Injected state
var _content_state: ContentStateResource = null
var _view_state: ViewStateResource = null
var _last_seen_mode: int = 0
var _last_seen_source_id: String = ""

# Tab Mapping - Using direct enum values
var _view_mode_to_tab_index: Dictionary = {}
var _tab_index_to_view_mode: Dictionary = {}

func _build_tab_mapping() -> void:
	# Make tab mapping resilient to reordering by using the tab control node names.
	_view_mode_to_tab_index.clear()
	_tab_index_to_view_mode.clear()
	if not is_instance_valid(_sources_tab_container):
		return

	for i in range(_sources_tab_container.get_tab_count()):
		var c := _sources_tab_container.get_tab_control(i)
		if not is_instance_valid(c):
			continue
		var n := str(c.name)
		match n:
			"ContentList":
				_view_mode_to_tab_index[0] = i
				_tab_index_to_view_mode[i] = 0
			"ContentHierarchy":
				_view_mode_to_tab_index[1] = i
				_tab_index_to_view_mode[i] = 1
			"ContextGraphWorkspace":
				_view_mode_to_tab_index[2] = i
				_tab_index_to_view_mode[i] = 2
			_:
				pass

	# Safe fallbacks if naming is missing or modified.
	if not _view_mode_to_tab_index.has(0):
		_view_mode_to_tab_index[0] = 0
		_tab_index_to_view_mode[0] = 0
	if not _view_mode_to_tab_index.has(1) and _sources_tab_container.get_tab_count() > 1:
		_view_mode_to_tab_index[1] = 1
		_tab_index_to_view_mode[1] = 1
	if not _view_mode_to_tab_index.has(2) and _sources_tab_container.get_tab_count() > 2:
		_view_mode_to_tab_index[2] = 2
		_tab_index_to_view_mode[2] = 2

func _ready() -> void:
	print("ViewManager: Ready called")
	_is_ready = true
	# Wait for injected resources (connected in setup()).
	
	# Note: TabContainer connection is handled in setup()
	# The warning about _sources_tab_container not being set in _ready is expected
	# because it's initialized during setup() which happens after _ready()
	
	# If we already have the tab container (unlikely but possible), connect to it
	if _sources_tab_container:
		_connect_tab_container_signals()

# New helper function to centralize tab container signal connections
func _connect_tab_container_signals() -> void:
	if _sources_tab_container and not _sources_tab_container.tab_selected.is_connected(_on_sources_tab_selected):
		_sources_tab_container.tab_selected.connect(_on_sources_tab_selected)
		print("ViewManager: Connected to TabContainer tab_selected signal")

func _connect_state_signals() -> void:
	if not is_instance_valid(_view_state):
		push_warning("ViewManager: ViewStateResource not injected; cannot connect state signals.")
		return
	if not _view_state.source_selected.is_connected(_on_source_selected):
		_view_state.source_selected.connect(_on_source_selected)
	if not _view_state.view_state_changed.is_connected(_on_view_state_changed_from_resource):
		_view_state.view_state_changed.connect(_on_view_state_changed_from_resource)

func _on_source_selected(source_id: String, selected: bool = true) -> void:
	print("ViewManager: Source selection event - source_id: %s, selected: %s" % [source_id, str(selected)])
	
	if _is_transitioning:
		print("ViewManager: Skipping source selection handling - currently transitioning")
		return
		
	# Update current source tracking
	var source_changed = false
	if selected:
		if _current_source_id != source_id:
			_current_source_id = source_id
			source_changed = true
			print("ViewManager: Source %s selected, setting _current_source_id" % source_id)
	elif _current_source_id == source_id: # Only clear if the deselected source was the current one
		_current_source_id = ""
		source_changed = true
		print("ViewManager: Source %s deselected, clearing _current_source_id" % source_id)
	
	# Update tab states ONLY if the effective selection changed
	if source_changed:
		_update_tab_states()
		print("ViewManager: Updated tab states after source selection change")

func setup(ui_references: Dictionary) -> void:
	print("ViewManager: Setting up with UI references (TabContainer)")
	
	# Store UI references from SyntreePanel
	_sources_tab_container = ui_references.get("sources_tab_container")
	_content_list_container = ui_references.get("content_list_container")
	_content_hierarchy_node = ui_references.get("content_hierarchy_node")
	_graph_view_node = ui_references.get("graph_view_node")
	_content_state = ui_references.get("content_state")
	_view_state = ui_references.get("view_state")
	_conversation_manager = ui_references.get("conversation_manager")
	
	# Validate required references
	if not _sources_tab_container:
		push_error("ViewManager: Missing sources_tab_container reference!")
		return
	if not _content_list_container:
		push_error("ViewManager: Missing content_list_container reference!")
		return
	if not _content_hierarchy_node:
		push_error("ViewManager: Missing content_hierarchy_node reference!")
		return
	if not _graph_view_node:
		push_error("ViewManager: Missing graph_view_node reference!")
		return
	
	# Log paths for debugging
	print("ViewManager (setup): Validating node references...")
	if is_instance_valid(_content_list_container):
		print("  - List container path: %s" % _content_list_container.get_path())
	if is_instance_valid(_content_hierarchy_node):
		print("  - Hierarchy node path: %s" % _content_hierarchy_node.get_path())
	if is_instance_valid(_graph_view_node):
		print("  - Graph view path: %s" % _graph_view_node.get_path())
	
	# Connect tab container signals using the helper
	_connect_tab_container_signals()

	# Build mapping after tab container is available.
	_build_tab_mapping()
	
	# Initialize graph controller (only when state is injected)
	if is_instance_valid(_content_state) and is_instance_valid(_view_state) and is_instance_valid(_graph_view_node):
		_initialize_graph_controller()
	else:
		# Avoid spamming errors during early editor startup; we will retry on the next view_state change.
		push_warning("ViewManager: Deferring graph controller init until resources are injected.")

	# Ensure state signals are connected
	_last_seen_mode = int(_view_state.current_mode) if is_instance_valid(_view_state) else 0
	_last_seen_source_id = String(_view_state.current_source_id) if is_instance_valid(_view_state) else ""
	_connect_state_signals()
	
	# Set initial tab states - use call_deferred to ensure UI is ready
	call_deferred("_update_tab_states")
	
	print("ViewManager: Setup complete")

func _initialize_graph_controller() -> void:
	print("ViewManager: Initializing graph controller...")

	# Per-panel controller instance (do NOT use a singleton here).
	_graph_controller = ContentGraphController.new()
	if not is_instance_valid(_graph_controller):
		push_error("ViewManager: Failed to create ContentGraphController")
		return

	# Ensure it's in the scene tree (but don't reparent if another owner already attached it).
	if not _graph_controller.get_parent():
		add_child(_graph_controller)
	
	if not is_instance_valid(_content_state):
		push_error("ViewManager: Cannot initialize graph controller - ContentStateResource not injected")
		return
	
	# Initialize controller with graph view and content state
	if _graph_controller.has_method("initialize"):
		# Only re-initialize if needed (e.g., first init or graph view changed due to refactor).
		var is_inited := bool(_graph_controller.get("_is_initialized"))
		var bound_view = _graph_controller.get("graph_view")
		var bound_state = _graph_controller.get("content_state")
		if (not is_inited) or (bound_view != _graph_view_node) or (bound_state != _content_state):
			print("ViewManager: Binding graph controller to current graph view/state")
			_graph_controller.initialize(
				_content_state,
				_graph_view_node,
				_view_state,
				_conversation_manager
			)
	else:
		push_error("ViewManager: GraphController missing initialize method!")

# REMOVE This function - ContentListView now handles populating itself
# func update_content_source_options() -> void:
# 	...

# REMOVE These functions - Not needed if ContentListView manages children
# func _clear_content_source_items() -> void:
# 	...
# func _add_content_source_item(item_instance: Node) -> void:
# 	...

# REMOVE array storing items
# var _content_source_items: Array[Node] = []

# REMOVE the handler - ContentListView handles the signal now
# func _on_content_model_ready() -> void: 
# 	...

# --- NEW FUNCTION --- 
func _update_tab_states() -> void:
	if not _sources_tab_container:
		push_warning("ViewManager: Cannot update tab states - tab container not available")
		return
		
	var has_valid_source = not _current_source_id.is_empty()

	# Recompute mapping in case tabs were modified at runtime (editor refactors).
	_build_tab_mapping()
	var hierarchy_idx: int = int(_view_mode_to_tab_index.get(1, 1))
	var graph_idx: int = int(_view_mode_to_tab_index.get(2, 2))
	var list_idx: int = int(_view_mode_to_tab_index.get(0, 0))

	# Update tab disabled states
	if hierarchy_idx >= 0 and hierarchy_idx < _sources_tab_container.get_tab_count():
		_sources_tab_container.set_tab_disabled(hierarchy_idx, not has_valid_source)
	if graph_idx >= 0 and graph_idx < _sources_tab_container.get_tab_count():
		_sources_tab_container.set_tab_disabled(graph_idx, not has_valid_source)
	
	# Update tab titles based on state
	if not has_valid_source:
		if hierarchy_idx >= 0 and hierarchy_idx < _sources_tab_container.get_tab_count():
			_sources_tab_container.set_tab_title(hierarchy_idx, "Hierarchy (Select Source)")
		if graph_idx >= 0 and graph_idx < _sources_tab_container.get_tab_count():
			_sources_tab_container.set_tab_title(graph_idx, "Context Graph (Select Source)")
		
		# If we're on a disabled tab, switch to list view
		var current_tab = _sources_tab_container.current_tab
		if _sources_tab_container.is_tab_disabled(current_tab):
			# Prevent tab_selected feedback loop while we correct the UI.
			_sources_tab_container.set_block_signals(true)
			_sources_tab_container.current_tab = list_idx
			_sources_tab_container.set_block_signals(false)
			if is_instance_valid(_view_state):
				_view_state.change_view(0, "") # ViewStateResource.ViewMode.LIST
	else:
		# Show the currently displayed source name in the tab header (truncated),
		# instead of stack diagnostics that can bloat headers.
		var sd: Dictionary = {}
		if is_instance_valid(_content_state) and _content_state.has_method("get_source_data"):
			sd = _content_state.get_source_data(_current_source_id)
		var current_id := String(_current_source_id).strip_edges()
		var full_name := _get_source_display_name(current_id, sd)
		var short_name := _truncate_tab_label(full_name, 12)
		var suffix := " [%s]" % short_name
		
		# Optional tooltip with full name + stack info (keeps UI compact while retaining detail).
		var path_txt := ""
		if sd.has("meta") and (sd.get("meta") is Dictionary):
			path_txt = String((sd.get("meta") as Dictionary).get("path", "")).strip_edges()
		var tooltip := "Source: %s\nID: %s" % [full_name, current_id]
		if not path_txt.is_empty():
			tooltip += "\nPath: %s" % path_txt
		if is_instance_valid(_content_state) and _content_state.has_method("is_stack_source") and _content_state.is_stack_source(current_id):
			var uw := 0
			if _content_state.has_method("get_stack_unwired_member_count"):
				uw = int(_content_state.get_stack_unwired_member_count(current_id))
			tooltip += "\nSTACK (Unwired: %d)" % uw

		var stack_tag := ""
		if is_instance_valid(_content_state) and _content_state.has_method("is_stack_source") and bool(_content_state.is_stack_source(current_id)):
			# Make stack context visible without relying on tooltip-only discovery.
			stack_tag = " [STACK]"

		if hierarchy_idx >= 0 and hierarchy_idx < _sources_tab_container.get_tab_count():
			_sources_tab_container.set_tab_title(hierarchy_idx, "Hierarchy" + suffix + stack_tag)
			if _sources_tab_container.has_method("set_tab_tooltip"):
				_sources_tab_container.set_tab_tooltip(hierarchy_idx, tooltip)
		if graph_idx >= 0 and graph_idx < _sources_tab_container.get_tab_count():
			_sources_tab_container.set_tab_title(graph_idx, "Context Graph" + suffix + stack_tag)
			if _sources_tab_container.has_method("set_tab_tooltip"):
				_sources_tab_container.set_tab_tooltip(graph_idx, tooltip)

# REMOVED: _update_hierarchy_button_state

# REMOVED: _force_check_graph_visibility

# REMOVED: _initialize_graph_view - Handled in setup

# REMOVED: _validate_graph_components - Simplified

# REMOVED: _ensure_graph_nodes_for_source - Logic moved to _on_view_state_changed

# REMOVED: _show_list_view
# REMOVED: _show_hierarchy_view
# REMOVED: _show_graph_view

# Helper to consistently get source display name
func _get_source_display_name(source_id: String, source_data: Dictionary) -> String:
	var display_name: String = String(source_id).strip_edges()
	# Try multiple possible locations for the name
	if source_data.has("meta") and source_data["meta"].has("name"):
		display_name = String(source_data["meta"]["name"]).strip_edges()
	elif source_data.has("name"):
		display_name = String(source_data["name"]).strip_edges()
	return display_name

func _truncate_tab_label(s: String, max_len: int) -> String:
	var t := String(s).strip_edges()
	if max_len <= 0:
		return ""
	if t.length() > max_len:
		return t.substr(0, max_len) + "..."
	return t

# --- Signal handlers ---

# REMOVED: _on_list_view_button_pressed
# REMOVED: _on_hierarchy_view_button_pressed
# REMOVED: _on_graph_view_button_pressed

# --- NEW HANDLER for TabContainer ---
func _on_sources_tab_selected(tab_idx: int) -> void:
	print("ViewManager: Tab selected by user: index %d" % tab_idx)
	
	if _is_transitioning:
		print("ViewManager: Ignoring tab selection during transition")
		return
	
	_build_tab_mapping()
	if not _tab_index_to_view_mode.has(tab_idx):
		push_error("ViewManager: Selected tab index %d is invalid!" % tab_idx)
		return
		
	# Prevent selecting disabled tabs (though UI should prevent this, add safeguard)
	if _sources_tab_container.is_tab_disabled(tab_idx):
		print("ViewManager: Attempted to select disabled tab %d. Reverting." % tab_idx)
		# Revert selection visually - needs care to avoid loops
		var previous_tab_idx = int(_view_mode_to_tab_index.get(_current_view_mode, 0))
		_sources_tab_container.set_block_signals(true)
		_sources_tab_container.call_deferred("set_current_tab", previous_tab_idx)
		# Unblock on next frame so the deferred tab change doesn't emit tab_selected.
		get_tree().process_frame.connect(func(): _sources_tab_container.set_block_signals(false), CONNECT_ONE_SHOT)
		return
	
	var new_mode = _tab_index_to_view_mode[tab_idx]
	
	# If the selected tab corresponds to the current mode, do nothing
	if new_mode == _current_view_mode:
		print("ViewManager: Selected tab (%d) matches current view mode (%d). No change." % [tab_idx, new_mode])
		return
		
	print("ViewManager: Requesting view change with source_id: '%s'" % _current_source_id) 
	
	if is_instance_valid(_view_state):
		_view_state.change_view(int(new_mode), _current_source_id)

# --- Existing handlers (modified or kept) ---

func _on_show_hierarchy_requested(source_id: String) -> void:
	print("ViewManager: Show hierarchy requested externally for source: " + source_id)
	
	if source_id.is_empty():
		push_warning("ViewManager: Cannot show hierarchy - empty source ID")
		return
		
	# Always update internal source ID when explicitly requested
	_current_source_id = source_id
	print("ViewManager: Updated current source ID to: %s" % source_id)
	
	# Get source data before switching view
	print("ViewManager: Getting source data before hierarchy view change...")
	var source_data = _content_state.get_source_data(source_id) if is_instance_valid(_content_state) else {}
	if source_data.is_empty():
		push_warning("ViewManager: Cannot switch to hierarchy view - no source data available")
		return
	
	# Update tab states before switching view
	_update_tab_states()
	
	# Request view change to hierarchy mode with the source ID
	print("ViewManager: Requesting view change to HIERARCHY mode for source: %s" % source_id)
	if is_instance_valid(_view_state):
		_view_state.change_view(1, source_id) # ViewStateResource.ViewMode.HIERARCHY

func _on_edit_source_requested(source_id: String) -> void:
	print("ViewManager: Edit source requested: " + source_id)
	# TODO: Delegate to ContentBus or handle directly

func _on_delete_source_requested(source_id: String) -> void:
	print("ViewManager: Delete source requested: " + source_id)
	# TODO: Delegate to ContentBus or handle directly

func _on_show_error(title: String, message: String, details: String) -> void:
	print("ViewManager: Show error requested: ", title)
	show_error_requested.emit(title, message, details)

func _on_view_state_changed(_old_mode: int, _new_mode: int, _source_id: String) -> void:
	# Legacy hook (ContentBus-driven). Kept as a no-op during refactor.
	pass

func _on_view_state_changed_from_resource() -> void:
	if not is_instance_valid(_view_state):
		return

	# Late init: graph controller might be deferred during early boot.
	if (not is_instance_valid(_graph_controller) or not bool(_graph_controller.get("_is_initialized"))) and is_instance_valid(_content_state) and is_instance_valid(_graph_view_node):
		_initialize_graph_controller()

	var old_mode := _last_seen_mode
	var old_source_id := _last_seen_source_id

	var new_mode := int(_view_state.current_mode)
	var new_source_id := String(_view_state.current_source_id)

	# Ignore redundant notifications (common during node selection / checkbox syncing).
	if new_mode == old_mode and new_source_id == old_source_id:
		return

	_last_seen_mode = new_mode
	_last_seen_source_id = new_source_id

	print("ViewManager: ViewStateResource changed: %d -> %d (source: %s -> %s)" % [old_mode, new_mode, old_source_id, new_source_id])

	if _is_transitioning:
		print("ViewManager: Already transitioning, skipping state change")
		return

	_is_transitioning = true
	_current_view_mode = new_mode
	_current_source_id = new_source_id
	_handle_view_state_change_internally(new_mode, new_source_id)
	_is_transitioning = false

func _handle_view_state_change_internally(new_mode: int, source_id: String) -> void:
	print("ViewManager: Internally handling view state change to mode: %d, source: %s" % [new_mode, source_id])
	
	# Validate the new mode is within enum range (0..2)
	if new_mode < 0 or new_mode > 2:
		push_error("ViewManager: Invalid view mode (%d) received. Valid modes are 0-2" % new_mode)
		return
	
	_build_tab_mapping()
	if not _view_mode_to_tab_index.has(new_mode):
		push_error("ViewManager: View mode (%d) not mapped to a tab index" % new_mode)
		_is_transitioning = false
		return
	
	# Update internal tracking state
	_current_view_mode = new_mode
	
	# Update the TabContainer's current tab visually
	var target_tab_idx = int(_view_mode_to_tab_index[new_mode])
	if _sources_tab_container and _sources_tab_container.current_tab != target_tab_idx:
		print("ViewManager: Setting TabContainer current_tab to %d" % target_tab_idx)
		_sources_tab_container.current_tab = target_tab_idx
	
	# Update the disabled state of tabs based on source ID
	_update_tab_states()
	
	# --- Trigger content updates for the specific view --- 
	match new_mode:
		0: # ViewStateResource.ViewMode.LIST
			# List content is updated via update_content_source_options, no immediate action needed here
			pass 
		1: # ViewStateResource.ViewMode.HIERARCHY
			if _content_hierarchy_node and not source_id.is_empty():
				print("ViewManager: Getting source data for hierarchy view...")
				var source_data = _content_state.get_source_data(source_id) if is_instance_valid(_content_state) else {}
				if not source_data.is_empty():
					print("ViewManager: Displaying hierarchy with source data")
					if _content_hierarchy_node.has_method("display_hierarchy"):
						print("ViewManager: Calling display_hierarchy with source data")
						_content_hierarchy_node.display_hierarchy(source_data)
					else:
						push_error("ViewManager: Hierarchy node missing display_hierarchy method!")
				else:
					push_error("ViewManager: No source data available for hierarchy view!")
		2: # ViewStateResource.ViewMode.GRAPH
			if not source_id.is_empty():
				print("ViewManager: Switching to graph view for source: %s" % source_id)
				# Ensure graph controller is initialized
				if not _graph_controller or not _graph_controller.get("_is_initialized"):
					print("ViewManager: Graph controller not initialized, reinitializing...")
					_initialize_graph_controller()
				
				if _graph_controller and _graph_controller.get("_is_initialized"):
					print("ViewManager: Initializing graph with source")
					if _graph_controller.has_method("initialize_with_source"):
						_graph_controller.initialize_with_source(source_id)
					else:
						push_error("ViewManager: Graph controller missing initialize_with_source method!")
				else:
					push_error("ViewManager: Cannot update graph - controller not properly initialized!")
		_:
			push_warning("ViewManager: Unhandled view mode: %d" % new_mode)
	
	print("ViewManager: Internal view state handling complete")

func _on_source_loaded(source_id: String) -> void:
	print("ViewManager: Source loaded signal received: ", source_id)
	# ContentListView should handle refreshing itself based on this signal if needed.

func _on_metaprompt_state_changed(source_id: String, is_metaprompt: bool) -> void:
	print("ContentViewManager: Metaprompt state changed for ", source_id, ": ", is_metaprompt)
	_handle_metaprompt_state_change(source_id, is_metaprompt)

func _handle_metaprompt_state_change(source_id: String, is_metaprompt: bool) -> void:
	print("ContentViewManager: Forwarding metaprompt state change to hierarchy/graph if available.") # Added log	
	# Forward to hierarchy view if available and has method
	if _content_hierarchy_node and _content_hierarchy_node.has_method("_on_metaprompt_state_changed"):
		_content_hierarchy_node._on_metaprompt_state_changed(source_id, is_metaprompt)
		
	# Forward to graph view if available and has method
	if _graph_view_node and _graph_view_node.has_method("_on_metaprompt_state_changed"):
		_graph_view_node._on_metaprompt_state_changed(source_id, is_metaprompt)

# REMOVED: _update_view_visibility

func _update_graph_with_source_data(source_id: String) -> void:
	print("ViewManager: Updating graph with source data: " + source_id)
	
	if not _graph_view_node:
		push_warning("ViewManager: Cannot update graph - GraphEdit node not available")
		return
	
	if not _graph_controller:
		push_warning("ViewManager: Cannot update graph - GraphController not available")
		return
		
	if not is_instance_valid(_content_state):
		push_warning("ViewManager: Cannot initialize graph controller - ContentStateResource not injected")
		return
		
	# Initialize controller if needed
	if not _graph_controller.get("_is_initialized") or _graph_controller.graph_view != _graph_view_node:
		print("ViewManager: Initializing graph controller with ContentStateResource")
		_graph_controller.initialize(
			_content_state,
			_graph_view_node,
			_view_state,
			_conversation_manager
		)
	
	# Call the controller method to build/update the graph
	if _graph_controller.has_method("initialize_with_source"):
		_graph_controller.initialize_with_source(source_id)
	else:
		push_warning("ViewManager: GraphController missing initialize_with_source method.")

# Ensure this class is marked as tool if needed by other tool scripts
# @tool (already at top)
