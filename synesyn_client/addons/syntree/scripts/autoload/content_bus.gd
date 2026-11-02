## Purpose: autoload/content_bus.gd
@tool
extends Node

# Load resource scripts directly
const _SyntreeResourcesScript = preload("res://addons/syntree/scripts/resources/syntree_resources.gd")

# Preload resource implementations
const ContentSourceResource = preload("res://addons/syntree/scripts/resources/content_source_resource.gd")
const ContentStateResource = preload("res://addons/syntree/scripts/resources/content_state_resource.gd")
const ViewStateResource = preload("res://addons/syntree/scripts/resources/view_state_resource.gd")
const GraphStateResource = preload("res://addons/syntree/scripts/resources/graph_state_resource.gd")

# Internal helpers
const _PersistenceSchedulerScript = preload("res://addons/syntree/scripts/autoload/internal/content_bus_persistence_scheduler.gd")
const _UrlLoaderScript = preload("res://addons/syntree/scripts/autoload/internal/content_bus_url_loader.gd")

# Define view mode enum
enum ViewMode {
	LIST = 0,
	HIERARCHY = 1,
	GRAPH = 2
}

# Define transition state enum
enum TransitionState {
	NONE = 0,
	IN_PROGRESS = 1
}

# Feature flag for new resource-based architecture
const USE_RESOURCE_ARCHITECTURE = true

# Resource references - Now specifically SyntreeResources
var _resources: SyntreeResources # Changed base type to specific type
const RESOURCES_PATH = "res://addons/syntree/resources/syntree_resources.tres" # bundled seed (read-only in packaged builds)

var _persist_scheduler: Node = null
var _url_loader: Node = null

# Signals
signal source_selected(source_id: String, selected: bool)
signal source_loaded(source_id: String)
signal sources_initialized
signal all_sources_loaded
signal initialization_completed()
signal operation_failed(operation: String, error: String, details: String)
signal view_state_entered(from_mode: int, to_mode: int, source_id: String)
signal view_state_transition_started(from_mode: int, to_mode: int, source_id: String)
signal view_state_transition_completed(from_mode: int, to_mode: int, source_id: String)
signal ui_state_changed(mode: int, show_content_list: bool)
signal view_mode_changed(old_mode: int, new_mode: int, source_id: String)
signal sources_refreshed(result: Dictionary)
signal dev_agent_enabled_changed(enabled: bool)

# Additional signals
signal panel_ready(panel: Node)
signal hierarchy_mode_changed(enabled: bool)
signal hierarchy_requested(source_id: String)
signal hierarchy_view_changed(source_name: String, is_hierarchy: bool)
signal hierarchy_data_ready(hierarchy_data: Dictionary)

signal graph_requested(source_id: String)

# --- NEW Signal for remote completion ---
signal remote_source_processed(source_id: String)
# --- END NEW Signal ---

signal source_deselected(source_id: String)
signal source_deleted(source_name: String)
signal source_added(source_data: Dictionary)
signal source_updated(source_data: Dictionary)
signal content_loaded(source_name: String)
signal content_cleared(source_name: String)
signal content_error(source_name: String, error: String)
signal error_occurred(title: String, message: String, details: String)

# State tracking
var _current_view_mode: ViewMode = ViewMode.LIST
var _current_source_id: String = ""
var _transition_state: TransitionState = TransitionState.NONE
var _is_ready := false

# Public access to current source ID - DELEGATE to resource
var current_source_id: String:
	get: 
		if _resources and is_instance_valid(_resources.view_state):
			return _resources.view_state.get_current_source_id()
		push_warning("ContentBus: Cannot get current_source_id, ViewStateResource not ready.")
		return ""
	# No setter needed if ViewStateResource manages it

var current_view_mode: ViewMode:
	get:
		if _resources and is_instance_valid(_resources.view_state):
			# Ensure correct enum mapping if ViewStateResource uses its own enum
			return ViewMode.values()[int(_resources.view_state.get_current_mode())] 
		push_warning("ContentBus: Cannot get current_view_mode, ViewStateResource not ready.")
		return ViewMode.LIST # Default

# Debug tracking
var _view_change_calls := 0
var _max_view_changes := 10
var _last_view_change_time := 0.0
var _is_processing_view_change := false
var _current_transition_id := 0
var _transition_history := []
var _source_history_per_view := {
	ViewMode.LIST: [],
	ViewMode.HIERARCHY: [], 
	ViewMode.GRAPH: []
}
var _last_view_per_source := {}

# Reference to NotificationManager
var _notification_manager: Node


