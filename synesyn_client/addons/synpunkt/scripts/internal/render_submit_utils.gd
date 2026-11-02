extends RefCounted
class_name SynpunktRenderSubmitUtils

const WorkflowUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_utils.gd")

static func on_submit_render(owner: Control) -> void:
	owner.call("_ensure_render_results_bound")
	var render: Node = owner.get("_render")
	if not render or not render.comfy:
		owner.call("_set_status", "Render: render service not initialized")
		return
	var comfy_url: LineEdit = owner.get("_comfy_url")
	var comfy_url_text := comfy_url.text.strip_edges() if comfy_url else ""
	render.set_comfy_base_url(comfy_url_text)
	owner.call("_remember_comfy_url", comfy_url_text)
	var workflow_json: TextEdit = owner.get("_workflow_json")
	var raw := workflow_json.text if workflow_json else ""
	var wf_any: Variant = JSON.parse_string(raw)
	if typeof(wf_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Render: invalid workflow JSON")
		return
	var wf_wrapped: Dictionary = wf_any
	var wf_norm: Dictionary = WorkflowUtilsScript.extract_comfy_prompt_graph(wf_wrapped)
	if not bool(wf_norm.get("ok", false)):
		owner.call("_set_status", "Render: %s" % str(wf_norm.get("error", "workflow_invalid")))
		return
	var workflow: Dictionary = wf_norm.get("prompt", {})
	var patches: Array = []
	var patch_json: TextEdit = owner.get("_patch_json")
	if patch_json:
		var ptxt := patch_json.text.strip_edges()
		if not ptxt.is_empty():
			var p_any: Variant = JSON.parse_string(ptxt)
			if typeof(p_any) == TYPE_ARRAY:
				patches = p_any
			else:
				owner.call("_set_status", "Render: Patch JSON must be an array")
				return
	var request_id := "rr_%d_%06d" % [int(Time.get_unix_time_from_system()), int(randi() % 1000000)]
	owner.set("_current_turn_id", request_id)
	SynesynSession.set_current_turn_id("synpunkt", request_id)
	var workflow_hash := WorkflowUtilsScript.hash_sha256_hex(WorkflowUtilsScript.canonical_json_bytes(workflow))
	var seed_info := WorkflowUtilsScript.extract_seed_info_from_patches(patches)
	var model_ids := WorkflowUtilsScript.extract_model_identifiers_from_workflow(workflow)
	var prompt_text := WorkflowUtilsScript.extract_prompt_text_from_patches(patches)
	var active_flowdoc_id := str(owner.get("_active_flowdoc_id")).strip_edges()
	var active_closure_id := str(owner.get("_active_closure_id")).strip_edges()
	var ref_context_graph: LineEdit = owner.get("_ref_context_graph")
	var ref_prompt_chain: LineEdit = owner.get("_ref_prompt_chain")
	var prompt_artifact_id := ""
	var hub: Node = owner.get("_hub")
	var session_id := str(owner.get("_session_id"))
	var last_sensor_snapshot_artifact_id := str(owner.get("_last_sensor_snapshot_artifact_id")).strip_edges()
	if not prompt_text.strip_edges().is_empty():
		var prompt_meta := {
			"provenance": {
				"generated_by": "synpunkt.render.prompt",
				"session_id": session_id,
				"turn_id": request_id,
				"request_id": request_id,
			},
			"refs": {
				"syndoc_artifact_id": active_flowdoc_id,
				"closure_artifact_id": active_closure_id,
				"context_graph_artifact_id": ref_context_graph.text.strip_edges() if ref_context_graph else "",
				"prompt_chain_artifact_id": ref_prompt_chain.text.strip_edges() if ref_prompt_chain else "",
			},
		}
		var pr_res: Dictionary = await hub.create_artifact_inline_text("text.prompt", prompt_text, prompt_meta)
		prompt_artifact_id = str(pr_res.get("id", "")).strip_edges()
	var workflow_persist_error := ""
	var should_save_workflow := bool(owner.get("_render_auto_save_workflows_enabled"))
	var workflow_artifact_id := ""
	var seen_any: Variant = owner.get("_render_seen_workflow_hash_to_workflow_id")
	var seen: Dictionary = seen_any if typeof(seen_any) == TYPE_DICTIONARY else {}
	if should_save_workflow and seen.has(workflow_hash):
		workflow_artifact_id = str(seen.get(workflow_hash, "")).strip_edges()
	if should_save_workflow and workflow_artifact_id.is_empty():
		workflow_artifact_id = await owner.call("_find_existing_workflow_artifact_id_by_hash", workflow_hash)
	if should_save_workflow and workflow_artifact_id.is_empty():
		var workflow_meta := {
			"provenance": {
				"generated_by": "synpunkt.render_bridge",
				"session_id": session_id,
				"turn_id": request_id,
				"request_id": request_id,
				"workflow_hash_sha256": workflow_hash,
				"seed_info": seed_info,
				"model_identifiers": model_ids,
			},
			"refs": {
				"syndoc_artifact_id": active_flowdoc_id,
				"closure_artifact_id": active_closure_id,
			}
		}
		var wf_res: Dictionary = await hub.create_artifact_inline_json("json.workflow", workflow, workflow_meta)
		workflow_artifact_id = str(wf_res.get("id", wf_res.get("artifact_id", ""))).strip_edges()
		if workflow_artifact_id.is_empty():
			var err_any: Variant = wf_res.get("error", wf_res)
			workflow_persist_error = str(err_any)
			push_warning("SynPunkt Render: failed to persist json.workflow: %s" % workflow_persist_error)
			owner.call("_set_status", "Render: warning: failed to persist json.workflow. Details: %s" % workflow_persist_error)
			should_save_workflow = false
		else:
			owner.set("_last_saved_workflow_artifact_id", workflow_artifact_id)
			seen[workflow_hash] = workflow_artifact_id
			owner.set("_render_seen_workflow_hash_to_workflow_id", seen)
			var workflow_select: OptionButton = owner.get("_workflow_select")
			if workflow_select:
				await owner.call("_refresh_render_workflow_selector")
				owner.call("_select_workflow_in_selector", workflow_artifact_id)
	var routing_mode := str(owner.call("_current_render_route_mode")).strip_edges().to_lower()
	if routing_mode != "hub":
		routing_mode = "direct"
	var req := {
		"schema_version": 1,
		"kind": "synesyn.render_request",
		"routing": {
			"mode": routing_mode,
			"provider": "comfyui",
			"comfy_base_url": comfy_url_text,
		},
		"output_routing": {
			"mode": "substrate",
			"render_request_artifact_type": "json.render_request",
			"images": {"artifact_type": "image.generated"},
		},
		"workflow": {
			"inline": workflow,
			"artifact_id": workflow_artifact_id,
			"hash_sha256": workflow_hash,
		},
		"patches": patches,
		"client": {
			"app_id": "synpunkt",
			"session_id": session_id,
			"request_id": request_id,
			"turn_id": request_id,
		},
		"refs": {
			"syndoc_artifact_id": active_flowdoc_id,
			"closure_artifact_id": active_closure_id,
			"context_graph_artifact_id": ref_context_graph.text.strip_edges() if ref_context_graph else "",
			"prompt_chain_artifact_id": ref_prompt_chain.text.strip_edges() if ref_prompt_chain else "",
			"workflow_artifact_id": workflow_artifact_id,
			"prompt_artifact_id": prompt_artifact_id,
			"sensor_snapshot_artifact_id": last_sensor_snapshot_artifact_id,
		},
	}
	var submit: Dictionary = await render.submit_render_request(req)
	if not bool(submit.get("ok", false)):
		owner.call("_set_status_err", owner.call("_render_error_status", "submit", submit))
		return
	var prompt_id := str(submit.get("prompt_id", "")).strip_edges()
	var route := str(owner.call("_render_route_label", submit))
	var mode := str(submit.get("mode", "")).strip_edges().to_lower()
	var job_id := str(submit.get("job_id", "")).strip_edges()
	if mode == "hub":
		owner.call("_set_status_ok", "Render submitted [%s]: job=%s" % [route, job_id if not job_id.is_empty() else "?"])
		await owner.call("_refresh_render_jobs", 100, "submit")
		await owner.call("_refresh_render_results_from_hub", 200, "post_submit_hub")
		return
	else:
		owner.call("_set_status_ok", "Render submitted [%s]: prompt=%s" % [route, prompt_id if not prompt_id.is_empty() else "?"])
	var submitted_request: Dictionary = submit.get("normalized_request", {})
	var hist: Dictionary = await render.comfy.poll_history_until_done(prompt_id, 180.0, 0.75)
	if not bool(hist.get("ok", false)):
		owner.call("_set_status_err", owner.call("_render_error_status", "history", hist))
		return
	var entry: Dictionary = hist.get("history", {})
	var outputs_any: Variant = entry.get("outputs", {})
	if typeof(outputs_any) != TYPE_DICTIONARY:
		owner.call("_set_status", owner.call("_render_error_status", "no_outputs", {"error": "no outputs in history entry"}))
		return
	var outputs: Dictionary = outputs_any
	var created_count := 0
	var image_artifact_ids: Array[String] = []
	var header_added := false
	var first_added_result_idx := -1
	var render_results: ItemList = owner.get("_render_results")
	for node_id in outputs.keys():
		var out_any: Variant = outputs.get(node_id, {})
		if typeof(out_any) != TYPE_DICTIONARY:
			continue
		var out: Dictionary = out_any
		var images_any: Variant = out.get("images", [])
		if typeof(images_any) != TYPE_ARRAY:
			continue
		var images: Array = images_any
		for img_any in images:
			if typeof(img_any) != TYPE_DICTIONARY:
				continue
			var img: Dictionary = img_any
			var filename := str(img.get("filename", "")).strip_edges()
			var subfolder := str(img.get("subfolder", "")).strip_edges()
			var typ := str(img.get("type", "output")).strip_edges()
			if filename.is_empty():
				continue
			var bytes_res: Dictionary = await render.comfy.fetch_image_bytes(filename, subfolder, typ)
			if not bool(bytes_res.get("ok", false)):
				continue
			var bytes: PackedByteArray = bytes_res.get("bytes", PackedByteArray())
			var inputs: Array = []
			if not workflow_artifact_id.is_empty():
				inputs.append({"artifact_id": workflow_artifact_id, "artifact_type": "json.workflow"})
			if not active_flowdoc_id.is_empty():
				inputs.append({"artifact_id": active_flowdoc_id, "artifact_type": "ui.syndoc"})
			if not active_closure_id.is_empty():
				inputs.append({"artifact_id": active_closure_id, "artifact_type": "ui.closure"})
			if not prompt_artifact_id.is_empty():
				inputs.insert(1, {"artifact_id": prompt_artifact_id, "artifact_type": "text.prompt"})
			if not last_sensor_snapshot_artifact_id.is_empty():
				inputs.append({"artifact_id": last_sensor_snapshot_artifact_id, "artifact_type": "json.sensor_snapshot"})
			var display_name := str(owner.call("_next_default_render_artifact_name"))
			var prov := {
				"generated_by": "synpunkt.render.comfyui",
				"session_id": session_id,
				"turn_id": request_id,
				"request_id": request_id,
				"route_mode": routing_mode,
				"route_provider": "comfyui",
				"prompt_id": prompt_id,
				"comfy_url": comfy_url_text,
				"node_id": str(node_id),
				"filename": filename,
				"subfolder": subfolder,
				"workflow_hash_sha256": workflow_hash,
				"seed_info": seed_info,
				"model_identifiers": model_ids,
				"workflow_patch_set": patches,
				"inputs": inputs,
			}
			var meta := {
				"provenance": prov,
				"ui": {"display_name": display_name},
				"refs": {
					"workflow_artifact_id": workflow_artifact_id,
					"prompt_artifact_id": prompt_artifact_id,
					"sensor_snapshot_artifact_id": last_sensor_snapshot_artifact_id,
					"syndoc_artifact_id": active_flowdoc_id,
					"closure_artifact_id": active_closure_id,
					"context_graph_artifact_id": ref_context_graph.text.strip_edges() if ref_context_graph else "",
					"prompt_chain_artifact_id": ref_prompt_chain.text.strip_edges() if ref_prompt_chain else "",
				}
			}
			var ext := "png"
			var fnl := filename.to_lower()
			if fnl.ends_with(".jpg") or fnl.ends_with(".jpeg"):
				ext = "jpg"
			var img_res: Dictionary = await hub.create_artifact_inline_bytes_base64("image.generated", bytes, ext, meta)
			var art_id := str(img_res.get("id", "")).strip_edges()
			if art_id.is_empty():
				art_id = str(img_res.get("artifact_id", "")).strip_edges()
			if art_id.is_empty():
				continue
			image_artifact_ids.append(art_id)
			if render_results:
				if not header_added:
					header_added = true
					var header := "Render %s (prompt %s)" % [request_id, prompt_id]
					var hidx := render_results.item_count
					render_results.add_item(header)
					render_results.set_item_disabled(hidx, true)
					render_results.set_item_metadata(hidx, {"kind": "header", "request_id": request_id, "prompt_id": prompt_id})
				var label := str(owner.call("_artifact_item_label", art_id, "", JSON.stringify(meta)))
				var ridx := render_results.item_count
				render_results.add_item(label)
				render_results.set_item_metadata(ridx, {"kind": "artifact", "artifact_id": art_id, "node_id": str(node_id), "request_id": request_id, "prompt_id": prompt_id, "display_name": display_name, "metadata_json": JSON.stringify(meta)})
				if first_added_result_idx == -1:
					first_added_result_idx = ridx
			created_count += 1
	var rr: Dictionary = submitted_request.duplicate(true)
	var rr_wf: Dictionary = rr.get("workflow", {})
	if not workflow_artifact_id.is_empty():
		rr_wf.erase("inline")
		rr_wf["artifact_id"] = workflow_artifact_id
	else:
		rr_wf["inline"] = workflow
		rr_wf["artifact_id"] = ""
	rr["workflow"] = rr_wf
	rr["provider_job"] = {"prompt_id": prompt_id}
	rr["outputs"] = {"image_artifact_ids": image_artifact_ids}
	rr["source_app"] = "synpunkt"
	var rr_inputs: Array = []
	if not workflow_artifact_id.is_empty():
		rr_inputs.append({"artifact_id": workflow_artifact_id, "artifact_type": "json.workflow"})
	else:
		rr_inputs.append({"artifact_type": "json.workflow", "hash_sha256": workflow_hash})
	var rr_meta := {"provenance": {"generated_by": "synpunkt.render.request", "inputs": rr_inputs}}
	var rr_res: Dictionary = await hub.create_artifact_inline_json("json.render_request", rr, rr_meta)
	var rr_id := str(rr_res.get("id", rr_res.get("artifact_id", ""))).strip_edges()
	if rr_id.is_empty():
		var rr_err_any: Variant = rr_res.get("error", rr_res)
		push_warning("SynPunkt Render: failed to persist json.render_request: %s" % str(rr_err_any))
	else:
		owner.set("_last_saved_render_request_artifact_id", rr_id)
		var full_refs := {
			"render_request_artifact_id": rr_id,
			"workflow_artifact_id": workflow_artifact_id,
			"prompt_artifact_id": prompt_artifact_id,
			"sensor_snapshot_artifact_id": last_sensor_snapshot_artifact_id,
			"syndoc_artifact_id": active_flowdoc_id,
			"closure_artifact_id": active_closure_id,
			"context_graph_artifact_id": ref_context_graph.text.strip_edges() if ref_context_graph else "",
			"prompt_chain_artifact_id": ref_prompt_chain.text.strip_edges() if ref_prompt_chain else "",
		}
		var patch_fail := 0
		for image_aid in image_artifact_ids:
			var patch_res: Dictionary = await hub.update_artifact_metadata(image_aid, {"refs": full_refs}, true)
			if not bool(patch_res.get("ok", false)):
				patch_fail += 1
		if patch_fail > 0:
			push_warning("SynPunkt Render: failed to patch render_request link for %d image artifact(s)." % patch_fail)
	if created_count <= 0:
		owner.call("_set_status_warn", "Render complete, but no image artifacts were persisted to Hub.")
		return
	if render_results and render_results.item_count > 0:
		var sel_idx := first_added_result_idx if first_added_result_idx != -1 else (render_results.item_count - 1)
		render_results.select(sel_idx)
		if render_results.has_method("ensure_current_is_visible"):
			render_results.ensure_current_is_visible()
	var first_id := image_artifact_ids[0] if image_artifact_ids.size() > 0 else ""
	await owner.call("_refresh_render_results_from_hub", 200, "post_submit")
	if not first_id.is_empty():
		owner.call("_select_render_result_by_artifact_id", first_id)
	var hint := ""
	if render_results == null:
		hint = " (RenderResults list not found; copy id from status)"
	var wf_hint := (" workflow=%s" % workflow_artifact_id.left(12)) if not workflow_artifact_id.is_empty() else " workflow=(not saved)"
	var rr_hint := (" render_request=%s" % rr_id.left(12)) if not rr_id.is_empty() else " render_request=(not saved)"
	var wf_err_hint := (" (workflow save error: %s)" % workflow_persist_error) if workflow_artifact_id.is_empty() and not workflow_persist_error.is_empty() else ""
	owner.call("_set_status_ok", "Render complete [%s]: %d image artifact(s)%s%s%s%s%s" % [route, created_count, (", first: %s" % first_id) if not first_id.is_empty() else "", hint, wf_hint, rr_hint, wf_err_hint])
