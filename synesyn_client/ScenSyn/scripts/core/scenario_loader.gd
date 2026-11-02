extends RefCounted
class_name ScenarioLoader

const WorkshopScenarioContractScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_scenario_contract.gd"
)
const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)

## ScenarioLoader — Loads and parses scenarios by Session Type and Collection.
##
## Scenario files are plain .txt files under:
##   res://ScenSyn/session_types/story_catalyst/<collection_id>/scenarios/<name>.txt
##   res://ScenSyn/session_types/workshop_catalyst/scenarios/<name>.txt
##
## Each file is divided into bracketed sections, e.g. [SCENARIO], [CHARACTERS],
## [SYSTEM_CONFIG]. The following sections are recognized by the loader:
##
##   [SCENARIO]        — Name, Objective, Location and Setting.
##   [CHARACTERS]      — One block per character (Name, Role, Persona, etc.).
##   [SYSTEM_CONFIG]   — Key: value pairs (keys lowercased on parse). Recognized keys:
##
##       speaker_name              System cue speaker label.
##       metric_template           Template for the live metric line.
##       max_words_brief           Word ceiling for "brief" cue cards.
##       max_words_default         Word ceiling for "default" cue cards.
##       reprompt_on_excess        "true"/"false" — reprompt instead of truncate.
##       director_model            Model id to use for Director batch calls only.
##                                 When set, the Director routes its LLM call to
##                                 this model rather than the global current model.
##                                 Leave unset to use the global current model.
##                                 Example: gpt-4o-mini
##       actor_model               Model id to use for every Actor call in this scenario.
##                                 When set, Actor calls route to this model.
##                                 Leave unset to use the global current model.
##                                 Example: claude-sonnet-4-6
##
##   [MEMORY_CONTINUITY] — Cross-session memory options (enabled, source_mode, depth).
##   [PHASE_GUIDANCE]    — Sub-sections (--- SETUP ---, --- ACT_1 ---) giving
##                         per-phase director/narrative instructions.
##   [STAGE_GUIDANCE]    — Workshop stage-specific instructions.
##   [DIRECTOR_ARCHETYPES] — Named archetypes with behavioral text per sub-section.
##   [TURN_OBLIGATIONS]  — Per-character turn-level obligations.
##   [WORKSHOP_PACKET]   — Free-text workshop framing for Catalyst-theme scenarios.
##   [WORKSHOP_AGENDA]   — JSON array defining workshop stages with durations.
##   [ABOUT]             — Human-readable scenario description (shown in the UI).
##   [HOW_TO]            — Human-readable facilitation instructions.
##   [LULL_PROTOCOL]     — Config for lull/silence detection and response.
##   [AMBIENT_SOUND]     — Ambient audio config.
##   [TIME_MODEL]        — Narrative time settings.
##   [VERSE_SYSTEM]      — Verse/precomposed-text config.
##   [VIS_STORY]         — Visual story export config.
##   [RELATIONAL_MATRIX] — Relational matrix schema.
##   [PLAYER_AUTO_INPUT] — Auto-input / simulation config.
##
## All unknown sections are collected into section_texts and are available to
## themes via scenario["section_texts"][section_name].

# Core data storage
var scenario_data = {}
var character_templates = []
var loaded_scenario_content = ""
var loaded_scenario_name: String = ""
var current_session_type: String = "story_catalyst"
var current_collection_id: String = "sustainability"

## Resolve a scenario resource path from its Session Type and Collection.
static func get_scenario_path(
	scenario_name: String,
	session_type_id: String,
	collection_id: String
) -> String:
	if session_type_id == "workshop_catalyst" and collection_id == "decision_triage":
		return (
			"res://ScenSyn/session_types/workshop_catalyst/scenarios/"
			+ scenario_name
			+ ".txt"
		)
	if session_type_id == "story_catalyst" and not collection_id.is_empty():
		return (
			"res://ScenSyn/session_types/story_catalyst/"
			+ collection_id
			+ "/scenarios/"
			+ scenario_name
			+ ".txt"
		)
	return ""

