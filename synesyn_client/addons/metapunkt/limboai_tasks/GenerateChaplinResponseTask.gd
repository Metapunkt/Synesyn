@tool
extends BTTask
class_name GenerateChaplinResponseTask
## Generates a chat response using the SynTree tool and saves it to the blackboard.

## The blackboard variable where the generated response text will be stored.
@export var response_variable: String = "response_text"

# --- Dependencies (from blackboard) ---
var agent_instance # : AgentInstance
var short_term_memory # : ShortTermMemory

# --- State ---
var _action_state = null

func _setup():
	agent_instance = blackboard.get_var("agent_instance")
	short_term_memory = blackboard.get_var("short_term_memory")
	if not agent_instance:
		printerr("GenerateChaplinResponseTask: AgentInstance not found on blackboard!")
	if not short_term_memory:
		printerr("GenerateChaplinResponseTask: ShortTermMemory not found on blackboard!")

func _tick(_delta: float) -> int:
	if not agent_instance or not short_term_memory:
		return BT.Status.FAILURE
	
	# If we are already waiting for a response...
	if is_instance_valid(_action_state):
		if _action_state.is_valid():
			return BT.Status.RUNNING # Still waiting
		else:
			# Finished waiting, get the result.
			var tool_result = _action_state.get_result()
			_action_state = null # Clear state
			
			if tool_result and tool_result.has("response"):
				var generated_text = tool_result.response
				print("Generated response: '", generated_text, "'")
				blackboard.set_var(response_variable, generated_text)
				return BT.Status.SUCCESS
			else:
				printerr("GenerateChaplinResponseTask: SynTree tool failed to return a valid response.")
				return BT.Status.FAILURE

	# --- Construct the message to send to the LLM ---
	var conversation_log = short_term_memory.get_memory("conversation_log", "shared", [])
	var last_few_messages = conversation_log.slice(max(0, conversation_log.size() - 4)) # Get last 4 messages
	
	var history_prompt = ""
	for entry in last_few_messages:
		history_prompt += "%s: %s\n" % [entry.speaker, entry.message]
		
	var prompt_message = "Your persona: " + agent_instance.definition.persona + \
						 "\n\nHere is the recent conversation history:\n" + history_prompt + \
						 "\nBased on your persona, what is your response? Only provide the response text, nothing else."

	# --- Call the SynTree tool to generate a response ---
	var tool_args = {
		"operation": "chat",
		"message": prompt_message,
		"thread_name": "chaplin_conversation" # Use a dedicated thread for generation
	}
	
	print("Generating response for agent: %s" % agent_instance.agent_id)
	_action_state = agent_instance.request_action("SynTree", tool_args)
	
	if is_instance_valid(_action_state) and _action_state.is_valid():
		return BT.Status.RUNNING # The call is async, so we wait
	else:
		printerr("GenerateChaplinResponseTask: Failed to dispatch action to SynTree.")
		return BT.Status.FAILURE

func _generate_name() -> String:
	return "GenerateChaplinResponse" 
