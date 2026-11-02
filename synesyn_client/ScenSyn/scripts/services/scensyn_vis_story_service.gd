extends RefCounted
class_name ScenSynVisStoryService


func get_effective_config(scenario: Dictionary) -> Dictionary:
	return _get_vis_story_config(scenario)


func export_current_cycle(hub, scenario: Dictionary, cycle_id: int = -1, opts: Dictionary = {}) -> Dictionary:
	var cfg := _get_vis_story_config(scenario)
	if not bool(cfg.get("enabled", false)):
		return {"ok": false, "skipped": true, "reason": "vis_story disabled"}
	if hub == null:
		return {"ok": false, "error": "hub unavailable"}
	if typeof(StoryState) == TYPE_NIL or not StoryState or not StoryState.has_method("get_scenario_continuity_state"):
		return {"ok": false, "error": "StoryState continuity unavailable"}

	var continuity_state: Dictionary = StoryState.get_scenario_continuity_state()
	if continuity_state.is_empty():
		return {"ok": false, "error": "scenario continuity state unavailable"}

	var resolved_cycle_id := int(cycle_id)
	if resolved_cycle_id <= 0 and StoryState.has_method("get_state"):
		var state: Dictionary = StoryState.get_state()
		resolved_cycle_id = max(1, int(state.get("current_turn", 1)))
	if resolved_cycle_id <= 0:
		resolved_cycle_id = 1

	var scenario_context := {
		"name": str(scenario.get("name", "")).strip_edges(),
		"location_and_setting": str(scenario.get("location and setting", scenario.get("description", ""))).strip_edges(),
		"objective": str(scenario.get("objective", "")).strip_edges(),
		"current_turn": resolved_cycle_id,
		"narrative_phase": str(StoryState.get_state().get("current_narrative_phase", "")).strip_edges() if StoryState and StoryState.has_method("get_state") else "",
		"suggested_narrative_phase": str(StoryState.get_state().get("suggested_narrative_phase", "")).strip_edges() if StoryState and StoryState.has_method("get_state") else "",
		"turn_context": _build_turn_context(opts.get("external_input", {})),
		"recent_story_log": _recent_story_log_summaries(),
	}
	var version := str(cfg.get("version", "v1")).strip_edges().to_lower()
	var response: Dictionary = {}
	if version == "v2":
		response = await hub.scensyn_build_vis_story_v2_cycle(
			continuity_state,
			resolved_cycle_id,
			scenario_context,
			int(cfg.get("max_panels_per_turn", 12)),
			int(cfg.get("panels_to_render", 6)),
			str(cfg.get("selection_mode", "spread")).strip_edges(),
			cfg.get("panel_indices", []),
			int(cfg.get("max_concurrent_renders", 2)),
		)
	else:
		response = await hub.scensyn_build_vis_story_cycle(continuity_state, resolved_cycle_id, scenario_context)
	if not bool(response.get("ok", false)):
		return response

	var workspace_root: String = await hub.get_workspace_root()
	if String(workspace_root).strip_edges().is_empty():
		return {"ok": false, "error": "workspace root unavailable"}

	var rel_dir := str(cfg.get("output_dir", "scensyn/vis_story_exports")).strip_edges()
	if rel_dir.is_empty():
		rel_dir = "scensyn/vis_story_exports"
	var abs_dir := String(workspace_root).path_join(rel_dir)
	var mk_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mk_err != OK:
		return {"ok": false, "error": "failed to create vis_story export dir", "code": mk_err, "path": abs_dir}

	var version_suffix := ""
	if version == "v2":
		version_suffix = "_v2"
	var filename := "%s_cycle_%03d%s.json" % [
		_scenario_slug(scenario),
		resolved_cycle_id,
		version_suffix,
	]
	var abs_path := abs_dir.path_join(filename)
	var rel_path := rel_dir.path_join(filename)
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "failed to open vis_story export file", "path": abs_path}
	file.store_string(JSON.stringify(response.get("story_json", {}), "\t"))
	file.close()

	return {
		"ok": true,
		"cycle_id": resolved_cycle_id,
		"path": abs_path,
		"relative_path": rel_path,
		"story_json": response.get("story_json", {}),
		"translator_payload": response,
	}


