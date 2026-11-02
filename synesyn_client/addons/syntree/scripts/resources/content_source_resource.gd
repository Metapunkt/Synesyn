## Purpose: ContentSourceResource (script)
@tool
extends Resource
class_name ContentSourceResource

signal source_added(source_id: String)
signal source_deleted(source_id: String) 
signal source_updated(source_id: String)
signal metaprompt_state_changed(source_id: String, is_metaprompt: bool)
signal active_state_changed(source_id: String, is_active: bool)

# Main data storage
@export var sources: Dictionary = {}
@export var node_to_source_map: Dictionary = {}
@export var sources_directory: String = "res://addons/syntree/content_source_lists"

# Schema validation (internal helper)
const _ContentSourceSchemaOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_source_schema_ops.gd")
var _schema_ops: Variant = null
const _ContentSourceSyncOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_source_sync_ops.gd")
var _sync_ops: Variant = null
const _ContentSourceIOOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_source_io_ops.gd")
var _io_ops: Variant = null

# Initialization
var _initialized: bool = false

func _init() -> void:
	# Connect to our own signals to mark resource as changed when data changes
	source_added.connect(_on_data_changed)
	source_deleted.connect(_on_data_changed)
	source_updated.connect(_on_data_changed)
	
	_initialized = true

func _on_data_changed(_arg = null) -> void:
	# Mark this resource as changed when data is modified
	emit_changed()

# Resource API
func is_initialized() -> bool:
	return _initialized

func clear_data() -> void:
	sources.clear()
	node_to_source_map.clear()

# Source management
func get_source_data(any_id: String) -> Dictionary:
	"""
	Returns source data for a given ID (source ID or node ID)
	"""
	if any_id.is_empty():
		return {}
		
	# If it's a node, get its source first
	var source_id = any_id
	if node_to_source_map.has(any_id):
		source_id = node_to_source_map[any_id]
	
	# Normalize the ID
	var normalized_id = get_normalized_id(source_id)
	
	# Return source data
	return sources.get(normalized_id, {})

func load_source_from_file(path: String) -> String:
	"""
	Loads a single source from a JSON file
	Returns the source ID if successful, empty string otherwise
	"""
	if not FileAccess.file_exists(path):
		push_error("ContentSourceResource: File not found: " + path)
		return ""
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ContentSourceResource: Failed to open file: " + path)
		return ""
		
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		push_error("ContentSourceResource: Failed to parse JSON: " + json.get_error_message())
		return ""
		
	var source_data = json.get_data()
	
	# Validate the data
	if not _validate_source_data(source_data):
		push_error("ContentSourceResource: Invalid source data format in file: " + path)
		return ""
		
	# Extract source ID
	var source_id = source_data.get("meta", {}).get("source_id", "")
	if source_id.is_empty():
		push_error("ContentSourceResource: Missing source_id in meta data: " + path)
		return ""
		
	# Store source data
	sources[source_id] = source_data
	
	# Register node relationships
	_register_nodes_to_source(source_data)
	
	# Emit the signal after successful load and store
	source_added.emit(source_id)
	print("[STATE] Emitted source_added for %s loaded from %s" % [source_id, path])
	
	return source_id

func _register_nodes_to_source(source_data: Dictionary) -> void:
	"""
	Registers all nodes in a source to the node_to_source_map
	"""
	var source_id = source_data["meta"]["source_id"]
	var normalized_source_id: String = get_normalized_id(str(source_id))
	# Rebuild this source's entries so removed/renamed nodes cannot leave stale
	# node-to-source mappings after an update.
	for mapped_node_id in node_to_source_map.keys():
		var mapped_source_id: String = get_normalized_id(
			str(node_to_source_map[mapped_node_id])
		)
		if mapped_source_id == normalized_source_id:
			node_to_source_map.erase(mapped_node_id)
	var content = source_data.get("content", {})
	var nodes = []
	if content is Dictionary and content.has("nodes"):
		nodes = content["nodes"]
	
	for node in nodes:
		if node is Dictionary and node.has("node_id"):
			node_to_source_map[node["node_id"]] = source_id

func _get_preferred_disk_path_for_source(source_id: String, source_data: Dictionary) -> String:
	# Prefer saving back to meta.path when it points to a local JSON file.
	# This prevents "persists during session but not after reload" when the filename differs from meta.source_id.
	var save_dir: String = sources_directory.strip_edges()
	if save_dir.is_empty():
		save_dir = "res://addons/syntree/content_source_lists"
	save_dir = save_dir.replace("\\", "/").strip_edges()

	var fallback := save_dir.path_join(source_id + ".json")

	var meta_any: Variant = source_data.get("meta", {})
	if typeof(meta_any) == TYPE_DICTIONARY:
		var meta: Dictionary = meta_any
		var p := str(meta.get("path", "")).strip_edges()
		if not p.is_empty():
			p = p.replace("\\", "/")
			if p.ends_with(".json"):
				# Trust it if it exists or is clearly within our configured sources directory.
				if FileAccess.file_exists(p) or p.begins_with(save_dir) or p.find("/content_source_lists/") != -1:
					return p

	return fallback

