# narrator_agent.gd
# Location: ScenSyn/scripts/agents/narrator_agent.gd
# Phase-3: Minimal behaviour system (no LimboAI yet)

extends Node
class_name NarratorAgent

# Metapunkt opt-in (slot assignment)
const _SLOT_ID := "scensyn.narrator"

# =============================================================
# Phase-3: Minimal behaviour system (no LimboAI yet)
# =============================================================

# Cool-down between narrator decisions (seconds)
const TICK_MIN_INTERVAL := 1.0
var _time_accum := 0.0
var _last_handled_turn := -1

# Simple phase thresholds – can be replaced by BT/state machine later
const PHASE_INTRO_END_TURN := 3
const PHASE_CRISIS_START_TURN := 10

# Add at top
const NarrationFilterScript = preload("res://ScenSyn/scripts/utils/narration_filter.gd")

var _awaiting_response := false

# add constant and helper
const MAX_RETRIES := 4

var _next_attempt_time := 0.0

const MIN_TURN_GAP := 3
var _last_narration_turn := -10

# After existing MIN_TURN_GAP, add new throttling constants and trackers
var MIN_MESSAGES_GAP: int = ProjectSettings.get_setting("scensyn/narrator/min_messages_gap", 2) # non-Narrator messages  
var MIN_SECONDS_GAP: float = ProjectSettings.get_setting("scensyn/narrator/min_seconds_gap", 5.0) # seconds between narrator lines
var _last_narration_time := -1000.0
var _last_narration_log_index := -1

# maximum chars for narrator line (also used in narration_filter)
var MAX_NARRATOR_CHARS: int = ProjectSettings.get_setting("scensyn/narrator/max_chars", 400)

var _bt_player: BTPlayer
var _intent_lines_res = null

# Performance optimization: Cache frequently accessed objects
var _cached_metaprompt_manager = null
var _cached_conv_manager = null
var _cached_game_flow_manager = null
var _cache_refresh_time := 0.0
const CACHE_REFRESH_INTERVAL := 15.0  # Refresh cache every 15 seconds

# Performance optimization: Reduce redundant state checks
var _last_story_log_size := 0
var _last_processed_turn := -1

func _ready():
	add_to_group("Narrator")
	if not StoryState.state_updated.is_connected(_on_state_updated):
		StoryState.state_updated.connect(_on_state_updated)
	# Setup behaviour tree runner (with error handling)
	var bt_resource = load("res://ScenSyn/behavior_trees/narrator_bt.tres")
	if bt_resource:
		_bt_player = BTPlayer.new()
		_bt_player.update_mode = BTPlayer.UpdateMode.MANUAL
		_bt_player.behavior_tree = bt_resource
		var bb := Blackboard.new()
		bb.set_var("narrator_node", self)
		_bt_player.blackboard = bb
		add_child(_bt_player)
		print("[NarratorAgent] Behavior tree loaded successfully")
	else:
		print("[NarratorAgent] ERROR: Failed to load behavior tree, continuing without it")
		_bt_player = null
	
	# Load intent narration lines (with error handling)
	var intent_script = load("res://ScenSyn/scripts/utils/phase_intent_narration.gd")
	if intent_script:
		_intent_lines_res = intent_script.new()
		print("[NarratorAgent] Intent lines loaded successfully")
	else:
		print("[NarratorAgent] ERROR: Failed to load intent lines, continuing without them")
		_intent_lines_res = null
	
	# Add phase transition task to existing behavior tree (temporarily disabled)
	# if _bt_player:
	#	_add_phase_transition_task()
	#	print("[NarratorAgent] Phase transition task added successfully")
	# else:
	#	print("[NarratorAgent] Skipping phase transition task - no behavior tree")
	print("[NarratorAgent] Phase transition task temporarily disabled")
	
	# Initialize performance caches
	_refresh_caches()
	
	print("[NarratorAgent] Ready – LimboAI BT integrated with phase transitions")

