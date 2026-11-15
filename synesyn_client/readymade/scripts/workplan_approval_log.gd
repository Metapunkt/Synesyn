extends RefCounted
class_name WorkplanApprovalLog
## Append-only approval / status-change ledger on WorkplanTask.approval_log.


static func append_change(
	task: WorkplanTask,
	from_status: String,
	to_status: String,
	person: String = "",
	note: String = ""
) -> void:
	if task == null:
		return
	var from_val: String = from_status.strip_edges()
	var to_val: String = to_status.strip_edges()
	if from_val == to_val:
		return
	var entry: Dictionary = {
		"from": from_val,
		"to": to_val,
		"at": Time.get_datetime_string_from_system(),
		"person": person.strip_edges(),
		"note": note.strip_edges(),
	}
	task.approval_log.append(entry)


static func record_content_status_change(
	task: WorkplanTask,
	new_status: String,
	person: String = "",
	note: String = ""
) -> void:
	if task == null:
		return
	var cleaned: String = new_status.strip_edges().to_lower()
	if not WorkplanTask.CONTENT_STATUSES.has(cleaned):
		cleaned = "draft"
	var from_val: String = task.get_content_status()
	if from_val == cleaned:
		return
	append_change(task, from_val, cleaned, person, note)


static func record_workflow_status_change(
	task: WorkplanTask,
	new_status: String,
	person: String = "",
	note: String = ""
) -> void:
	if task == null:
		return
	var to_val: String = new_status.strip_edges()
	var from_val: String = String(task.status).strip_edges()
	if from_val == to_val:
		return
	append_change(task, from_val, to_val, person, note)


static func format_entries(task: WorkplanTask) -> String:
	if task == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for entry_any in task.approval_log:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var line: String = "%s → %s @ %s" % [
			String(entry.get("from", "")),
			String(entry.get("to", "")),
			String(entry.get("at", "")),
		]
		var person: String = String(entry.get("person", "")).strip_edges()
		var note_text: String = String(entry.get("note", "")).strip_edges()
		if not person.is_empty():
			line += " (%s)" % person
		if not note_text.is_empty():
			line += " — %s" % note_text
		lines.append(line)
	return "\n".join(lines)


static func export_entries(task: WorkplanTask) -> Array:
	var out: Array = []
	if task == null:
		return out
	for entry_any in task.approval_log:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		out.append({
			"from": String(entry.get("from", "")),
			"to": String(entry.get("to", "")),
			"at": String(entry.get("at", "")),
			"person": String(entry.get("person", "")),
			"note": String(entry.get("note", "")),
		})
	return out