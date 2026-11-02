## Purpose: AIModelService (script)
@tool
extends "res://addons/syntree/scripts/base/base_service.gd"

class_name AIModelService

# Constants
const DEFAULT_MODEL = ""
const DEFAULT_SETTINGS = {
	"temperature": 0.7,
	"max_tokens": 2000,
	"top_p": 1.0,
	"frequency_penalty": 0.0,
	"presence_penalty": 0.0
}

# Services
var api_service: APIService
var ai_model_manager: AIModelManager

# State
var _current_model: String = DEFAULT_MODEL
var _model_settings: Dictionary = {}
var _available_models: Array[String] = []
var _last_completion_time: int = 0
var _completion_count: int = 0

# Signals
signal model_changed(model_name: String)
signal settings_updated(model_name: String, settings: Dictionary)
signal completion_started(model: String)
signal completion_completed(model: String, success: bool)
signal completion_failed(model: String, error: String)

func _init() -> void:
	super._init()
	require_services(["api_service", "ai_model_manager"])

func _setup() -> bool:
	api_service = get_service("api_service")
	ai_model_manager = get_service("ai_model_manager")
	
	if not api_service or not ai_model_manager:
		push_error("AIModelService: Required services not found")
		return false
	
	# Initialize model settings
	_available_models = ai_model_manager.get_available_models()
	for model in _available_models:
		_model_settings[model] = DEFAULT_SETTINGS.duplicate()
	
	# Connect to API service signals
	api_service.request_failed.connect(_on_api_request_failed)
	
	return true

func get_service_name() -> String:
	return "ai_model_service"

func _ensure_ready() -> bool:
	if not _is_ready:
		push_error("AIModelService: Service not ready")
		return false
	return true

func chat_completion(messages: Array, model: String = "", settings: Dictionary = {}) -> String:
	if not _ensure_ready():
		return "Error: Service not ready"
	
	var current_model = model if not model.is_empty() else _current_model
	if not _available_models.has(current_model):
		push_error("Invalid model: " + current_model)
		return "Error: Invalid model"
	
	var model_settings = settings if not settings.is_empty() else get_model_settings(current_model)
	
	_last_completion_time = Time.get_ticks_msec()
	_completion_count += 1
	completion_started.emit(current_model)
	
	var content = await api_service.chat_completion(current_model, messages, model_settings)
	
	if not content.begins_with("Error:"):
		completion_completed.emit(current_model, true)
	else:
		completion_failed.emit(current_model, content)
	
	return content

func set_current_model(model_name: String) -> bool:
	if not _ensure_ready():
		return false
		
	if not _available_models.has(model_name):
		push_error("Invalid model: " + model_name)
		return false
	
	_current_model = model_name
	model_changed.emit(_current_model)
	return true

func get_current_model() -> String:
	return _current_model

func update_model_settings(model_name: String, settings: Dictionary) -> bool:
	if not _ensure_ready():
		return false
		
	if not _available_models.has(model_name):
		push_error("Invalid model: " + model_name)
		return false
	
	_model_settings[model_name].merge(settings)
	settings_updated.emit(model_name, _model_settings[model_name])
	return true

func get_model_settings(model_name: String = "") -> Dictionary:
	if not _ensure_ready():
		return {}
		
	var target_model = model_name if not model_name.is_empty() else _current_model
	if not _model_settings.has(target_model):
		return DEFAULT_SETTINGS.duplicate()
	
	return _model_settings[target_model].duplicate()

func get_available_models() -> Array[String]:
	return _available_models.duplicate()

func get_last_completion_time() -> int:
	return _last_completion_time

func get_completion_count() -> int:
	return _completion_count

func _on_api_request_failed(_endpoint: String, error: AIError) -> void:
	# Handle API errors for the current model
	completion_failed.emit(_current_model, error.user_message) 