func save_source(source_id: String) -> bool:
	"""
	Saves a source to disk
	Returns true if successful, false otherwise
	"""
	var source_data = get_source_data(source_id)
	if source_data.is_empty():
		push_error("ContentSourceResource: Save failed - Source not found: " + source_id)
		return false
		
	# --- Determine SAVE Path --- 
	var path := _get_preferred_disk_path_for_source(source_id, source_data)
	path = path.replace("\\", "/")

	if _io_ops == null:
		_io_ops = _ContentSourceIOOpsScript.new()
	var res: Dictionary = (_io_ops as Object).call("write_json_file", path, source_data, "  ")
	if not bool(res.get("success", false)):
		push_error("ContentSourceResource: Save failed - %s" % str(res.get("error", "Unknown IO error")))
		return false
	return true

func update_source(source_id: String, data: Dictionary) -> bool:
	"""
	Updates a source with new data
	Returns true if successful, false otherwise
	"""
	var normalized_id := get_normalized_id(source_id)
	if not sources.has(normalized_id):
		push_error("ContentSourceResource: Source not found: " + normalized_id)
		return false
		
	# Validate the data
	if not _validate_source_data(data):
		push_error("ContentSourceResource: Invalid source data format")
		return false
		
	# Update the source
	# Ensure meta.source_id stays consistent with the key we store under.
	if data.has("meta") and data.get("meta") is Dictionary:
		(data["meta"] as Dictionary)["source_id"] = normalized_id
	sources[normalized_id] = data
	
	# Update node-to-source map
	_register_nodes_to_source(data)
	
	# Emit signal
	source_updated.emit(normalized_id)
	
	return true

func delete_source(source_id: String) -> bool:
	"""
	Deletes a source
	Returns true if successful, false otherwise
	"""
	if not sources.has(source_id):
		push_error("ContentSourceResource: Source not found: " + source_id)
		return false
		
	# Get correct file path (prefer meta.path when available)
	var source_data = get_source_data(source_id)
	var path := _get_preferred_disk_path_for_source(source_id, source_data)
	
	# Remove from sources dictionary
	sources.erase(source_id)
	
	# Remove all nodes for this source from the map
	var nodes_to_remove = []
	for node_id in node_to_source_map:
		if node_to_source_map[node_id] == source_id:
			nodes_to_remove.append(node_id)
			
	for node_id in nodes_to_remove:
		node_to_source_map.erase(node_id)
	
	# Delete file (best-effort; source already removed from memory)
	if _io_ops == null:
		_io_ops = _ContentSourceIOOpsScript.new()
	var del_res: Dictionary = (_io_ops as Object).call("remove_file", path)
	if not bool(del_res.get("success", true)):
		push_error("ContentSourceResource: Failed to delete file %s. Error: %s" % [path, str(del_res.get("error", ""))])
	
	# Emit signal
	source_deleted.emit(source_id)
	
	return true