func _process(delta: float):
	_time_accum += delta
	
	# Performance optimization: Refresh caches periodically
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _cache_refresh_time > CACHE_REFRESH_INTERVAL:
		_refresh_caches()
		_cache_refresh_time = current_time
	
	if _bt_player == null:
		return  # BT not initialized yet
	if current_time < _next_attempt_time:
		return
	if _time_accum < TICK_MIN_INTERVAL:
		return
	_time_accum = 0.0
	_bt_player.update(delta)

func _on_state_updated(_new_state: Dictionary):
	# Check if we should generate narration based on story updates
	print("[NarratorAgent] _on_state_updated called")
	
	# Performance optimization: Skip if no meaningful changes
	var current_story_log_size = _new_state.get("story_log", []).size()
	var current_turn = _new_state.get("current_turn", 0)
	
	if current_story_log_size == _last_story_log_size and current_turn == _last_processed_turn:
		print("[NarratorAgent] No meaningful state changes, skipping")
		return
	
	_last_story_log_size = current_story_log_size
	_last_processed_turn = current_turn
	
	if not _awaiting_response:
		print("[NarratorAgent] Not awaiting response, checking if should generate narration...")
		# Get current story state and check if we should respond
		var current_state = StoryState.get_state()
		if current_state:
			print("[NarratorAgent] Current story state has ", current_state.get("story_log", []).size(), " log entries")
			print("[NarratorAgent] Current narrative phase: ", current_state.get("current_narrative_phase", "unknown"))
			_maybe_generate_narration("ADVANCE_STORY", current_state)
		else:
			print("[NarratorAgent] WARNING: No current state available")
	else:
		print("[NarratorAgent] Already awaiting response, skipping") 

func _truncate_sentence(text: String) -> String:
	# Keep only first sentence and cap length.
	var limit := int(ProjectSettings.get_setting("scensyn/narrator/max_chars", MAX_NARRATOR_CHARS))
	var first := text.split(".")[0].strip_edges()
	if first == "":
		return ""
	if first.length() > limit:
		first = first.substr(0, limit) + " …"
	return first + "."

