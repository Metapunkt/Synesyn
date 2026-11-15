extends RefCounted
class_name WorkplanPublishTime
## Helpers for timezone-aware publish datetimes on workplan tasks.


static func effective_timezone(task: WorkplanTask, workplan: Resource = null) -> String:
	if task != null and not task.publish_timezone.strip_edges().is_empty():
		return task.publish_timezone.strip_edges()
	if workplan != null:
		var wp_tz: Variant = workplan.get("default_timezone")
		if wp_tz != null and not String(wp_tz).strip_edges().is_empty():
			return String(wp_tz).strip_edges()
	return ""


static func viewer_timezone(workplan: Resource = null, override_zone: String = "") -> String:
	if not override_zone.strip_edges().is_empty():
		return override_zone.strip_edges()
	if workplan != null:
		var viewer: Variant = workplan.get("viewer_timezone")
		if viewer != null and not String(viewer).strip_edges().is_empty():
			return String(viewer).strip_edges()
		var default_tz: Variant = workplan.get("default_timezone")
		if default_tz != null and not String(default_tz).strip_edges().is_empty():
			return String(default_tz).strip_edges()
	return ""


static func format_publish_label(
	task: WorkplanTask,
	workplan: Resource = null,
	viewer_zone_override: String = ""
) -> String:
	"""Human-readable publish datetime; converts into viewer zone when set."""
	if task == null:
		return ""
	var date_str: String = task.publish_date
	if date_str.is_empty():
		return ""
	var time_str: String = task.publish_time.strip_edges()
	var task_tz: String = effective_timezone(task, workplan)
	var viewer_tz: String = viewer_timezone(workplan, viewer_zone_override)
	if viewer_tz.is_empty() or time_str.is_empty() or task_tz.is_empty() or viewer_tz == task_tz:
		if time_str.is_empty() and task_tz.is_empty():
			return date_str
		if time_str.is_empty():
			return "%s (%s)" % [date_str, task_tz]
		if task_tz.is_empty():
			return "%s %s" % [date_str, time_str]
		return "%s %s %s" % [date_str, time_str, task_tz]
	const TzScript = preload("res://readymade/scripts/workplan_timezone.gd")
	return TzScript.format_for_viewer(date_str, time_str, task_tz, viewer_tz)


static func convert_task_to_viewer(
	task: WorkplanTask,
	workplan: Resource = null,
	viewer_zone_override: String = ""
) -> Dictionary:
	"""Return {date, time, timezone} for the task in the viewer zone."""
	if task == null:
		return {}
	var task_tz: String = effective_timezone(task, workplan)
	var viewer_tz: String = viewer_timezone(workplan, viewer_zone_override)
	if task.publish_date.is_empty():
		return {}
	if viewer_tz.is_empty() or task_tz.is_empty() or viewer_tz == task_tz:
		return {
			"date": task.publish_date,
			"time": task.publish_time,
			"timezone": task_tz if not task_tz.is_empty() else viewer_tz,
		}
	const TzScript = preload("res://readymade/scripts/workplan_timezone.gd")
	return TzScript.convert_zones(
		task.publish_date,
		task.publish_time if not task.publish_time.is_empty() else "00:00",
		task_tz,
		viewer_tz
	)


static func set_task_publish(
	task: WorkplanTask,
	date_str: String,
	time_str: String,
	timezone: String
) -> void:
	if task == null:
		return
	task.publish_date = date_str.strip_edges()
	task.publish_time = time_str.strip_edges()
	task.publish_timezone = timezone.strip_edges()


static func set_task_publish_from_viewer(
	task: WorkplanTask,
	viewer_date: String,
	viewer_time: String,
	viewer_zone: String,
	store_zone: String = ""
) -> void:
	"""Enter a time in viewer_zone; store wall clock in store_zone (default viewer)."""
	if task == null:
		return
	var target_zone: String = store_zone.strip_edges()
	if target_zone.is_empty():
		target_zone = viewer_zone.strip_edges()
	if target_zone.is_empty() or target_zone == viewer_zone.strip_edges():
		set_task_publish(task, viewer_date, viewer_time, target_zone)
		return
	const TzScript = preload("res://readymade/scripts/workplan_timezone.gd")
	var converted: Dictionary = TzScript.convert_zones(viewer_date, viewer_time, viewer_zone, target_zone)
	set_task_publish(
		task,
		String(converted.get("date", viewer_date)),
		String(converted.get("time", viewer_time)),
		target_zone
	)
