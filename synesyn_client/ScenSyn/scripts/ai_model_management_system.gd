extends RefCounted
class_name AIModelManagementSystem

"""
AI Model Management System

This system provides:
- AI model selection and validation
- Model synchronization checking
- API key validation
- Model status monitoring
- Debug and diagnostic tools

Usage:
	var ai_model_manager = AIModelManagementSystem.new()
	ai_model_manager.initialize(conversation_manager)
	var models = ai_model_manager.get_available_models()
"""

# Signal definitions
signal model_changed(new_model: String, old_model: String)
signal model_validation_failed(model: String, error: String)
signal synchronization_status_changed(is_synchronized: bool)
signal api_key_validation_completed(model: String, is_valid: bool)

# Dependencies (injected)
var conversation_manager = null
var plugin_manager = null
var global_reference = null

# Configuration
var auto_validate_on_change = true
var sync_check_interval = 30.0  # seconds
var fallback_model_preference = ["claude-3-5-sonnet", "claude-3-sonnet", "gpt-4", "gpt-3.5-turbo"]

# Internal state
var last_sync_check_time = 0.0
var sync_status_cache = {}

func _init():
	"""Initialize the AI model management system"""
	print("AIModelManagementSystem: Initialized")

func initialize(conv_manager, plugin_mgr = null, global_ref = null):
	"""Initialize with required dependencies"""
	conversation_manager = conv_manager
	plugin_manager = plugin_mgr
	global_reference = global_ref
	print("AIModelManagementSystem: Dependencies set")

# ------------------------------------------------------------------
# PUBLIC API - CORE MODEL MANAGEMENT
# ------------------------------------------------------------------

func get_available_models() -> Array:
	"""Get list of available AI models"""
	if not _validate_dependencies():
		return []
	
	var ai_manager = conversation_manager.ai_model_manager
	if not ai_manager:
		print("AIModelManagementSystem: No AI model manager available")
		return []
	
	var available_models = ai_manager.get_available_models()
	print("AIModelManagementSystem: Available models: ", available_models)
	return available_models

func get_current_model() -> String:
	"""Get the currently selected AI model"""
	if not _validate_dependencies():
		return ""
	
	var ai_manager = conversation_manager.ai_model_manager
	if not ai_manager:
		print("AIModelManagementSystem: No AI model manager available")
		return ""
	
	var current_model = ai_manager.get_current_model()
	print("AIModelManagementSystem: Current model: ", current_model)
	return current_model

func set_model(model_name: String) -> Dictionary:
	"""Set the AI model. Returns: {"success": bool, "error": String, "previous_model": String}"""
	print("AIModelManagementSystem: Attempting to set model to: ", model_name)
	
	if not _validate_dependencies():
		return {"success": false, "error": "Dependencies not properly initialized", "previous_model": ""}
	
	var ai_manager = conversation_manager.ai_model_manager
	if not ai_manager:
		var error = "No AI model manager available"
		print("AIModelManagementSystem: ERROR - ", error)
		return {"success": false, "error": error, "previous_model": ""}
	
	# Get current model for rollback/comparison
	var previous_model = ai_manager.get_current_model()
	
	# Check if model is available
	var available_models = ai_manager.get_available_models()
	if not model_name in available_models:
		var error = "Model '%s' not available. Available models: %s" % [model_name, str(available_models)]
		print("AIModelManagementSystem: ERROR - ", error)
		return {"success": false, "error": error, "previous_model": previous_model}
	
	# Validate API key for the model if auto-validation is enabled
	if auto_validate_on_change:
		var validation = validate_api_key_for_model(model_name)
		if not validation.valid:
			var error = "API key validation failed for model '%s': %s" % [model_name, validation.error]
			print("AIModelManagementSystem: ERROR - ", error)
			model_validation_failed.emit(model_name, validation.error)
			return {"success": false, "error": error, "previous_model": previous_model}
	
	# Set the model
	var result = ai_manager.set_current_model(model_name)
	if result.success:
		print("AIModelManagementSystem: Successfully set model to: ", model_name)
		model_changed.emit(model_name, previous_model)
		return {"success": true, "error": "", "previous_model": previous_model}
	else:
		print("AIModelManagementSystem: Failed to set model: ", result.error)
		return {"success": false, "error": result.error, "previous_model": previous_model}

