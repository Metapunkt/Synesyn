extends RefCounted
class_name SynpunktRenderResultsLinksUtils

static func normalize_render_refs(mdict: Dictionary) -> Dictionary:
	var refs_any: Variant = mdict.get("refs", {})
	var refs_src: Dictionary = refs_any if typeof(refs_any) == TYPE_DICTIONARY else {}
	return {
		"render_request_artifact_id": str(refs_src.get("render_request_artifact_id", "")).strip_edges(),
		"workflow_artifact_id": str(refs_src.get("workflow_artifact_id", "")).strip_edges(),
		"prompt_artifact_id": str(refs_src.get("prompt_artifact_id", "")).strip_edges(),
		"sensor_snapshot_artifact_id": str(refs_src.get("sensor_snapshot_artifact_id", "")).strip_edges(),
		"syndoc_artifact_id": str(refs_src.get("syndoc_artifact_id", "")).strip_edges(),
		"closure_artifact_id": str(refs_src.get("closure_artifact_id", "")).strip_edges(),
		"context_graph_artifact_id": str(refs_src.get("context_graph_artifact_id", "")).strip_edges(),
		"prompt_chain_artifact_id": str(refs_src.get("prompt_chain_artifact_id", "")).strip_edges(),
	}


static func playback_route_ctx() -> Dictionary:
	return {"routing": {"mode": "hub", "provider": "substrate"}}


static func set_playback_error_status(owner: Control, stage: String, err: Variant) -> void:
	var route_ctx := playback_route_ctx()
	owner.call("_set_status", owner.call("_render_error_status", stage, {"routing": route_ctx.get("routing", {}), "error": err}))


static func update_render_artifact_details(owner: Control) -> void:
	var details: RichTextLabel = owner.get("_render_artifact_details")
	if not details:
		return
	var rr: ItemList = owner.get("_render_results")
	if not rr:
		details.text = "Select one artifact to view metadata and cross-links."
		return
	var target := str(owner.get("_last_render_selected_artifact_id")).strip_edges()
	if target.is_empty():
		var aids: Array = owner.call("_get_selected_render_artifact_ids")
		if aids.size() == 1:
			target = aids[0]
	if target.is_empty():
		details.text = "Select one artifact to view metadata and cross-links."
		return
	var ctx: Dictionary = current_render_artifact_context(owner)
	if ctx.is_empty():
		details.text = "Select one artifact to view metadata and cross-links."
		return
	set_render_artifact_details_from_context(owner, ctx, {})
	var seq := int(owner.get("_render_details_update_seq")) + 1
	owner.set("_render_details_update_seq", seq)
	kick_render_artifact_link_health_check(owner, ctx, seq)


