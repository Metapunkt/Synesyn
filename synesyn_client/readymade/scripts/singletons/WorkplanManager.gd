# WorkplanManager.gd
extends Node

const WorkplanMarkdownExportScript = preload("res://readymade/scripts/workplan_markdown_export.gd")

signal workplan_changed(workplan: Workplan)
signal workplan_list_updated(workplan_list: Array)

# Current active workplan
var current_workplan: Workplan
var current_workplan_name: String = ""
var current_workplan_path: String = ""

# Workplan management
var available_workplans: Dictionary = {}  # name -> path mapping
var workplans_directory: String = ""

func _ready():
	print("🗂️ WorkplanManager initializing...")
	# Path getters are pure; run Documents/Synesyn layout migrations once here.
	RuntimeConfig.run_storage_migrations()
	workplans_directory = RuntimeConfig.get_workplans_dir()
	_ensure_workplans_directory()
	_migrate_legacy_workplans()
	_migrate_legacy_single_workplan_file()
	_load_workplan_registry()
	_load_default_workplan()

func _ensure_workplans_directory():
	"""Ensure the workplans directory exists under Documents/Synesyn"""
	if workplans_directory.strip_edges().is_empty():
		workplans_directory = RuntimeConfig.get_workplans_dir()
	var error: Error = DirAccess.make_dir_recursive_absolute(workplans_directory)
	if error == OK or error == ERR_ALREADY_EXISTS:
		print("📁 Workplans directory: ", workplans_directory)
	else:
		push_warning("WorkplanManager: Failed to create workplans directory: " + str(error))


func _migrate_legacy_workplans() -> void:
	var legacy_dir: String = "user://workplans/"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(legacy_dir)):
		return
	var dir: DirAccess = DirAccess.open(legacy_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var dest_path: String = workplans_directory.path_join(file_name)
			if not FileAccess.file_exists(dest_path):
				# Resource files: binary-safe copy via FileAccess buffers.
				var src: FileAccess = FileAccess.open(legacy_dir.path_join(file_name), FileAccess.READ)
				if src:
					var bytes: PackedByteArray = src.get_buffer(src.get_length())
					src.close()
					DirAccess.make_dir_recursive_absolute(workplans_directory)
					var dest: FileAccess = FileAccess.open(dest_path, FileAccess.WRITE)
					if dest:
						dest.store_buffer(bytes)
						dest.close()
		file_name = dir.get_next()
	dir.list_dir_end()


func _migrate_legacy_single_workplan_file() -> void:
	"""Import the old dual-write workplan_data.tres into workplans/ once."""
	var dest_file_name: String = "default_workplan.tres"
	var dest_path: String = workplans_directory.path_join(dest_file_name)
	if FileAccess.file_exists(dest_path) or ResourceLoader.exists(dest_path):
		return

	var legacy_documents: String = Workplan.legacy_persist_path()
	var nested_legacy: String = Workplan.nested_legacy_persist_path()
	# Prefer top-level ReadyMade path; also accept nested synesyn/readymade/ and user://.
	RuntimeConfig.migrate_binary_file_if_needed(
		legacy_documents, [nested_legacy, "user://workplan_data.tres"]
	)

	var source_path: String = ""
	if FileAccess.file_exists(legacy_documents) or ResourceLoader.exists(legacy_documents):
		source_path = legacy_documents
	elif FileAccess.file_exists(nested_legacy) or ResourceLoader.exists(nested_legacy):
		source_path = nested_legacy
	elif FileAccess.file_exists("user://workplan_data.tres"):
		source_path = "user://workplan_data.tres"

	if source_path.is_empty():
		return

	var loaded: Workplan = _load_workplan_from_path(source_path)
	if loaded == null:
		# Binary copy fallback when ResourceLoader cannot interpret the path yet.
		RuntimeConfig.migrate_binary_file_if_needed(dest_path, [source_path])
		if FileAccess.file_exists(dest_path) or ResourceLoader.exists(dest_path):
			print("📦 Migrated legacy workplan_data.tres → ", dest_path)
		return

	if loaded.name.strip_edges().is_empty():
		loaded.name = "Default Workplan"
	DirAccess.make_dir_recursive_absolute(workplans_directory)
	var error: Error = ResourceSaver.save(loaded, dest_path)
	if error == OK:
		print("📦 Migrated legacy workplan_data.tres → ", dest_path)
	else:
		push_warning("WorkplanManager: Failed to migrate legacy workplan: " + str(error))

func _load_workplan_registry():
	"""Load the list of available workplans"""
	available_workplans.clear()
	
	var dir = DirAccess.open(workplans_directory)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".tres"):
				var workplan_path: String = workplans_directory.path_join(file_name)
				var loaded: Workplan = _load_workplan_from_path(workplan_path)
				var workplan_name: String = file_name.get_basename()
				if loaded != null and not String(loaded.name).strip_edges().is_empty():
					workplan_name = loaded.name
				available_workplans[workplan_name] = workplan_path
				print("📋 Found workplan: ", workplan_name, " at ", workplan_path)
			file_name = dir.get_next()
	
	print("🗂️ WorkplanManager found ", available_workplans.size(), " workplans")
	workplan_list_updated.emit(available_workplans.keys())

