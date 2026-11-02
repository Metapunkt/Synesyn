## Purpose: GeminiModelLoader (script)
extends BaseAIModelLoader
class_name GeminiModelLoader

## Constants for Gemini
## Use specific versions or 'latest' tags as appropriate
#const AVAILABLE_MODELS = ["gemini-1.5-pro-latest", "gemini-1.5-flash-latest", "gemini-pro"]
#const MAX_TOKENS_BY_MODEL = {
	#"gemini-1.5-pro-latest": 8192,
	#"gemini-1.5-flash-latest": 8192, 
	#"gemini-pro": 8192 # Older model, check effective limits
#}
#const DEFAULT_MAX_TOKENS = 8192
#const DEFAULT_TEMPERATURE = 0.7
#const API_VERSION = "v1beta" # Use v1beta for latest features
#
#func _init():
	#provider = "Google"
	## Base URL structure - model name is part of the path
	#base_url = "https://generativelanguage.googleapis.com/" + API_VERSION + "/models/"
	#model_name = "gemini-1.5-flash-latest" # Default model
	#max_tokens = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	#temperature = DEFAULT_TEMPERATURE
	#api_key = "" # Initialize API key

# Constants for Gemini
# Use specific versions or 'latest' tags as appropriate
const AVAILABLE_MODELS = [
	# Gemini 3 (see docs)
	# https://ai.google.dev/gemini-api/docs/gemini-3
	"gemini-3-pro",
	"gemini-3-flash",
	"gemini-1.5-pro-latest",
	"gemini-1.5-flash-latest",
	# Gemini 2.x (stable tags)
	"gemini-2.0-flash",
	"gemini-2.0-flash-lite"
]

const MAX_TOKENS_BY_MODEL = {
	# NOTE: max_tokens here maps to Gemini `maxOutputTokens` (output cap).
	# Keep conservative defaults unless the provider docs guarantee higher output caps.
	"gemini-3-pro": 65536,
	"gemini-3-flash": 8192,
	"gemini-1.5-pro-latest": 8192,
	"gemini-1.5-flash-latest": 8192,
	"gemini-2.0-flash": 8192,
	"gemini-2.0-flash-lite": 8192
}

const DEFAULT_MAX_TOKENS = 8192
const DEFAULT_TEMPERATURE = 0.7
const API_VERSION = "v1beta"  # Use v1beta for latest features

func get_available_models() -> Array:
	return AVAILABLE_MODELS.duplicate()

func _init():
	provider = "Google"
	# Base URL structure - model name is part of the path
	base_url = "https://generativelanguage.googleapis.com/" + API_VERSION + "/models/"
	model_name = "gemini-3-flash"
	max_tokens = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	temperature = DEFAULT_TEMPERATURE
	api_key = ""  # Initialize API key

# Helper method moved out of prepare_request
func _add_parts_to_contents(contents: Array, current_role: String, current_parts: Array) -> void:
	if not current_parts.is_empty() and not current_role.is_empty():
		contents.append({"role": current_role, "parts": current_parts})

# Gemini API expects a specific 'contents' structure.
# System prompts are handled differently - often as the first part of the first 'user' turn.
# `effective_model` lets a caller pick a per-call model; the URL endpoint is built
# separately by `get_request_endpoint_with_key()` which also accepts an override.
func prepare_request(messages: Array, system_prompt: String = "", effective_model: String = "") -> Dictionary:
	var contents = []
	var current_role = ""
	var current_parts = []

	# Prepend system prompt/context as the first instruction if provided
	if not system_prompt.is_empty():
		current_role = "user"
		current_parts.append({"text": system_prompt})
		# Check if the first *actual* message is 'assistant' to add a dummy model turn
		if not messages.is_empty() and messages[0].get("role") == "assistant": # Safer get
			_add_parts_to_contents(contents, current_role, current_parts)
			current_parts = [] # Reset parts
			current_role = "model"
			current_parts.append({"text": "Okay."}) # Placeholder model response


	for msg in messages:
		# Safer access to role/content
		var msg_role = msg.get("role", "user") # Default to user if missing
		var msg_content = msg.get("content", "")
		if msg_content.is_empty(): 
			push_warning("GeminiModelLoader: Skipping empty message content.")
			continue
			
		var target_role = "user" if msg_role == "user" else "model"

		# If the role changes, add the accumulated parts for the previous role
		if current_role != "" and current_role != target_role:
			_add_parts_to_contents(contents, current_role, current_parts)
			current_parts = [] # Reset parts for the new role

		# Start accumulating for the new/current role
		current_role = target_role
		current_parts.append({"text": msg_content})

	# Add any remaining accumulated parts
	_add_parts_to_contents(contents, current_role, current_parts)

	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name
	var call_max_tokens: int = MAX_TOKENS_BY_MODEL.get(call_model, max_tokens)

	var generation_config = {
		"temperature": temperature,
		"maxOutputTokens": call_max_tokens
	}

	return {
		"contents": contents,
		"generationConfig": generation_config
	}