func _build_turn_context(external_input: Dictionary = {}) -> Dictionary:
	var out := {}
	var latest: Dictionary = external_input if typeof(external_input) == TYPE_DICTIONARY else {}
	if latest.is_empty():
		if typeof(Global) == TYPE_NIL or not Global or not Global.has_method("get_metaprompt_manager"):
			return out
		var mgr = Global.get_metaprompt_manager()
		if mgr == null or not is_instance_valid(mgr):
			return out
		if mgr.has_method("get_latest_turn_context_for_prompt"):
			out["prompt_context"] = str(mgr.get_latest_turn_context_for_prompt("")).strip_edges()
		if not mgr.has_method("get_latest_external_input"):
			return out
		var latest_any: Variant = mgr.get_latest_external_input()
		if typeof(latest_any) != TYPE_DICTIONARY:
			return out
		latest = latest_any
	if latest.is_empty():
		return out

	var turn_packet: Dictionary = latest.get("turn_packet", {}) if typeof(latest.get("turn_packet", {})) == TYPE_DICTIONARY else {}
	var shared: Dictionary = turn_packet.get("shared", {}) if typeof(turn_packet.get("shared", {})) == TYPE_DICTIONARY else {}
	var seeker: Dictionary = turn_packet.get("seeker", {}) if typeof(turn_packet.get("seeker", {})) == TYPE_DICTIONARY else {}
	var narrator: Dictionary = turn_packet.get("narrator", {}) if typeof(turn_packet.get("narrator", {})) == TYPE_DICTIONARY else {}
	var diviner: Dictionary = turn_packet.get("diviner", {}) if typeof(turn_packet.get("diviner", {})) == TYPE_DICTIONARY else {}
	var echo: Dictionary = turn_packet.get("echo", {}) if typeof(turn_packet.get("echo", {})) == TYPE_DICTIONARY else {}
	var matrix: Dictionary = latest.get("matrix_resolution", {}) if typeof(latest.get("matrix_resolution", {})) == TYPE_DICTIONARY else {}

	out["window_label"] = str(latest.get("label", "")).strip_edges()
	out["odu_name"] = str(latest.get("odu", matrix.get("odu_name", ""))).strip_edges()
	out["province_or_site"] = str(shared.get("province_or_site", matrix.get("province_or_site", ""))).strip_edges()
	out["tapestry_region_primary"] = str(shared.get("tapestry_region_primary", matrix.get("tapestry_region_primary", ""))).strip_edges()
	out["tapestry_region_secondary"] = str(matrix.get("tapestry_region_secondary", "")).strip_edges()
	out["predicament_family"] = str(shared.get("predicament_family", matrix.get("predicament_family", ""))).strip_edges()
	out["world_domain_focus"] = str(shared.get("world_domain_focus", matrix.get("world_domain_focus", ""))).strip_edges()
	out["visible_world_effect"] = str(seeker.get("visible_world_effect", seeker.get("seeker_manifestation_cue", ""))).strip_edges()
	out["next_question"] = str(narrator.get("next_question", "")).strip_edges()
	out["failure_state_risk"] = str(echo.get("failure_state_risk", matrix.get("failure_state_risk", ""))).strip_edges()
	out["flourishing_state_potential"] = str(seeker.get("flourishing_state_potential", matrix.get("flourishing_state_potential", ""))).strip_edges()
	out["diviner_operation_cue"] = str(diviner.get("diviner_operation_cue", "")).strip_edges()
	out["diviner_shadow_tendency"] = str(diviner.get("shadow_tendency", "")).strip_edges()
	out["echo_omen_cue"] = str(echo.get("echo_omen_cue", "")).strip_edges()
	out["resonance"] = str(latest.get("resonance", "")).strip_edges()
	return out


func _recent_story_log_summaries(limit: int = 4) -> Array[String]:
	var out: Array[String] = []
	if StoryState == null or not StoryState.has_method("get_state"):
		return out
	var state: Dictionary = StoryState.get_state()
	var log_any: Variant = state.get("story_log", [])
	if typeof(log_any) != TYPE_ARRAY:
		return out
	var log: Array = log_any
	var start := maxi(0, log.size() - maxi(1, limit))
	for i in range(start, log.size()):
		var entry_any: Variant = log[i]
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender := str(entry.get("sender", "")).strip_edges()
		var message := str(entry.get("message", "")).strip_edges()
		if message.is_empty():
			continue
		if message.length() > 180:
			message = message.substr(0, 180).strip_edges() + "..."
		out.append(("%s: %s" % [sender, message]).strip_edges())
	return out


