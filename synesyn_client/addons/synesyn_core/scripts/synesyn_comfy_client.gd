extends Node
class_name SynesynComfyClient

# Minimal ComfyUI client (shared, cross-app).
# Based on the original SynPunktRenderBridge implementation.
#
# - POST /prompt (submit workflow)
# - GET /history/{prompt_id} (poll until complete)
# - GET /view?... (download images)

signal status_changed(text: String)
signal progress_changed(stage: String, percent: float)
signal render_completed(result: Dictionary)
signal render_failed(error: String, details: String)

var comfy_base_url: String = "http://127.0.0.1:8188"
var _ws: WebSocketPeer
var _ws_client_id: String = ""

func _ready() -> void:
	_ws = WebSocketPeer.new()

func set_base_url(url: String) -> void:
	comfy_base_url = url.strip_edges().rstrip("/")

func _http_request(method: int, url: String, headers: PackedStringArray, body: String = "", timeout_sec: float = 20.0) -> Array:
	# IMPORTANT: HTTPRequest nodes cannot run concurrent requests. Use one node per request.
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return [false, {"error": "request_failed", "details": str(err), "url": url}]
	var res = await http.request_completed
	http.queue_free()
	# res shape: [result_code, response_code, headers, body]
	var result_code: int = int(res[0])
	var response_code: int = int(res[1])
	if result_code != HTTPRequest.RESULT_SUCCESS:
		# Network-level failures often have response_code == 0.
		return [
			false,
			{
				"error": "http_request_failed",
				"details": "result_code=%d" % result_code,
				"result_code": result_code,
				"status": response_code,
				"url": url,
			},
		]
	return [true, res]

func _get_json(url: String) -> Dictionary:
	var headers := PackedStringArray(["Accept: application/json"])
	var ok_and_res: Array = await _http_request(HTTPClient.METHOD_GET, url, headers, "", 20.0)
	if not bool(ok_and_res[0]):
		var err_d: Dictionary = ok_and_res[1] if typeof(ok_and_res[1]) == TYPE_DICTIONARY else {}
		err_d["ok"] = false
		return err_d
	var res = ok_and_res[1]
	var code: int = int(res[1])
	var body: PackedByteArray = res[3]
	var txt := body.get_string_from_utf8()
	var parsed: Variant = {} if txt.is_empty() else JSON.parse_string(txt)
	if code < 200 or code >= 300:
		return {"ok": false, "status": code, "error": "http_error", "body": parsed}
	return {"ok": true, "status": code, "data": parsed}

func _get_bytes(url: String) -> Dictionary:
	var headers := PackedStringArray(["Accept: */*"])
	var ok_and_res: Array = await _http_request(HTTPClient.METHOD_GET, url, headers, "", 30.0)
	if not bool(ok_and_res[0]):
		var err_d: Dictionary = ok_and_res[1] if typeof(ok_and_res[1]) == TYPE_DICTIONARY else {}
		err_d["ok"] = false
		return err_d
	var res = ok_and_res[1]
	var code: int = int(res[1])
	var body: PackedByteArray = res[3]
	if code < 200 or code >= 300:
		return {"ok": false, "status": code, "error": "http_error"}
	return {"ok": true, "status": code, "bytes": body}

func _post_json(url: String, payload: Dictionary) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	var body := JSON.stringify(payload)
	var ok_and_res: Array = await _http_request(HTTPClient.METHOD_POST, url, headers, body, 30.0)
	if not bool(ok_and_res[0]):
		var err_d: Dictionary = ok_and_res[1] if typeof(ok_and_res[1]) == TYPE_DICTIONARY else {}
		err_d["ok"] = false
		return err_d
	var res = ok_and_res[1]
	var code: int = int(res[1])
	var buf: PackedByteArray = res[3]
	var txt := buf.get_string_from_utf8()
	var parsed: Variant = {} if txt.is_empty() else JSON.parse_string(txt)
	if code < 200 or code >= 300:
		return {"ok": false, "status": code, "error": "http_error", "body": parsed}
	return {"ok": true, "status": code, "data": parsed}

