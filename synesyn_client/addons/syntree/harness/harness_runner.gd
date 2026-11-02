extends Node

## Run directory for captures requested mid-run, set before post actions run.
var _capture_dir: String = ""

func _ready() -> void:
	# Editor: always run. Non-editor (e.g. CLI): run only when a pending run spec exists,
	# so the agent/Cursor can drive harness runs by writing _pending_run.json then launching this scene.
	if not OS.has_feature("editor"):
		if not FileAccess.file_exists(_pending_run_path()):
			get_tree().quit()
			return
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

func _runs_root_dir() -> String:
	var p := _artifacts_dir().path_join("runs")
	DirAccess.make_dir_recursive_absolute(p)
	return p

func _sanitize_filename(s: String) -> String:
	var out := String(s)
	out = out.replace(":", "-")
	out = out.replace("/", "_")
	out = out.replace("\\", "_")
	out = out.replace(" ", "_")
	out = out.replace("\t", "_")
	out = out.replace("\n", "_")
	return out

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

func _get_autoload(name: String) -> Node:
	var n := String(name).strip_edges()
	if n.is_empty():
		return null
	return get_node_or_null("/root/%s" % n)

func _call_with_args(target: Object, method: String, args: Array) -> Variant:
	if not is_instance_valid(target) or method.is_empty():
		return null
	match args.size():
		0: return target.call(method)
		1: return target.call(method, args[0])
		2: return target.call(method, args[0], args[1])
		3: return target.call(method, args[0], args[1], args[2])
		4: return target.call(method, args[0], args[1], args[2], args[3])
		_: return target.callv(method, args)

func _run_actions(actions_any: Variant) -> Array:
	# Returns array of action results.
	var results: Array = []
	if typeof(actions_any) != TYPE_ARRAY:
		return results
	for a_any in (actions_any as Array):
		if typeof(a_any) != TYPE_DICTIONARY:
			continue
		var a: Dictionary = a_any
		var kind := String(a.get("type", "call_autoload")).strip_edges()
		if kind != "call_autoload":
			results.append({"ok": false, "error": "Unsupported action type: %s" % kind})
			continue
		var autoload := String(a.get("autoload", "")).strip_edges()
		var method := String(a.get("method", "")).strip_edges()
		var args_any: Variant = a.get("args", [])
		if autoload.is_empty() or method.is_empty():
			results.append({"ok": false, "error": "Action missing autoload/method"})
			continue
		var target := _get_autoload(autoload)
		if not is_instance_valid(target):
			results.append({"ok": false, "error": "Autoload not found: %s" % autoload})
			continue
		if not (target as Object).has_method(method):
			results.append({"ok": false, "error": "Method not found: %s.%s" % [autoload, method]})
			continue
		var args: Array = args_any if typeof(args_any) == TYPE_ARRAY else []
		var call_res: Variant = _call_with_args(target as Object, method, args)
		results.append({"ok": true, "autoload": autoload, "method": method, "result": call_res})
	return results

func _get_node_from_scene_root(scene_root: Node, node_path: String) -> Node:
	var p := String(node_path).strip_edges()
	if p.is_empty() or not is_instance_valid(scene_root):
		return null
	if p.begins_with("/root/"):
		return get_node_or_null(p)
	# Treat as relative to scene root.
	return scene_root.get_node_or_null(p)

