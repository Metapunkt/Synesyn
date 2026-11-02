extends BaseMetapromptManager
class_name CulturalNarrativeMetapromptManager

const DramaturgyMatrixProcessorScript = preload("res://ScenSyn/scripts/cultural_narratives/dramaturgy_matrix_processor.gd")
var _latest_external_input: Dictionary = {}
var _verse_reading_service = null
var _verse_role_map: Dictionary = {}
var _turn_obligation_templates: Dictionary = {}
var _pendulum_bridge: Node = null

const VERSE_PRECOMPOSED_MARKER := "__VERSE_PRECOMPOSED__"

## CulturalNarrativeMetapromptManager - Cultural Narrative specific metaprompt management
##
## REFACTORED: This manager is now fully data-driven. It relies on the scenario .txt file
## to provide System Config and Director Instructions, allowing it to support any
## cultural narrative scenario (e.g., Ireti Okan, Stochastic Dreams) without code changes.

func _ready():
	super._ready()
	game_theme = "Cultural Narrative & Theatrical AI"

# NOTE: All prompt-building, keyword/concept dictionaries, and character matrices
# have been removed. This data now lives in the scenario .txt file as the single
# source of truth, and prompt assembly is handled by the DirectorAgent.

## Override: Get character-specific behavioral guidance from the parsed scenario file.
# This is now a primary responsibility of this class.
func get_character_behavioral_guidance(character_name: String, scenario: Dictionary) -> String:
	if not scenario or not scenario.has("characters"):
		return ""
		
	for character in scenario.characters:
		if character.get("name") == character_name:
			# The parser combines multiline values into a single string.
			var instructions = character.get("behavioral_instructions", "")
			if not instructions.is_empty():
				# Reconstruct a similar format to the old hardcoded version for the prompt
				var guidance = "\n--- " + character_name.to_upper() + " BEHAVIORAL INSTRUCTIONS ---\n"
				guidance += instructions + "\n"
				var matrix_guidance = DramaturgyMatrixProcessorScript.get_character_behavioral_guidance(character_name, scenario)
				if not matrix_guidance.is_empty():
					return matrix_guidance + "\n" + guidance
				return guidance
	# No explicit instructions in the scenario file, fall back to whatever the
	# dramaturgy matrix (CSV) provides for this character.
	return DramaturgyMatrixProcessorScript.get_character_behavioral_guidance(character_name, scenario)

## Override: Get cultural narrative-specific creative mission for a given phase.
## This now fetches the guidance directly from the parsed scenario data.
func get_theme_creative_mission(phase: String, scenario: Dictionary) -> String:
	# The ScenarioDataManager parser creates a sub-dictionary for sections with "---" headers
	var phase_guidance = scenario.get("phase_guidance", {})
	var phase_key = phase.to_upper()
	
	print("[MetapromptManager] Requesting phase '%s' (key: '%s'). Available keys: %s" % [phase, phase_key, phase_guidance.keys()])
	
	if phase_guidance.has(phase_key):
		var guidance = phase_guidance.get(phase_key, "")
		print("[MetapromptManager] Found guidance, length: ", guidance.length())
		return guidance
	
	print("[MetapromptManager] WARNING: Phase '%s' not found in phase_guidance!" % phase_key)
	return ""
	
## NEW: Generic function to get the text content of any [SECTION] from the scenario.
func get_narrative_section(section_name: String, scenario: Dictionary) -> String:
	# The parser stores these sections with lowercase keys and "_text" suffix.
	var key = section_name.to_lower() + "_text"
	return scenario.get(key, "ERROR: Section '%s' not found in scenario." % section_name)

## Handle external input (e.g., from ExternalInputListener)
func handle_external_input(data: Dictionary) -> void:
	print("[CulturalNarrativeMetapromptManager] Handling external input: ", data)
	_latest_external_input = data.duplicate(true)
	
	var scenario = Global.get_current_scenario()
	if not scenario.has("system_config"):
		return
		
	var message := _build_external_input_system_message(data, scenario)
	if message == "":
		var tmpl = scenario.system_config.get("metric_template", "")
		if tmpl == "":
			return
		
		# 1. Process simple template replacements (flatten dictionary)
		var flat_data = _flatten_dict(data)
		message = tmpl
		for key in flat_data:
			var token = "{%s}" % key
			if message.contains(token):
				message = message.replace(token, str(flat_data[key]))
			
	# 2. Inject into StoryState as a system message
	if Engine.has_singleton("StoryState"):
		var ss = Engine.get_singleton("StoryState")
		if ss and ss.has_method("add_system_event"):
			# Use the configured speaker name (e.g., "The Chaos Engine")
			var speaker = get_system_cue_tag()
			ss.add_system_event(speaker, message)
			print("[CulturalNarrativeMetapromptManager] Injected system event: ", message)

func get_latest_external_input() -> Dictionary:
	return _latest_external_input.duplicate(true)

