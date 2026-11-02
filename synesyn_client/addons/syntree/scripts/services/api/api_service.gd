## Purpose: APIService (script)
@tool
extends Node
class_name APIService

const OllamaRuntimeServiceScript = preload(
	"res://addons/syntree/scripts/services/api/internal/ollama_runtime_service.gd"
)
const OllamaStreamingClientScript = preload(
	"res://addons/syntree/scripts/services/api/internal/ollama_streaming_client.gd"
)
const DEFAULT_TIMEOUT: float = 25.0
const MAX_RETRIES: int = 2
const OLLAMA_TIMEOUT_FLOOR: float = 75.0
## Cloud providers (Grok, Claude, GPT, Gemini) often need longer than the short
## chat default once Workshop / ScenSyn attach large metaprompt context. A read
## timeout surfaces from Godot as HTTP status 0 and was previously reported as
## "Could not connect", which misdiagnoses a slow model as a dead endpoint.
## Keep aligned with workshop_stateless_model_task.CLOUD_TIMEOUT_SECONDS.
const CLOUD_TIMEOUT_FLOOR: float = 120.0

# Signals
signal request_started(endpoint: String)
signal request_completed(endpoint: String, response: Dictionary)
signal operation_failed(operation: String, error: String, details: String)
signal inference_metrics_updated(model_id: String, metrics: Dictionary)
signal ollama_models_refreshed(models: Array[String], status: Dictionary)
signal stream_chunk_received(request_id: String, content_delta: String)

# Services
var ai_model_manager: Node

# State
var _http_request: HTTPRequest
var _active_requests: Array[HTTPRequest] = []
var _active_request_records: Dictionary = {}
var _cancelled_request_ids: Dictionary = {}
var _timeout: float = DEFAULT_TIMEOUT
var _last_request_time: int = 0
var _request_count: int = 0
var _last_error_details: String = ""
var _last_inference_metrics: Dictionary = {}
var _ollama_runtime_service: Node
var _ollama_streaming_client: Node
## Models that answered a reasoning budget with a refusal, so the next call does not spend a
## round trip rediscovering it. Learned rather than listed, because only the provider knows,
## and a session is short enough that forgetting on restart costs one call.
var _models_refusing_reasoning_effort: Dictionary = {}

# Sets up the APIService.
# Parameters:
#   p_ai_model_manager: The AIModelManager instance (required).
#   timeout (optional): Request timeout duration.
func setup(p_ai_model_manager: Node, timeout: float = DEFAULT_TIMEOUT) -> Dictionary:
	# Validate ai_model_manager
	if not p_ai_model_manager:
		push_error("APIService: AI Model Manager is required for setup.")
		return {"success": false, "error": "AI Model Manager required"}
	
	# Store the AIModelManager reference; it's needed to get provider/loader/key info.
	ai_model_manager = p_ai_model_manager
	_timeout = timeout
	
	# Initialize HTTP request
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.timeout = _timeout
	_ollama_runtime_service = OllamaRuntimeServiceScript.new()
	_ollama_runtime_service.name = "OllamaRuntimeService"
	add_child(_ollama_runtime_service)
	_ollama_streaming_client = OllamaStreamingClientScript.new()
	_ollama_streaming_client.name = "OllamaStreamingClient"
	add_child(_ollama_streaming_client)
	Signal(
		_ollama_streaming_client,
		"chunk_received"
	).connect(_on_ollama_stream_chunk)
	
	return {"success": true, "error": ""}

func set_ollama_base_url(origin_url: String) -> Dictionary:
	if (
		not is_instance_valid(_ollama_runtime_service)
		or not is_instance_valid(_ollama_streaming_client)
	):
		return {"success": false, "error": "ollama_runtime_unavailable"}
	var runtime_ok: bool = bool(
		_ollama_runtime_service.call("configure", origin_url)
	)
	var streaming_ok: bool = bool(
		_ollama_streaming_client.call("configure", origin_url)
	)
	if not runtime_ok or not streaming_ok:
		return {"success": false, "error": "invalid_ollama_base_url"}
	return {"success": true, "base_url": origin_url}

