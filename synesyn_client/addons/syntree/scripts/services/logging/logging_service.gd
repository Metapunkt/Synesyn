## Purpose: LoggingService (script)
@tool
extends "res://addons/syntree/scripts/base/base_service.gd"

class_name LoggingService

enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3
}

enum LogCategory {
	GENERAL,
	INITIALIZATION,
	SERVICE,
	COMPONENT,
	DEPENDENCY,
	STATE_CHANGE
}

var _log_level: LogLevel = LogLevel.DEBUG
var _enabled_categories: Dictionary = {}
var _log_buffer: Array = []
var _max_buffer_size: int = 1000

func _init() -> void:
	super._init()
	_setup_default_categories()

func _setup() -> bool:
	return true

func get_service_name() -> String:
	return "logging_service"

func _setup_default_categories() -> void:
	for category in LogCategory.values():
		_enabled_categories[category] = true

# Main logging methods
func debug(message: String, category: LogCategory = LogCategory.GENERAL) -> void:
	_log(LogLevel.DEBUG, message, category)

func info(message: String, category: LogCategory = LogCategory.GENERAL) -> void:
	_log(LogLevel.INFO, message, category)

func warning(message: String, category: LogCategory = LogCategory.GENERAL) -> void:
	_log(LogLevel.WARNING, message, category)

func error(message: String, category: LogCategory = LogCategory.GENERAL) -> void:
	_log(LogLevel.ERROR, message, category)

# Internal logging method
func _log(level: LogLevel, message: String, category: LogCategory) -> void:
	if level < _log_level or not _enabled_categories.get(category, false):
		return

	var timestamp = Time.get_datetime_string_from_system()
	var level_str = LogLevel.keys()[level]
	var category_str = LogCategory.keys()[category]
	
	var log_entry = {
		"timestamp": timestamp,
		"level": level_str,
		"category": category_str,
		"message": message
	}
	
	_add_to_buffer(log_entry)
	
	# Format console output
	var console_message = "[%s][%s][%s] %s" % [timestamp, level_str, category_str, message]
	match level:
		LogLevel.ERROR:
			push_error(console_message)
		LogLevel.WARNING:
			push_warning(console_message)
		_:
			print(console_message)

func _add_to_buffer(entry: Dictionary) -> void:
	_log_buffer.append(entry)
	if _log_buffer.size() > _max_buffer_size:
		_log_buffer.pop_front()

# Configuration methods
func set_log_level(level: LogLevel) -> void:
	_log_level = level

func enable_category(category: LogCategory) -> void:
	_enabled_categories[category] = true

func disable_category(category: LogCategory) -> void:
	_enabled_categories[category] = false

# Query methods
func get_logs(level: LogLevel = -1, category: LogCategory = -1, limit: int = 50) -> Array:
	var filtered_logs = []
	for log in _log_buffer:
		if filtered_logs.size() >= limit:
			break
			
		if level >= 0 and LogLevel[log.level] != level:
			continue
			
		if category >= 0 and LogCategory[log.category] != category:
			continue
			
		filtered_logs.append(log)
	
	return filtered_logs

func clear_logs() -> void:
	_log_buffer.clear() 