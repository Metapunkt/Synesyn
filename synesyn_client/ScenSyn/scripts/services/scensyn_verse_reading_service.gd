extends Node
class_name ScenSynVerseReadingService

## Scenario-agnostic verse reading service.
## Fetches composed readings from the Hub verse engine when turns arrive,
## stores the result for consumption by the metaprompt manager and
## AI character agent, and runs a heartbeat timer during lulls.

signal verse_reading_available(reading_data: Dictionary)
signal heartbeat_rumination_available(speaker: String, text: String)
signal seekers_journey_paragraph_ready(paragraph: String)

var _hub = null
var _latest_reading: Dictionary = {}
var _latest_character_prompts: Dictionary = {}
var _latest_vis_story_context: Dictionary = {}
var _past_readings: Array = []
var _seekers_journey_paragraphs: Array = []
var _heartbeat_timer: Timer
var _heartbeat_interval_s: float = 90.0
var _verse_enabled: bool = false
var _fetch_in_progress: bool = false
var _reader_character: String = ""
var _heartbeat_speaker: String = ""

func configure(hub, scenario: Dictionary) -> void:
	_hub = hub
	var vs_cfg: Dictionary = _get_verse_config(scenario)
	var enabled_val: String = str(vs_cfg.get("enabled", "false")).strip_edges().to_lower()
	_verse_enabled = enabled_val == "true" or enabled_val == "1"
	_heartbeat_interval_s = float(vs_cfg.get("heartbeat_interval_s", 90.0))
	_reader_character = str(vs_cfg.get("reader_character", "")).strip_edges()
	_heartbeat_speaker = str(vs_cfg.get("heartbeat_speaker", "")).strip_edges()
	if _verse_enabled:
		print("[VerseReadingService] Verse system enabled. Reader: %s, Heartbeat speaker: %s, Interval: %ss" % [_reader_character, _heartbeat_speaker, str(_heartbeat_interval_s)])
	_setup_heartbeat_timer()

func is_enabled() -> bool:
	return _verse_enabled

func get_reader_character() -> String:
	return _reader_character

func get_heartbeat_speaker() -> String:
	return _heartbeat_speaker

func get_latest_reading() -> Dictionary:
	return _latest_reading.duplicate(true) if not _latest_reading.is_empty() else {}

func get_latest_character_prompts() -> Dictionary:
	return _latest_character_prompts.duplicate(true) if not _latest_character_prompts.is_empty() else {}

func get_latest_vis_story_context() -> Dictionary:
	return _latest_vis_story_context.duplicate(true) if not _latest_vis_story_context.is_empty() else {}

func has_reading_for_current_turn() -> bool:
	return not _latest_reading.is_empty()

func get_seekers_journey_paragraphs() -> Array:
	return _seekers_journey_paragraphs.duplicate()

func on_external_input(data: Dictionary) -> void:
	if not _verse_enabled or _hub == null:
		return
	if _fetch_in_progress:
		return
	var odu_name := str(_deep_get(data, "odu", _deep_get(data, "matrix_resolution.odu_name", ""))).strip_edges()
	if odu_name.is_empty():
		return

	_fetch_in_progress = true
	_restart_heartbeat_timer()

	var resonance := float(_deep_get(data, "resonance", 0.5))
	var complement_odu := str(_deep_get(data, "matrix_resolution.complementary_odu", _deep_get(data, "turn_packet.echo.complementary_odu", ""))).strip_edges()
	var stability := float(_deep_get(data, "uwp_traversal.stability", _deep_get(data, "pendulum.stability", 0.5)))
	var crossings := int(float(_deep_get(data, "uwp_traversal.crossings", 0)))
	var turn_seed := str(_deep_get(data, "window_id", str(Time.get_unix_time_from_system())))

	var turn_context := _build_turn_context(data)

	var result: Dictionary = await _hub.scensyn_verse_character_prompts(
		odu_name, turn_context, resonance, complement_odu,
		stability, crossings, turn_seed,
	)

	if bool(result.get("ok", false)):
		_latest_reading = result.get("reading", {})
		_latest_character_prompts = result.get("character_prompts", {})
		_latest_vis_story_context = result.get("vis_story_context", {})
		_past_readings.append(_latest_reading.duplicate(true))
		if _past_readings.size() > 64:
			_past_readings = _past_readings.slice(_past_readings.size() - 64)
		print("[VerseReadingService] Reading fetched for %s (length: %s)" % [odu_name, str(_latest_reading.get("reading_length", "?"))])
		verse_reading_available.emit(_latest_reading)
		_fetch_seekers_journey(odu_name, turn_context, resonance, complement_odu, stability, crossings, turn_seed)
	else:
		var err_info = result.get("error", "unknown")
		print("[VerseReadingService] Hub verse request failed for %s: %s" % [odu_name, str(err_info)])
		if typeof(err_info) == TYPE_DICTIONARY:
			var detail = err_info.get("body", "")
			if typeof(detail) == TYPE_DICTIONARY:
				print("[VerseReadingService]   detail: %s" % str(detail.get("detail", "")))
			elif typeof(detail) == TYPE_STRING and not detail.is_empty():
				print("[VerseReadingService]   body: %s" % detail)

	_fetch_in_progress = false

