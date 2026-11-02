extends RefCounted
class_name WorkshopSessionScanner

## Scans the local ScenSyn story log directory for previously saved sessions
## by reading each *.provenance.json sidecar. Powers the "My Sessions" list
## so a facilitator can resume a prior Workshop Catalyst session without
## hunting through the "Load Story Log" file picker.

const PROVENANCE_SUFFIX := ".provenance.json"
const WORKSHOP_SUFFIX := ".workshop.json"
const JSON_SUFFIX := ".json"


## Returns Workshop Catalyst sessions found in the story log directory, most
## recently saved first. Each entry: file_stem, json_path, session_id,
## scenario, saved_at, entry_count, decisions_count, open_questions_count,
## last_stage_name.
static func scan_workshop_catalyst_sessions(story_log_dir: String = "") -> Array[Dictionary]:
	var dir_path: String = story_log_dir
	if dir_path.is_empty():
		dir_path = RuntimeConfig.get_scensyn_story_log_dir()
	var results: Array[Dictionary] = []
	var dir := DirAccess.open(dir_path)
	if not dir:
		return results
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(PROVENANCE_SUFFIX):
			var session_entry: Dictionary = _read_session_entry(dir_path, entry_name)
			if not session_entry.is_empty():
				results.append(session_entry)
		entry_name = dir.get_next()
	dir.list_dir_end()
	results.sort_custom(_by_saved_at_descending)
	return results


static func _by_saved_at_descending(entry_a: Dictionary, entry_b: Dictionary) -> bool:
	return String(entry_a.get("saved_at", "")) > String(entry_b.get("saved_at", ""))


static func _read_session_entry(dir_path: String, provenance_file_name: String) -> Dictionary:
	var prov_text: String = _read_text_file(dir_path + provenance_file_name)
	if prov_text.is_empty():
		return {}
	var prov_parsed: Variant = JSON.parse_string(prov_text)
	if typeof(prov_parsed) != TYPE_DICTIONARY:
		return {}
	var provenance: Dictionary = prov_parsed
	var file_stem: String = String(provenance.get("file_stem", ""))
	if file_stem.is_empty():
		file_stem = provenance_file_name.substr(
			0, provenance_file_name.length() - PROVENANCE_SUFFIX.length()
		)
	var ws_path: String = dir_path + file_stem + WORKSHOP_SUFFIX
	var has_workshop_sidecar: bool = FileAccess.file_exists(ws_path)
	var session_type: String = String(provenance.get("session_type", ""))
	if session_type.is_empty():
		# Legacy sessions saved before the session_type field existed: fall
		# back to the .workshop.json sidecar's presence as the signal.
		if not has_workshop_sidecar:
			return {}
	elif session_type != "workshop_catalyst":
		return {}
	var json_path: String = dir_path + file_stem + JSON_SUFFIX
	if not FileAccess.file_exists(json_path):
		return {}
	var session_entry: Dictionary = {
		"file_stem": file_stem,
		"json_path": json_path,
		"session_id": String(provenance.get("session_id", "")),
		"scenario": String(provenance.get("scenario", "")),
		"saved_at": String(provenance.get("saved_at", "")),
		"entry_count": int(provenance.get("entry_count", 0)),
		"decisions_count": 0,
		"open_questions_count": 0,
		"last_stage_name": "",
	}
	if has_workshop_sidecar:
		_apply_workshop_sidecar_summary(session_entry, ws_path)
	return session_entry


static func _apply_workshop_sidecar_summary(session_entry: Dictionary, ws_path: String) -> void:
	var ws_text: String = _read_text_file(ws_path)
	var ws_parsed: Variant = JSON.parse_string(ws_text)
	if typeof(ws_parsed) != TYPE_DICTIONARY:
		return
	var ws: Dictionary = ws_parsed
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	session_entry["decisions_count"] = _bucket_count(buckets, "decisions")
	session_entry["open_questions_count"] = _bucket_count(buckets, "open_questions")
	var stage_history_any: Variant = ws.get("stage_history", [])
	var stage_history: Array = (
		stage_history_any if typeof(stage_history_any) == TYPE_ARRAY else []
	)
	if stage_history.is_empty():
		return
	var last_stage_any: Variant = stage_history.back()
	if typeof(last_stage_any) == TYPE_DICTIONARY:
		var last_stage: Dictionary = last_stage_any
		session_entry["last_stage_name"] = String(last_stage.get("stage_name", ""))


static func _bucket_count(buckets: Dictionary, bucket_key: String) -> int:
	var items_any: Variant = buckets.get(bucket_key, [])
	var items: Array = items_any if typeof(items_any) == TYPE_ARRAY else []
	var count_value: int = 0
	for item_any: Variant in items:
		if String(item_any).strip_edges() != "":
			count_value += 1
	return count_value


static func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Human-friendly multi-line label for a session entry, for list display.
static func format_session_label(session_entry: Dictionary) -> String:
	var scenario: String = String(session_entry.get("scenario", "")).strip_edges()
	var saved_at: String = String(session_entry.get("saved_at", "")).strip_edges()
	var label: String = (
		scenario if not scenario.is_empty() else String(session_entry.get("file_stem", ""))
	)
	if not saved_at.is_empty():
		label += " — " + saved_at
	var decisions_count: int = int(session_entry.get("decisions_count", 0))
	var open_questions_count: int = int(session_entry.get("open_questions_count", 0))
	var stage_name: String = String(session_entry.get("last_stage_name", "")).strip_edges()
	var detail_parts: Array[String] = []
	if not stage_name.is_empty():
		detail_parts.append("Last stage: %s" % stage_name)
	if decisions_count > 0:
		detail_parts.append("%d decision(s)" % decisions_count)
	if open_questions_count > 0:
		detail_parts.append("%d open question(s)" % open_questions_count)
	if not detail_parts.is_empty():
		label += "\n" + " \u00b7 ".join(detail_parts)
	return label