func get_latest_turn_context_for_prompt(character_name: String = "") -> String:
	if _latest_external_input.is_empty():
		return ""
	var lines: Array[String] = []

	# Include the packet's window_id (a live millisecond timestamp) so the LLM API
	# never serves a cached response for repeated swings of the same board config.
	var window_id: String = str(_turn_value("window_id", "")).strip_edges()
	if window_id.is_empty():
		window_id = str(int(Time.get_unix_time_from_system()))
	lines.append("- Window: %s" % window_id)

	var province: String = str(_turn_value("turn_packet.shared.province_or_site", _turn_value("matrix_resolution.province_or_site", ""))).strip_edges()
	var region: String = str(_turn_value("turn_packet.shared.tapestry_region_primary", _turn_value("matrix_resolution.tapestry_region_primary", ""))).strip_edges()
	var predicament: String = str(_turn_value("turn_packet.shared.predicament_family", _turn_value("matrix_resolution.predicament_family", ""))).strip_edges()
	var region_secondary: String = str(_turn_value("matrix_resolution.tapestry_region_secondary", "")).strip_edges()
	var world_domain: String = str(_turn_value("matrix_resolution.world_domain_focus", _turn_value("turn_packet.shared.world_domain_focus", ""))).strip_edges()
	var world_effect: String = str(_turn_value("turn_packet.seeker.visible_world_effect", "")).strip_edges()
	var resonance_raw: String = str(_turn_value("resonance", "")).strip_edges()
	var next_question: String = str(_turn_value("turn_packet.narrator.next_question", "")).strip_edges()
	var risk: String = str(_turn_value("turn_packet.echo.failure_state_risk", _turn_value("matrix_resolution.failure_state_risk", ""))).strip_edges()
	var potential: String = str(_turn_value("turn_packet.seeker.flourishing_state_potential", _turn_value("matrix_resolution.flourishing_state_potential", ""))).strip_edges()

	# Build a qualitative orbit narrative from raw pendulum values — never expose
	# raw floats or crossing counts to the LLM; these invite metric readouts.
	var dominant: String = str(_turn_value("board.primary_bead", _turn_value("beads.primary_concept", ""))).strip_edges()
	var crossings_raw: String = str(_turn_value("uwp_traversal.crossings", "")).strip_edges()
	var stability_raw: String = str(_turn_value("pendulum.stability", "")).strip_edges()
	var orbit_narrative: String = _pendulum_to_narrative(dominant, crossings_raw, stability_raw)

	if province != "" or region != "":
		lines.append("- Site of change: %s in %s." % [province if province != "" else "Unnamed Site", region if region != "" else "Unnamed Region"])
	if region_secondary != "":
		lines.append("- Secondary region under influence: %s." % region_secondary)
	if predicament != "":
		lines.append("- Active predicament family: %s." % predicament)
	if world_domain != "":
		lines.append("- Civic domain in play: %s." % world_domain)
	if world_effect != "":
		lines.append("- Visible world effect: %s" % world_effect)
	if orbit_narrative != "":
		lines.append("- Orbit behavior: %s" % orbit_narrative)
	if resonance_raw != "":
		lines.append("- Field coherence: %s" % _resonance_to_label(resonance_raw.to_float()))
	if risk != "":
		lines.append("- Failure risk now in play: %s." % risk)
	if potential != "":
		lines.append("- Flourishing horizon: %s." % potential)
	if next_question != "":
		lines.append("- Unresolved next question: %s" % next_question)
	var role_brief: String = get_character_turn_obligation(character_name)
	if role_brief != "":
		lines.append("- Character obligation: %s" % role_brief)
	if lines.size() <= 1:  # only the sequence line
		return ""
	return "\n".join(lines)

## Translate a raw resonance float into a qualitative field description that
## characters can use as dramatic context without quoting numbers.
func _resonance_to_label(r: float) -> String:
	if r < 0.3:
		return "low — the field scattered, no coherent pattern emerged"
	elif r < 0.5:
		return "moderate — a frequency found, but the field has not yet settled"
	elif r < 0.7:
		return "high — the orbit found coherence; the field aligned"
	else:
		return "very high — the field confirmed itself strongly; little resistance was met"

## Translate raw pendulum crossings / stability into a narrative orbit description.
## Characters receive this instead of raw numeric values.
func _pendulum_to_narrative(dominant: String, crossings_raw: String, stability_raw: String) -> String:
	var crossings: int = int(crossings_raw) if crossings_raw != "" else -1
	var stability: float = stability_raw.to_float() if stability_raw != "" else -1.0
	var site: String = dominant if dominant != "" else "its sector"
	if crossings < 0 and stability < 0.0:
		return ""
	if crossings == 0:
		if stability >= 0.5:
			return "The orbit held steady in %s without crossing its own perimeter — a field that has not yet tested its edges." % site
		else:
			return "The orbit stalled in %s — it did not cross, did not probe, confirmed only what it already knew." % site
	elif crossings <= 2:
		return "The orbit crossed %s time(s) in %s — the frame was tested and held." % [crossings, site]
	elif crossings <= 4:
		return "The orbit crossed %s times in %s — significant pressure, the frame is being tested." % [crossings, site]
	else:
		return "The orbit scattered — crossed %s times in %s, unable to hold a stable path." % [crossings, site]

func set_verse_reading_service(service) -> void:
	_verse_reading_service = service

func get_verse_reading_service():
	return _verse_reading_service

func get_verse_precomposed_marker() -> String:
	return VERSE_PRECOMPOSED_MARKER

func load_scenario_obligations(scenario: Dictionary) -> void:
	_turn_obligation_templates = scenario.get("turn_obligations", {})
	var verse_cfg: Dictionary = scenario.get("verse_system", {})
	_verse_role_map = _parse_role_map(str(verse_cfg.get("role_map", "")))
	_latest_external_input = {}
	_manage_pendulum_bridge(scenario)


