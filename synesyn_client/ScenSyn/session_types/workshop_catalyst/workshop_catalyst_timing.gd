extends RefCounted
class_name WorkshopCatalystTiming

## Stateless ownership boundary for Workshop Catalyst agenda normalization,
## session-duration scaling, and current-stage lookup.


static func normalize_state(ws: Dictionary, scenario: Dictionary) -> Dictionary:
	var normalized: Dictionary = ws.duplicate(true)
	var time_model: Dictionary = get_time_model(scenario)
	var session_minutes: int = int(normalized.get("session_duration_minutes", 0))
	if session_minutes <= 0:
		session_minutes = get_default_session_duration_minutes(time_model)
	normalized["session_duration_minutes"] = session_minutes
	if not normalized.has("is_multi_day"):
		normalized["is_multi_day"] = get_bool_setting(time_model.get("default_multi_day", "false"), false)
	if not normalized.has("series_id"):
		normalized["series_id"] = ""
	if not normalized.has("session_number"):
		normalized["session_number"] = 1
	if not normalized.has("resume_mode"):
		normalized["resume_mode"] = "fresh"
	if not normalized.has("resume_summary"):
		normalized["resume_summary"] = ""
	if not normalized.has("session_id") or String(normalized.get("session_id", "")).strip_edges().is_empty():
		normalized["session_id"] = build_session_id()
	normalized["uses_scaled_stage_timing"] = should_scale_stage_timing(time_model)
	var loaded_agenda_any: Variant = normalized.get("agenda", [])
	var loaded_agenda: Array = loaded_agenda_any if typeof(loaded_agenda_any) == TYPE_ARRAY else []
	var is_resume: bool = String(normalized.get("resume_mode", "fresh")) == "continue_prior_session"
	if is_resume and not loaded_agenda.is_empty():
		normalized["agenda"] = loaded_agenda
	else:
		normalized["agenda"] = apply_session_timing_to_agenda(
			parse_agenda(scenario),
			session_minutes,
			bool(normalized.get("uses_scaled_stage_timing", false))
		)
	if not normalized.has("day_index"):
		normalized["day_index"] = 0
	if not normalized.has("stage_index"):
		normalized["stage_index"] = 0
	if not normalized.has("stage_status"):
		normalized["stage_status"] = "not_started"
	if not normalized.has("stage_started_at_unix"):
		normalized["stage_started_at_unix"] = 0
	if not normalized.has("stage_completed_at_unix"):
		normalized["stage_completed_at_unix"] = 0
	if not normalized.has("stage_history"):
		normalized["stage_history"] = []
	if not normalized.has("is_note_only_next_input"):
		normalized["is_note_only_next_input"] = false
	if not normalized.has("send_as_facilitator"):
		normalized["send_as_facilitator"] = false
	if not normalized.has("buckets") or typeof(normalized.get("buckets", {})) != TYPE_DICTIONARY:
		normalized["buckets"] = {
			"ideas": [],
			"constraints": [],
			"risks": [],
			"decisions": [],
			"open_questions": [],
			"next_steps": [],
		}
	var stage_info: Dictionary = get_current_stage_info(normalized)
	var stage_duration_sec: int = get_stage_duration_sec(stage_info)
	if int(normalized.get("stage_remaining_sec", -1)) < 0:
		normalized["stage_remaining_sec"] = stage_duration_sec
	if not normalized.has("current_stage_name") or String(normalized.get("current_stage_name", "")).strip_edges().is_empty():
		normalized["current_stage_name"] = String(stage_info.get("name", ""))
	normalized["day"] = get_current_day_number(normalized)
	normalized["session_label"] = build_session_label(normalized)
	return normalized


static func parse_agenda(scenario: Dictionary) -> Array:
	var agenda_text: String = String(scenario.get("workshop_agenda_text", "")).strip_edges()
	if agenda_text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(agenda_text)
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	return []


static func get_time_model(scenario: Dictionary) -> Dictionary:
	var time_model_value: Variant = scenario.get("time_model", {})
	return time_model_value if typeof(time_model_value) == TYPE_DICTIONARY else {}


static func get_default_session_duration_minutes(time_model: Dictionary) -> int:
	var default_hours: int = get_int_setting(time_model.get("default_session_duration_hours", "2"), 2)
	default_hours = clampi(default_hours, 1, 4)
	return default_hours * 60


static func should_scale_stage_timing(time_model: Dictionary) -> bool:
	var timing_kind: String = String(time_model.get("stage_timing_mode", "fixed")).strip_edges().to_lower()
	return timing_kind == "scalable"


