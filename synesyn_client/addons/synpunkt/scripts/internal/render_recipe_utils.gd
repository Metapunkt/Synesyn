extends RefCounted
class_name SynpunktRenderRecipeUtils

const WorkflowUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_utils.gd")

static func on_save_render_recipe(owner: Control) -> void:
	var render_recipe_name: LineEdit = owner.get("_render_recipe_name")
	if not render_recipe_name:
		owner.call("_set_status", "Render recipe UI not available.")
		return
	var name := render_recipe_name.text.strip_edges()
	if name.is_empty():
		owner.call("_set_status", "Recipe name is empty.")
		return
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if not workflow_json:
		owner.call("_set_status", "No workflow JSON field.")
		return
	var wf_any: Variant = JSON.parse_string(workflow_json.text)
	if typeof(wf_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Recipe: invalid workflow JSON")
		return
	var workflow: Dictionary = wf_any
	var patches: Array = []
	var patch_json: TextEdit = owner.get("_patch_json")
	if patch_json:
		var p_any: Variant = JSON.parse_string(patch_json.text.strip_edges())
		if typeof(p_any) == TYPE_ARRAY:
			patches = p_any
	var workflow_hash := WorkflowUtilsScript.hash_sha256_hex(WorkflowUtilsScript.canonical_json_bytes(workflow))
	var workflow_artifact_id := await owner.call("_find_existing_workflow_artifact_id_by_hash", workflow_hash)
	var session_id := str(owner.get("_session_id")).strip_edges()
	var active_flowdoc_id := str(owner.get("_active_flowdoc_id")).strip_edges()
	var active_closure_id := str(owner.get("_active_closure_id")).strip_edges()
	var ref_context_graph: LineEdit = owner.get("_ref_context_graph")
	var ref_prompt_chain: LineEdit = owner.get("_ref_prompt_chain")
	var hub: Node = owner.get("_hub")
	if workflow_artifact_id.is_empty():
		var wf_meta := {"provenance": {"generated_by": "synpunkt.render.recipe", "workflow_hash_sha256": workflow_hash, "session_id": session_id}, "refs": {"syndoc_artifact_id": active_flowdoc_id}}
		var wf_res: Dictionary = await hub.create_artifact_inline_json("json.workflow", workflow, wf_meta)
		workflow_artifact_id = str(wf_res.get("id", wf_res.get("artifact_id", ""))).strip_edges()
	if not workflow_artifact_id.is_empty():
		var seen_any: Variant = owner.get("_render_seen_workflow_hash_to_workflow_id")
		var seen: Dictionary = seen_any if typeof(seen_any) == TYPE_DICTIONARY else {}
		seen[workflow_hash] = workflow_artifact_id
		owner.set("_render_seen_workflow_hash_to_workflow_id", seen)
	var params: Array = []
	for p_any2 in patches:
		if typeof(p_any2) != TYPE_DICTIONARY:
			continue
		var p2: Dictionary = p_any2
		var node_id := str(p2.get("node_id", "")).strip_edges()
		var input_key := str(p2.get("input", "")).strip_edges()
		if node_id.is_empty() or input_key.is_empty():
			continue
		params.append({"node_id": node_id, "input": input_key})
	var recipe := {
		"schema_version": 1,
		"kind": "synesyn.render_recipe",
		"name": name,
		"created_at": Time.get_unix_time_from_system(),
		"workflow_artifact_id": workflow_artifact_id,
		"workflow_hash_sha256": workflow_hash,
		"default_patches": patches,
		"params": params,
		"output_routing": {"mode": "substrate", "render_request_artifact_type": "json.render_request", "images": {"artifact_type": "image.generated"}},
		"refs": {
			"syndoc_artifact_id": active_flowdoc_id,
			"closure_artifact_id": active_closure_id,
			"context_graph_artifact_id": ref_context_graph.text.strip_edges() if ref_context_graph else "",
			"prompt_chain_artifact_id": ref_prompt_chain.text.strip_edges() if ref_prompt_chain else "",
		},
	}
	var meta := {
		"provenance": {"generated_by": "synpunkt.render.recipe", "session_id": session_id, "workflow_hash_sha256": workflow_hash},
		"refs": {"workflow_artifact_id": workflow_artifact_id, "syndoc_artifact_id": active_flowdoc_id},
	}
	var res: Dictionary = await hub.create_artifact_inline_json("json.render_recipe", recipe, meta)
	if bool(res.get("ok", false)):
		owner.call("_set_status", "Saved render recipe: %s" % str(res.get("id", "")))
	else:
		owner.call("_set_status", "Save recipe failed: %s" % str(res.get("error", res)))
