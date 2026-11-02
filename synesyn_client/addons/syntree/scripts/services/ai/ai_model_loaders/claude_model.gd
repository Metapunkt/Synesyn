## Purpose: ClaudeModelLoader (script)
extends BaseAIModelLoader

class_name ClaudeModelLoader

# Constants
const AVAILABLE_MODELS = ["claude-2.1", "claude-instant-1.2"]
const MAX_TOKENS_BY_MODEL = {
	"claude-2.1": 100000,
	"claude-instant-1.2": 100000
}

func _init():
	provider = "Anthropic"
	base_url = "https://api.anthropic.com/v1/messages"
	model_name = "claude-2.1"  # Default model
	max_tokens = MAX_TOKENS_BY_MODEL[model_name]
	temperature = 0.7

func prepare_request(messages: Array, system_prompt: String = "", effective_model: String = "") -> Dictionary:
	var formatted_messages = []
	
	# Skip the system message if it exists in messages array, 
	# as Claude expects it as a separate parameter
	for message in messages:
		if message.get("role") != "system": # Use .get for safety
			# Basic validation
			if message.has("role") and message.has("content"):
				formatted_messages.append({
					"role": message["role"],
					"content": message["content"]
				})
			else:
				push_warning("ClaudeModelLoader: Skipping message with missing role/content: " + str(message))

	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name
	var call_max_tokens: int = MAX_TOKENS_BY_MODEL.get(call_model, max_tokens)

	var request_data = {
		"model": call_model,
		"messages": formatted_messages,
		"max_tokens": call_max_tokens,
		"temperature": temperature
	}
	
	# Add system prompt/context if provided via the parameter
	if not system_prompt.is_empty():
		request_data["system"] = system_prompt
	
	return request_data

# Returns the necessary HTTP headers for Claude API calls (same as Anthropic).
# Parameters:
#   api_key_to_use (String): The API key to include in the x-api-key header.
func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	# Same headers as Anthropic
	return [
		"x-api-key: " + api_key_to_use,
		"anthropic-version: 2023-06-01", # Use the standard Anthropic version
		"Content-Type: application/json"
	]

func parse_response(response: Dictionary) -> String:
	if response.has("content") and response["content"] is Array:
		return response["content"][0]["text"]
	return ""

# Enhanced functionality
func get_capabilities() -> Dictionary:
	var base_capabilities = super.get_capabilities()
	return {
		"streaming": true,
		"max_tokens": MAX_TOKENS_BY_MODEL[model_name],
		"supports_system_prompt": true,
		"supports_functions": false,
		"supports_vision": false,
		"provider": provider,
		"base_url": base_url,
		"available_models": AVAILABLE_MODELS,
		"supports_frequency_penalty": false,
		"supports_presence_penalty": false,
		"supports_top_p": true,
		"supports_long_context": true
	}

func validate_settings(settings: Dictionary) -> Dictionary:
	var errors = super.validate_settings(settings)
	
	if settings.has("top_p"):
		if settings.top_p <= 0.0 or settings.top_p > 1.0:
			errors["top_p"] = "Must be between 0.0 and 1.0"
	
	return errors

func set_model(new_model: String) -> bool:
	if not new_model in AVAILABLE_MODELS:
		push_error("ClaudeModelLoader: Invalid model name: " + new_model)
		return false
		
	model_name = new_model
	max_tokens = MAX_TOKENS_BY_MODEL[model_name]
	return true
