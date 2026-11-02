@tool
extends BTAction

"""
Simple conversation task that generates dynamic Chaplin responses about UFOs.
Creates varied responses based on conversation history and turn number.
"""

# --- Request throttling to prevent HTTP collisions ---
var _last_request_time: float = 0.0
const MIN_REQUEST_INTERVAL: float = 2.0  # 2 seconds between requests

func _tick(delta: float) -> int:
	# Get the agent's blackboard
	var bb = get_blackboard()
	if not bb:
		push_error("SimpleConversationTask: No blackboard available")
		return FAILURE
	
	# Get agent context from blackboard
	var agent_instance = bb.get_var("agent_instance", null)
	var short_term_memory = bb.get_var("short_term_memory", null)
	
	if not agent_instance:
		push_error("SimpleConversationTask: No agent_instance in blackboard")
		return FAILURE
		
	if not short_term_memory:
		push_error("SimpleConversationTask: No short_term_memory in blackboard")
		return FAILURE
	
	var agent_id = agent_instance.agent_id
	
	# Check if this agent should speak
	var should_speak = short_term_memory.get_memory("should_speak", agent_id)
	if not should_speak:
		return FAILURE
	
	# Throttle requests to prevent HTTP collisions
	var current_timestamp = Time.get_time_dict_from_system()
	var current_time_float = current_timestamp.hour * 3600.0 + current_timestamp.minute * 60.0 + current_timestamp.second
	
	if current_time_float - _last_request_time < MIN_REQUEST_INTERVAL:
		return RUNNING  # Wait longer
	
	_last_request_time = current_time_float
	
	# Get conversation history to make dynamic responses
	var conversation_log = short_term_memory.get_memory("conversation_log", "shared")
	if not conversation_log:
		conversation_log = []
	
	var turn_number = conversation_log.size()
	
	# Generate dynamic AI response
	var response = await _generate_dynamic_response(agent_instance, turn_number, conversation_log, bb)

	if response.is_empty():
		return FAILURE

	var log_entry = {
		"speaker": agent_id,
		"message": response,
		"timestamp": Time.get_unix_time_from_system(),
		"turn": turn_number
	}

	conversation_log.append(log_entry)
	short_term_memory.set_memory("conversation_log", conversation_log, "shared")

	# Mark that we've spoken
	short_term_memory.set_memory("should_speak", false, agent_id)

	return SUCCESS

func _generate_scripted_response(agent_id: String, turn: int, history: Array) -> String:
	"""Generate pre-scripted responses as primary method (renamed from original function)"""
	var is_believer = agent_id == "agent_chaplin_1" or agent_id == "chaplin_1"
	
	# Different responses based on turn and role
	if is_believer:
		match turn:
			0: return "🎭 *adjusts bowler hat* My dear friend, have you seen those strange lights dancing in the night sky? Like celestial performers in the cosmic circus!"
			1: return "🎪 *gestures excitedly* But surely you must admit, the patterns they make are too deliberate for mere weather phenomena!"
			2: return "✨ *twirls mustache thoughtfully* I've heard tales from farmers - visitors from the stars, walking among the wheat fields like silent movie actors!"
			3: return "🎭 *dramatic pause* What if they're trying to communicate through these sky dances? A universal language of light and motion!"
			4: return "🌟 *leans forward conspiratorially* I say we should welcome them! Imagine the cosmic vaudeville they could teach us!"
			_: return "🎪 *final bow* Perhaps one day we'll join their celestial circus, dancing among the stars themselves!"
	else:
		match turn:
			0: return "🎩 *twirls cane skeptically* Ah, my optimistic friend, but have you considered they might be reflections of our own earthly contraptions?"
			1: return "🤔 *adjusts monocle* Patterns, you say? The human mind is remarkably good at finding patterns where none exist - like seeing faces in clouds!"
			2: return "🎭 *theatrical sigh* Tales from farmers, yes... but farmers also see scarecrows move in the moonlight. The imagination is a powerful thing!"
			3: return "🎨 *mimes looking through telescope* Communication? Or perhaps just the Aurora Borealis putting on a particularly spectacular show?"
			4: return "🎪 *chuckles softly* Welcome them? My dear Chaplin, first we must prove they exist beyond our hopeful hearts!"
			_: return "🎩 *tips hat graciously* Until then, I'll keep watching the skies... with one eyebrow appropriately raised!"
	
	return "🎭 *silent comedy gesture*" 

# ----------------------
# Dynamic response helper
# ----------------------
func _generate_dynamic_response(agent_instance, turn: int, history: Array, blackboard) -> String:
	"""Generate a natural response using SynTree with character context and concrete UFO cases"""
	
	var action_dispatcher = blackboard.get_var("action_dispatcher", null)
	var short_term_memory = blackboard.get_var("short_term_memory", null)
	if not action_dispatcher or not short_term_memory:
		push_error("SimpleConversationTask: Missing dispatcher or memory")
		return ""
	
	var recent_context = ""
	var context_size = min(6, history.size())
	if context_size > 0:
		var recent_messages = history.slice(history.size() - context_size)
		for msg in recent_messages:
	#		var prefix = "You" if msg.speaker == agent_instance.agent_id else "Partner"
	#		recent_context += prefix + ": " + msg.message + "\n"
			recent_context += msg.message + "\n"
	
	var persona = agent_instance.definition.persona
	
	# Build prompt without exposing agent names
	var prompt = """Your persona: %s\n\nRecent conversation:\n%s\nRespond directly to your conversation partner while keeping the conversation dynamic and engaging. Avoid repeating phrases or simply mirroring your partner; advance the discussion. Keep tone natural, minimal metaphors, and stay under 100 words unless context really demands more.""" % [persona, recent_context]
	
	var syntree_args = {
		"operation": "chat",
		"message": prompt,
		"thread_name": "conversation_" + agent_instance.agent_id + "_" + str(Time.get_unix_time_from_system())
	}
	
	var result = await action_dispatcher.dispatch_action(agent_instance.agent_id, "SynTree", syntree_args, "system", [])
	if result and result.has("result") and result.result and result.result.has("response"):
		var text = result.result.response.strip_edges()
		return text
	
	return "" 
