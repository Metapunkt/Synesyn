## Purpose: AIModelManager (script)
@tool
extends Node
class_name AIModelManager

const DEFAULT_MODEL = ""  # Changed from "gpt-3.5-turbo" to empty - will use first available model
# Preload new loaders
const OpenAIModelLoader = preload("res://addons/syntree/scripts/services/ai/ai_model_loaders/openai_model.gd")
const AnthropicModelLoader = preload("res://addons/syntree/scripts/services/ai/ai_model_loaders/anthropic_model.gd")
const OllamaModelLoader = preload("res://addons/syntree/scripts/services/ai/ai_model_loaders/ollama_model.gd")
const GeminiModelLoader = preload("res://addons/syntree/scripts/services/ai/ai_model_loaders/gemini_model.gd")
const DeepseekModelLoader = preload("res://addons/syntree/scripts/services/ai/ai_model_loaders/deepseek_model.gd")
const XAIModelLoader = preload("res://addons/syntree/scripts/services/ai/ai_model_loaders/xai_model.gd")
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")
const DEFAULT_OLLAMA_BASE_URL: String = "http://127.0.0.1:11434"

# Signals
signal model_changed(model_name: String)
signal provider_registered(provider_name: String)
signal provider_removed(provider_name: String)
signal operation_failed(operation: String, error: String)
signal models_changed(models: Array[String])
signal provider_status_changed(provider_name: String, status: Dictionary)
signal inference_metrics_updated(model_name: String, metrics: Dictionary)

# State
var _current_model: String = DEFAULT_MODEL
var _available_models: Array = []
var _model_settings: Dictionary = {}
var _model_loaders: Dictionary = {}  # provider -> BaseAIModelLoader
var _config_manager = null
var _api_service = null  # Reference to API service
var _last_inference_metrics: Dictionary = {}
var _provider_status: Dictionary = {}
var _ollama_base_url: String = DEFAULT_OLLAMA_BASE_URL
var _ollama_refresh_on_startup: bool = true
# Last model the user explicitly selected, persisted across project reloads via
# runtime config (apps.syntree.selected_model). Restored once at startup (or on
# the first async model rebuild where it becomes available); an explicit user
# selection during the session overrides it.
var _persisted_selected_model: String = ""
var _persisted_model_restored: bool = false

func setup(api_keys: Dictionary = {}, p_config_manager = null) -> Dictionary:
	_config_manager = p_config_manager
	_load_ollama_runtime_settings()
	# Seed the current model from the persisted selection so it survives project
	# reloads. The validity check below keeps it if still available, otherwise it
	# falls through to auto-selection and is retried after async model discovery.
	if _current_model.is_empty() and not _persisted_selected_model.is_empty():
		_current_model = _persisted_selected_model
	
	# --- Register All Providers ---
	var providers_to_register = {
		"anthropic": AnthropicModelLoader,
		"ollama": OllamaModelLoader,
		"openai": OpenAIModelLoader,
		"google": GeminiModelLoader,
		"deepseek": DeepseekModelLoader,
		"xai": XAIModelLoader,
	}
	
	_available_models.clear()
	
	for provider_name in providers_to_register:
		var LoaderClass = providers_to_register[provider_name]
		var loader = LoaderClass.new()
		if (
			provider_name == "ollama"
			and loader.has_method("set_base_origin")
		):
			loader.call("set_base_origin", _ollama_base_url)
		
		# Set API key if found in config/passed keys
		# Provider names in config should match keys here (lowercase)
		var key = api_keys.get(provider_name, "")
		if key.is_empty() and _config_manager: # Fallback to config manager if not passed directly
			key = _config_manager.get_api_key(provider_name)
			
		if not key.is_empty():
			loader.api_key = key
			print("AIModelManager: Found API key for provider: ", provider_name)
		
		var result = register_provider(provider_name, loader)
		if not result.success:
			push_warning("Failed to register %s provider: %s" % [provider_name, result.error])
			continue # Skip adding models if registration failed
		
		var provider_models: Array = _get_models_for_loader(loader)
		if not provider_models.is_empty():
			_available_models.append_array(provider_models)
		else:
			push_warning("Loader for %s returned no available models." % provider_name)

	print("AIModelManager: Setup complete. All available models: ", _available_models)
	
	# Ensure we have a valid current model after loading all models
	if _current_model.is_empty() or not _current_model in _available_models:
		if not _available_models.is_empty():
			var best_model = ""

			# First priority: Anthropic model with a valid API key (best quality)
			for model_candidate in _available_models:
				var prov: String = get_provider_for_model(model_candidate)
				if prov == "anthropic":
					var validation: Dictionary = validate_api_key_for_model(model_candidate)
					if validation.valid:
						best_model = model_candidate
						print("AIModelManager: Selected Anthropic model (key present): ", best_model)
						break

			# Second priority: Ollama models (no API key needed, local)
			if best_model.is_empty():
				for model_candidate in _available_models:
					if get_provider_for_model(model_candidate) == "ollama":
						best_model = model_candidate
						print("AIModelManager: Selected Ollama model (no API key required): ", best_model)
						break

			# Third priority: Any model with a valid API key
			if best_model.is_empty():
				for model_candidate in _available_models:
					var validation: Dictionary = validate_api_key_for_model(model_candidate)
					if validation.valid:
						best_model = model_candidate
						print("AIModelManager: Selected model with valid API key: ", best_model)
						break

			# Fallback: First available model
			if best_model.is_empty():
				best_model = _available_models[0]
				print("AIModelManager: No valid models found, using first available: ", best_model)
				var validation: Dictionary = validate_api_key_for_model(best_model)
				if not validation.valid:
					print("AIModelManager: WARNING - Selected model may not work: ", validation.error)

			_current_model = best_model
		else:
			print("AIModelManager: WARNING - No models available!")
			_current_model = ""
	else:
		print("AIModelManager: Keeping existing valid model: ", _current_model)

	# Track whether the persisted selection was honoured so async model rebuilds
	# know whether to attempt restoration (an explicit user choice sets this too).
	_persisted_model_restored = (
		not _persisted_selected_model.is_empty()
		and _current_model == _persisted_selected_model
	)

	return {"success": true, "error": ""}