func _manage_pendulum_bridge(scenario: Dictionary) -> void:
	var scenario_name: String = str(scenario.get("name", "")).to_lower().strip_edges()
	var is_stochastic_dreams: bool = scenario_name.contains("stochastic_dreams") or scenario_name.contains("stochastic dreams")
	print("[CulturalNarrativeMetapromptManager] _manage_pendulum_bridge — scenario_name='%s'  is_stochastic_dreams=%s  bridge_exists=%s" % [
		scenario_name, str(is_stochastic_dreams), str(_pendulum_bridge != null)
	])
	if is_stochastic_dreams and _pendulum_bridge == null:
		var bridge_script: GDScript = load("res://ScenSyn/session_types/story_catalyst/cultural_narratives/stochastic_dreams/pendulum_bridge.gd")
		if bridge_script:
			_pendulum_bridge = bridge_script.new()
			add_child(_pendulum_bridge)
			print("[CulturalNarrativeMetapromptManager] ✓ Pendulum bridge activated for Stochastic Dreams")
		else:
			push_error("[CulturalNarrativeMetapromptManager] pendulum_bridge.gd failed to load — OSC will not be received")
	elif not is_stochastic_dreams and _pendulum_bridge != null:
		_pendulum_bridge.queue_free()
		_pendulum_bridge = null
		print("[CulturalNarrativeMetapromptManager] Pendulum bridge deactivated (scenario changed)")
	elif is_stochastic_dreams and _pendulum_bridge != null:
		print("[CulturalNarrativeMetapromptManager] Pendulum bridge already active — no action needed")

func _has_verse_reading() -> bool:
	if _verse_reading_service == null:
		return false
	if not _verse_reading_service.has_method("is_enabled"):
		return false
	return _verse_reading_service.is_enabled() and _verse_reading_service.has_reading_for_current_turn()

func get_character_turn_obligation(character_name: String) -> String:
	if _has_verse_reading():
		return _get_verse_obligation(character_name)
	return _get_standard_obligation(character_name)

func _get_verse_obligation(character_name: String) -> String:
	var prompts: Dictionary = _verse_reading_service.get_latest_character_prompts()
	if prompts.is_empty():
		return _get_standard_obligation(character_name)
	var prompt_key: String = _verse_role_map.get(character_name, "").strip_edges()
	if prompt_key.is_empty():
		prompt_key = _verse_role_map.get(_canonical_turn_character_name(character_name), "").strip_edges()
	if prompt_key.is_empty():
		return _get_standard_obligation(character_name)
	var reader_character: String = ""
	if _verse_reading_service.has_method("get_reader_character"):
		reader_character = _verse_reading_service.get_reader_character()
	var is_reader: bool = not reader_character.is_empty() and (character_name == reader_character or _canonical_turn_character_name(character_name) == reader_character)
	var prompt_text: String = str(prompts.get(prompt_key, "")).strip_edges()
	if prompt_text.is_empty():
		return _get_standard_obligation(character_name)
	if is_reader:
		# Feed the precomposed verse as source material for a live riff rather than
		# delivering it verbatim.  The Actor LLM keeps the core insight and closing
		# question but generates fresh language each time — preventing the same poem
		# from being spoken word-for-word across multiple pendulum swings in one session.
		return (
			"SOURCE VERSE — do NOT recite verbatim. Perform it freely:\n"
			+ prompt_text
			+ "\nKEEP: the core insight and the closing question. "
			+ "TRANSFORM: fragment a line, compress an image, or invert a stanza. "
			+ "Every word must be original to this delivery. The oracle interprets — it does not recite."
		)
	return prompt_text

func _get_standard_obligation(character_name: String) -> String:
	if _latest_external_input.is_empty():
		return ""
	var template: String = _get_obligation_template(character_name)
	if template.is_empty():
		return ""
	return _render_obligation_template(template)

func _get_obligation_template(character_name: String) -> String:
	if _turn_obligation_templates.is_empty():
		return ""
	if _turn_obligation_templates.has(character_name):
		return str(_turn_obligation_templates[character_name]).strip_edges()
	var canonical: String = _canonical_turn_character_name(character_name)
	if _turn_obligation_templates.has(canonical):
		return str(_turn_obligation_templates[canonical]).strip_edges()
	return ""

func _render_obligation_template(template: String) -> String:
	var flat: Dictionary = _flatten_dict(_latest_external_input)
	var shortcut_map: Dictionary = {
		"province_or_site": "turn_packet.shared.province_or_site",
		"predicament_family": "turn_packet.shared.predicament_family",
		"world_domain_focus": "turn_packet.shared.world_domain_focus",
		"diviner_operation_cue": "turn_packet.diviner.diviner_operation_cue",
		"shadow_tendency": "turn_packet.diviner.shadow_tendency",
		# {resonance} resolves to a qualitative label, never a raw float.
		"resonance": "__resonance_label__",
		"echo_omen_cue": "turn_packet.echo.echo_omen_cue",
		"failure_state_risk": "turn_packet.echo.failure_state_risk",
		"hidden_cost": "turn_packet.seeker.hidden_cost",
		"visible_gain": "turn_packet.seeker.visible_gain",
		"flourishing_state_potential": "turn_packet.seeker.flourishing_state_potential",
		"visible_world_effect": "turn_packet.seeker.visible_world_effect",
		"next_question": "turn_packet.narrator.next_question",
	}
	var result := template
	for short_key in shortcut_map:
		var token := "{%s}" % short_key
		if result.contains(token):
			var long_key: String = shortcut_map[short_key]
			var value: String
			if long_key == "__resonance_label__":
				var r_raw: String = str(flat.get("resonance", "")).strip_edges()
				value = _resonance_to_label(r_raw.to_float()) if r_raw != "" else "unknown"
			else:
				value = str(flat.get(long_key, flat.get("matrix_resolution.%s" % short_key, ""))).strip_edges()
			if value.is_empty():
				value = "the current %s" % short_key.replace("_", " ")
			result = result.replace(token, value)
	for key in flat:
		var token := "{%s}" % key
		if result.contains(token):
			result = result.replace(token, str(flat[key]))
	return result