# REMOVE DEPRECATED getters
# var _sources: Dictionary:
# var node_to_source_map: Dictionary:

# Add the view_changed signal to ContentBus.gd if not already present
signal view_changed(old_mode: int, new_mode: int, source_id: String)

signal metaprompt_state_changed(source_id: String, is_metaprompt: bool)
signal active_state_changed(source_id: String, is_active: bool)

# Add guard against recursion in metaprompt handling
var _is_processing_metaprompt_update := false
var _is_processing_active_update := false

# Signals
signal resources_ready

func register_notification_manager(manager: Node) -> void:
	print("ContentBus: Registering notification manager")
	if not manager:
		push_warning("ContentBus: Cannot register null notification manager")
		return
		
	_notification_manager = manager
	print("ContentBus: Notification manager registered successfully")

func _init() -> void:
	print("ContentBus: Initializing...")
	
	# Load or create the main SyntreeResources file
	_init_resources()
	
	# DO NOT wait for ContentModel ready signal
	
	# Connect signals from the LOADED resource
	_connect_resource_signals()

	# Editor-only persistence scheduling (debounced).
	_ensure_persist_scheduler()
	# Remote URL loading orchestration.
	_ensure_url_loader()

func _ready() -> void:
	print("ContentBus: Ready called")
	_is_ready = true
	
	# Get NotificationManager reference
	_notification_manager = get_node_or_null("/root/NotificationManager")
	if not _notification_manager:
		push_warning("ContentBus: NotificationManager not found, falling back to direct error signals")
	
	# Emit ready signal AFTER resources are loaded in _init
	if is_instance_valid(_resources):
		print("ContentBus: Resources already loaded in _init. Emitting resources_ready.")
		resources_ready.emit()
		initialization_completed.emit()
	else:
		push_warning("ContentBus: _resources not valid in _ready. Waiting for _init_resources completion signal?")

func _init_resources() -> void:
	print("ContentBus: Initializing/Loading SyntreeResources from: %s" % RESOURCES_PATH)
	
	# <<< TESTING: Always create NEW resources >>>
	# print("ContentBus (TEST): Always creating NEW SyntreeResources instance.")
	# _resources = _SyntreeResourcesScript.new()
	# # Ensure nested resources are definitely created
	# if not is_instance_valid(_resources.content_state): _resources.content_state = ContentStateResource.new()
	# if not is_instance_valid(_resources.content_state.content_source): _resources.content_state.content_source = ContentSourceResource.new()
	# if not is_instance_valid(_resources.view_state): _resources.view_state = ViewStateResource.new()
	# if not is_instance_valid(_resources.graph_state): _resources.graph_state = GraphStateResource.new()
	# _save_resources() # Save the newly created one
	# <<< END TESTING BLOCK >>>

	# --- Load logic ---
	# 1. Prefer Documents/Synesyn (migrate legacy user:// once).
	# 2. Fall back to bundled res:// seed.
	# 3. If neither exists, create a fresh resource and save under Documents.
	var resources_path: String = _resources_persist_path()
	var load_path: String = ""
	if FileAccess.file_exists(resources_path):
		load_path = resources_path
	elif FileAccess.file_exists(RESOURCES_PATH):
		load_path = RESOURCES_PATH
		print("ContentBus: No user state found; seeding from bundled resource: %s" % RESOURCES_PATH)

	if not load_path.is_empty():
		_resources = ResourceLoader.load(load_path, "SyntreeResources")
		if is_instance_valid(_resources):
			print("ContentBus: Loaded SyntreeResources from %s." % load_path)
			# Validate nested resources.
			if not is_instance_valid(_resources.content_state):
				push_warning("ContentBus: Loaded _resources missing valid content_state. Recreating.")
				_resources = _SyntreeResourcesScript.new()
				_save_resources()
			elif not is_instance_valid(_resources.content_state.content_source):
				push_warning("ContentBus: Loaded content_state missing valid content_source. Recreating.")
				_resources = _SyntreeResourcesScript.new()
				_save_resources()
			elif load_path == RESOURCES_PATH:
				# Seeded from bundled resource: persist under Documents immediately.
				_save_resources()
		else:
			push_error("ContentBus: Failed to load SyntreeResources from %s (returned null/invalid). Creating new." % load_path)
			_resources = _SyntreeResourcesScript.new()
			_save_resources()
	else:
		print("ContentBus: No SyntreeResources file found. Creating new.")
		_resources = _SyntreeResourcesScript.new()
		_save_resources()
	# --- End load logic ---

	# Ensure the resource reference is set for other functions
	if not is_instance_valid(_resources):
		push_error("ContentBus: CRITICAL - Failed to load or create _resources!")
		return

	print("ContentBus: SyntreeResources instance is ready (Instance ID: %s)." % _resources.get_instance_id())