func update_error_handler_provider(provider: String) -> void:
	pass  # No longer needed

func _make_request(
	timeout_sec: float,
	request_id: String = "",
	provider_id: String = ""
) -> HTTPRequest:
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = timeout_sec
	_active_requests.append(req)
	if not request_id.is_empty():
		_active_request_records[request_id] = {
			"request": req,
			"provider": provider_id,
		}
	return req

func _release_request(req: HTTPRequest) -> void:
	if req == null:
		return
	_active_requests.erase(req)
	for request_id: String in _active_request_records.keys():
		var record: Dictionary = _active_request_records[request_id]
		if record.get("request") == req:
			_active_request_records.erase(request_id)
			break
	if is_instance_valid(req):
		req.queue_free()

func _handle_request_error(code: int, body: String, transport_result: int = OK) -> void:
	var json = JSON.parse_string(body) if not body.is_empty() else null
	var error_message: String
	var error_details: String = ""

	# Transport failures (timeout / TLS / DNS) report HTTP status 0. Distinguish
	# them from a true unreachable endpoint so Workshop users are not told to
	# "check that Ollama is running" when Grok simply exceeded the read timeout.
	if transport_result == HTTPRequest.RESULT_TIMEOUT:
		error_message = (
			"AI request timed out before a response arrived. "
			+ "Try a faster model, reduce context, or wait and retry."
		)
	elif transport_result != OK and code == 0:
		match transport_result:
			HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
				error_message = "Could not connect to AI service. Check that it is running (e.g. Ollama, or your API provider)."
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				error_message = "TLS handshake with the AI provider failed. Check network/proxy settings."
			_:
				error_message = "Could not complete AI request (transport result %d)." % transport_result
	else:
		# User-actionable messages for the most common HTTP error codes.
		match code:
			0:
				error_message = "Could not connect to AI service. Check that it is running (e.g. Ollama, or your API provider)."
			401, 403:
				error_message = "Authentication failed. Check your API key in Tools \u2192 Services."
			404:
				error_message = "Model or endpoint not found (404). If using Ollama, run 'ollama list' and then verify the selected model in Tools \u2192 Services."
			429:
				error_message = "Rate limit reached. Wait a moment and try again, or switch to a different model."
			500, 502, 503:
				error_message = "AI service returned a server error (%d). It may still be starting; try again in a moment." % code
			_:
				error_message = "Request failed with status " + str(code)

	# Append provider-level error detail if the response body is parseable.
	if json and typeof(json) == TYPE_DICTIONARY and json.has("error"):
		var api_err: Variant = json.get("error")
		if typeof(api_err) == TYPE_DICTIONARY:
			var api_err_d: Dictionary = api_err
			if api_err_d.has("message"):
				error_details = str(api_err_d.get("message", ""))
			if api_err_d.has("type"):
				error_details += ("\n" if not error_details.is_empty() else "") + "Type: " + str(api_err_d.get("type", ""))
			if api_err_d.has("code"):
				error_details += "\nCode: " + str(api_err_d.get("code", ""))
		elif typeof(api_err) == TYPE_STRING:
			error_details = str(api_err)

	push_error("APIService: " + error_message + (" Details: " + error_details if not error_details.is_empty() else ""))
	operation_failed.emit("chat_completion", error_message, error_details)
	_last_error_details = error_details

func _handle_operation_error(operation: String, error: String) -> void:
	push_error("APIService [%s]: %s" % [operation, error])
	operation_failed.emit(operation, error, "")

