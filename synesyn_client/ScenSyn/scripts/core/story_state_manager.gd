# story_state_manager.gd
# Location: ScenSyn/scripts/core/story_state_manager.gd
# Add this script as an Autoload singleton named `StoryStateManager` in ProjectSettings > AutoLoad.
# It provides a single source of truth for narrative state that all gameplay and network
# systems can query or update.  Phase-1: minimal API – will be expanded in later phases.

extends Node
class_name StoryStateManager

# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------
signal state_updated(new_state : Dictionary)
signal turn_advanced(new_turn : int)
signal phase_changed(new_phase : String)
signal narrative_phase_changed(new_phase : String)
signal event_triggered(event_id, payload)
signal visual_presentation_update(ai_response : Dictionary)  # New: For story_stage integration
signal scenario_continuity_updated(continuity_state : Dictionary)

# -----------------------------------------------------------------------------
# Narrative phase constants
# -----------------------------------------------------------------------------
enum NarrativePhase {
	SETUP,
	INCIDENT,
	RISING,
	CLIMAX,
	RESOLUTION,
	ENDED
}

const NARRATIVE_PHASE_NAMES = {
	NarrativePhase.SETUP: "setup",
	NarrativePhase.INCIDENT: "incident", 
	NarrativePhase.RISING: "rising",
	NarrativePhase.CLIMAX: "climax",
	NarrativePhase.RESOLUTION: "resolution",
	NarrativePhase.ENDED: "ended"
}

# -----------------------------------------------------------------------------
# Internal state container
# -----------------------------------------------------------------------------
var _state : Dictionary = {
	"current_turn": 0,
	"current_phase": "introduction",
	"story_log": [],              # Array of {sender, message}
	"characters": {},             # name -> data dict
	"unresolved_challenges": [], # Array of strings
	"player_choices": [],          # Array of {turn, player, choice}
	"current_narrative_phase": "setup",  # Current narrative phase
	"turn_in_phase": 0,           # Turns spent in current phase
	"phase_transition_readiness": 0.0,  # 0.0-1.0 readiness for next phase
	"scenario_continuity": {},
	"suggested_narrative_phase": "",
	"memory_context": {},
	"continuity_prompt_cues": {}
}

var _event_queue := []
var _inactive_turns: int = 0
var _last_action_turn: int = 0

var _AUTOSAVE_DIR: String = RuntimeConfig.get_scensyn_story_log_dir()
var _autosave_timer: Timer = null
var _autosave_dirty: bool = false
var _autosave_session_id: String = ""

# Add sustainability state
var _sustainability: Dictionary = {
	"energy_level": 100,
	"resource_status": "stable"
}
var _current_dilemmas: Array = []

# -----------------------------------------------------------------------------
# Automatic narrative phase progression
# -----------------------------------------------------------------------------

# Minimum turns before we start considering an automatic transition
const _MIN_TURNS_PER_PHASE := 2

# Hard upper-bounds to force a transition if nothing else does it first
const _MAX_TURNS_PER_PHASE := {
	"setup": 4,
	"incident": 5,
	"rising": 6,
	"climax": 3,
	"resolution": 3
}

# Heuristic keyword table (quick copy of the task version). If any of these appear
# in the last three log lines we treat it as a narrative cue to move on.
const _TRANSITION_KEYWORDS := {
	"setup_to_incident": ["crisis", "problem", "challenge", "urgent", "emergency", "conflict"],
	"incident_to_rising": ["decide", "choose", "options", "what if", "consider", "debate"],
	"rising_to_climax": ["vote", "decision", "agree", "consensus", "final", "choose now"],
	"climax_to_resolution": ["decided", "chosen", "resolved", "outcome", "result"],
	"resolution_to_ended": ["complete", "finished", "end", "conclusion", "summary", "done"]
}

