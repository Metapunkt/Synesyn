extends RefCounted
class_name WorkplanCampaignDashboard
## Aggregate campaign / theme stats for the ReadyMade campaign dashboard.


static func build(workplan: Resource, group_by: String = "campaign") -> Dictionary:
	"""Return {groups: Array[Dictionary], totals: Dictionary, cadence: Array}.
	group_by: "campaign" | "theme"
	"""
	var result := {
		"groups": [],
		"totals": _empty_totals(),
		"cadence": [],
		"group_by": group_by,
	}
	if workplan == null or not workplan.has_method("get_all_tasks"):
		return result
	var buckets: Dictionary = {}  # key -> group dict
	var today: String = Time.get_date_string_from_system()
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		task.migrate_content_status_from_notes()
		var key: String = _group_key(task, group_by)
		if not buckets.has(key):
			buckets[key] = _empty_group(key)
		var group: Dictionary = buckets[key]
		_accumulate_task(group, task, today)
		_accumulate_task(result["totals"], task, today)
	var keys: Array = buckets.keys()
	keys.sort()
	for key_any in keys:
		result["groups"].append(buckets[key_any])
	const CadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")
	result["cadence"] = CadenceScript.validate(workplan)
	result["channel_distribution"] = _channel_distribution(workplan)
	return result


