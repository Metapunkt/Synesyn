@tool
extends BTTask
class_name DebugTask
## A debug task that prints blackboard and memory contents.

@export var debug_message: String = "Debug Task"

# --- Dependencies (from blackboard) ---
var agent_instance # : AgentInstance
var short_term_memory # : ShortTermMemory

func _setup():
	agent_instance = blackboard.get_var("agent_instance")
	short_term_memory = blackboard.get_var("short_term_memory")
	
	print("=== DebugTask Setup ===")
	print("Debug message: ", debug_message)
	print("Agent instance found: ", agent_instance != null)
	print("Short term memory found: ", short_term_memory != null)
	
	if agent_instance:
		print("Agent ID: ", agent_instance.agent_id)
		print("Agent name: ", agent_instance.definition.agent_name if agent_instance.definition else "No definition")
	
	if not agent_instance:
		printerr("DebugTask: AgentInstance not found on blackboard!")
	if not short_term_memory:
		printerr("DebugTask: ShortTermMemory not found on blackboard!")

func _tick(delta: float) -> int:
	print("=== DebugTask Tick ===")
	print("Debug message: ", debug_message)
	
	if not agent_instance or not short_term_memory:
		print("Missing dependencies!")
		return BT.Status.FAILURE

	print("Agent ID: ", agent_instance.agent_id)
	
	# Check specific memory values
	var should_speak = short_term_memory.get_memory("should_speak", agent_instance.agent_id)
	print("should_speak for ", agent_instance.agent_id, ": ", should_speak)
	
	var conversation_log = short_term_memory.get_memory("conversation_log", "shared")
	print("Conversation log entries: ", conversation_log.size() if conversation_log else 0)
	
	# Print all blackboard contents
	print("Blackboard contents:")
	for key in blackboard.get_vars():
		print("  ", key, ": ", blackboard.get_var(key))
	
	print("=== DebugTask Complete ===")
	return BT.Status.SUCCESS

func _generate_name() -> String:
	return "Debug: %s" % debug_message 