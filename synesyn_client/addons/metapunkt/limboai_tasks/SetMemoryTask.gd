@tool
extends BTTask
class_name SetMemoryTask
## Sets a value in the agent's ShortTermMemory.

## The name of the variable to set in ShortTermMemory.
@export var variable_name: String = ""
## The value to set. 
@export var value_to_set = false
## Memory scope to use (defaults to agent's scope)
@export var memory_scope: String = ""

# --- Dependencies (from blackboard) ---
var agent_instance # : AgentInstance
var short_term_memory # : ShortTermMemory

func _setup():
	agent_instance = blackboard.get_var("agent_instance")
	short_term_memory = blackboard.get_var("short_term_memory")
	if not agent_instance:
		printerr("SetMemoryTask: AgentInstance not found on blackboard!")
	if not short_term_memory:
		printerr("SetMemoryTask: ShortTermMemory not found on blackboard!")

func _tick(delta: float) -> int:
	if not agent_instance or not short_term_memory or variable_name.is_empty():
		return BT.Status.FAILURE

	var scope = memory_scope if not memory_scope.is_empty() else agent_instance.agent_id
	short_term_memory.set_memory(variable_name, value_to_set, scope)
	
	print("SetMemoryTask: Set '%s' = %s in scope '%s'" % [variable_name, str(value_to_set), scope])
	return BT.Status.SUCCESS

func _generate_name() -> String:
	return "SetMemory: %s = %s" % [variable_name, str(value_to_set)] 