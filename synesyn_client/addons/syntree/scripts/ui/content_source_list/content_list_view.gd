## Purpose: ContentListView (script)
@tool
extends VBoxContainer
class_name ContentListView

const DEBUG: bool = false

# Use full path to ensure it loads correctly
const ContentSourceItemScene = preload("res://addons/syntree/scenes/content_source_item.tscn")
const ContentSourceItem = preload("res://addons/syntree/scripts/ui/content_source_list/content_source_item.gd")

var _current_source_id: String = ""
var _plugin_ref = null # Add plugin reference
var _current_filters: Dictionary = {} # Store active filters

# Injected state (preferred). Views should not discover ContentBus.
var _content_state: ContentStateResource = null
var _view_state: ViewStateResource = null
var _signals_connected: bool = false

func _ready() -> void:
	# Ensure the container expands
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if DEBUG:
		print("ContentListView [%s]: _ready - Set size flags to expand." % get_instance_id())
	
	# NOTE: we connect signals once resources are injected via setup_list().
	# Views should not discover ContentBus on their own.

# setup function called by SyntreePanel
func setup_list(plugin_ref, content_state: ContentStateResource = null, view_state: ViewStateResource = null) -> void:
	if DEBUG:
		print("ContentListView [%s]: setup_list called with plugin ref" % get_instance_id())
	_plugin_ref = plugin_ref # Store plugin ref
	if not is_instance_valid(_plugin_ref):
		push_warning("ContentListView: Invalid plugin reference received!")

	if is_instance_valid(content_state):
		_content_state = content_state
		if DEBUG:
			print("[LISTVIEW] ContentListView using content_state instance: %s" % str(_content_state.get_instance_id()))
	if is_instance_valid(view_state):
		_view_state = view_state

	_connect_state_signals()
	call_deferred("refresh_sources")

func _connect_state_signals() -> void:
	if _signals_connected:
		return
	if not is_instance_valid(_content_state):
		push_warning("ContentListView: Cannot connect state signals yet (ContentStateResource not injected).")
		return
	_signals_connected = true

	# Keep list fresh when sources change.
	if _content_state.has_signal("source_added") and not _content_state.source_added.is_connected(_on_source_loaded):
		_content_state.source_added.connect(_on_source_loaded)
	if _content_state.has_signal("source_deleted") and not _content_state.source_deleted.is_connected(_on_source_deleted):
		_content_state.source_deleted.connect(_on_source_deleted)
	if _content_state.has_signal("source_updated") and not _content_state.source_updated.is_connected(_on_source_updated):
		_content_state.source_updated.connect(_on_source_updated)

	# Keep item toggles in sync.
	if _content_state.has_signal("metaprompt_state_changed") and not _content_state.metaprompt_state_changed.is_connected(_on_metaprompt_state_changed):
		_content_state.metaprompt_state_changed.connect(_on_metaprompt_state_changed)
	if _content_state.has_signal("active_state_changed") and not _content_state.active_state_changed.is_connected(_on_active_state_changed):
		_content_state.active_state_changed.connect(_on_active_state_changed)

	# Track selection/view changes (optional)
	if is_instance_valid(_view_state) and _view_state.has_signal("source_selected") and not _view_state.source_selected.is_connected(_on_source_selected):
		_view_state.source_selected.connect(_on_source_selected)
	if is_instance_valid(_view_state) and _view_state.has_signal("view_state_changed") and not _view_state.view_state_changed.is_connected(_on_view_state_changed):
		_view_state.view_state_changed.connect(_on_view_state_changed)

func _on_source_loaded(_source_id: String) -> void:
	# Newly created sources should appear immediately without requiring manual refresh.
	call_deferred("refresh_sources")

func _on_source_deleted(_source_id: String) -> void:
	call_deferred("refresh_sources")

# --- ADDED Missing Handler --- 
# Add handler for active source state changes FROM CONTENT BUS
func _on_active_state_changed(signal_source_id: String, is_active: bool) -> void:
	if DEBUG:
		print("ContentListView: Received active_state_changed for source %s to %s" % [signal_source_id, str(is_active)])

	# Skip if view is not visible or source ID is empty
	if not visible or signal_source_id.is_empty():
		if DEBUG:
			print("ContentListView: Skipping active state update (view hidden or empty source ID)")
		return

	if not is_instance_valid(_content_state):
		return
	var normalized_signal_source = _content_state.get_normalized_id(signal_source_id)
	var found_match = false

	# Update the item that corresponds to this source ID
	for child in get_children():
		if child is ContentSourceItem:
			# Use the item's stored _source_id for matching
			var item_source_id = child._source_id 
			var normalized_item_source = _content_state.get_normalized_id(item_source_id)

			if normalized_item_source == normalized_signal_source:
				if DEBUG:
					print("ContentListView: Updating Active state for item %s to %s" % [item_source_id, str(is_active)])
				if child.has_method("update_active_state"):
					# Call the item's method to update its visual state and internal state
					child.update_active_state(is_active) 
					found_match = true
					# No need to break, update all items related to this source if needed (though usually 1:1)
				else:
					push_warning("ContentListView: ContentSourceItem missing update_active_state method.")
					break # Stop searching if method is missing on the correct item type
	
	if not found_match:
		if DEBUG:
			print("ContentListView: No UI item found for source ID: %s in _on_active_state_changed" % signal_source_id)