func _resources_persist_path() -> String:
	var dest: String = RuntimeConfig.get_syntree_resources_path()
	RuntimeConfig.migrate_binary_file_if_needed(dest, ["user://syntree_resources.tres"])
	return dest


func _save_resources() -> void:
	if not is_instance_valid(_resources):
		push_error("ContentBus: Cannot save invalid _resources!")
		return
	# Ensure nested resources are valid before saving container
	if not is_instance_valid(_resources.content_state): _resources.content_state = ContentStateResource.new()
	if not is_instance_valid(_resources.content_state.content_source): _resources.content_state.content_source = ContentSourceResource.new()
	if not is_instance_valid(_resources.view_state): _resources.view_state = ViewStateResource.new()
	if not is_instance_valid(_resources.graph_state): _resources.graph_state = GraphStateResource.new()

	# Always save under Documents/Synesyn; never to res:// (read-only in packaged installs).
	var persist_path: String = _resources_persist_path()
	DirAccess.make_dir_recursive_absolute(persist_path.get_base_dir())
	var save_err: int = ResourceSaver.save(_resources, persist_path)
	if save_err == OK:
		print("ContentBus: Saved SyntreeResources to: %s" % persist_path)
	else:
		push_error("ContentBus: Failed to save SyntreeResources (%s). State will not persist." % str(save_err))

func _connect_resource_signals() -> void:
	if not is_instance_valid(_resources) or not _resources.is_initialized():
		push_warning("ContentBus: Cannot connect resource signals - _resources invalid or not initialized.")
		return
		
	print("ContentBus: Connecting resource signals...")
	
	# Connect View State signals
	if is_instance_valid(_resources.view_state) and _resources.view_state.has_signal("view_state_changed"):
		var callable_on_view_state = Callable(self, "_on_view_state_changed")
		if not _resources.view_state.view_state_changed.is_connected(callable_on_view_state):
			_resources.view_state.view_state_changed.connect(callable_on_view_state)
	else:
		push_warning("ContentBus: Could not connect to view_state.view_state_changed")

	# Relay Dev Agent toggle changes (persisted in ViewStateResource)
	if is_instance_valid(_resources.view_state) and _resources.view_state.has_signal("dev_agent_enabled_changed"):
		var callable_dev_agent := Callable(self, "_on_resource_dev_agent_enabled_changed")
		if not _resources.view_state.dev_agent_enabled_changed.is_connected(callable_dev_agent):
			_resources.view_state.dev_agent_enabled_changed.connect(callable_dev_agent)
	
	# Connect Content State signals using intermediate handlers
	if is_instance_valid(_resources.content_state):
		# --- source_added -> source_loaded --- 
		if self.has_signal("source_loaded") and _resources.content_state.has_signal("source_added"):
			var callable_added = Callable(self, "_on_resource_source_added")
			# Check connection first
			if not _resources.content_state.source_added.is_connected(callable_added):
				_resources.content_state.source_added.connect(callable_added)
			
		# --- source_deleted -> source_deleted --- 
		if self.has_signal("source_deleted") and _resources.content_state.has_signal("source_deleted"):
			var callable_deleted = Callable(self, "_on_resource_source_deleted")
			if not _resources.content_state.source_deleted.is_connected(callable_deleted):
				_resources.content_state.source_deleted.connect(callable_deleted)
			
		# --- source_updated -> source_updated --- 
		if self.has_signal("source_updated") and _resources.content_state.has_signal("source_updated"):
			var callable_updated = Callable(self, "_on_resource_source_updated")
			if not _resources.content_state.source_updated.is_connected(callable_updated):
				_resources.content_state.source_updated.connect(callable_updated)
				
		# --- metaprompt_state_changed -> metaprompt_state_changed --- 
		if self.has_signal("metaprompt_state_changed") and _resources.content_state.has_signal("metaprompt_state_changed"): 
			var callable_meta = Callable(self, "_on_resource_metaprompt_changed")
			if not _resources.content_state.metaprompt_state_changed.is_connected(callable_meta):
				_resources.content_state.metaprompt_state_changed.connect(callable_meta)

		# --- active_state_changed -> active_state_changed ---
		# This keeps UI in sync when active state changes due to load/refresh or non-UI mutations.
		if self.has_signal("active_state_changed") and _resources.content_state.has_signal("active_state_changed"):
			var callable_active = Callable(self, "_on_active_state_changed")
			if not _resources.content_state.active_state_changed.is_connected(callable_active):
				_resources.content_state.active_state_changed.connect(callable_active)
	else:
		push_warning("ContentBus: _resources.content_state is not valid, cannot connect its signals.")
		
	print("ContentBus: Resource signals connection attempt complete.")

