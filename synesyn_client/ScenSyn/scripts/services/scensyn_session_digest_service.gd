extends RefCounted
class_name ScenSynSessionDigestService

## Generates a structured session digest from the story log and appends it
## to the evolving scenario memory markdown, then re-ingests the document
## so that future sessions pick up accumulated narrative context.

const DIGEST_SECTION_HEADER := "## Session Digests"
const MAX_DIGEST_ENTRIES := 20

var _digest_written := false

func write_session_digest(hub, scenario: Dictionary, continuity_service) -> Dictionary:
	if _digest_written:
		return {"ok": true, "skipped": true, "reason": "digest already written this session"}
	if hub == null:
		return {"ok": false, "error": "hub client unavailable"}
	if continuity_service == null:
		return {"ok": false, "error": "continuity_service unavailable"}

	var cfg: Dictionary = continuity_service._get_memory_config(scenario)
	if not bool(cfg.get("enabled", false)):
		return {"ok": false, "skipped": true, "reason": "memory continuity disabled"}

	var source_res: Dictionary = await continuity_service._ensure_source_document(hub, scenario, cfg)
	if not bool(source_res.get("ok", false)):
		return source_res

	var md_path := str(source_res.get("path", "")).strip_edges()
	if md_path.is_empty():
		return {"ok": false, "error": "memory source path is empty"}

	var digest_md := _build_digest_markdown()
	if digest_md.is_empty():
		return {"ok": false, "skipped": true, "reason": "story log empty or no character speech"}

	var append_ok := _append_digest_to_markdown(md_path, digest_md)
	if not append_ok:
		return {"ok": false, "error": "failed to append digest to " + md_path}

	_digest_written = true

	var cache_path := str(source_res.get("cache_path", "")).strip_edges()
	_invalidate_cache(cache_path)

	var ingest_res: Dictionary = await hub.stfx_ingest_document(
		md_path, str(cfg.get("parse_strategy", "headings"))
	)
	if not bool(ingest_res.get("ok", false)):
		print("[SessionDigest] Re-ingest failed; next startup will re-ingest: ", ingest_res)
		return {"ok": true, "path": md_path, "note": "digest written, re-ingest deferred to next startup"}

	var new_id := str(ingest_res.get("document_id", "")).strip_edges()
	if not new_id.is_empty() and not cache_path.is_empty():
		continuity_service._save_cached_document_id(cache_path, md_path, new_id)

	print("[SessionDigest] Digest written and re-ingested. document_id=%s" % new_id)
	return {"ok": true, "document_id": new_id, "path": md_path}


func write_digest_sync(scenario: Dictionary, continuity_service) -> bool:
	if _digest_written:
		return true
	if continuity_service == null:
		return false

	var cfg: Dictionary = continuity_service._get_memory_config(scenario)
	if not bool(cfg.get("enabled", false)):
		return false

	var slug: String = continuity_service._scenario_slug(scenario)
	var candidate_paths: Array[String] = _guess_memory_md_paths(slug)
	var md_path := ""
	for candidate in candidate_paths:
		if FileAccess.file_exists(candidate):
			md_path = candidate
			break

	if md_path.is_empty():
		print("[SessionDigest] sync: no memory markdown found for slug '%s'" % slug)
		return false

	var digest_md := _build_digest_markdown()
	if digest_md.is_empty():
		return false

	var ok := _append_digest_to_markdown(md_path, digest_md)
	if ok:
		_digest_written = true
		var cache_path := md_path + ".memory.json"
		if md_path.ends_with("_scenario_memory.md"):
			cache_path = md_path.replace("_scenario_memory.md", "_scenario_memory.cache.json")
		_invalidate_cache(cache_path)
		print("[SessionDigest] sync: digest appended to %s (re-ingest deferred)" % md_path)
	return ok


func _guess_memory_md_paths(slug: String) -> Array[String]:
	var paths: Array[String] = []
	var workspace_candidates: Array[String] = []
	if OS.has_environment("SYNESYN_WORKSPACE"):
		workspace_candidates.append(OS.get_environment("SYNESYN_WORKSPACE"))
	var user_docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if not user_docs.is_empty():
		workspace_candidates.append(user_docs.path_join("Synesyn/Workspaces"))
		var dir := DirAccess.open(user_docs.path_join("Synesyn/Workspaces"))
		if dir:
			dir.list_dir_begin()
			var folder_name := dir.get_next()
			while folder_name != "":
				if dir.current_is_dir() and folder_name.begins_with("Workspace_"):
					workspace_candidates.append(
						user_docs.path_join("Synesyn/Workspaces").path_join(folder_name)
					)
				folder_name = dir.get_next()
			dir.list_dir_end()

	for ws in workspace_candidates:
		var candidate: String = ws.path_join("scensyn/memory_sources").path_join(slug + "_scenario_memory.md")
		if not paths.has(candidate):
			paths.append(candidate)
	return paths


func _invalidate_cache(cache_path: String) -> void:
	if cache_path.is_empty():
		return
	if FileAccess.file_exists(cache_path):
		DirAccess.remove_absolute(cache_path)
		print("[SessionDigest] Cache invalidated: %s" % cache_path)