func _fetch_seekers_journey(odu_name: String, turn_context: Dictionary, resonance: float, complement_odu: String, stability: float, crossings: int, turn_seed: String) -> void:
	if _hub == null:
		return
	var last_paragraphs: Array = _seekers_journey_paragraphs.slice(max(0, _seekers_journey_paragraphs.size() - 5))
	var turn_number := _seekers_journey_paragraphs.size() + 1
	var result: Dictionary = await _hub.scensyn_verse_seekers_journey_prompt(
		odu_name, turn_context, last_paragraphs, turn_number,
		resonance, complement_odu, stability, crossings, turn_seed,
	)
	if bool(result.get("ok", false)):
		var prompt_data: Dictionary = result.get("journey_prompt", {})
		if not prompt_data.is_empty():
			var paragraph := await _generate_journey_paragraph(prompt_data)
			if not paragraph.is_empty():
				_seekers_journey_paragraphs.append(paragraph)
				print("[VerseReadingService] Seeker's Journey paragraph %d generated" % turn_number)
				seekers_journey_paragraph_ready.emit(paragraph)

func _generate_journey_paragraph(prompt_data: Dictionary) -> String:
	var system_prompt: String = str(prompt_data.get("system", "")).strip_edges()
	var user_prompt: String = str(prompt_data.get("user", "")).strip_edges()
	if user_prompt.is_empty():
		return ""
	var conv_manager = Global.get_conversation_manager() if Global and Global.has_method("get_conversation_manager") else null
	if conv_manager == null:
		return ""
	var full_prompt := ""
	if not system_prompt.is_empty():
		full_prompt = system_prompt + "\n\n" + user_prompt
	else:
		full_prompt = user_prompt
	var response = await conv_manager.chat(full_prompt, "seekers_journey")
	if typeof(response) == TYPE_STRING:
		return str(response).strip_edges()
	return ""

func _on_heartbeat_timeout() -> void:
	if not _verse_enabled or _hub == null:
		return
	if _past_readings.is_empty():
		return
	var seed := str(Time.get_unix_time_from_system())
	var result: Dictionary = await _hub.scensyn_verse_heartbeat(_past_readings, seed)
	if not bool(result.get("ok", false)):
		return
	var fragment_data = result.get("fragment", null)
	if fragment_data == null:
		return
	var omen_text := ""
	var province := ""
	var predicament := ""
	if typeof(fragment_data) == TYPE_DICTIONARY:
		omen_text = str(fragment_data.get("omen_fragment", "")).strip_edges()
		province = str(fragment_data.get("province", "")).strip_edges()
		predicament = str(fragment_data.get("predicament", "")).strip_edges()
	elif typeof(fragment_data) == TYPE_STRING:
		omen_text = str(fragment_data).strip_edges()
	if omen_text.is_empty():
		return
	var rumination := await _generate_heartbeat_rumination(omen_text, province, predicament)
	if rumination.is_empty():
		return
	var speaker := _heartbeat_speaker if not _heartbeat_speaker.is_empty() else "System"
	print("[VerseReadingService] Heartbeat rumination (%s): %s" % [speaker, rumination.left(80)])
	heartbeat_rumination_available.emit(speaker, rumination)

