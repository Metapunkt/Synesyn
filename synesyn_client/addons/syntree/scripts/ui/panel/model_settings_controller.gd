## Purpose: Panel controller for Model/Provider settings (model selector, provider selector, API key input)
@tool
extends Node
class_name ModelSettingsController

var _ai_model_manager: Object = null

var _ai_model_selector: OptionButton = null
var _api_provider_selector: OptionButton = null
var _api_key_input: LineEdit = null
var _ollama_status_label: Label = null
var _ollama_endpoint_input: LineEdit = null

var _show_error_cb: Callable = Callable() # expects (title:String, message:String)
var _emit_operation_failed_cb: Callable = Callable() # expects (operation:String, error:String, details:String)

const PROVIDERS_WITH_KEYS := {
	"openai": "OpenAI",
	"anthropic": "Anthropic",
	"google": "Google",
	"deepseek": "Deepseek",
	"xai": "xAI",
}

var _desired_default_model: String = "gemma4:26b"
## Model the user tried to select before an API key was available; applied after key save.
var _pending_model_after_key: String = ""

func setup(
		ai_model_manager: Object,
		ai_model_selector: OptionButton,
		api_provider_selector: OptionButton,
		api_key_input: LineEdit,
		ollama_status_label: Label,
		ollama_endpoint_input: LineEdit,
		show_error_cb: Callable,
		emit_operation_failed_cb: Callable,
		desired_default_model: String = "gemma4:26b"
	) -> void:
	_ai_model_manager = ai_model_manager
	_ai_model_selector = ai_model_selector
	_api_provider_selector = api_provider_selector
	_api_key_input = api_key_input
	_ollama_status_label = ollama_status_label
	_ollama_endpoint_input = ollama_endpoint_input
	_show_error_cb = show_error_cb
	_emit_operation_failed_cb = emit_operation_failed_cb
	_desired_default_model = String(desired_default_model).strip_edges()
	if _desired_default_model.is_empty():
		_desired_default_model = "gemma4:26b"
	update_ollama_status(
		"ollama",
		{"success": false, "error": "checking"}
	)
	# Bootstrap can call setup before PluginManager has created AIModelManager.
	if not is_instance_valid(_ai_model_manager):
		return
	if _ai_model_manager.has_method("get_provider_status"):
		var provider_status: Dictionary = (
			_ai_model_manager.get_provider_status("ollama")
		)
		if not provider_status.is_empty():
			update_ollama_status("ollama", provider_status)
	if _ai_model_manager.has_method("get_last_inference_metrics"):
		var metrics: Dictionary = (
			_ai_model_manager.get_last_inference_metrics()
		)
		if not metrics.is_empty():
			update_inference_metrics(
				String(metrics.get("model_id", "")),
				metrics
			)
	if (
		is_instance_valid(_ollama_endpoint_input)
		and _ai_model_manager.has_method("get_ollama_base_url")
	):
		_ollama_endpoint_input.text = String(
			_ai_model_manager.get_ollama_base_url()
		)

func populate_provider_selector() -> void:
	if not is_instance_valid(_api_provider_selector):
		return
	_api_provider_selector.clear()
	var provider_order := ["openai", "anthropic", "google", "deepseek", "xai"]
	var id_counter := 0
	for provider_key in provider_order:
		if not PROVIDERS_WITH_KEYS.has(provider_key):
			continue
		var display_name: String = PROVIDERS_WITH_KEYS[provider_key]
		_api_provider_selector.add_item(display_name, id_counter)
		var idx := _api_provider_selector.item_count - 1
		_api_provider_selector.set_item_metadata(idx, provider_key)
		id_counter += 1
	# Add Ollama
	_api_provider_selector.add_item("Ollama", id_counter)
	_api_provider_selector.set_item_metadata(_api_provider_selector.item_count - 1, "ollama")
	id_counter += 1

	# Select first provider by default, and sync key field if possible.
	if _api_provider_selector.item_count > 0:
		_select_provider_by_key(String(_api_provider_selector.get_item_metadata(0)))

