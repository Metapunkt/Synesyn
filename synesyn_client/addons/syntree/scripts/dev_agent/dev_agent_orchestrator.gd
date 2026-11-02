@tool
extends Node
class_name DevAgentOrchestrator

signal log_line(line: String)
signal loop_finished(ok: bool, summary: String)

var _panel: Object = null
var _conversation_manager: Object = null

var _running: bool = false
var _stop_requested: bool = false

func setup(panel_ref: Object, conversation_manager_ref: Object) -> void:
	_panel = panel_ref
	_conversation_manager = conversation_manager_ref

func is_running() -> bool:
	return _running

func stop() -> void:
	_stop_requested = true
	_emit_log("Stop requested.")

func start(task_text: String, max_iterations: int = 2) -> void:
	if _running:
		_emit_log("Loop already running.")
		return
	var task := String(task_text).strip_edges()
	if task.is_empty():
		_emit_log("Task is empty; nothing to do.")
		loop_finished.emit(false, "empty task")
		return
	var iters := clampi(int(max_iterations), 1, 10)
	_running = true
	_stop_requested = false
	call_deferred("_run_loop_async", task, iters)

func _emit_log(msg: String) -> void:
	log_line.emit("[%s] %s" % [Time.get_time_string_from_system(), String(msg)])

func _guard_ready() -> bool:
	if not Engine.is_editor_hint():
		_emit_log("Editor-only: loop requires editor context.")
		return false
	if _panel == null:
		_emit_log("Panel reference missing.")
		return false
	if _conversation_manager == null or not (_conversation_manager as Object).has_method("chat"):
		_emit_log("ConversationManager missing or has no chat().")
		return false
	# Side effects gated by Dev Agent toggle
	if (_panel as Object).has_method("_dev_agent_guard_or_warn"):
		if not bool((_panel as Object).call("_dev_agent_guard_or_warn")):
			_emit_log("Dev Agent is OFF. Enable it before running the loop.")
			return false
	return true

func _get_thread_id() -> String:
	if _panel != null and (_panel as Object).has_method("_get_current_thread_id_safe"):
		var tid := String((_panel as Object).call("_get_current_thread_id_safe")).strip_edges()
		return tid if not tid.is_empty() else "default"
	return "default"

func _read_json_file(path: String) -> Dictionary:
	var p := String(path).strip_edges()
	if p.is_empty() or not FileAccess.file_exists(p):
		return {}
	var raw := FileAccess.get_file_as_string(p)
	if raw.strip_edges().is_empty():
		return {}
	var any: Variant = JSON.parse_string(raw)
	return any if typeof(any) == TYPE_DICTIONARY else {}

func _extract_first_fenced_json(text: String) -> Dictionary:
	var parts := String(text).split("```")
	for i in range(1, parts.size(), 2):
		var block := String(parts[i]).strip_edges()
		# Strip leading language tag line if present.
		var nl := block.find("\n")
		if nl != -1 and block.substr(0, nl).strip_edges().to_lower() in ["json", "javascript"]:
			block = block.substr(nl + 1).strip_edges()
		if not block.begins_with("{"):
			continue
		var any: Variant = JSON.parse_string(block)
		if typeof(any) == TYPE_DICTIONARY:
			return any
	return {}

func _extract_run_spec_json(text: String) -> Dictionary:
	var d := _extract_first_fenced_json(text)
	if not d.is_empty():
		return d
	# Fallback: try parse between first '{' and last '}'.
	var s := String(text)
	var a := s.find("{")
	var b := s.rfind("}")
	if a != -1 and b != -1 and b > a:
		var sub := s.substr(a, b - a + 1)
		var any: Variant = JSON.parse_string(sub)
		if typeof(any) == TYPE_DICTIONARY:
			return any
	return {}

func _extract_unified_diff(text: String) -> String:
	var s := String(text)
	var idx := s.find("\n--- ")
	if idx == -1:
		if s.begins_with("--- "):
			idx = 0
	if idx == -1:
		idx = s.find("--- ")
	if idx == -1:
		return ""
	var tail := s.substr(idx).strip_edges()
	# Stop before a new major heading if present.
	var cut := tail.find("\n## ")
	if cut != -1:
		tail = tail.substr(0, cut).strip_edges()
	return tail