## Load a scenario from the specified Session Type and Collection.
## @param scenario_name: Name of the scenario file (without .txt extension)
## @param session_type_id: Session Type registry id.
## @param collection_id: Collection registry id.
## @return: true if loaded successfully, false otherwise
func load_scenario(
	scenario_name: String,
	session_type_id: String,
	collection_id: String
) -> bool:
	current_session_type = session_type_id
	current_collection_id = collection_id
	var file_path: String = get_scenario_path(
		scenario_name,
		session_type_id,
		collection_id
	)
	if file_path.is_empty():
		push_error(
			"ScenarioLoader: Unknown Session Type/Collection: %s/%s"
			% [session_type_id, collection_id]
		)
		_create_emergency_scenario(scenario_name)
		return false
	print("ScenarioLoader: Attempting to load scenario: ", file_path)
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		loaded_scenario_content = file.get_as_text()
		file.close()
		print("ScenarioLoader: Successfully loaded scenario file, size: ", loaded_scenario_content.length())
		
		# Parse the scenario text and attach helper metadata so downstream systems
		# (e.g., dramaturgy loaders) know the base directory and file name.
		scenario_data = parse_scenario_file(loaded_scenario_content)
		if session_type_id == "workshop_catalyst":
			var workshop_source: Dictionary = scenario_data.get("scenario", {}).duplicate(true)
			workshop_source["characters"] = scenario_data.get("characters", [])
			scenario_data["scenario"] = WorkshopScenarioContractScript.normalize(
				workshop_source
			)
			scenario_data["characters"] = []
		if scenario_data.has("scenario"):
			var scenario_dict: Dictionary = scenario_data.get("scenario", {}).duplicate()
			var base_dir: String = file_path.get_base_dir() + "/"
			scenario_dict["_base_dir"] = base_dir
			scenario_dict["_scenario_file"] = file_path
			scenario_dict["_scenario_name"] = scenario_name
			scenario_dict["_session_type_id"] = session_type_id
			scenario_dict["_collection_id"] = collection_id
			scenario_data["scenario"] = scenario_dict
		character_templates = scenario_data.get("characters", [])
		loaded_scenario_name = scenario_name
		print("ScenarioLoader: Parsed characters: ", character_templates.size(), " characters found")
		return true
	else:
		print("ScenarioLoader: ERROR - Could not open scenario file: ", file_path)
		print("ScenarioLoader: FileAccess error: ", FileAccess.get_open_error())
		
		# Create fallback scenario to prevent complete failure
		print("ScenarioLoader: Creating emergency fallback scenario...")
		_create_emergency_scenario(scenario_name)
		return false

