extends RefCounted
class_name WorkshopCatalystExportUtils

static func export_workshop_summary(
	ws: Dictionary,
	session_id: String,
	scenario: Dictionary,
	stage_info: Dictionary,
	exported_at: String,
	committed_payload: Dictionary = {},
	committed_artifact_id: String = ""
) -> String:
	if ws.is_empty():
		return ""
	var effective_session_id: String = session_id.strip_edges()
	if effective_session_id.is_empty():
		effective_session_id = str(Time.get_unix_time_from_system())

	var scenario_name: String = String(scenario.get("name", "Workshop")).strip_edges()
	var stage_name: String = String(stage_info.get("name", "")).strip_edges()
	var header := "# Workshop Summary\n\n"
	header += "- Scenario: %s\n" % scenario_name
	header += "- Session ID: %s\n" % effective_session_id
	header += "- Exported: %s\n" % exported_at
	if committed_artifact_id.is_empty():
		header += "- Record Status: Uncommitted fallback export\n"
		header += "- Committed Summary Artifact: unavailable\n"
	else:
		header += "- Record Status: Committed Workshop summary version\n"
		header += "- Committed Summary Artifact: %s\n" % committed_artifact_id
	header += "- Session Format: %s\n" % str(ws.get("session_label", ""))
	header += "- Session Duration (min): %s\n" % str(ws.get("session_duration_minutes", 0))
	header += "- Multi-day Session: %s\n" % str(ws.get("is_multi_day", false))
	header += "- Resume Mode: %s\n" % str(ws.get("resume_mode", "fresh"))
	var series_id_text: String = str(ws.get("series_id", "")).strip_edges()
	if not series_id_text.is_empty():
		header += "- Series ID: %s\n" % series_id_text
	header += "- Day: %s\n" % str(ws.get("day", 1))
	if not stage_name.is_empty():
		header += "- Current Stage: %s\n" % stage_name
	var resume_summary_text: String = str(ws.get("resume_summary", "")).strip_edges()
	if not resume_summary_text.is_empty():
		header += "- Resume Summary: %s\n" % resume_summary_text
	header += "\n"

	var buckets: Dictionary = (
		committed_payload if not committed_artifact_id.is_empty() else _buckets_from_ws(ws)
	)
	var out_text: String = header
	out_text += build_decision_record_block(buckets)
	out_text += build_supporting_notes_block(buckets)
	out_text += build_stage_history_markdown(ws)
	return write_markdown_file(effective_session_id, "workshop_summary", out_text)

static func export_decision_record_only(
	ws: Dictionary,
	session_id: String,
	scenario: Dictionary,
	exported_at: String,
	committed_payload: Dictionary = {},
	committed_artifact_id: String = ""
) -> String:
	if ws.is_empty():
		return ""
	var effective_session_id: String = session_id.strip_edges()
	if effective_session_id.is_empty():
		effective_session_id = str(Time.get_unix_time_from_system())
	var scenario_name: String = String(scenario.get("name", "Workshop")).strip_edges()
	var buckets: Dictionary = (
		committed_payload if not committed_artifact_id.is_empty() else _buckets_from_ws(ws)
	)
	var decisions: Array = _bucket_array(buckets, "decisions")
	var risks: Array = _bucket_array(buckets, "risks")
	var open_questions: Array = _bucket_array(buckets, "open_questions")

	var out := "# Decision Record\n\n"
	out += "**Scenario:** %s\n" % scenario_name
	out += "**Exported:** %s\n\n" % exported_at
	if committed_artifact_id.is_empty():
		out += "**Record status:** Uncommitted fallback export\n\n"
	else:
		out += "**Committed summary artifact:** `%s`\n\n" % committed_artifact_id
	out += "---\n\n"
	out += _numbered_target_section("Decisions Made", "Decision", decisions, 3, "No decisions captured yet.")
	out += _numbered_target_section("Named Risks", "Risk", risks, 2, "No risks captured yet.")
	out += _numbered_target_section("Deferred Questions", "Deferred", open_questions, 1, "No deferred questions captured yet.")
	return write_markdown_file(effective_session_id, "decision_record", out)

static func build_decision_record_block(buckets: Dictionary) -> String:
	var decisions: Array = _bucket_array(buckets, "decisions")
	var risks: Array = _bucket_array(buckets, "risks")
	var open_questions: Array = _bucket_array(buckets, "open_questions")
	var record := "## DECISION RECORD\n\n"
	record += _bold_target_section("Decisions Made", "Decision", decisions, 3, "(none captured)")
	record += _bold_target_section("Named Risks", "Risk", risks, 2, "(none captured)")
	record += _bold_target_section("Deferred Questions", "Deferred", open_questions, 1, "(none captured)")
	return record