func _maybe_generate_narration(intent: String, state: Dictionary, attempt: int = 0, payload := {}):
	# Check if we should generate narration based on current narrative phase
	var current_phase = state.get("current_narrative_phase", "setup")
	if current_phase == "ended":
		# Don't generate narration for ended stories
		return
	
	# Map narrative phases to appropriate narrator intents
	intent = _map_phase_to_intent(current_phase, intent)
	
	# Check group morale
	var morale: int = 0
	morale = StoryState.get_group_morale()
	if morale == 1:
		intent = "GROUP_MORALE_HIGH"
	elif morale == -1:
		intent = "GROUP_MORALE_LOW"
	# Detect context
	var context_key: String = "default"
	if state.has("current_phase"):
		context_key = str(state["current_phase"])
	if state.has("time_of_day"):
		context_key = str(state["time_of_day"])
	if state.has("weather"):
		context_key = str(state["weather"])
	# Gather recent player data for placeholders
	var last_choice: String = ""
	var last_action: String = ""
	var player_name: String = ""
	var story_log_entries: Array = state.get("story_log", [])
	for i in range(story_log_entries.size() - 1, -1, -1):
		if story_log_entries[i].get("sender", "") != "Narrator":
			last_choice = story_log_entries[i].get("message", "")
			player_name = story_log_entries[i].get("sender", "")
			last_action = story_log_entries[i].get("message", "")
			break
	var placeholders = {"last_choice": last_choice, "last_action": last_action, "player_name": player_name}
	var turn: int = int(state.get("current_turn", 0))
	# ---- frequency throttle ----
	var current_time := Time.get_ticks_msec() / 1000.0
	var non_narrator_since := 0
	if _last_narration_log_index >= 0:
		for i in range(_last_narration_log_index + 1, story_log_entries.size()):
			if story_log_entries[i].get("sender", "") != "Narrator":
				non_narrator_since += 1
	else:
		non_narrator_since = story_log_entries.size()
	
	print("[NarratorAgent] Frequency check - non_narrator_since: ", non_narrator_since, ", MIN_MESSAGES_GAP: ", MIN_MESSAGES_GAP)
	print("[NarratorAgent] Time check - time_since_last: ", current_time - _last_narration_time, ", MIN_SECONDS_GAP: ", MIN_SECONDS_GAP)
	print("[NarratorAgent] Intent: ", intent, ", awaiting_response: ", _awaiting_response)
	
	if non_narrator_since < MIN_MESSAGES_GAP and current_time - _last_narration_time < MIN_SECONDS_GAP:
		print("[NarratorAgent] BLOCKED by frequency throttle - not enough messages or time elapsed")
		return
	# --------------------------------
	if intent == "SILENT" or _awaiting_response:
		print("[NarratorAgent] BLOCKED - intent is SILENT or already awaiting response")
		return
	
	print("[NarratorAgent] PROCEEDING with narration generation - all checks passed")
	_awaiting_response = true
	# build recent context
	var recent_context: String = ""
	for entry in story_log_entries.slice(-5, story_log_entries.size()):
		recent_context += "%s: %s\n" % [entry.get("sender", ""), entry.get("message", "")]
	# last narrator text for repetition avoidance
	var last_narrator_text := ""
	for i in range(story_log_entries.size() - 1, -1, -1):
		if story_log_entries[i].get("sender", "") == "Narrator":
			last_narrator_text = story_log_entries[i].get("message", "")
			break
	# Get enhanced metaprompt from MetapromptManager (performance optimized)
	var metaprompt_manager = _cached_metaprompt_manager
	var base_prompt = ""
	if metaprompt_manager:
		# Get AI character list for narrator agent
		var ai_characters = []
		if Network and Network.has_method("get_ai_controlled_character_names"):
			var ai_names = Network.get_ai_controlled_character_names()
			var scenario = _cached_game_flow_manager.get_current_scenario() if _cached_game_flow_manager else {}
			if scenario.has("characters"):
				for character in scenario.characters:
					if character.get("name", "") in ai_names:
						ai_characters.append(character)
		
		# Generate enhanced narrator metaprompt
		metaprompt_manager.generate_narrator_metaprompt(ai_characters)
		base_prompt = metaprompt_manager.get_narrator_metaprompt()
	else:
		# Fallback prompt if metaprompt manager not available
		base_prompt = "You are the Narrator of an interactive story set in Trondheim during an energy crisis."
	
	var prompt: String = base_prompt + "\n\nRespond with a single descriptive sentence (max 350 characters), vary sentence openings, avoid repeating descriptions, and advance the plot.\n\nIMPORTANT: Do NOT include 'Narrator:' prefix in your response - just provide the narration content directly.\n\nRecent context:\n" + recent_context
	if last_narrator_text != "":
		prompt += "\nLast narration:\n" + last_narrator_text + "\nAvoid repeating imagery or phrasing from it.\n\nProvide narration that "
	else:
		prompt += "\nProvide narration that "
	if intent == "EVENT_NARRATION" and payload.has("line"):
		prompt += payload["line"]
	else:
		var line = ""
		if _intent_lines_res:
			line = _intent_lines_res.get_random_line(intent, context_key, placeholders)
			if line == "":
				line = _intent_lines_res.get_random_line("ADVANCE_STORY", "default", placeholders)
		if line == "":
			line = "advances the story."
		prompt += line
	var conv_manager = _cached_conv_manager
	if not conv_manager:
		print("[NarratorAgent] ERROR: Conversation manager not available")
		_awaiting_response = false
		return
	if conv_manager.is_busy():
		print("[NarratorAgent] Conversation manager is busy, retrying later")
		_awaiting_response = false
		_next_attempt_time = Time.get_ticks_msec() / 1000.0 + 3.0  # wait 3 seconds before retry
		return
	
	print("[NarratorAgent] Sending AI request with prompt length: ", prompt.length())
	var thread_name := "narrator_" + str(get_instance_id())
	print("[NarratorAgent] Using thread name: ", thread_name)
	var response: Dictionary = {}
	# Opt-in: if user assigned a Metapunkt agent to scensyn.narrator, route via Metapunkt tool call (policy/audit + agent identity).
	var mp_agent_id := _get_metapunkt_assigned_agent_id(_SLOT_ID)
	if not mp_agent_id.is_empty():
		var mp_resp := await _metapunkt_chat(mp_agent_id, prompt, thread_name)
		# Normalize to ConversationManager-like envelope for existing code.
		if mp_resp.get("success", false) == true:
			response = {"success": true, "response": str(mp_resp.get("response", ""))}
		else:
			response = {"success": false, "error": str(mp_resp.get("error", "Metapunkt chat failed"))}
	else:
		response = await conv_manager.chat(prompt, thread_name)
	print("[NarratorAgent] AI response received. Success: ", response.success)
	if response.success:
		var text: String = str(response.response)
		print("[NarratorAgent] Raw AI response: ", text)
		
		# Remove "Narrator:" prefix if AI included it (since we add it automatically)
		if text.begins_with("Narrator:"):
			text = text.substr(9).strip_edges()
			print("[NarratorAgent] Removed 'Narrator:' prefix: ", text)
		
		text = _truncate_sentence(text)
		print("[NarratorAgent] After truncation: ", text)
		text = NarrationFilter.clean(text, state)
		print("[NarratorAgent] After filtering: ", text)
		if text != "":
			print("[NarratorAgent] Adding to story log: ", text)
			StoryState.add_log_entry("Narrator", text)
			_last_narration_time = current_time
			_last_narration_log_index = story_log_entries.size()
			_last_narration_turn = turn
			_awaiting_response = false
			print("[NarratorAgent] Successfully added narrator content to story log")
			return
		else:
			print("[NarratorAgent] WARNING: Filtered text is empty, not adding to story log")
	else:
		print("[NarratorAgent] AI response failed: ", response.get("error", "Unknown error"))
	
	# Handle retries only if response failed
	if not response.success:
		var err_str := str(response.get("error", "Unknown error"))
		print("[NarratorAgent] AI error (attempt", attempt, "):", err_str)
		if err_str.find("busy") != -1 and attempt < MAX_RETRIES:
			_awaiting_response = false
			await get_tree().create_timer(1.5 * (attempt + 1)).timeout
			_maybe_generate_narration(intent, state, attempt + 1)
			return
	
	_awaiting_response = false 