# Gemini requires API Key in the URL query parameters. Headers are simple.
func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	return ["Content-Type: application/json"]

# Special function called by APIService for providers needing API key in URL
# Returns the full endpoint URL including the API key.
# `effective_model` (optional): per-call model override; empty string keeps the
# loader's internal model_name (legacy behavior).
func get_request_endpoint_with_key(api_key_to_use: String, effective_model: String = "") -> String:
	if api_key_to_use.is_empty():
		push_error("GeminiModelLoader: API key is required for request.")
		return "" # Indicate error

	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name
	var task = ":generateContent" # Standard task for chat-like generation
	# Construct the full URL: base + model + task + key parameter
	return base_url + call_model + task + "?key=" + api_key_to_use

# Parse the Gemini response structure.
func parse_response(response_body: Dictionary) -> String:
	if response_body.has("error"):
		var error_info = response_body.error
		var msg = error_info.get("message", "Unknown Gemini error in response body.")
		push_error("Gemini API Error: " + msg + " (Code: " + str(error_info.get("code", "N/A")) + ")")
		return "" # Return empty on error

	if response_body.has("candidates") and response_body.candidates is Array:
		if response_body.candidates.size() > 0:
			var first_candidate = response_body.candidates[0]
			# Check for safety ratings causing block
			if first_candidate.has("finishReason") and first_candidate.finishReason != "STOP":
				push_warning("Gemini response finished due to: %s. Check safety ratings." % first_candidate.finishReason)
				# You might want to return a specific message or check safetyRatings here.
				# return "[Content blocked due to: %s]" % first_candidate.finishReason
			
			if first_candidate.has("content") and first_candidate.content.has("parts"):
				if first_candidate.content.parts is Array and first_candidate.content.parts.size() > 0:
					if first_candidate.content.parts[0].has("text"):
						return first_candidate.content.parts[0].text

	push_error("Could not parse Gemini response structure: " + str(response_body))
	return ""


# --- Override get_capabilities ---
func get_capabilities() -> Dictionary:
	var base_capabilities = super.get_capabilities()
	base_capabilities["provider"] = provider
	base_capabilities["base_url"] = base_url # Note: actual URL is constructed later
	base_capabilities["available_models"] = AVAILABLE_MODELS
	base_capabilities["max_tokens"] = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	base_capabilities["supports_system_prompt"] = true # Handled via message formatting
	# Add other Gemini specific capabilities if known
	return base_capabilities
	
# --- Override set_model ---
func set_model(new_model: String) -> bool:
	if not new_model in AVAILABLE_MODELS:
		# Check if it follows general gemini naming convention maybe?
		if not new_model.begins_with("gemini-"):
			push_error("GeminiModelLoader: Invalid model name format: " + new_model)
			return false
		# Allow potentially unknown models but use default token limit
		push_warning("GeminiModelLoader: Unknown model '%s'. Using default max tokens." % new_model)
		max_tokens = DEFAULT_MAX_TOKENS
	else:
		max_tokens = MAX_TOKENS_BY_MODEL.get(new_model, DEFAULT_MAX_TOKENS)

	model_name = new_model
	# Base URL doesn't change with model for Gemini, it's part of the path
	return true
	
# --- Override validate_settings ---
# func validate_settings(settings: Dictionary) -> Dictionary:
#	 var errors = super.validate_settings(settings)
#	 # Add Gemini specific checks for topP, topK etc. if desired
#	 return errors