func populate_model_selector(_ignored_models: Variant = null) -> void:
	if not is_instance_valid(_ai_model_selector):
		return
	if not is_instance_valid(_ai_model_manager):
		_ai_model_selector.disabled = true
		_ai_model_selector.clear()
		_ai_model_selector.add_item("No Models Available")
		return

	var available_models: Array = []
	if _ai_model_manager.has_method("get_available_models"):
		available_models = _ai_model_manager.get_available_models()

	_ai_model_selector.clear()
	if available_models.is_empty():
		_ai_model_selector.add_item("No Models Found")
		_ai_model_selector.disabled = true
		return
	_ai_model_selector.disabled = false

	# Group models by provider.
	var grouped: Dictionary = {}
	for model_name_any in available_models:
		var model_name := str(model_name_any)
		var provider_id := ""
		if _ai_model_manager.has_method("get_provider_for_model"):
			provider_id = str(_ai_model_manager.get_provider_for_model(model_name))
		if provider_id.is_empty():
			provider_id = "unknown"
		if not grouped.has(provider_id):
			grouped[provider_id] = []
		(grouped[provider_id] as Array).append(model_name)
		(grouped[provider_id] as Array).sort()

	var provider_order := ["openai", "anthropic", "google", "deepseek", "xai", "ollama"]
	var provider_display_names := PROVIDERS_WITH_KEYS.duplicate()
	provider_display_names["ollama"] = "Ollama"
	provider_display_names["unknown"] = "Unknown Provider"

	var item_index := 0
	for provider_key in provider_order:
		if grouped.has(provider_key) and not (grouped[provider_key] as Array).is_empty():
			var display_name := str(provider_display_names.get(provider_key, String(provider_key).capitalize()))
			_ai_model_selector.add_item("-- %s --" % display_name, item_index)
			_ai_model_selector.set_item_disabled(item_index, true)
			_ai_model_selector.set_item_metadata(item_index, null)
			item_index += 1
			for model_name in (grouped[provider_key] as Array):
				var is_embed_capable := _check_embedding_support(provider_key, model_name)
				var display_text: String = model_name
				var model_status_suffix := _build_model_status_suffix(model_name)
				if not model_status_suffix.is_empty():
					display_text += model_status_suffix
				if is_embed_capable:
					display_text += "  [embed]"
				_ai_model_selector.add_item(display_text, item_index)
				_ai_model_selector.set_item_metadata(item_index, model_name)
				_ai_model_selector.set_item_tooltip(
					item_index,
					_build_model_tooltip(model_name)
				)
				item_index += 1

	if grouped.has("unknown") and not (grouped["unknown"] as Array).is_empty():
		_ai_model_selector.add_item("-- %s --" % str(provider_display_names["unknown"]), item_index)
		_ai_model_selector.set_item_disabled(item_index, true)
		_ai_model_selector.set_item_metadata(item_index, null)
		item_index += 1
		for model_name in (grouped["unknown"] as Array):
			_ai_model_selector.add_item(model_name, item_index)
			_ai_model_selector.set_item_metadata(item_index, model_name)
			item_index += 1

	# Choose model (manager current → desired default → first selectable).
	var current_model := ""
	if _ai_model_manager.has_method("get_current_model"):
		current_model = str(_ai_model_manager.get_current_model())
	var model_to_set := ""
	var selected_index := -1

	if not current_model.is_empty():
		for i in range(_ai_model_selector.item_count):
			var meta := _ai_model_selector.get_item_metadata(i)
			if meta is String and meta == current_model:
				selected_index = i
				model_to_set = current_model
				break

	if selected_index == -1 and current_model.is_empty() and not _desired_default_model.is_empty():
		for i in range(_ai_model_selector.item_count):
			var meta := _ai_model_selector.get_item_metadata(i)
			if meta is String and meta == _desired_default_model:
				selected_index = i
				model_to_set = _desired_default_model
				break

	if selected_index == -1:
		for i in range(_ai_model_selector.item_count):
			if not _ai_model_selector.is_item_disabled(i):
				var meta := _ai_model_selector.get_item_metadata(i)
				if meta is String:
					selected_index = i
					model_to_set = meta
					break

	if selected_index != -1:
		_select_model_index_no_signal(selected_index)
		if not model_to_set.is_empty() and model_to_set != current_model and _ai_model_manager.has_method("set_current_model"):
			var set_result: Dictionary = _ai_model_manager.set_current_model(model_to_set)
			if not bool(set_result.get("success", false)):
				if _show_error_cb.is_valid():
					_show_error_cb.call("Model Selection Error", "Failed to set model '%s': %s" % [model_to_set, str(set_result.get("error", ""))])
				# Revert UI to manager’s model if available.
				sync_ui_from_manager()

	# Sync provider selector for the chosen model.
	sync_provider_selector_from_current_model()

