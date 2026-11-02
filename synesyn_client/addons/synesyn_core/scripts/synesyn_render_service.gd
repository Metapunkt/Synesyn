extends Node
class_name SynesynRenderService

# Cross-app render submission entrypoint (v1).
# - Normalizes/validates a SynesynRenderRequestV1 payload
# - Routes to provider(s)
#   - direct+comfyui implemented (client-side submission)
#   - hub mode is a placeholder (hub endpoint not yet implemented in this repo)

const SynesynRenderRequestV1Script = preload("res://addons/synesyn_core/scripts/synesyn_render_request_v1.gd")
const SynesynComfyClientScript = preload("res://addons/synesyn_core/scripts/synesyn_comfy_client.gd")

var comfy: SynesynComfyClient
var hub_client: Node = null # optional; typically HubSubstrateClient

func _enter_tree() -> void:
	# Ensure `comfy` exists as soon as this node enters the tree, so callers can
	# safely connect signals immediately after `add_child(SynesynRenderService)`.
	if comfy == null:
		comfy = SynesynComfyClientScript.new()
		add_child(comfy)

func set_hub_client(hub: Node) -> void:
	hub_client = hub

func set_comfy_base_url(url: String) -> void:
	if comfy:
		comfy.set_base_url(url)

func submit_render_request(request: Dictionary, defaults: Dictionary = {}) -> Dictionary:
	# Returns:
	# - {ok:true, provider:"comfyui", mode:"direct", prompt_id, client_id, normalized_request, workflow_patched, applied_patches}
	# - {ok:false, error, details?}
	var norm: Dictionary = SynesynRenderRequestV1Script.normalize(request, defaults)
	if not bool(norm.get("ok", false)):
		return norm
	var req: Dictionary = norm.get("request", {})
	var v: Dictionary = SynesynRenderRequestV1Script.validate(req)
	if not bool(v.get("ok", false)):
		return v

	var routing: Dictionary = req.get("routing", {})
	var mode := str(routing.get("mode", "")).strip_edges()
	var provider := str(routing.get("provider", "")).strip_edges().to_lower()

	if mode == "hub":
		if hub_client == null or (not hub_client.has_method("submit_render")):
			return {"ok": false, "error": "hub_client_required_for_hub_mode"}
		# Submit to hub for async execution; hub will emit render.* events.
		var res: Dictionary = await hub_client.submit_render(req)
		if not bool(res.get("ok", false)):
			return res
		return {
			"ok": true,
			"provider": provider,
			"mode": "hub",
			"job_id": str(res.get("job_id", res.get("id", ""))),
			"render_request_artifact_id": str(res.get("render_request_artifact_id", "")),
			"normalized_request": req,
		}

	if mode != "direct":
		return {"ok": false, "error": "unsupported_routing_mode", "details": mode}
	if provider != "comfyui":
		return {"ok": false, "error": "unsupported_provider", "details": provider}

	var comfy_url := str(routing.get("comfy_base_url", "")).strip_edges()
	if comfy_url.is_empty():
		return {"ok": false, "error": "comfy_base_url_required"}
	set_comfy_base_url(comfy_url)

	# Resolve workflow.inline or fetch via hub from workflow.artifact_id.
	var wf: Dictionary = req.get("workflow", {})
	var wf_inline_any: Variant = wf.get("inline", null)
	var workflow: Dictionary = {}
	if wf_inline_any != null and typeof(wf_inline_any) == TYPE_DICTIONARY:
		workflow = wf_inline_any
	else:
		var art_id := str(wf.get("artifact_id", "")).strip_edges()
		if art_id.is_empty():
			return {"ok": false, "error": "workflow_required", "details": "workflow.inline or workflow.artifact_id required"}
		if hub_client == null or (not hub_client.has_method("get_artifact_json")):
			return {"ok": false, "error": "hub_client_required_to_fetch_workflow", "details": art_id}
		var fetched: Dictionary = await hub_client.get_artifact_json(art_id)
		if not bool(fetched.get("ok", false)):
			return {"ok": false, "error": "failed_to_fetch_workflow", "details": fetched}
		workflow = fetched.get("json", {})
		if typeof(workflow) != TYPE_DICTIONARY:
			return {"ok": false, "error": "workflow_json_invalid", "details": art_id}

	var patches: Array = req.get("patches", [])
	var client: Dictionary = req.get("client", {})
	var client_id := str(client.get("client_id", "")).strip_edges()

	var submit: Dictionary = await comfy.submit_render_request({"workflow": workflow, "patches": patches, "client_id": client_id})
	if not bool(submit.get("ok", false)):
		return submit

	# Mirror the normalized request, but ensure we keep any generated client_id.
	var out_req := req.duplicate(true)
	var out_client: Dictionary = out_req.get("client", {})
	out_client["client_id"] = str(submit.get("client_id", "")).strip_edges()
	out_req["client"] = out_client

	return {
		"ok": true,
		"provider": "comfyui",
		"mode": "direct",
		"prompt_id": str(submit.get("prompt_id", "")),
		"client_id": str(submit.get("client_id", "")),
		"normalized_request": out_req,
		"workflow_patched": submit.get("workflow", {}),
		"applied_patches": submit.get("applied_patches", []),
	}