# Metaprompt state management
func set_metaprompt_state(source_id: String, is_metaprompt: bool) -> bool:
	"""Sets the metaprompt state for a source and ensures it persists"""
	
	var normalized_id := get_normalized_id(source_id)
	var source_data = get_source_data(normalized_id)
	if source_data.is_empty():
		push_error("[STATE] Cannot set metaprompt state - Source not found: " + normalized_id)
		return false
	
	# Get current state for comparison
	var current_state = source_data.get("meta", {}).get("ai_context", {}).get("metaprompt", false)
	if current_state == is_metaprompt:
		print("[STATE] Source %s already in desired metaprompt state: %s" % [source_id, str(is_metaprompt)])
		return true
	
	# Ensure nested structure exists
	if not source_data.has("meta"):
		source_data["meta"] = {}
	if not source_data.meta.has("ai_context"):
		source_data.meta["ai_context"] = {}
	
	# Update state in memory (local copy), then commit to the resource store.
	source_data.meta.ai_context["metaprompt"] = is_metaprompt

	# IMPORTANT: ensure the in-memory sources dictionary is updated so view rebuilds reflect the change.
	# Without this, UI can show the toggled state but switching views re-reads stale state.
	if not update_source(normalized_id, source_data):
		push_error("[STATE] Failed to update source in memory for metaprompt change: " + normalized_id)
		return false
	
	# Save with retry mechanism
	var max_retries = 3
	var retry_count = 0
	var save_success = false
	
	while retry_count < max_retries and not save_success:
		save_success = save_source(normalized_id)
		if not save_success:
			retry_count += 1
			print("[STATE] Save attempt %d failed for %s, retrying..." % [retry_count, normalized_id])
			OS.delay_msec(100) # Small delay between retries
	
	if not save_success:
		push_error("[STATE] Failed to save metaprompt state after %d attempts for %s" % [max_retries, normalized_id])
		# Revert memory state (best-effort) and re-commit.
		source_data.meta.ai_context["metaprompt"] = current_state
		update_source(normalized_id, source_data)
		return false
	
	# Verify the saved state
	var verification = _verify_saved_state(normalized_id, "metaprompt", is_metaprompt)
	if not verification.success:
		push_error("[STATE] State verification failed for %s: %s" % [normalized_id, verification.error])
		return false
	
	print("[STATE] Successfully set and verified metaprompt state for %s to %s" % [normalized_id, str(is_metaprompt)])
	metaprompt_state_changed.emit(normalized_id, is_metaprompt)
	emit_changed()
	return true

func _verify_saved_state(source_id: String, state_key: String, expected_value: bool) -> Dictionary:
	"""
	Verifies that a state was correctly saved to disk
	Returns Dictionary with success and error fields
	"""
	var source_data = get_source_data(source_id)
	var source_path := _get_preferred_disk_path_for_source(source_id, source_data)
	
	# Small delay to ensure file is written
	OS.delay_msec(50)

	if _io_ops == null:
		_io_ops = _ContentSourceIOOpsScript.new()
	var read_res: Dictionary = (_io_ops as Object).call("read_json_file", source_path)
	if not bool(read_res.get("success", false)):
		return {"success": false, "error": str(read_res.get("error", "Failed to read JSON for verification"))}
	var saved_data: Variant = read_res.get("data")
	if not (saved_data is Dictionary):
		return {"success": false, "error": "Saved JSON was not a Dictionary"}
	var saved_value = saved_data.get("meta", {}).get("ai_context", {}).get(state_key)
	
	if saved_value != expected_value:
		return {
			"success": false,
			"error": "Saved value (%s) does not match expected value (%s)" % [str(saved_value), str(expected_value)]
		}
	
	return {"success": true, "error": ""}

func get_metaprompt_state(source_id: String) -> bool:
	var source_data = get_source_data(source_id)
	return source_data.get("meta", {}).get("ai_context", {}).get("metaprompt", false)

# Add active source methods
func set_source_active_state(source_id: String, is_active: bool) -> bool:
	"""Sets the active state for a source and ensures it persists"""
	
	var normalized_id := get_normalized_id(source_id)
	var source_data = get_source_data(normalized_id)
	if source_data.is_empty():
		push_error("[STATE] Cannot set active state - Source not found: " + normalized_id)
		return false
	
	# Get current state for comparison
	var current_state = source_data.get("meta", {}).get("ai_context", {}).get("is_active", false)
	if current_state == is_active:
		print("[STATE] Source %s already in desired state: %s" % [source_id, str(is_active)])
		return true
	
	# Ensure nested structure exists
	if not source_data.has("meta"):
		source_data["meta"] = {}
	if not source_data.meta.has("ai_context"):
		source_data.meta["ai_context"] = {}
	
	# Update state in memory (local copy), then commit to the resource store.
	source_data.meta.ai_context["is_active"] = is_active

	# IMPORTANT: ensure the in-memory sources dictionary is updated so view rebuilds reflect the change.
	if not update_source(normalized_id, source_data):
		push_error("[STATE] Failed to update source in memory for active-state change: " + normalized_id)
		return false
	
	# Save with retry mechanism
	var max_retries = 3
	var retry_count = 0
	var save_success = false
	
	while retry_count < max_retries and not save_success:
		save_success = save_source(normalized_id)
		if not save_success:
			retry_count += 1
			print("[STATE] Save attempt %d failed for %s, retrying..." % [retry_count, normalized_id])
			OS.delay_msec(100) # Small delay between retries
	
	if not save_success:
		push_error("[STATE] Failed to save active state after %d attempts for %s" % [max_retries, normalized_id])
		# Revert memory state (best-effort) and re-commit.
		source_data.meta.ai_context["is_active"] = current_state
		update_source(normalized_id, source_data)
		return false
	
	# Verify the saved state
	var verification = _verify_saved_state(normalized_id, "is_active", is_active)
	if not verification.success:
		push_error("[STATE] State verification failed for %s: %s" % [normalized_id, verification.error])
		return false
	
	print("[STATE] Successfully set and verified active state for %s to %s" % [normalized_id, str(is_active)])
	active_state_changed.emit(normalized_id, is_active)
	emit_changed()
	return true