# --- Intermediate Signal Handlers for Relaying --- 
func _on_resource_source_added(source_id: String) -> void:
	print("ContentBus Relay: source_added -> emitting source_loaded(%s)" % source_id)
	source_loaded.emit(source_id)

func _on_resource_source_deleted(source_id: String) -> void:
	print("ContentBus Relay: source_deleted -> emitting source_deleted(%s)" % source_id)
	source_deleted.emit(source_id)

func _on_resource_source_updated(source_id: String) -> void:
	print("ContentBus Relay: source_updated -> emitting source_updated(%s)" % source_id)
	# The ContentListView handler _on_source_updated expects the source_id (String)
	# Emit the source_id directly, not the data dictionary
	source_updated.emit(source_id)
	# Persist changes to the resource container so project reload retains edits (e.g. hierarchy reorder).
	_schedule_persist_resources()
	# if is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
	# 	 var data = _resources.content_state.get_source_data(source_id)
	# 	 source_updated.emit(data) # Assuming this signature matches
	# else:
	# 	 push_error("ContentBus Relay: Cannot relay source_updated, resource invalid")

func _on_resource_metaprompt_changed(source_id: String, is_metaprompt: bool) -> void:
	print("ContentBus Relay: metaprompt_state_changed -> emitting metaprompt_state_changed(%s, %s)" % [source_id, str(is_metaprompt)])
	metaprompt_state_changed.emit(source_id, is_metaprompt)
	# Persist changes so project reload retains toggle state even if no view_state change occurs.
	_schedule_persist_resources()
# --- End Intermediate Handlers --- 

# Handle view state changes from resource
func _on_view_state_changed() -> void:
	if not _resources or not _resources.is_initialized():
		return
		
	var view_state = _resources.view_state
	
	# Update ContentBus internal state to match resource
	var old_mode = _current_view_mode
	# Convert the enum value to an integer first, then to our local enum
	var resource_mode_value = int(view_state.current_mode)
	_current_view_mode = ViewMode.values()[resource_mode_value]
	_current_source_id = view_state.current_source_id
	
	# Emit signals to maintain compatibility
	if old_mode != _current_view_mode:
		view_changed.emit(old_mode, _current_view_mode, _current_source_id)
		view_mode_changed.emit(old_mode, _current_view_mode, _current_source_id)
		view_state_entered.emit(old_mode, _current_view_mode, _current_source_id)

	# Persist view state changes (thread selection, current source, etc.) for project reload.
	# Debounced to avoid writing on every small UI event.
	_schedule_persist_resources()

func _on_resource_dev_agent_enabled_changed(enabled: bool) -> void:
	# Single source of truth is ViewStateResource; ContentBus just relays + persists.
	dev_agent_enabled_changed.emit(bool(enabled))
	_schedule_persist_resources()

func _ensure_persist_scheduler() -> void:
	if is_instance_valid(_persist_scheduler):
		return
	_persist_scheduler = _PersistenceSchedulerScript.new()
	_persist_scheduler.name = "ContentBusPersistenceScheduler"
	add_child(_persist_scheduler)
	if _persist_scheduler.has_method("setup"):
		_persist_scheduler.call("setup", Callable(self, "_save_resources"), 0.25)

func _ensure_url_loader() -> void:
	if is_instance_valid(_url_loader):
		return
	_url_loader = _UrlLoaderScript.new()
	_url_loader.name = "ContentBusUrlLoader"
	add_child(_url_loader)
	if _url_loader.has_method("setup"):
		_url_loader.call(
			"setup",
			Callable(self, "get_content_state_resource"),
			Callable(self, "handle_operation_failed"),
			Callable(self, "_emit_remote_source_processed")
		)

func _schedule_persist_resources() -> void:
	# Only persist automatically in the editor; in exported builds `res://` is not writable.
	if not Engine.is_editor_hint():
		return
	_ensure_persist_scheduler()
	if is_instance_valid(_persist_scheduler) and _persist_scheduler.has_method("request_persist"):
		_persist_scheduler.call("request_persist")