func _parse_role_map(raw: String) -> Dictionary:
	var result: Dictionary = {}
	if raw.strip_edges().is_empty():
		return result
	for pair in raw.split(","):
		var parts := pair.strip_edges().split("=", true, 1)
		if parts.size() == 2:
			result[parts[0].strip_edges()] = parts[1].strip_edges()
	return result

func get_latest_turn_system_cue(_phase: String = "") -> String:
	if _latest_external_input.is_empty():
		return ""
	var province: String = str(_turn_value("turn_packet.shared.province_or_site", _turn_value("matrix_resolution.province_or_site", ""))).strip_edges()
	var predicament: String = str(_turn_value("turn_packet.shared.predicament_family", _turn_value("matrix_resolution.predicament_family", ""))).strip_edges()
	var effect: String = str(_turn_value("turn_packet.seeker.visible_world_effect", "")).strip_edges()
	var resonance: String = str(_turn_value("resonance", "")).strip_edges()
	if province == "" and predicament == "":
		return ""
	var cue := "Divination registered at %s under %s." % [province if province != "" else "the active site", predicament if predicament != "" else "the current pattern"]
	if effect != "":
		cue += " " + effect
	if resonance != "":
		cue += " Resonance " + resonance + "."
	return cue.strip_edges()

func get_current_turn_guardrails(_character_name: String = "") -> Dictionary:
	var result: Dictionary = {}

	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	var sys_cfg: Dictionary = scenario.get("system_config", {})
	var mwb: String = str(sys_cfg.get("max_words_brief", "")).strip_edges()
	var mwd: String = str(sys_cfg.get("max_words_default", "")).strip_edges()
	var roe: String = str(sys_cfg.get("reprompt_on_excess", "")).strip_edges().to_lower()
	if mwb.is_valid_int():
		result["max_words_brief"] = mwb.to_int()
	if mwd.is_valid_int():
		result["max_words_default"] = mwd.to_int()
	if roe == "true":
		result["reprompt_on_excess"] = true

	if not _latest_external_input.is_empty():
		var anchors: Array[String] = []
		var candidates: Array[String] = [
			str(_turn_value("turn_packet.shared.province_or_site", "")),
			str(_turn_value("turn_packet.shared.tapestry_region_primary", "")),
			str(_turn_value("turn_packet.shared.predicament_family", "")),
			str(_turn_value("matrix_resolution.world_domain_focus", _turn_value("turn_packet.shared.world_domain_focus", ""))),
			str(_turn_value("turn_packet.echo.failure_state_risk", _turn_value("matrix_resolution.failure_state_risk", ""))),
			str(_turn_value("turn_packet.seeker.flourishing_state_potential", _turn_value("matrix_resolution.flourishing_state_potential", "")))
		]
		for candidate_any in candidates:
			var candidate: String = str(candidate_any).strip_edges()
			if candidate != "" and not anchors.has(candidate):
				anchors.append(candidate)
		result["required_anchor_terms"] = anchors
		result["require_anchor_term"] = not anchors.is_empty()
		result["allowed_bead_names"] = ["Fount", "Ethos", "Will", "Cycle", "Seed"]
		result["enforce_known_bead_names"] = true

	return result

func _build_external_input_system_message(data: Dictionary, scenario: Dictionary) -> String:
	var _scenario: Dictionary = scenario
	var shared_any: Variant = _get_nested_value(data, "turn_packet.shared")
	if typeof(shared_any) != TYPE_DICTIONARY:
		return ""
	var shared: Dictionary = shared_any
	var province: String = str(shared.get("province_or_site", "")).strip_edges()
	var predicament: String = str(shared.get("predicament_family", "")).strip_edges()
	var pendulum_summary: String = str(shared.get("pendulum_summary", "")).strip_edges()
	var resonance: String = str(data.get("resonance", "")).strip_edges()
	var message := ""
	if province != "" and predicament != "":
		message = "%s registers %s." % [province, predicament]
	elif province != "":
		message = "Divination window resolves at %s." % province
	if pendulum_summary != "":
		message += " " + pendulum_summary
	if resonance != "":
		message += " Resonance " + resonance + "."
	return message.strip_edges()

func _turn_value(path: String, default_value: Variant = "") -> Variant:
	return _get_nested_value(_latest_external_input, path, default_value)

func _get_nested_value(source: Dictionary, path: String, default_value: Variant = "") -> Variant:
	if source.is_empty() or path == "":
		return default_value
	var current: Variant = source
	for part_any in path.split("."):
		var part: String = String(part_any).strip_edges()
		if typeof(current) != TYPE_DICTIONARY:
			return default_value
		var current_dict: Dictionary = current
		if not current_dict.has(part):
			return default_value
		current = current_dict[part]
	return current

