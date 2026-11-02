## Purpose: ContentService (script)
@tool
extends Node
class_name ContentService

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")

# Services
var persistence: ContentPersistenceService
var _is_ready: bool = false

func _content_state() -> Object:
	var bus := SynTreeAutoloads.content_bus()
	if not is_instance_valid(bus):
		return null
	return bus.get_content_state_resource()

# Signals
signal content_loaded(content: Dictionary)
signal content_saved(content: Dictionary)
signal content_deleted(content_id: String)
signal operation_failed(operation: String, error: String)
signal content_source_saved(source: Dictionary)
signal content_source_removed(source: Dictionary)
signal initialization_completed

# Content sources storage
var _content_sources: Array = []

# Refactor initialize to be synchronous
func initialize(plugin_manager) -> void:
	print("ContentService: Initializing (synchronous check)...")
	if not plugin_manager or not plugin_manager.has_method("get_content_persistence"):
		push_error("ContentService: Invalid PluginManager provided.")
		operation_failed.emit("initialize", "Invalid PluginManager")
		return
		
	persistence = plugin_manager.get_content_persistence()
	if not is_instance_valid(persistence):
		push_error("ContentService: Failed to get ContentPersistenceService from PluginManager.")
		operation_failed.emit("initialize", "Persistence service unavailable")
		return

	# --- Just mark ready immediately --- 
	_is_ready = true
	initialization_completed.emit()
	print("ContentService: Initialization complete (assuming persistence is ready).")

# Content Sources Management
func get_content_sources() -> Array:
	return _content_sources

func save_content_source(source: Dictionary) -> void:
	if not source.has("name") or not source.has("path"):
		operation_failed.emit("save_source", "Invalid source data")
		return
		
	# Update existing or add new
	var found = false
	for i in range(_content_sources.size()):
		if _content_sources[i].name == source.name:
			_content_sources[i] = source
			found = true
			break
			
	if not found:
		_content_sources.append(source)
	
	content_source_saved.emit(source)

func remove_content_source(source: Dictionary) -> void:
	if not source.has("name"):
		operation_failed.emit("remove_source", "Invalid source data")
		return
		
	for i in range(_content_sources.size()):
		if _content_sources[i].name == source.name:
			_content_sources.remove_at(i)
			content_source_removed.emit(source)
			return
			
	operation_failed.emit("remove_source", "Source not found")

# Load content - returns {content: Dictionary, error: String}
func load_content(content_id: String = "", file_path: String = "") -> Dictionary:
	if not _is_ready:
		print("ContentService: Service not ready")
		return {"content": {}, "error": "Service not ready"}
	
	if not persistence:
		print("ContentService: Persistence service not available")
		return {"content": {}, "error": "Persistence service not available"}
	
	print("ContentService: Loading content from file: ", file_path)
	var content = persistence.load_content(file_path)
	if not content.is_empty():
		print("ContentService: Content loaded successfully")
		
		# Parse content if it's a string (JSON)
		if content is String:
			var json = JSON.new()
			var error = json.parse(content)
			if error == OK:
				content = json.get_data()
				print("ContentService: JSON parsed successfully")
			else:
				print("ContentService: Failed to parse JSON: ", json.get_error_message())
				return {"content": {}, "error": "Failed to parse JSON content"}
		
		if not content is Dictionary:
			print("ContentService: Content is not a dictionary: ", typeof(content))
			return {"content": {}, "error": "Invalid content format"}
		
		print("ContentService: Content loading complete")
		content_loaded.emit(content)
		if content_id.is_empty():
			return {"content": content, "error": ""}
		elif content.has(content_id):
			return {"content": content[content_id], "error": ""}
	else:
		print("ContentService: No content found in file")
	return {"content": {}, "error": "Content not found"}

# Save content - Update to get hierarchy from Resource
func save_content(content: Dictionary = {}) -> Dictionary:
	if not _check_services(): return {"success": false, "error": "Services not available"}
	
	var content_state = _content_state()
	var to_save = {}
	if content.is_empty():
		if is_instance_valid(content_state) and content_state.has_method("get_hierarchy"):
			to_save = content_state.get_hierarchy()
		else:
			push_warning("ContentService: Cannot get hierarchy from ContentStateResource to save.")
	else:
		to_save = content # Use provided content if not empty
	
	if to_save.is_empty():
		return {"success": false, "error": "No content provided or retrieved to save"}
		
	if persistence.save_content(to_save):
		content_saved.emit(to_save)
		return {"success": true, "error": ""}
	return {"success": false, "error": "Failed to save content"}