## Parse scenario file content into structured data
## @param scenario_content: Raw text content of the scenario file
## @return: Dictionary containing parsed scenario and character data
func parse_scenario_file(scenario_content: String) -> Dictionary:
	var parsed_data = {}
	var current_section = ""
	var current_character = {}
	var characters = []
	var scenario = {}
	# Optional voices mapping parsed from [VOICES]
	var voices_mapping: Dictionary = {}
	# NEW: Optional voice overrides mapping parsed from [VOICE_OVERRIDES]
	var voice_overrides: Dictionary = {}
	# Optional dramaturgy matrix schema metadata
	var dramaturgy_schema: Dictionary = {}
		# Generic storage for ALL text sections (new approach)
	var section_texts: Dictionary = {}
	var time_model: Dictionary = {}
	# Special handling for PHASE_GUIDANCE with sub-sections
	var phase_guidance: Dictionary = {}
	# Workshop-stage guidance keyed by authored stage title
	var stage_guidance: Dictionary = {}
	# NEW: Special handling for DIRECTOR_ARCHETYPES with sub-sections
	var director_archetypes: Dictionary = {}
	# Key–value config block read from [SYSTEM_CONFIG].
	# All keys are lowercased on parse. Recognized keys are documented in the
	# class header above. The two new keys added in the prompt-budget refactor are:
	#   director_model — routes Director LLM calls to this model for this scenario.
	#   actor_model    — routes every Actor LLM call to this model for this scenario.
	# Both default to empty string, meaning "use the global current model".
	var system_config: Dictionary = {}
	# NEW: Player auto-input configuration
	var player_auto_input_config: Dictionary = {}
	# NEW: Scenario-scoped symbolic memory continuity configuration
	var memory_continuity: Dictionary = {}
	# NEW: Optional vis_story export configuration
	var vis_story_config: Dictionary = {}
	var verse_system_config: Dictionary = {}
	var turn_obligations: Dictionary = {}
	# NEW: Relational matrix schema
	var relational_schema: Dictionary = {}
	var lull_protocol_config: Dictionary = {}
	var lull_murmurs: Array[String] = []
	var ambient_sound_config: Dictionary = {}
	var current_phase = ""
	var current_stage_guidance = ""
	var current_archetype = ""
	var current_obligation_character = ""

	for line in scenario_content.split("\n"):
		var original_line = line
		line = line.strip_edges()
		
		if line.begins_with("[") and line.ends_with("]"):
			var inner = line.substr(1, line.length() - 2)
			# Real section headers (e.g. [SCENARIO], [HOW_TO], [END_OF_SCENARIO]) are a
			# single token with no nested brackets.  BBCode tags that span to a closing
			# tag (e.g. [b]text[/b]) always contain extra ] or [ inside because the
			# outer [ and ] belong to different tags.  This single check is sufficient
			# and future-proof: no real section name will ever contain [ or ].
			if inner.find("[") == -1 and inner.find("]") == -1:
				current_section = inner
			current_phase = "" # Reset phase when entering a new section
			current_stage_guidance = "" # Reset stage guidance when entering a new section
			current_archetype = "" # Reset archetype
		elif current_section == "PHASE_GUIDANCE":
			# Special parsing for phase sub-sections (e.g., "--- SETUP ---")
			if line.begins_with("---") and line.ends_with("---"):
				current_phase = line.replace("---", "").strip_edges().to_upper()
				phase_guidance[current_phase] = ""
			elif current_phase != "":
				phase_guidance[current_phase] += original_line + "\n"
		elif current_section == "STAGE_GUIDANCE":
			if line.begins_with("---") and line.ends_with("---"):
				current_stage_guidance = line.replace("---", "").strip_edges()
				stage_guidance[current_stage_guidance] = ""
			elif current_stage_guidance != "":
				stage_guidance[current_stage_guidance] += original_line + "\n"
		elif current_section == "DIRECTOR_ARCHETYPES":
			if line.begins_with("---") and line.ends_with("---"):
				current_archetype = line.replace("---", "").strip_edges().to_lower()
				director_archetypes[current_archetype] = ""
			elif current_archetype != "":
				director_archetypes[current_archetype] += original_line + "\n"
		elif current_section == "TURN_OBLIGATIONS":
			if line.begins_with("---") and line.ends_with("---"):
				current_obligation_character = line.replace("---", "").strip_edges()
				turn_obligations[current_obligation_character] = ""
			elif current_obligation_character != "" and line != "":
				turn_obligations[current_obligation_character] += original_line + "\n"
		elif current_section == "SYSTEM_CONFIG" and line != "":
			if line.begins_with("#"):
				pass # comment line — skip silently
			else:
				var parts = line.split(":", true, 1)
				if parts.size() == 2:
					var key = parts[0].strip_edges().to_lower()
					var value = parts[1].strip_edges()
					system_config[key] = value
		elif current_section == "TIME_MODEL" and line != "":
			var time_parts = line.split(":", true, 1)
			if time_parts.size() == 2:
				var time_key = time_parts[0].strip_edges().to_lower()
				var time_value = time_parts[1].strip_edges()
				time_model[time_key] = time_value
		elif current_section == "PLAYER_AUTO_INPUT" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				player_auto_input_config[key] = value
		elif current_section == "MEMORY_CONTINUITY" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				memory_continuity[key] = value
		elif current_section == "VIS_STORY" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				vis_story_config[key] = value
		elif current_section == "VERSE_SYSTEM" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				verse_system_config[key] = value
		elif current_section == "RELATIONAL_MATRIX" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				relational_schema[key] = value
		elif current_section == "SCENARIO" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				scenario[key] = value
		elif current_section == "VOICES" and line != "":
			# Support two formats:
			# 1) Name: en-US-JennyNeural
			# 2) Name: voice=en-US-JennyNeural, rate=+5%, volume=+0%, pitch=-10Hz
			var vparts = line.split(":", true, 1)
			if vparts.size() == 2:
				var char_name = vparts[0].strip_edges()
				var rhs = vparts[1].strip_edges()
				var conf: Dictionary = {}
				if rhs.find("=") == -1:
					conf["voice"] = rhs
				else:
					var tokens = rhs.split(",")
					for t in tokens:
						var tok = String(t).strip_edges()
						var kv = tok.split("=", true, 1)
						if kv.size() == 2:
							conf[kv[0].strip_edges().to_lower()] = kv[1].strip_edges()
				if not char_name.is_empty() and not conf.is_empty():
					voices_mapping[char_name] = conf
		elif current_section == "VOICE_OVERRIDES" and line != "":
			var oparts = line.split(":", true, 1)
			if oparts.size() == 2:
				var original_char = oparts[0].strip_edges()
				var override_char = oparts[1].strip_edges()
				if not original_char.is_empty() and not override_char.is_empty():
					voice_overrides[original_char] = override_char
		elif current_section == "DRAMATURGY_MATRIX" and line != "":
			# Declarative schema for optional dramaturgy matrix CSV parsing.
			# Scenarios can specify: type, file, key_column, field_columns, etc.
			var dm_parts = line.split(":", true, 1)
			if dm_parts.size() == 2:
				var dm_key = dm_parts[0].strip_edges().to_lower()
				var dm_value = dm_parts[1].strip_edges()
				if dm_key != "":
					dramaturgy_schema[dm_key] = dm_value
		elif current_section == "CHARACTERS":
			if line == "":
				continue  # Skip blank lines in CHARACTERS section
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				if key == "id":
					if not current_character.is_empty():
						characters.append(current_character)
					current_character = {"id": int(value)}
				elif key == "behavioral instructions":
					# Start collecting multi-line behavioral instructions
					current_character["behavioral_instructions"] = ""
				else:
					current_character[key] = value
			elif line.begins_with("-") and current_character.has("behavioral_instructions"):
				# Continuation of behavioral instructions
				current_character["behavioral_instructions"] += line + "\n"
		elif current_section == "LULL_PROTOCOL" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				lull_protocol_config[key] = value
		elif current_section == "LULL_MURMURS" and line != "":
			var murmur_line: String = line.strip_edges()
			if not murmur_line.is_empty():
				lull_murmurs.append(murmur_line)
		elif current_section == "AMBIENT_SOUND" and line != "":
			var parts = line.split(":", true, 1)
			if parts.size() == 2:
				var key = parts[0].strip_edges().to_lower()
				var value = parts[1].strip_edges()
				ambient_sound_config[key] = value
		elif current_section != "" and current_section not in ["SCENARIO", "VOICES", "CHARACTERS", "PHASE_GUIDANCE", "STAGE_GUIDANCE", "DIRECTOR_ARCHETYPES", "TURN_OBLIGATIONS", "SYSTEM_CONFIG", "TIME_MODEL", "PLAYER_AUTO_INPUT", "MEMORY_CONTINUITY", "VIS_STORY", "VERSE_SYSTEM", "RELATIONAL_MATRIX", "VOICE_OVERRIDES", "DRAMATURGY_MATRIX", "LULL_PROTOCOL", "LULL_MURMURS", "AMBIENT_SOUND"]:
			# Generic text section (INSTRUCTIONS, CONTEXT, WORKSHOP_PACKET, WORKSHOP_AGENDA, WORLDBUILDING_CONTEXT, DESIGN_PROVOCATIONS, PROPOSAL_OUTPUT_TEMPLATE, ABOUT, HOW_TO, etc.)
			# Section name like "HOW_TO" or "HOW TO" both become key "how_to_text"
			var key = current_section.to_lower().replace(" ", "_") + "_text"
			if not section_texts.has(key):
				section_texts[key] = ""
			section_texts[key] += line + "\n"

	if not current_character.is_empty():
		characters.append(current_character)

	# Map Location and Setting to description if present
	if scenario.has("location and setting") and not scenario.has("description"):
		scenario["description"] = scenario.get("location and setting", "")

	# Attach all text sections to the scenario
	for key in section_texts:
		scenario[key] = section_texts[key].strip_edges()
	
	# Attach phase guidance as a structured dictionary
	if not phase_guidance.is_empty():
		scenario["phase_guidance"] = phase_guidance
		print("ScenarioLoader: Parsed phase_guidance with keys: ", phase_guidance.keys())
	else:
		print("ScenarioLoader: WARNING - No phase guidance was parsed!")

	if not stage_guidance.is_empty():
		scenario["stage_guidance"] = stage_guidance
		print("ScenarioLoader: Parsed stage_guidance with keys: ", stage_guidance.keys())
	
	if not voices_mapping.is_empty():
		scenario["voices_mapping"] = voices_mapping

	if not voice_overrides.is_empty():
		scenario["voice_overrides"] = voice_overrides

	if not dramaturgy_schema.is_empty():
		scenario["dramaturgy_matrix"] = dramaturgy_schema

	if not director_archetypes.is_empty():
		scenario["director_archetypes"] = director_archetypes

	if not system_config.is_empty():
		scenario["system_config"] = system_config

	if not time_model.is_empty():
		scenario["time_model"] = time_model

	if not player_auto_input_config.is_empty():
		scenario["player_auto_input"] = player_auto_input_config

	if not memory_continuity.is_empty():
		scenario["memory_continuity"] = memory_continuity

	if not vis_story_config.is_empty():
		scenario["vis_story"] = vis_story_config

	if not verse_system_config.is_empty():
		scenario["verse_system"] = verse_system_config
		print("ScenarioLoader: Parsed verse_system with keys: ", verse_system_config.keys())

	if not turn_obligations.is_empty():
		scenario["turn_obligations"] = turn_obligations
		print("ScenarioLoader: Parsed turn_obligations for characters: ", turn_obligations.keys())

	if not relational_schema.is_empty():
		scenario["relational_matrix"] = relational_schema

	if not lull_protocol_config.is_empty():
		scenario["lull_protocol"] = lull_protocol_config
	if not lull_murmurs.is_empty():
		scenario["lull_murmurs"] = lull_murmurs
	if not ambient_sound_config.is_empty():
		scenario["ambient_sound"] = ambient_sound_config

	parsed_data["characters"] = characters
	parsed_data["scenario"] = scenario
	return parsed_data

