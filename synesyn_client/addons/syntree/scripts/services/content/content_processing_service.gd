## Purpose: ContentProcessingService (script)
@tool
extends "res://addons/syntree/scripts/base/base_component.gd"

class_name ContentProcessingService

# Services
var content_model = null
var api_service = null
var ai_model_manager = null

# State
var _processing_nodes: Dictionary = {}  # node_id -> processing state
var _last_processed_time: int = 0
var _processing_count: int = 0

# Signals
signal processing_started(node_id: String)
signal processing_completed(node_id: String, success: bool)
signal processing_failed(node_id: String, error: String)
signal batch_processing_completed(success_count: int, fail_count: int)
signal content_processed(node_id: String, content: String)
signal operation_failed(operation: String, error: String)

func _init() -> void:
	super._init()

func _ready() -> void:
	await super._ready()

func setup(model, api, ai_manager) -> void:
	content_model = model
	api_service = api
	ai_model_manager = ai_manager
	
	if not content_model or not api_service or not ai_model_manager:
		operation_failed.emit("setup", "Required services not available")
		return

func process_content(node_id: String) -> void:
	if not _check_services():
		operation_failed.emit("process_content", "Services not available")
		return
		
	var hierarchy = content_model.get_hierarchy()
	var node = hierarchy.nodes.get(node_id)
	if not node:
		operation_failed.emit("process_content", "Node not found")
		return
		
	var content = node.get("content", "")
	if content.is_empty():
		operation_failed.emit("process_content", "No content to process")
		return
		
	# Process with AI model
	var result = await ai_model_manager.process_content(content)
	if result.success:
		var processed_content = result.content
		var update_result = content_model.update_node_property(node_id, "processed_content", processed_content)
		if update_result.success:
			content_processed.emit(node_id, processed_content)
		else:
			operation_failed.emit("process_content", update_result.error)
	else:
		operation_failed.emit("process_content", result.error)

func process_batch(node_ids: Array) -> Dictionary:
	if not _check_services():
		return {"success": 0, "failed": 0}
	
	var results = {"success": 0, "failed": 0}
	
	for node_id in node_ids:
		var result = await process_content(node_id)
		if not result.begins_with("Error:"):
			results.success += 1
		else:
			results.failed += 1
	
	batch_processing_completed.emit(results.success, results.failed)
	return results

func cancel_processing(node_id: String) -> void:
	if not _check_services() or not _processing_nodes.has(node_id):
		return
		
	_processing_nodes[node_id]["status"] = "cancelled"
	processing_failed.emit(node_id, "Processing cancelled")
	_processing_nodes.erase(node_id)

func get_processing_status(node_id: String) -> Dictionary:
	if not _check_services() or not _processing_nodes.has(node_id):
		return {}
	return _processing_nodes[node_id].duplicate()

func is_processing() -> bool:
	if not _check_services():
		return false
	return _processing_count > 0 and _processing_nodes.values().any(func(state): return state["status"] == "processing")

func get_processing_count() -> int:
	return _processing_count

func get_last_processed_time() -> int:
	return _last_processed_time

func _handle_processing_failure(node_id: String, error: String) -> void:
	_processing_nodes[node_id]["status"] = "failed"
	_processing_nodes[node_id]["error"] = error
	processing_failed.emit(node_id, error)

func _on_api_request_failed(_endpoint: String, error: AIError) -> void:
	# Handle API errors for any ongoing processing
	for node_id in _processing_nodes:
		if _processing_nodes[node_id]["status"] == "processing":
			_handle_processing_failure(node_id, error.user_message)

func _check_services() -> bool:
	return content_model != null and api_service != null and ai_model_manager != null