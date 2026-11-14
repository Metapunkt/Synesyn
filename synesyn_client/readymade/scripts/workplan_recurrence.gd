extends RefCounted
class_name WorkplanRecurrence
## Expand a template task with weekly recurrence into dated WorkplanTask instances.


static func expand_weekly_instances(template: WorkplanTask) -> Array:
	"""Return dated clones for each matching weekday up to recurring_end_date.
	Does not include the template itself unless its publish_date is a match day.
	"""
	var out: Array = []
	if template == null:
		return out
	var pattern: String = template.recurring_pattern.strip_edges().to_lower()
	if pattern != "weekly" and pattern != "week":
		return out
	var weekdays: Array[int] = []
	for wd_any in template.recurring_weekdays:
		var wd: int = int(wd_any)
		if wd >= 0 and wd <= 6 and not weekdays.has(wd):
			weekdays.append(wd)
	if weekdays.is_empty():
		return out
	var start_date: String = template.publish_date
	if start_date.is_empty():
		start_date = template.scheduled_date
	if start_date.is_empty():
		start_date = Time.get_date_string_from_system()
	var end_date: String = template.recurring_end_date.strip_edges()
	if end_date.is_empty():
		end_date = _add_days(start_date, 28)
	var cursor: String = start_date
	var guard: int = 0
	while cursor <= end_date and guard < 400:
		guard += 1
		var weekday: int = _iso_weekday(cursor)  # 0=Mon .. 6=Sun
		if weekdays.has(weekday):
			var instance: WorkplanTask = template.clone()
			instance.ensure_task_id()
			instance.publish_date = cursor
			instance.scheduled_date = cursor
			instance.deadline = cursor
			instance.recurring_pattern = "none"
			instance.recurring_weekdays = []
			instance.recurring_end_date = ""
			# Avoid duplicating the template's own date when expanding in place.
			if cursor == start_date and template.publish_date == start_date:
				pass
			else:
				out.append(instance)
		cursor = _add_days(cursor, 1)
	# If template date itself matches a weekday, include a dated copy only when
	# the caller asked for full range including start — include start match as
	# first instance when template.publish_date is empty of pattern expansion intent.
	# Standard: include all matching days in [start, end], including start.
	var with_start: Array = []
	cursor = start_date
	guard = 0
	while cursor <= end_date and guard < 400:
		guard += 1
		var weekday2: int = _iso_weekday(cursor)
		if weekdays.has(weekday2):
			var instance2: WorkplanTask = template.clone()
			instance2.ensure_task_id()
			instance2.publish_date = cursor
			instance2.scheduled_date = cursor
			instance2.deadline = cursor
			instance2.recurring_pattern = "none"
			instance2.recurring_weekdays.clear()
			instance2.recurring_end_date = ""
			with_start.append(instance2)
		cursor = _add_days(cursor, 1)
	return with_start


static func apply_weekly_to_task(
	task: WorkplanTask,
	weekdays: Array,
	end_date: String
) -> void:
	"""Stamp recurrence fields on a template task (does not expand)."""
	if task == null:
		return
	task.recurring_pattern = "weekly"
	var cleaned: Array[int] = []
	for wd_any in weekdays:
		var wd: int = int(wd_any)
		if wd >= 0 and wd <= 6 and not cleaned.has(wd):
			cleaned.append(wd)
	task.recurring_weekdays = cleaned
	task.recurring_end_date = end_date.strip_edges()


static func expand_into_workplan(workplan: Resource, template: WorkplanTask) -> int:
	"""Expand template into dated instances and add them to the workplan. Returns count added."""
	if workplan == null or template == null:
		return 0
	var instances: Array = expand_weekly_instances(template)
	var added: int = 0
	for inst_any in instances:
		var inst: WorkplanTask = inst_any as WorkplanTask
		if inst == null:
			continue
		# Skip if an identical date+channel+title already exists.
		if _has_same_slot(workplan, inst):
			continue
		var month_key: String = inst.publish_date.substr(0, 7) if inst.publish_date.length() >= 7 else "undated"
		if workplan.has_method("add_task_to_month"):
			workplan.add_task_to_month(month_key, inst)
			added += 1
	return added


static func _has_same_slot(workplan: Resource, candidate: WorkplanTask) -> bool:
	if not workplan.has_method("get_all_tasks"):
		return false
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		if (
			task.publish_date == candidate.publish_date
			and task.channel == candidate.channel
			and task.title == candidate.title
		):
			return true
	return false


static func _iso_weekday(date_str: String) -> int:
	"""Return 0=Monday .. 6=Sunday for YYYY-MM-DD."""
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return 0
	var dict := {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 12,
		"minute": 0,
		"second": 0,
	}
	var unix: int = int(Time.get_unix_time_from_datetime_dict(dict))
	var full: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	# Godot weekday: 0=Sunday .. 6=Saturday → convert to ISO Mon=0.
	var godot_wd: int = int(full.get("weekday", 0))
	return (godot_wd + 6) % 7


static func _add_days(date_str: String, days: int) -> String:
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return date_str
	var dict := {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 12,
		"minute": 0,
		"second": 0,
	}
	var unix: int = int(Time.get_unix_time_from_datetime_dict(dict)) + (days * 86400)
	var next: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(next.year), int(next.month), int(next.day)]
