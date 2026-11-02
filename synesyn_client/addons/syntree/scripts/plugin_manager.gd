## Purpose: plugin_manager.gd
@tool
extends Node

# --- Temporarily comment out preload --- 
const ContentPersistenceService = preload("res://addons/syntree/scripts/services/content/content_persistence_service.gd")

signal initialization_completed

var _is_ready: bool = false
var editor_interface = null

# Services
var content_service
var content_persistence
var api_service
var ai_model_manager
var conversation_manager
var config_manager = null  # Will be set by SynTreePanel
var notification_manager = null  # UNCOMMENT THIS LINE

func setup(p_editor_interface) -> void:
	editor_interface = p_editor_interface
	if not _is_ready:
		print("PluginManager: Calling _ready from setup")
		_ready()
	else:
		print("PluginManager: Already initialized, skipping _ready call")

func _ready():
	print("PluginManager: _ready START") # LOG
	print("=== Initializing Plugin Manager ===")
	
	# Initialize services in dependency order
	_init_services()
	
	_is_ready = true
	print("PluginManager: Emitting initialization_completed") # LOG
	initialization_completed.emit()
	print("PluginManager: _ready COMPLETE") # LOG
	print("=== Plugin Manager Initialization Complete ===")

func _init_services():
	print("PluginManager: _init_services START") # LOG
	# Uncomment ConfigManager
	print("PluginManager: Preloading ConfigManager...") 
	var ConfigManagerClass = preload("res://addons/syntree/scripts/utils/config_manager.gd")
	print("PluginManager: ConfigManager preloaded.")
	config_manager = ConfigManagerClass.new()
	print("PluginManager: ConfigManager instantiated.")
	add_child(config_manager)
	print("PluginManager: ConfigManager added as child.")
	
	# Uncomment remaining logic that depends on config_manager
	# Get API keys from config
	print("PluginManager: Getting API keys...")
	var api_keys = {}
	for provider_id: String in ["anthropic", "openai", "google", "deepseek", "xai"]:
		var provider_key: String = config_manager.get_api_key(provider_id)
		if not provider_key.is_empty():
			api_keys[provider_id] = provider_key
	print("PluginManager: API keys retrieved.")
	
	# Initialize the rest of the previously commented out services
	# Notification manager should already be uncommented in the original file based on the comment
	
	# 1) AI Model Manager setup with config_manager
	# AIModelManager handles different AI providers/models and their API keys.
	print("PluginManager: Setting up AI model manager...")
	var AIModelManagerClass = preload("res://addons/syntree/scripts/services/ai/ai_model_loaders/ai_model_manager.gd")
	ai_model_manager = AIModelManagerClass.new()
	add_child(ai_model_manager)
	
	# AI Model Manager setup with config_manager
	var model_setup = ai_model_manager.setup(api_keys, config_manager)
	if not model_setup.success:
		push_error("Failed to set up AI model manager: " + model_setup.error)
		
	print("PluginManager: AI model manager setup complete.")
	
	# 2) API service setup
	# APIService handles the actual HTTP requests to AI endpoints.
	# It requires a reference to AIModelManager to get provider-specific details.
	print("PluginManager: Setting up API service...")
	var APIServiceClass = preload("res://addons/syntree/scripts/services/api/api_service.gd")
	api_service = APIServiceClass.new()
	add_child(api_service)
	# Pass the ai_model_manager instance to the API service setup - removed api_key arg
	# APIService setup no longer takes an API key directly; it retrieves it via the loader.
	var api_setup = api_service.setup(ai_model_manager) # Pass only manager and use default timeout
	# Check if setup returned a valid dictionary before accessing keys
	if not api_setup is Dictionary:
		push_error("Failed to set up API service: Invalid return value from setup.")
	elif not api_setup.success:
		push_error("Failed to set up API service: " + api_setup.get("error", "Unknown setup error"))
	if ai_model_manager and ai_model_manager.has_method("set_api_service"):
		ai_model_manager.set_api_service(api_service)
	print("PluginManager: API service setup complete.")
	
	# 3) Content persistence setup
	# Handles saving/loading content source data and state.
	print("PluginManager: Setting up content persistence...")
	content_persistence = ContentPersistenceService.new()
	add_child(content_persistence)
	content_persistence.initialize(self)
	print("PluginManager: Content persistence setup complete.")
	
	# 4) Content service setup
	# Manages the in-memory representation and validation of content sources.
	print("PluginManager: Setting up content service...")
	var ContentServiceClass = preload("res://addons/syntree/scripts/services/content/content_service.gd")
	content_service = ContentServiceClass.new()
	add_child(content_service)
	content_service.initialize(self)
	print("PluginManager: Content service setup complete.")
	
	# 5) Conversation manager setup
	# Manages chat history, threads, and interaction with APIService.
	# Requires both APIService and AIModelManager references.
	print("PluginManager: Setting up conversation manager...")
	# Instantiate via class_name to avoid preload/new edge-cases during editor tool loading.
	conversation_manager = ConversationManager.new()
	add_child(conversation_manager)
	# Enforce isolation + predictable behavior for SynTree editor surface.
	#
	# INTEGRATOR NOTE (ReadyMade/Studio/etc):
	# If you are calling ConversationManager from another app, you MUST set a unique scope
	# BEFORE calling `ConversationManager.setup(...)`:
	#   conversation_manager.set_thread_scope("readymade_session")  # example
	#   conversation_manager.setup(api_service, ai_model_manager)
	# Otherwise, threads can be loaded/saved under the wrong scope and histories may mix.
	if conversation_manager and conversation_manager.has_method("set_thread_scope"):
		conversation_manager.set_thread_scope("syntree_editor")
	if conversation_manager and conversation_manager.has_method("set_include_content_bus_context"):
		conversation_manager.set_include_content_bus_context(true)
	var conversation_setup = conversation_manager.setup(api_service, ai_model_manager)
	if not conversation_setup.success:
		push_error("Failed to set up conversation manager: " + conversation_setup.error)
	print("PluginManager: Conversation manager setup complete.")

	print("PluginManager: Connecting operation_failed signals...")
	if content_service and content_service.has_signal("operation_failed"):
		content_service.operation_failed.connect(_on_operation_failed)
	if content_persistence and content_persistence.has_signal("operation_failed"):
		content_persistence.operation_failed.connect(_on_operation_failed)
	if api_service and api_service.has_signal("operation_failed"):
		api_service.operation_failed.connect(_on_operation_failed)
	if ai_model_manager and ai_model_manager.has_signal("operation_failed"):
		ai_model_manager.operation_failed.connect(_on_operation_failed)
	if conversation_manager and conversation_manager.has_signal("operation_failed"):
		conversation_manager.operation_failed.connect(_on_operation_failed)
	print("PluginManager: operation_failed signals connected.") 
	
	print("PluginManager: _init_services COMPLETE") # Updated log

