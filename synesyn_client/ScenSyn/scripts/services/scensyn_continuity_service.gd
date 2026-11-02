extends RefCounted
class_name ScenSynContinuityService

const MEMORY_SUBDIR := "scensyn/memory_sources"

func load_store_context_pack_into_story_state(hub, context_pack_id: String) -> Dictionary:
	var cpid := String(context_pack_id).strip_edges()
	if cpid.is_empty():
		return {"ok": false, "error": "context_pack_id is required"}
	if hub == null:
		return {"ok": false, "error": "hub client unavailable"}
	if not hub.has_method("scensyn_get_continuity_state_from_store_context"):
		return {"ok": false, "error": "hub client missing scensyn_get_continuity_state_from_store_context"}
	var session_id := SynesynSession.get_or_create_session_id("scensyn")
	var continuity: Dictionary = await hub.scensyn_get_continuity_state_from_store_context(cpid, true, session_id)
	if not bool(continuity.get("ok", false)):
		return continuity
	if StoryState and StoryState.has_method("set_scenario_continuity_state"):
		StoryState.set_scenario_continuity_state(continuity)
	var provenance_any: Variant = continuity.get("provenance", {})
	var provenance: Dictionary = provenance_any if typeof(provenance_any) == TYPE_DICTIONARY else {}
	return {
		"ok": true,
		"context_pack_id": cpid,
		"session_id": session_id,
		"continuity_artifact_id": str(provenance.get("continuity_artifact_id", "")).strip_edges(),
		"continuity_state": continuity,
	}

func load_into_story_state(hub, scenario: Dictionary) -> Dictionary:
	var cfg: Dictionary = _get_memory_config(scenario)
	if not bool(cfg.get("enabled", false)):
		return {"ok": false, "skipped": true, "reason": "memory continuity disabled"}
	if hub == null:
		return {"ok": false, "error": "hub client unavailable"}

	var source_res: Dictionary = await _ensure_source_document(hub, scenario, cfg)
	if not bool(source_res.get("ok", false)):
		return source_res

	var source_path := str(source_res.get("path", "")).strip_edges()
	if source_path.is_empty():
		return {"ok": false, "error": "source path is empty"}

	var cache_path := str(source_res.get("cache_path", "")).strip_edges()
	var document_res: Dictionary = await _ensure_document_id(hub, source_path, cache_path, cfg)
	if not bool(document_res.get("ok", false)):
		return document_res
	var document_id := str(document_res.get("document_id", "")).strip_edges()
	if document_id.is_empty():
		return {
			"ok": false,
			"error": "memory document_id missing after resolution",
			"source_path": source_path,
			"cache_path": cache_path,
			"document_resolution": document_res,
		}

	var continuity: Dictionary = await hub.scensyn_get_continuity_state(
		document_id,
		str(cfg.get("chunk_path", "")).strip_edges(),
		int(cfg.get("depth", 2)),
		int(cfg.get("sibling_window", 2))
	)
	if not bool(continuity.get("ok", false)):
		return continuity

	_inject_session_history(continuity, source_path)

	if StoryState and StoryState.has_method("set_scenario_continuity_state"):
		StoryState.set_scenario_continuity_state(continuity)

	return {
		"ok": true,
		"document_id": document_id,
		"source_path": source_path,
		"cache_path": cache_path,
		"continuity_state": continuity,
	}