func _build_digest_markdown() -> String:
	if typeof(StoryState) == TYPE_NIL or not StoryState or not StoryState.has_method("get_state"):
		return ""
	var state: Dictionary = StoryState.get_state()
	var log_entries: Array = state.get("story_log", [])
	if log_entries.is_empty():
		return ""

	var character_lines: Dictionary = {}
	var turn_count := 0
	var all_speakers: Array[String] = []

	for entry_any in log_entries:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender := str(entry.get("sender", "")).strip_edges()
		var msg := str(entry.get("message", "")).strip_edges()
		if sender.is_empty() or msg.is_empty():
			continue
		if sender == "Narrator" and (msg.contains("Welcome to") or msg.contains("couldn't generate") or msg.contains("Hub offline") or msg.contains("Hub back online")):
			continue

		if not all_speakers.has(sender):
			all_speakers.append(sender)
		if not character_lines.has(sender):
			character_lines[sender] = []
		character_lines[sender].append(msg)
		turn_count += 1

	if character_lines.is_empty():
		return ""

	var phase := str(state.get("current_narrative_phase", "unknown")).strip_edges()
	var unresolved: Array = state.get("unresolved_challenges", [])

	var lines: Array[String] = []
	var now := Time.get_datetime_dict_from_system()
	var timestamp := "%04d-%02d-%02d %02d:%02d" % [
		now["year"], now["month"], now["day"], now["hour"], now["minute"]]

	lines.append("### Session — %s" % timestamp)
	lines.append("")
	lines.append("- Speakers: %s" % ", ".join(all_speakers))
	lines.append("- Turns: %d" % turn_count)
	lines.append("- Final phase: %s" % phase)
	lines.append("")

	lines.append("#### Key narrative moments")
	lines.append("")
	for speaker_name in character_lines.keys():
		var speaker_msgs: Array = character_lines[speaker_name]
		if speaker_msgs.is_empty():
			continue
		var last_msg: String = speaker_msgs[speaker_msgs.size() - 1]
		var excerpt := _truncate(last_msg, 200)
		lines.append("- **%s** (last): %s" % [speaker_name, excerpt])

	if not unresolved.is_empty():
		lines.append("")
		lines.append("#### Unresolved threads")
		for thread_any in unresolved:
			lines.append("- %s" % str(thread_any).strip_edges())

	var memory_any: Variant = state.get("memory_context", {})
	var memory_context: Dictionary = memory_any if typeof(memory_any) == TYPE_DICTIONARY else {}
	var latent_tensions_any: Variant = memory_context.get("latent_tensions", [])
	var latent_tensions: Array = latent_tensions_any if typeof(latent_tensions_any) == TYPE_ARRAY else []
	if not latent_tensions.is_empty():
		lines.append("")
		lines.append("#### What the Tapestry was dreaming")
		for tension_any in latent_tensions:
			lines.append("- %s" % str(tension_any).strip_edges())

	lines.append("")
	lines.append("#### Seeker's journey so far")
	var seeker_lines: Array = character_lines.get("The Seeker", [])
	if seeker_lines.size() > 0:
		var first_excerpt := _truncate(str(seeker_lines[0]), 150)
		var last_excerpt := _truncate(str(seeker_lines[seeker_lines.size() - 1]), 150)
		lines.append("- Began: %s" % first_excerpt)
		if seeker_lines.size() > 1:
			lines.append("- Ended: %s" % last_excerpt)
	else:
		lines.append("- The Seeker did not speak this session.")

	lines.append("")
	return "\n".join(lines)


func _append_digest_to_markdown(md_path: String, digest_md: String) -> bool:
	var existing := ""
	if FileAccess.file_exists(md_path):
		existing = FileAccess.get_file_as_string(md_path)

	var section_idx := existing.find(DIGEST_SECTION_HEADER)
	var new_content := ""

	if section_idx == -1:
		new_content = existing.strip_edges() + "\n\n" + DIGEST_SECTION_HEADER + "\n\n" + digest_md
	else:
		var before_section := existing.substr(0, section_idx + DIGEST_SECTION_HEADER.length())
		var after_header := existing.substr(section_idx + DIGEST_SECTION_HEADER.length())
		new_content = before_section + "\n\n" + digest_md + after_header

	new_content = _trim_old_digests(new_content)

	var f := FileAccess.open(md_path, FileAccess.WRITE)
	if not f:
		print("[SessionDigest] ERROR: Could not open %s for writing" % md_path)
		return false
	f.store_string(new_content)
	f.close()
	return true


func _trim_old_digests(content: String) -> String:
	var session_marker := "### Session — "
	var search_from := 0
	var positions: Array[int] = []
	while true:
		var idx := content.find(session_marker, search_from)
		if idx == -1:
			break
		positions.append(idx)
		search_from = idx + session_marker.length()

	if positions.size() <= MAX_DIGEST_ENTRIES:
		return content

	var cutoff_pos := positions[positions.size() - MAX_DIGEST_ENTRIES]
	var header_idx := content.find(DIGEST_SECTION_HEADER)
	if header_idx == -1:
		return content

	var before := content.substr(0, header_idx + DIGEST_SECTION_HEADER.length())
	var kept := content.substr(cutoff_pos)
	return before + "\n\n" + kept


func _truncate(text: String, max_len: int) -> String:
	var clean := text.replace("\n", " ").strip_edges()
	if clean.length() <= max_len:
		return clean
	return clean.substr(0, max_len).strip_edges() + "..."