func _ready():
	if not _state.has("story_log"):
		_state["story_log"] = []
	_state = _state
	_autosave_session_id = str(Time.get_unix_time_from_system())
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 3.0
	_autosave_timer.one_shot = true
	_autosave_timer.timeout.connect(_flush_autosave)
	add_child(_autosave_timer)
	print("[StoryState] autosave: initialised (session_id=%s, dir=%s)" % [
		_autosave_session_id,
		ProjectSettings.globalize_path(_AUTOSAVE_DIR)])
	
# -----------------------------------------------------------------------------
# Basic accessors
# -----------------------------------------------------------------------------
func get_state() -> Dictionary:
	_state["inactive_turns"] = get_inactive_turns()
	# Only expose the sustainability block for that Story Catalyst Collection.
	if Global and Global.current_collection_id == "sustainability":
		_state["sustainability"] = get_sustainability()
	elif _state.has("sustainability"):
		_state.erase("sustainability")
	_state["dilemmas"] = get_current_dilemmas()
	return _state

func get_scenario_continuity_state() -> Dictionary:
	var value: Variant = _state.get("scenario_continuity", {})
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

func set_scenario_continuity_state(continuity_state: Dictionary, merge_unresolved_challenges: bool = true):
	if typeof(continuity_state) != TYPE_DICTIONARY:
		return
	_state["scenario_continuity"] = continuity_state.duplicate(true)
	_state["continuity_prompt_cues"] = continuity_state.get("prompt_cues", {}).duplicate(true) if typeof(continuity_state.get("prompt_cues", {})) == TYPE_DICTIONARY else {}
	var state_patch_any: Variant = continuity_state.get("state_patch", {})
	if typeof(state_patch_any) == TYPE_DICTIONARY:
		var state_patch: Dictionary = state_patch_any
		_state["suggested_narrative_phase"] = str(state_patch.get("current_narrative_phase_hint", "")).strip_edges()
		var memory_ctx_any: Variant = state_patch.get("memory_context", {})
		_state["memory_context"] = memory_ctx_any.duplicate(true) if typeof(memory_ctx_any) == TYPE_DICTIONARY else {}
		if merge_unresolved_challenges:
			var existing: Array = _state.get("unresolved_challenges", []) as Array
			var merged: Array = existing.duplicate()
			var incoming_any: Variant = state_patch.get("unresolved_challenges", [])
			var incoming: Array = incoming_any if typeof(incoming_any) == TYPE_ARRAY else []
			for item in incoming:
				var text := str(item).strip_edges()
				if text != "" and not merged.has(text):
					merged.append(text)
			_state["unresolved_challenges"] = merged
	emit_signal("scenario_continuity_updated", _state["scenario_continuity"])
	emit_signal("state_updated", _state)

func set_state(new_state : Dictionary):
	_state = new_state.duplicate(true)
	emit_signal("state_updated", _state)

# -----------------------------------------------------------------------------
# Turn / phase helpers
# -----------------------------------------------------------------------------
func advance_turn():
	_state["current_turn"] += 1
	increment_phase_turn()
	_maybe_advance_narrative_phase()  # Automatic phase progression check
	emit_signal("turn_advanced", _state["current_turn"])
	emit_signal("state_updated", _state)

func set_phase(phase : String):
	if _state["current_phase"] == phase:
		return
	_state["current_phase"] = phase
	emit_signal("phase_changed", phase)
	emit_signal("state_updated", _state)

# -----------------------------------------------------------------------------
# Narrative phase helpers
# -----------------------------------------------------------------------------
func set_narrative_phase(phase : String):
	if _state["current_narrative_phase"] == phase:
		return
	_state["current_narrative_phase"] = phase
	_state["turn_in_phase"] = 0  # Reset turn counter for new phase
	_state["phase_transition_readiness"] = 0.0  # Reset readiness
	emit_signal("narrative_phase_changed", phase)
	emit_signal("state_updated", _state)

func get_narrative_phase() -> String:
	return _state["current_narrative_phase"]

func increment_phase_turn():
	_state["turn_in_phase"] += 1

func get_turn_in_phase() -> int:
	return _state["turn_in_phase"]

