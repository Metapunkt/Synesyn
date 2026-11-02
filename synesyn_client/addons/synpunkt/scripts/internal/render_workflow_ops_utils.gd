extends RefCounted
class_name SynpunktRenderWorkflowOpsUtils

const WorkflowUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_utils.gd")

static func find_existing_workflow_artifact_id_by_hash(owner: Control, workflow_hash: String) -> String:
	var wh := String(workflow_hash).strip_edges()
	var hub: Node = owner.get("_hub")
	if wh.is_empty() or not hub:
		return ""
	var seen_any: Variant = owner.get("_render_seen_workflow_hash_to_workflow_id")
	var seen: Dictionary = seen_any if typeof(seen_any) == TYPE_DICTIONARY else {}
	if seen.has(wh):
		return str(seen.get(wh, "")).strip_edges()
	var q: Dictionary = await hub.query_artifacts_by_type("json.workflow", 200)
	if not bool(q.get("ok", false)):
		return ""
	var result: Dictionary = q.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var row: Array = r_any
		var aid := str(owner.call("_row_get", cols, row, "id")).strip_edges()
		if aid.is_empty():
			continue
		var meta_txt := str(owner.call("_row_get", cols, row, "metadata_json")).strip_edges()
		if meta_txt.is_empty():
			meta_txt = str(owner.call("_row_get", cols, row, "metadata")).strip_edges()
		if meta_txt.is_empty():
			meta_txt = str(owner.call("_row_get", cols, row, "meta_json")).strip_edges()
		var h := str(owner.call("_workflow_hash_from_metadata_json", meta_txt))
		if not h.is_empty() and h == wh:
			seen[wh] = aid
			owner.set("_render_seen_workflow_hash_to_workflow_id", seen)
			return aid
	return ""


static func workflow_health_info(owner: Control) -> Dictionary:
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if not workflow_json:
		return {"status": "error", "message": "Workflow health: field missing"}
	var raw := workflow_json.text.strip_edges()
	if raw.is_empty():
		return {"status": "warn", "message": "Workflow health: empty"}
	var wf_any: Variant = JSON.parse_string(raw)
	if typeof(wf_any) != TYPE_DICTIONARY:
		return {"status": "error", "message": "Workflow health: invalid JSON/object"}
	var wf_norm: Dictionary = WorkflowUtilsScript.extract_comfy_prompt_graph(wf_any)
	if not bool(wf_norm.get("ok", false)):
		return {"status": "error", "message": "Workflow health: invalid (%s)" % str(wf_norm.get("error", "workflow_invalid"))}
	var prompt_any: Variant = wf_norm.get("prompt", {})
	var node_count := (prompt_any as Dictionary).size() if typeof(prompt_any) == TYPE_DICTIONARY else 0
	if typeof(prompt_any) != TYPE_DICTIONARY:
		return {"status": "error", "message": "Workflow health: invalid (prompt graph missing)"}
	var prompt: Dictionary = prompt_any
	var missing_class_type: Array[String] = []
	var malformed_nodes := 0
	for node_id in prompt.keys():
		var node_any: Variant = prompt.get(node_id, null)
		if typeof(node_any) != TYPE_DICTIONARY:
			malformed_nodes += 1
			continue
		var node: Dictionary = node_any
		var class_type := str(node.get("class_type", "")).strip_edges()
		if class_type.is_empty():
			missing_class_type.append(str(node_id))
	if malformed_nodes > 0:
		return {"status": "error", "message": "Workflow health: invalid (%d malformed node entr%s)." % [malformed_nodes, "y" if malformed_nodes == 1 else "ies"]}
	if missing_class_type.size() > 0:
		var sample := ""
		var show_n := mini(missing_class_type.size(), 5)
		for i in range(show_n):
			if i > 0:
				sample += ", "
			sample += missing_class_type[i]
		if missing_class_type.size() > 5:
			sample += ", …"
		return {"status": "error", "message": "Workflow health: invalid (%d node(s) missing class_type: %s)" % [missing_class_type.size(), sample]}
	return {"status": "ok", "message": "Workflow health: valid (%d nodes)" % node_count}