func _run_post_actions(scene_root: Node, actions_any: Variant) -> Array:
	# Post-load actions can call methods on the scene root or a node under it.
	#
	# Supported action types:
	# - call_scene_method: { "type": "call_scene_method", "method": "test_send_user_message", "args": [...] }
	# - call_node_method: { "type": "call_node_method", "node_path": "%InputField", "method": "grab_focus", "args": [...] }
	# - set_node_property: { "type": "set_node_property", "node_path": "%InputField", "property": "text", "value": "hello" }
	# - call_autoload: same as pre-scene action (for convenience)
	# - wait_seconds: { "type": "wait_seconds", "seconds": 30.0 }  — real-time wait (use for LLM responses)
	# - wait_frames:  { "type": "wait_frames",  "frames":  60    }  — frame-count wait
	# - capture_screenshot: { "type": "capture_screenshot", "name": "thinking-map" }
	#   Writes <run_dir>/<name>.png. The run always captures screenshot.png at the
	#   end; this is for the states a run passes through on the way there, so one
	#   session can yield several images instead of one session per image.
	# - mount_scene: { "type": "mount_scene", "scene_path": "res://...", "hide_current": true }
	#   Adds a second scene beside the first, sharing this process and therefore the
	#   session already in the autoloads. The product switches views with
	#   change_scene_to_file, which would free this runner mid-run and lose the
	#   artifacts, so a run that needs a second view of one session mounts it instead.
	#   Later actions still address the original scene root.
	var results: Array = []
	if typeof(actions_any) != TYPE_ARRAY:
		return results
	for a_any in (actions_any as Array):
		if typeof(a_any) != TYPE_DICTIONARY:
			continue
		var a: Dictionary = a_any
		var kind := String(a.get("type", "")).strip_edges()
		var args_any: Variant = a.get("args", [])
		var args: Array = args_any if typeof(args_any) == TYPE_ARRAY else []

		if kind == "wait_seconds":
			var secs := float(a.get("seconds", 0.0))
			await _wait_seconds(secs)
			results.append({"ok": true, "type": kind, "seconds": secs})
			continue

		if kind == "wait_frames":
			var frames := int(a.get("frames", 0))
			await _wait_frames(frames)
			results.append({"ok": true, "type": kind, "frames": frames})
			continue

		if kind == "capture_screenshot":
			var capture_name := String(a.get("name", "")).strip_edges()
			if capture_name.is_empty():
				results.append({"ok": false, "error": "capture_screenshot needs a name"})
				continue
			if _capture_dir.is_empty():
				results.append({"ok": false, "error": "No run directory for capture"})
				continue
			var capture_path := _capture_dir.path_join("%s.png" % _sanitize_filename(capture_name))
			var capture: Dictionary = await _capture_screenshot_png(capture_path)
			results.append({
				"ok": bool(capture.get("ok", false)),
				"error": str(capture.get("error", "")),
				"type": kind,
				"name": capture_name,
				"path": capture_path,
			})
			continue

		if kind == "mount_scene":
			var mount_path := String(a.get("scene_path", "")).strip_edges()
			var mount_packed: Variant = load(mount_path) if not mount_path.is_empty() else null
			if not (mount_packed is PackedScene):
				results.append({"ok": false, "error": "mount_scene could not load: %s" % mount_path})
				continue
			if bool(a.get("hide_current", true)) and scene_root is CanvasItem:
				(scene_root as CanvasItem).visible = false
			add_child((mount_packed as PackedScene).instantiate())
			await get_tree().process_frame
			await get_tree().process_frame
			results.append({"ok": true, "type": kind, "scene_path": mount_path})
			continue

		if kind == "call_scene_method":
			var method := String(a.get("method", "")).strip_edges()
			if method.is_empty() or not is_instance_valid(scene_root) or not (scene_root as Object).has_method(method):
				results.append({"ok": false, "error": "Scene method not found: %s" % method})
				continue
			var call_res: Variant = _call_with_args(scene_root as Object, method, args)
			results.append({"ok": true, "type": kind, "method": method, "result": call_res})
			continue

		if kind == "call_node_method":
			var node_path := String(a.get("node_path", "")).strip_edges()
			var method2 := String(a.get("method", "")).strip_edges()
			var node := _get_node_from_scene_root(scene_root, node_path)
			if not is_instance_valid(node):
				results.append({"ok": false, "error": "Node not found: %s" % node_path})
				continue
			if method2.is_empty() or not (node as Object).has_method(method2):
				results.append({"ok": false, "error": "Method not found on node: %s.%s" % [node_path, method2]})
				continue
			var call_res2: Variant = _call_with_args(node as Object, method2, args)
			results.append({"ok": true, "type": kind, "node_path": node_path, "method": method2, "result": call_res2})
			continue

		if kind == "set_node_property":
			var node_path2 := String(a.get("node_path", "")).strip_edges()
			var prop := String(a.get("property", "")).strip_edges()
			var node2 := _get_node_from_scene_root(scene_root, node_path2)
			if not is_instance_valid(node2):
				results.append({"ok": false, "error": "Node not found: %s" % node_path2})
				continue
			if prop.is_empty():
				results.append({"ok": false, "error": "Missing property name for node: %s" % node_path2})
				continue
			(node2 as Object).set(prop, a.get("value"))
			results.append({"ok": true, "type": kind, "node_path": node_path2, "property": prop})
			continue

		if kind == "call_autoload":
			# Reuse pre-scene action semantics.
			var autoload := String(a.get("autoload", "")).strip_edges()
			var method3 := String(a.get("method", "")).strip_edges()
			if autoload.is_empty() or method3.is_empty():
				results.append({"ok": false, "error": "Action missing autoload/method"})
				continue
			var target := _get_autoload(autoload)
			if not is_instance_valid(target):
				results.append({"ok": false, "error": "Autoload not found: %s" % autoload})
				continue
			if not (target as Object).has_method(method3):
				results.append({"ok": false, "error": "Method not found: %s.%s" % [autoload, method3]})
				continue
			var call_res3: Variant = _call_with_args(target as Object, method3, args)
			results.append({"ok": true, "type": kind, "autoload": autoload, "method": method3, "result": call_res3})
			continue

		results.append({"ok": false, "error": "Unsupported post action type: %s" % kind})
	return results