func _get_memory_config(scenario: Dictionary) -> Dictionary:
	var direct_any: Variant = scenario.get("memory_continuity", {})
	if typeof(direct_any) == TYPE_DICTIONARY:
		var direct: Dictionary = direct_any
		if not direct.is_empty():
			return _normalize_memory_config(direct)
	var sys_any: Variant = scenario.get("system_config", {})
	var sys_cfg: Dictionary = sys_any if typeof(sys_any) == TYPE_DICTIONARY else {}
	if sys_cfg.is_empty():
		return {}
	var has_memory_key := false
	for k_any in sys_cfg.keys():
		var k := String(k_any).strip_edges().to_lower()
		if k.begins_with("memory_"):
			has_memory_key = true
			break
	if not has_memory_key:
		return {}
	return _normalize_memory_config({
		"enabled": String(sys_cfg.get("memory_enabled", "false")).to_lower() == "true",
		"source_mode": str(sys_cfg.get("memory_source_mode", "scenario_scaffold")).strip_edges(),
		"source_path": str(sys_cfg.get("memory_source_path", "")).strip_edges(),
		"chunk_path": str(sys_cfg.get("memory_chunk_path", "")).strip_edges(),
		"depth": int(sys_cfg.get("memory_depth", 2)),
		"sibling_window": int(sys_cfg.get("memory_sibling_window", 2)),
	})

func _normalize_memory_config(raw: Dictionary) -> Dictionary:
	return {
		"enabled": _boolish(raw.get("enabled", false)),
		"source_mode": str(raw.get("source_mode", "scenario_scaffold")).strip_edges(),
		"source_path": str(raw.get("source_path", "")).strip_edges(),
		"chunk_path": str(raw.get("chunk_path", "")).strip_edges(),
		"depth": int(raw.get("depth", 2)),
		"sibling_window": int(raw.get("sibling_window", 2)),
		"parse_strategy": str(raw.get("parse_strategy", "headings")).strip_edges(),
	}

func _boolish(value: Variant) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	return str(value).strip_edges().to_lower() in ["1", "true", "yes", "on"]

func _ensure_source_document(hub, scenario: Dictionary, cfg: Dictionary) -> Dictionary:
	var mode := str(cfg.get("source_mode", "scenario_scaffold")).strip_edges().to_lower()
	if mode == "file":
		var resolved := _resolve_source_path(String(cfg.get("source_path", "")), scenario)
		if resolved.is_empty():
			return {"ok": false, "error": "memory source_path could not be resolved"}
		return {"ok": true, "path": resolved, "cache_path": resolved + ".memory.json"}
	return await _write_scenario_scaffold_markdown(hub, scenario)

func _resolve_source_path(source_path: String, scenario: Dictionary) -> String:
	var raw := source_path.strip_edges()
	if raw.is_empty():
		return ""
	if raw.begins_with("res://") or raw.begins_with("user://"):
		return ProjectSettings.globalize_path(raw)
	if raw.contains(":") or raw.begins_with("/") or raw.begins_with("\\"):
		return raw
	var base_dir := str(scenario.get("_base_dir", "")).strip_edges()
	if not base_dir.is_empty():
		return ProjectSettings.globalize_path(base_dir.path_join(raw))
	return raw

func _write_scenario_scaffold_markdown(hub, scenario: Dictionary) -> Dictionary:
	var workspace_root: String = await hub.get_workspace_root()
	if workspace_root.is_empty():
		return {"ok": false, "error": "workspace root unavailable from hub"}
	var slug := _scenario_slug(scenario)
	var dir_path: String = workspace_root.path_join(MEMORY_SUBDIR)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var md_path: String = dir_path.path_join(slug + "_scenario_memory.md")
	var cache_path: String = dir_path.path_join(slug + "_scenario_memory.cache.json")
	var content := _build_scenario_memory_markdown(scenario)
	var existing := ""
	if FileAccess.file_exists(md_path):
		existing = FileAccess.get_file_as_string(md_path)
	if existing != content:
		var f := FileAccess.open(md_path, FileAccess.WRITE)
		if not f:
			return {"ok": false, "error": "failed to write scenario memory markdown", "path": md_path}
		f.store_string(content)
		f.close()
	return {"ok": true, "path": md_path, "cache_path": cache_path}