## Generate character instances for the scenario
## @param count: Number of characters to generate
## @return: Array of character dictionaries ready for use
func generate_characters(count: int) -> Array:
	print("ScenarioLoader: Generating ", count, " characters from ", character_templates.size(), " templates")
	if character_templates.is_empty():
		print("Warning: No character templates available. Using default characters.")
		return _generate_default_characters(count)
	
	var characters = []
	for i in range(count):
		var index = i % character_templates.size()
		var character = character_templates[index].duplicate()
		
		# Ensure each character has a unique ID
		if not character.has("id") or character.get("id", -1) == -1:
			character["id"] = i
		
		character["is_player"] = false
		character["is_ai"] = true
		characters.append(character)
		
		print("ScenarioLoader: Generated character: ", character.get("name", "Unnamed"), " (ID: ", character.get("id", -1), ")")
	
	return characters

## Get the current scenario data
## @return: Dictionary containing scenario information
func get_current_scenario() -> Dictionary:
	var scenario_info = scenario_data.get("scenario", {})
	# Return the ENTIRE scenario_info dictionary, not just a subset
	var scenario = scenario_info.duplicate(true)
	# Add character templates
	scenario["characters"] = character_templates
	return scenario


func load_workshop_dictionary(source: Dictionary) -> bool:
	current_session_type = "workshop_catalyst"
	current_collection_id = "decision_triage"
	scenario_data = {
		"scenario": WorkshopScenarioContractScript.normalize(source),
		"characters": [],
	}
	character_templates = []
	loaded_scenario_name = String(
		scenario_data["scenario"].get("id", "custom_workshop_scenario")
	)
	loaded_scenario_content = ""
	return true


