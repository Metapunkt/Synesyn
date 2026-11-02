extends RefCounted
class_name SynpunktRenderCommonParamsUtils

static func workflow_node_by_id(workflow: Dictionary, node_id: String) -> Dictionary:
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		return {}
	if workflow.has(nid):
		var n_any: Variant = workflow.get(nid)
		return n_any if typeof(n_any) == TYPE_DICTIONARY else {}
	for k_any in workflow.keys():
		if str(k_any).strip_edges() != nid:
			continue
		var n2_any: Variant = workflow.get(k_any)
		return n2_any if typeof(n2_any) == TYPE_DICTIONARY else {}
	return {}


static func link_node_id(link_any: Variant) -> String:
	if typeof(link_any) != TYPE_ARRAY:
		return ""
	var arr: Array = link_any
	if arr.is_empty():
		return ""
	return str(arr[0]).strip_edges()


static func resolve_text_target(workflow: Dictionary, node_id: String) -> Dictionary:
	var n: Dictionary = workflow_node_by_id(workflow, node_id)
	if n.is_empty():
		return {}
	var inputs_any: Variant = n.get("inputs", {})
	if typeof(inputs_any) != TYPE_DICTIONARY:
		return {}
	var inputs: Dictionary = inputs_any
	var ordered_keys: Array[String] = ["text", "prompt", "text_g", "text_l"]
	for key in ordered_keys:
		if not inputs.has(key):
			continue
		return {
			"node_id": node_id,
			"input": key,
			"value": str(inputs.get(key, "")),
		}
	return {}


static func detect_common_param_targets(workflow: Dictionary) -> Dictionary:
	var targets: Dictionary = {}
	var values: Dictionary = {}
	var ksampler_id := ""
	for node_id_any in workflow.keys():
		var node_id := str(node_id_any).strip_edges()
		var n_any: Variant = workflow.get(node_id_any)
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var class_type := str(n.get("class_type", "")).strip_edges()
		if class_type.begins_with("KSampler"):
			ksampler_id = node_id
			break
	if ksampler_id.is_empty():
		return {"ok": false, "error": "no_ksampler_node"}
	var ksampler: Dictionary = workflow_node_by_id(workflow, ksampler_id)
	var kinputs_any: Variant = ksampler.get("inputs", {})
	var kinputs: Dictionary = kinputs_any if typeof(kinputs_any) == TYPE_DICTIONARY else {}
	var numeric_keys: Array[String] = ["seed", "steps", "cfg", "denoise"]
	for key in numeric_keys:
		if not kinputs.has(key):
			continue
		targets[key] = {"node_id": ksampler_id, "input": key}
		values[key] = kinputs.get(key, null)
	var pos_node_id := link_node_id(kinputs.get("positive", null))
	if not pos_node_id.is_empty():
		var pos_target: Dictionary = resolve_text_target(workflow, pos_node_id)
		if not pos_target.is_empty():
			targets["prompt"] = {"node_id": str(pos_target.get("node_id", "")), "input": str(pos_target.get("input", "text"))}
			values["prompt"] = str(pos_target.get("value", ""))
	var neg_node_id := link_node_id(kinputs.get("negative", null))
	if not neg_node_id.is_empty():
		var neg_target: Dictionary = resolve_text_target(workflow, neg_node_id)
		if not neg_target.is_empty():
			targets["negative"] = {"node_id": str(neg_target.get("node_id", "")), "input": str(neg_target.get("input", "text"))}
			values["negative"] = str(neg_target.get("value", ""))
	var latent_node_id := link_node_id(kinputs.get("latent_image", null))
	if latent_node_id.is_empty():
		for node_id_any2 in workflow.keys():
			var node_id2 := str(node_id_any2).strip_edges()
			var n2_any: Variant = workflow.get(node_id_any2)
			if typeof(n2_any) != TYPE_DICTIONARY:
				continue
			var n2: Dictionary = n2_any
			var class_type2 := str(n2.get("class_type", "")).strip_edges()
			if class_type2.findn("EmptyLatentImage") != -1:
				latent_node_id = node_id2
				break
	var latent_node: Dictionary = workflow_node_by_id(workflow, latent_node_id)
	if not latent_node.is_empty():
		var latent_inputs_any: Variant = latent_node.get("inputs", {})
		if typeof(latent_inputs_any) == TYPE_DICTIONARY:
			var latent_inputs: Dictionary = latent_inputs_any
			if latent_inputs.has("width"):
				targets["width"] = {"node_id": latent_node_id, "input": "width"}
				values["width"] = latent_inputs.get("width", null)
			if latent_inputs.has("height"):
				targets["height"] = {"node_id": latent_node_id, "input": "height"}
				values["height"] = latent_inputs.get("height", null)
	return {"ok": true, "targets": targets, "values": values}