func _ensure_document_id(hub, source_path: String, cache_path: String, cfg: Dictionary) -> Dictionary:
	var cached_id := _load_cached_document_id(cache_path, source_path)
	if not cached_id.is_empty():
		var doc_check: Dictionary = await hub.stfx_get_document(cached_id)
		if bool(doc_check.get("ok", false)):
			return {
				"ok": true,
				"document_id": cached_id,
				"source": "cache",
			}
	var ingest_res: Dictionary = await hub.stfx_ingest_document(source_path, str(cfg.get("parse_strategy", "headings")))
	if not bool(ingest_res.get("ok", false)):
		return {
			"ok": false,
			"error": "failed to ingest memory source document",
			"source_path": source_path,
			"cache_path": cache_path,
			"ingest_result": ingest_res,
		}
	var new_id := str(ingest_res.get("document_id", "")).strip_edges()
	if new_id.is_empty():
		return {
			"ok": false,
			"error": "ingest succeeded but returned empty document_id",
			"source_path": source_path,
			"cache_path": cache_path,
			"ingest_result": ingest_res,
		}
	_save_cached_document_id(cache_path, source_path, new_id)
	return {
		"ok": true,
		"document_id": new_id,
		"source": "ingest",
	}

func _load_cached_document_id(cache_path: String, source_path: String) -> String:
	if cache_path.is_empty() or not FileAccess.file_exists(cache_path):
		return ""
	var raw := FileAccess.get_file_as_string(cache_path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var d: Dictionary = parsed
	if str(d.get("source_path", "")).strip_edges() != source_path.strip_edges():
		return ""
	return str(d.get("document_id", "")).strip_edges()

func _save_cached_document_id(cache_path: String, source_path: String, document_id: String) -> void:
	if cache_path.is_empty():
		return
	var dir_path := cache_path.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if not f:
		return
	var payload := {
		"source_path": source_path,
		"document_id": document_id,
		"updated_utc": Time.get_datetime_string_from_system(true),
	}
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

func _scenario_slug(scenario: Dictionary) -> String:
	var base := str(scenario.get("_scenario_name", "")).strip_edges()
	if base.is_empty():
		base = str(scenario.get("name", "scenario")).strip_edges().to_lower()
	var cleaned := ""
	var prev_sep := true
	for ch in base:
		var code := ch.unicode_at(0)
		var is_alpha := (code >= 97 and code <= 122) or (code >= 65 and code <= 90)
		var is_num := (code >= 48 and code <= 57)
		if is_alpha or is_num:
			cleaned += ch.to_lower()
			prev_sep = false
		elif ch == " " or ch == "-" or ch == "_":
			if not prev_sep:
				cleaned += "-"
			prev_sep = true
	while cleaned.ends_with("-"):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	return cleaned if not cleaned.is_empty() else "scenario"

func _build_scenario_memory_markdown(scenario: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("# " + str(scenario.get("name", "Unnamed Scenario")).strip_edges())
	lines.append("")
	lines.append("## Objective")
	lines.append(str(scenario.get("objective", "No objective set")).strip_edges())
	lines.append("")
	lines.append("## Setting")
	lines.append(str(scenario.get("description", "No setting description")).strip_edges())
	lines.append("")

	var context_text := str(scenario.get("context_text", "")).strip_edges()
	if not context_text.is_empty():
		lines.append("## Context")
		lines.append(context_text)
		lines.append("")

	var about_text := str(scenario.get("about_text", "")).strip_edges()
	if not about_text.is_empty():
		lines.append("## About")
		lines.append(about_text)
		lines.append("")

	var workshop_packet_text := str(scenario.get("workshop_packet_text", "")).strip_edges()
	if not workshop_packet_text.is_empty():
		lines.append("## Workshop Packet")
		lines.append(workshop_packet_text)
		lines.append("")

	var output_template_text := str(scenario.get("output_template_text", "")).strip_edges()
	if not output_template_text.is_empty():
		lines.append("## Output Template")
		lines.append(output_template_text)
		lines.append("")

	var facilitator_playbook_text := str(scenario.get("facilitator_playbook_text", "")).strip_edges()
	if not facilitator_playbook_text.is_empty():
		lines.append("## Facilitator Playbook")
		lines.append(facilitator_playbook_text)
		lines.append("")

	var resume_guidance_text := str(scenario.get("resume_guidance_text", "")).strip_edges()
	if not resume_guidance_text.is_empty():
		lines.append("## Resume Guidance")
		lines.append(resume_guidance_text)
		lines.append("")

	var phase_guidance_any: Variant = scenario.get("phase_guidance", {})
	var phase_guidance: Dictionary = phase_guidance_any if typeof(phase_guidance_any) == TYPE_DICTIONARY else {}
	if not phase_guidance.is_empty():
		lines.append("## Phase Guidance")
		for phase_name in phase_guidance.keys():
			lines.append("")
			lines.append("### " + str(phase_name))
			lines.append(str(phase_guidance[phase_name]).strip_edges())
		lines.append("")

	var stage_guidance_any: Variant = scenario.get("stage_guidance", {})
	var stage_guidance: Dictionary = stage_guidance_any if typeof(stage_guidance_any) == TYPE_DICTIONARY else {}
	if not stage_guidance.is_empty():
		lines.append("## Stage Guidance")
		for stage_name_any in stage_guidance.keys():
			var stage_name: String = str(stage_name_any).strip_edges()
			lines.append("")
			lines.append("### " + stage_name)
			lines.append(str(stage_guidance[stage_name_any]).strip_edges())
		lines.append("")

	var chars_any: Variant = scenario.get("characters", [])
	var chars: Array = chars_any if typeof(chars_any) == TYPE_ARRAY else []
	if not chars.is_empty():
		lines.append("## Characters")
		for char_any in chars:
			if typeof(char_any) != TYPE_DICTIONARY:
				continue
			var char: Dictionary = char_any
			lines.append("")
			lines.append("### " + str(char.get("name", "Unnamed")).strip_edges())
			lines.append("- Role: " + str(char.get("role", "Unknown")).strip_edges())
			lines.append("- Description: " + str(char.get("description", "")).strip_edges())
			var beh := str(char.get("behavioral_instructions", "")).strip_edges()
			if not beh.is_empty():
				lines.append("- Behavioral Instructions:")
				lines.append(beh)
		lines.append("")

	var scene_ledger := str(scenario.get("scene_ledger_text", "")).strip_edges()
	if not scene_ledger.is_empty():
		lines.append("## Scene Ledger")
		lines.append(scene_ledger)
		lines.append("")

	return "\n".join(lines).strip_edges() + "\n"


func _inject_session_history(continuity: Dictionary, source_path: String) -> void:
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return
	var content := FileAccess.get_file_as_string(source_path)
	var digest_header := "## Session Digests"
	var header_idx := content.find(digest_header)
	if header_idx == -1:
		return

	var digest_section := content.substr(header_idx + digest_header.length()).strip_edges()
	if digest_section.is_empty():
		return

	var max_chars := 2000
	if digest_section.length() > max_chars:
		digest_section = digest_section.substr(digest_section.length() - max_chars)
		var first_session := digest_section.find("### Session")
		if first_session > 0:
			digest_section = digest_section.substr(first_session)

	var state_patch_any: Variant = continuity.get("state_patch", {})
	var state_patch: Dictionary = state_patch_any if typeof(state_patch_any) == TYPE_DICTIONARY else {}
	var mem_ctx_any: Variant = state_patch.get("memory_context", {})
	var mem_ctx: Dictionary = mem_ctx_any if typeof(mem_ctx_any) == TYPE_DICTIONARY else {}

	mem_ctx["session_history"] = digest_section
	state_patch["memory_context"] = mem_ctx
	continuity["state_patch"] = state_patch
	print("[ContinuityService] Injected session history (%d chars) from digests" % digest_section.length())
