extends RefCounted
class_name WorkplanTimezone
## DST-aware conversion between IANA zones for ReadyMade publish times.
## Godot Time has no IANA table; this module embeds common zone rules.
## Unknown zones fall back to a fixed offset of 0 (UTC) with a warning flag.


enum DstRule {
	NONE = 0,
	EU = 1,  # Last Sunday March 01:00 UTC → last Sunday Oct 01:00 UTC
	US = 2,  # 2nd Sunday March 02:00 local → 1st Sunday Nov 02:00 local
	AU = 3,  # 1st Sunday Oct 02:00 local → 1st Sunday Apr 03:00 local (southern)
}


## zone_id -> {std: minutes east of UTC, dst: DstRule, dst_delta: minutes}
static var ZONE_TABLE: Dictionary = {
	"UTC": {"std": 0, "dst": DstRule.NONE, "dst_delta": 0},
	"Etc/UTC": {"std": 0, "dst": DstRule.NONE, "dst_delta": 0},
	"Europe/London": {"std": 0, "dst": DstRule.EU, "dst_delta": 60},
	"Europe/Oslo": {"std": 60, "dst": DstRule.EU, "dst_delta": 60},
	"Europe/Berlin": {"std": 60, "dst": DstRule.EU, "dst_delta": 60},
	"Europe/Paris": {"std": 60, "dst": DstRule.EU, "dst_delta": 60},
	"Europe/Stockholm": {"std": 60, "dst": DstRule.EU, "dst_delta": 60},
	"Europe/Copenhagen": {"std": 60, "dst": DstRule.EU, "dst_delta": 60},
	"Europe/Amsterdam": {"std": 60, "dst": DstRule.EU, "dst_delta": 60},
	"America/New_York": {"std": -300, "dst": DstRule.US, "dst_delta": 60},
	"America/Chicago": {"std": -360, "dst": DstRule.US, "dst_delta": 60},
	"America/Denver": {"std": -420, "dst": DstRule.US, "dst_delta": 60},
	"America/Los_Angeles": {"std": -480, "dst": DstRule.US, "dst_delta": 60},
	"America/Toronto": {"std": -300, "dst": DstRule.US, "dst_delta": 60},
	"America/Sao_Paulo": {"std": -180, "dst": DstRule.NONE, "dst_delta": 0},
	# Africa: most zones have no DST. Lagos (WAT) was missing and silently
	# fell back to UTC, shifting viewer labels by an hour vs Europe/Oslo in winter.
	"Africa/Lagos": {"std": 60, "dst": DstRule.NONE, "dst_delta": 0},
	"Africa/Johannesburg": {"std": 120, "dst": DstRule.NONE, "dst_delta": 0},
	"Africa/Nairobi": {"std": 180, "dst": DstRule.NONE, "dst_delta": 0},
	"Africa/Cairo": {"std": 120, "dst": DstRule.NONE, "dst_delta": 0},
	"Asia/Tokyo": {"std": 540, "dst": DstRule.NONE, "dst_delta": 0},
	"Asia/Shanghai": {"std": 480, "dst": DstRule.NONE, "dst_delta": 0},
	"Asia/Kolkata": {"std": 330, "dst": DstRule.NONE, "dst_delta": 0},
	"Australia/Sydney": {"std": 600, "dst": DstRule.AU, "dst_delta": 60},
	"Pacific/Auckland": {"std": 720, "dst": DstRule.AU, "dst_delta": 60},
}


static func known_zones() -> Array[String]:
	var out: Array[String] = []
	for key in ZONE_TABLE.keys():
		out.append(String(key))
	out.sort()
	return out


static func is_known(zone_id: String) -> bool:
	return ZONE_TABLE.has(zone_id.strip_edges())


