## Purpose: ModelService (script)
@tool
extends "res://addons/syntree/scripts/base/base_service.gd"

class_name ModelService

# Services
var ai_model_manager: AIModelManager

# Signals
signal model_changed(model_name: String)
signal settings_updated(model_name: String, settings: Dictionary)

func _init() -> void:
	super._init()
	require_services(["ai_model_manager"])

func _setup() -> bool:
	ai_model_manager = get_service("ai_model_manager")
	
	if not ai_model_manager:
		push_error("ModelService: Required services not found")
		return false
	
	# Connect to AIModelManager signals
	ai_model_manager.model_changed.connect(_on_model_changed)
	ai_model_manager.settings_validated.connect(_on_settings_validated)
	
	return true

func get_service_name() -> String:
	return "model_service"

func _ensure_ready() -> bool:
	if not _is_ready:
		push_error("ModelService: Service not ready")
		return false
	return true

func get_current_model() -> String:
	if not _ensure_ready():
		return ""
	return ai_model_manager.get_current_model()

func set_current_model(model_name: String) -> bool:
	if not _ensure_ready():
		return false
	
	# Check if model exists in available models
	var available_models = ai_model_manager._available_models
	if not model_name in available_models:
		push_error("ModelService: Invalid model name: " + model_name)
		return false
		
	ai_model_manager.set_current_model(model_name)
	return true

func get_model_settings() -> Dictionary:
	if not _ensure_ready():
		return {}
	return ai_model_manager.get_model_settings()

func update_model_settings(settings: Dictionary) -> bool:
	if not _ensure_ready():
		return false
		
	var current_settings = ai_model_manager.get_model_settings()
	current_settings.merge(settings)
	return true

func get_available_models() -> Array:
	if not _ensure_ready():
		return []
	return ai_model_manager._available_models.duplicate()

func get_model_capabilities() -> Dictionary:
	if not _ensure_ready():
		return {}
	var model = get_current_model()
	var settings = get_model_settings()
	return {
		"model": model,
		"settings": settings
	}

# Signal handlers
func _on_model_changed(model_name: String) -> void:
	model_changed.emit(model_name)
	
	# Update settings signal
	var settings = get_model_settings()
	settings_updated.emit(model_name, settings)

func _on_settings_validated(model_name: String, settings: Dictionary) -> void:
	settings_updated.emit(model_name, settings)