# Sends a request to the appropriate AI model provider's chat completion endpoint.
# Fetches the API key and other details from the AIModelManager and the specific model loader.
func chat_completion(model: String, messages: Array, settings: Dictionary = {}) -> Dictionary:
	if messages.is_empty():
		_handle_operation_error("chat_completion", "No messages provided")
		return {"success": false, "error": "No messages provided"}
	
	_last_request_time = Time.get_ticks_msec()
	_request_count += 1
	
	# Ensure ai_model_manager is valid
	if not ai_model_manager:
		_handle_operation_error("chat_completion", "AI Model Manager not available in APIService")
		return {"success": false, "error": "AI Model Manager not available"}

	# Get the provider for the selected model via the manager
	var provider = ai_model_manager.get_provider_for_model(model)
	if provider.is_empty():
		_handle_operation_error("chat_completion", "Unknown model provider for model: " + model)
		return {"success": false, "error": "Unknown model provider"}
	var request_id: String = String(
		settings.get(
			"request_id",
			"chat_%d_%d" % [_request_count, Time.get_ticks_usec()]
		)
	).strip_edges()
	if provider == "ollama" and _has_active_provider_request("ollama"):
		return {
			"success": false,
			"error": "ollama_busy",
			"details": (
				"Another local-model request is still running. "
				+ "Wait for it to finish or cancel it before retrying."
			),
			"request_id": request_id,
		}
	
	# Get the model loader for the provider via the manager
	var loader = ai_model_manager.get_provider_loader(provider)
	if not loader:
		_handle_operation_error("chat_completion", "Model loader not found for provider: " + provider)
		return {"success": false, "error": "Model loader not found"}

	# --- Get the API key from the loader --- 
	# The API key is stored within the specific loader instance, managed by AIModelManager.
	var current_api_key = loader.api_key
	if current_api_key.is_empty():
		# Handle cases like Ollama which don't require a key, or if the key wasn't set for others.
		if provider != "ollama": # Allow Ollama to proceed without a key (Corrected case)
			_handle_operation_error("chat_completion", "API key not set for provider: " + provider)
			return {"success": false, "error": "API key not set for provider: " + provider}
	
	# --- Prepare request using the loader --- 
	# Extract context from settings to pass as system_prompt
	var context_as_system_prompt = settings.get("context_string", "")
	# Optional per-call model override (set by process_message_with_history). When
	# non-empty, loaders use this model for the request body and any model-keyed
	# decisions (max_tokens, cache eligibility) WITHOUT mutating loader state.
	# Empty string preserves the loader's current internal model_name (legacy path).
	var effective_model: String = String(settings.get("effective_model", "")).strip_edges()
	var request_body = loader.prepare_request(messages, context_as_system_prompt, effective_model)
	if provider == "ollama":
		var requested_options_any: Variant = settings.get("request_options", {})
		if typeof(requested_options_any) == TYPE_DICTIONARY:
			var merged_options: Dictionary = {}
			var loader_options_any: Variant = request_body.get("options", {})
			if typeof(loader_options_any) == TYPE_DICTIONARY:
				merged_options = (loader_options_any as Dictionary).duplicate(true)
			merged_options.merge(requested_options_any as Dictionary, true)
			if not merged_options.is_empty():
				request_body["options"] = merged_options
		if settings.get("force_json", false) == true:
			request_body["format"] = "json"
	elif provider == "xai":
		# Grok spends most of a call on reasoning tokens it never shows: a director cue
		# batch measured 7.4s for 300 of them against 80 of answer. A caller whose call is
		# mechanical rather than creative can ask for less of that. Scoped to this provider
		# because the key is xAI's; nobody else is sent it.
		var reasoning_effort: String = String(settings.get("reasoning_effort", "")).strip_edges()
		# xAI names its non-reasoning models so, and they reject the parameter outright;
		# skipping it here saves the round trip the error handler below would otherwise
		# have to spend discovering that, for this model and for any that has already
		# refused once in this session.
		var model_can_reason: bool = (
			not model.to_lower().contains("non-reasoning")
			and not _models_refusing_reasoning_effort.has(model)
		)
		if not reasoning_effort.is_empty() and model_can_reason:
			request_body["reasoning_effort"] = reasoning_effort

	# --- Get Endpoint and Headers --- 
	var headers = PackedStringArray()
	var endpoint = ""
	
	# Handle Gemini's special endpoint requirement
	if provider == "google" and loader.has_method("get_request_endpoint_with_key"):
		# Gemini encodes the model in the URL path, so any per-call effective_model
		# must reach get_request_endpoint_with_key (it accepts an optional override).
		endpoint = loader.get_request_endpoint_with_key(current_api_key, effective_model)
		headers = loader.get_headers() # Headers are simple for Gemini
		if endpoint.is_empty(): # Check if endpoint generation failed (e.g., missing key)
			_handle_operation_error("chat_completion", "Failed to generate endpoint for Google Gemini")
			return {"success": false, "error": "Failed to generate Gemini endpoint"}
	else:
		# Standard approach for other providers. Some loaders (Anthropic) compute
		# headers from the effective model (cache-eligible models add a beta header)
		# so we surface effective_model via a method check to keep older loaders
		# working unchanged.
		if loader.has_method("get_headers_for_model"):
			headers = loader.get_headers_for_model(current_api_key, effective_model)
		else:
			headers = loader.get_headers(current_api_key)
		endpoint = loader.base_url
	
	request_started.emit("chat_completion")
	var effective_timeout: float = float(settings.get("timeout_sec", _timeout))
	if provider == "ollama":
		effective_timeout = maxf(_timeout, OLLAMA_TIMEOUT_FLOOR)
		effective_timeout = maxf(
			effective_timeout,
			float(settings.get("timeout_sec", OLLAMA_TIMEOUT_FLOOR))
		)
	elif not settings.has("timeout_sec"):
		# Character chat via process_message_with_history did not set a cloud
		# budget; Workshop metaprompt context routinely exceeds 25s on Grok/etc.
		effective_timeout = maxf(effective_timeout, CLOUD_TIMEOUT_FLOOR)

	var body_text: String = JSON.stringify(request_body)
	var attempt := 0
	var maximum_attempts: int = maxi(
		1,
		int(settings.get("max_retries", MAX_RETRIES))
	)
	while attempt < maximum_attempts:
		attempt += 1

		var request := _make_request(
			effective_timeout,
			request_id,
			provider
		)
		var error = request.request(endpoint, headers, HTTPClient.METHOD_POST, body_text)

		if error != OK:
			_release_request(request)
			if attempt < maximum_attempts:
				print("[APIService] Attempt %d/%d send error (%s). Retrying..." % [attempt, maximum_attempts, str(error)])
				await get_tree().create_timer(float(attempt) * 2.0).timeout
				continue
			_handle_operation_error("chat_completion", "Failed to send request: " + str(error))
			return {"success": false, "error": "Failed to send request"}

		var response: Array = await request.request_completed
		_release_request(request)
		if bool(_cancelled_request_ids.get(request_id, false)):
			_cancelled_request_ids.erase(request_id)
			return {
				"success": false,
				"error": "cancelled",
				"request_id": request_id,
			}

		var is_connection_failure: bool = (response[0] != OK)
		var is_server_error: bool = (not is_connection_failure and response[1] >= 500)

		if (is_connection_failure or is_server_error) and attempt < maximum_attempts:
			var reason: String = "connection error" if is_connection_failure else ("server %d" % response[1])
			print("[APIService] Attempt %d/%d failed (%s). Retrying in %ds..." % [attempt, maximum_attempts, reason, attempt * 2])
			await get_tree().create_timer(float(attempt) * 2.0).timeout
			continue

		if response[0] != OK:
			_handle_request_error(
				int(response[1]),
				response[3].get_string_from_utf8(),
				int(response[0])
			)
			return {"success": false, "error": "Request failed", "details": _last_error_details}

		if response[1] != 200:
			var failure_body: String = response[3].get_string_from_utf8()
			# A model that cannot reason rejects the whole request for carrying a reasoning
			# budget, so a scenario routed to one would fall silent rather than answer fast.
			# The budget is an optimisation, never the point of the call: drop it and ask
			# again, once, so the caller gets its answer either way.
			if (
				request_body.has("reasoning_effort")
				and int(response[1]) == 400
				and failure_body.to_lower().contains("reasoning")
			):
				print("[APIService] %s does not take a reasoning budget; retrying without one." % model)
				_models_refusing_reasoning_effort[model] = true
				request_body.erase("reasoning_effort")
				body_text = JSON.stringify(request_body)
				# Not a failed attempt: the same call, asked properly.
				attempt -= 1
				continue
			_handle_request_error(int(response[1]), failure_body)
			return {"success": false, "error": "Request failed with status " + str(response[1]), "details": _last_error_details}

		var response_body = JSON.parse_string(response[3].get_string_from_utf8())
		if not response_body:
			_handle_operation_error("chat_completion", "Invalid response format")
			return {"success": false, "error": "Invalid response format"}

		var parsed_response = loader.parse_response(response_body)
		var metrics: Dictionary = {}
		if loader.has_method("parse_metrics"):
			metrics = loader.call("parse_metrics", response_body)
			metrics["request_id"] = request_id
			metrics["model_id"] = model
			metrics["provider_id"] = provider
			_last_inference_metrics = metrics.duplicate(true)
			inference_metrics_updated.emit(model, metrics.duplicate(true))
		var result: Dictionary = {
			"success": true,
			"response": parsed_response,
			"request_id": request_id,
			"metrics": metrics,
			# What the request actually carried, which is not always what was asked for: a
			# model that cannot reason had it dropped. Reported so the diagnostic line
			# describes the call that happened.
			"reasoning_effort": String(request_body.get("reasoning_effort", "")),
		}
		request_completed.emit("chat_completion", result.duplicate(true))
		return result

	_handle_operation_error("chat_completion", "All %d attempts failed" % maximum_attempts)
	return {"success": false, "error": "All retry attempts exhausted"}

