extends Node
class_name PlayerAutoInput

signal auto_input_changed(enabled: bool)
signal configuration_changed(is_available: bool)

const DEFAULT_MIN_INTERVAL := 1.0
# Maximum number of unprocessed payloads held in memory. When the AI is busy
# for a long time (LLM stall, timeout) and new physical inputs arrive, older
# queued entries are dropped so the system always acts on recent board state.
const MAX_PENDING_QUEUE_SIZE := 2

var _is_enabled: bool = false
var _config: Dictionary = {}
var _last_send_time: float = -999.0
var _listener: ExternalInputListener
var _pending_payloads: Array[Dictionary] = []
var _seen_packet_ids: Dictionary = {}

func _ready() -> void:
	Global.connect("scenario_changed", Callable(self, "_on_scenario_changed"))
	_listener = Global.get_external_input_listener()
	if _listener and not _listener.data_received.is_connected(_on_external_data):
		_listener.data_received.connect(_on_external_data)
	_refresh_config()

func is_available() -> bool:
	if _config.is_empty():
		return false
	var mode: String = String(_config.get("character_mode", "")).strip_edges().to_lower()
	var has_character: bool = _config.get("character", "") != "" or mode == "dynamic"
	return has_character and _has_any_template()

func is_enabled() -> bool:
	return _is_enabled

## How to name the source of input in a scenario where no human holds a role: the
## sender the scenario configures, e.g. "External Divination". Empty for a scenario
## where a person does choose a character, so a caller can tell the two apart.
func external_sender_name() -> String:
	if not is_available():
		return ""
	return String(_config.get("trigger_sender", "External Divination")).strip_edges()

func set_enabled(enabled: bool, force: bool = false) -> void:
	var target = enabled and is_available()
	if not force and target == _is_enabled:
		return
	_is_enabled = target
	auto_input_changed.emit(_is_enabled)

func force_disable() -> void:
	if _is_enabled:
		_is_enabled = false
		auto_input_changed.emit(false)

func _on_scenario_changed(_name: String) -> void:
	_refresh_config()

func _refresh_config() -> void:
	_config = {}
	_pending_payloads.clear()
	_seen_packet_ids.clear()
	var scenario = Global.get_game_flow_manager().get_current_scenario() if Global.get_game_flow_manager() else {}
	if scenario and scenario.has("player_auto_input"):
		_config = scenario["player_auto_input"]
	var default_enabled: bool = _get_bool(_config.get("enabled_by_default", "false"))
	_is_enabled = false  # reset before set_enabled
	set_enabled(default_enabled, true)
	configuration_changed.emit(is_available())

func _process(_delta: float) -> void:
	_try_submit_next_payload()

func _on_external_data(data: Dictionary) -> void:
	if not is_available() or not _is_enabled:
		return
	var packet_id: String = _packet_id_from_payload(data)
	if packet_id != "" and _seen_packet_ids.has(packet_id):
		return
	if packet_id != "":
		_seen_packet_ids[packet_id] = true
	# Keep only the most recent MAX_PENDING_QUEUE_SIZE packets. If the AI has
	# been stalled (slow LLM / timeout), older queued readings represent physical
	# states that have since changed — acting on them would feel broken in the
	# exhibition. Drop from the front (oldest) to make room for the new one.
	while _pending_payloads.size() >= MAX_PENDING_QUEUE_SIZE:
		var dropped: Dictionary = _pending_payloads.pop_front()
		push_warning("PlayerAutoInput: queue full — dropping stale packet '%s' to make room" % dropped.get("packet_id", "?"))
	var queued: Dictionary = {
		"packet_id": packet_id,
		"payload": data.duplicate(true),
	}
	_pending_payloads.append(queued)
	_try_submit_next_payload()

func _try_submit_next_payload() -> void:
	if not is_available() or not _is_enabled:
		return
	if _pending_payloads.is_empty():
		return
	if _is_ai_busy():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var interval: float = _get_float(_config.get("min_interval", str(DEFAULT_MIN_INTERVAL)), DEFAULT_MIN_INTERVAL)
	if now - _last_send_time < interval:
		return
	var queued: Dictionary = _pending_payloads[0]
	var payload: Dictionary = queued.get("payload", {})
	if payload.is_empty():
		_pending_payloads.pop_front()
		return
	var speaker: String = _select_character_from_payload(payload)
	var text: String = _build_message_from_payload(payload, speaker)
	if text.strip_edges() == "":
		_pending_payloads.pop_front()
		return
	var submitted: bool = false
	if _submission_mode() == "direct_ai":
		submitted = _trigger_ai_directly(text, speaker)
	else:
		submitted = _submit_player_line(text, speaker)
	if submitted:
		_last_send_time = now
		_pending_payloads.pop_front()

func _submission_mode() -> String:
	return String(_config.get("submission_mode", "story_log")).strip_edges().to_lower()

