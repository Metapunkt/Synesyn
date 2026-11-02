# workplan.gd
class_name Workplan extends Resource

@export var months: Dictionary # { "Month 1": Array[WorkplanTask], "Month 2": Array[WorkplanTask], ... }
@export var name: String = "Default Workplan"
@export var description: String = ""
@export var created_date: String = ""

func _persist_path() -> String:
	var dest: String = (
		RuntimeConfig.get_readymade_data_dir().path_join("workplan_data.tres")
	)
	RuntimeConfig.migrate_binary_file_if_needed(dest, ["user://workplan_data.tres"])
	return dest

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
	"""Save workplan to persistent storage under Documents/Synesyn"""
	var save_path: String = _persist_path()
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var error = ResourceSaver.save(self, save_path)
	if error != OK:
		print("❌ Failed to save workplan: ", error)
	else:
		print("💾 Workplan saved successfully")

static func load_from_disk() -> Workplan:
	"""Load workplan from persistent storage, or create new if none exists"""
	var save_path: String = (
		RuntimeConfig.get_readymade_data_dir().path_join("workplan_data.tres")
	)
	RuntimeConfig.migrate_binary_file_if_needed(save_path, ["user://workplan_data.tres"])
	if ResourceLoader.exists(save_path) or FileAccess.file_exists(save_path):
		var loaded_workplan = ResourceLoader.load(save_path) as Workplan
		if loaded_workplan:
			print("📂 Workplan loaded from disk with %d tasks" % loaded_workplan.get_total_tasks())
			return loaded_workplan
		else:
			print("⚠️ Failed to load workplan, creating new one")
	else:
		print("📝 No saved workplan found, creating new one")
	
	return Workplan.new() 