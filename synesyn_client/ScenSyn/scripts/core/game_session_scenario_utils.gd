extends RefCounted
class_name GameSessionScenarioUtils

## Scenario description and voice setup, split from the narrative helpers to
## keep each runtime module within the project line limit.


static func setup_scenario_display(owner: Node) -> void:
	var game_flow_manager: Variant = owner.get("game_flow_manager")
	if not game_flow_manager:
		push_error("GameSession: game_flow_manager unavailable for Scenario display")
		return
	var scenario: Dictionary = game_flow_manager.get_current_scenario()
	owner.set("current_scenario", scenario)
	if scenario.is_empty():
		return
	var title_label_node: Label = owner.get("scenario_title_label")
	var objective_label_node: RichTextLabel = owner.get("objective_label")
	title_label_node.text = scenario.get("name", "Unnamed Scenario")
	objective_label_node.text = _scenario_description(scenario)
	_set_optional_tab(
		owner.get_node_or_null("%AboutTabLabel"),
		String(scenario.get("about_text", "")),
		"No additional information available for this Scenario."
	)
	_set_optional_tab(
		owner.get_node_or_null("%HowToTabLabel"),
		String(scenario.get("how_to_text", "")),
		"No how-to guidance available for this Scenario."
	)
	var is_workshop: bool = Global and Global.current_session_type == "workshop_catalyst"
	if is_workshop:
		return
	apply_character_voice_mappings(owner, scenario)
	owner.call("_enable_voice_for_scenario_characters")
	if scenario.has("voices_mapping"):
		var config: Dictionary = RuntimeConfig.load_config()
		var voice_config: Dictionary = config.get("voice", {})
		var provider_mode: String = String(
			voice_config.get("provider_mode", "direct")
		).strip_edges().to_lower()
		if provider_mode == "direct":
			post_voices_mapping_to_server(owner, scenario["voices_mapping"])


static func apply_character_voice_mappings(owner: Node, scenario: Dictionary) -> void:
	if typeof(VoiceService) == TYPE_NIL or scenario.is_empty():
		return
	var scenario_voices: Dictionary = {}
	if typeof(scenario.get("voices_mapping", {})) == TYPE_DICTIONARY:
		scenario_voices = scenario.get("voices_mapping", {})
	# The flow manager's copy is sometimes taken before [VOICES] is attached.
	# The loader still has the parsed block. Using the pool in that window is
	# what made a character's first line the wrong voice and every later line
	# the right one.
	if scenario_voices.is_empty():
		scenario_voices = _voices_from_loader()
	var declared_speakers: Array = collect_declared_speaker_names(scenario)
	if declared_speakers.is_empty():
		for voice_key_any: Variant in scenario_voices.keys():
			_add_unique(declared_speakers, voice_key_any)
	if declared_speakers.is_empty():
		return
	var voice_pool: Array[String] = [
		"en-US-JennyNeural",
		"en-GB-RyanNeural",
		"en-US-GuyNeural",
		"en-US-ChristopherNeural",
		"en-US-AriaNeural",
	]
	for speaker_name_any: Variant in declared_speakers:
		var speaker_name: String = String(speaker_name_any)
		var selected_voice: String = ""
		var selected_config: Dictionary = {}
		var voice_key := _matching_voice_key(scenario_voices, speaker_name)
		if voice_key != "":
			var config_any: Variant = scenario_voices[voice_key]
			if typeof(config_any) == TYPE_DICTIONARY and (config_any as Dictionary).has("voice"):
				selected_voice = String((config_any as Dictionary)["voice"])
				selected_config = (config_any as Dictionary).duplicate(true)
			else:
				selected_voice = String(config_any)
		else:
			# A full config already came from the scenario file. The pool is
			# only for a speaker the block never names.
			if _keeps_installed_voice(speaker_name):
				continue
			var voice_index: int = int(
				owner.call("_stable_index_from_name", speaker_name, voice_pool.size())
			)
			selected_voice = voice_pool[voice_index]
		if not selected_config.is_empty() and VoiceService.has_method("set_character_voice_config"):
			VoiceService.set_character_voice_config(speaker_name, selected_config)
		else:
			VoiceService.set_character_voice(speaker_name, selected_voice)


static func _voices_from_loader() -> Dictionary:
	if Global == null or not Global.has_method("get_scenario_loader"):
		return {}
	var loader: Object = Global.get_scenario_loader()
	if loader == null or not loader.has_method("get_current_scenario"):
		return {}
	var raw: Variant = loader.get_current_scenario()
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var voices_any: Variant = (raw as Dictionary).get("voices_mapping", {})
	if typeof(voices_any) != TYPE_DICTIONARY or (voices_any as Dictionary).is_empty():
		return {}
	return (voices_any as Dictionary).duplicate(true)


