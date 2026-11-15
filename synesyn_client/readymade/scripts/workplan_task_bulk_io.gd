extends RefCounted
class_name WorkplanTaskBulkIO
## CSV / JSON bulk import-export for Workplan tasks (create + update).
## Schema is documented in docs/developer-guide/readymade-task-bulk-io.md

const WorkplanDependenciesScript = preload("res://readymade/scripts/workplan_dependencies.gd")
const WorkplanApprovalLogScript = preload("res://readymade/scripts/workplan_approval_log.gd")

const COLUMNS: Array[String] = [
	"task_id",
	"publish_date",
	"publish_time",
	"publish_timezone",
	"deadline",
	"start_date",
	"channel",
	"content_theme",
	"campaign_tag",
	"title",
	"draft",
	"status",
	"workflow_status",
	"notes",
	"depends_on",
	"assignee",
	"approval_log",
]


static func export_rows(workplan: Resource) -> Array:
	var rows: Array = []
	if workplan == null:
		return rows
	var tasks: Array = _all_tasks(workplan)
	for task_any in tasks:
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		task.ensure_task_id()
		task.migrate_content_status_from_notes()
		var tz_label: String = task.publish_timezone
		rows.append({
			"task_id": task.task_id,
			"publish_date": task.publish_date,
			"publish_time": task.publish_time,
			"publish_timezone": tz_label,
			"deadline": task.deadline,
			"start_date": task.start_date,
			"channel": task.channel,
			"content_theme": task.content_theme,
			"campaign_tag": task.campaign_tag,
			"title": task.title,
			"draft": task.generated_content,
			"status": task.get_content_status(),
			"workflow_status": task.status,
			"notes": task.notes,
			"depends_on": ";".join(WorkplanDependenciesScript.normalize_ids(task.depends_on)),
			"assignee": task.assignee,
			"approval_log": JSON.stringify(WorkplanApprovalLogScript.export_entries(task)),
		})
	return rows


static func export_csv(workplan: Resource) -> String:
	var rows: Array = export_rows(workplan)
	var lines: PackedStringArray = PackedStringArray()
	lines.append(",".join(COLUMNS))
	for row_any in rows:
		var row: Dictionary = row_any
		var cells: PackedStringArray = PackedStringArray()
		for col in COLUMNS:
			cells.append(_csv_escape(String(row.get(col, ""))))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func export_json(workplan: Resource) -> String:
	return JSON.stringify({"tasks": export_rows(workplan)}, "\t")


static func parse_csv(text: String) -> Array:
	"""Parse CSV including quoted fields that contain newlines."""
	var rows: Array = []
	var normalized: String = text.replace("\r\n", "\n").replace("\r", "\n")
	if normalized.strip_edges().is_empty():
		return rows
	var raw_rows: Array = _split_csv_records(normalized)
	if raw_rows.is_empty():
		return rows
	var header_cells: PackedStringArray = _parse_csv_line(String(raw_rows[0]))
	var header_map: Dictionary = {}
	for i in range(header_cells.size()):
		header_map[String(header_cells[i]).strip_edges().to_lower()] = i
	for row_i in range(1, raw_rows.size()):
		var raw_line: String = String(raw_rows[row_i]).strip_edges()
		if raw_line.is_empty():
			continue
		var cells: PackedStringArray = _parse_csv_line(raw_line)
		var row: Dictionary = {}
		for col in COLUMNS:
			var idx: int = int(header_map.get(col, -1))
			if idx >= 0 and idx < cells.size():
				row[col] = String(cells[idx])
			else:
				row[col] = ""
		rows.append(row)
	return rows


static func _split_csv_records(text: String) -> Array:
	"""Split CSV text into records, respecting quoted newlines."""
	var records: Array = []
	var current: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < text.length():
		var ch: String = text.substr(i, 1)
		if ch == "\"":
			current += ch
			if in_quotes and i + 1 < text.length() and text.substr(i + 1, 1) == "\"":
				current += "\""
				i += 2
				continue
			in_quotes = not in_quotes
			i += 1
			continue
		if ch == "\n" and not in_quotes:
			records.append(current)
			current = ""
			i += 1
			continue
		current += ch
		i += 1
	if not current.is_empty():
		records.append(current)
	return records