static func workflow_health_status(owner: Control) -> String:
	var info: Dictionary = workflow_health_info(owner)
	return str(info.get("status", "error"))


static func workflow_health_message(owner: Control) -> String:
	var info: Dictionary = workflow_health_info(owner)
	return str(info.get("message", "Workflow health: invalid"))


static func render_route_label(owner: Control, payload: Variant = null) -> String:
	var mode := ""
	var provider := ""
	if payload != null and typeof(payload) == TYPE_DICTIONARY:
		var p: Dictionary = payload
		var routing_any: Variant = p.get("routing", {})
		var routing: Dictionary = routing_any if typeof(routing_any) == TYPE_DICTIONARY else {}
		if not routing.is_empty():
			mode = str(routing.get("mode", "")).strip_edges().to_lower()
			provider = str(routing.get("provider", "")).strip_edges().to_lower()
		if mode.is_empty() or provider.is_empty():
			var req_any: Variant = p.get("normalized_request", {})
			var req: Dictionary = req_any if typeof(req_any) == TYPE_DICTIONARY else {}
			var req_routing_any: Variant = req.get("routing", {})
			var req_routing: Dictionary = req_routing_any if typeof(req_routing_any) == TYPE_DICTIONARY else {}
			if mode.is_empty():
				mode = str(req_routing.get("mode", p.get("mode", ""))).strip_edges().to_lower()
			if provider.is_empty():
				provider = str(req_routing.get("provider", p.get("provider", ""))).strip_edges().to_lower()
	if mode.is_empty():
		mode = "direct"
	if provider.is_empty():
		provider = "comfyui"
	return "%s/%s" % [mode, provider]


static func render_error_status(owner: Control, stage: String, err: Variant) -> String:
	var details := error_details_text(err)
	var dlow := details.to_lower()
	var route := render_route_label(owner, err)
	var route_mode := route.get_slice("/", 0)
	var cat := "unknown"
	if dlow.find("timeout") != -1 or dlow.find("cant_connect") != -1 or dlow.find("unable to connect") != -1 or dlow.find("connection refused") != -1:
		if stage == "results_query" or route_mode == "hub":
			cat = "hub_unreachable"
		else:
			cat = "comfy_unreachable"
	elif dlow.find("invalid") != -1 and (dlow.find("workflow") != -1 or dlow.find("class_type") != -1):
		cat = "workflow_invalid"
	elif dlow.find("patch") != -1 and dlow.find("json") != -1:
		cat = "patch_invalid"
	elif stage == "no_outputs":
		cat = "output_missing"
	var prefix := "Render %s" % stage
	return "%s [%s] [%s]: %s" % [prefix, cat, route, details if not details.is_empty() else "unknown_error"]


static func refresh_workflow_health_indicator(owner: Control) -> void:
	var workflow_health_label: Label = owner.get("_workflow_health_label")
	if workflow_health_label:
		workflow_health_label.text = workflow_health_message(owner)
		var status: String = workflow_health_status(owner)
		var cached: Variant = owner.get("_workflow_health_dark_theme")
		var is_dark_theme: bool
		if cached == null:
			var default_fg: Color = workflow_health_label.get_theme_color("font_color", "Label")
			is_dark_theme = (default_fg.r + default_fg.g + default_fg.b) > 1.5
			owner.set("_workflow_health_dark_theme", is_dark_theme)
		else:
			is_dark_theme = bool(cached)
		var color: Color
		if status == "ok":
			color = Color(0.45, 0.82, 0.58, 1) if is_dark_theme else Color(0.16, 0.53, 0.29, 1)
		elif status == "warn":
			color = Color(0.93, 0.70, 0.36, 1) if is_dark_theme else Color(0.45, 0.38, 0.18, 1)
		else:
			color = Color(0.98, 0.47, 0.47, 1) if is_dark_theme else Color(0.74, 0.2, 0.2, 1)
		workflow_health_label.add_theme_color_override("font_color", color)