func _trigger_ai_directly(text: String, preferred_speaker: String = "") -> bool:
	var trimmed_text: String = text.strip_edges()
	if trimmed_text == "":
		return false
	var ai_agent = get_tree().get_first_node_in_group("AICharacterAgent")
	if ai_agent == null:
		return false
	if not ai_agent.has_method("trigger_external_response"):
		return false
	var trigger_sender: String = String(_config.get("trigger_sender", "External Divination")).strip_edges()
	return bool(ai_agent.trigger_external_response(trigger_sender, trimmed_text, preferred_speaker))

func _build_message_from_payload(payload: Dictionary, speaker: String) -> String:
	var template: String = _template_for_speaker(speaker)
	if template == "":
		return ""
	var flat = _flatten(payload)
	flat["auto.speaker"] = speaker
	for key in flat.keys():
		template = template.replace("{%s}" % key, str(flat[key]))
	
	# NEW: Inject real Umeno Chaos metrics if available
	var chaos_engine = get_tree().get_first_node_in_group("chaos_engine")
	if chaos_engine:
		var metrics = chaos_engine.get_narrative_mood()
		var params = chaos_engine.get_comfy_parameters()
		# Add specific math tokens
		flat["chaos.alpha"] = params.alpha
		flat["chaos.beta"] = params.beta
		flat["chaos.coherence"] = metrics.coherence
		
		# Replace in template if keys exist
		template = template.replace("{chaos.alpha}", str(params.alpha))
		template = template.replace("{chaos.beta}", str(params.beta))
	
	# Optional oracle lookup
	if template.find("{oracle}") != -1:
		var oracle_value = _resolve_oracle(flat)
		template = template.replace("{oracle}", oracle_value)

	return template

func _select_character_from_payload(payload: Dictionary) -> String:
	var flat: Dictionary = _flatten(payload)
	var character_field: String = String(_config.get("character_field", "")).strip_edges()
	if character_field != "":
		var field_value: String = String(flat.get(character_field, "")).strip_edges()
		if field_value != "":
			return _canonicalize_speaker_name(field_value)

	var mode: String = String(_config.get("character_mode", "")).strip_edges().to_lower()
	if mode == "dynamic":
		var resonance: float = _safe_float(flat.get("resonance", 0.5), 0.5)
		var entropy: float = _safe_float(flat.get("pendulum.entropy", 0.5), 0.5)
		var stability: float = _safe_float(flat.get("pendulum.stability", 0.5), 0.5)
		var crossings: float = _safe_float(flat.get("uwp_traversal.crossings", 0.0), 0.0)
		var primary_bead: String = String(flat.get("beads.primary_concept", flat.get("board.primary_bead", ""))).strip_edges()
		var axis_bias: String = String(flat.get("board.axis_y_bias", "")).strip_edges().to_lower()
		var predicament: String = String(flat.get("matrix_resolution.predicament_family", "")).strip_edges()

		var candidate: String = ""
		if predicament in ["The Mirror That Judges the Frame", "Oscillation Without Resolution"] or (resonance < 0.35 and entropy > 0.6):
			candidate = "The Narrator"
		elif resonance >= 0.75 and stability >= 0.65:
			candidate = "The Seeker"
		elif crossings >= 6.0 or (primary_bead in ["Fount", "Will"] and axis_bias == "centralized"):
			candidate = "The Diviner"
		elif entropy > 0.45 or String(flat.get("turn_packet.echo.echo_omen_cue", "")).strip_edges() != "":
			candidate = "The Echo"
		elif stability < 0.5:
			candidate = "The Diviner"
		else:
			candidate = ["The Narrator", "The Seeker", "The Diviner", "The Echo"][randi() % 4]

		# Cooldown: avoid routing to the same character who just spoke.
		# Rotate through the ensemble so no single voice dominates consecutive turns.
		var last_speaker: String = _get_last_ai_speaker()
		if last_speaker == candidate:
			const ROTATION: Array = ["The Seeker", "The Diviner", "The Echo", "The Narrator"]
			var idx: int = ROTATION.find(candidate)
			if idx >= 0:
				candidate = ROTATION[(idx + 1) % ROTATION.size()]
		return candidate

	return _canonicalize_speaker_name(String(_config.get("character", "")).strip_edges())


func _get_last_ai_speaker() -> String:
	if not Engine.has_singleton("StoryState"):
		return ""
	var ss = Engine.get_singleton("StoryState")
	if ss == null or not ss.has_method("get_state"):
		return ""
	var log: Array = ss.get_state().get("story_log", [])
	var ai_names: Array = ["The Seeker", "The Diviner", "The Echo", "The Narrator"]
	for i in range(log.size() - 1, -1, -1):
		var sender: String = String(log[i].get("sender", "")).strip_edges()
		if sender in ai_names:
			return sender
	return ""

func _template_for_speaker(speaker: String) -> String:
	var normalized: String = String(speaker).strip_edges().to_lower().replace(" ", "_")
	if normalized.begins_with("the_"):
		normalized = normalized.trim_prefix("the_")
	var speaker_key: String = "template_" + normalized
	var specific: String = String(_config.get(speaker_key, "")).strip_edges()
	if specific != "":
		return specific
	return String(_config.get("template", "")).strip_edges()