# Centralized error handling methods
func show_error(title: String, message: String, details: String = "") -> void:
	if _notification_manager and _notification_manager.has_method("show_error"):
		_notification_manager.show_error(title, message, details)
	else:
		error_occurred.emit(title, message, details)
		push_error("[ContentBus] %s: %s\n%s" % [title, message, details])

func show_warning(title: String, message: String) -> void:
	if _notification_manager and _notification_manager.has_method("show_warning"):
		_notification_manager.show_warning(title, message)
	else:
		push_warning("[ContentBus] %s: %s" % [title, message])

func handle_operation_failed(operation: String, error: String, details: String = "") -> void:
	operation_failed.emit(operation, error, details)
	show_error("Operation Failed: " + operation, error, details)

# View state management methods
func get_current_view_mode() -> ViewMode:
	if USE_RESOURCE_ARCHITECTURE and _resources and _resources.is_initialized():
		# Convert ViewStateResource.ViewMode back to our ViewMode using the integer value
		return ViewMode.values()[_resources.view_state.current_mode]
	return _current_view_mode

func get_current_source_id() -> String:
	if USE_RESOURCE_ARCHITECTURE and _resources and _resources.is_initialized():
		return _resources.view_state.get_current_source_id()
	return _current_source_id

func _is_valid_transition(from_mode: ViewMode, to_mode: ViewMode) -> bool:
	if not VALID_TRANSITIONS.has(from_mode):
		show_warning("Invalid Transition", "Cannot transition from invalid view mode")
		return false
	return to_mode in VALID_TRANSITIONS[from_mode]

# Source selection handling
func set_selected_source(source_id: String, selected: bool) -> void:
	print("ContentBus: Setting selected source: " + source_id + " to " + str(selected))
	
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.view_state):
		_resources.view_state.select_source(source_id, selected)
	else:
		push_error("ContentBus: Cannot set selected source - resource architecture not ready.")

# View state transition request
func request_view_change(mode: int, source_id: String = "") -> void:
	"""
	Request a change in view mode and optionally set a new source ID
	"""
	var old_mode = _current_view_mode
	# Use the provided source_id if not empty, otherwise stick with the currently tracked one
	var effective_source_id = source_id if not source_id.is_empty() else get_current_source_id() # Use getter
	
	# Validate source ID for hierarchy and graph views
	if (mode == ViewMode.HIERARCHY or mode == ViewMode.GRAPH) and effective_source_id.is_empty():
		push_warning("ContentBus: Cannot switch to HIERARCHY/GRAPH view without a source ID")
		return
	
	print("ContentBus: Requesting view change from %d to %d (source: %s)" % [old_mode, mode, effective_source_id]) # Updated log
	
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.view_state):
		# Ensure source data exists in the resource before changing view?
		# Skip this check if we are transitioning TO the list view, 
		# as the source might have just been deleted.
		if mode != ViewMode.LIST and not effective_source_id.is_empty():
			if not has_source(effective_source_id): # Check using the resource via has_source
				push_warning("ContentBus: Source data not found in resource for ID: %s" % effective_source_id)
				# Return early only if NOT going to list view? Maybe allow ViewStateResource to handle?
				# Consider if returning here is correct. If ViewStateResource handles it gracefully,
				# we might not need to return.
				# return 
		
		# Use the integer value of the mode instead of trying to convert enum types
		print("ContentBus: Delegating view change to ViewStateResource.") # Added log
		_resources.view_state.change_view(mode, effective_source_id)
	
	print("ContentBus: View change request processed (delegated to resource)." ) # Modified log

# State check
func is_ready() -> bool:
	return _is_ready and is_instance_valid(_resources)

# Resource access 
func get_resources() -> Resource:
	"""
	Returns the SyntreeResources instance
	"""
	return _resources

# Metaprompt state handling
func on_metaprompt_toggled(source_id: String, is_metaprompt: bool) -> void:
	if _is_processing_metaprompt_update:
		return
	
	_is_processing_metaprompt_update = true
	
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		_resources.content_state.set_metaprompt_state(source_id, is_metaprompt)
	else:
		push_error("ContentBus.on_metaprompt_toggled: Resource architecture not ready.")
	
	_is_processing_metaprompt_update = false

func set_source_metaprompt(source_id: String, is_metaprompt: bool) -> void:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		_resources.content_state.set_metaprompt_state(source_id, is_metaprompt)
	else:
		push_error("ContentBus.set_source_metaprompt: Resource architecture not ready.")

# Generic content data access methods with architecture selection
func get_source_data(any_id: String) -> Dictionary:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		return _resources.content_state.get_source_data(any_id)
	else:
		push_error("ContentBus.get_source_data: Resource architecture not ready.")
		return {}