static func resolve_zone(zone_id: String) -> Dictionary:
	var cleaned: String = zone_id.strip_edges()
	if cleaned.is_empty():
		return {"std": 0, "dst": DstRule.NONE, "dst_delta": 0, "known": false}
	if ZONE_TABLE.has(cleaned):
		var info: Dictionary = ZONE_TABLE[cleaned].duplicate()
		info["known"] = true
		return info
	# Accept UTC±HH:MM / GMT±HH:MM
	var fixed: int = _parse_fixed_offset(cleaned)
	if fixed != -99999:
		return {"std": fixed, "dst": DstRule.NONE, "dst_delta": 0, "known": true}
	return {"std": 0, "dst": DstRule.NONE, "dst_delta": 0, "known": false}


static func offset_minutes_at_unix(zone_id: String, unix_utc: int) -> int:
	var info: Dictionary = resolve_zone(zone_id)
	var std: int = int(info.get("std", 0))
	var rule: int = int(info.get("dst", DstRule.NONE))
	var delta: int = int(info.get("dst_delta", 0))
	if rule == DstRule.NONE or delta == 0:
		return std
	if _is_dst(rule, unix_utc, std):
		return std + delta
	return std


static func local_to_unix(date_str: String, time_str: String, zone_id: String) -> int:
	"""Interpret date+time as wall clock in zone_id; return approximate UTC unix."""
	var parts: PackedStringArray = date_str.split("-")
	if parts.size() < 3:
		return 0
	var hour := 0
	var minute := 0
	var tp: PackedStringArray = time_str.split(":")
	if tp.size() >= 2:
		hour = int(tp[0])
		minute = int(tp[1])
	var local_as_utc := {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": hour,
		"minute": minute,
		"second": 0,
	}
	var naive_unix: int = int(Time.get_unix_time_from_datetime_dict(local_as_utc))
	# Iterate once: guess offset at naive, then refine (handles DST transitions).
	var offset1: int = offset_minutes_at_unix(zone_id, naive_unix)
	var utc1: int = naive_unix - offset1 * 60
	var offset2: int = offset_minutes_at_unix(zone_id, utc1)
	return naive_unix - offset2 * 60


static func unix_to_local(unix_utc: int, zone_id: String) -> Dictionary:
	var offset: int = offset_minutes_at_unix(zone_id, unix_utc)
	var local_unix: int = unix_utc + offset * 60
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(local_unix)
	return {
		"date": "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)],
		"time": "%02d:%02d" % [int(d.hour), int(d.minute)],
		"timezone": zone_id,
		"offset_minutes": offset,
	}


static func convert_zones(
	date_str: String,
	time_str: String,
	from_zone: String,
	to_zone: String
) -> Dictionary:
	"""Convert wall time from from_zone to to_zone. Returns {date, time, timezone, known}."""
	var from_clean: String = from_zone.strip_edges()
	var to_clean: String = to_zone.strip_edges()
	if from_clean.is_empty():
		from_clean = "UTC"
	if to_clean.is_empty():
		to_clean = from_clean
	var unix_utc: int = local_to_unix(date_str, time_str if not time_str.is_empty() else "00:00", from_clean)
	var local: Dictionary = unix_to_local(unix_utc, to_clean)
	local["known"] = is_known(from_clean) and is_known(to_clean)
	local["source_timezone"] = from_clean
	return local


static func format_for_viewer(
	date_str: String,
	time_str: String,
	task_zone: String,
	viewer_zone: String
) -> String:
	if date_str.is_empty():
		return ""
	if time_str.is_empty():
		if viewer_zone.is_empty() or viewer_zone == task_zone:
			return date_str if task_zone.is_empty() else "%s (%s)" % [date_str, task_zone]
		return "%s (%s → %s)" % [date_str, task_zone, viewer_zone]
	if viewer_zone.is_empty() or viewer_zone == task_zone or task_zone.is_empty():
		var tz: String = task_zone if not task_zone.is_empty() else viewer_zone
		return "%s %s %s" % [date_str, time_str, tz] if not tz.is_empty() else "%s %s" % [date_str, time_str]
	var converted: Dictionary = convert_zones(date_str, time_str, task_zone, viewer_zone)
	var label: String = "%s %s %s (from %s %s %s)" % [
		String(converted.get("date", "")),
		String(converted.get("time", "")),
		viewer_zone,
		date_str,
		time_str,
		task_zone,
	]
	if not bool(converted.get("known", true)):
		label += " ⚠ unknown zone treated as UTC"
	return label


