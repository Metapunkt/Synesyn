## Purpose: OpenAIModelLoader (script)
extends BaseAIModelLoader

class_name OpenAIModelLoader

# Constants
const AVAILABLE_MODELS = [
	# See OpenAI model docs:
	# - https://platform.openai.com/docs/models
	# - https://platform.openai.com/docs/models/gpt-5.2
	#
	# Keep this list tight and provider-valid.
	"gpt-5.2",
	"gpt-5.2-2025-12-11",
	"gpt-4o",
	"gpt-4o-mini"
]
const MAX_TOKENS_BY_MODEL = {
	# NOTE: max_tokens here is MAX *OUTPUT* tokens (OpenAI `max_tokens`), not context window.
	# GPT-5.2: 400k context, 128k max output.
	"gpt-5.2": 128000,
	"gpt-5.2-2025-12-11": 128000,
	"gpt-4o": 4096,
	"gpt-4o-mini": 4096
}

func get_available_models() -> Array:
	return AVAILABLE_MODELS.duplicate()

func _init():
	provider = "OpenAI"
	base_url = "https://api.openai.com/v1/chat/completions"
	# Default to a broadly-available model; users can pick GPT-5.2 if their account has access.
	model_name = "gpt-4o-mini"
	max_tokens = MAX_TOKENS_BY_MODEL[model_name]
	temperature = 0.7
	api_key = "" # Initialize

# Keep base signature, use system_prompt parameter for context.
# `effective_model` (optional): per-call model override; empty string keeps
# legacy behavior of using `self.model_name`.
func prepare_request(messages: Array, system_prompt: String = "", effective_model: String = "") -> Dictionary:
	var formatted_messages = []
	
	# Add system prompt/context if provided via the parameter
	if not system_prompt.is_empty():
		formatted_messages.append({"role": "system", "content": system_prompt})
	
	# Add user/assistant messages from history + new prompt
	for msg in messages:
		# Basic validation
		if msg.has("role") and msg.has("content"):
			formatted_messages.append({"role": msg.role, "content": msg.content})
		else:
			push_warning("OpenAIModelLoader: Skipping message with missing role/content: " + str(msg))

	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name
	var call_max_tokens: int = MAX_TOKENS_BY_MODEL.get(call_model, max_tokens)

	# Use internal temperature/max_tokens
	# If per-call settings are needed later, a different approach is required
	return {
		"model": call_model,
		"messages": formatted_messages,
		"max_tokens": call_max_tokens,
		"temperature": temperature
	}

# Returns the necessary HTTP headers for OpenAI API calls.
# Parameters:
#   api_key_to_use (String): The API key to include in the Authorization header.
func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	return [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key_to_use
	]

func parse_response(response: Dictionary) -> String:
	if response.has("choices") and response["choices"].size() > 0:
		return response["choices"][0]["message"]["content"]
	return ""

# Enhanced functionality
func get_capabilities() -> Dictionary:
	var base_capabilities = super.get_capabilities()
	return {
		"streaming": true,
		"max_tokens": MAX_TOKENS_BY_MODEL[model_name],
		"supports_system_prompt": true,
		"supports_functions": true,
		"supports_vision": model_name == "gpt-4o" or model_name == "gpt-4o-mini",
		"provider": provider,
		"base_url": base_url,
		"available_models": AVAILABLE_MODELS,
		"supports_frequency_penalty": true,
		"supports_presence_penalty": true,
		"supports_top_p": true
	}

func validate_settings(settings: Dictionary) -> Dictionary:
	var errors = super.validate_settings(settings)
	
	if settings.has("frequency_penalty"):
		if settings.frequency_penalty < -2.0 or settings.frequency_penalty > 2.0:
			errors["frequency_penalty"] = "Must be between -2.0 and 2.0"
			
	if settings.has("presence_penalty"):
		if settings.presence_penalty < -2.0 or settings.presence_penalty > 2.0:
			errors["presence_penalty"] = "Must be between -2.0 and 2.0"
			
	if settings.has("top_p"):
		if settings.top_p <= 0.0 or settings.top_p > 1.0:
			errors["top_p"] = "Must be between 0.0 and 1.0"
	
	return errors

# ── Embeddings (Tier 3) ───────────────────────────────────────────────────
# OpenAI /v1/embeddings uses a dedicated embedding model.

const EMBEDDING_MODEL := "text-embedding-3-small"

func supports_embeddings() -> bool:
	return true

func get_embeddings_url(_api_key_to_use: String = "") -> String:
	return "https://api.openai.com/v1/embeddings"

func prepare_embeddings_request(texts: Array) -> Dictionary:
	return {"model": EMBEDDING_MODEL, "input": texts}

func get_embeddings_headers(api_key_to_use: String = "") -> PackedStringArray:
	return get_headers(api_key_to_use)

func parse_embeddings_response(response_body: Dictionary) -> Array:
	# OpenAI returns {"data": [{"embedding": [...], "index": 0}, ...]}
	var data_any: Variant = response_body.get("data", [])
	if typeof(data_any) != TYPE_ARRAY:
		return []
	var data: Array = data_any
	# Sort by index to ensure correct ordering
	data.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
	var vectors: Array = []
	for entry_any in data:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var vec_any: Variant = entry.get("embedding", [])
		if typeof(vec_any) == TYPE_ARRAY:
			vectors.append(vec_any)
	return vectors

func set_model(new_model: String) -> bool:
	if not new_model in AVAILABLE_MODELS:
		push_error("OpenAIModelLoader: Invalid model name: " + new_model)
		return false
		
	model_name = new_model
	max_tokens = MAX_TOKENS_BY_MODEL.get(model_name, 4096)
	return true