static func parse_json(text: String) -> Array:
	var rows: Array = []
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var tasks_any: Variant = parsed.get("tasks", [])
		if typeof(tasks_any) == TYPE_ARRAY:
			for item in tasks_any:
				if typeof(item) == TYPE_DICTIONARY:
					rows.append(_normalize_row(item))
	elif typeof(parsed) == TYPE_ARRAY:
		for item2 in parsed:
			if typeof(item2) == TYPE_DICTIONARY:
				rows.append(_normalize_row(item2))
	return rows


static func preview_import(workplan: Resource, text: String, format_hint: String = "") -> Dictionary:
	"""Return {created, updated, skipped, errors, actions} without mutating the workplan."""
	var result := {
		"created": 0,
		"updated": 0,
		"skipped": 0,
		"errors": [],
		"actions": [],
	}
	var rows: Array = _parse_by_hint(text, format_hint)
	if rows.is_empty() and not text.strip_edges().is_empty():
		result["errors"].append("No task rows parsed from input")
		return result
	var by_id: Dictionary = _index_by_task_id(workplan)
	var by_fallback: Dictionary = _index_by_fallback(workplan)
	for row_any in rows:
		var row: Dictionary = row_any
		var title: String = String(row.get("title", "")).strip_edges()
		if title.is_empty():
			result["skipped"] = int(result["skipped"]) + 1
			result["errors"].append("Skipped row with empty title")
			continue
		var task_id: String = String(row.get("task_id", "")).strip_edges()
		var matched: WorkplanTask = null
		var match_kind: String = "create"
		if not task_id.is_empty() and by_id.has(task_id):
			matched = by_id[task_id]
			match_kind = "update"
		else:
			var key: String = _fallback_key(
				String(row.get("publish_date", "")),
				String(row.get("channel", "")),
				title
			)
			if by_fallback.has(key):
				matched = by_fallback[key]
				match_kind = "update"
		result["actions"].append({
			"kind": match_kind,
			"row": row,
			"task": matched,
		})
		if match_kind == "create":
			result["created"] = int(result["created"]) + 1
		else:
			result["updated"] = int(result["updated"]) + 1
	return result


static func apply_import(workplan: Resource, preview: Dictionary) -> Dictionary:
	"""Apply a preview from preview_import. Mutates workplan tasks."""
	var applied := {"created": 0, "updated": 0, "errors": []}
	if workplan == null:
		applied["errors"].append("No workplan")
		return applied
	var actions: Array = preview.get("actions", [])
	for action_any in actions:
		var action: Dictionary = action_any
		var row: Dictionary = action.get("row", {})
		var kind: String = String(action.get("kind", "create"))
		if kind == "update":
			var existing: WorkplanTask = action.get("task") as WorkplanTask
			if existing == null:
				applied["errors"].append("Update target missing for %s" % String(row.get("title", "")))
				continue
			_apply_row_to_task(existing, row, false)
			applied["updated"] = int(applied["updated"]) + 1
		else:
			var task := WorkplanTask.new()
			_apply_row_to_task(task, row, true)
			var month_key: String = _month_key(task.publish_date)
			if workplan.has_method("add_task_to_month"):
				workplan.add_task_to_month(month_key, task)
			else:
				applied["errors"].append("Workplan missing add_task_to_month")
				continue
			applied["created"] = int(applied["created"]) + 1
	if workplan.has_method("update_task"):
		workplan.update_task()
	return applied


