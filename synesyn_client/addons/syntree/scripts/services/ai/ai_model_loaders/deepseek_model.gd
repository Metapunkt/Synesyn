## Purpose: DeepseekModelLoader (script)
extends BaseAIModelLoader
class_name DeepseekModelLoader

## Constants for Deepseek
## Using standard API model names
#const AVAILABLE_MODELS = ["deepseek-chat", "deepseek-coder"]
#const MAX_TOKENS_BY_MODEL = {
	#"deepseek-chat": 16384, # Example, check actual limits
	#"deepseek-coder": 16384 # Example
#}
#const DEFAULT_MAX_TOKENS = 16384
#const DEFAULT_TEMPERATURE = 0.7
#
#func _init():
	#provider = "Deepseek"
	#base_url = "https://api.deepseek.com/v1/chat/completions" # Standard endpoint
	#model_name = "deepseek-chat" # Default model
	#max_tokens = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	#temperature = DEFAULT_TEMPERATURE
	#api_key = "" # Initialize API key

# Constants for Deepseek
# Updated model names for V3/R1 integration
const AVAILABLE_MODELS = [
	"deepseek-chat", 
	"deepseek-coder",
	"deepseek-ai/DeepSeek-V3",  # V3 model identifier [1][3]
	"deepseek-ai/DeepSeek-R1"   # R1 model identifier [4][5]
]

const MAX_TOKENS_BY_MODEL = {
	"deepseek-chat": 16384,
	"deepseek-coder": 16384,
	"deepseek-ai/DeepSeek-V3": 16384,  # Example value - actual limit may vary
	"deepseek-ai/DeepSeek-R1": 16384    # Check API docs for exact limits [4]
}

# API configuration updates
const DEFAULT_MAX_TOKENS = 16384
const DEFAULT_TEMPERATURE = 0.7

func get_available_models() -> Array:
	return AVAILABLE_MODELS.duplicate()

func _init():
	provider = "Deepseek"
	base_url = "https://api.deepinfra.com/v1/openai/chat/completions"  # Updated endpoint [3][5]
	model_name = "deepseek-ai/DeepSeek-V3"  # New default model
	max_tokens = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	temperature = DEFAULT_TEMPERATURE
	api_key = ""  # Use DEEPINFRA_TOKEN for authentication [3][5]

# Deepseek API is very similar to OpenAI's structure
func prepare_request(messages: Array, system_prompt: String = "", effective_model: String = "") -> Dictionary:
	var formatted_messages = []
	# Handle system prompt if provided
	if not system_prompt.is_empty():
		formatted_messages.append({"role": "system", "content": system_prompt})
	
	# Add user/assistant messages
	for msg in messages:
		# Basic validation
		if msg.has("role") and msg.has("content"):
			formatted_messages.append({"role": msg.role, "content": msg.content})
		else:
			push_warning("DeepseekModelLoader: Skipping message with missing role/content: " + str(msg))

	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name
	var call_max_tokens: int = MAX_TOKENS_BY_MODEL.get(call_model, max_tokens)

	var request_data = {
		"model": call_model,
		"messages": formatted_messages,
		"max_tokens": call_max_tokens,
		"temperature": temperature
	}
	return request_data

# Deepseek uses Bearer token authentication
func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	if api_key_to_use.is_empty():
		push_error("DeepseekModelLoader: API key is required.")
		# Return minimal headers, request will likely fail
		return ["Content-Type: application/json"] 
	return [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key_to_use
	]

# Standard OpenAI-like response structure
func parse_response(response_body: Dictionary) -> String:
	if response_body.has("error"):
		var error_info = response_body.error
		var msg = error_info.get("message", "Unknown Deepseek error in response body.")
		push_error("Deepseek API Error: " + msg + " (Type: " + error_info.get("type", "N/A") + ")")
		return ""

	if response_body.has("choices") and response_body.choices is Array:
		if response_body.choices.size() > 0:
			var first_choice = response_body.choices[0]
			if first_choice.has("message") and first_choice.message.has("content"):
				return first_choice.message.content

	push_error("Could not parse Deepseek response structure: " + str(response_body))
	return ""

# --- Override get_capabilities ---
func get_capabilities() -> Dictionary:
	var base_capabilities = super.get_capabilities()
	base_capabilities["provider"] = provider
	base_capabilities["base_url"] = base_url
	base_capabilities["available_models"] = AVAILABLE_MODELS
	base_capabilities["max_tokens"] = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	base_capabilities["supports_system_prompt"] = true
	# Add other Deepseek specific capabilities if known
	return base_capabilities

# --- Override set_model ---
func set_model(new_model: String) -> bool:
	if not new_model in AVAILABLE_MODELS:
		# Allow potentially unknown models but use default token limit
		push_warning("DeepseekModelLoader: Unknown model '%s'. Using default max tokens." % new_model)
		max_tokens = DEFAULT_MAX_TOKENS
	else:
		max_tokens = MAX_TOKENS_BY_MODEL.get(new_model, DEFAULT_MAX_TOKENS)
		
	model_name = new_model
	return true

# --- Override validate_settings ---
# func validate_settings(settings: Dictionary) -> Dictionary:
#	 var errors = super.validate_settings(settings)
#	 # Add Deepseek specific checks
#	 return errors