func _has_any_template() -> bool:
	if String(_config.get("template", "")).strip_edges() != "":
		return true
	for key in _config.keys():
		var key_text: String = String(key)
		if key_text.begins_with("template_") and String(_config.get(key, "")).strip_edges() != "":
			return true
	return false

func _resolve_oracle(flat: Dictionary) -> String:
	var concept_field: String = _config.get("concept_field", "")
	var state_field: String = _config.get("state_field", "")
	if concept_field == "" or state_field == "":
		return ""
	var concept_value: String = flat.get(concept_field, "")
	var state_value: String = flat.get(state_field, "")
	if concept_value == "" or state_value == "":
		return ""
	var manager = Global.get_metaprompt_manager()
	var scenario = Global.get_game_flow_manager().get_current_scenario() if Global.get_game_flow_manager() else {}
	if manager and manager.has_method("consult_oracle"):
		return manager.consult_oracle(concept_value, state_value, scenario)
	return ""

func _submit_player_line(text: String, speaker_override: String = "") -> bool:
	var sessions = get_tree().get_nodes_in_group("game_session")
	if sessions.is_empty():
		return false
	var session = sessions[0]
	if not session:
		return false
	var trimmed_text: String = text.strip_edges()
	if trimmed_text == "":
		return false

	var configured_character: String = str(speaker_override).strip_edges()
	if configured_character == "":
		configured_character = str(_config.get("character", "")).strip_edges()
	configured_character = _canonicalize_speaker_name(configured_character)
	if configured_character == "":
		if not session.has_method("_on_player_input_received"):
			return false
		var sender_id = multiplayer.get_unique_id()
		session._on_player_input_received(sender_id, trimmed_text)
		return true

	var state: Dictionary = StoryState.get_state()
	var story_log: Array = state.get("story_log", [])
	var last_entry: Variant = story_log.back() if not story_log.is_empty() else null
	if typeof(last_entry) == TYPE_DICTIONARY:
		var entry: Dictionary = last_entry
		if entry.get("sender") == configured_character and entry.get("message") == trimmed_text:
			return false

	StoryState.add_log_entry(configured_character, trimmed_text)
	if session.has_method("_emit_session_turn_async"):
		session._emit_session_turn_async(configured_character, trimmed_text, StoryState.get_state().get("current_turn", 0))
	StoryState.advance_turn()
	if session.has_method("set"):
		session.set("current_turn", StoryState.get_state().get("current_turn", 0))
	var sustainability_system = session.get("sustainability_system")
	if sustainability_system and sustainability_system.has_method("set_current_turn"):
		sustainability_system.set_current_turn(int(session.get("current_turn")))
	if session.has_method("update_display_from_story_state"):
		session.update_display_from_story_state()
	return true

func _flatten(dict: Dictionary, prefix: String = "") -> Dictionary:
	var result: Dictionary = {}
	for key in dict.keys():
		var value = dict[key]
		var full_key = key if prefix == "" else "%s.%s" % [prefix, key]
		if typeof(value) == TYPE_DICTIONARY:
			result.merge(_flatten(value, full_key))
		else:
			result[full_key] = value
	return result

func _get_bool(value) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	return String(value).strip_edges().to_lower() in ["true", "1", "yes", "on"]

func _get_float(value, default_value: float) -> float:
	if typeof(value) == TYPE_FLOAT:
		return value
	if typeof(value) == TYPE_INT:
		return float(value)
	var text: String = String(value)
	if text == "":
		return default_value
	return float(text) if text.is_valid_float() else default_value

func _safe_float(value, default_value: float) -> float:
	if typeof(value) == TYPE_FLOAT:
		return value
	if typeof(value) == TYPE_INT:
		return float(value)
	var text: String = String(value).strip_edges()
	if text == "":
		return default_value
	return float(text) if text.is_valid_float() else default_value

func _canonicalize_speaker_name(name: String) -> String:
	var trimmed: String = String(name).strip_edges()
	match trimmed.to_lower():
		"narrator", "the narrator":
			return "The Narrator"
		"seeker", "the seeker":
			return "The Seeker"
		"diviner", "the diviner":
			return "The Diviner"
		"echo", "the echo":
			return "The Echo"
		_:
			return trimmed

func _packet_id_from_payload(payload: Dictionary) -> String:
	if payload.has("window_id"):
		return "window:%s" % str(payload.get("window_id"))
	var source_id: String = str(payload.get("source_id", "")).strip_edges()
	var label: String = str(payload.get("label", "")).strip_edges()
	var timestamp: String = str(payload.get("timestamp", "")).strip_edges()
	if source_id != "" or label != "" or timestamp != "":
		return "src:%s|label:%s|ts:%s" % [source_id, label, timestamp]
	return ""

func _is_ai_busy() -> bool:
	var agent = get_tree().get_first_node_in_group("AICharacterAgent")
	if agent == null:
		return false
	if agent.has_method("is_busy"):
		return bool(agent.call("is_busy"))
	return bool(agent.get("_awaiting_response"))


