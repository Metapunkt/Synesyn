## Purpose: ContentPersistenceService (script)
@tool
extends BaseService

class_name ContentPersistenceService

"""
NOTE: This service is currently reserved for future use.
It was originally designed to handle content source persistence but that functionality
has been moved to direct file management in the content_source_lists directory.

Future plans for this service include:
- Storing user preferences and settings
- Managing conversation history
- Caching frequently accessed content
- Storing custom AI model configurations
"""

#const CONTENT_FILE = "user://content.json"
#const SOURCES_FILE = "user://content_sources.json"
const CONTENT_FILE = ""
const SOURCES_FILE = ""

# State
var _last_save_time: int = 0
var _last_load_time: int = 0
var _sources: Dictionary = {}

# Signals
signal content_saved
signal content_loaded(source_name: String, content: Dictionary)
signal source_added(source_name: String)
signal source_removed(source_name: String)

func _init() -> void:
	# No dependencies required for this service
	pass

func _setup() -> bool:
	# Currently disabled - will be used for future features
	_is_ready = true
	return true

func get_service_name() -> String:
	return "content_persistence"

func _ensure_ready() -> bool:
	if not _is_ready:
		push_error("ContentPersistenceService: Service not ready")
		return false
	return true

# These methods are kept but made inactive for future implementation
func add_source(source_name: String, source_path: String) -> bool:
	return true  # No-op for now

func remove_source(source_name: String) -> bool:
	return true  # No-op for now

func get_sources() -> Dictionary:
	return {}  # No-op for now

func _save_sources() -> bool:
	return true  # No-op for now

func _load_sources() -> bool:
	return true  # No-op for now

func save_content(nodes: Dictionary) -> bool:
	return true  # No-op for now

func load_content(file_path: String = CONTENT_FILE) -> Dictionary:
	if not _ensure_ready():
		return {}
		
	if not FileAccess.file_exists(file_path):
		push_warning("No content file found at: " + file_path)
		return {}
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open file for reading: " + file_path)
		return {}
		
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	if json == null:
		push_error("Failed to parse content file")
		return {}
		
	_last_load_time = Time.get_unix_time_from_system()
	content_loaded.emit()
	return json

func get_last_save_time() -> int:
	return _last_save_time

func get_last_load_time() -> int:
	return _last_load_time

func load_source_content(source_name: String) -> Dictionary:
	if not _ensure_ready():
		print("ContentPersistenceService: Service not ready")
		return {"success": false, "error": "Service not ready"}
		
	# Clean up source name
	source_name = source_name.get_basename()
	if source_name.begins_with("[📁] "):
		source_name = source_name.substr(4)
		
	print("ContentPersistenceService: Loading source: ", source_name)
	
	if not _sources.has(source_name):
		print("ContentPersistenceService: Source not found: ", source_name)
		return {"success": false, "error": "Source not found: " + source_name}
		
	var source_info = _sources[source_name]
	var file_path = source_info.path
	print("ContentPersistenceService: Loading from path: ", file_path)
	
	if not FileAccess.file_exists(file_path):
		print("ContentPersistenceService: File not found: ", file_path)
		return {"success": false, "error": "Source file not found: " + file_path}
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("ContentPersistenceService: Failed to open file: ", file_path)
		return {"success": false, "error": "Failed to open source file: " + file_path}
		
	var content = file.get_as_text()
	print("ContentPersistenceService: Raw content: ", content)
	
	var json = JSON.parse_string(content)
	if json == null:
		print("ContentPersistenceService: Failed to parse JSON from file: ", file_path)
		return {"success": false, "error": "Failed to parse source file: " + file_path}
		
	print("ContentPersistenceService: Parsed content: ", json)
	
	source_info.last_updated = Time.get_unix_time_from_system()
	_save_sources()  # Update last_updated time
	
	content_loaded.emit(source_name, json)
	return {"success": true, "error": "", "content": json}
