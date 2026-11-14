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


static func format_publish_label(task: WorkplanTask, workplan: Resource = null) -> String:
	"""Human-readable publish datetime for UI and exports."""
	if task == null:
		return ""
	var date_str: String = task.publish_date
	if date_str.is_empty():
		return ""
	var time_str: String = task.publish_time.strip_edges()
	var tz: String = effective_timezone(task, workplan)
	if time_str.is_empty() and tz.is_empty():
		return date_str
	if time_str.is_empty():
		return "%s (%s)" % [date_str, tz]
	if tz.is_empty():
		return "%s %s" % [date_str, time_str]
	return "%s %s %s" % [date_str, time_str, tz]


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
