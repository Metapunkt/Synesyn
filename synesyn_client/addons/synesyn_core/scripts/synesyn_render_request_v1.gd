extends RefCounted
class_name SynesynRenderRequestV1

# Cross-app render request contract (v1).
#
# Goals:
# - Versioned, stable, app-agnostic shape for "submit a render".
# - Back-compat: accept the legacy ad-hoc shape used by SynPunkt v0/v1 UI
#   (e.g. {"workflow": {...}, "patches": [...]}) and normalize it.
#
# Canonical normalized shape (v1):
# {
#   "schema_version": 1,
#   "kind": "synesyn.render_request",
#   "routing": {
#     "mode": "direct",                 # "direct" | "hub"
#     "provider": "comfyui",            # "comfyui" (v1)
#     "comfy_base_url": "http://..."    # required for direct+comfyui
#   },
#   "workflow": {
#     "inline": { ... } ,               # optional if artifact_id present
#     "artifact_id": "art_..."          # optional if inline present
#   },
#   "patches": [ {"node_id":"3","input":"seed","value":123}, ... ],
#   "client": {
#     "app_id": "synpunkt",
#     "client_id": "synpunkt_...",      # used for ComfyUI WS progress
#     "request_id": "rr_...",           # optional, app-generated
#     "session_id": "sess_..."          # optional
#   },
#   "refs": { ... },                    # optional provenance refs
#   "output_routing": { ... },          # stable output routing contract (v1)
#   "outputs": { ... },                 # optional actual outputs (typically filled after completion)
#   "created_at": 1730000000            # optional unix seconds
# }

const SCHEMA_VERSION := 1
const KIND := "synesyn.render_request"

static func _as_dict(v: Variant) -> Dictionary:
	return v as Dictionary if typeof(v) == TYPE_DICTIONARY else {}

static func _as_array(v: Variant) -> Array:
	return v as Array if typeof(v) == TYPE_ARRAY else []

static func _norm_mode(v: String) -> String:
	var s := String(v).strip_edges().to_lower()
	if s in ["local", "client", "direct", "client_direct", "self", "self_hosted", "byo"]:
		return "direct"
	if s in ["hub", "hosted", "hub_submit"]:
		return "hub"
	return s

static func normalize(request_any: Variant, defaults: Dictionary = {}) -> Dictionary:
	# Returns:
	# - {ok:true, request:<normalized Dictionary>}
	# - {ok:false, error:<code>, details:<optional>}
	if typeof(request_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "request_required"}

	var req_in: Dictionary = request_any
	var dflts := _as_dict(defaults)

	# Legacy input support: {"workflow": {...}, "patches":[...], "client_id":"..."}
	var has_legacy_workflow := req_in.has("workflow") and typeof(req_in.get("workflow")) == TYPE_DICTIONARY and (not req_in.has("schema_version"))
	if has_legacy_workflow:
		var routing_d := _as_dict(dflts.get("routing", {}))
		var comfy_url := str(routing_d.get("comfy_base_url", "")).strip_edges()
		var legacy: Dictionary = {
			"schema_version": SCHEMA_VERSION,
			"kind": KIND,
			"routing": {
				"mode": _norm_mode(str(routing_d.get("mode", "direct"))),
				"provider": str(routing_d.get("provider", "comfyui")).strip_edges(),
				"comfy_base_url": comfy_url,
			},
			"workflow": {"inline": req_in.get("workflow", {})},
			"patches": _as_array(req_in.get("patches", [])),
			"client": {
				"app_id": str(dflts.get("app_id", "")).strip_edges(),
				"client_id": str(req_in.get("client_id", "")).strip_edges(),
			},
		}
		return {"ok": true, "request": _normalize_canonical(legacy, dflts)}

	# Canonical input (or close to it)
	return {"ok": true, "request": _normalize_canonical(req_in, dflts)}