func validate_api_key_for_model(model_name: String) -> Dictionary:
	"""Validate API key for a specific model. Returns: {"valid": bool, "error": String}"""
	if not _validate_dependencies():
		return {"valid": false, "error": "Dependencies not properly initialized"}
	
	var ai_manager = conversation_manager.ai_model_manager
	if not ai_manager:
		return {"valid": false, "error": "No AI model manager available"}
	
	if not ai_manager.has_method("validate_api_key_for_model"):
		return {"valid": false, "error": "API key validation not supported"}
	
	var validation = ai_manager.validate_api_key_for_model(model_name)
	api_key_validation_completed.emit(model_name, validation.get("valid", false))
	return validation

func get_model_provider(model_name: String) -> String:
	"""Get the provider for a specific model"""
	if not _validate_dependencies():
		return ""
	
	var ai_manager = conversation_manager.ai_model_manager
	if not ai_manager:
		return ""
	
	if not ai_manager.has_method("get_provider_for_model"):
		return "unknown"
	
	return ai_manager.get_provider_for_model(model_name)

# ------------------------------------------------------------------
# MODEL STATUS AND ANALYSIS
# ------------------------------------------------------------------

func get_model_status_report() -> Dictionary:
	"""Get comprehensive status report for all models"""
	var report = {
		"current_model": get_current_model(),
		"available_models": get_available_models(),
		"model_details": {},
		"synchronization_status": get_synchronization_status(),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Get detailed status for each model
	for model in report.available_models:
		var model_info = {
			"provider": get_model_provider(model),
			"is_current": model == report.current_model,
			"api_key_valid": false,
			"validation_error": ""
		}
		
		var validation = validate_api_key_for_model(model)
		model_info.api_key_valid = validation.get("valid", false)
		model_info.validation_error = validation.get("error", "")
		
		report.model_details[model] = model_info
	
	return report

func get_models_by_provider() -> Dictionary:
	"""Get models grouped by provider"""
	var models_by_provider = {}
	var available_models = get_available_models()
	
	for model in available_models:
		var provider = get_model_provider(model)
		if not models_by_provider.has(provider):
			models_by_provider[provider] = []
		models_by_provider[provider].append(model)
	
	return models_by_provider

func get_valid_models() -> Array:
	"""Get list of models with valid API keys"""
	var valid_models = []
	var available_models = get_available_models()
	
	for model in available_models:
		var validation = validate_api_key_for_model(model)
		if validation.get("valid", false):
			valid_models.append(model)
	
	return valid_models

func find_best_available_model() -> String:
	"""Find the best available model based on preferences and API key validity"""
	var valid_models = get_valid_models()
	
	if valid_models.is_empty():
		print("AIModelManagementSystem: No models with valid API keys found")
		return ""
	
	# Check preference order
	for preferred_model in fallback_model_preference:
		for valid_model in valid_models:
			if preferred_model.to_lower() in valid_model.to_lower():
				print("AIModelManagementSystem: Found preferred model: ", valid_model)
				return valid_model
	
	# If no preferred model found, return first valid model
	print("AIModelManagementSystem: Using first valid model: ", valid_models[0])
	return valid_models[0]

# ------------------------------------------------------------------
# SYNCHRONIZATION MANAGEMENT
# ------------------------------------------------------------------

func get_synchronization_status() -> Dictionary:
	"""Check synchronization status between GameSession and SynTree panel"""
	var sync_status = {
		"is_synchronized": false,
		"game_model": "",
		"syntree_model": "",
		"game_manager_id": null,
		"syntree_manager_id": null,
		"error": ""
	}
	
	if not _validate_dependencies():
		sync_status.error = "Dependencies not properly initialized"
		return sync_status
	
	var ai_manager = conversation_manager.ai_model_manager
	if not ai_manager:
		sync_status.error = "No AI model manager available"
		return sync_status
	
	sync_status.game_model = ai_manager.get_current_model()
	sync_status.game_manager_id = ai_manager.get_instance_id()
	
	# Check SynTree panel's AI manager
	if plugin_manager and plugin_manager.is_ready():
		var syntree_ai_manager = plugin_manager.get_ai_model_manager()
		if syntree_ai_manager:
			sync_status.syntree_model = syntree_ai_manager.get_current_model()
			sync_status.syntree_manager_id = syntree_ai_manager.get_instance_id()
			
			sync_status.is_synchronized = (
				sync_status.game_manager_id == sync_status.syntree_manager_id and
				sync_status.game_model == sync_status.syntree_model
			)
		else:
			sync_status.error = "Could not get SynTree AI manager"
	else:
		sync_status.error = "PluginManager not available"
	
	# Cache the result
	sync_status_cache = sync_status
	last_sync_check_time = Time.get_unix_time_from_system()
	
	return sync_status

func check_synchronization_periodically():
	"""Check synchronization status if enough time has passed"""
	var current_time = Time.get_unix_time_from_system()
	if current_time - last_sync_check_time >= sync_check_interval:
		var sync_status = get_synchronization_status()
		synchronization_status_changed.emit(sync_status.is_synchronized)

func force_synchronization() -> Dictionary:
	"""Attempt to force synchronization between systems"""
	var sync_status = get_synchronization_status()
	
	if sync_status.is_synchronized:
		return {"success": true, "message": "Systems already synchronized"}
	
	if not plugin_manager or not plugin_manager.is_ready():
		return {"success": false, "error": "PluginManager not available for synchronization"}
	
	var syntree_ai_manager = plugin_manager.get_ai_model_manager()
	if not syntree_ai_manager:
		return {"success": false, "error": "Could not access SynTree AI manager"}
	
	# Try to sync the model
	var active_model = get_current_model()
	if active_model.is_empty():
		return {"success": false, "error": "No current model to synchronize"}
	
	# This would require implementation in the plugin manager
	# For now, just report the status
	return {
		"success": false, 
		"error": "Synchronization requires plugin manager support",
		"current_status": sync_status
	}

# ------------------------------------------------------------------
# DEBUG AND DIAGNOSTIC TOOLS
# ------------------------------------------------------------------

func debug_synchronization():
	"""Debug function to check AI model synchronization"""
	print("=== AI MODEL SYNCHRONIZATION DEBUG ===")
	
	var sync_status = get_synchronization_status()
	
	print("Game AI Manager Instance ID: ", sync_status.game_manager_id)
	print("Game Current Model: ", sync_status.game_model)
	print("SynTree AI Manager Instance ID: ", sync_status.syntree_manager_id)
	print("SynTree Current Model: ", sync_status.syntree_model)
	
	if sync_status.is_synchronized:
		print("✓ SYNCHRONIZED - Both systems using same AI model manager and model")
	else:
		if sync_status.game_manager_id != sync_status.syntree_manager_id:
			print("✗ MANAGER MISMATCH - Different AI model manager instances")
		if sync_status.game_model != sync_status.syntree_model:
			print("✗ MODEL MISMATCH - Different models selected")
		if not sync_status.error.is_empty():
			print("✗ ERROR: ", sync_status.error)
	
	print("=== END DEBUG ===")
	return sync_status

func debug_model_status():
	"""Debug function to show detailed model status"""
	print("=== AI MODEL STATUS DEBUG ===")
	
	var report = get_model_status_report()
	print("Current model: ", report.current_model)
	print("Available models: ", report.available_models)
	
	if report.available_models.is_empty():
		print("No AI models available")
	else:
		print("\nDetailed model status:")
		for model in report.available_models:
			var details = report.model_details[model]
			var status_parts = []
			
			if details.is_current:
				status_parts.append("CURRENT")
			
			status_parts.append("Provider: " + details.provider)
			
			if details.api_key_valid:
				status_parts.append("✓ API Key OK")
			else:
				status_parts.append("✗ API Key: " + details.validation_error)
			
			var status_str = " [" + ", ".join(status_parts) + "]"
			print("  - " + model + status_str)
	
	print("\nSynchronization status:")
	var sync_status = report.synchronization_status
	if sync_status.is_synchronized:
		print("  ✓ Synchronized with SynTree panel")
	else:
		print("  ✗ Not synchronized: ", sync_status.error)
	
	print("=== END DEBUG ===")

func list_models_with_status():
	"""Print a formatted list of all models with their status"""
	print("=== AI MODELS STATUS ===")
	
	var report = get_model_status_report()
	
	if report.available_models.is_empty():
		print("No AI models available")
		return
	
	print("Available AI models:")
	for model in report.available_models:
		var details = report.model_details[model]
		var status_parts = []
		
		if details.is_current:
			status_parts.append("CURRENT")
		
		status_parts.append("Provider: " + details.provider)
		
		if details.api_key_valid:
			status_parts.append("✓ API Key OK")
		else:
			status_parts.append("✗ API Key: " + details.validation_error)
		
		var status_str = " [" + ", ".join(status_parts) + "]"
		print("  - " + model + status_str)
	
	print("=== END STATUS ===")

# ------------------------------------------------------------------
# CONVENIENCE FUNCTIONS
# ------------------------------------------------------------------

func set_model_simple(model_name: String):
	"""Simple wrapper for console use: set_model_simple("model_name")"""
	var result = set_model(model_name)
	if not result.success:
		print("Failed to set model: ", result.error)
	else:
		print("Model set to: ", model_name)

func list_models():
	"""Simple wrapper for console use: list_models()"""
	list_models_with_status()

func current_model():
	"""Simple wrapper for console use: current_model()"""
	var model = get_current_model()
	if model.is_empty():
		print("No model currently selected")
	else:
		print("Current model: ", model)

func auto_select_best_model() -> Dictionary:
	"""Automatically select the best available model"""
	var best_model = find_best_available_model()
	if best_model.is_empty():
		return {"success": false, "error": "No valid models available"}
	
	return set_model(best_model)

func switch_to_fallback_model() -> Dictionary:
	"""Switch to a fallback model if current model is invalid"""
	var current = get_current_model()
	if not current.is_empty():
		var validation = validate_api_key_for_model(current)
		if validation.get("valid", false):
			return {"success": true, "message": "Current model is valid, no switch needed"}
	
	return auto_select_best_model()

# ------------------------------------------------------------------
# CONFIGURATION MANAGEMENT
# ------------------------------------------------------------------

func set_auto_validation(enabled: bool):
	"""Enable or disable automatic API key validation on model change"""
	auto_validate_on_change = enabled
	print("AIModelManagementSystem: Auto-validation ", "enabled" if enabled else "disabled")

func set_sync_check_interval(interval_seconds: float):
	"""Set the interval for periodic synchronization checks"""
	sync_check_interval = max(1.0, interval_seconds)
	print("AIModelManagementSystem: Sync check interval set to ", sync_check_interval, " seconds")

func set_fallback_preferences(preferences: Array):
	"""Set the preferred model order for fallback selection"""
	fallback_model_preference = preferences
	print("AIModelManagementSystem: Fallback preferences updated: ", preferences)

func get_configuration() -> Dictionary:
	"""Get current system configuration"""
	return {
		"auto_validate_on_change": auto_validate_on_change,
		"sync_check_interval": sync_check_interval,
		"fallback_model_preference": fallback_model_preference,
		"last_sync_check_time": last_sync_check_time
	}

# ------------------------------------------------------------------
# UTILITY AND TESTING FUNCTIONS
# ------------------------------------------------------------------

func test_all_models() -> Dictionary:
	"""Test API key validation for all available models"""
	print("AIModelManagementSystem: Testing all models...")
	
	var results = {
		"tested_models": [],
		"valid_models": [],
		"invalid_models": [],
		"errors": {}
	}
	
	var available_models = get_available_models()
	for model in available_models:
		results.tested_models.append(model)
		var validation = validate_api_key_for_model(model)
		
		if validation.get("valid", false):
			results.valid_models.append(model)
			print("  ✓ ", model, " - Valid")
		else:
			results.invalid_models.append(model)
			results.errors[model] = validation.get("error", "Unknown error")
			print("  ✗ ", model, " - ", validation.get("error", "Unknown error"))
	
	print("AIModelManagementSystem: Test completed. Valid: ", results.valid_models.size(), 
		  "/", results.tested_models.size())
	
	return results

func get_system_health() -> float:
	"""Get the health of the AI model management system"""
	var health = 1.0
	
	# Check if we have a current model
	var current = get_current_model()
	if current.is_empty():
		health *= 0.3
		return health
	
	# Check if current model is valid
	var validation = validate_api_key_for_model(current)
	if not validation.get("valid", false):
		health *= 0.5
	
	# Check synchronization status
	var sync_status = get_synchronization_status()
	if not sync_status.is_synchronized:
		health *= 0.8
	
	# Check if we have multiple valid models available
	var valid_models = get_valid_models()
	if valid_models.size() < 2:
		health *= 0.9
	
	return health

# ------------------------------------------------------------------
# PRIVATE HELPER FUNCTIONS
# ------------------------------------------------------------------

func _validate_dependencies() -> bool:
	"""Validate that required dependencies are available"""
	if not conversation_manager:
		print("AIModelManagementSystem: ERROR - No conversation manager set")
		return false
	
	if not conversation_manager.ai_model_manager:
		print("AIModelManagementSystem: ERROR - No AI model manager in conversation manager")
		return false
	
	return true

func _handle_model_change_error(model_name: String, error: String):
	"""Handle errors during model changes"""
	print("AIModelManagementSystem: Model change error for ", model_name, ": ", error)
	model_validation_failed.emit(model_name, error)
	
	# Try to switch to fallback if auto-validation is enabled
	if auto_validate_on_change:
		print("AIModelManagementSystem: Attempting fallback model selection...")
		var fallback_result = switch_to_fallback_model()
		if fallback_result.success:
			print("AIModelManagementSystem: Successfully switched to fallback model")
		else:
			print("AIModelManagementSystem: Failed to switch to fallback: ", fallback_result.error) 