static func _matching_voice_key(voices: Dictionary, speaker_name: String) -> String:
	if speaker_name == "" or voices.is_empty():
		return ""
	if voices.has(speaker_name):
		return speaker_name
	var want := speaker_name.strip_edges().to_lower()
	var alternate := (
		speaker_name.trim_prefix("The ").strip_edges()
		if speaker_name.begins_with("The ")
		else "The " + speaker_name
	)
	var alternate_lower := alternate.strip_edges().to_lower()
	for key_any: Variant in voices.keys():
		var key := str(key_any).strip_edges()
		var lowered := key.to_lower()
		if lowered == want or lowered == alternate_lower:
			return key
	return ""


static func _keeps_installed_voice(speaker_name: String) -> bool:
	if typeof(VoiceService) == TYPE_NIL or VoiceService == null:
		return false
	if not VoiceService.has_method("get_character_voices"):
		return false
	var voices: Dictionary = VoiceService.get_character_voices()
	var raw: Variant = voices.get(speaker_name, "")
	return typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("voice", "")).strip_edges() != ""


static func collect_declared_speaker_names(scenario: Dictionary) -> Array:
	var speaker_names: Array = []
	for character_any: Variant in scenario.get("characters", []):
		if typeof(character_any) == TYPE_DICTIONARY:
			_add_unique(speaker_names, (character_any as Dictionary).get("name", ""))
	var voices_any: Variant = scenario.get("voices_mapping", {})
	if typeof(voices_any) == TYPE_DICTIONARY:
		for speaker_key_any: Variant in (voices_any as Dictionary).keys():
			_add_unique(speaker_names, speaker_key_any)
	var overrides_any: Variant = scenario.get("voice_overrides", {})
	if typeof(overrides_any) == TYPE_DICTIONARY:
		for source_any: Variant in (overrides_any as Dictionary).keys():
			_add_unique(speaker_names, source_any)
			_add_unique(speaker_names, (overrides_any as Dictionary)[source_any])
	var special_any: Variant = scenario.get("special_speakers", [])
	if typeof(special_any) == TYPE_ARRAY:
		for special_speaker_any: Variant in special_any:
			_add_unique(speaker_names, special_speaker_any)
	return speaker_names


static func post_voices_mapping_to_server(owner: Node, voices_mapping: Dictionary) -> void:
	var payload: Dictionary = {"character_voices": {}}
	for speaker_key_any: Variant in voices_mapping.keys():
		var config_any: Variant = voices_mapping[speaker_key_any]
		payload.character_voices[speaker_key_any] = (
			config_any if typeof(config_any) == TYPE_DICTIONARY else String(config_any)
		)
	var http_node := HTTPRequest.new()
	owner.add_child(http_node)
	var request_error: Error = http_node.request(
		"http://127.0.0.1:8000/set_character_voices",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if request_error != OK:
		http_node.queue_free()
		return
	http_node.request_completed.connect(
		func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			http_node.queue_free()
	)


static func _scenario_description(scenario: Dictionary) -> String:
	var display_text: String = (
		"[font_size=18][b]Scenario Objective[/b][/font_size]\n\n"
		+ String(scenario.get("objective", "No objective set"))
		+ "\n\n"
	)
	var is_workshop: bool = Global and Global.current_session_type == "workshop_catalyst"
	if is_workshop:
		var packet_any: Variant = scenario.get("workshop_packet", {})
		var packet: Dictionary = packet_any if typeof(packet_any) == TYPE_DICTIONARY else {}
		var perspectives_any: Variant = packet.get("relevant_perspectives", [])
		if typeof(perspectives_any) == TYPE_ARRAY and not (perspectives_any as Array).is_empty():
			display_text += "[font_size=18][b]Relevant stakeholders / perspectives[/b][/font_size]\n\n"
			for perspective_any: Variant in perspectives_any:
				display_text += "• " + String(perspective_any).strip_edges() + "\n"
		return display_text
	display_text += "[font_size=18][b]Characters[/b][/font_size]\n\n"
	var characters: Array = scenario.get("characters", [])
	for character_index: int in range(characters.size()):
		var character: Dictionary = characters[character_index]
		display_text += "[b]%s[/b]: %s - %s" % [
			character.get("name", "Unnamed"),
			character.get("role", "Unknown Role"),
			character.get("description", "No description available"),
		]
		if character_index < characters.size() - 1:
			display_text += "\n\n"
	return display_text


static func _set_optional_tab(
	label_node: RichTextLabel,
	content_text: String,
	fallback_text: String
) -> void:
	if not label_node:
		return
	var clean_text: String = content_text.strip_edges()
	label_node.text = clean_text if not clean_text.is_empty() else "[i]%s[/i]" % fallback_text


static func _add_unique(values: Array, value_any: Variant) -> void:
	var value_text: String = String(value_any).strip_edges()
	if not value_text.is_empty() and value_text not in values:
		values.append(value_text)