func _on_view_state_changed() -> void:
	# ViewStateResource emits a generic changed signal; read current_mode.
	if not is_instance_valid(_view_state):
		return
	if int(_view_state.current_mode) == 0: # ViewStateResource.ViewMode.LIST
		call_deferred("refresh_sources")

func _on_filters_applied(filters: Dictionary) -> void:
	_current_filters = filters
	refresh_sources()

func clear_filters() -> void:
	_current_filters.clear()
	refresh_sources()

func update_selection(source_id: String) -> void:
	# Legacy helper: keep it in sync with ViewStateResource (multi-select).
	_current_source_id = source_id
	if not is_instance_valid(_view_state):
		return
	for child in get_children():
		if child is ContentSourceItem and child.select_check:
			var is_selected := _view_state.is_source_selected(child._source_id)
			child.select_check.set_block_signals(true)
			child.select_check.button_pressed = is_selected
			child.select_check.set_block_signals(false)

func _add_source_item(source_id: String, source_data: Dictionary) -> void:
	if DEBUG:
		print("ContentListView: Adding source item for %s" % source_id)
	
	# Validate source data structure
	if source_data.is_empty():
		push_warning("ContentListView: Empty source data for %s" % source_id)
		return
		
	# Extract metadata with fallbacks
	var source_name = "Unnamed Source"
	var source_path = ""
	var is_metaprompt = false
	
	if source_data.has("meta"):
		var meta = source_data["meta"]
		source_name = meta.get("name", source_id) # Fallback to ID if no name
		source_path = meta.get("path", "")
		is_metaprompt = meta.get("ai_context", {}).get("metaprompt", false)
	else:
		# Try direct access if no meta section
		source_name = source_data.get("name", source_id)
		source_path = source_data.get("path", "")
		is_metaprompt = source_data.get("ai_context", {}).get("metaprompt", false)
	
	if DEBUG:
		print("ContentListView: Processed metadata - name: %s, path: %s, metaprompt: %s" % [source_name, source_path, str(is_metaprompt)])
	
	# Instantiate the item scene
	var item = ContentSourceItemScene.instantiate()
	if not is_instance_valid(item):
		push_error("ContentListView: Failed to instantiate ContentSourceItem")
		return
	
	# Add the item to this container
	add_child(item)

	# Inject resources + wire item intents to resources/state (no ContentBus coupling)
	if item.has_method("set_resources"):
		item.set_resources(_content_state, _view_state)

	# Selection intent
	if item.has_signal("select_toggled") and is_instance_valid(_view_state):
		if not item.select_toggled.is_connected(_view_state.select_source):
			item.select_toggled.connect(_view_state.select_source)

	# View intent (Hierarchy/Graph)
	if item.has_signal("view_requested") and is_instance_valid(_view_state):
		if not item.view_requested.is_connected(_view_state.change_view):
			item.view_requested.connect(_view_state.change_view)

	# Toggle intents - connect via wrapper to trace calls
	if item.has_signal("metaprompt_toggled") and is_instance_valid(_content_state):
		if not item.metaprompt_toggled.is_connected(_on_item_metaprompt_toggled_wrapper):
			item.metaprompt_toggled.connect(_on_item_metaprompt_toggled_wrapper)
	if item.has_signal("active_source_toggled") and is_instance_valid(_content_state):
		if not item.active_source_toggled.is_connected(_on_item_active_toggled_wrapper):
			item.active_source_toggled.connect(_on_item_active_toggled_wrapper)
	
	# --- Connect Delete Requested Signal ---
	if item.has_signal("delete_requested"):
		if not item.delete_requested.is_connected(_on_item_delete_requested):
			item.delete_requested.connect(_on_item_delete_requested)
			if DEBUG:
				print("ContentListView: Connected delete_requested for item %s" % source_id)
	else:
		push_warning("ContentListView: Item missing delete_requested signal!")
	# --- End Connect Delete Requested Signal ---
	
	# (Removed ContentBus toggle wiring)
	
	# Set up the item with extracted data
	if item.has_method("setup"):
		item.setup(source_id, source_name, source_path, is_metaprompt)
		if DEBUG:
			print("ContentListView: Item setup complete for %s" % source_id)
	else:
		push_error("ContentListView: Item missing setup method!")
		item.queue_free()
		return
	
	# Set initial selection state
	if item.select_check:
		item.select_check.set_block_signals(true)
		# Render true multi-selection from ViewStateResource.
		if is_instance_valid(_view_state):
			item.select_check.button_pressed = _view_state.is_source_selected(source_id)
		else:
			item.select_check.button_pressed = (source_id == _current_source_id)
		item.select_check.set_block_signals(false)
	
	if DEBUG:
		print("ContentListView: Successfully added item for %s" % source_id)