func get_source_for_node(node_id: String) -> String:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		return _resources.content_state.get_source_for_node(node_id)
	else:
		push_error("ContentBus.get_source_for_node: Resource architecture not ready.")
		return ""

func has_source(source_id: String) -> bool:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		var normalized_id = _resources.content_state.get_normalized_id(source_id)
		# Need to access the nested resource's sources dictionary
		if is_instance_valid(_resources.content_state.content_source):
			return _resources.content_state.content_source.sources.has(normalized_id)
		else:
			push_error("ContentBus.has_source: Nested ContentSourceResource is invalid.")
			return false
	else:
		push_error("ContentBus.has_source: Resource architecture not ready.")
		return false

func get_source_ids() -> Array:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		if is_instance_valid(_resources.content_state.content_source):
			return _resources.content_state.content_source.sources.keys()
		else:
			push_error("ContentBus.get_source_ids: Nested ContentSourceResource is invalid.")
			return []
	else:
		push_error("ContentBus.get_source_ids: Resource architecture not ready.")
		return []

# Convenience methods that delegate to appropriate resource or legacy model
# These need to be here for backward compatibility
func load_source(path: String) -> Error:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		var source_id = _resources.content_state.load_source_from_file(path)
		return OK if not source_id.is_empty() else ERR_FILE_CANT_READ
	else:
		push_error("ContentBus.load_source: Resource architecture not ready.")
		return ERR_UNCONFIGURED

func save_source(source_id: String) -> Error:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		return OK if _resources.content_state.save_source(source_id) else ERR_FILE_CANT_WRITE
	else:
		push_error("ContentBus.save_source: Resource architecture not ready.")
		return ERR_UNCONFIGURED

func update_source(source_id: String, data: Dictionary) -> Error:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		return OK if _resources.content_state.update_source(source_id, data) else ERR_INVALID_DATA
	else:
		push_error("ContentBus.update_source: Resource architecture not ready.")
		return ERR_UNCONFIGURED

func delete_source(source_id: String) -> Error:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		return OK if _resources.content_state.delete_source(source_id) else ERR_DOES_NOT_EXIST
	else:
		push_error("ContentBus.delete_source: Resource architecture not ready.")
		return ERR_UNCONFIGURED

func get_source_nodes(source_id: String) -> Array:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		var source_data = _resources.content_state.get_source_data(source_id)
		return source_data.get("content", {}).get("nodes", [])
	else:
		push_error("ContentBus.get_source_nodes: Resource architecture not ready.")
		return []

func register_node_source_relationship(node_id: String, source_id: String) -> void:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		_resources.content_state.register_node_source_relationship(node_id, source_id)
	else:
		push_error("ContentBus.register_node_source_relationship: Resource architecture not ready.")

func get_normalized_id(any_id: String) -> String:
	if USE_RESOURCE_ARCHITECTURE and is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		return _resources.content_state.get_normalized_id(any_id)
	else:
		push_error("ContentBus.get_normalized_id: Resource architecture not ready.")
		return any_id # Fallback?

# Other ContentBus methods...

# Transition validation table
const VALID_TRANSITIONS := {
	ViewMode.LIST: [ViewMode.HIERARCHY, ViewMode.GRAPH, ViewMode.LIST],  # Allow transition to self for initial state
	ViewMode.HIERARCHY: [ViewMode.LIST, ViewMode.GRAPH, ViewMode.HIERARCHY],  # Allow self-transition for refresh
	ViewMode.GRAPH: [ViewMode.HIERARCHY, ViewMode.LIST, ViewMode.GRAPH]  # Allow self-transition for refresh
}

func set_current_view_mode(mode: ViewMode) -> void:
	"""
	Sets the current view mode directly
	This is used by ViewManager to update the view mode
	"""
	var old_mode = _current_view_mode
	_current_view_mode = mode
	
	if USE_RESOURCE_ARCHITECTURE and _resources and _resources.is_initialized():
		# Convert our ViewMode to ViewStateResource.ViewMode using the integer value
		_resources.view_state.current_mode = ViewStateResource.ViewMode.values()[mode]
		
	# Emit signals to maintain compatibility
	if old_mode != mode:
		view_changed.emit(old_mode, mode, _current_source_id)
		view_mode_changed.emit(old_mode, mode, _current_source_id)
		view_state_entered.emit(old_mode, mode, _current_source_id)