func get_source_active_state(source_id: String) -> bool:
	var source_data = get_source_data(source_id)
	var state = source_data.get("meta", {}).get("ai_context", {}).get("is_active", false)
	print("[DEBUG_STATE] get_source_active_state for '%s': Found state '%s' (Type: %s)" % [source_id, str(state), typeof(state)])
	return state

func get_active_sources() -> Array[String]:
	var active_sources: Array[String] = []
	for source_id in sources:
		if get_source_active_state(source_id):
			active_sources.append(source_id)
	return active_sources

# Utility methods
func get_normalized_id(any_id: String) -> String:
	"""
	Normalizes an ID (source ID or file path)
	"""
	if any_id.is_empty():
		return ""
		
	# If it's a file path, extract the ID from the filename
	if any_id.ends_with(".json"):
		var file_name = any_id.split("/")[-1]  # Get the filename
		if file_name.contains("."):  # If it has an extension
			file_name = file_name.substr(0, file_name.rfind("."))  # Remove extension
		return file_name
		
	# If it's already a source ID, return it
	if sources.has(any_id):
		return any_id
		
	# If it's a node ID, return its source ID
	if node_to_source_map.has(any_id):
		return node_to_source_map[any_id]
		
	# Default case - return the original ID
	return any_id

func get_source_for_node(node_id: String) -> String:
	"""
	Returns the source ID for a node
	"""
	return node_to_source_map.get(node_id, "")

func register_node_source_relationship(node_id: String, source_id: String) -> void:
	"""
	Registers a node to a source
	"""
	node_to_source_map[node_id] = source_id

func has_source(source_id: String) -> bool:
	"""
	Checks if a source exists
	"""
	var normalized_id = get_normalized_id(source_id)
	return sources.has(normalized_id)

# Validation
func _validate_source_data(data: Dictionary) -> bool:
	"""
	Validates source data against the schema
	"""
	if _schema_ops == null:
		_schema_ops = _ContentSourceSchemaOpsScript.new()
	var res: Dictionary = (_schema_ops as Object).call("validate_and_normalize_source_data", data)
	if not bool(res.get("success", false)):
		push_warning("ContentSourceResource: " + str(res.get("error", "Invalid source data")))
		return false
	return true

# Directory initialization
func initialize_content_sources(content_dir: String = "") -> Dictionary:
	print("[STATE] Starting content sources initialization (Syncing with filesystem)")
	
	var dir_to_scan = content_dir
	if dir_to_scan.is_empty():
		dir_to_scan = sources_directory # Use the exported property
	
	var results = {
		"success": true,
		"sources_loaded": 0,
		"sources_added": 0,
		"sources_removed": 0,
		"errors": [],
		"active_sources_count": 0
	}
	
	# --- Filesystem Check (via helper) ---
	if _sync_ops == null:
		_sync_ops = _ContentSourceSyncOpsScript.new()
	var scan: Dictionary = (_sync_ops as Object).call("scan_json_source_ids", dir_to_scan)
	if not bool(scan.get("success", false)):
		results.success = false
		results.errors.append(str(scan.get("error", "Failed to scan directory")))
		print("[STATE] Error opening directory: ", str(scan.get("error", "")))
		return results
	var file_source_ids: PackedStringArray = scan.get("ids", PackedStringArray([]))
	print("[STATE] Found %d source files in %s" % [file_source_ids.size(), dir_to_scan])
	
	# --- Memory State Check --- 
	var memory_source_ids = sources.keys()
	print("[STATE] Found %d sources currently in memory." % memory_source_ids.size())
	
	# --- Synchronization Logic --- 
	var plan: Dictionary = (_sync_ops as Object).call("compute_sync_plan", file_source_ids, memory_source_ids)
	var sources_to_remove: Array = plan.get("to_remove", [])
	var sources_to_add: Array = plan.get("to_add", [])
			
	# Remove stale sources from memory
	if not sources_to_remove.is_empty():
		print("[STATE] Removing %d stale sources from memory: %s" % [sources_to_remove.size(), str(sources_to_remove)])
		for id_to_remove in sources_to_remove:
			# Perform cleanup similar to delete_source without file IO or signals
			sources.erase(id_to_remove)
			var nodes_in_map_to_remove = []
			for node_id in node_to_source_map:
				if node_to_source_map[node_id] == id_to_remove:
					nodes_in_map_to_remove.append(node_id)
			for node_id in nodes_in_map_to_remove:
				node_to_source_map.erase(node_id)
			results.sources_removed += 1
		
	# Add new sources from disk (not in memory)
	if not sources_to_add.is_empty():
		print("[STATE] Adding %d new sources from disk: %s" % [sources_to_add.size(), str(sources_to_add)])
		for id_to_add in sources_to_add:
			var file_path = dir_to_scan.path_join(id_to_add + ".json")
			var loaded_id = load_source_from_file(file_path) # This emits source_added
			if not loaded_id.is_empty():
				results.sources_added += 1
			else:
				results.errors.append("Failed to load new source file: " + file_path)
				results.success = false # Mark as non-successful if any load fails
				
	# --- Update Counts and Final Report --- 
	results.sources_loaded = sources.size() # Total count after sync
	
	# Recalculate active count based on current in-memory state
	results.active_sources_count = 0
	for source_id in sources:
		if get_source_active_state(source_id):
			results.active_sources_count += 1

	print("[STATE] Synchronization complete")
	print("  - Sources loaded/remaining: %d" % results.sources_loaded)
	print("  - Sources added this sync: %d" % results.sources_added)
	print("  - Sources removed this sync: %d" % results.sources_removed)
	print("  - Active sources in memory: %d" % results.active_sources_count)
	print("  - Errors encountered: %d" % results.errors.size())
	
	emit_changed()
	return results