static func current_render_artifact_context(owner: Control) -> Dictionary:
	var target := str(owner.get("_last_render_selected_artifact_id")).strip_edges()
	if target.is_empty():
		var aids: Array = owner.call("_get_selected_render_artifact_ids")
		if aids.size() == 1:
			target = aids[0]
	if target.is_empty():
		return {}
	var meta_txt := ""
	var rr: ItemList = owner.get("_render_results")
	if rr:
		for i in range(rr.item_count):
			var md: Variant = rr.get_item_metadata(i)
			if md == null or typeof(md) != TYPE_DICTIONARY:
				continue
			var m: Dictionary = md
			if str(m.get("artifact_id", "")).strip_edges() != target:
				continue
			meta_txt = str(m.get("metadata_json", "")).strip_edges()
			break
	if meta_txt.is_empty():
		var cache_any: Variant = owner.get("_render_results_cache")
		var cache: Array = cache_any if typeof(cache_any) == TYPE_ARRAY else []
		for row_any in cache:
			if typeof(row_any) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = row_any
			if str(row.get("artifact_id", "")).strip_edges() != target:
				continue
			meta_txt = str(row.get("metadata_json", "")).strip_edges()
			break
	var mdict := owner.call("_metadata_dict_from_text", meta_txt)
	var refs: Dictionary = normalize_render_refs(mdict)
	var prov_any: Variant = mdict.get("provenance", {})
	var provenance: Dictionary = prov_any if typeof(prov_any) == TYPE_DICTIONARY else {}
	var created := ""
	var uri := ""
	var h := ""
	var at := ""
	var cache_any2: Variant = owner.get("_render_results_cache")
	var cache2: Array = cache_any2 if typeof(cache_any2) == TYPE_ARRAY else []
	for row_any2 in cache2:
		if typeof(row_any2) != TYPE_DICTIONARY:
			continue
		var row2: Dictionary = row_any2
		if str(row2.get("artifact_id", "")).strip_edges() != target:
			continue
		created = str(row2.get("created_at", "")).strip_edges()
		uri = str(row2.get("uri", "")).strip_edges()
		h = str(row2.get("hash", "")).strip_edges()
		at = str(row2.get("artifact_type", "")).strip_edges()
		break
	return {
		"artifact_id": target,
		"metadata_json": meta_txt,
		"metadata": mdict,
		"refs": refs,
		"provenance": provenance,
		"created_at": created,
		"uri": uri,
		"hash": h,
		"artifact_type": at,
	}


static func render_link_health_label(link_id: String, key: String, health: Dictionary) -> String:
	var lid := String(link_id).strip_edges()
	if lid.is_empty():
		return "N/A (not generated in this run)"
	if health.has(key):
		return "OK" if bool(health.get(key, false)) else "MISSING (id not found in current workspace)"
	return "CHECKING…"

static func render_link_status_for_context(ctx: Dictionary, key: String, link_id: String, health: Dictionary) -> String:
	var lid := String(link_id).strip_edges()
	var prov_any: Variant = ctx.get("provenance", {})
	var prov: Dictionary = prov_any if typeof(prov_any) == TYPE_DICTIONARY else {}
	if lid.is_empty():
		if key == "render_request":
			return "MISSING (not linked)"
		if key == "workflow":
			var wh := str(prov.get("workflow_hash_sha256", "")).strip_edges()
			return "N/A (inline workflow)" if not wh.is_empty() else "MISSING (no workflow link/hash)"
		if key == "prompt":
			return "N/A (no prompt artifact)"
		return "N/A"
	if health.has(key):
		return "OK" if bool(health.get(key, false)) else "MISSING (id not found in current workspace)"
	return "CHECKING…"