func get_current_model() -> String:
	return _current_model

func get_available_models() -> Array:
	return _available_models

func set_current_model(model_name: String) -> Dictionary:
	print("AIModelManager: Attempting to set model. Received: '%s', Current: '%s'" % [model_name, _current_model]) # DEBUG
	if not model_name in _available_models:
		print("DEBUG: AI Model Manager - Invalid model name: ", model_name)
		operation_failed.emit("model_selection", "Invalid model name: " + model_name)
		return {"success": false, "error": "Invalid model name: " + model_name}
		
	# Check if provider has API key
	var provider = get_provider_for_model(model_name)
	var loader = get_provider_loader(provider)
	if not loader:
		print("DEBUG: AI Model Manager - Provider not found for model: ", model_name)
		operation_failed.emit("model_selection", "Provider not found for model: " + model_name)
		return {"success": false, "error": "Provider not found for model: " + model_name}
		
	# Skip API key check for Ollama provider
	if provider != "ollama": 
		if loader.api_key.is_empty():
			print("DEBUG: AI Model Manager - API key required for ", provider)
			operation_failed.emit("model_selection", "API key required for " + provider.capitalize() + " models")
			return {"success": false, "error": "API key required for " + provider.capitalize() + " models"}
		
	var previous_model: String = _current_model
	var previous_provider: String = get_provider_for_model(previous_model)
	_current_model = model_name
	print("AIModelManager: Model successfully set. Current: '%s'" % _current_model) # DEBUG
	
	# --- ADDED: Update the loader's internal model name --- 
	if loader and loader.has_method("set_model"):
		if not loader.set_model(model_name):
			push_warning("AIModelManager: Loader failed to set model internally: " + model_name)
			# Optionally return error, but might be okay if _current_model is set
	else:
		push_warning("AIModelManager: Loader missing set_model method for: " + provider)
	# --- END ADDED ---

	# Update API service error handler provider
	if _api_service:
		_api_service.update_error_handler_provider(provider)
		if (
			previous_provider == "ollama"
			and previous_model != model_name
			and _api_service.has_method("unload_ollama_model")
		):
			_api_service.call_deferred(
				"unload_ollama_model",
				previous_model
			)

	# Persist the explicit selection so it survives project reloads, and pin the
	# restored flag so a later async model rebuild never overrides a user choice.
	_persisted_selected_model = model_name
	_persisted_model_restored = true
	_persist_selected_model(model_name)

	model_changed.emit(model_name)
	return {"success": true, "error": ""}

func register_provider(provider_name: String, loader: BaseAIModelLoader) -> Dictionary:
	if provider_name in _model_loaders:
		return {"success": false, "error": "Provider already registered"}
	
	_model_loaders[provider_name] = loader
	provider_registered.emit(provider_name)
	return {"success": true, "error": ""}