func _canonical_turn_character_name(character_name: String) -> String:
	var trimmed: String = String(character_name).strip_edges()
	if trimmed.is_empty():
		return trimmed
	var scenario: Dictionary = {}
	if Global and Global.has_method("get_game_flow_manager") and Global.get_game_flow_manager():
		scenario = Global.get_game_flow_manager().get_current_scenario()
	if scenario.has("characters"):
		var lower_input := trimmed.to_lower()
		for character in scenario["characters"]:
			var name: String = str(character.get("name", ""))
			if name.to_lower() == lower_input or ("the " + lower_input) == name.to_lower():
				return name
	return trimmed

# Helper to flatten nested dictionary keys for template replacement
# e.g. {"pendulum": {"alpha": 0.8}} -> {"pendulum.alpha": 0.8}
func _flatten_dict(dict: Dictionary, prefix: String = "") -> Dictionary:
	var result = {}
	for key in dict:
		var full_key = key if prefix == "" else prefix + "." + key
		if typeof(dict[key]) == TYPE_DICTIONARY:
			var sub = _flatten_dict(dict[key], full_key)
			result.merge(sub)
		else:
			result[full_key] = dict[key]
	return result

## System notifications. The label comes from the scenario's speaker_name.
## A scenario that does not set one is shown as a plain system message.
func get_system_cue_tag() -> String:
	var scenario = Global.get_current_scenario()
	if scenario.has("system_config"):
		var named := String(scenario.system_config.get("speaker_name", "")).strip_edges()
		if named != "":
			return named
	return "System Message"


func get_system_senders() -> Array[String]:
	var senders: Array[String] = super.get_system_senders()
	var cue := get_system_cue_tag()
	if cue != "" and not senders.has(cue):
		senders.append(cue)
	return senders

# Internal state for simple metric progression (persists while manager lives).
# Randomise the starting value so the first cue in a new session doesn't always
# print the same percentage (0 + step = 8 is otherwise a fixed first output).
var _child_progress := randi_range(0, 12)
var _child_metric_toggle := false

## Build a short metric line to append to system cues.
## Example: "Okan's emergence protocol at 72% completion"
## REFACTORED: Uses metric_template from scenario config if available
func get_system_metric_line(phase: String, turn_outcome: String = "") -> String:
	# Phase-based base step
	var step := 8
	var ph := phase.to_upper()
	if ph == "CLIMAX":
		step = 12
	elif ph == "RISING":
		step = 9
	elif ph == "SETUP":
		step = 6
	# Dialogue-reactive delta and outcome steering
	var delta := _compute_metric_delta_from_dialogue()
	var ob := 0
	var to := String(turn_outcome).to_lower()
	if to == "reveal":
		ob = 2
	elif to == "escalate":
		ob = 5
	elif to == "decision":
		ob = 10
	elif to == "reframe":
		ob = 3
	# Update with clamped progression (prefer non-decreasing; allow tiny stall)
	var new_progress := _child_progress + step + delta + ob
	if new_progress < _child_progress:
		# Prevent large regressions; allow at most -2 to simulate flicker
		new_progress = max(_child_progress - 2, _child_progress)
	_child_progress = clampi(new_progress, 0, 100)
	# Alternate label to keep poetics fresh
	_child_metric_toggle = not _child_metric_toggle
	var label := "emergence" if _child_metric_toggle else "calibration"
	
	# Check for data-driven template
	var scenario = Global.get_current_scenario()
	if scenario.has("system_config"):
		var tmpl = scenario.system_config.get("metric_template", "")
		if tmpl != "":
			# Simple substitutions
			var sys_name = get_system_cue_tag()
			return tmpl.replace("{system_name}", sys_name).replace("{protocol}", label).replace("{value}", str(_child_progress))

	return "Okan's %s protocol at %d%% completion" % [label, _child_progress]

# Analyze recent dialogue to adjust metric toward what the scene implies,
# and nudge the next beat. Heuristics only; scenario remains source of truth.
func _compute_metric_delta_from_dialogue() -> int:
	var last_lines: Array = []
	if Engine.has_singleton("StoryState"):
		var ss = Engine.get_singleton("StoryState")
		if ss and ss.has_method("get_state"):
			var story_log_entries: Array = ss.get_state().get("story_log", [])
			for i in range(max(0, story_log_entries.size() - 4), story_log_entries.size()):
				var e: Dictionary = story_log_entries[i]
				var s := String(e.get("sender", ""))
				if s == "Narrator":
					continue
				last_lines.append(String(e.get("message", "")))
	if last_lines.is_empty():
		return 0
	var txt := (" \n").join(last_lines).to_lower()
	var delta := 0
	# Strong emergence confirmations → jump forward
	if txt.find("confirmed") != -1 and txt.find("emerg") != -1:
		delta += 25
	if txt.find("self-modification") != -1 or txt.find("self modification") != -1:
		delta += 15
	# Escalation indicators
	if txt.find("containment") != -1 or txt.find("cascade failure") != -1 or txt.find("collapse") != -1:
		delta += 10
	# Skepticism / denial can dampen acceleration a bit
	if txt.find("not ready") != -1 or txt.find("doubt") != -1 or txt.find("unpredictable") != -1:
		delta -= 3
	# If someone explicitly says "emerged" or treats Okan as present, ensure we don't contradict with very low %
	if txt.find("emerged") != -1 or txt.find("is here") != -1:
		if _child_progress < 60:
			delta += 60 - _child_progress
	return delta

