## Purpose: OllamaModelLoader (script)
extends BaseAIModelLoader

class_name OllamaModelLoader

# Constants
# Add common Llama 3 variants and other popular Ollama models
const AVAILABLE_MODELS = [
	"gemma4:26b",
	"llama3.2",
	"llama2",
	"codellama",
	"mistral",
	"phi3",
	"qwen",
	"deepseek-r1:7b",
	"llama3.1:8b-instruct-q4_K_M",
	"llava:7b",
]
const MAX_TOKENS_BY_MODEL = {
	"gemma4:26b": 131072,
	"llama2": 4096,
	"codellama": 16384,
	"mistral": 8192,
	"phi3": 4096,
	"qwen": 8192,
	"llama3.2": 8192,
	"deepseek-r1:7b": 16384,
	"llama3.1:8b-instruct-q4_K_M": 8192,
	"llava:7b": 4096,
}

var _discovered_models: Array[String] = []
var _model_metadata: Dictionary = {}


func get_available_models() -> Array:
	if not _discovered_models.is_empty():
		return _discovered_models.duplicate()
	return AVAILABLE_MODELS.duplicate()


func set_base_origin(origin_url: String) -> bool:
	var normalized_origin: String = _normalize_origin(origin_url)
	if normalized_origin.is_empty():
		return false
	base_url = normalized_origin + "/api/chat"
	return true


func get_base_origin() -> String:
	return base_url.trim_suffix("/api/chat").trim_suffix("/")


func set_discovered_models(
	model_ids: Array[String],
	metadata_by_model: Dictionary = {}
) -> void:
	_discovered_models = model_ids.duplicate()
	_discovered_models.sort()
	_model_metadata = metadata_by_model.duplicate(true)


func get_model_metadata(requested_model: String = "") -> Dictionary:
	var resolved_model: String = (
		requested_model.strip_edges()
		if not requested_model.is_empty()
		else model_name
	)
	var metadata_any: Variant = _model_metadata.get(resolved_model, {})
	var metadata: Dictionary = (
		metadata_any.duplicate(true)
		if typeof(metadata_any) == TYPE_DICTIONARY
		else {}
	)
	metadata["context_length"] = _context_length_for(resolved_model)
	metadata["installed"] = resolved_model in _discovered_models
	return metadata

func _init():
	provider = "Ollama"
	base_url = "http://127.0.0.1:11434/api/chat"
	model_name = "gemma4:26b"
	# Set initial max_tokens based on the new default
	if model_name in MAX_TOKENS_BY_MODEL:
		max_tokens = MAX_TOKENS_BY_MODEL[model_name]
	else:
		max_tokens = 4096 # Default fallback
	temperature = 0.7

# Keep base signature, use system_prompt parameter for context.
# `effective_model` (optional): per-call model override; empty string keeps
# legacy behavior of using `self.model_name`.
func prepare_request(messages: Array, system_prompt: String = "", effective_model: String = "") -> Dictionary:
	var formatted_messages = []
	# Ollama /api/chat reliably supports system messages via the messages[] array.
	# (The top-level "system" field is not consistently honored across versions.)
	if not system_prompt.is_empty():
		formatted_messages.append({"role": "system", "content": system_prompt})
	for msg in messages:
		# Basic validation
		if msg.has("role") and msg.has("content"):
			formatted_messages.append({"role": msg.role, "content": msg.content})
		else:
			push_warning("OllamaModelLoader: Skipping message with missing role/content: " + str(msg))

	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name

	var request_data: Dictionary = {
		"model": call_model,
		"messages": formatted_messages,
		"stream": false,
		# Keep the active model warm between workshop turns without pinning every
		# model used during model switching in RAM/VRAM for an entire day.
		"keep_alive": "5m",
	}
	var opts: Dictionary = {}
	if call_model.begins_with("gemma4"):
		opts["num_ctx"] = 8192
		opts["num_predict"] = 1024
		# think=false bug only affects structured/JSON output, not plain text chat.
		request_data["think"] = false
	elif call_model.begins_with("deepseek-r1"):
		request_data["think"] = false
	if not opts.is_empty():
		request_data["options"] = opts
	return request_data

# Returns the necessary HTTP headers for Ollama API calls.
# Parameters:
#   api_key_to_use (String): Ignored, as Ollama typically doesn't require API keys.
# Add api_key parameter (ignored for Ollama) with default value
func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	# Ollama doesn't require auth headers
	return ["Content-Type: application/json"]