func _get_models_for_loader(loader: BaseAIModelLoader) -> Array:
	if not loader:
		return []
	return loader.get_available_models()

func get_provider_loader(provider_name: String) -> BaseAIModelLoader:
	return _model_loaders.get(provider_name)

func get_model_settings(model_name: String = "") -> Dictionary:
	if model_name.is_empty():
		model_name = _current_model
	
	# Get settings from the appropriate loader
	for loader in _model_loaders.values():
		var loader_models: Array = _get_models_for_loader(loader)
		if model_name in loader_models:
			return {
				"temperature": loader.temperature,
				"max_tokens": loader.max_tokens
			}
	
	return {}

func get_provider_for_model(model_name: String) -> String:
	for provider_name in _model_loaders:
		var loader = _model_loaders[provider_name]
		var loader_models: Array = _get_models_for_loader(loader)
		if model_name in loader_models:
			return provider_name
	# Handle Ollama's potentially custom models (if not found in standard lists)
	if _model_loaders.has("ollama"):
		# A more robust check might involve querying the Ollama API if possible,
		# but for now, assume if not found elsewhere, it *might* be an Ollama model.
		# This isn't perfect but avoids errors if a user uses a custom Ollama model name.
		print("AIModelManager: Model '%s' not found in registered lists, assuming Ollama." % model_name)
		return "ollama"
	return ""

func get_api_key(provider_name: String) -> String:
	var loader = get_provider_loader(provider_name)
	if loader:
		return loader.api_key
	return ""

func set_api_service(api_service: Node) -> void:
	_api_service = api_service
	if not is_instance_valid(_api_service):
		return
	if _api_service.has_signal("inference_metrics_updated"):
		var metrics_signal := Signal(
			_api_service,
			"inference_metrics_updated"
		)
		if not metrics_signal.is_connected(_on_inference_metrics_updated):
			metrics_signal.connect(_on_inference_metrics_updated)
	if _api_service.has_method("set_ollama_base_url"):
		_api_service.call("set_ollama_base_url", _ollama_base_url)
	if _ollama_refresh_on_startup:
		call_deferred("_refresh_ollama_models_async")


func refresh_ollama_models() -> Dictionary:
	if (
		not is_instance_valid(_api_service)
		or not _api_service.has_method("refresh_ollama_models")
	):
		return {"success": false, "error": "api_service_unavailable"}
	var result: Dictionary = await _api_service.call(
		"refresh_ollama_models"
	)
	if not bool(result.get("success", false)):
		_provider_status["ollama"] = result.duplicate(true)
		provider_status_changed.emit("ollama", result.duplicate(true))
		return result
	var loader: BaseAIModelLoader = get_provider_loader("ollama")
	if not loader or not loader.has_method("set_discovered_models"):
		return {"success": false, "error": "ollama_loader_unavailable"}
	var model_ids: Array[String] = []
	var models_any: Variant = result.get("models", [])
	if typeof(models_any) == TYPE_ARRAY:
		for model_any: Variant in models_any:
			var model_id: String = String(model_any).strip_edges()
			if not model_id.is_empty():
				model_ids.append(model_id)
	var metadata_any: Variant = result.get("metadata", {})
	var metadata: Dictionary = (
		metadata_any if typeof(metadata_any) == TYPE_DICTIONARY else {}
	)
	await _inspect_ollama_models(model_ids, metadata)
	loader.call("set_discovered_models", model_ids, metadata)
	_rebuild_available_models()
	if _api_service.has_method("get_running_ollama_models"):
		var running_result: Dictionary = await _api_service.call(
			"get_running_ollama_models"
		)
		if bool(running_result.get("success", false)):
			result["running_models"] = running_result.get("models", [])
	result["metadata"] = metadata
	result["available"] = true
	_provider_status["ollama"] = result.duplicate(true)
	provider_status_changed.emit("ollama", result.duplicate(true))
	models_changed.emit(_typed_model_list())
	return result


func get_model_metadata(model_name: String = "") -> Dictionary:
	var resolved_model: String = (
		model_name.strip_edges()
		if not model_name.is_empty()
		else _current_model
	)
	var provider_id: String = get_provider_for_model(resolved_model)
	var loader: BaseAIModelLoader = get_provider_loader(provider_id)
	if loader and loader.has_method("get_model_metadata"):
		return loader.call("get_model_metadata", resolved_model)
	return {}