func _wait_frames(frame_count: int) -> void:
	var n := maxi(0, int(frame_count))
	for _i in range(n):
		await get_tree().process_frame

func _wait_seconds(secs: float) -> void:
	if secs <= 0.0:
		return
	await get_tree().create_timer(secs).timeout

func _capture_screenshot_png(path: String) -> Dictionary:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "No viewport image"}
	var err := img.save_png(path)
	return {"ok": err == OK, "error": "" if err == OK else "save_png error: %s" % str(err)}

func _dump_ui_metrics(root: Node) -> Dictionary:
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
	return {"count": items.size(), "controls": items}

func _read_file_tail_text(path: String, max_bytes: int = 256000) -> String:
	var p := String(path).strip_edges()
	if p.is_empty() or not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	if not f:
		return ""
	var n := int(f.get_length())
	var want := clampi(int(max_bytes), 1, 10_000_000)
	if n > want:
		f.seek(n - want)
	var txt := f.get_as_text()
	f.close()
	return txt

func _try_find_godot_log_file_path() -> String:
	# Best-effort: Godot's log file locations vary by platform/editor settings.
	# We look in a few common places and otherwise scan user://logs for any .log/.txt.
	var candidates: Array[String] = []
	candidates.append("user://logs/godot.log")
	candidates.append("user://logs/godot_editor.log")
	candidates.append("user://logs/editor.log")
	candidates.append("user://logs/project.log")
	candidates.append("user://godot.log")
	for c in candidates:
		if FileAccess.file_exists(c):
			return c

	var logs_dir := "user://logs"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(logs_dir)):
		return ""
	var dir := DirAccess.open(logs_dir)
	if not dir:
		return ""
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		var low := name.to_lower()
		if low.ends_with(".log") or low.ends_with(".txt"):
			var p := logs_dir.path_join(name)
			if FileAccess.file_exists(p):
				dir.list_dir_end()
				return p
	dir.list_dir_end()
	return ""