static func set_render_artifact_details_from_context(owner: Control, ctx: Dictionary, health: Dictionary = {}) -> void:
	var details: RichTextLabel = owner.get("_render_artifact_details")
	if not details:
		return
	var target := str(ctx.get("artifact_id", "")).strip_edges()
	if target.is_empty():
		details.text = "Select one artifact to view metadata and cross-links."
		return
	var meta_txt := str(ctx.get("metadata_json", "")).strip_edges()
	var created := str(ctx.get("created_at", "")).strip_edges()
	var uri := str(ctx.get("uri", "")).strip_edges()
	var h := str(ctx.get("hash", "")).strip_edges()
	var at := str(ctx.get("artifact_type", "")).strip_edges()
	var mdict := owner.call("_metadata_dict_from_text", meta_txt)
	var refs: Dictionary = normalize_render_refs(mdict)
	var rr_id := str(refs.get("render_request_artifact_id", "")).strip_edges()
	var wf_id := str(refs.get("workflow_artifact_id", "")).strip_edges()
	var pr_id := str(refs.get("prompt_artifact_id", "")).strip_edges()
	var prov_any: Variant = ctx.get("provenance", {})
	var prov: Dictionary = prov_any if typeof(prov_any) == TYPE_DICTIONARY else {}
	var ext := str(owner.call("_artifact_ext_from_uri", uri))
	var sz := str(owner.call("_artifact_size_human", int(owner.call("_artifact_size_from_uri", uri))))
	var name := str(owner.call("_artifact_display_name_for_id", target, meta_txt))
	var lines: Array[String] = []
	lines.append("[b]Name:[/b] %s" % (name if not name.is_empty() else "(unnamed)"))
	lines.append("[b]Artifact:[/b] %s" % target)
	lines.append("[b]Created:[/b] %s" % (created if not created.is_empty() else "?"))
	lines.append("[b]Type:[/b] %s    [b]Ext:[/b] %s    [b]Size:[/b] %s" % [at if not at.is_empty() else "image.generated", ext if not ext.is_empty() else "?", sz])
	lines.append("[b]Render request:[/b] %s  (%s)" % [rr_id, render_link_status_for_context(ctx, "render_request", rr_id, health)])
	lines.append("[b]Workflow:[/b] %s  (%s)" % [wf_id, render_link_status_for_context(ctx, "workflow", wf_id, health)])
	lines.append("[b]Prompt:[/b] %s  (%s)" % [pr_id, render_link_status_for_context(ctx, "prompt", pr_id, health)])
	var route_mode := str(prov.get("route_mode", "")).strip_edges()
	if route_mode.is_empty():
		route_mode = str(prov.get("routing_mode", "")).strip_edges()
	if route_mode.is_empty():
		route_mode = "direct"
	var route_provider := str(prov.get("route_provider", "")).strip_edges()
	if route_provider.is_empty():
		route_provider = str(prov.get("provider", "comfyui")).strip_edges()
	lines.append("[b]Route:[/b] %s/%s" % [route_mode, route_provider])
	var seed_info_any: Variant = prov.get("seed_info", {})
	if typeof(seed_info_any) == TYPE_DICTIONARY:
		var seed_info: Dictionary = seed_info_any
		var seeds_any: Variant = seed_info.get("seeds", [])
		var offsets_any: Variant = seed_info.get("offsets", [])
		var seeds: Array = seeds_any if typeof(seeds_any) == TYPE_ARRAY else []
		var offsets: Array = offsets_any if typeof(offsets_any) == TYPE_ARRAY else []
		var seed_text := str(seeds[0]) if seeds.size() > 0 else "(none)"
		lines.append("[b]Seed:[/b] %s  [b]Offsets:[/b] %d" % [seed_text, offsets.size()])
	var models_any: Variant = prov.get("model_identifiers", [])
	var models: Array = models_any if typeof(models_any) == TYPE_ARRAY else []
	if models.size() > 0:
		var model_sample := ""
		var mi := 0
		for m_any in models:
			if mi >= 3:
				break
			var m := str(m_any).strip_edges()
			if m.is_empty():
				continue
			model_sample += (", " if not model_sample.is_empty() else "") + m
			mi += 1
		if not model_sample.is_empty():
			lines.append("[b]Model(s):[/b] %s" % model_sample)
	var patches_any: Variant = prov.get("workflow_patch_set", [])
	var patches: Array = patches_any if typeof(patches_any) == TYPE_ARRAY else []
	lines.append("[b]Patches:[/b] %d" % patches.size())
	var inputs_any: Variant = prov.get("inputs", [])
	var inputs: Array = inputs_any if typeof(inputs_any) == TYPE_ARRAY else []
	if inputs.size() > 0:
		lines.append("[b]Trace:[/b] image -> render_request -> workflow/prompt/inputs")
		for in_any in inputs.slice(0, 6):
			if typeof(in_any) != TYPE_DICTIONARY:
				continue
			var inp: Dictionary = in_any
			var in_id := str(inp.get("artifact_id", "")).strip_edges()
			var in_type := str(inp.get("artifact_type", "")).strip_edges()
			if in_id.is_empty() and in_type.is_empty():
				continue
			lines.append("  - %s  (%s)" % [in_id if not in_id.is_empty() else "inline", in_type if not in_type.is_empty() else "?"])
	if not h.is_empty():
		lines.append("[b]Hash:[/b] %s" % h.left(24))
	details.text = "\n".join(lines)