static func sync_common_params_from_workflow_json(owner: Control, show_status: bool = false) -> void:
	owner.set("_common_param_targets", {})
	var parsed: Dictionary = owner.call("_workflow_from_textbox")
	if not bool(parsed.get("ok", false)):
		if show_status:
			owner.call("_set_status", "Common params: %s" % str(parsed.get("error", "workflow_invalid")))
		return
	var workflow_any: Variant = parsed.get("workflow", {})
	if typeof(workflow_any) != TYPE_DICTIONARY:
		if show_status:
			owner.call("_set_status", "Common params: workflow not found.")
		return
	var detected: Dictionary = detect_common_param_targets(workflow_any)
	if not bool(detected.get("ok", false)):
		if show_status:
			owner.call("_set_status", "Common params: %s" % str(detected.get("error", "detect_failed")))
		return
	var targets_any: Variant = detected.get("targets", {})
	owner.set("_common_param_targets", targets_any if typeof(targets_any) == TYPE_DICTIONARY else {})
	var values_any: Variant = detected.get("values", {})
	var values: Dictionary = values_any if typeof(values_any) == TYPE_DICTIONARY else {}
	var common_prompt: LineEdit = owner.get("_common_prompt")
	var common_negative: LineEdit = owner.get("_common_negative")
	var common_seed: SpinBox = owner.get("_common_seed")
	var common_steps: SpinBox = owner.get("_common_steps")
	var common_cfg: SpinBox = owner.get("_common_cfg")
	var common_denoise: SpinBox = owner.get("_common_denoise")
	var common_width: SpinBox = owner.get("_common_width")
	var common_height: SpinBox = owner.get("_common_height")
	if common_prompt and values.has("prompt"):
		common_prompt.text = str(values.get("prompt", ""))
	if common_negative and values.has("negative"):
		common_negative.text = str(values.get("negative", ""))
	if common_seed and values.has("seed") and values.get("seed") != null:
		common_seed.value = float(values.get("seed"))
	if common_steps and values.has("steps") and values.get("steps") != null:
		common_steps.value = float(values.get("steps"))
	if common_cfg and values.has("cfg") and values.get("cfg") != null:
		common_cfg.value = float(values.get("cfg"))
	if common_denoise and values.has("denoise") and values.get("denoise") != null:
		common_denoise.value = float(values.get("denoise"))
	if common_width and values.has("width") and values.get("width") != null:
		common_width.value = float(values.get("width"))
	if common_height and values.has("height") and values.get("height") != null:
		common_height.value = float(values.get("height"))
	if show_status:
		var targets: Dictionary = owner.get("_common_param_targets")
		owner.call("_set_status", "Common params: detected %d editable targets." % targets.size())


static func upsert_patch(patches: Array, node_id: String, input_key: String, value: Variant) -> void:
	var nid := String(node_id).strip_edges()
	var ikey := String(input_key).strip_edges()
	if nid.is_empty() or ikey.is_empty():
		return
	for i in range(patches.size()):
		var p_any: Variant = patches[i]
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		if str(p.get("node_id", "")).strip_edges() == nid and str(p.get("input", "")).strip_edges() == ikey:
			p["value"] = value
			patches[i] = p
			return
	patches.append({"node_id": nid, "input": ikey, "value": value})


static func on_common_apply_to_patch_pressed(owner: Control) -> void:
	var patch_json: TextEdit = owner.get("_patch_json")
	if not patch_json:
		owner.call("_set_status", "Common params: Patch JSON field missing.")
		return
	var common_param_targets_any: Variant = owner.get("_common_param_targets")
	var common_param_targets: Dictionary = common_param_targets_any if typeof(common_param_targets_any) == TYPE_DICTIONARY else {}
	if common_param_targets.is_empty():
		owner.call("_set_status", "Common params: nothing detected yet. Click Detect first.")
		return
	var patches: Array = []
	var ptxt := patch_json.text.strip_edges()
	if not ptxt.is_empty():
		var p_any: Variant = JSON.parse_string(ptxt)
		if typeof(p_any) != TYPE_ARRAY:
			owner.call("_set_status", "Common params: Patch JSON must be an array.")
			return
		patches = p_any
	var common_seed: SpinBox = owner.get("_common_seed")
	var common_seed_randomize: BaseButton = owner.get("_common_seed_randomize")
	var common_prompt: LineEdit = owner.get("_common_prompt")
	var common_negative: LineEdit = owner.get("_common_negative")
	var common_steps: SpinBox = owner.get("_common_steps")
	var common_cfg: SpinBox = owner.get("_common_cfg")
	var common_denoise: SpinBox = owner.get("_common_denoise")
	var common_width: SpinBox = owner.get("_common_width")
	var common_height: SpinBox = owner.get("_common_height")
	var seed_value := int(round(common_seed.value)) if common_seed else 0
	if common_seed_randomize and common_seed_randomize.button_pressed:
		seed_value = int(randi() % 2147483647)
		if common_seed:
			common_seed.value = float(seed_value)
	var key_to_value: Dictionary = {
		"prompt": common_prompt.text if common_prompt else "",
		"negative": common_negative.text if common_negative else "",
		"seed": seed_value,
		"steps": int(round(common_steps.value)) if common_steps else 20,
		"cfg": float(common_cfg.value) if common_cfg else 7.0,
		"denoise": float(common_denoise.value) if common_denoise else 1.0,
		"width": int(round(common_width.value)) if common_width else 1024,
		"height": int(round(common_height.value)) if common_height else 1024,
	}
	var changed := 0
	for key_any in key_to_value.keys():
		var key := str(key_any)
		if not common_param_targets.has(key):
			continue
		var tgt_any: Variant = common_param_targets.get(key, {})
		if typeof(tgt_any) != TYPE_DICTIONARY:
			continue
		var tgt: Dictionary = tgt_any
		var nid := str(tgt.get("node_id", "")).strip_edges()
		var ikey := str(tgt.get("input", "")).strip_edges()
		if nid.is_empty() or ikey.is_empty():
			continue
		upsert_patch(patches, nid, ikey, key_to_value.get(key))
		changed += 1
	patch_json.text = JSON.stringify(patches, "\t")
	owner.call("_set_status", "Common params: applied %d values to Patch JSON." % changed)
