extends RefCounted
class_name WorkplanDependencies
## Lean task dependency helpers: blocked state, cycle prevention, cascade offset.


static func normalize_ids(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	var parts: Array = []
	if raw is Array:
		parts = raw
	else:
		var text: String = String(raw).strip_edges()
		if text.is_empty():
			return out
		for piece in text.replace(";", ",").split(","):
			parts.append(piece)
	for part_any in parts:
		var id_text: String = String(part_any).strip_edges()
		if id_text.is_empty() or seen.has(id_text):
			continue
		seen[id_text] = true
		out.append(id_text)
	return out


static func set_depends_on(task: WorkplanTask, raw: Variant) -> void:
	if task == null:
		return
	task.depends_on = normalize_ids(raw)


static func is_blocked(task: WorkplanTask, workplan: Resource) -> bool:
	"""True when any predecessor exists and is not Done."""
	if task == null or workplan == null:
		return false
	var deps: Array[String] = normalize_ids(task.depends_on)
	if deps.is_empty():
		return false
	var by_id: Dictionary = _index_by_id(workplan)
	for dep_id in deps:
		var pred: WorkplanTask = by_id.get(dep_id) as WorkplanTask
		if pred == null:
			# Missing predecessor still blocks until cleared.
			return true
		if String(pred.status).strip_edges() != "Done":
			return true
	return false


static func would_create_cycle(task_id: String, new_depends: Variant, workplan: Resource) -> bool:
	"""True if assigning new_depends to task_id would introduce a cycle."""
	var self_id: String = task_id.strip_edges()
	if self_id.is_empty() or workplan == null:
		return false
	var candidates: Array[String] = normalize_ids(new_depends)
	if candidates.has(self_id):
		return true
	var by_id: Dictionary = _index_by_id(workplan)
	for cand in candidates:
		if _reaches(cand, self_id, by_id, {}):
			return true
	return false


static func get_dependents(task_id: String, workplan: Resource) -> Array:
	var out: Array = []
	var self_id: String = task_id.strip_edges()
	if self_id.is_empty() or workplan == null or not workplan.has_method("get_all_tasks"):
		return out
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		var deps: Array[String] = normalize_ids(task.depends_on)
		if deps.has(self_id):
			out.append(task)
	return out


static func day_offset(from_date: String, to_date: String) -> int:
	"""Whole-day offset (to - from). Returns 0 on parse failure."""
	var a: Dictionary = _parse_ymd(from_date)
	var b: Dictionary = _parse_ymd(to_date)
	if a.is_empty() or b.is_empty():
		return 0
	var a_unix: int = int(Time.get_unix_time_from_datetime_dict(a))
	var b_unix: int = int(Time.get_unix_time_from_datetime_dict(b))
	return int((b_unix - a_unix) / 86400)


static func shift_date(date_str: String, offset_days: int) -> String:
	if date_str.strip_edges().is_empty() or offset_days == 0:
		return date_str
	var parsed: Dictionary = _parse_ymd(date_str)
	if parsed.is_empty():
		return date_str
	var unix: int = int(Time.get_unix_time_from_datetime_dict(parsed)) + offset_days * 86400
	var shifted: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(shifted["year"]), int(shifted["month"]), int(shifted["day"])]


static func default_cascade_fields() -> Array:
	"""Fields shifted on cascade so durations (start→deadline/publish) stay intact."""
	return ["publish_date", "scheduled_date", "deadline", "start_date"]


static func cascade_fields_preserving_duration(primary_fields: Array) -> Array:
	"""Ensure start_date is included whenever non-start dates move."""
	var out: Array = []
	var seen: Dictionary = {}
	for field_any in primary_fields:
		var field_name: String = String(field_any)
		if field_name.is_empty() or seen.has(field_name):
			continue
		seen[field_name] = true
		out.append(field_name)
	var only_start: bool = out.size() == 1 and String(out[0]) == "start_date"
	if not only_start and not seen.has("start_date"):
		out.append("start_date")
	return out


static func snapshot_task_dates(task: WorkplanTask) -> Dictionary:
	if task == null:
		return {}
	return {
		"task": task,
		"publish_date": task.publish_date,
		"scheduled_date": task.scheduled_date,
		"deadline": task.deadline,
		"start_date": task.start_date,
		"publish_time": task.publish_time,
		"publish_timezone": task.publish_timezone,
	}


static func move_dependents_by_offset(
	root_task: WorkplanTask,
	offset_days: int,
	workplan: Resource,
	fields: Array = []
) -> Dictionary:
	"""Shift direct + transitive dependents by offset_days.
	Returns {moved: int, tasks: Array, snapshots: Array} — snapshots are pre-move dates for undo.
	"""
	var use_fields: Array = fields if not fields.is_empty() else default_cascade_fields()
	use_fields = cascade_fields_preserving_duration(use_fields)
	var result := {"moved": 0, "tasks": [], "snapshots": []}
	if root_task == null or workplan == null or offset_days == 0:
		return result
	root_task.ensure_task_id()
	var queue: Array = get_dependents(root_task.task_id, workplan)
	var visited: Dictionary = {}
	while not queue.is_empty():
		var dep: WorkplanTask = queue.pop_front() as WorkplanTask
		if dep == null:
			continue
		dep.ensure_task_id()
		if visited.has(dep.task_id):
			continue
		visited[dep.task_id] = true
		result["snapshots"].append(snapshot_task_dates(dep))
		for field_any in use_fields:
			var field_name: String = String(field_any)
			match field_name:
				"publish_date":
					dep.publish_date = shift_date(dep.publish_date, offset_days)
				"scheduled_date":
					dep.scheduled_date = shift_date(dep.scheduled_date, offset_days)
				"deadline":
					dep.deadline = shift_date(dep.deadline, offset_days)
				"start_date":
					dep.start_date = shift_date(dep.start_date, offset_days)
		result["moved"] = int(result["moved"]) + 1
		result["tasks"].append(dep)
		for nested in get_dependents(dep.task_id, workplan):
			queue.append(nested)
	if int(result["moved"]) > 0 and workplan.has_method("update_task"):
		workplan.update_task()
	return result


static func _reaches(start_id: String, target_id: String, by_id: Dictionary, seen: Dictionary) -> bool:
	if start_id == target_id:
		return true
	if seen.has(start_id):
		return false
	seen[start_id] = true
	var node: WorkplanTask = by_id.get(start_id) as WorkplanTask
	if node == null:
		return false
	for next_id in normalize_ids(node.depends_on):
		if _reaches(next_id, target_id, by_id, seen):
			return true
	return false


static func _index_by_id(workplan: Resource) -> Dictionary:
	var out: Dictionary = {}
	if workplan == null or not workplan.has_method("get_all_tasks"):
		return out
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		task.ensure_task_id()
		out[task.task_id] = task
	return out


static func _parse_ymd(date_str: String) -> Dictionary:
	var cleaned: String = date_str.strip_edges()
	if cleaned.length() < 10:
		return {}
	var parts: PackedStringArray = cleaned.substr(0, 10).split("-")
	if parts.size() < 3:
		return {}
	return {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 0,
		"minute": 0,
		"second": 0,
	}