static func artifact_id_exists(owner: Control, artifact_id: String) -> bool:
	var aid := String(artifact_id).strip_edges()
	var hub: Object = owner.get("_hub")
	if aid.is_empty() or not hub:
		return false
	var res: Dictionary = await hub.call("get_artifact_record_by_id", aid)
	if not bool(res.get("ok", false)):
		return false
	var result: Dictionary = res.get("result", {})
	var rows_any: Variant = result.get("rows", [])
	if typeof(rows_any) != TYPE_ARRAY:
		return false
	return (rows_any as Array).size() > 0


static func kick_render_artifact_link_health_check(owner: Control, ctx: Dictionary, seq: int) -> void:
	owner.call_deferred("_render_artifact_link_health_check_async", ctx, seq)


static func render_artifact_link_health_check_async(owner: Control, ctx: Dictionary, seq: int) -> void:
	var hub: Object = owner.get("_hub")
	if not hub:
		return
	var target := str(ctx.get("artifact_id", "")).strip_edges()
	if target.is_empty():
		return
	var refs_any: Variant = ctx.get("refs", {})
	var refs: Dictionary = refs_any if typeof(refs_any) == TYPE_DICTIONARY else {}
	var health: Dictionary = {}
	var rr_id := str(refs.get("render_request_artifact_id", "")).strip_edges()
	var wf_id := str(refs.get("workflow_artifact_id", "")).strip_edges()
	var pr_id := str(refs.get("prompt_artifact_id", "")).strip_edges()
	if not rr_id.is_empty():
		health["render_request"] = await artifact_id_exists(owner, rr_id)
	if not wf_id.is_empty():
		health["workflow"] = await artifact_id_exists(owner, wf_id)
	if not pr_id.is_empty():
		health["prompt"] = await artifact_id_exists(owner, pr_id)
	if seq != int(owner.get("_render_details_update_seq")):
		return
	if target != str(owner.get("_last_render_selected_artifact_id")).strip_edges():
		return
	set_render_artifact_details_from_context(owner, ctx, health)