func on_model_selected(index: int) -> void:
	if not is_instance_valid(_ai_model_selector) or not is_instance_valid(_ai_model_manager):
		return
	var model_any: Variant = _ai_model_selector.get_item_metadata(index)
	if not (model_any is String):
		# Likely header. Revert to current model.
		sync_ui_from_manager()
		return
	var model_name := str(model_any)

	# Sync provider selector + api key field.
	sync_provider_selector_from_model(model_name)

	# Validate API key for this model before switching.
	if _ai_model_manager.has_method("validate_api_key_for_model"):
		var validation: Dictionary = _ai_model_manager.validate_api_key_for_model(model_name)
		if not bool(validation.get("valid", true)):
			_pending_model_after_key = model_name
			var provider_name := "this provider"
			var provider_id := ""
			if _ai_model_manager.has_method("get_provider_for_model"):
				provider_id = str(_ai_model_manager.get_provider_for_model(model_name)).strip_edges()
				if PROVIDERS_WITH_KEYS.has(provider_id):
					provider_name = str(PROVIDERS_WITH_KEYS[provider_id])
				elif provider_id == "ollama":
					provider_name = "Ollama"
				elif not provider_id.is_empty():
					provider_name = provider_id.capitalize()
			# Keep provider + API key field on the target provider; only revert the model dropdown.
			if not provider_id.is_empty():
				_select_provider_by_key(provider_id)
			sync_model_selector_from_current_model()
			if is_instance_valid(_api_key_input):
				_api_key_input.visible = true
				_api_key_input.editable = true
				_api_key_input.grab_focus()
			if _show_error_cb.is_valid():
				_show_error_cb.call(
					"API Key Required",
					"%s is supported, but %s needs an API key before it can be selected.\n\nUse the Provider / API key row in SynTree: paste your %s key, then click Save. SynTree will select %s automatically once the key is saved.\n\nOr choose an Ollama model for local use." % [model_name, provider_name, provider_name, model_name]
				)
			return

	_pending_model_after_key = ""
	if _ai_model_manager.has_method("set_current_model"):
		var res: Dictionary = _ai_model_manager.set_current_model(model_name)
		if not bool(res.get("success", false)):
			if _show_error_cb.is_valid():
				_show_error_cb.call("Model Selection Error", str(res.get("error", "Unknown error")))
			sync_ui_from_manager()

func _build_model_status_suffix(model_name: String) -> String:
	if not is_instance_valid(_ai_model_manager):
		return ""
	if not _ai_model_manager.has_method("validate_api_key_for_model"):
		return ""
	var validation: Dictionary = _ai_model_manager.validate_api_key_for_model(model_name)
	if bool(validation.get("valid", true)):
		return ""
	return "  [needs API key]"


func update_ollama_status(
	provider_name: String,
	status: Dictionary
) -> void:
	if (
		provider_name != "ollama"
		or not is_instance_valid(_ollama_status_label)
	):
		return
	if not bool(status.get("success", false)):
		var error_id: String = String(status.get("error", ""))
		_ollama_status_label.text = (
			"Checking Ollama models…"
			if error_id == "checking"
			else "Ollama unavailable — verify the configured endpoint."
		)
		return
	var models_any: Variant = status.get("models", [])
	var installed_count: int = (
		(models_any as Array).size()
		if typeof(models_any) == TYPE_ARRAY
		else 0
	)
	var running_any: Variant = status.get("running_models", [])
	var running_count: int = (
		(running_any as Array).size()
		if typeof(running_any) == TYPE_ARRAY
		else 0
	)
	_ollama_status_label.text = (
		"Ollama ready • %d installed model%s • %d loaded"
		% [
			installed_count,
			"" if installed_count == 1 else "s",
			running_count,
		]
	)


func update_inference_metrics(
	_model_name: String,
	metrics: Dictionary
) -> void:
	if not is_instance_valid(_ollama_status_label):
		return
	if String(metrics.get("provider_id", "")) != "ollama":
		return
	_ollama_status_label.text = (
		"Ollama ready • %.1f tok/s • %d prompt + %d output • %.0f ms load"
		% [
			float(metrics.get("completion_tokens_per_second", 0.0)),
			int(metrics.get("prompt_tokens", 0)),
			int(metrics.get("completion_tokens", 0)),
			float(metrics.get("load_duration_ms", 0.0)),
		]
	)