func test_comfy() -> Dictionary:
	# /system_stats exists on ComfyUI
	status_changed.emit("Testing ComfyUI...")
	return await _get_json(comfy_base_url + "/system_stats")

func submit_workflow(workflow: Dictionary, client_id: String = "") -> Dictionary:
	status_changed.emit("Submitting workflow to ComfyUI...")
	var cid := client_id.strip_edges()
	if cid.is_empty():
		cid = "synesyn_%d" % int(Time.get_ticks_usec())
	var payload := {"prompt": workflow, "client_id": cid}
	var res := await _post_json(comfy_base_url + "/prompt", payload)
	if not bool(res.get("ok", false)):
		return res
	var data: Variant = res.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "invalid_response"}
	var d: Dictionary = data
	var pid := str(d.get("prompt_id", "")).strip_edges()
	if pid.is_empty():
		return {"ok": false, "error": "missing_prompt_id", "data": d}
	return {"ok": true, "prompt_id": pid}

func apply_patches(workflow: Dictionary, patches: Array) -> Dictionary:
	"""
	Patch workflow inputs in a stable way.
	Patch schema (v1):
	  [{"node_id":"3","input":"seed","value":123}, ...]
	This only patches top-level node "inputs" dictionaries.
	"""
	var wf := workflow.duplicate(true)
	var applied: Array = []
	for p_any in patches:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		var node_id := str(p.get("node_id", "")).strip_edges()
		var input_key := str(p.get("input", "")).strip_edges()
		if node_id.is_empty() or input_key.is_empty():
			continue
		if not wf.has(node_id):
			continue
		var n_any: Variant = wf.get(node_id)
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var inputs_any: Variant = n.get("inputs", {})
		if typeof(inputs_any) != TYPE_DICTIONARY:
			inputs_any = {}
		var inputs: Dictionary = inputs_any
		inputs[input_key] = p.get("value", null)
		n["inputs"] = inputs
		wf[node_id] = n
		applied.append({"node_id": node_id, "input": input_key})
	return {"ok": true, "workflow": wf, "applied": applied}

func connect_progress_ws(client_id: String) -> void:
	# Best-effort: ComfyUI websocket progress (if available).
	_ws_client_id = client_id.strip_edges()
	if _ws_client_id.is_empty():
		return
	var base := comfy_base_url.strip_edges().rstrip("/")
	if base.is_empty():
		return
	var ws_url := base
	if ws_url.begins_with("https://"):
		ws_url = "wss://" + ws_url.trim_prefix("https://")
	elif ws_url.begins_with("http://"):
		ws_url = "ws://" + ws_url.trim_prefix("http://")
	ws_url += "/ws?clientId=%s" % _ws_client_id.uri_encode()
	_ws.connect_to_url(ws_url)

func disconnect_progress_ws() -> void:
	if _ws:
		_ws.close()
	_ws_client_id = ""

func poll_progress_ws() -> void:
	if not _ws:
		return
	_ws.poll()
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while _ws.get_available_packet_count() > 0:
		var txt := _ws.get_packet().get_string_from_utf8()
		if txt.is_empty():
			continue
		# Avoid spamming the editor output with JSON parse errors if the server sends non-JSON packets.
		# (Some WS endpoints send plaintext greetings like "Hello".)
		var t0 := txt.strip_edges()
		if not (t0.begins_with("{") or t0.begins_with("[")):
			continue
		var any: Variant = JSON.parse_string(t0)
		if typeof(any) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = any
		var typ := str(msg.get("type", "")).strip_edges()
		if typ == "progress":
			var data_any: Variant = msg.get("data", {})
			if typeof(data_any) == TYPE_DICTIONARY:
				var d: Dictionary = data_any
				var v := float(d.get("value", 0.0))
				var m := float(d.get("max", 1.0))
				var pct := 0.0
				if m > 0.0:
					pct = (v / m) * 100.0
				progress_changed.emit("comfy.progress", pct)
		elif typ == "status":
			status_changed.emit("Comfy status update received.")

