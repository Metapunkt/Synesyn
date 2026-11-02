@tool
extends BTTask # Standardize on BTTask for all custom tasks
class_name CallMetapunktToolTask
## LimboAI Task to execute a Metapunkt tool via the ActionDispatcher.

## The name of the tool registered in Metapunkt's ToolRegistry.
@export var tool_name: String = ""

## The dictionary of arguments to pass to the tool's execute_tool method.
@export var tool_args: Dictionary = {}

# --- State ---
var _action_state = null

# Variables to store retrieved dependencies
var agent_instance # : AgentInstance 
var action_dispatcher # : ActionDispatcher

# Called once when the task begins execution.
func _setup():
	# Get dependencies from the blackboard (injected by LimboAIRunner)
	agent_instance = blackboard.get_var("agent_instance")
	action_dispatcher = blackboard.get_var("action_dispatcher")
	
	if not agent_instance:
		printerr("CallMetapunktToolTask: AgentInstance not found on blackboard!")
		return
	if not action_dispatcher:
		printerr("CallMetapunktToolTask: ActionDispatcher not found on blackboard!")
		return

# Called every tick while the task is active.
func _tick(_delta: float) -> int:
	if not agent_instance or not action_dispatcher:
		push_warning("CallMetapunktToolTask: Missing dependencies during execute.")
		return BT.Status.FAILURE
		
	if tool_name.is_empty():
		push_warning("CallMetapunktToolTask: Tool name is not set.")
		return BT.Status.FAILURE

	# --- Asynchronous Action Handling ---
	
	# If we are already waiting for an action to complete...
	if is_instance_valid(_action_state):
		# Check if the function state has completed.
		if _action_state.is_valid():
			# It's still running.
			return BT.Status.RUNNING
		else:
			# It has finished. Get the result.
			var dispatch_result = _action_state.get_result()
			_action_state = null # Clear the state
			return _handle_dispatch_result(dispatch_result)
	
	# If we are not waiting, start a new action.
	print("Limbo Task: Requesting action '%s' with args: %s" % [tool_name, str(tool_args)])
	_action_state = agent_instance.request_action(tool_name, tool_args)

	# Check if the call returned a function state (meaning it's async).
	if is_instance_valid(_action_state) and _action_state.is_valid():
		# The action is asynchronous. Return RUNNING to wait for it.
		return BT.Status.RUNNING
	else:
		# The action was synchronous or failed immediately.
		var dispatch_result = _action_state
		_action_state = null # Clear the state
		return _handle_dispatch_result(dispatch_result)

func _handle_dispatch_result(dispatch_result: Dictionary) -> int:
	"""Helper function to process the result of the action dispatch."""
	if dispatch_result == null:
		printerr("CallMetapunktToolTask: Action dispatch returned null.")
		return BT.Status.FAILURE
		
	if dispatch_result.has("error"):
		printerr("CallMetapunktToolTask: Action dispatch failed - %s" % dispatch_result["error"])
		return BT.Status.FAILURE
	elif dispatch_result.has("task_id"):
		# Action submitted asynchronously.
		print("Limbo Task: Action '%s' submitted async (task_id: %s). Returning SUCCESS." % [tool_name, dispatch_result["task_id"]])
		return BT.Status.SUCCESS
	else:
		# Action executed synchronously and successfully.
		print("Limbo Task: Action '%s' executed sync successfully. Result: %s" % [tool_name, str(dispatch_result.get("result"))])
		return BT.Status.SUCCESS

# Optional: Customize display name in the editor
func _generate_name() -> String:
	if tool_name.is_empty():
		return "CallMetapunktTool (Unconfigured)"
	else:
		return "Call Tool: %s" % tool_name 
