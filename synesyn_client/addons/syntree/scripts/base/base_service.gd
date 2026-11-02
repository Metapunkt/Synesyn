## Purpose: BaseService (script)
# services/base_service.gd
@tool
extends Node
class_name BaseService

const LoggingService = preload("res://addons/syntree/scripts/services/logging/logging_service.gd")

signal service_ready
signal initialization_started
signal initialization_completed
signal initialization_failed(error: String)
signal service_error(error_type: int, message: String)
signal operation_failed(operation: String, error: String)

enum ErrorType {
	INITIALIZATION_ERROR,
	DEPENDENCY_ERROR,
	OPERATION_ERROR,
	VALIDATION_ERROR,
	STATE_ERROR
}

var _plugin_manager = null
var _is_ready: bool = false
var _initialization_in_progress: bool = false
var _required_services: Array[String] = []
var _error_state: Dictionary = {}
var _initialization_error: String = ""
var _logger: LoggingService = null

func _init() -> void:
	pass

func initialize(plugin_manager) -> bool:
	if _is_ready:
		_log_info("Service already initialized", LoggingService.LogCategory.INITIALIZATION)
		return true
		
	if _initialization_in_progress:
		_log_info("Service initialization in progress, waiting...", LoggingService.LogCategory.INITIALIZATION)
		await initialization_completed
		return _is_ready
		
	_log_info("Starting service initialization", LoggingService.LogCategory.INITIALIZATION)
	initialization_started.emit()
	_initialization_in_progress = true
	_initialization_error = ""
	
	_plugin_manager = plugin_manager
	if not _plugin_manager:
		_fail_initialization("Invalid PluginManager provided")
		return false
	
	# Get logging service first
	_logger = _plugin_manager.get_service("logging_service")
	if not _logger:
		push_error("Logging service not available - falling back to console logging")
	
	_log_info("Waiting for required services...", LoggingService.LogCategory.DEPENDENCY)
	if not await _wait_for_required_services():
		_fail_initialization("Failed to initialize required services: " + _initialization_error)
		return false
		
	_log_info("Setting up service...", LoggingService.LogCategory.INITIALIZATION)
	if not await _setup():
		_fail_initialization("Service setup failed: " + _initialization_error)
		return false
	
	_is_ready = true
	_initialization_in_progress = false
	_log_info("Service initialization completed successfully", LoggingService.LogCategory.INITIALIZATION)
	initialization_completed.emit()
	return true

func _fail_initialization(error: String) -> void:
	_initialization_error = error
	_is_ready = false
	_initialization_in_progress = false
	_log_error("Initialization failed: " + error, LoggingService.LogCategory.INITIALIZATION)
	_handle_error(ErrorType.INITIALIZATION_ERROR, error)
	initialization_failed.emit(error)

func _setup() -> bool:
	return true

func get_service_name() -> String:
	_handle_error(ErrorType.OPERATION_ERROR, "get_service_name() must be implemented by derived class")
	return ""

func get_service(name: String) -> Node:
	if not _plugin_manager:
		_handle_error(ErrorType.DEPENDENCY_ERROR, "PluginManager not available")
		return null
		
	var service = _plugin_manager.get_service(name)
	if not service:
		_log_error("Service not found: " + name, LoggingService.LogCategory.DEPENDENCY)
		_handle_error(ErrorType.DEPENDENCY_ERROR, "Service not found: " + name)
		return null
		
	return service

func require_services(service_names: Array[String]) -> void:
	_required_services = service_names
	if _logger:
		_log_info("Required services set: " + str(service_names), LoggingService.LogCategory.DEPENDENCY)

func is_ready() -> bool:
	return _is_ready

func is_initializing() -> bool:
	return _initialization_in_progress

func _wait_for_required_services() -> bool:
	for service_name in _required_services:
		_log_debug("Checking service: " + service_name, LoggingService.LogCategory.DEPENDENCY)
		var service = get_service(service_name)
		if not service:
			_initialization_error = "Required service not found: " + service_name
			return false
			
		if service.has_signal("service_ready"):
			if not service.is_ready():
				if service.is_initializing():
					_log_info("Waiting for service: " + service_name, LoggingService.LogCategory.DEPENDENCY)
					await service.initialization_completed
				else:
					_initialization_error = "Service not ready and not initializing: " + service_name
					return false
					
			if not service.is_ready():
				_initialization_error = "Service failed to initialize: " + service_name
				return false
				
	_log_info("All required services are ready", LoggingService.LogCategory.DEPENDENCY)
	return true

func _handle_error(error_type: ErrorType, message: String) -> void:
	var error_info = {
		"type": error_type,
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	_error_state[error_info.timestamp] = error_info
	
	_log_error(message, LoggingService.LogCategory.GENERAL)
	
	service_error.emit(error_type, message)
	if error_type == ErrorType.OPERATION_ERROR:
		operation_failed.emit("service_operation", message)

# Logging helper methods
func _log_debug(message: String, category: int) -> void:
	if _logger:
		_logger.debug("[" + get_service_name() + "] " + message, category)
	else:
		print("[DEBUG][" + get_service_name() + "] " + message)

func _log_info(message: String, category: int) -> void:
	if _logger:
		_logger.info("[" + get_service_name() + "] " + message, category)
	else:
		print("[INFO][" + get_service_name() + "] " + message)

func _log_warning(message: String, category: int) -> void:
	if _logger:
		_logger.warning("[" + get_service_name() + "] " + message, category)
	else:
		push_warning("[" + get_service_name() + "] " + message)

func _log_error(message: String, category: int) -> void:
	if _logger:
		_logger.error("[" + get_service_name() + "] " + message, category)
	else:
		push_error("[" + get_service_name() + "] " + message)