func submit_render_request(request: Dictionary) -> Dictionary:
	"""
	Stable render request interface (legacy-compatible).
	Expected request keys:
	  - workflow: Dictionary (Comfy workflow prompt graph)
	  - patches: Array (optional)
	  - client_id: String (optional)
	Returns: {ok, prompt_id, workflow, applied_patches}
	"""
	var wf_any: Variant = request.get("workflow", {})
	if typeof(wf_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "workflow_required"}
	var workflow: Dictionary = wf_any
	var patches_any: Variant = request.get("patches", [])
	var patches: Array = patches_any if typeof(patches_any) == TYPE_ARRAY else []
	var client_id := str(request.get("client_id", "")).strip_edges()
	if client_id.is_empty():
		client_id = "synesyn_%d" % int(Time.get_ticks_usec())

	var patched := apply_patches(workflow, patches)
	if not bool(patched.get("ok", false)):
		render_failed.emit("patch_failed", str(patched.get("error", patched)))
		return patched
	var wf_patched: Dictionary = patched.get("workflow", {})
	var applied: Array = patched.get("applied", [])
	connect_progress_ws(client_id)
	var submit := await submit_workflow(wf_patched, client_id)
	if not bool(submit.get("ok", false)):
		render_failed.emit("submit_failed", str(submit.get("error", submit)))
		disconnect_progress_ws()
		return submit
	return {"ok": true, "prompt_id": submit.get("prompt_id", ""), "workflow": wf_patched, "applied_patches": applied, "client_id": client_id}

func poll_history_until_done(prompt_id: String, timeout_sec: float = 120.0, poll_interval: float = 0.5) -> Dictionary:
	var pid := prompt_id.strip_edges()
	if pid.is_empty():
		return {"ok": false, "error": "prompt_id_required"}
	status_changed.emit("Waiting for ComfyUI output...")
	var t0 := Time.get_ticks_msec()
	var timeout_ms := int(timeout_sec * 1000.0)
	while true:
		# Best-effort WS progress updates.
		poll_progress_ws()
		if (Time.get_ticks_msec() - t0) > timeout_ms:
			disconnect_progress_ws()
			render_failed.emit("timeout", "ComfyUI history poll timed out")
			return {"ok": false, "error": "timeout"}
		var res := await _get_json(comfy_base_url + "/history/" + pid)
		if bool(res.get("ok", false)):
			var data_any: Variant = res.get("data", {})
			if typeof(data_any) == TYPE_DICTIONARY:
				var data: Dictionary = data_any
				# ComfyUI returns a dict keyed by prompt_id
				if data.has(pid):
					var entry_any: Variant = data.get(pid)
					if typeof(entry_any) == TYPE_DICTIONARY:
						var entry: Dictionary = entry_any
						var outputs_any: Variant = entry.get("outputs", {})
						if typeof(outputs_any) == TYPE_DICTIONARY and (outputs_any as Dictionary).size() > 0:
							disconnect_progress_ws()
							render_completed.emit(entry)
							return {"ok": true, "history": entry}
		await get_tree().create_timer(poll_interval).timeout
	# Analyzer guard (should be unreachable)
	return {"ok": false, "error": "unreachable"}

func fetch_image_bytes(filename: String, subfolder: String, typ: String = "output") -> Dictionary:
	var fn := filename.strip_edges()
	if fn.is_empty():
		return {"ok": false, "error": "filename_required"}
	var sf := subfolder.strip_edges()
	var t := typ.strip_edges()
	if t.is_empty():
		t = "output"
	var url := "%s/view?filename=%s&subfolder=%s&type=%s" % [
		comfy_base_url,
		fn.uri_encode(),
		sf.uri_encode(),
		t.uri_encode(),
	]
	return await _get_bytes(url)