func get_last_inference_metrics() -> Dictionary:
	return _last_inference_metrics.duplicate(true)


func get_provider_status(provider_name: String) -> Dictionary:
	var status_any: Variant = _provider_status.get(provider_name, {})
	return (
		status_any.duplicate(true)
		if typeof(status_any) == TYPE_DICTIONARY
		else {}
	)


func get_ollama_base_url() -> String:
	return _ollama_base_url


func set_ollama_base_url(origin_url: String) -> Dictionary:
	var normalized: String = origin_url.strip_edges().trim_suffix("/")
	normalized = normalized.trim_suffix("/api/chat")
	if not (
		normalized.begins_with("http://")
		or normalized.begins_with("https://")
	):
		return {"success": false, "error": "invalid_ollama_base_url"}
	var loader: BaseAIModelLoader = get_provider_loader("ollama")
	if (
		not loader
		or not loader.has_method("set_base_origin")
		or not bool(loader.call("set_base_origin", normalized))
	):
		return {"success": false, "error": "invalid_ollama_base_url"}
	if (
		is_instance_valid(_api_service)
		and _api_service.has_method("set_ollama_base_url")
	):
		var api_result: Dictionary = _api_service.call(
			"set_ollama_base_url",
			normalized
		)
		if not bool(api_result.get("success", false)):
			return api_result
	_ollama_base_url = normalized
	_save_ollama_runtime_settings()
	call_deferred("_refresh_ollama_models_async")
	return {"success": true, "base_url": _ollama_base_url}

func set_api_key(provider_name: String, api_key: String) -> Dictionary:
	var loader = get_provider_loader(provider_name.to_lower())
	if not loader:
		print("DEBUG: AI Model Manager - Provider not found: ", provider_name)
		operation_failed.emit("set_api_key", "Provider not found: " + provider_name.capitalize())
		return {"success": false, "error": "Provider not found: " + provider_name.capitalize()}
		
	# Don't allow empty API keys
	if api_key.strip_edges().is_empty():
		print("DEBUG: AI Model Manager - Empty API key")
		operation_failed.emit("set_api_key", provider_name.capitalize() + " API key cannot be empty")
		return {"success": false, "error": provider_name.capitalize() + " API key cannot be empty"}
		
	# Set API key in loader
	loader.api_key = api_key.strip_edges()
	# Modify debug print to hide the actual key
	print("AIModelManager: Set key in loader '%s' for provider '%s'. Loader key set: %s" % [loader.get_class(), provider_name, str(not loader.api_key.is_empty())]) # DEBUG
	
	# Save to config
	if _config_manager:
		_config_manager.set_api_key(provider_name.to_lower(), api_key.strip_edges())
	else:
		print("DEBUG: AI Model Manager - Config manager not available")
		operation_failed.emit("set_api_key", "Config manager not available")
		return {"success": false, "error": "Config manager not available"}
	
	return {"success": true, "error": ""}

# Add validation helper
func validate_api_key_for_model(model_name: String) -> Dictionary:
	var provider = get_provider_for_model(model_name)
	if provider.is_empty():
		return {"valid": false, "error": "Provider not found for model: " + model_name}
		
	var loader = get_provider_loader(provider)
	if not loader:
		return {"valid": false, "error": "Loader not found for provider: " + provider}
		
	# Skip API key check for Ollama provider
	if provider != "ollama":
		if loader.api_key.is_empty():
			return {"valid": false, "error": "API key required for " + provider + " models"}
		
	return {"valid": true, "error": ""}


func _refresh_ollama_models_async() -> void:
	await refresh_ollama_models()


func _inspect_ollama_models(
	model_ids: Array[String],
	metadata: Dictionary
) -> void:
	if not _api_service.has_method("inspect_ollama_model"):
		return
	for model_id: String in model_ids:
		var inspection: Dictionary = await _api_service.call(
			"inspect_ollama_model",
			model_id
		)
		if not bool(inspection.get("success", false)):
			continue
		var current_any: Variant = metadata.get(model_id, {})
		var current_metadata: Dictionary = (
			current_any.duplicate(true)
			if typeof(current_any) == TYPE_DICTIONARY
			else {}
		)
		current_metadata["context_length"] = int(
			inspection.get("context_length", 0)
		)
		current_metadata["capabilities"] = inspection.get(
			"capabilities",
			[]
		)
		metadata[model_id] = current_metadata