func _run() -> void:
	var started_at := Time.get_datetime_string_from_system(false, true)
	var pending_path := _pending_run_path()
	var pending := _read_json(pending_path)
	var artifacts_dir := _artifacts_dir()
	var out_summary := artifacts_dir.path_join("harness_last_run.json")

	if pending.is_empty():
		_write_json(out_summary, {"ok": false, "error": "No pending run spec found", "pending_path": pending_path, "started_at": started_at})
		get_tree().quit()
		return

	var spec_any: Variant = pending.get("spec", {})
	var spec: Dictionary = spec_any if typeof(spec_any) == TYPE_DICTIONARY else {}
	var thread_id := String(pending.get("thread_id", "")).strip_edges()
	if thread_id.is_empty():
		thread_id = "default"

	# REQUIRED: explicit scene_path for portability across projects.
	var scene_path := String(spec.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		_write_json(out_summary, {"ok": false, "error": "Run spec missing required field: scene_path", "started_at": started_at})
		get_tree().quit()
		return

	var packed := load(scene_path)
	if not (packed is PackedScene):
		_write_json(out_summary, {"ok": false, "error": "Failed to load scene", "scene_path": scene_path, "started_at": started_at})
		get_tree().quit()
		return

	# Standardized run folder contract.
	var ts := _sanitize_filename(started_at)
	var run_id := "%s__%s" % [ts, _sanitize_filename(thread_id)]
	var run_dir := _runs_root_dir().path_join(run_id)
	DirAccess.make_dir_recursive_absolute(run_dir)
	_capture_dir = run_dir
	var run_manifest_path := run_dir.path_join("run.json")
	var run_spec_path := run_dir.path_join("run_spec.json")
	var pending_copy_path := run_dir.path_join("pending_run.json")
	_write_json(run_spec_path, spec)
	_write_json(pending_copy_path, pending)

	# Optional pre-scene actions (autoload calls).
	var action_results := _run_actions(spec.get("actions", []))

	var inst := (packed as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	# Optional deterministic state hook.
	var state_any: Variant = spec.get("state", {})
	if typeof(state_any) == TYPE_DICTIONARY and (inst as Object).has_method("test_apply_state"):
		(inst as Object).call("test_apply_state", state_any)
		await get_tree().process_frame
		await get_tree().process_frame

	# Optional post-load actions (scene methods, node methods, etc.).
	# Inline wait_seconds/wait_frames actions are supported within the array for
	# multi-turn tests (send message → wait for AI → send next message → …).
	var post_action_results: Array = await _run_post_actions(inst, spec.get("post_actions", []))
	# Top-level waits run after all post_actions complete (backward compatible).
	await _wait_frames(int(spec.get("wait_frames_after_post", 0)))
	# Real-time wait: use wait_time_sec_after_post (or inline wait_seconds actions) instead
	# of wait_frames_after_post when waiting on LLM responses. Engine FPS in CLI mode can
	# be 200-600fps making frame counts unreliable for real-time coordination.
	var wait_sec: float = float(spec.get("wait_time_sec_after_post", 0.0))
	await _wait_seconds(wait_sec)

	# Artifacts (standard names under run_dir).
	var png_path := run_dir.path_join("screenshot.png")
	var metrics_path := run_dir.path_join("ui_metrics.json")
	var scene_logs_path := run_dir.path_join("scene_logs.json")
	var godot_log_tail_path := run_dir.path_join("godot_log_tail.txt")

	var shot := await _capture_screenshot_png(png_path)
	var metrics := _dump_ui_metrics(inst)
	_write_json(metrics_path, metrics)

	# Logs: prefer explicit scene hook, then also capture engine logfile tail (best-effort).
	var scene_logs_ok := false
	if (inst as Object).has_method("test_dump_logs"):
		var since_msec := int(spec.get("logs_since_msec", 0))
		(inst as Object).call("test_dump_logs", scene_logs_path, since_msec)
		scene_logs_ok = FileAccess.file_exists(scene_logs_path)

	var godot_log_src := _try_find_godot_log_file_path()
	var godot_tail := _read_file_tail_text(godot_log_src, int(spec.get("godot_log_tail_bytes", 256000)))
	if not godot_tail.is_empty():
		var f := FileAccess.open(godot_log_tail_path, FileAccess.WRITE)
		if f:
			f.store_string(godot_tail)
			f.close()

	var run_manifest := {
		"ok": bool(shot.get("ok", false)),
		"error": str(shot.get("error", "")),
		"thread_id": thread_id,
		"scene_path": scene_path,
		"started_at": started_at,
		"run_id": run_id,
		"run_dir": run_dir,
		"inputs": {
			"pending_run_path": pending_path,
			"pending_run_copy": pending_copy_path,
			"run_spec_path": run_spec_path,
		},
		"actions": action_results,
		"post_actions": post_action_results,
		"artifacts": {
			"screenshot_png": png_path,
			"ui_metrics_json": metrics_path,
			"scene_logs_json": scene_logs_path if scene_logs_ok else "",
			"godot_log_tail_txt": godot_log_tail_path if FileAccess.file_exists(godot_log_tail_path) else "",
			"godot_log_source_path": godot_log_src,
		},
	}
	_write_json(run_manifest_path, run_manifest)

	# Stable pointer to last run.
	_write_json(out_summary, {
		"ok": bool(run_manifest.get("ok", false)),
		"error": str(run_manifest.get("error", "")),
		"run_id": run_id,
		"run_dir": run_dir,
		"run_manifest_path": run_manifest_path,
		"started_at": started_at,
	})

	get_tree().quit()