## Load a custom Open Play / Story Catalyst scenario from an in-memory dict
## (local draft or host-synced). Characters become the playable cast templates.
func load_story_dictionary(source: Dictionary) -> bool:
	current_session_type = "story_catalyst"
	current_collection_id = "open_play"
	var normalized: Dictionary = StoryScenarioContractScript.normalize(source)
	var characters_any: Variant = normalized.get("characters", [])
	var characters: Array = characters_any if typeof(characters_any) == TYPE_ARRAY else []
	scenario_data = {
		"scenario": normalized,
		"characters": characters,
	}
	character_templates = characters.duplicate(true)
	loaded_scenario_name = String(normalized.get("id", "custom_open_play_scenario"))
	loaded_scenario_content = ""
	return true

## Get the loaded scenario name
## @return: String name of the currently loaded scenario
func get_loaded_scenario_name() -> String:
	return loaded_scenario_name

func get_current_session_type() -> String:
	return current_session_type

func get_current_collection_id() -> String:
	return current_collection_id

## Generate default characters when templates are unavailable
## @param count: Number of default characters to create
## @return: Array of basic character dictionaries
func _generate_default_characters(count: int) -> Array:
	var default_characters = []
	for i in range(count):
		default_characters.append({
			"id": i,
			"name": "Default Character " + str(i),
			"role": "Unknown",
			"description": "No description available",
			"is_ai": true 
		})
	return default_characters

