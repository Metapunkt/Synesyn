extends RefCounted
class_name WorkplanCalendarReschedule
## Reschedule helpers: move publish/scheduled/deadline dates with undo stack
## and optional series expansion for recurring templates.


signal cadence_changed(warnings: Array)


var _undo_stack: Array = []  # Array of undo records
var _max_undo: int = 50


func clear_undo() -> void:
	_undo_stack.clear()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func undo_count() -> int:
	return _undo_stack.size()


func move_task_to_date(
	task: WorkplanTask,
	new_date: String,
	fields: Array = ["publish_date", "scheduled_date", "deadline"],
	preserve_time: bool = true,
	workplan: Resource = null,
	series_mode: String = "instance"
) -> Dictionary:
	"""Move a task (or series) to new_date.
	Primary fields are set to new_date. When moving publish/deadline (not start-only),
	start_date is shifted by the same day offset so work-window duration is preserved.
	series_mode: "instance" (default) | "series"
	Returns {moved: int, undo_id: int, warnings: Array, offset_days: int}.
	"""
	const DepsScript = preload("res://readymade/scripts/workplan_dependencies.gd")
	var result := {"moved": 0, "undo_id": -1, "warnings": [], "offset_days": 0}
	if task == null or new_date.strip_edges().is_empty():
		return result
	var targets: Array = [task]
	if series_mode == "series":
		targets = _collect_series(task, workplan)
	var only_start: bool = fields.size() == 1 and String(fields[0]) == "start_date"
	var snapshot: Array = []
	var offset_days: int = 0
	for target_any in targets:
		var target: WorkplanTask = target_any as WorkplanTask
		if target == null:
			continue
		var before := {
			"task": target,
			"publish_date": target.publish_date,
			"scheduled_date": target.scheduled_date,
			"deadline": target.deadline,
			"start_date": target.start_date,
			"publish_time": target.publish_time,
			"publish_timezone": target.publish_timezone,
		}
		snapshot.append(before)
		var old_anchor: String = _anchor_date_for_fields(target, fields)
		var target_offset: int = DepsScript.day_offset(old_anchor, new_date)
		if result["moved"] == 0:
			offset_days = target_offset
		for field_any in fields:
			var field_name: String = String(field_any)
			match field_name:
				"publish_date":
					target.publish_date = new_date
				"scheduled_date":
					target.scheduled_date = new_date
				"deadline":
					target.deadline = new_date
				"start_date":
					target.start_date = new_date
		# Preserve duration: shift start with publish/deadline moves (do not set it to new_date).
		if not only_start and target_offset != 0 and not target.start_date.is_empty():
			target.start_date = DepsScript.shift_date(target.start_date, target_offset)
		if not preserve_time:
			pass
		result["moved"] = int(result["moved"]) + 1
	if snapshot.is_empty():
		return result
	result["offset_days"] = offset_days
	_undo_stack.append({"snapshot": snapshot, "new_date": new_date})
	if _undo_stack.size() > _max_undo:
		_undo_stack.remove_at(0)
	result["undo_id"] = _undo_stack.size() - 1
	if workplan != null:
		const CadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")
		var warnings: Array = CadenceScript.validate(workplan)
		result["warnings"] = warnings
		cadence_changed.emit(warnings)
		if workplan.has_method("update_task"):
			workplan.update_task()
	return result


func extend_last_undo(extra_snapshots: Array) -> void:
	"""Append pre-move date snapshots (e.g. cascaded dependents) to the latest undo record."""
	if _undo_stack.is_empty() or extra_snapshots.is_empty():
		return
	var record: Dictionary = _undo_stack[_undo_stack.size() - 1]
	var snapshot: Array = record.get("snapshot", [])
	for entry_any in extra_snapshots:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		snapshot.append(entry_any)
	record["snapshot"] = snapshot


func undo_last(workplan: Resource = null) -> bool:
	if _undo_stack.is_empty():
		return false
	var record: Dictionary = _undo_stack.pop_back()
	var snapshot: Array = record.get("snapshot", [])
	for before_any in snapshot:
		var before: Dictionary = before_any
		var target: WorkplanTask = before.get("task") as WorkplanTask
		if target == null:
			continue
		target.publish_date = String(before.get("publish_date", ""))
		target.scheduled_date = String(before.get("scheduled_date", ""))
		target.deadline = String(before.get("deadline", ""))
		target.start_date = String(before.get("start_date", ""))
		target.publish_time = String(before.get("publish_time", ""))
		target.publish_timezone = String(before.get("publish_timezone", ""))
	if workplan != null:
		const CadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")
		cadence_changed.emit(CadenceScript.validate(workplan))
		if workplan.has_method("update_task"):
			workplan.update_task()
	return true


func _anchor_date_for_fields(task: WorkplanTask, fields: Array) -> String:
	if task == null:
		return ""
	for field_any in fields:
		match String(field_any):
			"publish_date":
				if not task.publish_date.is_empty():
					return task.publish_date
			"deadline":
				if not task.deadline.is_empty():
					return task.deadline
			"start_date":
				if not task.start_date.is_empty():
					return task.start_date
			"scheduled_date":
				if not task.scheduled_date.is_empty():
					return task.scheduled_date
	if not task.publish_date.is_empty():
		return task.publish_date
	if not task.deadline.is_empty():
		return task.deadline
	return task.start_date


func _collect_series(template: WorkplanTask, workplan: Resource) -> Array:
	var out: Array = [template]
	if workplan == null or not workplan.has_method("get_all_tasks"):
		return out
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null or task == template:
			continue
		if task.title == template.title and task.channel == template.channel:
			# Recurring expansion clears pattern on instances; match by title+channel.
			if not out.has(task):
				out.append(task)
	return out