static func on_workflow_json_text_changed(owner: Control) -> void:
	refresh_workflow_health_indicator(owner)


static func error_details_text(err: Variant) -> String:
	if err == null:
		return ""
	var t := typeof(err)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = err
		var e := str(d.get("error", "")).strip_edges()
		var det := str(d.get("details", "")).strip_edges()
		var status := int(d.get("status", 0))
		var out := e
		if out.is_empty():
			out = str(d.get("message", d.get("detail", ""))).strip_edges()
		if status > 0:
			out += (" status=%d" % status) if not out.is_empty() else ("status=%d" % status)
		if not det.is_empty():
			out += (" details=%s" % det) if not out.is_empty() else det
		var body: Variant = d.get("body", null)
		if body != null:
			var btxt := ""
			if typeof(body) == TYPE_DICTIONARY:
				var bd: Dictionary = body
				var btype := str(bd.get("type", "")).strip_edges()
				var bmsg := str(bd.get("message", "")).strip_edges()
				var bdetails := str(bd.get("details", "")).strip_edges()
				if not btype.is_empty():
					btxt = btype
				if not bmsg.is_empty():
					btxt += (" | " if not btxt.is_empty() else "") + bmsg
				if not bdetails.is_empty():
					btxt += (" | " if not btxt.is_empty() else "") + bdetails
			else:
				btxt = str(body).strip_edges()
			if btxt.length() > 220:
				btxt = btxt.substr(0, 220) + "…"
			if not btxt.is_empty():
				out += (" body=%s" % btxt) if not out.is_empty() else btxt
		return out
	return str(err).strip_edges()


static func on_clear_workflow_inputs_pressed(owner: Control) -> void:
	var workflow_json: TextEdit = owner.get("_workflow_json")
	var patch_json: TextEdit = owner.get("_patch_json")
	if workflow_json:
		workflow_json.text = ""
	if patch_json:
		patch_json.text = ""
	owner.set("_common_param_targets", {})
	var common_prompt: TextEdit = owner.get("_common_prompt")
	var common_negative: TextEdit = owner.get("_common_negative")
	var common_seed: SpinBox = owner.get("_common_seed")
	var common_seed_randomize: BaseButton = owner.get("_common_seed_randomize")
	var common_steps: SpinBox = owner.get("_common_steps")
	var common_cfg: SpinBox = owner.get("_common_cfg")
	var common_denoise: SpinBox = owner.get("_common_denoise")
	var common_width: SpinBox = owner.get("_common_width")
	var common_height: SpinBox = owner.get("_common_height")
	if common_prompt:
		common_prompt.text = ""
	if common_negative:
		common_negative.text = ""
	if common_seed:
		common_seed.value = 0.0
	if common_seed_randomize:
		common_seed_randomize.button_pressed = false
	if common_steps:
		common_steps.value = 20.0
	if common_cfg:
		common_cfg.value = 7.0
	if common_denoise:
		common_denoise.value = 1.0
	if common_width:
		common_width.value = 1024.0
	if common_height:
		common_height.value = 1024.0
	refresh_workflow_health_indicator(owner)
	owner.call("_set_status", "Render: cleared Workflow/Patch fields and Common params.")


