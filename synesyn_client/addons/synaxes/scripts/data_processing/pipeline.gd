@tool
extends Node

## Background-threaded data processing pipeline for SynAxes.
##
## Currently **not wired** into the import flow.  Planned usage (v1):
##   1. synaxes_runtime_controller.gd adds this Node as a child during _ready().
##   2. After importing items from the Hub, enqueue each item via process_data()
##      for pre-processing (JSON normalisation, CSV parsing, text statistics,
##      image metadata extraction) before feeding into the DiscoveryEngine.
##   3. Listen to processing_completed / processing_error signals to collect
##      results asynchronously.
##
## The thread polls a queue at 100 ms intervals.  Call _exit_tree() or free the
## node to shut down gracefully.

signal processing_completed(data: Dictionary)
signal processing_error(error: String)

var _thread: Thread
var _processing_queue: Array = []
var _is_processing: bool = false
var _should_exit: bool = false

func _ready() -> void:
	_thread = Thread.new()
	_thread.start(_process_data)

func _process_data() -> void:
	while not _should_exit:
		if _processing_queue.is_empty():
			OS.delay_msec(100)  # Prevent busy waiting
			continue
			
		var data = _processing_queue.pop_front()
		_process_single_item(data)

func _process_single_item(data: Dictionary) -> void:
	var result = {}
	
	match data.type:
		"json":
			result = _process_json(data.content)
		"csv":
			result = _process_csv(data.content)
		"text":
			result = _process_text(data.content)
		"image":
			result = _process_image(data.content)
		_:
			call_deferred("emit_signal", "processing_error", "Unsupported data type: " + data.type)
			return
	
	call_deferred("emit_signal", "processing_completed", result)

func _process_json(content: String) -> Dictionary:
	var json = JSON.new()
	var error = json.parse(content)
	if error != OK:
		call_deferred("emit_signal", "processing_error", "JSON parsing error: " + json.get_error_message())
		return {}
	return json.get_data()

func _process_csv(content: String) -> Dictionary:
	var lines = content.split("\n")
	var headers = lines[0].split(",")
	var result = []
	
	for i in range(1, lines.size()):
		var values = lines[i].split(",")
		if values.size() != headers.size():
			continue
			
		var row = {}
		for j in range(headers.size()):
			row[headers[j]] = values[j]
		result.append(row)
	
	return {"data": result}

func _process_text(content: String) -> Dictionary:
	# Basic text processing - can be extended based on needs
	return {
		"content": content,
		"word_count": content.split(" ").size(),
		"char_count": content.length()
	}

func _process_image(content: Image) -> Dictionary:
	# Basic image processing - can be extended based on needs
	return {
		"width": content.get_width(),
		"height": content.get_height(),
		"format": content.get_format()
	}

func process_data(data: Dictionary) -> void:
	_processing_queue.append(data)

func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_should_exit = true
		_thread.wait_to_finish() 