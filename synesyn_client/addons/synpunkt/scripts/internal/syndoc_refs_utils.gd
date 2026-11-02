extends RefCounted
class_name SynpunktSyndocRefsUtils

static func sync_from_raw_json(owner: Control) -> void:
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	var raw := flowdoc_json.text.strip_edges() if flowdoc_json else ""
	if raw.is_empty():
		owner.set("_flowdoc_model", {})
		owner.call("_refresh_blocks_ui")
		return
	var parsed_any: Variant = JSON.parse_string(raw)
	if typeof(parsed_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Raw SynDoc JSON is not a dictionary (block editor paused).")
		return
	owner.set("_flowdoc_model", parsed_any)
	owner.call("_reconcile_edgeless_frame_nodes_with_frames")
	owner.call("_refresh_refs_ui_from_flowdoc", parsed_any)
	owner.call("_refresh_edgeless_preview")
	owner.call("_refresh_present_edgeless")
	owner.call("_refresh_frames_ui")
	owner.call("_refresh_blocks_ui")
	owner.call("_refresh_performer_ui")


static func refresh_refs_ui_from_flowdoc(owner: Control, flowdoc: Dictionary) -> void:
	var refs := read_flowdoc_refs(flowdoc)
	var ref_closure: LineEdit = owner.get("_ref_closure")
	var ref_context_graph: LineEdit = owner.get("_ref_context_graph")
	var ref_prompt_chain: LineEdit = owner.get("_ref_prompt_chain")
	var ref_projection: LineEdit = owner.get("_ref_projection")
	var ref_cluster: LineEdit = owner.get("_ref_cluster")
	if ref_closure:
		ref_closure.text = str(refs.get("closure_artifact_id", "")).strip_edges()
	if ref_context_graph:
		ref_context_graph.text = str(refs.get("context_graph_artifact_id", "")).strip_edges()
	if ref_prompt_chain:
		ref_prompt_chain.text = str(refs.get("prompt_chain_asset_id", "")).strip_edges()
	if ref_projection:
		ref_projection.text = str(refs.get("projection_artifact_id", "")).strip_edges()
	if ref_cluster:
		ref_cluster.text = str(refs.get("cluster_artifact_id", "")).strip_edges()


static func apply_refs_fields_to_flowdoc(owner: Control, flowdoc: Dictionary) -> void:
	if typeof(flowdoc) != TYPE_DICTIONARY:
		return
	var refs_any: Variant = flowdoc.get("refs", {})
	var refs: Dictionary = (refs_any as Dictionary) if typeof(refs_any) == TYPE_DICTIONARY else {}
	var ref_closure: LineEdit = owner.get("_ref_closure")
	var ref_context_graph: LineEdit = owner.get("_ref_context_graph")
	var ref_prompt_chain: LineEdit = owner.get("_ref_prompt_chain")
	var ref_projection: LineEdit = owner.get("_ref_projection")
	var ref_cluster: LineEdit = owner.get("_ref_cluster")
	var closure_id := ref_closure.text.strip_edges() if ref_closure else ""
	if closure_id.is_empty():
		closure_id = str(owner.get("_active_closure_id")).strip_edges()
	if not closure_id.is_empty():
		refs["closure_artifact_id"] = closure_id
	var cg_id := ref_context_graph.text.strip_edges() if ref_context_graph else ""
	var active_closure_json_any: Variant = owner.get("_active_closure_json")
	var active_closure_json: Dictionary = active_closure_json_any if typeof(active_closure_json_any) == TYPE_DICTIONARY else {}
	if cg_id.is_empty() and not active_closure_json.is_empty():
		cg_id = get_closure_context_graph_artifact_id(active_closure_json)
	if not cg_id.is_empty():
		refs["context_graph_artifact_id"] = cg_id
	var pc_id := ref_prompt_chain.text.strip_edges() if ref_prompt_chain else ""
	if not pc_id.is_empty():
		refs["prompt_chain_asset_id"] = pc_id
	var proj_id := ref_projection.text.strip_edges() if ref_projection else ""
	if proj_id.is_empty() and not active_closure_json.is_empty():
		proj_id = get_closure_projection_artifact_id(active_closure_json)
	if not proj_id.is_empty():
		refs["projection_artifact_id"] = proj_id
	var cluster_id := ref_cluster.text.strip_edges() if ref_cluster else ""
	if cluster_id.is_empty() and not active_closure_json.is_empty():
		cluster_id = get_closure_cluster_artifact_id(active_closure_json)
	if not cluster_id.is_empty():
		refs["cluster_artifact_id"] = cluster_id
	flowdoc["refs"] = refs
	var src_any: Variant = flowdoc.get("source", {})
	var src: Dictionary = (src_any as Dictionary) if typeof(src_any) == TYPE_DICTIONARY else {}
	if not closure_id.is_empty():
		src["closure_artifact_id"] = closure_id
	flowdoc["source"] = src


static func read_flowdoc_refs(flowdoc: Dictionary) -> Dictionary:
	var out := {
		"closure_artifact_id": "",
		"context_graph_artifact_id": "",
		"prompt_chain_asset_id": "",
		"projection_artifact_id": "",
		"cluster_artifact_id": "",
	}
	var refs_any: Variant = flowdoc.get("refs", {})
	if typeof(refs_any) == TYPE_DICTIONARY:
		var refs: Dictionary = refs_any
		out["closure_artifact_id"] = str(refs.get("closure_artifact_id", "")).strip_edges()
		out["context_graph_artifact_id"] = str(refs.get("context_graph_artifact_id", "")).strip_edges()
		out["prompt_chain_asset_id"] = str(refs.get("prompt_chain_asset_id", "")).strip_edges()
		out["projection_artifact_id"] = str(refs.get("projection_artifact_id", "")).strip_edges()
		out["cluster_artifact_id"] = str(refs.get("cluster_artifact_id", "")).strip_edges()
	if str(out["closure_artifact_id"]).is_empty():
		var src_any: Variant = flowdoc.get("source", {})
		if typeof(src_any) == TYPE_DICTIONARY:
			out["closure_artifact_id"] = str((src_any as Dictionary).get("closure_artifact_id", "")).strip_edges()
	return out


static func get_closure_context_graph_artifact_id(closure: Dictionary) -> String:
	var id := str(closure.get("context_graph_artifact_id", "")).strip_edges()
	if not id.is_empty():
		return id
	id = str(closure.get("context_graph_id", "")).strip_edges()
	if not id.is_empty():
		return id
	var cg_any: Variant = closure.get("context_graph", null)
	if typeof(cg_any) == TYPE_DICTIONARY:
		var cg: Dictionary = cg_any
		id = str(cg.get("artifact_id", "")).strip_edges()
		if not id.is_empty():
			return id
		id = str(cg.get("id", "")).strip_edges()
		if not id.is_empty():
			return id
	return ""


static func get_closure_prompt_chain_asset_id(closure: Dictionary) -> String:
	var id := str(closure.get("prompt_chain_asset_id", "")).strip_edges()
	if not id.is_empty():
		return id
	id = str(closure.get("prompt_chain_id", "")).strip_edges()
	if not id.is_empty():
		return id
	return ""


static func get_closure_projection_artifact_id(closure: Dictionary) -> String:
	var sel_any: Variant = closure.get("selection", null)
	if typeof(sel_any) == TYPE_DICTIONARY:
		var sel: Dictionary = sel_any
		var id := str(sel.get("projection_artifact_id", "")).strip_edges()
		if not id.is_empty():
			return id
	var id2 := str(closure.get("projection_artifact_id", "")).strip_edges()
	if not id2.is_empty():
		return id2
	return ""


static func get_closure_cluster_artifact_id(closure: Dictionary) -> String:
	var sel_any: Variant = closure.get("selection", null)
	if typeof(sel_any) == TYPE_DICTIONARY:
		var sel: Dictionary = sel_any
		var id := str(sel.get("cluster_artifact_id", "")).strip_edges()
		if not id.is_empty():
			return id
	var id2 := str(closure.get("cluster_artifact_id", "")).strip_edges()
	if not id2.is_empty():
		return id2
	return ""