func chat_completion_stream(
	model: String,
	messages: Array,
	settings: Dictionary = {}
) -> Dictionary:
	if messages.is_empty():
		return {"success": false, "error": "No messages provided"}
	if not ai_model_manager:
		return {"success": false, "error": "AI Model Manager not available"}
	if ai_model_manager.get_provider_for_model(model) != "ollama":
		return {"success": false, "error": "streaming_provider_unsupported"}
	if (
		_has_active_provider_request("ollama")
		or (
			is_instance_valid(_ollama_streaming_client)
			and bool(_ollama_streaming_client.call("is_busy"))
		)
	):
		return {"success": false, "error": "ollama_busy"}
	var loader: BaseAIModelLoader = (
		ai_model_manager.get_provider_loader("ollama")
	)
	if not loader:
		return {"success": false, "error": "Model loader not found"}
	var request_id: String = String(
		settings.get(
			"request_id",
			"stream_%d" % Time.get_ticks_usec()
		)
	).strip_edges()
	var system_prompt: String = String(
		settings.get("context_string", "")
	)
	var request_body: Dictionary = loader.prepare_request(
		messages,
		system_prompt,
		model
	)
	var requested_options_any: Variant = settings.get(
		"request_options",
		{}
	)
	if typeof(requested_options_any) == TYPE_DICTIONARY:
		var merged_options: Dictionary = {}
		var loader_options_any: Variant = request_body.get("options", {})
		if typeof(loader_options_any) == TYPE_DICTIONARY:
			merged_options = (
				loader_options_any as Dictionary
			).duplicate(true)
		merged_options.merge(
			requested_options_any as Dictionary,
			true
		)
		request_body["options"] = merged_options
	if bool(settings.get("force_json", false)):
		request_body["format"] = "json"
	request_started.emit("chat_completion_stream")
	var timeout_seconds: float = maxf(
		OLLAMA_TIMEOUT_FLOOR,
		float(settings.get("timeout_sec", OLLAMA_TIMEOUT_FLOOR))
	)
	var result: Dictionary = await _ollama_streaming_client.call(
		"run",
		request_id,
		request_body,
		timeout_seconds
	)
	if not bool(result.get("success", false)):
		return result
	var raw_final_any: Variant = result.get("raw_final", {})
	if (
		typeof(raw_final_any) == TYPE_DICTIONARY
		and loader.has_method("parse_metrics")
	):
		var metrics: Dictionary = loader.call(
			"parse_metrics",
			raw_final_any
		)
		metrics["request_id"] = request_id
		metrics["model_id"] = model
		metrics["provider_id"] = "ollama"
		result["metrics"] = metrics
		_last_inference_metrics = metrics.duplicate(true)
		inference_metrics_updated.emit(model, metrics.duplicate(true))
	request_completed.emit(
		"chat_completion_stream",
		result.duplicate(true)
	)
	return result

