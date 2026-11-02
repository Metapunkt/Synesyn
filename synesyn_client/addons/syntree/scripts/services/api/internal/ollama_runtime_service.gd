extends Node
class_name OllamaRuntimeService

const DEFAULT_ORIGIN: String = "http://127.0.0.1:11434"
const CONTROL_TIMEOUT_SECONDS: float = 8.0

var origin: String = DEFAULT_ORIGIN


func configure(origin_url: String) -> bool:
	var normalized: String = origin_url.strip_edges().trim_suffix("/")
	normalized = normalized.trim_suffix("/api/chat")
	if not (
		normalized.begins_with("http://")
		or normalized.begins_with("https://")
	):
		return false
	origin = normalized
	return true


func discover_models() -> Dictionary:
	var response: Dictionary = await _request_json(
		HTTPClient.METHOD_GET,
		"/api/tags"
	)
	if not bool(response.get("success", false)):
		return response
	var payload_any: Variant = response.get("body", {})
	var payload: Dictionary = (
		payload_any if typeof(payload_any) == TYPE_DICTIONARY else {}
	)
	var models_any: Variant = payload.get("models", [])
	if typeof(models_any) != TYPE_ARRAY:
		return {"success": false, "error": "invalid_ollama_tags"}
	var model_ids: Array[String] = []
	var metadata_by_model: Dictionary = {}
	for model_any: Variant in models_any:
		if typeof(model_any) != TYPE_DICTIONARY:
			continue
		var model_data: Dictionary = model_any
		var model_id: String = String(
			model_data.get("name", model_data.get("model", ""))
		).strip_edges()
		if model_id.is_empty():
			continue
		model_ids.append(model_id)
		var details_any: Variant = model_data.get("details", {})
		var details: Dictionary = (
			details_any if typeof(details_any) == TYPE_DICTIONARY else {}
		)
		metadata_by_model[model_id] = {
			"size_bytes": int(model_data.get("size", 0)),
			"modified_at": String(model_data.get("modified_at", "")),
			"digest": String(model_data.get("digest", "")),
			"family": String(details.get("family", "")),
			"parameter_size": String(details.get("parameter_size", "")),
			"quantization_level": String(
				details.get("quantization_level", "")
			),
		}
	model_ids.sort()
	return {
		"success": true,
		"models": model_ids,
		"metadata": metadata_by_model,
	}


func inspect_model(model_id: String) -> Dictionary:
	var response: Dictionary = await _request_json(
		HTTPClient.METHOD_POST,
		"/api/show",
		{"model": model_id}
	)
	if not bool(response.get("success", false)):
		return response
	var body_any: Variant = response.get("body", {})
	var body: Dictionary = (
		body_any if typeof(body_any) == TYPE_DICTIONARY else {}
	)
	var model_info_any: Variant = body.get("model_info", {})
	var model_info: Dictionary = (
		model_info_any if typeof(model_info_any) == TYPE_DICTIONARY else {}
	)
	var context_length: int = 0
	for info_key_any: Variant in model_info:
		var info_key: String = String(info_key_any)
		if info_key.ends_with(".context_length"):
			context_length = int(model_info[info_key_any])
			break
	return {
		"success": true,
		"context_length": context_length,
		"capabilities": (
			body.get("capabilities", [])
			if typeof(body.get("capabilities", [])) == TYPE_ARRAY
			else []
		),
		"details": body.get("details", {}),
	}


func list_running_models() -> Dictionary:
	var response: Dictionary = await _request_json(
		HTTPClient.METHOD_GET,
		"/api/ps"
	)
	if not bool(response.get("success", false)):
		return response
	var body_any: Variant = response.get("body", {})
	var body: Dictionary = (
		body_any if typeof(body_any) == TYPE_DICTIONARY else {}
	)
	return {
		"success": true,
		"models": body.get("models", []),
	}


func unload_model(model_id: String) -> Dictionary:
	if model_id.strip_edges().is_empty():
		return {"success": false, "error": "model_required"}
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/api/generate",
		{
			"model": model_id,
			"keep_alive": 0,
		}
	)


func _request_json(
	http_method: HTTPClient.Method,
	path: String,
	payload: Dictionary = {}
) -> Dictionary:
	var request_node := HTTPRequest.new()
	request_node.timeout = CONTROL_TIMEOUT_SECONDS
	add_child(request_node)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body_text: String = (
		JSON.stringify(payload)
		if http_method != HTTPClient.METHOD_GET
		else ""
	)
	var request_error: Error = request_node.request(
		origin + path,
		headers,
		http_method,
		body_text
	)
	if request_error != OK:
		request_node.queue_free()
		return {
			"success": false,
			"error": "request_start_failed",
			"details": str(request_error),
		}
	var completed: Array = await request_node.request_completed
	request_node.queue_free()
	if int(completed[0]) != HTTPRequest.RESULT_SUCCESS:
		return {
			"success": false,
			"error": "ollama_unreachable",
			"result": int(completed[0]),
		}
	var status_code: int = int(completed[1])
	var response_text: String = (
		completed[3] as PackedByteArray
	).get_string_from_utf8()
	var parsed_any: Variant = JSON.parse_string(response_text)
	if status_code < 200 or status_code >= 300:
		return {
			"success": false,
			"error": "ollama_http_%d" % status_code,
			"details": response_text.left(500),
		}
	if typeof(parsed_any) != TYPE_DICTIONARY:
		return {"success": false, "error": "invalid_ollama_response"}
	return {"success": true, "body": parsed_any}