# Import methods
func import_from_content_model(content_model: Node) -> void:
	"""
	Imports data from a ContentModel
	"""
	if not content_model or not content_model.has_method("get_source_ids"):
		push_error("ContentSourceResource: Invalid ContentModel provided")
		return
		
	print("ContentSourceResource: Importing data from ContentModel")
	
	# Clear existing data
	clear_data()
	
	# Get all source IDs
	var source_ids = content_model.get_source_ids()
	print("ContentSourceResource: Found %d sources to import" % source_ids.size())
	
	# Import each source
	for source_id in source_ids:
		var source_data = content_model.get_source_data(source_id)
		if not source_data.is_empty():
			# Validate source data
			if not _validate_source_data(source_data):
				push_warning("ContentSourceResource: Invalid source data for ID: %s" % source_id)
				continue
			
			# Store source data
			sources[source_id] = source_data.duplicate(true)
			print("ContentSourceResource: Imported source: %s" % source_id)
			
			# Process nodes for node-to-source mapping
			if source_data.has("content") and source_data.content.has("nodes"):
				var nodes = source_data.content.nodes
				if nodes is Array:
					for node in nodes:
						if node is Dictionary and node.has("node_id"):
							node_to_source_map[node.node_id] = source_id
							print("ContentSourceResource: Mapped node %s to source %s" % [node.node_id, source_id])
				elif nodes is Dictionary:
					for node_id in nodes:
						node_to_source_map[node_id] = source_id
						print("ContentSourceResource: Mapped node %s to source %s" % [node_id, source_id])
			
			# Emit signal for each imported source
			source_added.emit(source_id)
		else:
			push_warning("ContentSourceResource: Empty source data for ID: %s" % source_id)
	
	print("ContentSourceResource: Import complete - %d sources imported" % sources.size())
	print("ContentSourceResource: Node-to-source map contains %d entries" % node_to_source_map.size())

func get_source_ids() -> Array:
	"""
	Returns an array of all source IDs
	"""
	return sources.keys() 

# --- NEW: Direct Add/Update Function (Bypasses Validation) ---
func add_or_update_source_data(source_data: Dictionary) -> String:
	"""
	Directly adds or updates source data in the dictionary.
	Performs minimal checks. Assumes data structure is mostly correct.
	Used for temporary/basic remote loading where JSON validation is skipped.
	Returns the source_id if successful, empty string otherwise.
	"""
	if not source_data.has("meta") or not source_data.meta.has("source_id"):
		push_error("ContentSourceResource: Cannot add/update source - missing meta.source_id.")
		return ""
		
	var source_id = source_data.meta.source_id
	var was_update = sources.has(source_id)
	
	sources[source_id] = source_data # Add or overwrite
	_register_nodes_to_source(source_data) # Register the basic node
	
	if was_update:
		source_updated.emit(source_id)
		print("[STATE] Directly updated source: %s" % source_id)
	else:
		source_added.emit(source_id)
		print("[STATE] Directly added source: %s" % source_id)
		
	emit_changed()
	return source_id
# --- END NEW FUNCTION --- 
