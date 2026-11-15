# workplan.gd
class_name Workplan extends Resource

@export var months: Dictionary # { "Month 1": Array[WorkplanTask], "Month 2": Array[WorkplanTask], ... }
@export var name: String = "Default Workplan"
@export var description: String = ""
@export var created_date: String = ""
## User-defined destinations (Discord channels, blogs, etc.). Empty by default —
## never pre-filled with org-specific channel lists. Persisted with the workplan.
@export var custom_channels: Array[String] = []
## Default IANA timezone for publish times (e.g. Europe/Oslo). Empty = unset.
@export var default_timezone: String = ""
## Viewer IANA zone for calendar/list display (empty = use default_timezone).
@export var viewer_timezone: String = ""
## Per-channel weekly cadence caps: { "#general": 2 }. Empty = no caps.
@export var channel_cadence_caps: Dictionary = {}
## People on this workplan: [{name, role, timezone}, ...]. Empty by default.
@export var people: Array[Dictionary] = []

## Legacy dual-write path under the ReadyMade app folder
## (Documents/Synesyn/readymade/workplan_data.tres after the top-level move).
## Persistence is owned by WorkplanManager under readymade/workplans/.
## Kept only so callers and migration helpers can resolve the old location.
static func legacy_persist_path() -> String:
	return RuntimeConfig.get_readymade_data_dir().path_join("workplan_data.tres")


## Nested pre-move path: Documents/Synesyn/synesyn/readymade/workplan_data.tres
static func nested_legacy_persist_path() -> String:
	return RuntimeConfig.get_legacy_readymade_data_dir().path_join("workplan_data.tres")

func _init():
	if created_date.is_empty():
		created_date = Time.get_datetime_string_from_system()
	if months.is_empty():
		months = {}

func add_task_to_month(month: String, task: WorkplanTask):
	if not months.has(month):
		months[month] = []
	months[month].append(task)
	save_to_disk()

func remove_task_from_month(month: String, task: WorkplanTask):
	if months.has(month):
		var tasks_array = months[month] as Array
		var index = tasks_array.find(task)
		if index >= 0:
			tasks_array.remove_at(index)
			save_to_disk()

func update_task():
	"""Call this whenever a task is modified to trigger persistence"""
	save_to_disk()

func get_all_tasks() -> Array:
	var all_tasks: Array = []
	for month_key in months.keys():
		var month_tasks = months[month_key] as Array
		for task in month_tasks:
			all_tasks.append(task)
	return all_tasks

func get_tasks_by_status(status: String) -> Array:
	var filtered_tasks: Array = []
	var all_tasks = get_all_tasks()
	for task in all_tasks:
		if task.status == status:
			filtered_tasks.append(task)
	return filtered_tasks

func get_total_tasks() -> int:
	return get_all_tasks().size()

func get_completed_tasks() -> int:
	return get_tasks_by_status("Done").size()

func get_in_progress_tasks() -> int:
	return get_tasks_by_status("In Progress").size()

func get_completion_percentage() -> float:
	var total = get_total_tasks()
	if total == 0:
		return 0.0
	return (get_completed_tasks() / float(total)) * 100.0

func save_to_disk():
	"""Persist via WorkplanManager only — no dual write to workplan_data.tres."""
	var manager: Node = _resolve_workplan_manager()
	if manager != null and manager.has_method("save_current_workplan"):
		manager.save_current_workplan()
		return
	push_warning(
		"Workplan.save_to_disk: WorkplanManager unavailable; skipping write "
		+ "(legacy workplan_data.tres dual-write removed)"
	)

static func load_from_disk() -> Workplan:
	"""Load via WorkplanManager when available; otherwise try legacy once."""
	var manager: Node = _resolve_workplan_manager_static()
	if manager != null and manager.has_method("get_current_workplan"):
		var current: Workplan = manager.get_current_workplan()
		if current != null:
			return current

	# One-shot legacy read for callers that run before WorkplanManager is ready.
	var legacy_path: String = legacy_persist_path()
	RuntimeConfig.migrate_binary_file_if_needed(
		legacy_path, ["user://workplan_data.tres"]
	)
	if ResourceLoader.exists(legacy_path) or FileAccess.file_exists(legacy_path):
		var loaded_workplan: Workplan = ResourceLoader.load(legacy_path) as Workplan
		if loaded_workplan:
			print("📂 Workplan loaded from legacy path with %d tasks" % loaded_workplan.get_total_tasks())
			return loaded_workplan
		print("⚠️ Failed to load legacy workplan, creating new one")
	else:
		print("📝 No saved workplan found, creating new one")

	return Workplan.new()

func _resolve_workplan_manager() -> Node:
	return _resolve_workplan_manager_static()

static func _resolve_workplan_manager_static() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("WorkplanManager")