static func render_text(report: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var group_by: String = String(report.get("group_by", "campaign"))
	lines.append("# Campaign dashboard (%s)" % group_by)
	lines.append("")
	var totals: Dictionary = report.get("totals", {})
	lines.append(_format_group_block("All tasks", totals))
	lines.append("")
	for group_any in report.get("groups", []):
		var group: Dictionary = group_any
		lines.append(_format_group_block(String(group.get("key", "(none)")), group))
		lines.append("")
	var channels: Dictionary = report.get("channel_distribution", {})
	if not channels.is_empty():
		lines.append("## Channel distribution (vs cadence caps)")
		var channel_keys: Array = channels.keys()
		channel_keys.sort()
		for ch_any in channel_keys:
			var ch: String = String(ch_any)
			var info: Dictionary = channels[ch]
			var cap: int = int(info.get("cap", 0))
			var week_count: int = int(info.get("this_week", 0))
			var total_n: int = int(info.get("total", 0))
			if cap > 0:
				lines.append("- `%s`: %d total, %d this week (cap %d)%s" % [
					ch, total_n, week_count, cap,
					" ⚠ over cap" if week_count > cap else "",
				])
			else:
				lines.append("- `%s`: %d total, %d this week (no cap)" % [ch, total_n, week_count])
		lines.append("")
	var cadence: Array = report.get("cadence", [])
	if cadence.is_empty():
		lines.append("Cadence: OK")
	else:
		lines.append("Cadence warnings:")
		for w_any in cadence:
			var w: Dictionary = w_any
			lines.append("- %s" % String(w.get("message", "")))
	return "\n".join(lines)


static func _group_key(task: WorkplanTask, group_by: String) -> String:
	if group_by == "theme":
		var theme: String = task.content_theme.strip_edges()
		return theme if not theme.is_empty() else "(no theme)"
	var campaign: String = task.campaign_tag.strip_edges()
	return campaign if not campaign.is_empty() else "(no campaign)"


static func _empty_totals() -> Dictionary:
	return _empty_group("All")


static func _empty_group(key: String) -> Dictionary:
	var by_status: Dictionary = {}
	for status_id in WorkplanTask.CONTENT_STATUSES:
		by_status[status_id] = 0
	return {
		"key": key,
		"total": 0,
		"by_status": by_status,
		"upcoming": 0,
		"overdue": 0,
		"completed_workflow": 0,
		"posted": 0,
		"open_slots": 0,
		"channels": {},
		"upcoming_titles": [],
		"overdue_titles": [],
	}


static func _accumulate_task(group: Dictionary, task: WorkplanTask, today: String) -> void:
	group["total"] = int(group["total"]) + 1
	var status_id: String = task.get_content_status()
	var by_status: Dictionary = group["by_status"]
	by_status[status_id] = int(by_status.get(status_id, 0)) + 1
	if status_id == "open_slot":
		group["open_slots"] = int(group["open_slots"]) + 1
	if status_id == "posted" or task.status == "Done":
		group["posted"] = int(group["posted"]) + 1
	if task.status == "Done":
		group["completed_workflow"] = int(group["completed_workflow"]) + 1
	var date_str: String = _primary_date(task)
	if not date_str.is_empty():
		if date_str < today and task.status != "Done" and status_id != "posted":
			group["overdue"] = int(group["overdue"]) + 1
			var overdue_titles: Array = group["overdue_titles"]
			if overdue_titles.size() < 8:
				overdue_titles.append(task.title)
		elif date_str >= today:
			group["upcoming"] = int(group["upcoming"]) + 1
			var upcoming_titles: Array = group["upcoming_titles"]
			if upcoming_titles.size() < 8:
				upcoming_titles.append(task.title)
	var channel: String = task.channel.strip_edges()
	if not channel.is_empty():
		var channels: Dictionary = group["channels"]
		channels[channel] = int(channels.get(channel, 0)) + 1


static func _primary_date(task: WorkplanTask) -> String:
	if not task.publish_date.is_empty():
		return task.publish_date.substr(0, mini(10, task.publish_date.length()))
	if not task.scheduled_date.is_empty():
		return task.scheduled_date.substr(0, mini(10, task.scheduled_date.length()))
	if not task.deadline.is_empty():
		return task.deadline.substr(0, mini(10, task.deadline.length()))
	return ""


static func completion_ratio(group: Dictionary) -> float:
	var total: int = int(group.get("total", 0))
	if total <= 0:
		return 0.0
	var done: int = int(group.get("posted", 0))
	return float(done) / float(total)


static func _channel_distribution(workplan: Resource) -> Dictionary:
	const CadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")
	var out: Dictionary = {}
	var today: String = Time.get_date_string_from_system()
	var this_week: String = CadenceScript._week_key(today)
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		var channel: String = task.channel.strip_edges()
		if channel.is_empty():
			continue
		if not out.has(channel):
			out[channel] = {
				"total": 0,
				"this_week": 0,
				"cap": CadenceScript.get_cap(workplan, channel),
			}
		out[channel]["total"] = int(out[channel]["total"]) + 1
		var date_str: String = _primary_date(task)
		if not date_str.is_empty() and CadenceScript._week_key(date_str) == this_week:
			out[channel]["this_week"] = int(out[channel]["this_week"]) + 1
	return out


static func _format_group_block(title: String, group: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("## %s" % title)
	lines.append("Total: %d | Upcoming: %d | Overdue: %d | Open slots: %d" % [
		int(group.get("total", 0)),
		int(group.get("upcoming", 0)),
		int(group.get("overdue", 0)),
		int(group.get("open_slots", 0)),
	])
	lines.append("Completion (posted/Done): %.0f%%" % (completion_ratio(group) * 100.0))
	var by_status: Dictionary = group.get("by_status", {})
	var status_bits: PackedStringArray = PackedStringArray()
	for status_id in WorkplanTask.CONTENT_STATUSES:
		var n: int = int(by_status.get(status_id, 0))
		if n > 0:
			status_bits.append("%s=%d" % [status_id, n])
	if not status_bits.is_empty():
		lines.append("Status: " + ", ".join(status_bits))
	var channels: Dictionary = group.get("channels", {})
	if not channels.is_empty():
		var ch_bits: PackedStringArray = PackedStringArray()
		for ch in channels.keys():
			ch_bits.append("`%s`=%d" % [String(ch), int(channels[ch])])
		lines.append("Channels: " + ", ".join(ch_bits))
	return "\n".join(lines)