func get_current_turn() -> int:
	"""Get the current turn number"""
	return _state.get("current_turn", 0)

func get_phase_readiness() -> float:
	return _state["phase_transition_readiness"]

func set_phase_readiness(readiness : float):
	_state["phase_transition_readiness"] = clamp(readiness, 0.0, 1.0)
	emit_signal("state_updated", _state)

# -----------------------------------------------------------------------------
# Log helpers
# -----------------------------------------------------------------------------
func add_log_entry(sender : String, message : String):
	# Normalize trailing newlines only (preserve intended paragraph spacing inside message)
	var normalized_message := String(message)
	while normalized_message.ends_with("\n"):
		normalized_message = normalized_message.substr(0, normalized_message.length() - 1)

	# Guard against immediate duplicates
	var existing_log : Array = _state.get("story_log", [])
	if not existing_log.is_empty():
		var last_entry : Dictionary = existing_log.back()
		var last_sender := String(last_entry.get("sender", ""))
		var last_message := String(last_entry.get("message", ""))
		while last_message.ends_with("\n"):
			last_message = last_message.substr(0, last_message.length() - 1)
		if last_sender == sender and last_message == normalized_message:
			return

	# Prevent duplicate Narrator "Welcome to ..." entries in a small recent window
	if sender == "Narrator" and normalized_message.find("Welcome to") != -1:
		var start_idx: int = max(0, existing_log.size() - 5)
		for i in range(existing_log.size() - 1, start_idx - 1, -1):
			var e : Dictionary = existing_log[i]
			var prev_sender := String(e.get("sender", ""))
			var prev_message := String(e.get("message", ""))
			while prev_message.ends_with("\n"):
				prev_message = prev_message.substr(0, prev_message.length() - 1)
			if prev_sender == "Narrator" and prev_message == normalized_message:
				return

	var log_entry = {"sender": sender, "message": normalized_message}
	_state["story_log"].append(log_entry)
	if sender != "Narrator":
		_last_action_turn = _state["current_turn"]
		_inactive_turns = 0
		# Clear dilemmas once a real action is taken
		if not _current_dilemmas.is_empty():
			clear_dilemmas()
	else:
		_inactive_turns += 1
	
	var ai_response: Dictionary = {
		"character_name": sender,
		"message": normalized_message,
		"timestamp": Time.get_unix_time_from_system(),
		"timestamp_us": Time.get_ticks_usec()
	}
	emit_signal("visual_presentation_update", ai_response)
	_mark_autosave_dirty()
	emit_signal("state_updated", _state)
	# Push the updated log to all connected clients so every peer stays in sync.
	if Network and Network.is_server() and not Network.get_connected_peers().is_empty():
		Network.rpc("sync_story_state", _state)

func get_recent_log(max_items := 5) -> Array:
	var story_log_entries: Array = _state["story_log"]
	return story_log_entries.slice(max(story_log_entries.size() - max_items, 0), story_log_entries.size())

# -----------------------------------------------------------------------------
# Character helpers (minimal for now)
# -----------------------------------------------------------------------------
func update_character(char_name : String, data : Dictionary):
	_state["characters"][char_name] = data.duplicate(true)
	emit_signal("state_updated", _state)

func get_character(char_name : String) -> Dictionary:
	return _state["characters"].get(char_name, {})

# -----------------------------------------------------------------------------
# Challenge / choice helpers (stubs – expand later)
# -----------------------------------------------------------------------------
func add_challenge(text : String):
	_state["unresolved_challenges"].append(text)
	emit_signal("state_updated", _state)

func add_player_choice(turn : int, player : String, choice : String):
	_state["player_choices"].append({"turn": turn, "player": player, "choice": choice})
	_last_action_turn = turn
	_inactive_turns = 0
	# Clear dilemmas once a real choice is made
	if not _current_dilemmas.is_empty():
		clear_dilemmas()
	emit_signal("state_updated", _state)