func _get_metapunkt_assigned_agent_id(slot_id: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return ""
	var host := tree.root.get_node_or_null("MetapunktAppHost")
	if not host or not (host as Object).has_method("get_slot_assignments"):
		return ""
	var m_any: Variant = (host as Object).call("get_slot_assignments")
	if typeof(m_any) != TYPE_DICTIONARY:
		return ""
	var m: Dictionary = m_any
	return str(m.get(slot_id, "")).strip_edges()

func _find_metapunkt_endpoint() -> Object:
	# Runtime Tools scene embeds Metapunkt panel; editor plugin does as well.
	# Find it by node name to avoid hard-coded paths.
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	var n: Node = tree.root.find_child("MetapunktEndpointHandler", true, false)
	return n as Object

func _metapunkt_chat(agent_id: String, prompt: String, thread_name: String) -> Dictionary:
	var ep := _find_metapunkt_endpoint()
	if not ep or not ep.has_method("call_tool"):
		return {"success": false, "error": "MetapunktEndpointHandler not available (open Tools→Metapunkt or ensure Metapunkt is running)"}
	var args := {"operation": "chat", "message": prompt, "thread_name": thread_name}
	var AuthContextUtilsScript = preload("res://addons/synesyn_core/scripts/auth_context_utils.gd")
	# Narrator is a system-like actor; keep identity stable for audit/provenance.
	var user_id := AuthContextUtilsScript.get_user_id("scensyn", "narrator")
	var scopes: Array = AuthContextUtilsScript.get_scopes("scensyn")
	var env_any: Variant = await ep.call("call_tool", agent_id, "SynTree", args, user_id, scopes)
	if typeof(env_any) != TYPE_DICTIONARY:
		return {"success": false, "error": "Metapunkt tool call returned invalid result"}
	var env: Dictionary = env_any
	if not (env.get("ok", false) == true):
		var err_obj: Variant = env.get("error_obj")
		if typeof(err_obj) == TYPE_DICTIONARY:
			return {"success": false, "error": str((err_obj as Dictionary).get("message", env.get("error", "Tool error")))}
		return {"success": false, "error": str(env.get("error", "Tool error"))}
	var res_any: Variant = env.get("result")
	if typeof(res_any) != TYPE_DICTIONARY:
		return {"success": false, "error": "SynTree tool returned invalid result payload"}
	var res: Dictionary = res_any
	if res.get("success", false) == true:
		return {"success": true, "response": str(res.get("response", ""))}
	return {"success": false, "error": str(res.get("error", "SynTree tool chat failed"))}

func _refresh_caches():
	"""Performance optimization: Cache frequently accessed objects"""
	_cached_metaprompt_manager = Global.get_metaprompt_manager()
	_cached_conv_manager = Global.get_conversation_manager()
	_cached_game_flow_manager = Global.get_game_flow_manager()

# Performance monitoring functions
func get_performance_stats() -> Dictionary:
	"""Get performance statistics for monitoring"""
	return {
		"awaiting_response": _awaiting_response,
		"last_narration_time": _last_narration_time,
		"cache_age": Time.get_ticks_msec() / 1000.0 - _cache_refresh_time,
		"behavior_tree_active": _bt_player != null,
		"intent_lines_loaded": _intent_lines_res != null
	}

# Add phase transition task to behavior tree
func _add_phase_transition_task():
	"""
	Programmatically add the AdvanceStoryPhaseTask to the existing behavior tree
	"""
	if not _bt_player or not _bt_player.behavior_tree:
		print("[NarratorAgent] Cannot add phase transition task - no behavior tree")
		return
	
	# Create and configure the phase transition task
	var phase_task = preload("res://ScenSyn/scripts/limbo_tasks/advance_story_phase_task.gd").new()
	
	# Add to the behavior tree's root sequence
	var root_task = _bt_player.behavior_tree.root_task
	if root_task and root_task.has_method("add_child"):
		root_task.add_child(phase_task)
		print("[NarratorAgent] Added phase transition task to behavior tree")
	else:
		print("[NarratorAgent] Could not add phase transition task - root task doesn't support children")

# Handle client-suggested phase transitions
func handle_phase_transition_suggestion(suggested_phase: String, reason: String):
	"""
	Handle phase transition suggestions from clients
	"""
	print("[NarratorAgent] Handling phase transition suggestion: ", suggested_phase, " (reason: ", reason, ")")
	
	# Create a temporary phase transition task to handle the suggestion
	var phase_task = preload("res://ScenSyn/scripts/limbo_tasks/advance_story_phase_task.gd").new()
	phase_task.handle_client_suggestion(suggested_phase, reason)

# Map narrative phases to appropriate narrator intents
func _map_phase_to_intent(current_phase: String, original_intent: String) -> String:
	"""
	Map current narrative phase to appropriate narrator intent
	"""
	# If we already have a specific intent, use it
	if original_intent != "SILENT" and original_intent != "":
		return original_intent
	
	# Map phase to intent
	match current_phase:
		"setup":
			return "SETUP_SCENE"
		"incident":
			return "INCIDENT_BEAT"
		"rising":
			return "RISING_TENSION"
		"climax":
			return "CLIMAX_BEAT"
		"resolution":
			return "RESOLUTION_BEAT"
		"ended":
			return "SILENT"  # Don't narrate ended stories
		_:
			return "ADVANCE_STORY"  # Default fallback
 