# --- Add Delete Request Handler ---
func _on_item_delete_requested(source_id: String) -> void:
	if DEBUG:
		print("ContentListView: Delete requested for source: %s" % source_id)
	
	# Create a confirmation dialog
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Confirm Deletion"
	confirm_dialog.dialog_text = "Are you sure you want to delete content source '%s'?\nThis will remove the source definition and its associated JSON file." % source_id
	confirm_dialog.ok_button_text = "Delete"
	confirm_dialog.cancel_button_text = "Cancel"
	
	# Connect signals
	confirm_dialog.confirmed.connect(_confirm_item_delete.bind(source_id, confirm_dialog))
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	
	# Add to scene and show
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()

# --- New method to handle confirmed deletion ---
func _confirm_item_delete(source_id: String, dialog: ConfirmationDialog) -> void:
	if DEBUG:
		print("ContentListView: Deletion confirmed for source: %s" % source_id)
	if is_instance_valid(_content_state):
		_content_state.delete_source(source_id)
	
	# Clear current selection if the deleted item was selected
	if _current_source_id == source_id:
		if DEBUG:
			print("ContentListView: Clearing current source ID as it was deleted.")
		_current_source_id = ""
		# Optionally notify ContentBus about the cleared selection if needed
		# ContentBus.set_selected_source("", false) 
		
	# Force a refresh of the list view AFTER requesting deletion
	call_deferred("refresh_sources")
	# Clean up the dialog
	dialog.queue_free()
# --- End New method --- 

func _on_source_updated(source_id: String) -> void:
	if DEBUG:
		print("ContentListView: Handling source_updated signal for %s" % source_id)
	if not is_instance_valid(_content_state):
		return

	# Get data using the fetched resource
	var source_data = _content_state.get_source_data(source_id)
	if source_data.is_empty():
		return
	
	# Update existing item
	for child in get_children():
		if child._source_id == source_id:
			var source_name = source_data.get("meta", {}).get("name", "Unnamed Source")
			var source_path = source_data.get("meta", {}).get("path", "")
			# Assuming ContentSourceItem.setup can handle potential metaprompt state
			# Fetch metaprompt state if necessary for setup
			var is_metaprompt = source_data.get("meta", {}).get("ai_context", {}).get("metaprompt", false)
			child.setup(source_id, source_name, source_path, is_metaprompt)
			break

func clear() -> void:
	for child in get_children():
		child.queue_free()

func _on_source_selected(source_id: String, selected: bool) -> void:
	# Reflect ViewStateResource selection set (multi-select).
	# IMPORTANT: `selected` may be false (deselect), so do not force it back on.
	if not is_instance_valid(_view_state):
		return
	_current_source_id = String(_view_state.current_source_id)
	for child in get_children():
		if child is ContentSourceItem and child.select_check:
			var is_selected := _view_state.is_source_selected(child._source_id)
			# Prevent feedback loop: programmatic toggle -> ContentSourceItem.select_toggled -> ViewStateResource -> back here
			child.select_check.set_block_signals(true)
			child.select_check.button_pressed = is_selected
			child.select_check.set_block_signals(false)

