extends RefCounted
class_name WorkplanCadence
## Per-channel weekly cadence caps with non-blocking validation warnings.


static func set_cap(workplan: Resource, channel: String, max_per_week: int) -> void:
	if workplan == null:
		return
	var cleaned: String = channel.strip_edges()
	if cleaned.is_empty():
		return
	var caps: Dictionary = workplan.get("channel_cadence_caps") as Dictionary
	if caps == null:
		caps = {}
	if max_per_week <= 0:
		caps.erase(cleaned)
	else:
		caps[cleaned] = max_per_week
	workplan.set("channel_cadence_caps", caps)


static func get_cap(workplan: Resource, channel: String) -> int:
	if workplan == null:
		return 0
	var caps: Dictionary = workplan.get("channel_cadence_caps") as Dictionary
	if caps == null:
		return 0
	return int(caps.get(channel.strip_edges(), 0))


static func validate(workplan: Resource) -> Array:
	"""Return warning dictionaries: {channel, week_start, count, cap, message}."""
	var warnings: Array = []
	if workplan == null or not workplan.has_method("get_all_tasks"):
		return warnings
	var caps: Dictionary = workplan.get("channel_cadence_caps") as Dictionary
	if caps == null or caps.is_empty():
		return warnings
	# Count posts per channel per ISO week (Mon-start week key YYYY-Www).
	var counts: Dictionary = {}  # "channel|week" -> count
	for task_any in workplan.get_all_tasks():
		var task: WorkplanTask = task_any as WorkplanTask
		if task == null:
			continue
		var channel: String = task.channel.strip_edges()
		if channel.is_empty() or not caps.has(channel):
			continue
		var date_str: String = task.publish_date
		if date_str.is_empty():
			date_str = task.scheduled_date
		if date_str.is_empty():
			continue
		var week_key: String = _week_key(date_str)
		var map_key: String = "%s|%s" % [channel, week_key]
		counts[map_key] = int(counts.get(map_key, 0)) + 1
	for map_key2 in counts.keys():
		var parts: PackedStringArray = String(map_key2).split("|")
		if parts.size() < 2:
			continue
		var channel2: String = parts[0]
		var week2: String = parts[1]
		var cap: int = int(caps.get(channel2, 0))
		var count: int = int(counts[map_key2])
		if cap > 0 and count > cap:
			warnings.append({
				"channel": channel2,
				"week_start": week2,
				"count": count,
				"cap": cap,
				"message": "%s has %d posts in week %s (cap %d)" % [channel2, count, week2, cap],
			})
	return warnings


static func validation_report(workplan: Resource) -> String:
	var warnings: Array = validate(workplan)
	if warnings.is_empty():
		return "Cadence OK — no channel weekly caps exceeded."
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Cadence warnings (%d):" % warnings.size())
	for warning_any in warnings:
		var warning: Dictionary = warning_any
		lines.append("- %s" % String(warning.get("message", "")))
	return "\n".join(lines)


static func _week_key(date_str: String) -> String:
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
	var unix: int = int(Time.get_unix_time_from_datetime_dict(dict))
	var full: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	var godot_wd: int = int(full.get("weekday", 0))  # 0=Sun
	var iso_wd: int = (godot_wd + 6) % 7  # 0=Mon
	var monday_unix: int = unix - (iso_wd * 86400)
	var monday: Dictionary = Time.get_datetime_dict_from_unix_time(monday_unix)
	return "%04d-%02d-%02d" % [int(monday.year), int(monday.month), int(monday.day)]