func set_current_source_silently(source_id: String) -> void:
	"""
	Sets the current source ID without emitting signals
	This is used by ViewManager to update the source ID without triggering view changes
	"""
	_current_source_id = source_id
	
	if USE_RESOURCE_ARCHITECTURE and _resources and _resources.is_initialized():
		_resources.view_state.current_source_id = source_id

"""
COMPONENT: ContentBus
RESPONSIBILITY: Central event bus for cross-component communication
PUBLIC API:
  - Signals:
	- source_selected(source_id, selected)
	- view_mode_changed(old_mode, new_mode, source_id)
	- source_loaded(source_id)
	- all_sources_loaded
  - Methods:
	- get_current_view_mode(): Returns current view mode
	- set_current_view_mode(mode): Changes view mode
	- get_current_source_id(): Returns ID of selected source
	- get_source_data(source_id): Returns data for specified source
	- request_view_change(mode, source_id): Request view change
DEPENDENCIES:
  - None (Autoload/Singleton)
"""

# --- NEW Getters for Resources --- 
func get_syntree_resources() -> SyntreeResources:
	# Should ideally wait until _is_ready? Or handle potential null
	if not is_instance_valid(_resources):
		push_warning("ContentBus: get_syntree_resources called before _resources is valid.")
	return _resources

func get_content_state_resource() -> ContentStateResource:
	# REMOVED 강제 리로드: _resources = ResourceLoader.load(RESOURCES_PATH, "SyntreeResources", ResourceLoader.CACHE_MODE_IGNORE)
	
	var resource_to_return = null
	if is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
		resource_to_return = _resources.content_state
	
	var validity_check = is_instance_valid(resource_to_return)
	print("ContentBus: get_content_state_resource() - Returning resource. Is valid: %s" % str(validity_check))
	if not validity_check:
		push_warning("ContentBus: get_content_state_resource called but resource is invalid.")
		
	return resource_to_return

# This getter is likely not needed externally if ContentStateResource provides the API
# func get_content_data_resource() -> ContentDataResource:
# 	 if is_instance_valid(_resources) and is_instance_valid(_resources.content_state):
# 		 return _resources.content_state.content_source 
# 	 return null

func get_view_state_resource() -> ViewStateResource:
	# REMOVED 강제 리로드: _resources = ResourceLoader.load(RESOURCES_PATH, "SyntreeResources", ResourceLoader.CACHE_MODE_IGNORE)
	
	# <<< Add Logging >>>
	var resource_to_return = null
	if is_instance_valid(_resources) and is_instance_valid(_resources.view_state):
		resource_to_return = _resources.view_state
		
	var validity_check = is_instance_valid(resource_to_return)
	print("ContentBus: get_view_state_resource() - Returning resource. Is valid: %s" % str(validity_check))
	if not validity_check:
		push_warning("ContentBus: get_view_state_resource called but resource is invalid.")
		
	return resource_to_return

func is_dev_agent_enabled() -> bool:
	var vs := get_view_state_resource()
	if not is_instance_valid(vs):
		return false
	if vs.has_method("is_dev_agent_enabled"):
		return bool(vs.is_dev_agent_enabled())
	# Back-compat if method missing but field exists.
	if "dev_agent_enabled" in vs:
		return bool(vs.dev_agent_enabled)
	return false

func set_dev_agent_enabled(enabled: bool) -> void:
	var vs := get_view_state_resource()
	if not is_instance_valid(vs):
		push_warning("ContentBus: Cannot set dev_agent_enabled - ViewStateResource not available")
		return
	var desired := bool(enabled)
	if vs.has_method("set_dev_agent_enabled"):
		vs.set_dev_agent_enabled(desired)
	else:
		# Back-compat: set field + mark changed through view_state_changed.
		if "dev_agent_enabled" in vs:
			vs.dev_agent_enabled = desired
		if vs.has_signal("view_state_changed"):
			vs.view_state_changed.emit()
	_schedule_persist_resources()
	dev_agent_enabled_changed.emit(desired)

func get_graph_state_resource() -> GraphStateResource:
	# REMOVED 강제 리로드: _resources = ResourceLoader.load(RESOURCES_PATH, "SyntreeResources", ResourceLoader.CACHE_MODE_IGNORE)
	
	# <<< Add Logging >>>
	var resource_to_return = null
	if is_instance_valid(_resources) and is_instance_valid(_resources.graph_state):
		resource_to_return = _resources.graph_state
		
	var validity_check = is_instance_valid(resource_to_return)
	print("ContentBus: get_graph_state_resource() - Returning resource. Is valid: %s" % str(validity_check))
	if not validity_check:
		push_warning("ContentBus: get_graph_state_resource called but resource is invalid.")
		
	return resource_to_return