func set_timeout(timeout: float) -> Dictionary:
	if timeout <= 0:
		return {"success": false, "error": "Invalid timeout value"}
	
	_timeout = timeout
	if _http_request:
		_http_request.timeout = _timeout
	return {"success": true, "error": ""}

func get_last_request_time() -> int:
	return _last_request_time

func get_request_count() -> int:
	return _request_count

func get_last_inference_metrics() -> Dictionary:
	return _last_inference_metrics.duplicate(true)

func refresh_ollama_models() -> Dictionary:
	if not is_instance_valid(_ollama_runtime_service):
		return {"success": false, "error": "ollama_runtime_unavailable"}
	var result: Dictionary = await _ollama_runtime_service.call(
		"discover_models"
	)
	var model_ids: Array[String] = []
	var models_any: Variant = result.get("models", [])
	if typeof(models_any) == TYPE_ARRAY:
		for model_any: Variant in models_any:
			var model_id: String = String(model_any).strip_edges()
			if not model_id.is_empty():
				model_ids.append(model_id)
	ollama_models_refreshed.emit(model_ids, result.duplicate(true))
	return result

func inspect_ollama_model(model_id: String) -> Dictionary:
	if not is_instance_valid(_ollama_runtime_service):
		return {"success": false, "error": "ollama_runtime_unavailable"}
	return await _ollama_runtime_service.call("inspect_model", model_id)

