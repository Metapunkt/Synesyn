# WorkplanManager.gd
extends Node

const WorkplanMarkdownExportScript = preload("res://readymade/scripts/workplan_markdown_export.gd")
const WorkplanTaskBulkIOScript = preload("res://readymade/scripts/workplan_task_bulk_io.gd")
const WorkplanCadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")

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
	if lower_path.ends_with(".csv") or lower_path.ends_with(".json"):
		# Task-level bulk export uses the named workplan (load if not current).
		var bulk_workplan: Workplan = workplan
		if current_workplan != null and current_workplan_name == workplan_name:
			bulk_workplan = current_workplan
		var body: String = ""
		if lower_path.ends_with(".csv"):
			body = WorkplanTaskBulkIOScript.export_csv(bulk_workplan)
		else:
			body = WorkplanTaskBulkIOScript.export_json(bulk_workplan)
		return _write_text_export(export_path, body)
	
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


func export_current_tasks_csv(export_path: String) -> bool:
	"""Export current workplan tasks as CSV (bulk review/edit)."""
	if current_workplan == null:
		push_error("WorkplanManager: No current workplan for CSV export")
		return false
	return _write_text_export(export_path, WorkplanTaskBulkIOScript.export_csv(current_workplan))


func export_current_tasks_json(export_path: String) -> bool:
	"""Export current workplan tasks as JSON (bulk review/edit)."""
	if current_workplan == null:
		push_error("WorkplanManager: No current workplan for JSON export")
		return false
	return _write_text_export(export_path, WorkplanTaskBulkIOScript.export_json(current_workplan))


func preview_import_tasks(text: String, format_hint: String = "") -> Dictionary:
	"""Preview create/update/skip counts before applying a CSV/JSON import."""
	if current_workplan == null:
		return {"created": 0, "updated": 0, "skipped": 0, "errors": ["No current workplan"], "actions": []}
	return WorkplanTaskBulkIOScript.preview_import(current_workplan, text, format_hint)


func apply_import_tasks_preview(preview: Dictionary) -> Dictionary:
	"""Apply a preview from preview_import_tasks to the current workplan."""
	if current_workplan == null:
		return {"created": 0, "updated": 0, "errors": ["No current workplan"]}
	var applied: Dictionary = WorkplanTaskBulkIOScript.apply_import(current_workplan, preview)
	save_current_workplan()
	return applied


func import_tasks_from_path(import_path: String, apply_now: bool = false) -> Dictionary:
	"""Load CSV/JSON from disk; return preview (and optionally apply)."""
	if not FileAccess.file_exists(import_path):
		return {"created": 0, "updated": 0, "skipped": 0, "errors": ["File not found: " + import_path], "actions": []}
	var text: String = FileAccess.get_file_as_string(import_path)
	var preview: Dictionary = preview_import_tasks(text, import_path)
	if apply_now:
		var applied: Dictionary = apply_import_tasks_preview(preview)
		preview["applied"] = applied
	return preview


func _write_text_export(export_path: String, contents: String) -> bool:
	var out_dir := export_path.get_base_dir()
	if not out_dir.is_empty() and not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)
	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file == null:
		push_error("WorkplanManager: Failed to open export path: " + export_path)
		return false
	file.store_string(contents)
	file.close()
	print("📤 Exported tasks to ", export_path)
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


## --- Custom destinations (channels) stored on the workplan -------------------
## Modes supply generic platform defaults only. Users add/rename/remove their
## own destinations per workplan; the list starts empty (neutral default).

func get_custom_channels() -> Array[String]:
	"""Return a copy of the current workplan's custom destination list."""
	var result: Array[String] = []
	if current_workplan == null:
		return result
	for channel_label in current_workplan.custom_channels:
		result.append(String(channel_label))
	return result


func set_custom_channels(channels: Array) -> bool:
	"""Replace the custom destination list (deduped, trimmed). Empty is valid."""
	if current_workplan == null:
		push_error("WorkplanManager: No current workplan for set_custom_channels")
		return false
	var cleaned: Array[String] = []
	for channel_any in channels:
		var channel_label: String = String(channel_any).strip_edges()
		if channel_label.is_empty():
			continue
		if not cleaned.has(channel_label):
			cleaned.append(channel_label)
	current_workplan.custom_channels = cleaned
	save_current_workplan()
	return true


func add_custom_channel(channel_label: String) -> bool:
	"""Add a user-defined destination. Returns false if empty or already present."""
	if current_workplan == null:
		push_error("WorkplanManager: No current workplan for add_custom_channel")
		return false
	var cleaned: String = channel_label.strip_edges()
	if cleaned.is_empty():
		return false
	if current_workplan.custom_channels.has(cleaned):
		return false
	current_workplan.custom_channels.append(cleaned)
	save_current_workplan()
	return true


func rename_custom_channel(old_label: String, new_label: String) -> bool:
	"""Rename a custom destination. Updates matching task.channel / channels."""
	if current_workplan == null:
		return false
	var old_clean: String = old_label.strip_edges()
	var new_clean: String = new_label.strip_edges()
	if old_clean.is_empty() or new_clean.is_empty():
		return false
	var idx: int = current_workplan.custom_channels.find(old_clean)
	if idx < 0:
		return false
	if new_clean != old_clean and current_workplan.custom_channels.has(new_clean):
		return false
	current_workplan.custom_channels[idx] = new_clean
	for task_any in current_workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		if task.channel == old_clean:
			task.channel = new_clean
		var updated_channels: Array[String] = []
		for ch in task.channels:
			if String(ch) == old_clean:
				updated_channels.append(new_clean)
			else:
				updated_channels.append(String(ch))
		task.channels = updated_channels
	save_current_workplan()
	return true