func should_emit_system_cue(turn_number: int) -> bool:
	# Theme-level cadence: 0–1 cue every 2–4 turns; deterministic simple cadence
	# Emit on every 3rd non-narrator turn starting from 2
	return turn_number >= 2 and turn_number % 3 == 0

func pick_system_notification(phase: String, scenario: Dictionary) -> String:
	var raw: String = String(scenario.get("system_notifications_text", "")).strip_edges()
	if raw == "":
		return ""
	var lines := raw.split("\n")
	var target_section := "--- " + phase.to_upper() + " ---"
	var in_section := false
	var candidates: Array = []
	for l in lines:
		var line := String(l).strip_edges()
		if line == "":
			continue
		if line.begins_with("--- ") and line.ends_with(" ---"):
			in_section = (line == target_section)
			continue
		if in_section and not line.begins_with("--- "):
			# strip potential leading dash
			if line.begins_with("-"):
				line = line.substr(1).strip_edges()
			candidates.append(line)
	if candidates.is_empty():
		return ""
	# Simple rotation by phase name hash to avoid randomness
	var h: int = hash(phase)
	if h < 0:
		h = -h
	var idx: int = h % candidates.size()
	return candidates[idx]

## SCENE LEDGER helpers (move taxonomy from scenario)
func get_scene_ledger_moves(scenario: Dictionary) -> Dictionary:
	var result := {
		"scene_aim": "",
		"moves": {} # id -> description
	}
	var raw := get_narrative_section("SCENE_LEDGER", scenario)
	if raw.begins_with("ERROR"):
		return result
	for line in raw.split("\n"):
		var l := String(line).strip_edges()
		if l == "":
			continue
		# scene_aim: ...
		if l.to_lower().begins_with("scene_aim:"):
			var parts = l.split(":", true, 1)
			if parts.size() == 2:
				result.scene_aim = String(parts[1]).strip_edges()
			continue
		# Parse bullet moves like: - C1: description
		if l.begins_with("-"):
			var rest := l.substr(1).strip_edges()
			var colon := rest.find(":")
			if colon > 0:
				var id := String(rest.substr(0, colon)).strip_edges()
				var desc := String(rest.substr(colon + 1)).strip_edges()
				if id != "" and desc != "":
					result.moves[id] = desc
	return result

func get_move_example(move_id: String, scenario: Dictionary) -> String:
	var ledger := get_scene_ledger_moves(scenario)
	var moves: Dictionary = ledger.get("moves", {})
	return String(moves.get(move_id, ""))

## NEW: Opening constraints parsed from scenario text (allowed/forbidden/max)
func get_opening_constraints(scenario: Dictionary) -> Dictionary:
	var result := {
		"allowed": [],
		"forbidden": [],
		"max_speakers": 2
	}
	var raw := get_narrative_section("OPENING_CONSTRAINTS", scenario)
	if raw.begins_with("ERROR"):
		return result
	for line in raw.split("\n"):
		var l := String(line).strip_edges()
		if l == "":
			continue
		var lower := l.to_lower()
		if lower.begins_with("- allowed opening speaker"):
			var parts = l.split(":", true, 1)
			if parts.size() == 2:
				var directive := parts[1].strip_edges()
				if directive.to_lower().begins_with("any ai character"):
					result.allowed = ["__ANY_AI__"]
				else:
					for speaker_name in directive.split(","):
						var speaker_name_trimmed := String(speaker_name).strip_edges()
						if speaker_name_trimmed != "":
							result.allowed.append(speaker_name_trimmed)
		elif lower.find("do not feature") != -1:
			# Example: "- DO NOT feature Lucky in the first exchange."
			var tokens = l.split(" ")
			for t in tokens:
				var tt := String(t).strip_edges().replace(",", "").replace(".", "")
				if tt != "" and tt != "DO" and tt != "NOT" and tt != "feature" and tt != "in" and tt != "the" and tt != "first" and tt != "exchange":
					result.forbidden.append(tt)
		elif lower.find("first exchange: exactly one ai speaker") != -1:
			result.max_speakers = 1
	return result

