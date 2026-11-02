extends Node # Needs to be a Node to use process loop or timers
class_name TaskRunner
#
## Executes tasks, handles async polling/callbacks.
## Implements SLOP /tasks endpoint logic.
#
## Preloads
const MetapunktTask = preload("res://addons/metapunkt/TaskManager/Task.gd")
#
## --- Dependencies ---
var task_queue # : TaskQueue
var audit_logger # : AuditLogger
#
## --- Configuration ---
var max_concurrent_tasks: int = 4 # Limit how many tasks run "at once"
var poll_interval: float = 0.1 # How often to check for new tasks
#
## --- Internal State ---
var _running_tasks: Dictionary = {} # task_id -> MetapunktTask
var _poll_timer: Timer
#
## --- Initialization ---
func _init(p_task_queue = null, p_audit_logger = null):
	task_queue = p_task_queue
	audit_logger = p_audit_logger
	if not task_queue:
		push_error("TaskRunner initialized without TaskQueue!")
	if not audit_logger:
		push_warning("TaskRunner initialized without AuditLogger.")

func _ready():
	_poll_timer = Timer.new()
	_poll_timer.wait_time = poll_interval
	_poll_timer.one_shot = false # Keep polling
	_poll_timer.timeout.connect(_check_for_tasks)
	add_child(_poll_timer)
	_poll_timer.start()
	print("TaskRunner started polling every %s seconds." % poll_interval)

func _exit_tree():
	if _poll_timer:
		_poll_timer.stop()
	## TODO: Potentially wait for running tasks to finish?

## --- Task Execution Logic ---

func _check_for_tasks():
	## Don't run too many tasks concurrently
	if _running_tasks.size() >= max_concurrent_tasks:
		return
	
	var task: MetapunktTask = task_queue.get_next_task()
	if task:
		print("TaskRunner picked up task: %s" % task.task_id)
		_running_tasks[task.task_id] = task
		## Execute the task deferred (yields one frame, basic concurrency)
		## For true async, would need Threads.
		_execute_task.call_deferred(task)

## This function actually runs the task logic
func _execute_task(task: MetapunktTask):
	if not is_instance_valid(task):
		printerr("Task object became invalid before execution: %s" % task.task_id)
		_running_tasks.erase(task.task_id) # Remove from local tracking
		return
		
	if not task.callable_target.is_valid():
		var err_msg = "Invalid callable target for task %s" % task.task_id
		printerr(err_msg)
		_handle_task_completion(task.task_id, null, err_msg)
		return
		
	# Call the target function with its arguments
	var result = task.callable_target.callv(task.arguments)

	# Await common awaitable shapes in Godot 4:
	# - GDScriptFunctionState (most async functions)
	# - Signal
	# - Object with "completed" signal (custom awaitables)
	var final_result = result
	# Avoid hard type refs (some Godot builds don’t expose GDScriptFunctionState to the parser).
	if result is Object and result.get_class() == "GDScriptFunctionState":
		print("Task %s returned GDScriptFunctionState, awaiting..." % task.task_id)
		final_result = await result
	elif result is Signal:
		print("Task %s returned Signal, awaiting..." % task.task_id)
		final_result = await result
	elif result is Object and result.has_signal("completed"):
		print("Task %s returned custom awaitable (completed), awaiting..." % task.task_id)
		final_result = await result.completed

	_handle_task_completion(task.task_id, final_result, "")


func _handle_task_completion(task_id: String, result, error_message: String):
	## Ensure task is still considered running by this runner
	var task: MetapunktTask = _running_tasks.get(task_id)
	if not task:
		## This might happen if task completed extremely quickly or race condition
		push_warning("Task %s completion handled, but it wasn't in the local running list." % task_id)
	else:
		_running_tasks.erase(task_id)

	# v1: emit task lifecycle events (avoid duplicating ToolRegistry tool.* events).
	# ActionDispatcher async tasks pass args: [agent_id, tool_name, args_dict, user_id, scopes, turn_id]
	if task and audit_logger and audit_logger.has_method("emit_event"):
		if task.arguments.size() >= 6 and task.arguments[0] is String and task.arguments[1] is String and task.arguments[2] is Dictionary:
			var agent_id := str(task.arguments[0])
			var tool_name := str(task.arguments[1])
			var user_id := str(task.arguments[3])
			var scopes: Array = task.arguments[4] if task.arguments[4] is Array else []
			var turn_id := str(task.arguments[5]).strip_edges()
			var call_id := str(task.arguments[6]).strip_edges() if task.arguments.size() >= 7 else ""
			var session_id := str(task.arguments[7]).strip_edges() if task.arguments.size() >= 8 else ""
			if error_message.is_empty():
				audit_logger.emit_event(
					"task.completed",
					{
						"task_id": task_id,
						"agent_id": agent_id,
						"tool_name": tool_name,
						"scopes": scopes,
						"turn_id": turn_id,
						"call_id": call_id,
						"session_id": session_id,
					},
					user_id,
					{"component": "metapunkt", "mode": "async"}
				)
			else:
				audit_logger.emit_event(
					"task.failed",
					{
						"task_id": task_id,
						"agent_id": agent_id,
						"tool_name": tool_name,
						"error": error_message,
						"scopes": scopes,
						"turn_id": turn_id,
						"call_id": call_id,
						"session_id": session_id,
					},
					user_id,
					{"component": "metapunkt", "mode": "async"}
				)

	## Update status in the queue
	if error_message.is_empty():
		task_queue.mark_task_completed(task_id, result)
	else:
		task_queue.mark_task_failed(task_id, error_message)

## --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
# Removed HTTPRequest/Response type hints from args again due to persistent parse errors
func handle_request(method: String, path_segments: Array, request, response, user_id: String, scopes: Array) -> Dictionary:
	var endpoint_path = "/tasks" + ("/" + "/".join(path_segments) if not path_segments.is_empty() else "")
	print("TaskRunner handling request: %s %s" % [method, endpoint_path])

	if method == "GET" and path_segments.size() == 1:
		var task_id = path_segments[0]
		return _handle_get_task_status(request, response, user_id, scopes, task_id)
	else:
		_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Not Implemented"}, user_id)
		# Return an error dictionary with status code
		return {"error": "Endpoint not implemented: %s %s" % [method, endpoint_path], "status_code": 501} # 501 Not Implemented


## --- Private Handler Methods ---

# Removed HTTPRequest/Response type hints from args again
func _handle_get_task_status(request, response, user_id: String, scopes: Array, task_id: String) -> Dictionary:
	var status_dict = task_queue.get_task_status(task_id)

	if status_dict.has("error"):
		_log_audit("get_task_status_error", {"task_id": task_id, "error": "Not Found"}, user_id)
		# Return an error dictionary with status code
		return {"error": status_dict["error"], "task_id": task_id, "status_code": 404} # 404 Not Found

	# TODO: Authorization check 
	# if not authorized: return {"error": "Unauthorized", "status_code": 403}
		
	_log_audit("get_task_status", {"task_id": task_id, "status": status_dict["status"]}, user_id)
	# Return the success data dictionary with status code
	return {"data": status_dict, "status_code": 200} # 200 OK


## --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 