func refresh_sources() -> void:
	if DEBUG:
		print("\n=== ContentListView [%s]: REFRESHING SOURCES (Filters: %s) ===" % [get_instance_id(), str(_current_filters)])
	if not is_instance_valid(_content_state):
		push_warning("ContentListView [%s]: Cannot refresh, ContentStateResource not injected yet." % get_instance_id())
		return
	var content_state = _content_state
	
	# <<< Robust Clear >>>
	if DEBUG:
		print("ContentListView [%s]: Clearing existing items..." % get_instance_id())
	var children_to_remove = get_children()
	for child in children_to_remove:
		if DEBUG:
			print("  - Removing: %s" % child.name)
		remove_child(child)
		child.queue_free()
	if DEBUG:
		print("ContentListView [%s]: Finished clearing. Child count: %d" % [get_instance_id(), get_child_count()])
	# <<< End Robust Clear >>>
	
	# Use ContentStateResource methods (using the locally fetched 'content_state')
	var source_ids = content_state.get_source_ids() 
	if DEBUG:
		print("ContentListView [%s]: Found %d source IDs from Resource: %s" % [get_instance_id(), source_ids.size(), str(source_ids)])
	
	if source_ids.is_empty():
		# This is normal if called before sources are loaded
		if DEBUG:
			print("ContentListView: No sources found in ContentStateResource at this time.") 
		# Return early, no items to add
		return
	
	var added_count = 0
	for source_id in source_ids:
		if DEBUG:
			print("ContentListView: Processing source ID: %s" % source_id)
		var source_data = content_state.get_source_data(source_id) # Use local var
		
		if source_data.is_empty(): 
			push_warning("ContentListView: Skipping source '%s' - could not get source data from resource." % source_id)
			continue
		
		# --- Apply Filters ---
		if not _matches_filters(source_data):
			if DEBUG:
				print("ContentListView: Source '%s' skipped due to filters." % source_id)
			continue
		# --- End Apply Filters ---
		
		if DEBUG:
			print("ContentListView: Source data obtained for %s" % source_id)
		_add_source_item(source_id, source_data)
		added_count += 1
	
	if DEBUG:
		print("ContentListView [%s]: Refresh complete. Attempted to add %d items. Final child count: %d" % [get_instance_id(), added_count, get_child_count()])
	
	# Verify children
	for i in range(get_child_count()):
		var child = get_child(i)
		if DEBUG:
			print("ContentListView [%s]: Child %d: %s (%s)" % [get_instance_id(), i, child.name, child.get_path()])
	
	if DEBUG:
		print("=== REFRESH END ===\n")

# --- Add Filter Matching Logic ---
func _matches_filters(source_data: Dictionary) -> bool:
	# If no filters are active, show everything
	if _current_filters.is_empty():
		return true
		
	var meta = source_data.get("meta", {})
	var ai_context = meta.get("ai_context", {})
		
	for key in _current_filters:
		var filter_value = _current_filters[key]
		match key:
			"source_origin":
				var source_origin = meta.get("source_origin", "file").to_lower()
				if source_origin != filter_value:
					return false
			"source_type": # Key for file extension filtering
				if meta.get("source_type", "unknown").to_lower() != filter_value:
					return false
			"is_active":
				if ai_context.get("is_active", false) != filter_value:
					return false
			"is_metaprompt":
				if ai_context.get("metaprompt", false) != filter_value:
					return false
			_: # Ignore unknown filter keys
				pass
				
	# If all active filters match, return true
	return true
# --- End Filter Matching Logic ---

func _on_metaprompt_state_changed(source_id: String, is_metaprompt: bool) -> void:
	if not is_instance_valid(_content_state):
		return
	var content_state = _content_state

	# Skip if view is not visible
	if not visible:
		return
		
	# Skip if source_id is empty
	if source_id.is_empty():
		return
	
	var found_match = false
	var normalized_signal := content_state.get_normalized_id(source_id)
	if normalized_signal.is_empty():
		normalized_signal = source_id
	
	# First try direct match (normalized).
	for child in get_children():
		if child is ContentSourceItem:
			var normalized_item := content_state.get_normalized_id(child._source_id)
			if normalized_item.is_empty():
				normalized_item = child._source_id
			if normalized_item == normalized_signal:
				if child.has_method("update_metaprompt_state"):
					child.update_metaprompt_state(is_metaprompt)
				elif child.metaprompt_check:
					# Fallback: set directly (ContentSourceItem should still guard with _is_updating_metaprompt).
					child.metaprompt_check.button_pressed = is_metaprompt
				found_match = true
	
	# If still no match, check if this is a node belonging to a source.
	if not found_match:
		var parent_source_id := String(content_state.get_source_for_node(source_id)).strip_edges()
		if not parent_source_id.is_empty():
			var normalized_parent := content_state.get_normalized_id(parent_source_id)
			if normalized_parent.is_empty():
				normalized_parent = parent_source_id
			for child in get_children():
				if child is ContentSourceItem:
					var normalized_item2 := content_state.get_normalized_id(child._source_id)
					if normalized_item2.is_empty():
						normalized_item2 = child._source_id
					if normalized_item2 == normalized_parent:
						if child.has_method("update_metaprompt_state"):
							child.update_metaprompt_state(is_metaprompt)
						elif child.metaprompt_check:
							child.metaprompt_check.button_pressed = is_metaprompt
						found_match = true
	
	# If still no match found, log a diagnostic message
	if not found_match:
		pass

# Wrapper functions to trace toggle calls
func _on_item_metaprompt_toggled_wrapper(source_id: String, is_metaprompt: bool) -> void:
	if is_instance_valid(_content_state):
		_content_state.set_metaprompt_state(source_id, is_metaprompt)

func _on_item_active_toggled_wrapper(source_id: String, is_active: bool) -> void:
	if is_instance_valid(_content_state):
		_content_state.set_source_active_state(source_id, is_active)
