extends RefCounted # Use RefCounted for easy memory management
class_name MetapunktTask

enum Status { PENDING, RUNNING, COMPLETED, FAILED }

var task_id: String
var callable_target: Callable # The function/method to call
var arguments: Array # Arguments for the callable
var status: Status = Status.PENDING
var created_time: int = Time.get_unix_time_from_system()
var started_time: int = 0
var completed_time: int = 0
var result = null
var error_message: String = ""
var user_id: String = "" # User context associated with the task

func _init(p_task_id: String, p_callable: Callable, p_args: Array = [], p_user_id: String = ""):
	task_id = p_task_id
	callable_target = p_callable
	arguments = p_args
	user_id = p_user_id

func mark_running():
	if status == Status.PENDING:
		status = Status.RUNNING
		started_time = Time.get_unix_time_from_system()

func mark_completed(p_result):
	if status == Status.RUNNING:
		status = Status.COMPLETED
		result = p_result
		completed_time = Time.get_unix_time_from_system()
		error_message = ""

func mark_failed(p_error_message: String):
	if status == Status.RUNNING:
		status = Status.FAILED
		error_message = p_error_message
		completed_time = Time.get_unix_time_from_system()
		result = null

func get_status_dict() -> Dictionary:
	return {
		"task_id": task_id,
		"status": Status.keys()[status],
		"created_time": created_time,
		"started_time": started_time,
		"completed_time": completed_time,
		"result": result, # May be null if pending, running, or failed
		"error": error_message, # Empty if not failed
		"user_id": user_id
	} 