func remove_custom_channel(channel_label: String) -> bool:
	"""Remove a custom destination from the workplan list (tasks keep their values)."""
	if current_workplan == null:
		return false
	var cleaned: String = channel_label.strip_edges()
	var idx: int = current_workplan.custom_channels.find(cleaned)
	if idx < 0:
		return false
	current_workplan.custom_channels.remove_at(idx)
	save_current_workplan()
	return true


func move_custom_channel(from_index: int, to_index: int) -> bool:
	"""Reorder a custom destination. Used by the Manage Channels UI."""
	if current_workplan == null:
		return false
	var channels: Array[String] = current_workplan.custom_channels
	if from_index < 0 or from_index >= channels.size():
		return false
	if to_index < 0 or to_index >= channels.size():
		return false
	if from_index == to_index:
		return true
	var label: String = channels[from_index]
	channels.remove_at(from_index)
	channels.insert(to_index, label)
	current_workplan.custom_channels = channels
	save_current_workplan()
	return true


func get_effective_channels() -> Array[String]:
	"""Mode platform defaults plus the current workplan's custom destinations."""
	var combined: Array[String] = []
	if ModeManager != null:
		for channel_label in ModeManager.get_current_channels():
			if not combined.has(channel_label):
				combined.append(channel_label)
	for channel_label in get_custom_channels():
		if not combined.has(channel_label):
			combined.append(channel_label)
	return combined


func get_default_timezone() -> String:
	if current_workplan == null:
		return ""
	return String(current_workplan.default_timezone)


func set_default_timezone(timezone: String) -> bool:
	if current_workplan == null:
		return false
	current_workplan.default_timezone = timezone.strip_edges()
	save_current_workplan()
	return true


func get_viewer_timezone() -> String:
	if current_workplan == null:
		return ""
	if not String(current_workplan.viewer_timezone).strip_edges().is_empty():
		return String(current_workplan.viewer_timezone).strip_edges()
	return String(current_workplan.default_timezone).strip_edges()


func set_viewer_timezone(timezone: String) -> bool:
	if current_workplan == null:
		return false
	current_workplan.viewer_timezone = timezone.strip_edges()
	save_current_workplan()
	return true


func set_channel_cadence_cap(channel: String, max_per_week: int) -> bool:
	if current_workplan == null:
		return false
	WorkplanCadenceScript.set_cap(current_workplan, channel, max_per_week)
	save_current_workplan()
	return true


func get_channel_cadence_cap(channel: String) -> int:
	if current_workplan == null:
		return 0
	return WorkplanCadenceScript.get_cap(current_workplan, channel)


func get_cadence_warnings() -> Array:
	if current_workplan == null:
		return []
	return WorkplanCadenceScript.validate(current_workplan)


func get_cadence_validation_report() -> String:
	if current_workplan == null:
		return "No current workplan."
	return WorkplanCadenceScript.validation_report(current_workplan)

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


## --- People / assignees ------------------------------------------------------

func get_people() -> Array[Dictionary]:
	const PeopleScript = preload("res://readymade/scripts/workplan_people.gd")
	if current_workplan == null:
		var empty: Array[Dictionary] = []
		return empty
	return PeopleScript.normalize_list(current_workplan.people)


func set_people(people: Array) -> bool:
	const PeopleScript = preload("res://readymade/scripts/workplan_people.gd")
	if current_workplan == null:
		return false
	current_workplan.people = PeopleScript.normalize_list(people)
	save_current_workplan()
	return true


func add_person(person_name: String, role_label: String = "", timezone: String = "") -> bool:
	const PeopleScript = preload("res://readymade/scripts/workplan_people.gd")
	if current_workplan == null:
		return false
	var person: Dictionary = PeopleScript.normalize_person({
		"name": person_name,
		"role": role_label,
		"timezone": timezone,
	})
	if String(person.get("name", "")).is_empty():
		return false
	var existing: Array[Dictionary] = PeopleScript.normalize_list(current_workplan.people)
	for entry_any in existing:
		var entry: Dictionary = entry_any
		if String(entry.get("name", "")).to_lower() == String(person.get("name", "")).to_lower():
			return false
	existing.append(person)
	current_workplan.people = existing
	save_current_workplan()
	return true


func remove_person(person_name: String) -> bool:
	const PeopleScript = preload("res://readymade/scripts/workplan_people.gd")
	if current_workplan == null:
		return false
	var needle: String = person_name.strip_edges().to_lower()
	if needle.is_empty():
		return false
	var kept: Array[Dictionary] = []
	var removed := false
	for entry_any in PeopleScript.normalize_list(current_workplan.people):
		var entry: Dictionary = entry_any
		if String(entry.get("name", "")).to_lower() == needle:
			removed = true
			continue
		kept.append(entry)
	if not removed:
		return false
	current_workplan.people = kept
	save_current_workplan()
	return true


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