func is_ready() -> bool:
	return _is_ready

# Simple getters for services
func get_content_service():
	# Return null if it wasn't initialized
	return content_service if is_instance_valid(content_service) else null

func get_content_persistence():
	return content_persistence if is_instance_valid(content_persistence) else null

func get_api_service():
	return api_service if is_instance_valid(api_service) else null

func get_ai_model_manager():
	return ai_model_manager if is_instance_valid(ai_model_manager) else null

func get_conversation_manager():
	return conversation_manager if is_instance_valid(conversation_manager) else null

# Add getter for config manager
func get_config_manager():
	return config_manager if is_instance_valid(config_manager) else null

# Add getter for notification manager
func get_notification_manager():
	return notification_manager

# Error handling bridge
func handle_ai_error(error: AIError) -> void:
	if not notification_manager:
		push_error("Notification manager not available")
		return
		
	# Show the main error message
	notification_manager.error(error.user_message, "AI Error - " + error.provider)
	
	# If there's a solution, show it as a follow-up info message
	if not error.solution.is_empty():
		notification_manager.info(error.solution, "Suggested Solution")
		
	# Log the error for debugging
	print("AI Error: ", error.raw_message)
	print("Error Type: ", AIError.ErrorType.keys()[error.error_type])

func handle_operation_error(operation: String, error_message: String) -> void:
	if not notification_manager:
		push_error("Notification manager not available")
		return
		
	notification_manager.error(error_message, "Operation Failed: " + operation)
	print("Operation Error - ", operation, ": ", error_message)

# Update existing operation_failed signal handling
func _on_operation_failed(operation: String, error: String, details: String = "") -> void:
	print("DEBUG: Plugin Manager - Operation failed: ", operation)
	print("DEBUG: Plugin Manager - Error: ", error)
	print("DEBUG: Plugin Manager - Details: ", details)

func get_service(service_name: String) -> Node:
	match service_name:
		"logging_service":
			return null  # We don't have a logging service, base_service will fall back to console logging
		"content_service":
			# Return null if it wasn't initialized
			return content_service if is_instance_valid(content_service) else null
		"content_persistence":
			return content_persistence if is_instance_valid(content_persistence) else null
		"api_service":
			return api_service if is_instance_valid(api_service) else null
		"ai_model_manager":
			return ai_model_manager if is_instance_valid(ai_model_manager) else null
		"conversation_manager", "ConversationManager":  # Support both naming conventions
			return conversation_manager if is_instance_valid(conversation_manager) else null
		"config_manager":
			return config_manager if is_instance_valid(config_manager) else null
		"notification_manager":
			return notification_manager
		_:
			return null

func get_available_services() -> Array:
	"""Return list of available service names"""
	var services = []
	if is_instance_valid(content_service):
		services.append("content_service")
	if is_instance_valid(content_persistence):
		services.append("content_persistence")
	if is_instance_valid(api_service):
		services.append("api_service")
	if is_instance_valid(ai_model_manager):
		services.append("ai_model_manager")
	if is_instance_valid(conversation_manager):
		services.append("conversation_manager")
		services.append("ConversationManager")  # Add both naming conventions
	if is_instance_valid(config_manager):
		services.append("config_manager")
	if notification_manager:
		services.append("notification_manager")
	return services