func get_running_ollama_models() -> Dictionary:
	if not is_instance_valid(_ollama_runtime_service):
		return {"success": false, "error": "ollama_runtime_unavailable"}
	return await _ollama_runtime_service.call("list_running_models")

func unload_ollama_model(model_id: String) -> Dictionary:
	if not is_instance_valid(_ollama_runtime_service):
		return {"success": false, "error": "ollama_runtime_unavailable"}
	if _has_active_provider_request("ollama"):
		return {"success": false, "error": "ollama_busy"}
	return await _ollama_runtime_service.call("unload_model", model_id)

func cancel_request(request_id: String) -> Dictionary:
	var record_any: Variant = _active_request_records.get(request_id)
	if typeof(record_any) != TYPE_DICTIONARY:
		if (
			is_instance_valid(_ollama_streaming_client)
			and bool(
				_ollama_streaming_client.call(
					"cancel",
					request_id
				)
			)
		):
			return {"success": true, "request_id": request_id}
		return {"success": false, "error": "request_not_found"}
	var request_node: HTTPRequest = (
		(record_any as Dictionary).get("request") as HTTPRequest
	)
	if not is_instance_valid(request_node):
		return {"success": false, "error": "request_not_found"}
	_cancelled_request_ids[request_id] = true
	request_node.cancel_request()
	return {"success": true, "request_id": request_id}

# Cancel any ongoing HTTP request
func cancel_current_request() -> Dictionary:
	var cancelled := false
	for req in _active_requests.duplicate():
		if req and is_instance_valid(req) and req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			for request_id: String in _active_request_records:
				var record: Dictionary = _active_request_records[request_id]
				if record.get("request") == req:
					_cancelled_request_ids[request_id] = true
					break
			req.cancel_request()
			cancelled = true
	if (
		is_instance_valid(_ollama_streaming_client)
		and bool(_ollama_streaming_client.call("cancel_all"))
	):
		cancelled = true
	if cancelled:
		return {"success": true, "message": "Request(s) cancelled"}
	return {"success": false, "message": "No active request to cancel"}

# Check if a request is currently in progress
func is_request_in_progress() -> bool:
	for req in _active_requests:
		if req and is_instance_valid(req) and req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			return true
	if (
		is_instance_valid(_ollama_streaming_client)
		and bool(_ollama_streaming_client.call("is_busy"))
	):
		return true
	return false

