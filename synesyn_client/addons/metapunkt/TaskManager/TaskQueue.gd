extends Object
class_name TaskQueue

# Manages prioritized task queue.
# Implements SLOP /queue endpoint logic.

# Preloads
const MetapunktTask = preload("res://addons/metapunkt/TaskManager/Task.gd")
const CustomHTTPResponse = preload("res://addons/metapunkt/Networking/SLOPServer/HTTPResponse.gd")

# --- Dependencies ---
var audit_logger # : AuditLogger

# --- Internal State ---
var _pending_tasks: Array[MetapunktTask] = [] # Simple FIFO queue for now
var _active_tasks: Dictionary = {} # task_id -> MetapunktTask
var _completed_tasks: Dictionary = {} # task_id -> MetapunktTask (Includes failed)
var _next_task_id: int = 1
var _max_completed_tasks: int = 1000 # Limit history size

# --- Initialization ---
func _init(p_audit_logger = null):
	audit_logger = p_audit_logger
	if not audit_logger:
		push_warning("TaskQueue initialized without AuditLogger.")

# --- Public API (called by TaskRunner, ActionDispatcher, etc.) ---

# Submits a new task to the queue
func submit_task(callable_target: Callable, args: Array = [], user_id: String = "") -> String:
	var task_id = "task_%06d" % _next_task_id
	_next_task_id += 1
	
	var new_task = MetapunktTask.new(task_id, callable_target, args, user_id)
	_pending_tasks.append(new_task)
	
	_log_audit("task_submitted", {"task_id": task_id, "callable": str(callable_target)}, user_id)
	return task_id

# Retrieves the next pending task for execution
func get_next_task() -> MetapunktTask:
	if _pending_tasks.is_empty():
		return null
	
	var task: MetapunktTask = _pending_tasks.pop_front()
	task.mark_running()
	_active_tasks[task.task_id] = task
	_log_audit("task_started", {"task_id": task.task_id}, task.user_id)
	return task

# Called by TaskRunner when a task completes successfully
func mark_task_completed(task_id: String, result):
	var task: MetapunktTask = _active_tasks[task_id] # Get first
	if not task:
		push_warning("Attempted to mark non-active or already erased task %s as completed." % task_id)
		return
	_active_tasks.erase(task_id) # Then erase
	task.mark_completed(result)
	_add_to_completed(task)
	_log_audit("task_completed", {"task_id": task_id}, task.user_id)

# Called by TaskRunner when a task fails
func mark_task_failed(task_id: String, error_message: String):
	var task: MetapunktTask = _active_tasks[task_id] # Get first
	if not task:
		push_warning("Attempted to mark non-active or already erased task %s as failed." % task_id)
		return
	_active_tasks.erase(task_id) # Then erase
	task.mark_failed(error_message)
	_add_to_completed(task)
	_log_audit("task_failed", {"task_id": task_id, "error": error_message}, task.user_id)

# Gets the status and potentially result/error of a task
func get_task_status(task_id: String) -> Dictionary:
	var task: MetapunktTask = _pending_tasks.filter(func(t): return t.task_id == task_id).front()
	if task:
		return task.get_status_dict()
	
	task = _active_tasks.get(task_id)
	if task:
		return task.get_status_dict()
		
	task = _completed_tasks.get(task_id)
	if task:
		return task.get_status_dict()
		
	return {"error": "Task not found", "task_id": task_id}

# --- ARCHITECTURE-BOUNDARY: SLOP Endpoint Handler ---
func handle_request(method: String, path_segments: Array, request_data: Dictionary, response: CustomHTTPResponse, user_id: String, scopes: Array):
	var endpoint_path = "/queue" # Only base path handled here for now
	print("TaskQueue handling request: %s %s" % [method, endpoint_path])

	# TODO: Implement specific queue management endpoints if needed (e.g., GET /queue to list pending?)
	# For now, focus is on /tasks endpoint via TaskRunner for status

	_log_audit("request_error", {"method": method, "path": endpoint_path, "error": "Not Implemented"}, user_id)
	response.send_error(501, "Endpoint not implemented: %s %s" % [method, endpoint_path])


# --- Private Helper Methods ---

func _add_to_completed(task: MetapunktTask):
	_completed_tasks[task.task_id] = task
	# Limit the size of the completed task history
	if _completed_tasks.size() > _max_completed_tasks:
		# Remove the oldest task (assuming dictionary iteration order is somewhat stable, which is risky)
		# A better approach would be a separate ordered list or timestamp check
		var oldest_task_id = _completed_tasks.keys().front() 
		_completed_tasks.erase(oldest_task_id)
		print("Removed old completed task: %s" % oldest_task_id)


# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 