func on_apply_ollama_endpoint() -> void:
	if (
		not is_instance_valid(_ollama_endpoint_input)
		or not is_instance_valid(_ai_model_manager)
		or not _ai_model_manager.has_method("set_ollama_base_url")
	):
		return
	var result: Dictionary = _ai_model_manager.set_ollama_base_url(
		_ollama_endpoint_input.text
	)
	if not bool(result.get("success", false)):
		if _show_error_cb.is_valid():
			_show_error_cb.call(
				"Invalid Ollama URL",
				"Enter an HTTP or HTTPS origin, for example "
				+ "http://127.0.0.1:11434."
			)
		return
	_ollama_endpoint_input.text = String(
		result.get("base_url", _ollama_endpoint_input.text)
	)
	update_ollama_status(
		"ollama",
		{"success": false, "error": "checking"}
	)


func on_refresh_ollama_models() -> void:
	if (
		not is_instance_valid(_ai_model_manager)
		or not _ai_model_manager.has_method("refresh_ollama_models")
	):
		return
	update_ollama_status(
		"ollama",
		{"success": false, "error": "checking"}
	)
	await _ai_model_manager.refresh_ollama_models()


func _build_model_tooltip(model_name: String) -> String:
	if (
		not is_instance_valid(_ai_model_manager)
		or not _ai_model_manager.has_method("get_model_metadata")
	):
		return model_name
	var metadata: Dictionary = _ai_model_manager.get_model_metadata(
		model_name
	)
	if metadata.is_empty():
		return model_name
	var parts: Array[String] = [model_name]
	var parameter_size: String = String(
		metadata.get("parameter_size", "")
	)
	var quantization: String = String(
		metadata.get("quantization_level", "")
	)
	var context_length: int = int(metadata.get("context_length", 0))
	if not parameter_size.is_empty():
		parts.append("Parameters: " + parameter_size)
	if not quantization.is_empty():
		parts.append("Quantization: " + quantization)
	if context_length > 0:
		parts.append("Context limit: %d tokens" % context_length)
	return "\n".join(parts)

func on_api_provider_selected(index: int) -> void:
	if not is_instance_valid(_api_provider_selector):
		return
	var provider_any: Variant = _api_provider_selector.get_item_metadata(index)
	if provider_any is String:
		_update_api_key_field(str(provider_any))

func on_api_key_changed(new_text: String = "") -> void:
	if not is_instance_valid(_ai_model_manager) or not is_instance_valid(_api_provider_selector):
		return
	var selected_provider_index := int(_api_provider_selector.selected)
	if selected_provider_index < 0:
		return
	var provider_any: Variant = _api_provider_selector.get_item_metadata(selected_provider_index)
	if not (provider_any is String):
		if _emit_operation_failed_cb.is_valid():
			_emit_operation_failed_cb.call("set_api_key", "Internal UI Error", "")
		return
	var provider_key := str(provider_any)
	if _ai_model_manager.has_method("set_api_key"):
		var res: Dictionary = _ai_model_manager.set_api_key(provider_key, new_text)
		if not bool(res.get("success", true)):
			if _emit_operation_failed_cb.is_valid():
				_emit_operation_failed_cb.call("set_api_key", str(res.get("error", "Failed to set API key")), str(res.get("details", "")))
			return
		_try_apply_pending_model_after_key()

func _try_apply_pending_model_after_key() -> void:
	var pending := _pending_model_after_key.strip_edges()
	if pending.is_empty() or not is_instance_valid(_ai_model_manager):
		return
	if _ai_model_manager.has_method("validate_api_key_for_model"):
		var validation: Dictionary = _ai_model_manager.validate_api_key_for_model(pending)
		if not bool(validation.get("valid", true)):
			return
	if not _ai_model_manager.has_method("set_current_model"):
		return
	var res: Dictionary = _ai_model_manager.set_current_model(pending)
	_pending_model_after_key = ""
	if bool(res.get("success", false)):
		populate_model_selector()
		sync_ui_from_manager()
	elif _show_error_cb.is_valid():
		_show_error_cb.call("Model Selection Error", str(res.get("error", "Unknown error")))
		sync_ui_from_manager()

func sync_ui_from_manager(_ignored: Variant = null) -> void:
	sync_model_selector_from_current_model()
	sync_provider_selector_from_current_model()

func sync_model_selector_from_current_model() -> void:
	if not is_instance_valid(_ai_model_manager) or not is_instance_valid(_ai_model_selector):
		return
	if not _ai_model_manager.has_method("get_current_model"):
		return
	var current_model := str(_ai_model_manager.get_current_model())
	if current_model.is_empty():
		return
	for i in range(_ai_model_selector.item_count):
		var meta := _ai_model_selector.get_item_metadata(i)
		if meta is String and meta == current_model:
			_select_model_index_no_signal(i)
			return