# Delete content - returns {success: bool, error: String}
func delete_content(content_id: String) -> Dictionary:
	if not _check_services(): return {"success": false, "error": "Services not available"}
	
	if persistence.delete_content(content_id):
		content_deleted.emit(content_id)
		return {"success": true, "error": ""}
	return {"success": false, "error": "Failed to delete content"}

# Helper function to check services
func _check_services() -> bool:
	if not persistence:
		operation_failed.emit("service_check", "Persistence service not set")
		return false
	return true

# Check if service is ready
func is_ready() -> bool:
	return _is_ready

# --- NEW FUNCTION: Source Stack Creation ---
# Creates a new content source file (.json) that represents a stack of other active sources.
func create_source_stack(stack_name: String) -> Dictionary:
	print("ContentService: Creating source stack named: ", stack_name)
	
	# 1. Get ContentStateResource via ContentBus
	var content_state = _content_state()
	if not is_instance_valid(content_state):
		var err_msg = "ContentStateResource not available via ContentBus."
		operation_failed.emit("create_stack", err_msg)
		return {"success": false, "error": err_msg}

	# 2. Get Active Sources
	var active_sources = content_state.get_active_sources()
	if active_sources.is_empty():
		var err_msg = "No active sources found to create a stack."
		# Don't emit operation_failed here, let the caller (UI) handle this specific user flow issue.
		return {"success": false, "error": err_msg}
	
	# 3. Get data for active sources (for metadata in stack file)
	var active_source_data_list = []
	var source_descriptions = []
	for source_id in active_sources:
		var source_data = content_state.get_source_data(source_id)
		if not source_data.is_empty() and source_data.has("meta"):
			var source_meta = source_data.meta
			var source_display_name = source_meta.get("name", source_id)
			var source_path = source_meta.get("path", "")
			active_source_data_list.append({
				"id": source_id,
				"name": source_display_name,
				"path": source_path
			})
			source_descriptions.append("- " + source_display_name + " (ID: " + source_id + ")")
		else:
			push_warning("ContentService: Could not get metadata for active source ID: " + source_id + " while creating stack.")
			# Optionally skip this source or continue?

	# 4. Prepare Stack Data Structure
	var final_stack_name = stack_name if not stack_name.is_empty() else "source_stack"
	var stack_data = {
		"format_version": "1.0.0",
		"meta": {
			"source_id": str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000000),
			"name": final_stack_name,
			"author": "SynTree User", # Consider making this configurable later
			"created": Time.get_datetime_string_from_system(),
			"modified": Time.get_datetime_string_from_system(),
			"path": "", # Will be set after determining filename
			"ai_context": {
				"metaprompt": false,
				"is_stack": true,
				"stack_sources": active_source_data_list, # Use the gathered list
				"is_active": false, # Stacks shouldn't auto-activate usually
				"model_metadata": {}
			}
		},
		"content": {
			"nodes": [] # Create a simple documentation node
		}
	}
	var node_uuid = stack_data.meta.source_id + "_node"
	stack_data.content.nodes.append({
		"node_id": node_uuid,
		"is_root": true,
		"title": final_stack_name,
		"position": {"x": 0, "y": 0},
		"content": "# " + final_stack_name + "\nThis stack includes the following sources:\n" + "\n".join(source_descriptions),
		"relationships": {"parents": [], "children": [], "dependencies": []}
	})
	
	# 5. Determine Save Path and Handle Conflicts
	var base_name = final_stack_name.to_lower().replace(" ", "_").replace("-", "_")
	var file_name = base_name + ".json"
	var counter = 1
	var dir_path = "res://addons/syntree/content_source_lists"
	var save_path = dir_path.path_join(file_name)
	
	# Ensure directory exists
	var dir = DirAccess.open("res://")
	if not dir:
		operation_failed.emit("create_stack", "Failed to access project directory")
		return {"success": false, "error": "Failed to access project directory"}
	
	if not dir.dir_exists(dir_path):
		var err = dir.make_dir_recursive(dir_path)
		if err != OK:
			operation_failed.emit("create_stack", "Failed to create content sources directory")
			return {"success": false, "error": "Failed to create content sources directory"}

	# Check for existing file and add suffix
	while FileAccess.file_exists(save_path):
		file_name = base_name + "_" + str(counter) + ".json"
		save_path = dir_path.path_join(file_name)
		counter += 1
	
	stack_data.meta.path = save_path # Set the final path in metadata
	
	# 6. Save the Stack File
	var save_file = FileAccess.open(save_path, FileAccess.WRITE)
	if not save_file:
		var err_msg = "Could not create stack file at: " + save_path
		operation_failed.emit("create_stack", err_msg)
		return {"success": false, "error": err_msg}
	
	save_file.store_string(JSON.stringify(stack_data, "  "))
	save_file.close()
	print("ContentService: Successfully saved source stack to: ", save_path)
	
	# 7. Load the new stack into ContentStateResource
	var load_result = content_state.load_source_from_file(save_path)
	if not load_result.success:
		# File was saved, but loading failed. This is weird.
		var err_msg = "Stack file saved to %s, but failed to load into state: %s" % [save_path, load_result.get("error", "Unknown loading error")]
		operation_failed.emit("create_stack", err_msg)
		# Return success=true because file was saved, but maybe add a warning?
		return {"success": true, "warning": err_msg}

	# Emit a signal? Reuse content_source_saved or add specific one?
	# content_source_saved.emit(stack_data) # Maybe pass the whole data?
	
	return {"success": true, "path": save_path, "data": stack_data}

