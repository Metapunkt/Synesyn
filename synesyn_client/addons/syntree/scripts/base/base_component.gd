## Purpose: base/base_component.gd
@tool
extends Node

var _is_ready: bool = false
var _is_initializing: bool = false

signal initialization_completed

func _init() -> void:
	_is_initializing = true

func _ready() -> void:
	_is_ready = true
	_is_initializing = false
	initialization_completed.emit()

func is_ready() -> bool:
	return _is_ready

func is_initializing() -> bool:
	return _is_initializing

func get_plugin_manager():
	return get_node_or_null("/root/PluginManager")

func get_content_model():
	var plugin_manager = get_plugin_manager()
	if plugin_manager:
		return plugin_manager.get_content_model()
	return null

func get_content_service():
	var plugin_manager = get_plugin_manager()
	if plugin_manager:
		return plugin_manager.get_content_service()
	return null

func get_content_persistence():
	var plugin_manager = get_plugin_manager()
	if plugin_manager:
		return plugin_manager.get_content_persistence()
	return null

func get_api_service():
	var plugin_manager = get_plugin_manager()
	if plugin_manager:
		return plugin_manager.get_api_service()
	return null

func get_ai_model_manager():
	var plugin_manager = get_plugin_manager()
	if plugin_manager:
		return plugin_manager.get_ai_model_manager()
	return null

func get_conversation_manager():
	var plugin_manager = get_plugin_manager()
	if plugin_manager:
		return plugin_manager.get_conversation_manager()
	return null

func get_config_manager():
	var plugin_manager = get_plugin_manager()
	if plugin_manager:
		return plugin_manager.get_config_manager()
	return null
