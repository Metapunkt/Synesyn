## Purpose: BaseAIModelLoader (script)
class_name BaseAIModelLoader
extends RefCounted

# Common properties all models should have
var model_name: String
var provider: String
var api_key: String
var base_url: String
var max_tokens: int
var temperature: float

func get_available_models() -> Array:
	return []

# Virtual methods that must be implemented by specific model classes.
# `effective_model` (optional): if non-empty, the subclass should use this model
# for the request body / max_tokens / cache decisions WITHOUT mutating its own
# `model_name`. Empty string keeps legacy behavior (use `self.model_name`).
func prepare_request(messages: Array, system_prompt: String = "", effective_model: String = "") -> Dictionary:
	push_error("prepare_request() must be implemented by subclass")
	return {}

func parse_response(response_body: Dictionary) -> String:
	push_error("parse_response() must be implemented by subclass")
	return ""

func get_headers(api_key_to_use: String = "") -> PackedStringArray:
	push_error("get_headers() must be implemented by subclass")
	return []

# ── Embeddings (Tier 3) ───────────────────────────────────────────────────
# Subclasses override these to enable model-provider embeddings.
# The caller is responsible for making the HTTP request; the loader only
# prepares the payload and parses the response.

## Returns true if this provider supports an embeddings endpoint.
func supports_embeddings() -> bool:
	return false

## Returns the full URL for the embeddings endpoint.
func get_embeddings_url(_api_key_to_use: String = "") -> String:
	return ""

## Builds the JSON request body for embedding a batch of texts.
func prepare_embeddings_request(_texts: Array) -> Dictionary:
	return {}

## Returns HTTP headers needed for the embeddings request.
func get_embeddings_headers(api_key_to_use: String = "") -> PackedStringArray:
	return get_headers(api_key_to_use)

## Parses the provider response into an Array of Array[float] vectors.
func parse_embeddings_response(_response_body: Dictionary) -> Array:
	return []

# Enhanced functionality for model capabilities
func get_capabilities() -> Dictionary:
	return {
		"streaming": false,
		"max_tokens": max_tokens,
		"supports_system_prompt": true,
		"supports_functions": false,
		"supports_vision": false,
		"supports_embeddings": supports_embeddings(),
		"provider": provider,
		"base_url": base_url
	}

# Settings validation
func validate_settings(settings: Dictionary) -> Dictionary:
	var errors = {}
	
	if settings.has("max_tokens"):
		if settings.max_tokens > max_tokens:
			errors["max_tokens"] = "Exceeds maximum allowed tokens (%d)" % max_tokens
		elif settings.max_tokens < 1:
			errors["max_tokens"] = "Must be greater than 0"
			
	if settings.has("temperature"):
		if settings.temperature < 0.0 or settings.temperature > 1.0:
			errors["temperature"] = "Must be between 0.0 and 1.0"
			
	return errors

# Helper method to check if the model is properly configured
func is_configured() -> bool:
	return not (model_name.is_empty() or provider.is_empty() or base_url.is_empty())