func _get_vis_story_config(scenario: Dictionary) -> Dictionary:
	var direct_any: Variant = scenario.get("vis_story", {})
	var direct: Dictionary = direct_any if typeof(direct_any) == TYPE_DICTIONARY else {}
	return _normalize_vis_story_config(direct)


func _normalize_vis_story_config(raw: Dictionary) -> Dictionary:
	var cfg := raw.duplicate(true)
	cfg["enabled"] = _boolish(cfg.get("enabled", false))
	cfg["version"] = _normalize_vis_story_version(cfg.get("version", "v1"))
	cfg["output_dir"] = str(cfg.get("output_dir", "scensyn/vis_story_exports")).strip_edges()
	cfg["render_on_export"] = _boolish(cfg.get("render_on_export", false))
	cfg["render_purpose"] = str(cfg.get("render_purpose", "vis_story_v2_turn")).strip_edges().to_lower()
	if cfg["render_purpose"] == "":
		cfg["render_purpose"] = "vis_story_v2_turn"
	cfg["render_submission_mode"] = str(cfg.get("render_submission_mode", "scheduler")).strip_edges().to_lower()
	if not (str(cfg["render_submission_mode"]) in ["scheduler", "batch_fanout"]):
		cfg["render_submission_mode"] = "scheduler"
	cfg["scheduler_workflow_path"] = str(cfg.get("scheduler_workflow_path", "")).strip_edges()
	cfg["scheduler_presets_path"] = str(cfg.get("scheduler_presets_path", "")).strip_edges()
	cfg["scheduler_output_root"] = str(cfg.get("scheduler_output_root", "")).strip_edges()
	cfg["scheduler_throttle_ms"] = clampi(_intish(cfg.get("scheduler_throttle_ms", 300), 300), 0, 10000)
	cfg["max_panels_per_turn"] = clampi(_intish(cfg.get("max_panels_per_turn", 12), 12), 1, 24)
	cfg["panels_to_render"] = clampi(_intish(cfg.get("panels_to_render", 6), 6), 1, 24)
	cfg["panels_to_render"] = mini(int(cfg["panels_to_render"]), int(cfg["max_panels_per_turn"]))
	cfg["selection_mode"] = _normalize_selection_mode(cfg.get("selection_mode", "spread"))
	cfg["panel_indices"] = _parse_panel_indices(cfg.get("panel_indices", ""))
	cfg["max_concurrent_renders"] = clampi(_intish(cfg.get("max_concurrent_renders", 2), 2), 1, 24)
	return cfg


func _boolish(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value).strip_edges().to_lower()
			return text in ["1", "true", "yes", "on", "enabled"]
		_:
			return false


func _intish(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value).strip_edges()
			if text.is_valid_int():
				return int(text)
			return fallback
		_:
			return fallback


func _normalize_vis_story_version(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	return "v2" if text == "v2" else "v1"


func _normalize_selection_mode(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	if text in ["first_n", "spread", "hero_only", "custom"]:
		return text
	return "spread"


func _parse_panel_indices(value: Variant) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	var raw_text := str(value).strip_edges()
	if raw_text.is_empty():
		return out
	for token in raw_text.split(","):
		var text := str(token).strip_edges()
		if not text.is_valid_int():
			continue
		var idx := int(text)
		if idx < 1 or idx > 24 or seen.has(idx):
			continue
		seen[idx] = true
		out.append(idx)
	return out


func _scenario_slug(scenario: Dictionary) -> String:
	var raw := str(scenario.get("name", scenario.get("_scenario_name", "scenario"))).strip_edges().to_lower()
	if raw.is_empty():
		raw = "scenario"
	var chars: Array[String] = []
	for ch in raw:
		var code := ch.unicode_at(0)
		var is_alnum := (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
		if is_alnum:
			chars.append(ch)
		elif ch in [" ", "-", "_"]:
			if chars.is_empty() or chars[chars.size() - 1] != "_":
				chars.append("_")
	var slug := ""
	for item in chars:
		slug += item
	slug = slug.strip_edges()
	while slug.ends_with("_"):
		slug = slug.left(slug.length() - 1)
	return slug if not slug.is_empty() else "scenario"