func _load_default_workplan():
	"""Load the default workplan or create one"""
	var default_name = "Default Workplan"
	
	# Check if we have any workplans
	if available_workplans.is_empty():
		print("📝 No workplans found, creating default workplan")
		create_new_workplan(default_name, "Default content creation workplan")
	else:
		# Load the first available workplan (could be enhanced with last-used preference)
		var first_workplan_name = available_workplans.keys()[0]
		switch_to_workplan(first_workplan_name)

func get_available_workplans() -> Array:
	"""Get list of available workplan names"""
	return available_workplans.keys()

func get_current_workplan() -> Workplan:
	"""Get the currently active workplan"""
	return current_workplan

func get_current_workplan_name() -> String:
	"""Get the name of the currently active workplan"""
	return current_workplan_name

func switch_to_workplan(workplan_name: String) -> bool:
	"""Switch to a different workplan"""
	if not available_workplans.has(workplan_name):
		push_error("WorkplanManager: Workplan not found: " + workplan_name)
		return false
	
	var workplan_path = available_workplans[workplan_name]
	var workplan = _load_workplan_from_path(workplan_path)
	
	if workplan:
		current_workplan = workplan
		current_workplan_name = workplan_name
		current_workplan_path = workplan_path
		print("🔄 Switched to workplan: ", workplan_name)
		workplan_changed.emit(current_workplan)
		return true
	else:
		push_error("WorkplanManager: Failed to load workplan: " + workplan_path)
		return false

func create_new_workplan(workplan_name: String, description: String = "") -> bool:
	"""Create a new workplan"""
	if available_workplans.has(workplan_name):
		push_error("WorkplanManager: Workplan already exists: " + workplan_name)
		return false
	
	var new_workplan = Workplan.new()
	new_workplan.name = workplan_name
	new_workplan.description = description
	new_workplan.created_date = Time.get_datetime_string_from_system()
	
	var file_name = _sanitize_filename(workplan_name) + ".tres"
	var workplan_path: String = workplans_directory.path_join(file_name)
	
	# Save the new workplan
	var error = ResourceSaver.save(new_workplan, workplan_path)
	if error != OK:
		push_error("WorkplanManager: Failed to save new workplan: " + str(error))
		return false
	
	# Add to registry and switch to it
	available_workplans[workplan_name] = workplan_path
	current_workplan = new_workplan
	current_workplan_name = workplan_name
	current_workplan_path = workplan_path
	
	print("✨ Created new workplan: ", workplan_name)
	workplan_list_updated.emit(available_workplans.keys())
	workplan_changed.emit(current_workplan)
	return true

func duplicate_workplan(source_name: String, new_name: String) -> bool:
	"""Create a copy of an existing workplan"""
	if not available_workplans.has(source_name):
		push_error("WorkplanManager: Source workplan not found: " + source_name)
		return false
	
	if available_workplans.has(new_name):
		push_error("WorkplanManager: Target workplan already exists: " + new_name)
		return false
	
	var source_path = available_workplans[source_name]
	var source_workplan = _load_workplan_from_path(source_path)
	
	if not source_workplan:
		push_error("WorkplanManager: Failed to load source workplan")
		return false
	
	# Create a duplicate
	var new_workplan = source_workplan.duplicate()
	new_workplan.name = new_name
	new_workplan.created_date = Time.get_datetime_string_from_system()
	
	var file_name = _sanitize_filename(new_name) + ".tres"
	var workplan_path: String = workplans_directory.path_join(file_name)
	
	# Save the duplicate
	var error = ResourceSaver.save(new_workplan, workplan_path)
	if error != OK:
		push_error("WorkplanManager: Failed to save duplicated workplan: " + str(error))
		return false
	
	# Add to registry
	available_workplans[new_name] = workplan_path
	
	print("📋 Duplicated workplan: ", source_name, " → ", new_name)
	workplan_list_updated.emit(available_workplans.keys())
	return true