static func apply_session_timing_to_agenda(
	agenda: Array,
	session_duration_minutes: int,
	uses_scaled_timing: bool
) -> Array:
	var normalized_agenda: Array = agenda.duplicate(true)
	var total_original_duration: int = 0
	for day_entry_value in normalized_agenda:
		if typeof(day_entry_value) != TYPE_DICTIONARY:
			continue
		var day_entry: Dictionary = day_entry_value
		var stages_value: Variant = day_entry.get("stages", [])
		var stages: Array = stages_value if typeof(stages_value) == TYPE_ARRAY else []
		for stage_value in stages:
			if typeof(stage_value) != TYPE_DICTIONARY:
				continue
			var stage_dict: Dictionary = stage_value
			var original_duration: int = int(
				stage_dict.get("original_duration", stage_dict.get("duration", 0))
			)
			total_original_duration += original_duration
	var target_total_duration: int = maxi(session_duration_minutes, 1) * 60
	var scale_factor: float = 1.0
	if uses_scaled_timing and total_original_duration > 0:
		scale_factor = float(target_total_duration) / float(total_original_duration)
	for day_index: int in range(normalized_agenda.size()):
		if typeof(normalized_agenda[day_index]) != TYPE_DICTIONARY:
			continue
		var day_copy: Dictionary = normalized_agenda[day_index]
		var stages_value: Variant = day_copy.get("stages", [])
		var stages: Array = stages_value if typeof(stages_value) == TYPE_ARRAY else []
		var new_stages: Array = []
		for stage_value in stages:
			if typeof(stage_value) != TYPE_DICTIONARY:
				continue
			var stage_copy: Dictionary = stage_value.duplicate(true)
			var original_duration: int = int(
				stage_copy.get("original_duration", stage_copy.get("duration", 0))
			)
			var recommended_duration: int = original_duration
			if uses_scaled_timing and total_original_duration > 0:
				recommended_duration = maxi(60, int(round(float(original_duration) * scale_factor)))
			stage_copy["original_duration"] = original_duration
			stage_copy["recommended_duration"] = recommended_duration
			stage_copy["duration"] = recommended_duration if uses_scaled_timing else original_duration
			new_stages.append(stage_copy)
		day_copy["stages"] = new_stages
		normalized_agenda[day_index] = day_copy
	return normalized_agenda


static func get_int_setting(setting_value: Variant, fallback_value: int) -> int:
	if typeof(setting_value) == TYPE_INT:
		return int(setting_value)
	var text_value: String = str(setting_value).strip_edges()
	if text_value.is_valid_int():
		return text_value.to_int()
	return fallback_value


static func get_bool_setting(setting_value: Variant, fallback_value: bool) -> bool:
	if typeof(setting_value) == TYPE_BOOL:
		return bool(setting_value)
	var text_value: String = str(setting_value).strip_edges().to_lower()
	if text_value in ["true", "1", "yes", "on"]:
		return true
	if text_value in ["false", "0", "no", "off"]:
		return false
	return fallback_value


static func build_session_id() -> String:
	var datetime_parts: Dictionary = Time.get_datetime_dict_from_system()
	return "wc_%04d%02d%02d_%02d%02d%02d" % [
		datetime_parts.year,
		datetime_parts.month,
		datetime_parts.day,
		datetime_parts.hour,
		datetime_parts.minute,
		datetime_parts.second,
	]


static func build_session_label(ws: Dictionary) -> String:
	var duration_minutes: int = int(ws.get("session_duration_minutes", 120))
	var duration_hours: int = maxi(1, int(round(float(duration_minutes) / 60.0)))
	var label_text: String = "%d-hour session" % duration_hours
	if ws.get("is_multi_day", false) == true:
		label_text += " (multi-day)"
	return label_text


static func get_current_day_number(ws: Dictionary) -> int:
	var agenda_value: Variant = ws.get("agenda", [])
	var agenda: Array = agenda_value if typeof(agenda_value) == TYPE_ARRAY else []
	var day_index: int = int(ws.get("day_index", 0))
	if day_index >= 0 and day_index < agenda.size() and typeof(agenda[day_index]) == TYPE_DICTIONARY:
		var day_entry: Dictionary = agenda[day_index]
		return int(day_entry.get("day", day_index + 1))
	return day_index + 1


static func get_stage_duration_sec(stage_info: Dictionary) -> int:
	if stage_info.is_empty():
		return 0
	return int(
		stage_info.get(
			"duration",
			stage_info.get("recommended_duration", stage_info.get("original_duration", 0))
		)
	)


static func get_current_stage_info(ws: Dictionary) -> Dictionary:
	var agenda_value: Variant = ws.get("agenda", [])
	var agenda: Array = agenda_value if typeof(agenda_value) == TYPE_ARRAY else []
	var day_index: int = int(ws.get("day_index", 0))
	if day_index < 0 or day_index >= agenda.size():
		return {}
	var day_entry_value: Variant = agenda[day_index]
	if typeof(day_entry_value) != TYPE_DICTIONARY:
		return {}
	var day_entry: Dictionary = day_entry_value
	var stages_value: Variant = day_entry.get("stages", [])
	var stages: Array = stages_value if typeof(stages_value) == TYPE_ARRAY else []
	var stage_index: int = int(ws.get("stage_index", 0))
	if stage_index < 0 or stage_index >= stages.size():
		return {}
	var stage_value: Variant = stages[stage_index]
	if typeof(stage_value) != TYPE_DICTIONARY:
		return {}
	return stage_value
