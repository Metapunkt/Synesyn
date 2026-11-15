extends RefCounted
class_name WorkplanPeople
## Workplan people list helpers: normalize, lookup, assignee timezone.


static func normalize_person(raw: Variant) -> Dictionary:
	var out := {"name": "", "role": "", "timezone": ""}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var data: Dictionary = raw
	out["name"] = String(data.get("name", "")).strip_edges()
	out["role"] = String(data.get("role", data.get("role_label", ""))).strip_edges()
	out["timezone"] = String(data.get("timezone", "")).strip_edges()
	return out


static func normalize_list(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	if raw == null:
		return out
	var items: Array = raw if raw is Array else []
	for item_any in items:
		var person: Dictionary = normalize_person(item_any)
		var person_name: String = String(person.get("name", ""))
		if person_name.is_empty() or seen.has(person_name.to_lower()):
			continue
		seen[person_name.to_lower()] = true
		out.append(person)
	return out


static func find_person(workplan: Resource, person_name: String) -> Dictionary:
	var needle: String = person_name.strip_edges().to_lower()
	if needle.is_empty() or workplan == null:
		return {}
	for person_any in normalize_list(workplan.get("people")):
		var person: Dictionary = person_any
		if String(person.get("name", "")).strip_edges().to_lower() == needle:
			return person
	return {}


static func assignee_timezone(task: WorkplanTask, workplan: Resource) -> String:
	"""IANA zone for the task assignee when listed on the workplan; else empty."""
	if task == null:
		return ""
	var assignee_name: String = String(task.assignee).strip_edges()
	if assignee_name.is_empty():
		return ""
	var person: Dictionary = find_person(workplan, assignee_name)
	return String(person.get("timezone", "")).strip_edges()


static func format_deadline_for_assignee(
	task: WorkplanTask,
	workplan: Resource = null
) -> String:
	"""Deadline date (and optional publish time) labeled in the assignee's zone."""
	if task == null:
		return ""
	var deadline: String = task.deadline.strip_edges()
	if deadline.is_empty():
		deadline = task.publish_date.strip_edges()
	if deadline.is_empty():
		return ""
	var assignee_tz: String = assignee_timezone(task, workplan)
	if assignee_tz.is_empty():
		if task.assignee.strip_edges().is_empty():
			return deadline
		return "%s (assignee: %s)" % [deadline, task.assignee]
	# Prefer converting publish datetime into assignee zone when time is known.
	var time_str: String = task.publish_time.strip_edges()
	if time_str.is_empty():
		return "%s (%s / %s)" % [deadline, task.assignee, assignee_tz]
	const PublishTimeScript = preload("res://readymade/scripts/workplan_publish_time.gd")
	var label: String = PublishTimeScript.format_publish_label(task, workplan, assignee_tz)
	if label.is_empty():
		return "%s (%s / %s)" % [deadline, task.assignee, assignee_tz]
	return "deadline→ %s" % label


static func matches_assignee_filter(task: WorkplanTask, filter_value: String) -> bool:
	var needle: String = filter_value.strip_edges().to_lower()
	if needle.is_empty() or needle == "all":
		return true
	if task == null:
		return false
	var assignee_name: String = String(task.assignee).strip_edges().to_lower()
	if needle == "(unassigned)" or needle == "unassigned":
		return assignee_name.is_empty()
	return assignee_name == needle
