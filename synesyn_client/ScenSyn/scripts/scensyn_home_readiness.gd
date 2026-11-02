extends RefCounted
class_name ScenSynHomeReadiness

## Home-screen Hub / model readiness. Opens Settings when the user needs to act.
## Mic and role are out of scope for this first strip.

const STATE_CHECKING := "checking"
const STATE_READY := "ready"
const STATE_NEEDS_SETUP := "needs_setup"

static func assess() -> Dictionary:
	var hub_known: bool = false
	var hub_ok: bool = false
	if WorkspaceBootstrapper:
		if WorkspaceBootstrapper.has_method("is_hub_health_known"):
			hub_known = bool(WorkspaceBootstrapper.is_hub_health_known())
		else:
			hub_known = true
		if WorkspaceBootstrapper.has_method("is_hub_reachable"):
			hub_ok = bool(WorkspaceBootstrapper.is_hub_reachable())
	else:
		hub_known = true
		hub_ok = false

	var model_known: bool = false
	var model_ok: bool = false
	var model_needs_key: bool = false
	if PluginManager == null:
		model_known = true
		model_ok = false
	elif PluginManager.has_method("is_ready") and PluginManager.is_ready():
		model_known = true
		var model_status: Dictionary = _assess_model()
		model_ok = bool(model_status.get("ok", false))
		model_needs_key = bool(model_status.get("needs_key", false))

	if (not hub_known) or (not model_known):
		return {
			"state": STATE_CHECKING,
			"message": "Checking Hub and AI model setup…",
		}

	if hub_ok and model_ok:
		return {
			"state": STATE_READY,
			"message": "",
		}

	var parts: PackedStringArray = []
	if not hub_ok:
		parts.append("Hub is not ready")
	if not model_ok:
		if model_needs_key:
			parts.append("the current AI model has no API key")
		else:
			parts.append("no usable AI model is selected")
	var detail: String = " and ".join(parts)
	return {
		"state": STATE_NEEDS_SETUP,
		"message": "%s. Open Settings to fix this before you start a session." % detail.capitalize(),
	}


static func _assess_model() -> Dictionary:
	if not PluginManager or not PluginManager.has_method("get_ai_model_manager"):
		return {"ok": false, "needs_key": false}
	var model_manager: Object = PluginManager.get_ai_model_manager()
	if model_manager == null:
		return {"ok": false, "needs_key": false}

	var model_id: String = ""
	if model_manager.has_method("get_current_model"):
		model_id = String(model_manager.get_current_model()).strip_edges()
	if model_id.is_empty():
		return {"ok": false, "needs_key": false}

	var provider_id: String = ""
	if model_manager.has_method("get_provider_for_model"):
		provider_id = String(model_manager.get_provider_for_model(model_id)).strip_edges().to_lower()
	if provider_id == "ollama":
		return {"ok": true, "needs_key": false}

	var api_key: String = ""
	if model_manager.has_method("get_api_key") and not provider_id.is_empty():
		api_key = String(model_manager.get_api_key(provider_id)).strip_edges()
	if api_key.is_empty():
		return {"ok": false, "needs_key": true}
	return {"ok": true, "needs_key": false}