static func _normalize_canonical(req_in: Dictionary, dflts: Dictionary) -> Dictionary:
	var req := req_in.duplicate(true)
	req["schema_version"] = int(req.get("schema_version", SCHEMA_VERSION))
	req["kind"] = str(req.get("kind", KIND)).strip_edges()
	if str(req["kind"]).is_empty():
		req["kind"] = KIND

	# routing
	var routing := _as_dict(req.get("routing", {}))
	var d_routing := _as_dict(dflts.get("routing", {}))
	routing["mode"] = _norm_mode(str(routing.get("mode", d_routing.get("mode", "direct"))))
	var prov := str(routing.get("provider", d_routing.get("provider", "comfyui"))).strip_edges().to_lower()
	if prov.is_empty():
		prov = "comfyui"
	routing["provider"] = prov
	if not routing.has("comfy_base_url"):
		routing["comfy_base_url"] = str(d_routing.get("comfy_base_url", "")).strip_edges()
	req["routing"] = routing

	# workflow
	var wf := _as_dict(req.get("workflow", {}))
	var inline_any: Variant = wf.get("inline", null)
	if inline_any != null and typeof(inline_any) != TYPE_DICTIONARY:
		wf.erase("inline")
	var art_id := str(wf.get("artifact_id", "")).strip_edges()
	if not art_id.is_empty():
		wf["artifact_id"] = art_id
	req["workflow"] = wf

	# patches
	req["patches"] = _as_array(req.get("patches", []))

	# client
	var client := _as_dict(req.get("client", {}))
	if not client.has("app_id"):
		client["app_id"] = str(dflts.get("app_id", "")).strip_edges()
	client["client_id"] = str(client.get("client_id", "")).strip_edges()
	client["request_id"] = str(client.get("request_id", "")).strip_edges()
	client["session_id"] = str(client.get("session_id", "")).strip_edges()
	req["client"] = client

	# refs/outputs
	req["refs"] = _as_dict(req.get("refs", {}))
	# output routing (stable contract) + outputs (actual results)
	var out_routing := _as_dict(req.get("output_routing", {}))
	var d_out_routing := _as_dict(dflts.get("output_routing", {}))
	if not out_routing.has("mode"):
		out_routing["mode"] = str(d_out_routing.get("mode", "substrate")).strip_edges().to_lower()
	if not out_routing.has("images"):
		out_routing["images"] = _as_dict(d_out_routing.get("images", {"artifact_type": "image.generated"}))
	var images := _as_dict(out_routing.get("images", {}))
	if not images.has("artifact_type"):
		images["artifact_type"] = str(_as_dict(d_out_routing.get("images", {})).get("artifact_type", "image.generated")).strip_edges()
	out_routing["images"] = images
	if not out_routing.has("render_request_artifact_type"):
		out_routing["render_request_artifact_type"] = str(d_out_routing.get("render_request_artifact_type", "json.render_request")).strip_edges()
	req["output_routing"] = out_routing
	req["outputs"] = _as_dict(req.get("outputs", {}))

	# created_at
	if not req.has("created_at"):
		req["created_at"] = int(Time.get_unix_time_from_system())
	return req

static func validate(req_any: Variant) -> Dictionary:
	if typeof(req_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "request_required"}
	var req: Dictionary = req_any
	if int(req.get("schema_version", 0)) != SCHEMA_VERSION:
		return {"ok": false, "error": "unsupported_schema_version", "details": req.get("schema_version")}
	if str(req.get("kind", "")).strip_edges() != KIND:
		return {"ok": false, "error": "invalid_kind", "details": req.get("kind")}
	var routing := _as_dict(req.get("routing", {}))
	var mode := _norm_mode(str(routing.get("mode", "")))
	if not (mode in ["direct", "hub"]):
		return {"ok": false, "error": "routing_mode_required", "details": mode}
	var provider := str(routing.get("provider", "")).strip_edges().to_lower()
	if provider.is_empty():
		return {"ok": false, "error": "routing_provider_required"}
	if mode == "direct" and provider == "comfyui":
		var url := str(routing.get("comfy_base_url", "")).strip_edges()
		if url.is_empty():
			return {"ok": false, "error": "comfy_base_url_required"}
	var wf := _as_dict(req.get("workflow", {}))
	var has_inline := wf.has("inline") and typeof(wf.get("inline")) == TYPE_DICTIONARY
	var has_art := (not str(wf.get("artifact_id", "")).strip_edges().is_empty())
	if not has_inline and not has_art:
		return {"ok": false, "error": "workflow_required", "details": "workflow.inline or workflow.artifact_id required"}
	var out_routing := _as_dict(req.get("output_routing", {}))
	var out_mode := str(out_routing.get("mode", "")).strip_edges().to_lower()
	if out_mode.is_empty():
		return {"ok": false, "error": "output_routing_mode_required"}
	if out_mode != "substrate":
		return {"ok": false, "error": "unsupported_output_routing_mode", "details": out_mode}
	var images := _as_dict(out_routing.get("images", {}))
	var img_type := str(images.get("artifact_type", "")).strip_edges()
	if img_type.is_empty():
		return {"ok": false, "error": "output_routing_images_artifact_type_required"}
	return {"ok": true}