static func on_test_comfy(owner: Control) -> void:
	var render: Node = owner.get("_render")
	if not render or not render.comfy:
		owner.call("_set_status", "ComfyUI: render service not initialized")
		return
	var comfy_url: LineEdit = owner.get("_comfy_url")
	var url := comfy_url.text.strip_edges() if comfy_url else ""
	render.set_comfy_base_url(url)
	owner.call("_remember_comfy_url", url)
	owner.call("_set_status", "ComfyUI: Testing %s ..." % (url if not url.is_empty() else "(empty url)"))
	var res: Dictionary = await render.comfy.test_comfy()
	if bool(res.get("ok", false)):
		owner.call("_set_status", "ComfyUI: OK")
		return
	var err := str(res.get("error", "")).strip_edges()
	var details := str(res.get("details", "")).strip_edges()
	var status := int(res.get("status", 0))
	var body_any: Variant = res.get("body", null)
	var body_s := ""
	if body_any != null:
		body_s = str(body_any)
		if body_s.length() > 180:
			body_s = body_s.substr(0, 180) + "…"
	var msg := err
	if msg.is_empty():
		msg = "unknown_error"
	if status > 0:
		msg += " status=%d" % status
	if not details.is_empty():
		msg += " details=%s" % details
	if not body_s.is_empty():
		msg += " body=%s" % body_s
	owner.call("_set_status", "ComfyUI: FAIL (%s)" % msg)


static func on_load_workflow_from_flowdoc(owner: Control) -> void:
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		owner.call("_set_status", "Load a SynDoc first.")
		return
	var frame: Dictionary = owner.call("_get_active_frame")
	if frame.is_empty():
		owner.call("_set_status", "No active frame.")
		return
	var blocks_any: Variant = frame.get("blocks", [])
	if typeof(blocks_any) != TYPE_ARRAY:
		owner.call("_set_status", "Active frame has no blocks.")
		return
	var blocks: Array = blocks_any
	var found_text := ""
	for b_any in blocks:
		if typeof(b_any) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = b_any
		var t := str(b.get("type", "")).strip_edges()
		if t == "comfy.workflow_json":
			found_text = str(b.get("text", "")).strip_edges()
			break
	if found_text.is_empty():
		var frames: Array = owner.call("_get_frames")
		for f_any in frames:
			if typeof(f_any) != TYPE_DICTIONARY:
				continue
			var f: Dictionary = f_any
			var fblocks_any: Variant = f.get("blocks", [])
			if typeof(fblocks_any) != TYPE_ARRAY:
				continue
			for bb_any in (fblocks_any as Array):
				if typeof(bb_any) != TYPE_DICTIONARY:
					continue
				var bb: Dictionary = bb_any
				var tt := str(bb.get("type", "")).strip_edges()
				if tt == "comfy.workflow_json":
					found_text = str(bb.get("text", "")).strip_edges()
					break
			if not found_text.is_empty():
				break
	if found_text.is_empty():
		owner.call("_set_status", "No comfy.workflow_json block found (active frame or any frame).")
		return
	var wf_any: Variant = JSON.parse_string(found_text)
	if typeof(wf_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Found comfy.workflow_json but it isn't valid JSON.")
		return
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if workflow_json:
		workflow_json.text = JSON.stringify(wf_any, "\t")
	owner.call("_sync_common_params_from_workflow_json", false)
	owner.call("_set_status", "Loaded workflow from SynDoc block (comfy.workflow_json).")


static func workflow_from_textbox(owner: Control) -> Dictionary:
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if not workflow_json:
		return {"ok": false, "error": "workflow_field_missing"}
	var raw := workflow_json.text.strip_edges()
	if raw.is_empty():
		return {"ok": false, "error": "workflow_json_empty"}
	var wf_any: Variant = JSON.parse_string(raw)
	if typeof(wf_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "workflow_json_invalid"}
	var wf_wrapped: Dictionary = wf_any
	var wf_norm: Dictionary = WorkflowUtilsScript.extract_comfy_prompt_graph(wf_wrapped)
	if not bool(wf_norm.get("ok", false)):
		return {"ok": false, "error": str(wf_norm.get("error", "workflow_invalid"))}
	var workflow_any: Variant = wf_norm.get("prompt", {})
	if typeof(workflow_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "workflow_prompt_missing"}
	return {"ok": true, "workflow": workflow_any}