func _rebuild_available_models() -> void:
	_available_models.clear()
	for loader_any: Variant in _model_loaders.values():
		var loader: BaseAIModelLoader = loader_any
		_available_models.append_array(_get_models_for_loader(loader))
	if (
		not _current_model.is_empty()
		and not _available_models.has(_current_model)
	):
		var ollama_loader: BaseAIModelLoader = get_provider_loader("ollama")
		var ollama_models: Array = _get_models_for_loader(ollama_loader)
		if not ollama_models.is_empty():
			var replacement_model: String = ""
			for candidate_any: Variant in ollama_models:
				var candidate_model: String = String(candidate_any)
				if candidate_model.get_slice(":", 0) == (
					_current_model.get_slice(":", 0)
				):
					replacement_model = candidate_model
					break
			_current_model = (
				replacement_model
				if not replacement_model.is_empty()
				else String(ollama_models[0])
			)
			ollama_loader.set_model(_current_model)
			model_changed.emit(_current_model)

	# Async model discovery (e.g. Ollama refresh) may make the persisted selection
	# available only now. Restore it once, going through set_current_model so the
	# loader is synced and validation runs. An explicit user choice already set
	# _persisted_model_restored=true, so this never overrides a session-time change.
	if (
		not _persisted_model_restored
		and not _persisted_selected_model.is_empty()
		and _persisted_selected_model in _available_models
	):
		set_current_model(_persisted_selected_model)


func _typed_model_list() -> Array[String]:
	var model_ids: Array[String] = []
	for model_any: Variant in _available_models:
		model_ids.append(String(model_any))
	return model_ids


func _on_inference_metrics_updated(
	model_name: String,
	metrics: Dictionary
) -> void:
	_last_inference_metrics = metrics.duplicate(true)
	inference_metrics_updated.emit(
		model_name,
		_last_inference_metrics.duplicate(true)
	)


func _load_ollama_runtime_settings() -> void:
	var runtime_config: Dictionary = RuntimeConfigScript.load_config()
	var apps_any: Variant = runtime_config.get("apps", {})
	if typeof(apps_any) != TYPE_DICTIONARY:
		return
	var syntree_any: Variant = (apps_any as Dictionary).get("syntree", {})
	if typeof(syntree_any) != TYPE_DICTIONARY:
		return
	var syntree_config: Dictionary = syntree_any
	_ollama_base_url = String(
		syntree_config.get(
			"ollama_base_url",
			DEFAULT_OLLAMA_BASE_URL
		)
	).strip_edges().trim_suffix("/")
	_ollama_refresh_on_startup = bool(
		syntree_config.get("ollama_refresh_on_startup", true)
	)
	_persisted_selected_model = String(
		syntree_config.get("selected_model", "")
	).strip_edges()


func _save_ollama_runtime_settings() -> void:
	var runtime_config: Dictionary = RuntimeConfigScript.load_config()
	var apps_any: Variant = runtime_config.get("apps", {})
	var apps_config: Dictionary = (
		apps_any.duplicate(true)
		if typeof(apps_any) == TYPE_DICTIONARY
		else {}
	)
	var syntree_any: Variant = apps_config.get("syntree", {})
	var syntree_config: Dictionary = (
		syntree_any.duplicate(true)
		if typeof(syntree_any) == TYPE_DICTIONARY
		else {}
	)
	syntree_config["ollama_base_url"] = _ollama_base_url
	syntree_config["ollama_refresh_on_startup"] = (
		_ollama_refresh_on_startup
	)
	apps_config["syntree"] = syntree_config
	runtime_config["apps"] = apps_config
	RuntimeConfigScript.save_config(runtime_config)


## Persists the user's explicit model selection under apps.syntree.selected_model
## so it is restored on the next project load. Mirrors the Ollama runtime settings
## persistence pattern; non-blocking best-effort (save_config returns bool).
func _persist_selected_model(model_name: String) -> void:
	var runtime_config: Dictionary = RuntimeConfigScript.load_config()
	var apps_any: Variant = runtime_config.get("apps", {})
	var apps_config: Dictionary = (
		apps_any.duplicate(true)
		if typeof(apps_any) == TYPE_DICTIONARY
		else {}
	)
	var syntree_any: Variant = apps_config.get("syntree", {})
	var syntree_config: Dictionary = (
		syntree_any.duplicate(true)
		if typeof(syntree_any) == TYPE_DICTIONARY
		else {}
	)
	syntree_config["selected_model"] = model_name
	apps_config["syntree"] = syntree_config
	runtime_config["apps"] = apps_config
	RuntimeConfigScript.save_config(runtime_config)