static func _apply_row_to_task(task: WorkplanTask, row: Dictionary, is_new: bool) -> void:
	var incoming_id: String = String(row.get("task_id", "")).strip_edges()
	if is_new:
		if incoming_id.is_empty():
			task.ensure_task_id()
		else:
			task.task_id = incoming_id
	elif not incoming_id.is_empty():
		task.task_id = incoming_id
	else:
		task.ensure_task_id()
	task.title = String(row.get("title", ""))
	task.publish_date = String(row.get("publish_date", ""))
	task.publish_time = String(row.get("publish_time", ""))
	task.publish_timezone = String(row.get("publish_timezone", ""))
	var deadline_raw: String = String(row.get("deadline", "")).strip_edges()
	var start_raw: String = String(row.get("start_date", "")).strip_edges()
	if not deadline_raw.is_empty():
		task.deadline = deadline_raw
	if not start_raw.is_empty():
		task.start_date = start_raw
	task.channel = String(row.get("channel", ""))
	if not task.channel.is_empty():
		task.channels = [task.channel]
	task.content_theme = String(row.get("content_theme", ""))
	task.campaign_tag = String(row.get("campaign_tag", ""))
	task.generated_content = String(row.get("draft", ""))
	task.notes = String(row.get("notes", ""))
	# CSV plans often omit core_idea; seed it so the editor can save without edits.
	var core_raw: String = String(row.get("core_idea", "")).strip_edges()
	if core_raw.is_empty():
		core_raw = task.generated_content.strip_edges()
	if core_raw.is_empty() and not task.notes.strip_edges().is_empty():
		core_raw = task.notes.strip_edges().split("\n")[0].strip_edges()
	if core_raw.is_empty():
		core_raw = task.title.strip_edges()
	if task.core_idea.strip_edges().is_empty() and not core_raw.is_empty():
		task.core_idea = core_raw
	var status_raw: String = String(row.get("status", "draft")).strip_edges().to_lower()
	if status_raw.is_empty():
		status_raw = "draft"
	task.set_content_status(status_raw)
	var workflow_raw: String = String(row.get("workflow_status", "")).strip_edges()
	if not workflow_raw.is_empty():
		task.status = workflow_raw
	WorkplanDependenciesScript.set_depends_on(task, row.get("depends_on", ""))
	task.assignee = String(row.get("assignee", "")).strip_edges()
	if not task.publish_date.is_empty():
		if task.scheduled_date.is_empty():
			task.scheduled_date = task.publish_date
		if task.deadline.is_empty():
			task.deadline = task.publish_date


static func _normalize_row(item: Dictionary) -> Dictionary:
	var row: Dictionary = {}
	for col in COLUMNS:
		row[col] = String(item.get(col, ""))
	# Accept alternate keys.
	if row["draft"].is_empty() and item.has("generated_content"):
		row["draft"] = String(item.get("generated_content", ""))
	if row["status"].is_empty() and item.has("content_status"):
		row["status"] = String(item.get("content_status", ""))
	if row["workflow_status"].is_empty() and item.has("status_workflow"):
		row["workflow_status"] = String(item.get("status_workflow", ""))
	return row


static func _parse_by_hint(text: String, format_hint: String) -> Array:
	var hint: String = format_hint.to_lower()
	if hint.ends_with(".json") or hint == "json" or text.strip_edges().begins_with("{") or text.strip_edges().begins_with("["):
		var json_rows: Array = parse_json(text)
		if not json_rows.is_empty():
			return json_rows
	return parse_csv(text)


static func _all_tasks(workplan: Resource) -> Array:
	if workplan != null and workplan.has_method("get_all_tasks"):
		return workplan.get_all_tasks()
	return []


static func _index_by_task_id(workplan: Resource) -> Dictionary:
	var out: Dictionary = {}
	for task_any in _all_tasks(workplan):
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		task.ensure_task_id()
		out[task.task_id] = task
	return out


static func _index_by_fallback(workplan: Resource) -> Dictionary:
	var out: Dictionary = {}
	for task_any in _all_tasks(workplan):
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		out[_fallback_key(task.publish_date, task.channel, task.title)] = task
	return out


static func _fallback_key(publish_date: String, channel: String, title: String) -> String:
	return "%s|%s|%s" % [
		publish_date.strip_edges().to_lower(),
		channel.strip_edges().to_lower(),
		title.strip_edges().to_lower(),
	]


static func _month_key(date_str: String) -> String:
	if date_str.length() >= 7:
		return date_str.substr(0, 7)
	return "undated"


static func _csv_escape(value: String) -> String:
	var needs_quotes: bool = (
		value.find(",") >= 0
		or value.find("\"") >= 0
		or value.find("\n") >= 0
		or value.find("\r") >= 0
	)
	var escaped: String = value.replace("\"", "\"\"")
	if needs_quotes:
		return "\"%s\"" % escaped
	return escaped


static func _parse_csv_line(line: String) -> PackedStringArray:
	var cells: PackedStringArray = PackedStringArray()
	var current: String = ""
	var in_quotes: bool = false
	var i: int = 0
	while i < line.length():
		var ch: String = line.substr(i, 1)
		if in_quotes:
			if ch == "\"":
				if i + 1 < line.length() and line.substr(i + 1, 1) == "\"":
					current += "\""
					i += 2
					continue
				in_quotes = false
				i += 1
				continue
			current += ch
			i += 1
			continue
		if ch == "\"":
			in_quotes = true
			i += 1
			continue
		if ch == ",":
			cells.append(current)
			current = ""
			i += 1
			continue
		current += ch
		i += 1
	cells.append(current)
	return cells