func _has_active_provider_request(provider_id: String) -> bool:
	if (
		provider_id == "ollama"
		and is_instance_valid(_ollama_streaming_client)
		and bool(_ollama_streaming_client.call("is_busy"))
	):
		return true
	for record_any: Variant in _active_request_records.values():
		if typeof(record_any) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_any
		var request_node: HTTPRequest = record.get("request") as HTTPRequest
		if (
			String(record.get("provider", "")) == provider_id
			and is_instance_valid(request_node)
			and request_node.get_http_client_status()
			!= HTTPClient.STATUS_DISCONNECTED
		):
			return true
	return false

func _on_ollama_stream_chunk(
	request_id: String,
	content_delta: String
) -> void:
	stream_chunk_received.emit(request_id, content_delta)

func _parse_error_response(response_text: String, response_code: int) -> String:
	var json = JSON.parse_string(response_text)
	if typeof(json) == TYPE_DICTIONARY and json.has("error"):
		return json.error.message
	return "Unknown error (HTTP " + str(response_code) + ")"

# Convenience function called by ConversationManager.
# It gets the current model and constructs the basic message list.
func process_message(message: String) -> Dictionary:
	# Check if the AI model manager reference is valid.
	if not ai_model_manager:
		return {"success": false, "error": "AI model manager not available"}
	
	# Get the currently selected model from the manager.
	var model = ai_model_manager.get_current_model()
	if model.is_empty():
		return {"success": false, "error": "No model selected"}
	
	# Format the basic message list.
	var messages = [{"role": "user", "content": message}]
	# TODO: Allow passing more complex settings/history from ConversationManager if needed.
	var settings = {"system_prompt": "You are a helpful assistant."}
	
	# Call the main chat_completion method.
	var response = await chat_completion(model, messages, settings)
	if not response.success:
		# Pass through the error details from chat_completion
		return {
			"success": false,
			"error": response.error,
			"details": response.get("details", _last_error_details)  # Use stored details if not in response
		}
	
	return response

# Send a full message history plus an optional context string to the API.
#
# Parameters:
#   messages       — Array of {role, content} dicts (history + new user message).
#   context_string — Optional system/context injection (e.g. ContentBus, PromptChain).
#   model_override — If non-empty, use this model for THIS call only. The manager's
#                    current-model state is NOT changed. Forwarded from
#                    ConversationManager.chat(); most callers can leave it empty.
#   call_settings  — Per-call request settings merged into the settings dictionary, for
#                    callers that know something about their own call that the loader
#                    cannot (e.g. "reasoning_effort" for an internal, mechanical call).
#                    Only the provider that understands a given key acts on it.
func process_message_with_history(messages: Array, context_string: String = "", model_override: String = "", call_settings: Dictionary = {}) -> Dictionary:
	if not ai_model_manager:
		return {"success": false, "error": "AI model manager not available"}

	var model: String = String(model_override).strip_edges()
	if model.is_empty():
		model = ai_model_manager.get_current_model()
	if model.is_empty():
		return {"success": false, "error": "No model selected"}

	# Construct settings dictionary
	var settings = {
		# Pass context string to be potentially used as system prompt by loaders
		"context_string": context_string,
		# Effective model for this call. Loaders that key off model name (caching,
		# max_tokens, etc.) read this if present so a per-call override flows all
		# the way down to the request body without mutating the loader's state.
		"effective_model": model,
		# Add other potential default settings here if needed
		# "temperature": 0.7 # Loaders should use their defaults if not provided
	}
	settings.merge(call_settings, true)

	# Ollama's normal chat path streams deltas while preserving the same final
	# response contract. Structured workshop tasks call chat_completion directly.
	var provider_id: String = ai_model_manager.get_provider_for_model(model)
	var response: Dictionary
	if provider_id == "ollama":
		response = await chat_completion_stream(model, messages, settings)
	else:
		response = await chat_completion(model, messages, settings)

	# Pass through the response (which includes success/error/details)
	return response
