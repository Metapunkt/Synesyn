extends RefCounted
class_name WorkplanMarkdownExport
## Pure helpers to render a Workplan as day-by-day markdown for content handoff.


static func render(workplan: Resource) -> String:
	if workplan == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	var plan_name: String = String(workplan.get("name")) if workplan.get("name") != null else "Workplan"
	var plan_desc: String = String(workplan.get("description")) if workplan.get("description") != null else ""
	lines.append("# %s" % plan_name)
	lines.append("")
	if not plan_desc.is_empty():
		lines.append(plan_desc)
		lines.append("")
	lines.append("Generated from ReadyMade Workplan export.")
	lines.append("")

	var tasks: Array = _collect_sorted_tasks(workplan)
	if tasks.is_empty():
		lines.append("_No tasks in this workplan._")
		lines.append("")
		return "\n".join(lines)

	lines.append("| Date | Channel | Theme | Title | Plan status |")
	lines.append("| --- | --- | --- | --- | --- |")
	for task_any in tasks:
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		var date_str: String = _primary_date(task)
		var channel_str: String = task.channel if not task.channel.is_empty() else "(unset)"
		var theme_str: String = task.content_theme if not task.content_theme.is_empty() else "(unset)"
		var plan_status: String = content_plan_status(task)
		lines.append("| %s | `%s` | %s | %s | %s |" % [
			date_str,
			channel_str,
			theme_str,
			task.title.replace("|", "/"),
			plan_status,
		])
	lines.append("")

	for task_any2 in tasks:
		var task2: WorkplanTask = task_any2 as WorkplanTask
		if task2 == null:
			continue
		lines.append("## %s — %s" % [_primary_date(task2), task2.title])
		lines.append("")
		lines.append("- **Channel:** `%s`" % (task2.channel if not task2.channel.is_empty() else "(unset)"))
		lines.append("- **Theme:** %s" % (task2.content_theme if not task2.content_theme.is_empty() else "(unset)"))
		lines.append("- **Campaign:** %s" % (task2.campaign_tag if not task2.campaign_tag.is_empty() else "(none)"))
		lines.append("- **Plan status:** %s" % content_plan_status(task2))
		lines.append("- **Publish:** %s" % _publish_label(task2, workplan))
		lines.append("- **Workflow:** %s" % task2.status)
		if not task2.notes.is_empty():
			lines.append("- **Notes / source:** %s" % task2.notes.replace("\n", " · "))
		lines.append("")
		var body: String = task2.generated_content.strip_edges()
		if body.is_empty():
			body = "_No draft yet._"
		lines.append(body)
		lines.append("")
	return "\n".join(lines)


static func content_plan_status(task: WorkplanTask) -> String:
	if task == null:
		return "draft"
	# Prefer first-class field; migrate legacy STATUS: notes once.
	task.migrate_content_status_from_notes()
	var field_status: String = task.get_content_status()
	if field_status != "draft":
		return field_status
	# Heuristics only when still at default draft.
	if task.title.findn("OPEN SLOT") >= 0:
		return "open_slot"
	if task.notes.findn("PLACEHOLDER") >= 0 or task.generated_content.findn("PLACEHOLDER") >= 0:
		return "placeholder"
	if task.title.findn("PLACEHOLDER") >= 0:
		return "placeholder"
	return field_status


static func _collect_sorted_tasks(workplan: Resource) -> Array:
	var out: Array = []
	var months: Dictionary = workplan.get("months") as Dictionary if workplan.get("months") != null else {}
	for month_key in months.keys():
		var month_tasks: Array = months[month_key] as Array
		for task_any in month_tasks:
			if task_any is WorkplanTask:
				out.append(task_any)
	out.sort_custom(func(a: WorkplanTask, b: WorkplanTask) -> bool:
		return _primary_date(a) < _primary_date(b)
	)
	return out


static func _primary_date(task: WorkplanTask) -> String:
	if not task.publish_date.is_empty():
		return task.publish_date
	if not task.scheduled_date.is_empty():
		return task.scheduled_date
	if not task.deadline.is_empty():
		return task.deadline
	return "undated"


static func _publish_label(task: WorkplanTask, workplan: Resource) -> String:
	const PublishTimeScript = preload("res://readymade/scripts/workplan_publish_time.gd")
	var label: String = PublishTimeScript.format_publish_label(task, workplan)
	if label.is_empty():
		return "(unset)"
	return label