func _generate_heartbeat_rumination(omen: String, province: String, predicament: String) -> String:
	var conv_manager = Global.get_conversation_manager() if Global and Global.has_method("get_conversation_manager") else null
	if conv_manager == null:
		return ""
	var context_parts: Array[String] = []
	context_parts.append("A previous reading contained this omen: \"%s\"" % omen)
	if not province.is_empty():
		context_parts.append("It concerned %s." % province)
	if not predicament.is_empty():
		context_parts.append("The predicament was %s." % predicament)
	var prompt := (
		"You are a contemplative voice reflecting on past events during a quiet moment. "
		+ " ".join(context_parts) + "\n\n"
		+ "Produce a brief 1-2 sentence rumination — a musing, a half-question, or a "
		+ "quiet observation about what that moment meant or what it left unresolved. "
		+ "Speak as if recalling a memory, not quoting. Do not use colons, quotation "
		+ "marks, bullet points, or stage directions. Do not name yourself."
	)
	var response = await conv_manager.chat(prompt, "heartbeat_rumination")
	if typeof(response) == TYPE_STRING:
		return str(response).strip_edges()
	return ""

func _setup_heartbeat_timer() -> void:
	if _heartbeat_timer != null:
		_heartbeat_timer.stop()
		_heartbeat_timer.queue_free()
		_heartbeat_timer = null
	if not _verse_enabled or _heartbeat_interval_s <= 0:
		return
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = _heartbeat_interval_s
	_heartbeat_timer.one_shot = false
	_heartbeat_timer.autostart = false
	_heartbeat_timer.timeout.connect(_on_heartbeat_timeout)
	add_child(_heartbeat_timer)

func _restart_heartbeat_timer() -> void:
	if _heartbeat_timer != null:
		_heartbeat_timer.stop()
		_heartbeat_timer.start()

func clear() -> void:
	_latest_reading = {}
	_latest_character_prompts = {}
	_latest_vis_story_context = {}

func _build_turn_context(data: Dictionary) -> Dictionary:
	return {
		"seeker_manifestation_cue": str(_deep_get(data, "turn_packet.seeker.seeker_manifestation_cue", "")),
		"visible_gain": str(_deep_get(data, "turn_packet.seeker.visible_gain", "")),
		"hidden_cost": str(_deep_get(data, "turn_packet.seeker.hidden_cost", "")),
		"flourishing_state_potential": str(_deep_get(data, "turn_packet.seeker.flourishing_state_potential", _deep_get(data, "matrix_resolution.flourishing_state_potential", ""))),
		"visible_world_effect": str(_deep_get(data, "turn_packet.seeker.visible_world_effect", "")),
		"echo_omen_cue": str(_deep_get(data, "turn_packet.echo.echo_omen_cue", "")),
		"failure_state_risk": str(_deep_get(data, "turn_packet.echo.failure_state_risk", _deep_get(data, "matrix_resolution.failure_state_risk", ""))),
		"complementary_odu": str(_deep_get(data, "turn_packet.echo.complementary_odu", _deep_get(data, "matrix_resolution.complementary_odu", ""))),
		"narrator_handoff_cue": str(_deep_get(data, "turn_packet.narrator.narrator_handoff_cue", "")),
		"next_question": str(_deep_get(data, "turn_packet.narrator.next_question", "")),
		"province_or_site": str(_deep_get(data, "turn_packet.shared.province_or_site", _deep_get(data, "matrix_resolution.province_or_site", ""))),
		"predicament_family": str(_deep_get(data, "turn_packet.shared.predicament_family", _deep_get(data, "matrix_resolution.predicament_family", ""))),
		"world_domain_focus": str(_deep_get(data, "turn_packet.shared.world_domain_focus", _deep_get(data, "matrix_resolution.world_domain_focus", ""))),
		"diviner_operation_cue": str(_deep_get(data, "turn_packet.diviner.diviner_operation_cue", "")),
		"shadow_tendency": str(_deep_get(data, "turn_packet.diviner.shadow_tendency", "")),
	}

func _deep_get(data: Dictionary, dotted_key: String, fallback: Variant = "") -> Variant:
	var keys := dotted_key.split(".")
	var current: Variant = data
	for k in keys:
		if typeof(current) != TYPE_DICTIONARY:
			return fallback
		if not current.has(k):
			return fallback
		current = current[k]
	return current

func _get_verse_config(scenario: Dictionary) -> Dictionary:
	if scenario.has("verse_system"):
		return scenario["verse_system"]
	return {}
