extends RefCounted
class_name WorkplanStageBoard
## Kanban columns from a workplan (workflow or content_status grouping).


const WorkplanDependenciesScript = preload("res://readymade/scripts/workplan_dependencies.gd")
const WorkplanApprovalLogScript = preload("res://readymade/scripts/workplan_approval_log.gd")

const WORKFLOW_COLUMN_IDS: Array[String] = [
	"To Do", "In Progress", "Review", "Done"
]


static func workflow_column_ids() -> Array[String]:
	return WORKFLOW_COLUMN_IDS.duplicate()


static func content_status_column_ids() -> Array[String]:
	return WorkplanTask.CONTENT_STATUSES.duplicate()


static func build_columns(workplan: Resource, board_mode: String, filters: Dictionary = {}) -> Array:
	"""Return Array of {id, title, tasks: Array[WorkplanTask]}. board_mode: workflow | content_status."""
	var column_ids: Array[String] = _column_ids_for_mode(board_mode)
	var columns: Array = []
	var buckets: Dictionary = {}
	for col_id in column_ids:
		buckets[col_id] = []
	if workplan == null or not workplan.has_method("get_all_tasks"):
		for col_id in column_ids:
			columns.append({"id": col_id, "title": _title_for_column(col_id, board_mode), "tasks": []})
		return columns
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		if not _task_matches_filters(task, filters):
			continue
		var bucket_id: String = _task_column_id(task, board_mode)
		if not buckets.has(bucket_id):
			bucket_id = column_ids[0]
		buckets[bucket_id].append(task)
	for col_id in column_ids:
		var bucket_tasks: Array = buckets[col_id]
		_sort_tasks(bucket_tasks, board_mode)
		columns.append({
			"id": col_id,
			"title": _title_for_column(col_id, board_mode),
			"tasks": bucket_tasks,
		})
	return columns


static func move_task_to_column(task: WorkplanTask, column_id: String, board_mode: String) -> bool:
	if task == null:
		return false
	var target_id: String = column_id.strip_edges()
	if board_mode == "content_status":
		var cleaned: String = target_id.to_lower()
		if not WorkplanTask.CONTENT_STATUSES.has(cleaned):
			return false
		task.set_content_status(cleaned)
		return true
	if not WORKFLOW_COLUMN_IDS.has(target_id):
		return false
	WorkplanApprovalLogScript.record_workflow_status_change(task, target_id)
	match target_id:
		"To Do":
			task.status = "To Do"
			task.completion_date = ""
		"In Progress":
			task.status = "In Progress"
			if task.start_date.is_empty():
				task.start_date = Time.get_datetime_string_from_system()
		"Review":
			task.status = "Review"
		"Done":
			task.complete_task()
		_:
			task.status = target_id
	return true


static func is_blocked(task: WorkplanTask, workplan: Resource) -> bool:
	return WorkplanDependenciesScript.is_blocked(task, workplan)


static func _column_ids_for_mode(board_mode: String) -> Array[String]:
	if board_mode == "content_status":
		return content_status_column_ids()
	return workflow_column_ids()


static func _title_for_column(column_id: String, board_mode: String) -> String:
	if board_mode == "content_status":
		return column_id.replace("_", " ").capitalize()
	return column_id


static func _task_column_id(task: WorkplanTask, board_mode: String) -> String:
	if board_mode == "content_status":
		return task.get_content_status()
	var wf: String = String(task.status).strip_edges()
	if WORKFLOW_COLUMN_IDS.has(wf):
		return wf
	return "To Do"


static func _task_matches_filters(task: WorkplanTask, filters: Dictionary) -> bool:
	var channel_needle: String = String(filters.get("channel", "")).strip_edges()
	if not channel_needle.is_empty() and channel_needle != "(any)":
		var channel_ok: bool = (
			task.channel == channel_needle or task.channels.has(channel_needle)
		)
		if not channel_ok:
			return false
	var assignee_needle: String = String(filters.get("assignee", "")).strip_edges()
	if not assignee_needle.is_empty() and assignee_needle != "(any)":
		if task.assignee.strip_edges() != assignee_needle:
			return false
	var search_needle: String = String(filters.get("search", "")).strip_edges().to_lower()
	if not search_needle.is_empty():
		var haystack: String = (
			task.title + " " + task.core_idea + " " + task.notes + " " + task.channel
		).to_lower()
		if haystack.find(search_needle) < 0:
			return false
	return true


static func _sort_tasks(tasks: Array, _board_mode: String) -> void:
	tasks.sort_custom(Callable(WorkplanStageBoard, "_compare_tasks_for_sort"))


static func _compare_tasks_for_sort(a: Variant, b: Variant) -> bool:
	var ta: WorkplanTask = a as WorkplanTask
	var tb: WorkplanTask = b as WorkplanTask
	if ta == null or tb == null:
		return false
	var title_a: String = ta.title.to_lower()
	var title_b: String = tb.title.to_lower()
	if title_a == title_b:
		return ta.task_id < tb.task_id
	return title_a < title_b