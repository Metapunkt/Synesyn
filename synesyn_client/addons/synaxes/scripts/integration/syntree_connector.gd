@tool
extends RefCounted
class_name SynTreeConnector

signal data_imported(data)
signal import_error(error_message)

# Configuration
var _syntree_path: String = "res://addons/syntree"
var _content_types: Array[String] = ["text", "document", "semantic", "image"]
var _max_items: int = 100
var _include_metadata: bool = true

func set_syntree_path(path: String) -> void:
	_syntree_path = path

func set_content_types(types: Array[String]) -> void:
	_content_types = types

func set_max_items(max_items: int) -> void:
	_max_items = max_items

func set_include_metadata(include: bool) -> void:
	_include_metadata = include

# Import data from SynTree content sources
func import_data() -> void:
	var syntree_plugin = _find_syntree_plugin()
	
	if not syntree_plugin:
		# This is an expected condition when SynTree is not installed
		print("Synaxes: SynTree not detected at path: " + _syntree_path + " (using test data instead)")
		emit_signal("import_error", "SynTree_NOT_FOUND")
		return
	
	var content_sources = _get_content_sources(syntree_plugin)
	
	if content_sources.is_empty():
		emit_signal("import_error", "No content sources found in SynTree")
		return
	
	var imported_data = []
	
	for source in content_sources:
		if not _is_valid_content_type(source):
			continue
		
		var source_data = _extract_data_from_source(source)
		if not source_data.is_empty():
			imported_data.append_array(source_data)
		
		if imported_data.size() >= _max_items:
			imported_data = imported_data.slice(0, _max_items)
			break
	
	emit_signal("data_imported", imported_data)

# Find the SynTree plugin in the filesystem
func _find_syntree_plugin() -> Node:
	# Check if SynTree folder exists without using EditorFileSystem
	if not FileAccess.file_exists(_syntree_path + "/plugin.gd"):
		return null
		
	# Try to load the plugin script
	var plugin_script = load(_syntree_path + "/plugin.gd")
	if plugin_script:
		return plugin_script.new()
	
	return null

# Get content sources from SynTree
func _get_content_sources(syntree_plugin: Node) -> Array:
	if syntree_plugin and syntree_plugin.has_method("get_content_sources"):
		return syntree_plugin.get_content_sources()
	
	return []

# Extract data from a SynTree content source
func _extract_data_from_source(source: Node) -> Array:
	if not source or not source.has_method("get_items"):
		return []
	
	var items = source.get_items()
	var processed_items = []
	
	for item in items:
		var processed_item = _process_content_item(item, source)
		if not processed_item.is_empty():
			processed_items.append(processed_item)
	
	return processed_items

# Process a single content item
func _process_content_item(item: Dictionary, source: Node) -> Dictionary:
	if not item.has("content"):
		return {}
	
	var processed_data = {
		"content": item["content"],
		"id": item.get("id", str(randi())),
	}
	
	# Add vector data if available
	if item.has("vector"):
		processed_data["vector"] = item["vector"]
	elif item.has("embedding"):
		processed_data["vector"] = item["embedding"]
	
	# Add type information
	processed_data["type"] = source.get("type") if source.has("type") else "unknown"
	
	# Add timestamp if available
	if item.has("timestamp"):
		processed_data["timestamp"] = item["timestamp"]
	elif item.has("time"):
		processed_data["timestamp"] = item["time"]
	elif item.has("date"):
		processed_data["timestamp"] = item["date"]
	
	# Add metadata if requested
	if _include_metadata:
		var metadata = {}
		for key in item:
			if key != "content" and key != "vector" and key != "embedding":
				metadata[key] = item[key]
		
		processed_data["metadata"] = metadata
	
	return processed_data

# Check if content source is of a type we want to import
func _is_valid_content_type(source: Node) -> bool:
	var source_type = source.get("type") if source.has("type") else "unknown"
	
	for allowed_type in _content_types:
		if source_type.to_lower().contains(allowed_type.to_lower()):
			return true
	
	return false

# Re-check SynTree availability and re-import if found.
func refresh_sources() -> void:
	import_data()

# Sync changes back to SynTree (not implemented yet)
func sync_changes_to_syntree(patterns: Array) -> void:
	# TODO: Implement syncing changes back to SynTree
	pass