## Create an emergency fallback scenario when loading fails
## @param scenario_name: Name of the scenario that failed to load
func _create_emergency_scenario(scenario_name: String):
	print("ScenarioLoader: Creating emergency scenario for: ", scenario_name)
	
	# Basic fallback scenario with theme-neutral content
	scenario_data = {
		"scenario": {
			"name": "Emergency Scenario",
			"objective": "Navigate an unexpected situation",
			"description": "A basic scenario created as fallback when the requested scenario failed to load"
		},
		"characters": [
			{
				"id": 1,
				"name": "Emergency Character 1",
				"role": "Citizen",
				"description": "A concerned individual dealing with the situation"
			},
			{
				"id": 2,
				"name": "Emergency Character 2",
				"role": "Official",
				"description": "An authority figure trying to manage the situation"
			},
			{
				"id": 3,
				"name": "Emergency Character 3",
				"role": "Expert",
				"description": "A knowledgeable person providing insight"
			},
			{
				"id": 4,
				"name": "Emergency Character 4",
				"role": "Advocate",
				"description": "Someone advocating for a particular solution"
			}
		]
	}
	
	character_templates = scenario_data.get("characters", [])
	loaded_scenario_name = scenario_name
	loaded_scenario_content = "# Emergency scenario created due to scenario loading failure"
	
	print("ScenarioLoader: Emergency scenario created with ", character_templates.size(), " characters")

## Extract new scenario generation prompt (if available in loaded content)
## @return: String containing the new scenario prompt, or empty string if not found
func get_new_scenario_prompt() -> String:
	var new_scenario_prompt = ""
	var in_new_scenario = false
	
	for line in loaded_scenario_content.split("\n"):
		if line.strip_edges() == "[NEW_SCENARIO]":
			in_new_scenario = true
		elif in_new_scenario:
			new_scenario_prompt += line + "\n"
	
	if new_scenario_prompt != "":
		print("ScenarioLoader: Found new scenario generation prompt")
	else:
		print("ScenarioLoader: No [NEW_SCENARIO] section found")
	
	return new_scenario_prompt.strip_edges()
