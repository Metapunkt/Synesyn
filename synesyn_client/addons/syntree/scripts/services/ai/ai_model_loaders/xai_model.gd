## Purpose: XAIModelLoader — OpenAI-compatible xAI (Grok) chat completions.
extends BaseAIModelLoader
class_name XAIModelLoader

## Model ids use a dot (grok-4.5), not a dash. Chat Completions endpoint:
## https://api.x.ai/v1/chat/completions
##
## A model absent from this list cannot be selected or routed to, so a scenario naming one
## silently falls back to the global selection. The list is maintained by hand against
## `GET https://api.x.ai/v1/models`, which is the authority on what a key actually serves;
## the image and video models it also returns are omitted, being no use to a chat call.
##
## The `non-reasoning` variant answers in about a second where a reasoning model spends
## five to ten, which is the difference between a staged line landing in conversational
## time and a visible wait. It rejects a reasoning budget outright, so APIService does not
## send one to it.
const AVAILABLE_MODELS: Array[String] = [
	"grok-4.6",
	"grok-4.5",
	"grok-4.5-latest",
	"grok-4.3",
	"grok-4.20-0309-reasoning",
	"grok-4.20-0309-non-reasoning",
	"grok-4.20-multi-agent-0309",
	"grok-build-0.1",
	"grok-build-latest",
]

const MAX_TOKENS_BY_MODEL: Dictionary = {
	"grok-4.6": 32768,
	"grok-4.5": 32768,
	"grok-4.5-latest": 32768,
	"grok-4.3": 32768,
	"grok-4.20-0309-reasoning": 32768,
	"grok-4.20-0309-non-reasoning": 32768,
	"grok-4.20-multi-agent-0309": 32768,
	"grok-build-0.1": 32768,
	"grok-build-latest": 32768,
}

const DEFAULT_MAX_TOKENS: int = 32768
const DEFAULT_TEMPERATURE: float = 0.7


func get_available_models() -> Array:
	return AVAILABLE_MODELS.duplicate()


func _init() -> void:
	provider = "xAI"
	base_url = "https://api.x.ai/v1/chat/completions"
	model_name = "grok-4.5"
	max_tokens = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	temperature = DEFAULT_TEMPERATURE
	api_key = ""


func prepare_request(
	messages: Array,
	system_prompt: String = "",
	effective_model: String = ""
) -> Dictionary:
	var formatted_messages: Array = []
	if not system_prompt.is_empty():
		formatted_messages.append({"role": "system", "content": system_prompt})
	for msg_any: Variant in messages:
		if typeof(msg_any) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_any
		if msg.has("role") and msg.has("content"):
			formatted_messages.append({"role": msg.role, "content": msg.content})
		else:
			push_warning("XAIModelLoader: Skipping message with missing role/content: " + str(msg))
	var call_model: String = (
		effective_model.strip_edges() if not effective_model.strip_edges().is_empty() else model_name
	)
	var call_max_tokens: int = int(MAX_TOKENS_BY_MODEL.get(call_model, max_tokens))
	return {
		"model": call_model,
		"messages": formatted_messages,
		"max_tokens": call_max_tokens,
		"temperature": temperature,
	}


func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	if api_key_to_use.is_empty():
		push_error("XAIModelLoader: API key is required.")
		return PackedStringArray(["Content-Type: application/json"])
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key_to_use,
	])


func parse_response(response_body: Dictionary) -> String:
	if response_body.has("error"):
		var error_info: Variant = response_body.error
		var msg: String = "Unknown xAI error"
		if typeof(error_info) == TYPE_DICTIONARY:
			msg = String((error_info as Dictionary).get("message", msg))
		elif typeof(error_info) == TYPE_STRING:
			msg = String(error_info)
		push_error("xAI API Error: " + msg)
		return ""
	if response_body.has("choices") and response_body.choices is Array:
		var choices: Array = response_body.choices
		if not choices.is_empty() and typeof(choices[0]) == TYPE_DICTIONARY:
			var first_choice: Dictionary = choices[0]
			if first_choice.has("message") and typeof(first_choice.message) == TYPE_DICTIONARY:
				return String((first_choice.message as Dictionary).get("content", ""))
	push_error("Could not parse xAI response structure: " + str(response_body))
	return ""


func get_capabilities() -> Dictionary:
	var base_capabilities: Dictionary = super.get_capabilities()
	base_capabilities["provider"] = provider
	base_capabilities["base_url"] = base_url
	base_capabilities["available_models"] = AVAILABLE_MODELS
	base_capabilities["max_tokens"] = MAX_TOKENS_BY_MODEL.get(model_name, DEFAULT_MAX_TOKENS)
	base_capabilities["supports_system_prompt"] = true
	base_capabilities["supports_functions"] = true
	base_capabilities["supports_structured_outputs"] = true
	base_capabilities["supports_vision"] = true
	return base_capabilities


func set_model(new_model: String) -> bool:
	if new_model not in AVAILABLE_MODELS:
		push_warning(
			"XAIModelLoader: Unknown model '%s'. Using default max tokens." % new_model
		)
		max_tokens = DEFAULT_MAX_TOKENS
	else:
		max_tokens = int(MAX_TOKENS_BY_MODEL.get(new_model, DEFAULT_MAX_TOKENS))
	model_name = new_model
	return true


func supports_embeddings() -> bool:
	return false