func _build_iteration_prompt(task: String, iteration_idx: int, last_run_manifest: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("TASK:\n%s" % task)
	parts.append("ITERATION: %d" % (iteration_idx + 1))
	if not last_run_manifest.is_empty():
		parts.append("LAST_RUN_MANIFEST (run.json):\n%s" % JSON.stringify(last_run_manifest, "  "))
	parts.append("OUTPUT REQUIREMENTS:\n- Provide a unified diff patch.\n- Provide a Run Spec JSON object.\n- If no change is needed, say STOP (all caps) and explain why.")
	return "\n\n".join(parts)

func _get_last_run_pointer_path() -> String:
	if _panel != null and (_panel as Object).has_method("_get_session_data_root_dir"):
		var root := String((_panel as Object).call("_get_session_data_root_dir")).strip_edges()
		if not root.is_empty():
			return root.path_join("syntree_artifacts").path_join("harness_last_run.json")
	return ""

func _wait_for_new_run(prev_run_id: String, timeout_s: float = 60.0) -> Dictionary:
	var start := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start) < (timeout_s * 1000.0):
		await get_tree().process_frame
		var ptr := _read_json_file(_get_last_run_pointer_path())
		if ptr.is_empty():
			continue
		var run_id := String(ptr.get("run_id", "")).strip_edges()
		if run_id.is_empty() or run_id == prev_run_id:
			continue
		var run_manifest_path := String(ptr.get("run_manifest_path", "")).strip_edges()
		if run_manifest_path.is_empty():
			continue
		var run := _read_json_file(run_manifest_path)
		if not run.is_empty():
			return run
	return {}

func _run_loop_async(task: String, max_iters: int) -> void:
	var ok := await _run_loop(task, max_iters)
	_running = false
	_stop_requested = false
	loop_finished.emit(ok, "completed" if ok else "stopped/failed")

func _run_loop(task: String, max_iters: int) -> bool:
	if not _guard_ready():
		return false
	var tid := _get_thread_id()
	_emit_log("Starting Dev Agent loop. thread=%s iters=%d" % [tid, max_iters])

	var last_run_manifest: Dictionary = {}
	var prev_run_id := ""
	var ptr0 := _read_json_file(_get_last_run_pointer_path())
	if not ptr0.is_empty():
		prev_run_id = String(ptr0.get("run_id", "")).strip_edges()
		var mp0 := String(ptr0.get("run_manifest_path", "")).strip_edges()
		if not mp0.is_empty():
			last_run_manifest = _read_json_file(mp0)

	for i in range(max_iters):
		if _stop_requested:
			_emit_log("Stopping before iteration %d." % (i + 1))
			return false

		_emit_log("Iteration %d/%d: asking model…" % [i + 1, max_iters])
		var prompt := _build_iteration_prompt(task, i, last_run_manifest)
		var res_any: Variant = await (_conversation_manager as Object).call("chat", prompt, tid)
		if typeof(res_any) != TYPE_DICTIONARY:
			_emit_log("Model call failed: invalid result type.")
			return false
		var res: Dictionary = res_any
		if not bool(res.get("success", false)):
			_emit_log("Model call failed: %s" % str(res.get("error", "unknown")))
			return false

		var txt := String(res.get("response", "")).strip_edges()
		if txt.to_upper().find("STOP") != -1 and txt.find("--- ") == -1:
			_emit_log("Model requested STOP.")
			return true

		var patch := _extract_unified_diff(txt)
		var run_spec := _extract_run_spec_json(txt)
		if patch.is_empty():
			_emit_log("No unified diff found in model output.")
		else:
			_emit_log("Applying patch (%d chars)…" % patch.length())
			if (_panel as Object).has_method("_dev_agent_apply_patch_text"):
				var ap_any: Variant = (_panel as Object).call("_dev_agent_apply_patch_text", patch)
				var ap: Dictionary = ap_any if typeof(ap_any) == TYPE_DICTIONARY else {}
				if not bool(ap.get("ok", false)):
					_emit_log("Patch apply failed: %s" % str(ap.get("error", ap)))
					last_run_manifest = {"ok": false, "error": "patch_apply_failed", "details": ap}
					continue
			else:
				_emit_log("Panel missing _dev_agent_apply_patch_text().")
				return false

		if run_spec.is_empty():
			_emit_log("No run spec JSON found; stopping.")
			return false

		_emit_log("Launching harness run…")
		if (_panel as Object).has_method("_dev_agent_launch_harness_from_spec"):
			var prev_ptr := _read_json_file(_get_last_run_pointer_path())
			prev_run_id = String(prev_ptr.get("run_id", "")).strip_edges()
			(_panel as Object).call("_dev_agent_launch_harness_from_spec", run_spec)
		else:
			_emit_log("Panel missing _dev_agent_launch_harness_from_spec().")
			return false

		_emit_log("Waiting for run.json…")
		var run := await _wait_for_new_run(prev_run_id, 90.0)
		if run.is_empty():
			_emit_log("Timed out waiting for run.json. (Did the harness run?)")
			return false
		last_run_manifest = run
		_emit_log("Run complete: ok=%s error=%s" % [str(run.get("ok", false)), str(run.get("error", ""))])

		if bool(run.get("ok", false)):
			_emit_log("Stopping: run ok.")
			return true

	_emit_log("Reached max iterations without success.")
	return false