func delete_workplan(workplan_name: String) -> bool:
	"""Delete a workplan (with safety checks)"""
	if not available_workplans.has(workplan_name):
		push_error("WorkplanManager: Workplan not found: " + workplan_name)
		return false
	
	# Prevent deleting the currently active workplan if it's the only one
	if workplan_name == current_workplan_name and available_workplans.size() == 1:
		push_error("WorkplanManager: Cannot delete the only remaining workplan")
		return false
	
	var workplan_path = available_workplans[workplan_name]
	
	# Delete the file
	if FileAccess.file_exists(workplan_path):
		var error = DirAccess.remove_absolute(workplan_path)
		if error != OK:
			push_error("WorkplanManager: Failed to delete workplan file: " + str(error))
			return false
	
	# Remove from registry
	available_workplans.erase(workplan_name)
	
	# If we deleted the current workplan, switch to another one
	if workplan_name == current_workplan_name:
		var remaining_workplans = available_workplans.keys()
		if not remaining_workplans.is_empty():
			switch_to_workplan(remaining_workplans[0])
	
	print("🗑️ Deleted workplan: ", workplan_name)
	workplan_list_updated.emit(available_workplans.keys())
	return true

func rename_workplan(old_name: String, new_name: String) -> bool:
	"""Rename an existing workplan"""
	if not available_workplans.has(old_name):
		push_error("WorkplanManager: Source workplan not found: " + old_name)
		return false
	
	if available_workplans.has(new_name):
		push_error("WorkplanManager: Target name already exists: " + new_name)
		return false
	
	var old_path = available_workplans[old_name]
	var workplan = _load_workplan_from_path(old_path)
	
	if not workplan:
		push_error("WorkplanManager: Failed to load workplan for renaming")
		return false
	
	# Update workplan name and save to new path
	workplan.name = new_name
	var new_file_name = _sanitize_filename(new_name) + ".tres"
	var new_path: String = workplans_directory.path_join(new_file_name)
	
	var error = ResourceSaver.save(workplan, new_path)
	if error != OK:
		push_error("WorkplanManager: Failed to save renamed workplan: " + str(error))
		return false
	
	# Delete old file
	DirAccess.remove_absolute(old_path)
	
	# Update registry
	available_workplans.erase(old_name)
	available_workplans[new_name] = new_path
	
	# Update current workplan if it was renamed
	if old_name == current_workplan_name:
		current_workplan_name = new_name
		current_workplan_path = new_path
	
	print("✏️ Renamed workplan: ", old_name, " → ", new_name)
	workplan_list_updated.emit(available_workplans.keys())
	return true

func export_workplan(workplan_name: String, export_path: String) -> bool:
	"""Export a workplan to a specified path (.tres resource or .md markdown)."""
	if not available_workplans.has(workplan_name):
		push_error("WorkplanManager: Workplan not found: " + workplan_name)
		return false
	
	var workplan_path = available_workplans[workplan_name]
	var workplan = _load_workplan_from_path(workplan_path)
	
	if not workplan:
		push_error("WorkplanManager: Failed to load workplan for export")
		return false

	var lower_path := export_path.to_lower()
	if lower_path.ends_with(".md") or lower_path.ends_with(".markdown"):
		return export_workplan_as_markdown(workplan_name, export_path)
	
	var error = ResourceSaver.save(workplan, export_path)
	if error != OK:
		push_error("WorkplanManager: Failed to export workplan: " + str(error))
		return false
	
	print("📤 Exported workplan: ", workplan_name, " to ", export_path)
	return true