static func load_workflow_from_render_request_artifact(owner: Control, rr_id: String) -> void:
	var rid := String(rr_id).strip_edges()
	var hub: Object = owner.get("_hub")
	if rid.is_empty() or not hub:
		return
	owner.call("_set_status", "Render playback: loading render_request %s…" % rid.left(12))
	var rr_res: Dictionary = await hub.call("get_artifact_json", rid)
	if not bool(rr_res.get("ok", false)):
		set_playback_error_status(owner, "playback_render_request", rr_res.get("error", rr_res))
		return
	var rr_any: Variant = rr_res.get("json", {})
	if typeof(rr_any) != TYPE_DICTIONARY:
		set_playback_error_status(owner, "playback_render_request", "render_request JSON invalid")
		return
	var rr: Dictionary = rr_any
	var wf: Dictionary = rr.get("workflow", {})
	var wf_id := str(wf.get("artifact_id", "")).strip_edges()
	var workflow_dict: Dictionary = {}
	var workflow_source := ""
	var wf_inline_any: Variant = wf.get("inline", {})
	var wf_inline: Dictionary = wf_inline_any if typeof(wf_inline_any) == TYPE_DICTIONARY else {}
	if not wf_id.is_empty():
		owner.call("_set_status", "Render playback: loading workflow %s…" % wf_id.left(12))
		var fetched2: Dictionary = await hub.call("get_artifact_json", wf_id)
		if bool(fetched2.get("ok", false)):
			var wf_any2: Variant = fetched2.get("json", {})
			if typeof(wf_any2) == TYPE_DICTIONARY:
				workflow_dict = wf_any2
				workflow_source = "artifact"
	# No compatibility fallback is needed for deployment, but inline is valid request data.
	# If a request carries inline workflow, prefer it over failing playback.
	if workflow_dict.is_empty() and not wf_inline.is_empty():
		workflow_dict = wf_inline
		workflow_source = "inline"
	if workflow_dict.is_empty():
		set_playback_error_status(owner, "playback_workflow", "render_request has neither loadable workflow.artifact_id nor inline workflow")
		return
	var patches_any: Variant = rr.get("patches", [])
	var patches: Array = patches_any if typeof(patches_any) == TYPE_ARRAY else []
	var routing_any: Variant = rr.get("routing", {})
	var routing: Dictionary = routing_any if typeof(routing_any) == TYPE_DICTIONARY else {}
	var comfy_base_url := str(routing.get("comfy_base_url", "")).strip_edges()
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if workflow_json:
		workflow_json.text = JSON.stringify(workflow_dict, "\t")
		owner.call("_sync_common_params_from_workflow_json", false)
	var patch_json: TextEdit = owner.get("_patch_json")
	if patch_json:
		patch_json.text = JSON.stringify(patches, "\t") if patches.size() > 0 else ""
	var comfy_url: LineEdit = owner.get("_comfy_url")
	if comfy_url and not comfy_base_url.is_empty():
		comfy_url.text = comfy_base_url
		owner.call("_remember_comfy_url", comfy_base_url)
	owner.call("_refresh_workflow_health_indicator")
	var route_hint := (" comfy=%s" % comfy_base_url) if not comfy_base_url.is_empty() else ""
	owner.call("_set_status", "Render playback: replaced editor from request %s (workflow=%s, patches=%d%s)." % [rid.left(12), workflow_source, patches.size(), route_hint])


static func on_render_details_load_linked_workflow(owner: Control) -> void:
	var ctx := current_render_artifact_context(owner)
	if ctx.is_empty():
		owner.call("_set_status", "Render details: select one artifact first.")
		return
	var refs_any: Variant = ctx.get("refs", {})
	var refs: Dictionary = refs_any if typeof(refs_any) == TYPE_DICTIONARY else {}
	var wf_id := str(refs.get("workflow_artifact_id", "")).strip_edges()
	if wf_id.is_empty():
		owner.call("_set_status", "Render details: no linked workflow_artifact_id.")
		return
	var hub: Object = owner.get("_hub")
	if not hub:
		return
	owner.call("_set_status", "Render: loading workflow %s…" % wf_id.left(12))
	var fetched: Dictionary = await hub.call("get_artifact_json", wf_id)
	if not bool(fetched.get("ok", false)):
		set_playback_error_status(owner, "playback_workflow", fetched.get("error", fetched))
		return
	var wf_any: Variant = fetched.get("json", {})
	if typeof(wf_any) != TYPE_DICTIONARY:
		set_playback_error_status(owner, "playback_workflow", "workflow artifact JSON invalid")
		return
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if workflow_json:
		workflow_json.text = JSON.stringify(wf_any, "\t")
		owner.call("_sync_common_params_from_workflow_json", false)
	owner.call("_set_status", "Render playback [hub/substrate]: loaded linked workflow %s." % wf_id.left(12))


static func on_render_details_load_linked_render_request(owner: Control) -> void:
	var ctx := current_render_artifact_context(owner)
	if ctx.is_empty():
		owner.call("_set_status", "Render details: select one artifact first.")
		return
	var refs_any: Variant = ctx.get("refs", {})
	var refs: Dictionary = refs_any if typeof(refs_any) == TYPE_DICTIONARY else {}
	var rr_id := str(refs.get("render_request_artifact_id", "")).strip_edges()
	if rr_id.is_empty():
		owner.call("_set_status", "Render details: no linked render_request_artifact_id.")
		return
	await load_workflow_from_render_request_artifact(owner, rr_id)