# -----------------------------------------------------------------------------
# Reset – useful for starting new sessions
# -----------------------------------------------------------------------------
func reset():
	_state = {
		"current_turn": 0,
		"current_phase": "introduction",
		"story_log": [],
		"characters": {},
		"unresolved_challenges": [],
		"player_choices": [],
		"current_narrative_phase": "setup",
		"turn_in_phase": 0,
		"phase_transition_readiness": 0.0,
		"scenario_continuity": {},
		"suggested_narrative_phase": "",
		"memory_context": {},
		"continuity_prompt_cues": {}
	}
	emit_signal("state_updated", _state)

# Event system
func trigger_event(event_id: String, payload: Dictionary = {}):
	_event_queue.append({"id": event_id, "payload": payload})
	emit_signal("event_triggered", event_id, payload)

func consume_event(event_id: String) -> Dictionary:
	# Returns and removes the first matching event, or empty dict
	for i in range(_event_queue.size()):
		if _event_queue[i]["id"] == event_id:
			var ev = _event_queue[i]
			_event_queue.remove_at(i)
			return ev["payload"]
	return {}

# Group morale: -1 = low, 0 = neutral, 1 = high
func get_group_morale() -> int:
	var story_log_entries: Array = _state.get("story_log", []) as Array
	if story_log_entries.size() == 0:
		return 0
	var recent: Array = story_log_entries.slice(-5, story_log_entries.size()) as Array
	var pos = 0
	var neg = 0
	for entry in recent:
		var msg = String(entry.get("message", "")).to_lower()
		if _contains_any_keyword(msg, ["cheer", "victory", "optimism", "confidence", "celebrate", "encourage", "unity", "success", "hope", "applause", "progress", "inspire"]):
			pos += 1
		elif _contains_any_keyword(msg, ["defeat", "loss", "frustration", "doubt", "tension", "fatigue", "resignation", "hopeless", "stall", "discourage", "failure", "regret"]):
			neg += 1
	if pos >= 3:
		return 1
	elif neg >= 3:
		return -1
	return 0

func get_inactive_turns() -> int:
	return _state["current_turn"] - _last_action_turn

func get_sustainability() -> Dictionary:
	return _sustainability

func set_sustainability(data: Dictionary):
	for k in data.keys():
		_sustainability[k] = data[k]

func set_current_dilemmas(dilemmas: Array):
	_current_dilemmas = dilemmas
	print("StoryState: New dilemmas set. Count: ", dilemmas.size())
	emit_signal("state_updated", get_state())

func get_current_dilemmas() -> Array:
	return _current_dilemmas

func clear_dilemmas():
	_current_dilemmas.clear()
	print("StoryState: Dilemmas cleared.")
	emit_signal("state_updated", get_state())

func _maybe_advance_narrative_phase():
	var current_phase: String = _state.get("current_narrative_phase", "setup")
	if current_phase == "ended":
		return  # Nothing beyond the end.

	var turn_in_phase: int = _state.get("turn_in_phase", 0)
	var readiness: float = _state.get("phase_transition_readiness", 0.0)

	# Next-phase lookup table
	var next_phase_map := {
		"setup": "incident",
		"incident": "rising",
		"rising": "climax",
		"climax": "resolution",
		"resolution": "ended"
	}
	var next_phase: String = String(next_phase_map.get(current_phase, ""))
	if next_phase == "":
		return  # Should not happen but be safe.

	var should_transition := false

	# 1) AI / external readiness suggestion
	if readiness >= 0.6:
		should_transition = true
	
	# 2) Forced by upper-bound turns
	var max_turns: int = int(_MAX_TURNS_PER_PHASE.get(current_phase, 6))
	if turn_in_phase >= max_turns:
		should_transition = true

	# 3) Heuristic keyword detection (only if not already decided)
	if not should_transition and turn_in_phase >= _MIN_TURNS_PER_PHASE:
		var key = current_phase + "_to_" + next_phase
		if _has_transition_keywords(key):
			should_transition = true

	if should_transition:
		var from_phase := current_phase
		set_narrative_phase(next_phase)
		# Inform any listeners explicitly (redundant but convenient)
		trigger_event("phase_transition", {
			"from": from_phase,
			"to": next_phase,
			"turn": _state.get("current_turn", 0)
		})