# Add active source methods
func set_source_active_state(source_id: String, is_active: bool) -> void:
	if _is_processing_active_update:
		print("ContentBus: Skipping recursive active state update")
		return
		
	print("ContentBus: Setting active state for %s to %s" % [source_id, str(is_active)])
	
	_is_processing_active_update = true
	
	var content_state = get_content_state_resource()
	if not is_instance_valid(content_state):
		push_error("ContentBus: Cannot set active state - ContentStateResource not available")
		_is_processing_active_update = false
		return
		
	if content_state.set_source_active_state(source_id, is_active):
		active_state_changed.emit(source_id, is_active)
	else:
		push_error("ContentBus: Failed to set active state for source: " + source_id)
	
	_is_processing_active_update = false

func get_source_active_state(source_id: String) -> bool:
	var content_state = get_content_state_resource()
	if not is_instance_valid(content_state):
		push_error("ContentBus: Cannot get active state - ContentStateResource not available")
		return false
		
	return content_state.get_source_active_state(source_id)

func get_active_sources() -> Array[String]:
	var content_state = get_content_state_resource()
	if not is_instance_valid(content_state):
		push_error("ContentBus: Cannot get active sources - ContentStateResource not available")
		return []
		
	return content_state.get_active_sources()

# --- Add Delete Request Method ---
func request_source_deletion(source_id: String) -> void:
	print("ContentBus: Deletion requested for source: %s" % source_id)
	var content_state = get_content_state_resource()
	if is_instance_valid(content_state):
		if not content_state.delete_source(source_id):
			push_error("ContentBus: Failed to delete source via ContentStateResource: " + source_id)
		# The resource should emit source_deleted if successful, triggering UI updates
	else:
		push_error("ContentBus: Cannot delete source - ContentStateResource not available.")
# --- End Delete Request Method ---

# Add handler for active state changes
func _on_active_state_changed(source_id: String, is_active: bool) -> void:
	if _is_processing_active_update:
		return
		
	_is_processing_active_update = true
	active_state_changed.emit(source_id, is_active)
	_is_processing_active_update = false
	# Persist changes so project reload retains toggle state even if no view_state change occurs.
	_schedule_persist_resources()

# --- ADD THIS FUNCTION --- 
func on_active_source_toggled(source_id: String, is_active: bool) -> void:
	print("[CONTENTBUS] Received active_source_toggled from UI for %s to %s" % [source_id, str(is_active)])
	# Directly call the main state setting function
	set_source_active_state(source_id, is_active)
# --- END ADDED FUNCTION ---

# scripts/autoload/content_bus.gd

func refresh_active_sources() -> void:
	var content_state = get_content_state_resource()
	if not is_instance_valid(content_state):
		push_error("ContentBus: Cannot refresh sources - content state not available")
		sources_refreshed.emit({"success": false, "error": "Content state not available"})
		return
		
	if content_state.has_method("refresh_active_sources"):
		var result = content_state.refresh_active_sources()
		sources_refreshed.emit(result)
	else:
		push_error("ContentBus: ContentStateResource missing refresh_active_sources method")
		sources_refreshed.emit({"success": false, "error": "Method not available"})

# --- ADD URL Loading Logic ---
func request_load_source_from_url(url: String, user_name: String, source_id_override: String = "") -> void: # Add user_name parameter
	_ensure_url_loader()
	if is_instance_valid(_url_loader) and _url_loader.has_method("request_load_source_from_url"):
		_url_loader.call("request_load_source_from_url", url, user_name, source_id_override)
# --- END URL Loading Logic ---

func _emit_remote_source_processed(source_id: String) -> void:
	remote_source_processed.emit(source_id)

# --- NEW: Trigger for Remote Refresh ---
func trigger_remote_source_refresh(source_id: String, url: String) -> void:
	print("ContentBus: Triggering remote source refresh for ID: %s, URL: %s" % [source_id, url])
	# We need the *current* name stored in the resource for this source_id
	var content_state = get_content_state_resource()
	var user_name = source_id # Fallback to ID
	if is_instance_valid(content_state):
		var source_data = content_state.get_source_data(source_id)
		if not source_data.is_empty() and source_data.has("meta") and source_data.meta.has("name"):
			user_name = source_data.meta.get("name")
	else:
		push_warning("ContentBus: Could not get current name for remote refresh of %s" % source_id)
		
	# Re-use the existing request function, preserving the existing source_id so refresh updates in-place.
	request_load_source_from_url(url, user_name, source_id)
# --- END NEW TRIGGER --- 
