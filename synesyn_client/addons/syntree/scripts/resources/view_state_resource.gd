## Purpose: ViewStateResource (script)
@tool
extends Resource
class_name ViewStateResource

# View mode enum
enum ViewMode {
	LIST = 0,
	HIERARCHY = 1,
	GRAPH = 2
}

# Current view state
@export var current_mode: ViewMode = ViewMode.LIST
@export var current_source_id: String = ""
@export var selected_source_ids: Array[String] = []
@export var current_thread_id: String = "default"

# Dev Agent safety state (armed/disarmed)
# This is intentionally part of the persisted view-state resource so the UI can
# remember the setting per-project, while still defaulting to false for new projects.
@export var dev_agent_enabled: bool = false

# View history to support back navigation
@export var view_history: Array[Dictionary] = []

signal view_state_changed  # Renamed from 'changed' to avoid conflict
signal source_selected(source_id: String, selected: bool)
signal dev_agent_enabled_changed(enabled: bool)

func _init() -> void:
	# Connect to our view_state_changed signal to emit the built-in changed signal
	self.view_state_changed.connect(func(): emit_changed())

func set_dev_agent_enabled(enabled: bool) -> void:
	var desired := bool(enabled)
	if dev_agent_enabled == desired:
		return
	dev_agent_enabled = desired
	dev_agent_enabled_changed.emit(desired)
	view_state_changed.emit()

func is_dev_agent_enabled() -> bool:
	return bool(dev_agent_enabled)

# View changing
func change_view(mode: ViewMode, source_id: String = "") -> void:
	"""
	Change the current view mode and source ID
	Adds the current state to history for back navigation
	"""
	print("ViewStateResource: Changing view from %d to %d with source: %s" % [current_mode, mode, source_id])
	
	# Store old state for comparison
	var old_mode = current_mode
	var old_source_id = current_source_id
	
	# If mode and source are the same, do nothing
	if mode == old_mode and source_id == old_source_id:
		return
		
	# Add current state to history if valid
	var current_state = {
		"mode": old_mode,
		"source_id": old_source_id
	}
	
	if not old_source_id.is_empty():
		view_history.append(current_state)
		
	# Update current state
	current_mode = mode
	
	# Handle source selection - DON'T deselect the old source anymore
	if not source_id.is_empty():
		# Just update the current source ID to the new one
		current_source_id = source_id
		
		# Make sure the new source is in the selected list
		if not selected_source_ids.has(source_id):
			selected_source_ids.append(source_id)
			source_selected.emit(source_id, true)
	
	print("ViewStateResource: View changed - mode: %d, source: %s, selections: %s" % 
		[current_mode, current_source_id, selected_source_ids])
	
	# Emit view state changed signal
	view_state_changed.emit()

func go_back() -> bool:
	"""
	Navigate back to the previous view state
	Returns true if successful, false if no history
	"""
	if view_history.is_empty():
		return false
		
	var previous_state = view_history.pop_back()
	current_mode = previous_state.mode
	current_source_id = previous_state.source_id
	
	view_state_changed.emit()
	return true

# Source selection
func select_source(source_id: String, selected: bool) -> void:
	"""
	Select or deselect a source without clearing existing selections
	"""
	print("ViewStateResource: Selecting source %s to %s" % [source_id, str(selected)])
	
	var changed := false
	# Handle selection
	if selected:
		# Add to selected sources if not already there
		if not source_id in selected_source_ids:
			selected_source_ids.append(source_id)
			changed = true
		
		# Always update current source ID to the last selected source
		if current_source_id != source_id:
			current_source_id = source_id
			changed = true
	else:
		# Remove from selections if deselected
		if selected_source_ids.has(source_id):
			selected_source_ids.erase(source_id)
			changed = true
		
		# If we're deselecting the current source, find another one or clear
		if current_source_id == source_id:
			# If there are other selections, use the most recent one
			if not selected_source_ids.is_empty():
				var next_id := selected_source_ids[-1]
				if current_source_id != next_id:
					current_source_id = next_id
					changed = true
			else:
				if not current_source_id.is_empty():
					current_source_id = ""
					changed = true
	
	print("ViewStateResource: Selected sources: %s, Current ID: %s" % [str(selected_source_ids), current_source_id])
	# Only emit when something actually changed; node selection can spam this otherwise.
	if changed:
		source_selected.emit(source_id, selected)
		view_state_changed.emit()