## NEW: Character delivery rules derived from scenario guidance
## Returns: { address_to: String|"", token_limit: int|-1, sentence_cap: int|-1 }
func get_character_delivery_rules(character_name: String, phase: String, scenario: Dictionary) -> Dictionary:
	var rules := {
		"address_to": "",
		"address_aliases": [],
		"token_limit": -1,
		"sentence_cap": -1
	}
	if not scenario or not scenario.has("characters"):
		return rules
	# Find character entry
	var entry := {}
	for c in scenario.characters:
		if String(c.get("name", "")) == character_name:
			entry = c
			break
	if entry.is_empty():
		return rules
	var beh := String(entry.get("behavioral_instructions", ""))
	# Addressing target heuristic: detect "Address X directly" (and optional 'as "Y"')
	for line in beh.split("\n"):
		var l := String(line).strip_edges()
		var lower := l.to_lower()
		if lower.begins_with("- address "):
			# Extract substring after '- address '
			var tail_full := l.substr(10).strip_edges()
			var aliases: Array[String] = []
			var as_idx := tail_full.to_lower().find(" as ")
			if as_idx != -1:
				var alias_part := tail_full.substr(as_idx + 4).strip_edges()
				alias_part = alias_part.replace("\"", "").replace("'", "").replace(".", "").replace(",", "").replace(";", "").replace(":", "").strip_edges()
				if alias_part != "":
					aliases.append(alias_part)
			# Trim anything after the word 'directly' (case-insensitive)
			var tail_lower := tail_full.to_lower()
			var idx := tail_lower.find(" directly")
			if idx != -1:
				tail_full = tail_full.substr(0, idx)
			# Take only the first token as a canonical name, strip punctuation
			var name_token := tail_full.split(" ")[0]
			name_token = name_token.replace(".", "").replace(",", "").replace(";", "").replace(":", "")
			if name_token != "":
				rules.address_to = name_token
				if not aliases.has(name_token):
					aliases.push_front(name_token)
				rules.address_aliases = aliases
				break
	# Token limits per phase (if described in behavior block)
	var p := String(phase).to_upper()
	if p == "SETUP" or p == "INCIDENT":
		# Detect explicit "no code-like tokens" guideline
		if beh.to_lower().find("no code-like tokens") != -1 or beh.to_lower().find("no tokens") != -1:
			rules.token_limit = 0
	elif p == "RISING":
		if beh.to_lower().find("at most one short") != -1 or beh.to_lower().find("at most one") != -1:
			rules.token_limit = 1
	elif p == "CLIMAX":
		if beh.to_lower().find("at most two short") != -1 or beh.to_lower().find("at most two") != -1:
			rules.token_limit = 2
	else:
		# Resolution/Ended: prefer clearer language
		rules.token_limit = 0

	# Sentence cap heuristics from behavioral text
	# If behavior explicitly says "One sentence only" or "One concise line", set cap=1
	var beh_lower := beh.to_lower()
	if beh_lower.find("one sentence only") != -1 or beh_lower.find("one concise line") != -1:
		rules.sentence_cap = 1

	# REFACTORED: Parse degradation rules into structured data
	var role_lower = String(entry.get("role", "")).to_lower()
	
	# Check for data-driven override for delivery notes if needed, otherwise stick to heuristics
	# But here we are mainly concerned with "Director" instructions in the next region.
	# For now, we keep the robotic check for delivery rules as it's tied to specific behavior text parsing
	# that assumes a certain format.
	
	if "robotic personal ai assistant" in role_lower:
		var phase_upper = phase.to_upper()
		var delivery_note = ""
		for line in beh.split("\n"):
			var trimmed_line = line.strip_edges().trim_prefix("-").strip_edges()
			var parts = trimmed_line.split(":")
			if parts.size() > 1:
				var phase_tags = parts[0].split("/")
				for tag in phase_tags:
					if tag.strip_edges() == phase_upper:
						delivery_note = trimmed_line.substr(trimmed_line.find(":") + 1).strip_edges()
						break
			if not delivery_note.is_empty():
				break
		
		if not delivery_note.is_empty():
			rules["delivery_note"] = delivery_note
			var note_lower = delivery_note.to_lower()
			# Translate free text rules into structured data for the validator
			if note_lower.contains("no code-like tokens"):
				rules["token_limit"] = 0
			elif note_lower.contains("at most one"):
				rules["token_limit"] = 1
			elif note_lower.contains("at most two"):
				rules["token_limit"] = 2
			
			if note_lower.contains("full sentences"):
				rules["require_full_sentence"] = true
			
			# NEW: Add flag to trigger the specialized two-step generation pipeline
			rules["requires_stylized_generation"] = true


	return rules

## OVERRIDE: Determine if a character's role allows technical speech.
func allows_technical_speech(character_role: String) -> bool:
	# In this theme, only characters with "Robotic" or "AI Assistant" in their role
	# are permitted to use technical language like numeric gauges or status tokens.
	var role_lower = character_role.to_lower()
	if "robotic" in role_lower or "ai assistant" in role_lower:
		return true
	return false

#endregion

#region ======================== DIRECTOR CUE REFINEMENT =========================