func parse_response(response: Dictionary) -> String:
	if response.has("message"):
		var content: String = str(response["message"]["content"])
		var think_re := RegEx.new()
		think_re.compile("(?s)<think>.*?</think>\\s*")
		content = think_re.sub(content, "", true)
		return content.strip_edges()
	return ""


func parse_metrics(response: Dictionary) -> Dictionary:
	var prompt_eval_count: int = int(response.get("prompt_eval_count", 0))
	var eval_count: int = int(response.get("eval_count", 0))
	var prompt_duration_ns: int = int(response.get("prompt_eval_duration", 0))
	var eval_duration_ns: int = int(response.get("eval_duration", 0))
	return {
		"total_duration_ms": float(response.get("total_duration", 0)) / 1000000.0,
		"load_duration_ms": float(response.get("load_duration", 0)) / 1000000.0,
		"prompt_tokens": prompt_eval_count,
		"completion_tokens": eval_count,
		"prompt_tokens_per_second": _tokens_per_second(
			prompt_eval_count,
			prompt_duration_ns
		),
		"completion_tokens_per_second": _tokens_per_second(
			eval_count,
			eval_duration_ns
		),
		"done_reason": String(response.get("done_reason", "")),
	}

# Enhanced functionality
func get_capabilities() -> Dictionary:
	var resolved_metadata: Dictionary = get_model_metadata()
	var capabilities_any: Variant = resolved_metadata.get(
		"capabilities",
		[]
	)
	var model_capabilities: Array = (
		capabilities_any if typeof(capabilities_any) == TYPE_ARRAY else []
	)
	return {
		"streaming": true,
		"cancellation": true,
		"structured_json": true,
		"max_tokens": _context_length_for(model_name),
		"context_length": _context_length_for(model_name),
		"supports_system_prompt": true,
		"supports_functions": model_capabilities.has("tools"),
		"supports_vision": model_capabilities.has("vision"),
		"provider": provider,
		"base_url": base_url,
		"available_models": get_available_models(),
		"model_metadata": resolved_metadata,
		"supports_frequency_penalty": false,
		"supports_presence_penalty": false,
		"supports_top_p": true,
		"supports_local_execution": true,
		"supports_thinking": model_capabilities.has("thinking"),
		"supports_custom_models": true
	}

func validate_settings(settings: Dictionary) -> Dictionary:
	var errors = super.validate_settings(settings)
	
	if settings.has("top_p"):
		if settings.top_p <= 0.0 or settings.top_p > 1.0:
			errors["top_p"] = "Must be between 0.0 and 1.0"
	
	return errors

# ── Embeddings (Tier 3) ───────────────────────────────────────────────────
# Ollama /api/embed supports batch embedding with any model.

func supports_embeddings() -> bool:
	return true

func get_embeddings_url(_api_key_to_use: String = "") -> String:
	# base_url is ".../api/chat", swap to /api/embed
	return base_url.replace("/api/chat", "/api/embed")

func prepare_embeddings_request(texts: Array) -> Dictionary:
	return {"model": model_name, "input": texts}

func parse_embeddings_response(response_body: Dictionary) -> Array:
	# Ollama /api/embed returns {"embeddings": [[...], [...]]}
	var embeddings_any: Variant = response_body.get("embeddings", [])
	if typeof(embeddings_any) == TYPE_ARRAY:
		return embeddings_any as Array
	return []

func set_model(new_model: String) -> bool:
	# Ollama supports custom models, so check known list but allow others
	if not new_model in MAX_TOKENS_BY_MODEL:
		print("OllamaModelLoader: Unknown model '%s'. Using default max_tokens (4096)." % new_model)
		max_tokens = 4096
	else:
		max_tokens = MAX_TOKENS_BY_MODEL[new_model]
	
	model_name = new_model
	return true


func _context_length_for(requested_model: String) -> int:
	var metadata_any: Variant = _model_metadata.get(requested_model, {})
	if typeof(metadata_any) == TYPE_DICTIONARY:
		var metadata: Dictionary = metadata_any
		var discovered_context: int = int(
			metadata.get("context_length", 0)
		)
		if discovered_context > 0:
			return discovered_context
	return int(MAX_TOKENS_BY_MODEL.get(requested_model, 4096))


func _tokens_per_second(token_count: int, duration_ns: int) -> float:
	if token_count <= 0 or duration_ns <= 0:
		return 0.0
	return float(token_count) / (float(duration_ns) / 1000000000.0)


func _normalize_origin(origin_url: String) -> String:
	var normalized: String = origin_url.strip_edges().trim_suffix("/")
	normalized = normalized.trim_suffix("/api/chat")
	if not (
		normalized.begins_with("http://")
		or normalized.begins_with("https://")
	):
		return ""
	return normalized