func _has_transition_keywords(transition_type: String) -> bool:
	var keywords: Array = _TRANSITION_KEYWORDS.get(transition_type, []) as Array
	if keywords.is_empty():
		return false
	var story_log_entries: Array = _state.get("story_log", []) as Array
	if story_log_entries.size() < 3:
		return false
	var recent: Array = story_log_entries.slice(-3) as Array
	for entry in recent:
		var msg: String = String(entry.get("message", "")).to_lower()
		for kw in keywords:
			if msg.find(kw) != -1:
				return true
	return false

func _contains_any_keyword(text: String, keywords: Array) -> bool:
	"""Helper function to check if text contains any of the given keywords"""
	for keyword in keywords:
		if text.find(keyword) != -1:
			return true
	return false

# ── Scene-independent auto-save ────────────────────────────────────────
func _mark_autosave_dirty() -> void:
	_autosave_dirty = true
	if _autosave_timer == null:
		print("[StoryState] autosave: timer is null — recreating")
		_autosave_timer = Timer.new()
		_autosave_timer.wait_time = 3.0
		_autosave_timer.one_shot = true
		_autosave_timer.timeout.connect(_flush_autosave)
		add_child(_autosave_timer)
	if _autosave_timer.is_stopped():
		_autosave_timer.start()

func _flush_autosave() -> void:
	if not _autosave_dirty:
		return
	_autosave_dirty = false
	var log_entries: Array = _state.get("story_log", [])
	if log_entries.is_empty():
		return
	var timestamped_entries: Array = []
	for entry in log_entries:
		var e: Dictionary = entry.duplicate() if typeof(entry) == TYPE_DICTIONARY else {"message": str(entry)}
		if not e.has("timestamp"):
			var now_dict := Time.get_datetime_dict_from_system()
			e["timestamp"] = "%04d-%02d-%02d %02d:%02d:%02d" % [
				now_dict["year"], now_dict["month"], now_dict["day"],
				now_dict["hour"], now_dict["minute"], now_dict["second"]]
		if not e.has("timestamp_us"):
			e["timestamp_us"] = Time.get_ticks_usec()
		timestamped_entries.append(e)
	var abs_dir := ProjectSettings.globalize_path(_AUTOSAVE_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		var err := DirAccess.make_dir_recursive_absolute(abs_dir)
		if err != OK:
			print("[StoryState] autosave: failed to create dir %s (err %d)" % [abs_dir, err])
			return
	var stem := _autosave_file_stem()
	var abs_path := abs_dir.path_join(stem + ".json")
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(timestamped_entries, "  "))
		f.close()
		print("[StoryState] autosave: saved %d entries to %s" % [timestamped_entries.size(), abs_path])
	else:
		var open_err := FileAccess.get_open_error()
		print("[StoryState] autosave: FileAccess.open failed for %s (err %d)" % [abs_path, open_err])

func _autosave_file_stem() -> String:
	var scenario_slug := "session"
	if Global and Global.has_method("get_game_flow_manager"):
		var gfm = Global.get_game_flow_manager()
		if gfm and gfm.has_method("get_scenario_name"):
			var sn := str(gfm.get_scenario_name()).strip_edges()
			if not sn.is_empty():
				scenario_slug = sn.to_lower().replace(" ", "-")
	var now := Time.get_datetime_dict_from_system()
	var date_str := "%04d-%02d-%02d_%02d%02d" % [now["year"], now["month"], now["day"], now["hour"], now["minute"]]
	return "%s_%s_%s" % [scenario_slug, date_str, _autosave_session_id]

# Allow external systems (e.g. the LLM wrapper) to suggest readiness
func set_phase_transition_readiness(value: float):
	set_phase_readiness(value)
	_maybe_advance_narrative_phase() 
