extends Node

const STORY_STAGE_SCENE := "res://ScenSyn/scenes/scensyn_story_stage.tscn"
const STORY_LOG_SCENE := "res://ScenSyn/scenes/game_session.tscn"

func _ready() -> void:
	# Run immediately; then quit.
	call_deferred("_run")

func _get_session_data_root_dir() -> String:
	var configured := ""
	if ProjectSettings.has_setting("synesyn/session_data_dir"):
		configured = String(ProjectSettings.get_setting("synesyn/session_data_dir", "")).strip_edges()
	if not configured.is_empty():
		DirAccess.make_dir_recursive_absolute(configured)
		return configured

	var docs := String(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).strip_edges()
	if not docs.is_empty():
		var d := docs.path_join("Synesyn")
		DirAccess.make_dir_recursive_absolute(d)
		return d

	var u := ProjectSettings.globalize_path("user://Synesyn")
	DirAccess.make_dir_recursive_absolute(u)
	return u

func _pending_run_path() -> String:
	return _get_session_data_root_dir().path_join("syntree_run_specs").path_join("_pending_run.json")

func _artifacts_dir() -> String:
	var p := _get_session_data_root_dir().path_join("syntree_artifacts")
	DirAccess.make_dir_recursive_absolute(p)
	return p

func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(String(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return {}
	return j.data if typeof(j.data) == TYPE_DICTIONARY else {}

func _resolve_scene_path(scene_key: String) -> String:
	var k := String(scene_key).strip_edges().to_lower()
	if k in ["story_stage", "stage", "visual"]:
		return STORY_STAGE_SCENE
	if k in ["game_session", "story_log", "log", "chat"]:
		return STORY_LOG_SCENE
	# Default to story_stage for now.
	return STORY_STAGE_SCENE

func _apply_state(spec: Dictionary) -> void:
	# Scenario selection
	var scenario := String(spec.get("scenario", "")).strip_edges()
	if not scenario.is_empty() and Engine.has_singleton("Global"):
		var g = Engine.get_singleton("Global")
		if is_instance_valid(g) and (g as Object).has_method("switch_scenario"):
			(g as Object).call("switch_scenario", scenario)

	# Toggles (minimal set)
	var toggles_any: Variant = spec.get("toggles", {})
	if typeof(toggles_any) == TYPE_DICTIONARY and Engine.has_singleton("Global"):
		var toggles: Dictionary = toggles_any
		var g2 = Engine.get_singleton("Global")
		if is_instance_valid(g2) and (g2 as Object).has_method("get_player_auto_input"):
			var pai = (g2 as Object).call("get_player_auto_input")
			if is_instance_valid(pai) and (pai as Object).has_method("set_enabled") and toggles.has("auto_player_input"):
				(pai as Object).call("set_enabled", bool(toggles.get("auto_player_input")), true)

func _capture_screenshot_png(path: String) -> Dictionary:
	# Wait until draw has occurred.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "No viewport image"}
	var err := img.save_png(path)
	return {"ok": err == OK, "error": "" if err == OK else "save_png error: %s" % str(err)}

func _dump_ui_metrics(root: Node) -> Dictionary:
	# Minimal metrics: Control rects/visibility for quick debugging.
	var items: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is Node:
				stack.append(c)
		if n is Control:
			var ctrl := n as Control
			items.append({
				"path": str(ctrl.get_path()),
				"visible": ctrl.visible,
				"pos": {"x": ctrl.position.x, "y": ctrl.position.y},
				"size": {"x": ctrl.size.x, "y": ctrl.size.y},
			})
	return {
		"count": items.size(),
		"controls": items,
	}

func _run() -> void:
	var started_at := Time.get_datetime_string_from_system(false, true)
	var pending_path := _pending_run_path()
	var pending := _read_json(pending_path)
	if pending.is_empty():
		_write_json(_artifacts_dir().path_join("harness_last_run.json"), {
			"ok": false,
			"error": "No pending run spec found",
			"pending_path": pending_path,
			"started_at": started_at,
		})
		get_tree().quit()
		return

	var spec_any: Variant = pending.get("spec", {})
	var spec: Dictionary = spec_any if typeof(spec_any) == TYPE_DICTIONARY else {}
	var scene_key := String(spec.get("scene", "story_stage"))
	var scene_path := _resolve_scene_path(scene_key)

	var packed := load(scene_path)
	if not (packed is PackedScene):
		_write_json(_artifacts_dir().path_join("harness_last_run.json"), {
			"ok": false,
			"error": "Failed to load scene",
			"scene_path": scene_path,
			"started_at": started_at,
		})
		get_tree().quit()
		return

	_apply_state(spec)

	var inst := (packed as PackedScene).instantiate()
	add_child(inst)

	# Let the scene settle.
	await get_tree().process_frame
	await get_tree().process_frame

	# Capture
	var ts := started_at.replace(":", "-").replace(" ", "_")
	var artifacts_dir := _artifacts_dir()
	var png_path := artifacts_dir.path_join("%s_%s.png" % [ts, scene_key])
	var metrics_path := artifacts_dir.path_join("%s_%s_metrics.json" % [ts, scene_key])

	var shot := await _capture_screenshot_png(png_path)
	var metrics := _dump_ui_metrics(inst)
	_write_json(metrics_path, metrics)

	_write_json(artifacts_dir.path_join("harness_last_run.json"), {
		"ok": bool(shot.get("ok", false)),
		"error": str(shot.get("error", "")),
		"scene_key": scene_key,
		"scene_path": scene_path,
		"scenario": str(spec.get("scenario", "")),
		"artifacts": {
			"screenshot_png": png_path,
			"ui_metrics_json": metrics_path,
		},
		"started_at": started_at,
	})

	get_tree().quit()