static func _is_dst(rule: int, unix_utc: int, std_offset_minutes: int) -> bool:
	var year: int = int(Time.get_datetime_dict_from_unix_time(unix_utc).year)
	match rule:
		DstRule.EU:
			var start: int = _last_sunday_utc(year, 3, 1)  # 01:00 UTC
			var end_u: int = _last_sunday_utc(year, 10, 1)
			return unix_utc >= start and unix_utc < end_u
		DstRule.US:
			# Transitions are in local standard time; convert boundaries to UTC.
			var start_local: int = _nth_weekday_local(year, 3, 2, 0, 2, 0)  # 2nd Sun Mar 02:00
			var end_local: int = _nth_weekday_local(year, 11, 1, 0, 2, 0)  # 1st Sun Nov 02:00
			var start_utc: int = start_local - std_offset_minutes * 60
			var end_utc: int = end_local - (std_offset_minutes + 60) * 60  # ends from DST
			return unix_utc >= start_utc and unix_utc < end_utc
		DstRule.AU:
			# Southern hemisphere: DST roughly Oct → Apr.
			var start_local: int = _nth_weekday_local(year, 10, 1, 0, 2, 0)
			var end_local: int = _nth_weekday_local(year, 4, 1, 0, 3, 0)
			var start_utc: int = start_local - std_offset_minutes * 60
			var end_utc: int = end_local - (std_offset_minutes + 60) * 60
			# Spans year boundary: DST if after Oct start OR before Apr end.
			return unix_utc >= start_utc or unix_utc < end_utc
		_:
			return false


static func _last_sunday_utc(year: int, month: int, hour_utc: int) -> int:
	# Find last day of month, walk back to Sunday (Godot weekday 0=Sun).
	var day: int = _days_in_month(year, month)
	while true:
		var dict := {"year": year, "month": month, "day": day, "hour": hour_utc, "minute": 0, "second": 0}
		var unix: int = int(Time.get_unix_time_from_datetime_dict(dict))
		var wd: int = int(Time.get_datetime_dict_from_unix_time(unix).weekday)
		if wd == 0:
			return unix
		day -= 1
		if day < 1:
			return unix
	return 0


static func _nth_weekday_local(year: int, month: int, nth: int, weekday: int, hour: int, minute: int) -> int:
	"""nth occurrence of weekday (0=Sun) in month, as unix treating clock as UTC."""
	var count := 0
	var day := 1
	var last_match := 0
	while day <= _days_in_month(year, month):
		var dict := {"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0}
		var unix: int = int(Time.get_unix_time_from_datetime_dict(dict))
		var wd: int = int(Time.get_datetime_dict_from_unix_time(unix).weekday)
		if wd == weekday:
			count += 1
			last_match = unix
			if count == nth:
				return unix
		day += 1
	return last_match


static func _days_in_month(year: int, month: int) -> int:
	var days := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and ((year % 4 == 0 and year % 100 != 0) or year % 400 == 0):
		return 29
	return days[month]


static func _parse_fixed_offset(zone_id: String) -> int:
	var s: String = zone_id.to_upper().replace("GMT", "UTC")
	if not s.begins_with("UTC"):
		return -99999
	var rest: String = s.substr(3).strip_edges()
	if rest.is_empty():
		return 0
	var sign := 1
	if rest.begins_with("+"):
		rest = rest.substr(1)
	elif rest.begins_with("-"):
		sign = -1
		rest = rest.substr(1)
	var hp: PackedStringArray = rest.split(":")
	if hp.is_empty():
		return -99999
	var hours: int = int(hp[0])
	var mins: int = int(hp[1]) if hp.size() > 1 else 0
	return sign * (hours * 60 + mins)
