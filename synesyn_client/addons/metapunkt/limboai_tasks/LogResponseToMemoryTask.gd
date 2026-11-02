@tool
extends BTTask
class_name LogResponseToMemoryTask
## Takes a response from a blackboard variable and logs it to the shared conversation log.

## The blackboard variable to read the response text from.
@export var text_variable: String = "response_text"

# --- Dependencies (from blackboard) ---
var agent_instance
var short_term_memory

func _setup():
	agent_instance = blackboard.get_var("agent_instance")
	short_term_memory = blackboard.get_var("short_term_memory")
	if not agent_instance:
		printerr("LogResponseToMemoryTask: AgentInstance not found on blackboard!")
	if not short_term_memory:
		printerr("LogResponseToMemoryTask: ShortTermMemory not found on blackboard!")

func _tick(delta: float) -> int:
	if not agent_instance or not short_term_memory:
		return BT.Status.FAILURE

	var message_text = blackboard.get_var(text_variable)
	if message_text == null or not message_text is String or message_text.is_empty():
		printerr("LogResponseToMemoryTask: Blackboard variable '", text_variable, "' is missing or empty.")
		return BT.Status.FAILURE

	var conversation_log = short_term_memory.get_memory("conversation_log", "shared", [])
	
	var log_entry = {
		"speaker": agent_instance.definition.agent_name,
		"message": message_text,
	}
	
	conversation_log.append(log_entry)
	short_term_memory.set_memory("conversation_log", conversation_log, "shared")
	
	print("Logged response from '", agent_instance.definition.agent_name, "' to shared memory.")
	
	# Clear the variable so it's not accidentally reused
	blackboard.set_var(text_variable, null)

	return BT.Status.SUCCESS

func _generate_name() -> String:
	return "LogResponseToMemory" 