static func build_supporting_notes_block(buckets: Dictionary) -> String:
	var out := "## SUPPORTING NOTES\n\n"
	for bucket_key: String in ["ideas", "constraints", "next_steps"]:
		var title: String = bucket_key.replace("_", " ").capitalize()
		out += "### %s\n" % title
		var items: Array = _bucket_array(buckets, bucket_key)
		if items.is_empty():
			out += "- (none)\n\n"
		else:
			for item_any in items:
				var item_text: String = _item_text(item_any)
				if item_text != "":
					out += "- " + item_text + "\n"
			out += "\n"
	return out

static func build_stage_history_markdown(ws: Dictionary) -> String:
	var stage_history_any: Variant = ws.get("stage_history", [])
	var stage_history: Array = stage_history_any if typeof(stage_history_any) == TYPE_ARRAY else []
	if stage_history.is_empty():
		return ""
	var out := "## Stage History\n"
	for entry_any in stage_history:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var stage_name: String = str(entry.get("stage_name", "")).strip_edges()
		if stage_name.is_empty():
			stage_name = "(unnamed stage)"
		out += "\n### %s\n" % stage_name
		out += "- Status: %s\n" % str(entry.get("stage_status", ""))
		out += "- Day Index: %s\n" % str(entry.get("day_index", 0))
		out += "- Stage Index: %s\n" % str(entry.get("stage_index", 0))
		out += "- Remaining Seconds at Snapshot: %s\n" % str(entry.get("remaining_sec", 0))
		var snapshot_any: Variant = entry.get("buckets_snapshot", {})
		var snapshot: Dictionary = snapshot_any if typeof(snapshot_any) == TYPE_DICTIONARY else {}
		var has_highlights := false
		for bucket_key: String in ["decisions", "next_steps", "open_questions"]:
			var items: Array = _bucket_array(snapshot, bucket_key)
			if items.is_empty():
				continue
			if not has_highlights:
				out += "- Snapshot Highlights:\n"
				has_highlights = true
			for item_any in items:
				var item_text: String = _item_text(item_any)
				if item_text != "":
					out += "  - %s: %s\n" % [bucket_key, item_text]
	return out + "\n"

static func write_markdown_file(session_id: String, suffix: String, content: String) -> String:
	var out_dir: String = RuntimeConfig.get_scensyn_story_log_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var out_path: String = out_dir + "session_%s.%s.md" % [session_id, suffix]
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if not file:
		push_warning("WorkshopCatalystExportUtils: Failed to write markdown: %s" % out_path)
		return ""
	file.store_string(content)
	file.close()
	return out_path

static func _buckets_from_ws(ws: Dictionary) -> Dictionary:
	var buckets_any: Variant = ws.get("buckets", {})
	return buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}

static func _bucket_array(buckets: Dictionary, bucket_key: String) -> Array:
	var items_any: Variant = buckets.get(bucket_key, [])
	return items_any if typeof(items_any) == TYPE_ARRAY else []

static func _bold_target_section(title: String, item_label: String, items: Array, target_count: int, empty_text: String) -> String:
	var out := ""
	if items.is_empty():
		out += "### %s (0 of %d target)\n- %s\n\n" % [title, target_count, empty_text]
	else:
		out += "### %s (%d of %d target)\n" % [title, items.size(), target_count]
		for item_index: int in range(items.size()):
			out += "**%s %d:** %s\n" % [
				item_label,
				item_index + 1,
				_item_text(items[item_index]),
			]
		out += "\n"
	return out

static func _numbered_target_section(title: String, item_label: String, items: Array, target_count: int, empty_text: String) -> String:
	var out := "## %s (%d of %d target)\n\n" % [title, items.size(), target_count]
	if items.is_empty():
		out += "_%s_\n\n" % empty_text
	else:
		for item_index: int in range(items.size()):
			out += "**%s %d:** %s\n\n" % [
				item_label,
				item_index + 1,
				_item_text(items[item_index]),
			]
	return out


static func _item_text(item_any: Variant) -> String:
	if typeof(item_any) == TYPE_DICTIONARY:
		return String(item_any.get("text", "")).strip_edges()
	return String(item_any).strip_edges()