# --- Service Methods for Content Loading/Saving ---

# Loads a single, specific content source, clearing others.
func load_specific_source(source_id_or_name: String) -> Dictionary:
	var content_state = _content_state()
	if not is_instance_valid(content_state):
		var err_msg = "ContentStateResource not available via ContentBus."
		operation_failed.emit("load_specific", err_msg)
		return {"success": false, "error": err_msg}
	
	# Clear existing content first
	if content_state.has_method("clear_all_sources"):
		content_state.clear_all_sources()
	else:
		push_warning("ContentService: ContentStateResource missing clear_all_sources method.")
		# Continue anyway, but loading might behave unexpectedly

	# Load the specific source
	if content_state.has_method("load_source_content"):
		var result = content_state.load_source_content(source_id_or_name)
		if not result.get("success", false):
			var err_msg = "Failed to load content source '%s': %s" % [source_id_or_name, result.get("error", "Unknown error")]
			operation_failed.emit("load_specific", err_msg)
			return {"success": false, "error": err_msg}
		return {"success": true}
	else:
		var err_msg = "ContentStateResource missing load_source_content method."
		operation_failed.emit("load_specific", err_msg)
		return {"success": false, "error": err_msg}

# Initializes/Reloads all content sources from the specified directory.
func load_all_sources(directory: String = "") -> Dictionary:
	var content_state = _content_state()
	if not is_instance_valid(content_state):
		var err_msg = "ContentStateResource not available via ContentBus."
		operation_failed.emit("load_all", err_msg)
		return {"success": false, "error": err_msg}

	var target_dir = directory
	if target_dir.is_empty():
		# Use a default path if none provided, maybe from config or constant?
		target_dir = "res://addons/syntree/content_source_lists/"

	if content_state.has_method("initialize_content_sources"):
		var result = content_state.initialize_content_sources(target_dir)
		if not result.get("success", false):
			var err_msg = "Failed to load sources from '%s': %s" % [target_dir, result.get("error", "Unknown error")]
			operation_failed.emit("load_all", err_msg)
			return {"success": false, "error": err_msg}
		
		if result.get("sources_loaded", 0) == 0:
			# This might not be an error, could be an empty directory
			push_warning("ContentService: No valid content sources found in " + target_dir)
			# Return success but maybe indicate zero loaded?
			return {"success": true, "count": 0}
		
		return {"success": true, "count": result.get("sources_loaded", 0)}
	else:
		var err_msg = "ContentStateResource missing initialize_content_sources method."
		operation_failed.emit("load_all", err_msg)
		return {"success": false, "error": err_msg}

# Persists the current state (e.g., active, metaprompt) of all loaded sources.
func persist_all_source_states() -> Dictionary:
	var content_state = _content_state()
	if not is_instance_valid(content_state):
		var err_msg = "ContentStateResource not available via ContentBus."
		operation_failed.emit("persist_all", err_msg)
		return {"success": false, "error": err_msg}
	
	if not content_state.has_method("save_all_source_states"):
		# If ContentStateResource doesn't have a bulk save method, 
		# we might need to implement iteration here or add it there.
		# For now, assume individual saves happened on state change.
		push_warning("ContentService: ContentStateResource does not implement save_all_source_states. Assuming states saved on change.")
		return {"success": true, "message": "No bulk save method; states assumed saved on change."}
	
	var result = content_state.save_all_source_states()
	if not result.get("success", false):
		var err_msg = "Failed to persist source states: %s" % result.get("error", "Unknown error")
		operation_failed.emit("persist_all", err_msg)
		return {"success": false, "error": err_msg}
	
	print("ContentService: Persisted states for %d sources." % result.get("saved_count", 0))
	return {"success": true}

