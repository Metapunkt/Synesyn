## Purpose: AnthropicModelLoader (script)
extends BaseAIModelLoader

class_name AnthropicModelLoader

# Constants
const AVAILABLE_MODELS = [
	"claude-sonnet-4-6",
	"claude-sonnet-4-5",
	"claude-opus-4-20250514",
	"claude-sonnet-4-20250514",
	"claude-3-7-sonnet-20250219",
	"claude-3-5-sonnet-20241022",
	"claude-3-5-haiku-20241022",
]

const MAX_TOKENS_BY_MODEL = {
	# max_tokens here is MAX *OUTPUT* tokens (Anthropic `max_tokens`), not context window.
	"claude-sonnet-4-6": 64000,
	"claude-sonnet-4-5": 64000,
	"claude-opus-4-20250514": 8192,
	"claude-sonnet-4-20250514": 8192,
	"claude-3-7-sonnet-20250219": 8192,
	"claude-3-5-sonnet-20241022": 8192,
	"claude-3-5-haiku-20241022": 4096,
}

# Models that support automatic prompt caching (system + history cached transparently).
const CACHE_ELIGIBLE_MODELS = [
	"claude-sonnet-4-6",
	"claude-sonnet-4-5",
	"claude-opus-4-20250514",
	"claude-sonnet-4-20250514",
]

const DEFAULT_TEMPERATURE = 0.5
const API_VERSION = "2023-06-01"

func get_available_models() -> Array:
	return AVAILABLE_MODELS.duplicate()

func _init():
	provider = "Anthropic"
	base_url = "https://api.anthropic.com/v1/messages"
	model_name = "claude-sonnet-4-6"
	max_tokens = MAX_TOKENS_BY_MODEL[model_name]
	temperature = DEFAULT_TEMPERATURE

func prepare_request(messages: Array, system_prompt: String = "", effective_model: String = "") -> Dictionary:
	var formatted_messages = []
	for msg in messages:
		if msg.has("role") and msg.has("content"):
			formatted_messages.append({"role": msg.role, "content": msg.content})
		else:
			push_warning("AnthropicModelLoader: Skipping message with missing role/content: " + str(msg))

	# Resolve the model id to use for THIS call. Empty override keeps legacy
	# behavior (use the loader's set model). When an override is provided we also
	# recompute max_tokens against the per-model table so request bodies stay valid.
	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name
	var call_max_tokens: int = MAX_TOKENS_BY_MODEL.get(call_model, max_tokens)

	var request_data: Dictionary = {
		"model": call_model,
		"messages": formatted_messages,
		"max_tokens": call_max_tokens,
		"temperature": temperature,
	}

	var is_cache_eligible := call_model in CACHE_ELIGIBLE_MODELS

	if not system_prompt.is_empty():
		if is_cache_eligible:
			request_data["system"] = _build_cached_system_blocks(system_prompt)
		else:
			request_data["system"] = system_prompt

	if is_cache_eligible and formatted_messages.size() >= 4:
		_mark_conversation_cache_breakpoint(formatted_messages)

	return request_data


func _build_cached_system_blocks(system_prompt: String) -> Array:
	var blocks: Array = []
	var split_marker := "## SCENARIO CONTINUITY HINTS"
	var split_idx := system_prompt.find(split_marker)

	if split_idx > 0:
		var stable_part := system_prompt.substr(0, split_idx).strip_edges()
		var dynamic_part := system_prompt.substr(split_idx).strip_edges()
		blocks.append({
			"type": "text",
			"text": stable_part,
			"cache_control": {"type": "ephemeral"},
		})
		blocks.append({
			"type": "text",
			"text": dynamic_part,
		})
	else:
		blocks.append({
			"type": "text",
			"text": system_prompt,
			"cache_control": {"type": "ephemeral"},
		})
	return blocks


func _mark_conversation_cache_breakpoint(formatted_messages: Array) -> void:
	var breakpoint_idx: int = mini(formatted_messages.size() - 2, 3)
	if breakpoint_idx < 0:
		return
	var msg: Dictionary = formatted_messages[breakpoint_idx]
	var content_val = msg.get("content", "")
	if typeof(content_val) == TYPE_STRING:
		msg["content"] = [
			{
				"type": "text",
				"text": content_val,
				"cache_control": {"type": "ephemeral"},
			}
		]
	elif typeof(content_val) == TYPE_ARRAY:
		var arr: Array = content_val
		if not arr.is_empty() and typeof(arr[arr.size() - 1]) == TYPE_DICTIONARY:
			var last_block: Dictionary = arr[arr.size() - 1]
			last_block["cache_control"] = {"type": "ephemeral"}

func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	return get_headers_for_model(api_key_to_use, "")

# `effective_model` lets `chat_completion` request headers tuned for a per-call
# model override (e.g. the prompt-caching beta header should be added based on
# the model that will actually be used, not the loader's stored model_name).
# Empty string falls back to the loader's set model.
func get_headers_for_model(api_key_to_use: String = "", effective_model: String = "") -> PackedStringArray:
	var call_model: String = effective_model.strip_edges() if effective_model != "" else model_name
	var headers := PackedStringArray([
		"x-api-key: " + api_key_to_use,
		"anthropic-version: " + API_VERSION,
		"Content-Type: application/json",
	])
	if call_model in CACHE_ELIGIBLE_MODELS:
		headers.append("anthropic-beta: prompt-caching-2024-07-31")
	return headers

func parse_response(response: Dictionary) -> String:
	if response.has("error"):
		push_error("Anthropic API error: " + str(response.error))
		return ""

	if response.has("content"):
		var content: Array = response.get("content", [])
		for block in content:
			if typeof(block) == TYPE_DICTIONARY and block.get("type", "") == "text":
				return String(block.get("text", ""))
		if content.size() > 0 and content[0].has("text"):
			return String(content[0].text)

	if response.has("message"):
		var message_val = response.get("message", {})
		if typeof(message_val) == TYPE_DICTIONARY and message_val.has("content"):
			return String(message_val.content)

	push_error("Unexpected Anthropic API response format: " + str(response))
	return ""

func get_capabilities() -> Dictionary:
	var base_capabilities = super.get_capabilities()
	base_capabilities["streaming"] = true
	base_capabilities["supports_system_prompt"] = true
	base_capabilities["supports_functions"] = false
	base_capabilities["supports_vision"] = model_name.begins_with("claude-3")
	base_capabilities["supports_prompt_caching"] = model_name in CACHE_ELIGIBLE_MODELS
	return base_capabilities

func validate_settings(settings: Dictionary) -> Dictionary:
	var errors = super.validate_settings(settings)
	if settings.has("model"):
		if not settings["model"] in AVAILABLE_MODELS:
			errors["model"] = "Invalid model. Available models: " + ", ".join(AVAILABLE_MODELS)
	return errors

func set_model(new_model: String) -> bool:
	if not new_model in AVAILABLE_MODELS:
		push_error("AnthropicModelLoader: Invalid model name: " + new_model)
		return false
	model_name = new_model
	max_tokens = MAX_TOKENS_BY_MODEL.get(new_model, 8192)
	return true