## NEW: Provide character-specific instructions to the DirectorAgent.
## This keeps the Director generic and moves scenario logic here.
## REFACTORED: Now primarily data-driven via DIRECTOR_ARCHETYPES in scenario file.
func get_director_instructions(character_name: String, _phase: String, scenario: Dictionary) -> String:
	var character_data = {}
	if scenario.has("characters"):
		for c in scenario.characters:
			if c.get("name") == character_name:
				character_data = c
				break
	
	if character_data.is_empty():
		return ""
	
	var role = String(character_data.get("role", "")).to_lower()

	# 1. Try to find an exact match in the scenario's DIRECTOR_ARCHETYPES
	if scenario.has("director_archetypes"):
		var archetypes = scenario.director_archetypes
		# Check each key in archetypes to see if it matches the role
		for key in archetypes:
			if key in role:
				var template = archetypes[key]
				# Simple interpolation if needed, e.g., %s for character name
				if template.contains("%s"):
					return template % character_name
				return template

	# 2. Fallback to Legacy Hardcoded Logic (for backward compatibility if file not updated)
	if "robotic personal ai assistant" in role:
		return """
**SPECIAL INSTRUCTIONS FOR THIS TURN (Character: %s - A Failing Machine Servant):**
- **CREATIVE TASK:** Generate a "Creative Brief" for a cue.
  - **Reporting Menu:** The cue must instruct the actor to report on ONE of the following, triggered by the last conversational action: a biometric reading of another character, a network status anomaly, a predictive model update, or an error in their own language processors.
  - **Emotional Counterpoint:** The report must not directly agree with the emotional sentiment of the last action. If the action was confident, the data should imply uncertainty. If it was questioning, the data should be a blunt, unrelated fact.
  - **Targeting:** The conversational action MUST be addressed to Pozzo.
""" % character_name
	elif "research scientist" in role:
		return """
**SPECIAL INSTRUCTIONS FOR THIS TURN (Character: %s - The Critical Scientist):**
- **CREATIVE TASK:** Generate a "Diversified Inquiry" cue. Instead of defaulting to asking for data, the cue must instruct the actor to perform ONE of the following actions in reaction to the last conversational action:
  - **Reframe with a Marxist Critique:** Analyze the last action from the perspective of power, ownership, or labor.
  - **Pivot to Ethical Concern:** Connect the last action to a broader humane or ethical implication.
  - **Solicit Cultural Insight:** Pose a question that explicitly asks for Gogo's cultural or mythological perspective.
  - **Make an Empirical Observation:** Make a concise, scientific observation about the immediate situation.
""" % character_name
	elif "neo capitalist" in role:
		return """
**SPECIAL INSTRUCTIONS FOR THIS TURN (Character: %s - The Neo-Capitalist):**
- **CREATIVE TASK:** Generate an "Assert Control" cue. The cue must instruct the actor to perform ONE of the following actions in reaction to the last conversational action:
  - **Reframe in Financial Terms:** Translate the last action into a matter of investment, assets, or ROI.
  - **Dismiss with Bluster:** Condescendingly dismiss another character's point (especially Gogo's) as "mysticism" or "unproductive."
  - **Issue a Command:** Attempt to reassert authority by giving a direct order to Lucky.
  - **Reveal Frustration:** Display a moment of aristocratic frustration that their control over the system is slipping.
""" % character_name
	elif "story teller" in role:
		return """
**SPECIAL INSTRUCTIONS FOR THIS TURN (Character: %s - The Storyteller):**
- **CREATIVE TASK:** Generate a "Reframe with Wisdom" cue. The cue must instruct the actor to perform ONE of the following actions in reaction to the last conversational action:
  - **Introduce a Proverb/Metaphor:** Respond with a relevant Yoruba proverb or a metaphor from nature.
  - **Provoke with a Riddle:** Mock another character's certainty (especially Pozzo's) with a witty riddle.
  - **Invoke Mythological Context:** Reframe the situation by referencing the mythology of Esu or Janus.
  - **Tell a Micro-Story:** Offer a very brief, relevant piece of ancestral wisdom.
""" % character_name
	else:
		return ""

## NEW: Get the voice override mappings from the parsed scenario.
func get_voice_overrides(scenario: Dictionary) -> Dictionary:
	if scenario and scenario.has("voice_overrides"):
		return scenario["voice_overrides"]
	return {}

## NEW: Consult the Oracle (Relational Matrix) for Divination/Meaning
## This helper function allows characters (Diviner/Narrator) to look up
## deep semantic meanings by cross-referencing "Bead Concepts" (Rows)
## and "Pendulum States" (Columns) from the relational matrix CSV.
func consult_oracle(concept_key: String, state_key: String, scenario: Dictionary) -> String:
	# Check if scenario has relational matrix configuration
	if not scenario.has("relational_matrix"):
		return ""
	
	var schema = scenario.relational_matrix
	var matrix_file = schema.get("file", "")
	if matrix_file == "":
		return ""

	# Resolve path similar to DramaturgyMatrixProcessor
	var csv_path = matrix_file
	if not csv_path.begins_with("res://"):
		csv_path = scenario.get("_base_dir", "") + csv_path
	
	# Load CSV (simple cache could be added here if performance becomes an issue)
	# For now, we'll use a simplified lookup since this is an infrequent operation
	if not FileAccess.file_exists(csv_path):
		return ""
		
	var file = FileAccess.open(csv_path, FileAccess.READ)
	if not file:
		return ""

	var headers = file.get_csv_line()
	var state_index = -1
	
	# Find column index for state_key (e.g., "OYEKU MEJI")
	for i in range(headers.size()):
		if headers[i].strip_edges().to_upper() == state_key.to_upper():
			state_index = i
			break
	
	if state_index == -1:
		return ""

	var result = ""
	# Scan rows for concept_key (e.g., "Fire & Forge")
	while file.get_position() < file.get_length():
		var line = file.get_csv_line()
		# Assume first meaningful column (index 1 or 2 usually) holds the concept name
		# We'll search the whole line for the concept key just to be safe/robust
		var row_match = false
		for cell in line:
			if cell.strip_edges().to_upper() == concept_key.to_upper():
				row_match = true
				break
		
		if row_match and state_index < line.size():
			result = line[state_index]
			break
			
	file.close()
	return result

#endregion

# The following functions are not currently used by the Director/Actor model,
# but are kept as stubs for potential future use.

func get_theme_keywords(scenario: Dictionary) -> Dictionary:
	var _scenario = scenario
	return {}

func get_theme_concepts(scenario: Dictionary) -> Dictionary:
	var _scenario = scenario
	return {}

func analyze_theme_content(message: String) -> Dictionary:
	var _message = message
	return {}

func generate_theme_challenge(metrics: Dictionary) -> String:
	var _metrics = metrics
	return ""