# Loads a single source file, typically used after creation via dialog.
func load_newly_created_source(json_path: String) -> Dictionary:
	var content_state = _content_state()
	if not is_instance_valid(content_state):
		var err_msg = "ContentStateResource not available via ContentBus."
		operation_failed.emit("load_new", err_msg)
		return {"success": false, "error": err_msg}

	if not content_state.has_method("load_source_from_file"):
		var err_msg = "ContentStateResource missing load_source_from_file method."
		operation_failed.emit("load_new", err_msg)
		return {"success": false, "error": err_msg}
		
	var result = content_state.load_source_from_file(json_path)
	if not result.get("success", false):
		var err_msg = "Failed to load newly created source '%s': %s" % [json_path, result.get("error", "Unknown error")]
		operation_failed.emit("load_new", err_msg)
		return {"success": false, "error": err_msg}
	
	# Optionally emit a signal or return more data?
	return {"success": true}

# --- NEW: Create Source from Local File ---
func create_source_from_file(source_name: String, source_path: String) -> Dictionary:
	print("ContentService: Attempting to create source metadata for '%s' pointing to '%s'" % [source_name, source_path])
	
	if source_path.is_empty() or source_name.is_empty():
		return {"success": false, "error": "Invalid source name or path provided."}
	
	# 2. Generate unique source ID based on user name
	var source_id = source_name.to_lower().replace(" ", "_").replace("-", "_")
	
	# 3. Get extension from the provided source path
	var extension = source_path.get_extension().to_lower()
	
	# 4. Ensure the output directory exists
	var dir_path = "res://addons/syntree/content_source_lists"
	var dir = DirAccess.open("res://")
	if not dir:
		return {"success": false, "error": "Failed to access project directory"}
	if not dir.dir_exists(dir_path):
		var err = dir.make_dir_recursive(dir_path)
		if err != OK:
			return {"success": false, "error": "Failed to create content sources directory"}
	
	# 5. Handle filename conflicts for the metadata JSON file
	var json_filename = source_id + ".json"
	var target_path = dir_path.path_join(json_filename) # Path for the NEW metadata json
	var counter = 1
	while FileAccess.file_exists(target_path):
		var new_source_id = "%s_%d" % [source_id.rstrip("_%0123456789"), counter]
		json_filename = new_source_id + ".json"
		target_path = dir_path.path_join(json_filename)
		source_id = new_source_id # Update source_id to match the final filename
		counter += 1
	
	# 6. Create the final JSON structure (Metadata container)
	var content_source_data = {
		"format_version": "1.0.0",
		"meta": {
			"source_id": source_id, # Use potentially updated ID
			"name": source_name, # Use user-provided name
			"author": "SynTree User",
			"created": Time.get_datetime_string_from_system(),
			"modified": Time.get_datetime_string_from_system(),
			"path": source_path, # Store original user-provided path to ACTUAL content
			"source_origin": "file", # Set origin
			"source_type": extension, # Store original file extension
			"ai_context": {"metaprompt": false, "is_active": false, "model_metadata": {}}
		},
		"content": {
			# Create a default root node so hierarchy/stack views always have an anchor.
			"nodes": [
				{
					"node_id": "%s_root" % source_id,
					"title": "Root",
					"is_root": true,
					"position": {"x": 0, "y": 0},
					"content": "# %s\n\nPath: %s" % [source_name, source_path],
					"relationships": {"parents": [], "children": [], "dependencies": []},
				}
			]
		}
	}
	
	# 7. Save the new metadata JSON file
	var json_string = JSON.stringify(content_source_data, "  ")
	var save_file = FileAccess.open(target_path, FileAccess.WRITE)
	if not save_file:
		return {"success": false, "error": "Failed to create content source file at: " + target_path}
	
	save_file.store_string(json_string)
	save_file.close()
	
	# 8. Load the newly created metadata JSON into ContentStateResource
	var content_state = _content_state()
	if is_instance_valid(content_state) and content_state.has_method("load_source_from_file"):
		var loaded_id = content_state.load_source_from_file(target_path)
		if loaded_id.is_empty():
			# File saved but couldn't be loaded - should not happen if saving worked
			return {"success": false, "error": "Saved file %s but failed to load into state." % target_path}
	else:
		return {"success": false, "error": "ContentStateResource unavailable or missing load method."}

	print("ContentService: Successfully created metadata source '%s' pointing to '%s' (saved as '%s')" % [source_name, source_path, target_path])
	return {"success": true, "data": content_source_data}
# --- END NEW FUNCTION ---

# --- End Service Methods ---
