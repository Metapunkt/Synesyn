extends RefCounted
class_name WorkshopStatelessModelTask

const OLLAMA_TIMEOUT_SECONDS: float = 180.0
const OLLAMA_CONTEXT_TOKENS: int = 4096
## 768 often truncates the four-role + map + synthesis envelope mid-JSON.
## Mid-tier local models need headroom; cloud models are unaffected.
const OLLAMA_OUTPUT_TOKENS: int = 2048
## The specialist envelope (four roles + cross-checks + map candidates, as
## strict JSON) is a heavy structured generation. api_service's default
## network read timeout (25s) is tuned for short chat replies and cuts off
## slower/"thinking" cloud models (e.g. Grok, extended-reasoning GPT/Claude/
## Gemini variants) mid-generation, surfacing as a generic connection error
## and the "specialist model could not be reached" fallback even though the
## model itself is perfectly capable. Give every provider, not just Ollama,
## headroom to finish.
const CLOUD_TIMEOUT_SECONDS: float = 120.0


func can_run(conversation_manager: Variant) -> bool:
	return (
		conversation_manager is Object
		and "api_service" in conversation_manager
		and "ai_model_manager" in conversation_manager
		and conversation_manager.get("api_service") != null
		and conversation_manager.get("ai_model_manager") != null
	)


func run(
	conversation_manager: Variant,
	prompt: String,
	model_override: String = ""
) -> Dictionary:
	if not can_run(conversation_manager):
		return {"success": false, "error": "stateless_task_unavailable"}
	var model_manager: Object = conversation_manager.get("ai_model_manager")
	var model_id: String = model_override.strip_edges()
	if model_id.is_empty() and model_manager.has_method("get_current_model"):
		model_id = String(model_manager.call("get_current_model")).strip_edges()
	if model_id.is_empty():
		return {"success": false, "error": "model_unavailable"}
	var provider_id: String = String(
		model_manager.call("get_provider_for_model", model_id)
	).strip_edges()
	var settings: Dictionary = {"effective_model": model_id}
	if provider_id == "ollama":
		settings["timeout_sec"] = OLLAMA_TIMEOUT_SECONDS
		settings["max_retries"] = 1
		settings["force_json"] = true
		settings["request_options"] = {
			"num_ctx": OLLAMA_CONTEXT_TOKENS,
			"num_predict": OLLAMA_OUTPUT_TOKENS,
			"temperature": 0.2,
		}
	else:
		# One long attempt beats two 25s attempts against a slow model: a retry
		# with a fresh short window still won't outrun a genuinely slow response.
		settings["timeout_sec"] = CLOUD_TIMEOUT_SECONDS
		settings["max_retries"] = 1
	var api_service: Object = conversation_manager.get("api_service")
	return await api_service.call(
		"chat_completion",
		model_id,
		[{"role": "user", "content": prompt}],
		settings
	)
