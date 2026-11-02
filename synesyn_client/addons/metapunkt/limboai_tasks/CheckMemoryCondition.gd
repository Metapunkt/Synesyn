@tool
extends BTTask
class_name CheckMemoryCondition
## Checks if a variable in the agent's ShortTermMemory matches a specific value.

## The name of the variable to check in ShortTermMemory.
@export var variable_name: String = ""
## The value to compare against. The memory value will be converted to match this type.
@export var value_to_check = true
## If true, the condition succeeds if the variable is NOT found in memory.
@export var success_if_not_found: bool = false

# --- Dependencies (from blackboard) ---
var agent_instance # : AgentInstance
var short_term_memory # : ShortTermMemory

func _setup():
	agent_instance = blackboard.get_var("agent_instance")
	short_term_memory = blackboard.get_var("short_term_memory")
	print("CheckMemoryCondition _setup called")
	print("  variable_name: '", variable_name, "'")
	print("  value_to_check: ", value_to_check)
	print("  agent_instance found: ", agent_instance != null)
	print("  short_term_memory found: ", short_term_memory != null)
	if agent_instance:
		print("  agent_id: ", agent_instance.agent_id)
	if not agent_instance:
		printerr("CheckMemoryCondition: AgentInstance not found on blackboard!")
	if not short_term_memory:
		printerr("CheckMemoryCondition: ShortTermMemory not found on blackboard!")

func _tick(delta: float) -> int: # Using int, as BT.Status is an enum
	print("CheckMemoryCondition _tick called for variable: '", variable_name, "'")
	if _is_condition_met():
		print("  Condition MET - returning SUCCESS")
		return BT.Status.SUCCESS
	else:
		print("  Condition NOT MET - returning FAILURE")
		return BT.Status.FAILURE

func _is_condition_met() -> bool:
	if not agent_instance or not short_term_memory or variable_name.is_empty():
		print("  Missing dependencies or empty variable_name")
		print("    agent_instance: ", agent_instance != null)
		print("    short_term_memory: ", short_term_memory != null)
		print("    variable_name: '", variable_name, "'")
		return false

	var memory_scope = agent_instance.agent_id
	var default_value = not value_to_check # A default that will cause failure
	
	var value_in_memory = short_term_memory.get_memory(variable_name, memory_scope)
	
	print("  Checking memory - scope: '", memory_scope, "', variable: '", variable_name, "'")
	print("  Value in memory: ", value_in_memory, " (type: ", typeof(value_in_memory), ")")
	print("  Expected value: ", value_to_check, " (type: ", typeof(value_to_check), ")")
	
	if value_in_memory == null:
		print("  Value is null, success_if_not_found: ", success_if_not_found)
		return success_if_not_found

	# Basic type coercion to avoid comparison errors between, e.g., 1.0 and 1
	if typeof(value_in_memory) != typeof(value_to_check):
		print("  Type mismatch, converting...")
		match typeof(value_to_check):
			TYPE_BOOL:
				value_in_memory = bool(value_in_memory)
			TYPE_INT:
				value_in_memory = int(value_in_memory)
			TYPE_FLOAT:
				value_in_memory = float(value_in_memory)
			TYPE_STRING:
				value_in_memory = str(value_in_memory)
		print("  Converted value in memory: ", value_in_memory)
	
	var result = value_in_memory == value_to_check
	print("  Final comparison result: ", result)
	return result 