func sync_provider_selector_from_current_model() -> void:
	if not is_instance_valid(_ai_model_manager) or not is_instance_valid(_api_provider_selector):
		return
	if not _ai_model_manager.has_method("get_current_model") or not _ai_model_manager.has_method("get_provider_for_model"):
		return
	var current_model := str(_ai_model_manager.get_current_model())
	if current_model.is_empty():
		return
	var provider_id := str(_ai_model_manager.get_provider_for_model(current_model))
	if provider_id.is_empty():
		return
	_select_provider_by_key(provider_id)

func sync_provider_selector_from_model(model_name: String) -> void:
	if not is_instance_valid(_ai_model_manager):
		return
	if not _ai_model_manager.has_method("get_provider_for_model"):
		return
	var provider_id := str(_ai_model_manager.get_provider_for_model(model_name))
	if provider_id.is_empty():
		_clear_api_key_field()
		return
	_select_provider_by_key(provider_id)

func _select_model_index_no_signal(i: int) -> void:
	if not is_instance_valid(_ai_model_selector):
		return
	var was_connected := _ai_model_selector.item_selected.is_connected(on_model_selected)
	if was_connected:
		_ai_model_selector.item_selected.disconnect(on_model_selected)
	_ai_model_selector.select(i)
	if was_connected:
		_ai_model_selector.item_selected.connect(on_model_selected)

func _select_provider_by_key(provider_key: String) -> void:
	if not is_instance_valid(_api_provider_selector):
		return
	var key := String(provider_key).strip_edges()
	if key.is_empty():
		return
	var target_index := -1
	for i in range(_api_provider_selector.item_count):
		var meta := _api_provider_selector.get_item_metadata(i)
		if meta is String and meta == key:
			target_index = i
			break
	if target_index != -1:
		var was_connected := _api_provider_selector.item_selected.is_connected(on_api_provider_selected)
		if was_connected:
			_api_provider_selector.item_selected.disconnect(on_api_provider_selected)
		_api_provider_selector.select(target_index)
		if was_connected:
			_api_provider_selector.item_selected.connect(on_api_provider_selected)
		_update_api_key_field(key)

func _update_api_key_field(provider_key: String) -> void:
	if not is_instance_valid(_api_key_input):
		return
	var key := String(provider_key).strip_edges()
	if key.is_empty():
		return

	# If manager not ready, still update placeholder but avoid writing key value.
	var current_key := ""
	if is_instance_valid(_ai_model_manager) and _ai_model_manager.has_method("get_api_key"):
		current_key = str(_ai_model_manager.get_api_key(key))

	var was_connected := _api_key_input.text_changed.is_connected(on_api_key_changed)
	if was_connected:
		_api_key_input.text_changed.disconnect(on_api_key_changed)
	_api_key_input.text = current_key
	_api_key_input.visible = true

	if key == "ollama":
		_api_key_input.placeholder_text = "No API Key Needed for Ollama Models"
		_api_key_input.editable = false
	else:
		var provider_display_name := str(PROVIDERS_WITH_KEYS.get(key, key.capitalize()))
		_api_key_input.placeholder_text = "Enter %s API Key" % provider_display_name
		_api_key_input.editable = true

	if was_connected:
		_api_key_input.text_changed.connect(on_api_key_changed)

func _clear_api_key_field() -> void:
	if not is_instance_valid(_api_key_input):
		return
	var was_connected := _api_key_input.text_changed.is_connected(on_api_key_changed)
	if was_connected:
		_api_key_input.text_changed.disconnect(on_api_key_changed)
	_api_key_input.text = ""
	_api_key_input.placeholder_text = "API Key (Select Provider)"
	if was_connected:
		_api_key_input.text_changed.connect(on_api_key_changed)

func _check_embedding_support(provider_key: String, _model_name: String) -> bool:
	## Check if this provider supports embeddings via its model loader.
	if not is_instance_valid(_ai_model_manager):
		return false
	if not _ai_model_manager.has_method("get_provider_loader"):
		return false
	var loader: Variant = _ai_model_manager.get_provider_loader(provider_key)
	if not loader:
		return false
	if loader.has_method("supports_embeddings"):
		return loader.supports_embeddings()
	return false