func set_source_selected_no_change_current(source_id: String, selected: bool) -> void:
	"""
	Select/deselect a source WITHOUT changing current_source_id.
	This is critical for stack hierarchy view: selecting a member source should not collapse the view.
	"""
	print("ViewStateResource: set_source_selected_no_change_current %s to %s" % [source_id, str(selected)])
	var changed := false
	if selected:
		if not selected_source_ids.has(source_id):
			selected_source_ids.append(source_id)
			changed = true
	else:
		if selected_source_ids.has(source_id):
			selected_source_ids.erase(source_id)
			changed = true
	# Do not touch current_source_id.
	if changed:
		source_selected.emit(source_id, selected)
		view_state_changed.emit()

func is_source_selected(source_id: String) -> bool:
	"""
	Check if a source is selected
	"""
	return source_id in selected_source_ids

func clear_selection() -> void:
	"""
	Clear all selections
	"""
	selected_source_ids.clear()
	current_source_id = ""
	
	view_state_changed.emit()

func set_all_sources_selected(available_ids: Array[String], selected: bool) -> void:
	"""
	Bulk select/deselect sources.

	- When `selected == true`, selects every id in `available_ids` (and removes any stale ids).
	- When `selected == false`, clears selection.

	Emits `view_state_changed` once (no per-item spam).
	"""
	var changed := false
	var ids: Array[String] = []
	for sid in available_ids:
		var s := String(sid).strip_edges()
		if s.is_empty():
			continue
		ids.append(s)

	if selected:
		# Normalize selection to exactly the available ids.
		# Keep current_source_id if possible; otherwise use the last id.
		if selected_source_ids != ids:
			selected_source_ids = ids
			changed = true
		if current_source_id.is_empty() or not selected_source_ids.has(current_source_id):
			var next_id := selected_source_ids[-1] if not selected_source_ids.is_empty() else ""
			if current_source_id != next_id:
				current_source_id = next_id
				changed = true
	else:
		if not selected_source_ids.is_empty() or not current_source_id.is_empty():
			selected_source_ids.clear()
			current_source_id = ""
			changed = true

	if changed:
		view_state_changed.emit()

# --- NEW: Sync selections with actually available sources --- 
func sync_selections_with_available(available_ids: Array) -> void:
	print("ViewStateResource: Syncing selections with available sources...")
	var changed = false
	var available_set := {} # Use Dict as Set for faster lookup
	for id in available_ids:
		available_set[id] = true
	
	var valid_selections: Array[String] = [] # Explicitly type as Array[String]
	for selected_id in selected_source_ids:
		if available_set.has(selected_id):
			valid_selections.append(selected_id)
		else:
			print("  - Removing stale selection: %s" % selected_id)
			changed = true
	
	# Update the selection list
	selected_source_ids = valid_selections
	
	# Verify current_source_id is still valid
	if not current_source_id.is_empty() and not available_set.has(current_source_id):
		print("  - Current source ID '%s' is stale. Updating..." % current_source_id)
		# If we still have valid selections, pick the last one
		if not selected_source_ids.is_empty():
			current_source_id = selected_source_ids[-1]
		else:
			current_source_id = ""
		changed = true
		
	if changed:
		print("ViewStateResource: Sync complete. Current source: %s, Selected: %s" % 
			[current_source_id, str(selected_source_ids)])
		view_state_changed.emit()
	else:
		print("ViewStateResource: Sync complete. No changes needed.")
# --- END NEW SYNC METHOD ---

# History management
func add_to_history(mode: ViewMode, source_id: String) -> void:
	"""
	Add a state to the view history
	"""
	view_history.append({
		"mode": mode,
		"source_id": source_id
	})
	
	view_state_changed.emit()

func clear_history() -> void:
	"""
	Clear the view history
	"""
	view_history.clear()
	view_state_changed.emit()

# Getters
func get_current_mode() -> ViewMode:
	return current_mode

func get_current_source_id() -> String:
	return current_source_id

func get_current_thread_id() -> String:
	return current_thread_id if not current_thread_id.is_empty() else "default"

# Setter for current thread
func set_current_thread_id(new_thread_id: String) -> void:
	var thread_id_to_set = new_thread_id
	if thread_id_to_set.is_empty():
		push_warning("ViewStateResource: Attempted to set empty thread ID, defaulting to 'default'.")
		thread_id_to_set = "default"
	
	if current_thread_id != thread_id_to_set:
		current_thread_id = thread_id_to_set
		print("ViewStateResource: Current thread set to: ", current_thread_id)
		view_state_changed.emit() # Emit signal on change 