func export_workplan_as_markdown(workplan_name: String, export_path: String) -> bool:
	"""Export a workplan as day-by-day markdown for handoff (e.g. Discord plans)."""
	if not available_workplans.has(workplan_name):
		push_error("WorkplanManager: Workplan not found: " + workplan_name)
		return false

	var workplan_path = available_workplans[workplan_name]
	var workplan = _load_workplan_from_path(workplan_path)
	if not workplan:
		push_error("WorkplanManager: Failed to load workplan for markdown export")
		return false

	var markdown: String = WorkplanMarkdownExportScript.render(workplan)
	var out_dir := export_path.get_base_dir()
	if not out_dir.is_empty() and not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)
	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file == null:
		push_error("WorkplanManager: Failed to open markdown export path: " + export_path)
		return false
	file.store_string(markdown)
	file.close()
	print("📤 Exported workplan markdown: ", workplan_name, " to ", export_path)
	return true

func import_workplan(import_path: String, new_name: String = "") -> bool:
	"""Import a workplan from a specified path"""
	if not FileAccess.file_exists(import_path):
		push_error("WorkplanManager: Import file not found: " + import_path)
		return false
	
	var workplan = ResourceLoader.load(import_path) as Workplan
	if not workplan:
		push_error("WorkplanManager: Failed to load workplan from: " + import_path)
		return false
	
	# Use provided name or derive from filename
	var import_name = new_name
	if import_name.is_empty():
		import_name = import_path.get_file().get_basename()
	
	# Ensure unique name
	var counter = 1
	var final_name = import_name
	while available_workplans.has(final_name):
		final_name = import_name + " (" + str(counter) + ")"
		counter += 1
	
	workplan.name = final_name
	
	var file_name = _sanitize_filename(final_name) + ".tres"
	var workplan_path: String = workplans_directory.path_join(file_name)
	
	var error = ResourceSaver.save(workplan, workplan_path)
	if error != OK:
		push_error("WorkplanManager: Failed to save imported workplan: " + str(error))
		return false
	
	# Add to registry
	available_workplans[final_name] = workplan_path
	
	print("📥 Imported workplan: ", final_name, " from ", import_path)
	workplan_list_updated.emit(available_workplans.keys())
	return true

func save_current_workplan():
	"""Save the current workplan to disk"""
	if current_workplan and not current_workplan_path.is_empty():
		DirAccess.make_dir_recursive_absolute(current_workplan_path.get_base_dir())
		var error = ResourceSaver.save(current_workplan, current_workplan_path)
		if error != OK:
			push_error("WorkplanManager: Failed to save current workplan: " + str(error))
		else:
			print("💾 Saved workplan: ", current_workplan_name)

func _load_workplan_from_path(path: String) -> Workplan:
	"""Load a workplan from a specific path.
	ResourceLoader.exists() alone misses some absolute Documents paths;
	FileAccess.file_exists is the fallback the dual-store bug lacked.
	"""
	if path.strip_edges().is_empty():
		return null
	var path_exists: bool = ResourceLoader.exists(path) or FileAccess.file_exists(path)
	if not path_exists:
		return null

	var workplan: Workplan = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Workplan
	if workplan:
		print("📂 Loaded workplan from: ", path)
		return workplan

	# Last-resort: open as bytes and ask ResourceLoader again after a binary copy
	# into a temporary user:// path (helps when the absolute path is not imported).
	var tmp_path: String = "user://_workplan_load_fallback.tres"
	var src: FileAccess = FileAccess.open(path, FileAccess.READ)
	if src == null:
		push_warning("WorkplanManager: File exists but could not open: " + path)
		return null
	var bytes: PackedByteArray = src.get_buffer(src.get_length())
	src.close()
	var dest: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if dest == null:
		return null
	dest.store_buffer(bytes)
	dest.close()
	workplan = ResourceLoader.load(tmp_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Workplan
	if workplan:
		print("📂 Loaded workplan via FileAccess fallback from: ", path)
	else:
		push_warning("WorkplanManager: Failed to deserialize workplan: " + path)
	return workplan

func _sanitize_filename(raw_name: String) -> String:
	"""Convert a workplan name to a safe filename"""
	var sanitized = raw_name.to_lower()
	# Replace invalid characters with underscores
	sanitized = sanitized.replace(" ", "_")
	sanitized = sanitized.replace("/", "_")
	sanitized = sanitized.replace("\\", "_")
	sanitized = sanitized.replace(":", "_")
	sanitized = sanitized.replace("*", "_")
	sanitized = sanitized.replace("?", "_")
	sanitized = sanitized.replace("\"", "_")
	sanitized = sanitized.replace("<", "_")
	sanitized = sanitized.replace(">", "_")
	sanitized = sanitized.replace("|", "_")
	return sanitized 
