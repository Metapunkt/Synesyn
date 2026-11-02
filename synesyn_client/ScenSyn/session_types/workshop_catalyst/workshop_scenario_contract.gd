extends RefCounted
class_name WorkshopScenarioContract

## Workshop-owned scenario compatibility and local-draft contract. Character
## fields are discarded only at this boundary; Story Catalyst data is untouched.

const SCHEMA_VERSION: int = 1
const CUSTOM_SCENARIO_ID: String = "custom_workshop_scenario"
## Legacy Godot app_userdata locations (migrated into Documents/Synesyn on read).
const _LEGACY_DRAFT_PATHS: Array[String] = [
	"user://scensyn/workshop_catalyst/scenario_draft_v1.json",
	"user://ScenSyn/workshop_catalyst/scenario_draft_v1.json",
]
const DEFAULT_DURATION_HOURS: float = 2.0
const ScenarioLibraryStoreScript = preload(
	"res://ScenSyn/scripts/core/scenario_library_store.gd"
)
const _LIBRARY_ID_PREFIX: String = "workshop"


static func local_draft_path() -> String:
	return RuntimeConfig.get_workshop_draft_path()


static func library_dir() -> String:
	return RuntimeConfig.get_workshop_scenarios_dir()


static func is_library_id(scenario_id: String) -> bool:
	var clean_id: String = scenario_id.strip_edges()
	return clean_id.begins_with(_LIBRARY_ID_PREFIX + "_") and clean_id != CUSTOM_SCENARIO_ID


## One beat per specialist lens, bracketed by the opening and closing acts of
## closure. "Weigh Who Is Affected" exists because the Stakeholder lens was the
## only one without a stage of its own, and authored Scenarios were compensating
## for that by hand.
## The Closure Audit stage (ADR 0020, PRD REQ-CA-014). Deliberately **not** in
## `DEFAULT_AGENDA`: the audit is opt-in through phases 1 and 2, and adding a seventh
## default stage would change what ADR 0012 asserts and what
## `test_workshop_scenario_and_map_corrections.gd` verifies. A scenario opts in by naming a
## stage with exactly this string in `[WORKSHOP_AGENDA]`; guidance then resolves by exact
## name like any other stage.
##
## Its guidance ships here anyway, so that an author who opts in gets the four-part contract
## without having to reconstruct the manual's sequence from the ADR — and so the wording has
## one home rather than being copied into each scenario that wants it.
const CLOSURE_AUDIT_STAGE_NAME: String = "Audit the Closure"

const CLOSURE_AUDIT_STAGE_GUIDANCE: String = """Facilitator goal: find out what this room has not examined, and decide what that costs. Work the sequence: name the decision under audit, orient each claim on the Closure Map, say why every thin quadrant is thin, triage what each absence would cost, read what the concentration means, then name the one transition required.
AI goal: describe the shape of the map without diagnosing it. Report which quadrants are empty, weak, dominant, or resting on a single voice, and where recorded views disagree — then stop. Whether an absence is irrelevant, excluded, unknown, suppressed, or not yet formed is the room's judgement, and offering one pre-empts the only step that makes this instrument worth running.
Required output before advancing: a stated decision under audit, a classification for every empty or weak quadrant, one tetrahedral transition in the form "dominant → neglected (edge XY) by <action>", and — where closure debt was recorded — at least one reopening action carrying an owner, a date, and what evidence would change the decision.
Decision-forcing question: "Which quadrant is thinnest, why is it thin, and would this decision differ if it were full? If it would, what are we doing about that and who owns it?"
"""

const DEFAULT_AGENDA: Array[Dictionary] = [
	{"name": "Frame the Scenario", "duration": 600},
	{"name": "Map Causes and Effects", "duration": 900},
	{"name": "Weigh Who Is Affected", "duration": 900},
	{"name": "Develop Options", "duration": 900},
	{"name": "Test Risks and Feasibility", "duration": 900},
	{"name": "Synthesize Decisions and Next Steps", "duration": 600},
]


static func normalize(source: Dictionary) -> Dictionary:
	var packet: Dictionary = _packet_from(source)
	var objective_text: String = String(
		source.get("objective", packet.get("objective", ""))
	).strip_edges()
	var normalized: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"id": String(source.get("id", source.get("_scenario_name", CUSTOM_SCENARIO_ID))).strip_edges(),
		"name": String(source.get("name", packet.get("title", "Untitled Scenario"))).strip_edges(),
		"objective": objective_text,
		"description": String(source.get("description", packet.get("context", ""))).strip_edges(),
		"workshop_packet": packet,
		"workshop_packet_text": _packet_text(packet),
		"workshop_agenda_text": _agenda_text(source),
		"time_model": _time_model(source.get("time_model", {})),
		"stage_guidance": _stage_guidance(source, objective_text),
		"system_config": _dictionary(source.get("system_config", {})),
		"about_text": String(source.get("about_text", "")).strip_edges(),
		"how_to_text": String(source.get("how_to_text", "")).strip_edges(),
		"_session_type_id": "workshop_catalyst",
		"_collection_id": "decision_triage",
		"persistence_state": String(source.get("persistence_state", "template")),
	}
	if String(normalized["id"]).is_empty():
		normalized["id"] = CUSTOM_SCENARIO_ID
	if String(normalized["name"]).is_empty():
		normalized["name"] = "Untitled Scenario"
	return normalized


static func create_custom(fields: Dictionary) -> Dictionary:
	var scenario_id: String = String(fields.get("id", CUSTOM_SCENARIO_ID)).strip_edges()
	if scenario_id.is_empty():
		scenario_id = CUSTOM_SCENARIO_ID
	return normalize({
		"id": scenario_id,
		"name": String(fields.get("title", "Untitled Scenario")),
		"objective": String(fields.get("objective", "")),
		"description": String(fields.get("context", "")),
		"workshop_packet": {
			"title": String(fields.get("title", "Untitled Scenario")),
			"objective": String(fields.get("objective", "")),
			"context": String(fields.get("context", "")),
			"desired_outcomes": _string_array(fields.get("desired_outcomes", [])),
			"constraints": _string_array(fields.get("constraints", [])),
			"time_horizon": String(fields.get("time_horizon", "")).strip_edges(),
			"relevant_perspectives": _string_array(fields.get("relevant_perspectives", [])),
			"evidence_notes": String(fields.get("evidence_notes", "")).strip_edges(),
		},
		"workshop_agenda_text": JSON.stringify([{
			"day": 1,
			"stages": DEFAULT_AGENDA.duplicate(true),
		}]),
		"time_model": {
			"default_session_duration_hours": DEFAULT_DURATION_HOURS,
			"allow_session_duration_override": true,
			"default_multi_day": false,
			"stage_timing_mode": "scalable",
		},
		"persistence_state": "local_draft",
	})


static func save_local_draft(scenario: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize(scenario)
	normalized["id"] = CUSTOM_SCENARIO_ID
	normalized["persistence_state"] = "local_draft"
	return ScenarioLibraryStoreScript.save_draft(normalized, local_draft_path())


static func load_local_draft() -> Dictionary:
	var raw: Dictionary = ScenarioLibraryStoreScript.load_draft_raw(
		local_draft_path(),
		_LEGACY_DRAFT_PATHS
	)
	if raw.is_empty():
		return {}
	var normalized: Dictionary = normalize(raw)
	normalized["id"] = CUSTOM_SCENARIO_ID
	normalized["persistence_state"] = "local_draft"
	return normalized


## Persist a Scenario into the selectable Workshop library.
##
## Workshop previously had only the single draft file, so importing or saving a
## second Scenario meant destroying the facilitator's working draft. The library
## mirrors Open Play: one file per Scenario, ids minted on save.
##
## `sync_draft` keeps the working draft pointing at the latest save so the
## editor reopens it. Imports pass false — a shared Scenario must never
## overwrite what the facilitator was authoring.
static func save_to_library(scenario: Dictionary, sync_draft: bool = true) -> Dictionary:
	var normalized: Dictionary = normalize(scenario)
	ScenarioLibraryStoreScript.carry_metadata(normalized, scenario)
	var scenario_id: String = String(normalized.get("id", "")).strip_edges()
	if scenario_id.is_empty() or scenario_id == CUSTOM_SCENARIO_ID:
		scenario_id = make_unique_id(String(normalized.get("name", "Untitled Scenario")))
	normalized["id"] = scenario_id
	var persistence: String = String(normalized.get("persistence_state", ""))
	normalized["persistence_state"] = persistence if persistence == "imported" else "saved"
	normalized["saved_at"] = ScenarioLibraryStoreScript.saved_at_stamp()
	var result: Dictionary = ScenarioLibraryStoreScript.save_entry(
		normalized,
		library_dir(),
		scenario_id
	)
	if bool(result.get("ok", false)) and sync_draft:
		save_local_draft(normalized)
	return result


static func load_saved_scenario(scenario_id: String) -> Dictionary:
	var clean_id: String = scenario_id.strip_edges()
	if clean_id.is_empty():
		return {}
	if clean_id == CUSTOM_SCENARIO_ID:
		return load_local_draft()
	var raw: Dictionary = ScenarioLibraryStoreScript.load_entry_raw(library_dir(), clean_id)
	if raw.is_empty():
		return {}
	var normalized: Dictionary = normalize(raw)
	ScenarioLibraryStoreScript.carry_metadata(normalized, raw)
	normalized["id"] = clean_id
	if String(normalized.get("persistence_state", "")).is_empty():
		normalized["persistence_state"] = "saved"
	return normalized


## Returns entries newest-first: {id, name, objective, saved_at, path}.
static func list_saved_scenarios() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var lib_dir: String = library_dir()
	for scenario_id: String in ScenarioLibraryStoreScript.list_entry_ids(lib_dir):
		var loaded: Dictionary = load_saved_scenario(scenario_id)
		if loaded.is_empty():
			continue
		entries.append({
			"id": scenario_id,
			"name": String(loaded.get("name", "Untitled Scenario")),
			"objective": String(loaded.get("objective", "")),
			"saved_at": String(loaded.get("saved_at", "")),
			"path": lib_dir.path_join(scenario_id + ".json"),
		})
	ScenarioLibraryStoreScript.sort_entries_newest_first(entries)
	return entries


static func make_unique_id(display_name: String) -> String:
	return ScenarioLibraryStoreScript.make_unique_id(
		_LIBRARY_ID_PREFIX,
		display_name,
		"scenario"
	)


static func _packet_from(source: Dictionary) -> Dictionary:
	var packet_any: Variant = source.get("workshop_packet", {})
	var packet: Dictionary = _dictionary(packet_any)
	if packet.is_empty():
		var context_text: String = String(
			source.get("workshop_packet_text", source.get("description", ""))
		)
		context_text = _strip_legacy_roleplay_text(context_text, source.get("characters", []))
		packet = {
			"title": String(source.get("name", "Untitled Scenario")),
			"objective": String(source.get("objective", "")),
			"context": context_text,
			"desired_outcomes": [],
			"constraints": [],
			"time_horizon": "",
			"relevant_perspectives": [],
			"evidence_notes": "",
		}
	for list_key: String in ["desired_outcomes", "constraints", "relevant_perspectives"]:
		packet[list_key] = _string_array(packet.get(list_key, []))
	return packet


static func _strip_legacy_roleplay_text(source_text: String, characters_any: Variant) -> String:
	var legacy_names: Array[String] = []
	if typeof(characters_any) == TYPE_ARRAY:
		for character_any: Variant in characters_any:
			if typeof(character_any) != TYPE_DICTIONARY:
				continue
			var legacy_name: String = String(
				(character_any as Dictionary).get("name", "")
			).strip_edges()
			if not legacy_name.is_empty():
				legacy_names.append(legacy_name)
	var retained: Array[String] = []
	for line_text: String in source_text.split("\n"):
		var lower_line: String = line_text.to_lower()
		var should_drop: bool = (
			lower_line.contains("4 characters")
			or lower_line.contains("stay in-role")
			or lower_line.contains("stay in role")
			or lower_line.contains("ai- or human-controlled")
			or lower_line.begins_with("roles in this workshop")
		)
		for legacy_name: String in legacy_names:
			if line_text.contains(legacy_name):
				should_drop = true
				break
		if not should_drop:
			retained.append(line_text)
	return "\n".join(retained).strip_edges()


static func _packet_text(packet: Dictionary) -> String:
	var lines: Array[String] = [
		"Title: " + String(packet.get("title", "")),
		"Central question/objective: " + String(packet.get("objective", "")),
		"Context: " + String(packet.get("context", "")),
		"Time horizon: " + String(packet.get("time_horizon", "")),
	]
	_append_list(lines, "Desired outcomes", packet.get("desired_outcomes", []))
	_append_list(lines, "Constraints", packet.get("constraints", []))
	_append_list(lines, "Relevant stakeholders/perspectives", packet.get("relevant_perspectives", []))
	var evidence_notes: String = String(packet.get("evidence_notes", "")).strip_edges()
	if not evidence_notes.is_empty():
		lines.append("Evidence/context notes: " + evidence_notes)
	return "\n".join(lines)


static func _append_list(lines: Array[String], heading: String, values_any: Variant) -> void:
	var values: Array[String] = _string_array(values_any)
	if values.is_empty():
		return
	lines.append(heading + ":")
	for value_text: String in values:
		lines.append("- " + value_text)


## A Scenario without stage guidance leaves the AI running on generic core rules
## for the whole session, so the default agenda ships with its own stage
## contracts. Authored guidance always wins.
static func _stage_guidance(source: Dictionary, objective_text: String) -> Dictionary:
	var authored: Dictionary = _dictionary(source.get("stage_guidance", {}))
	if not authored.is_empty():
		return authored
	return default_stage_guidance(objective_text)


static func default_stage_guidance(objective_text: String) -> Dictionary:
	var frame_guidance: String = """Facilitator goal: agree what this session is deciding, what is in and out of scope, and what a good enough outcome looks like by the end.
AI goal: keep the framing concrete, surface assumptions hiding inside the question, and stop the group solving before it has agreed what it is solving.
Required output before advancing: one agreed decision question for this session, one scope boundary, and one success criterion.
Decision-forcing question: "Can we agree that we are deciding this: [proposed question]? If not, what specifically needs to change?"
"""
	if not objective_text.is_empty():
		frame_guidance += "Scenario objective on record: " + objective_text + "\n"
	return {
		"Frame the Scenario": frame_guidance,
		"Map Causes and Effects": """Facilitator goal: build a workable picture of what drives the current situation and what follows from it, before anyone proposes a fix.
AI goal: infer root causes, dependencies, and second-order effects from what the room has actually said, and prefer mapping over advocacy.
Required output before advancing: the two most fragile points in the current situation, and one structural limit on what any intervention here can achieve.
Decision-forcing question: "Of everything on this map, which single point is most fragile, and who is responsible for it right now?"
""",
		"Weigh Who Is Affected": """Facilitator goal: establish who lives with the consequences of this decision, and who currently has no say in it.
AI goal: reason from inside the affected positions, surface framing gaps, and make quiet or displaced harms visible instead of letting fairness stay rhetorical.
Required output before advancing: name the group most likely to bear the cost of getting this wrong, and one effect that would be displaced rather than removed.
Decision-forcing question: "Who carries the cost if this goes wrong, and are they represented in this room?"
""",
		"Develop Options": """Facilitator goal: generate genuinely distinct options, including doing nothing, without selecting between them yet.
AI goal: hold each provisional alternative open long enough to be examined, and offer reframings without choosing for the group.
Required output before advancing: at least two distinct options plus the do-nothing option, each stated concretely enough to be tested, and one note on whether the affected parties would recognise the option as addressing their problem.
Decision-forcing question: "What are we actually choosing between? State each option in one sentence, including doing nothing."
""",
		"Test Risks and Feasibility": """Facilitator goal: break the options before committing to one, and find out which survive real constraints.
AI goal: narrow each option against the stated constraints, name what would predictably backfire, and say what would best explain a failure if this were to fail.
Required output before advancing: one named risk with a likelihood and a cost-bearer, and one option eliminated or amended on feasibility grounds.
Decision-forcing question: "If we do this and it fails, what will have caused it, and who pays for that?"
""",
		"Synthesize Decisions and Next Steps": """Facilitator goal: reduce the discussion to the decision record, and confirm what is being consciously deferred rather than left ambiguous.
AI goal: compress without flattening the live tensions, and surface any unresolved question that deserves an explicit owner and reason.
Required output: at least one decision with an owning role and confidence level, one named risk with a cost-bearer, and one deferred question with an owner and a reason.
Decision-forcing question: "What are we carrying out of this room, what are we naming as a risk, and what one question are we parking, and who owns it?"
""",
		CLOSURE_AUDIT_STAGE_NAME: CLOSURE_AUDIT_STAGE_GUIDANCE,
	}


static func _agenda_text(source: Dictionary) -> String:
	var authored: String = String(source.get("workshop_agenda_text", "")).strip_edges()
	if not authored.is_empty():
		return authored
	return JSON.stringify([{"day": 1, "stages": DEFAULT_AGENDA.duplicate(true)}])


static func _time_model(value_any: Variant) -> Dictionary:
	var time_model: Dictionary = _dictionary(value_any)
	if time_model.is_empty():
		return {
			"default_session_duration_hours": DEFAULT_DURATION_HOURS,
			"allow_session_duration_override": true,
			"default_multi_day": false,
			"stage_timing_mode": "scalable",
		}
	return time_model


static func _string_array(value_any: Variant) -> Array[String]:
	return ScenarioLibraryStoreScript.string_array(value_any)


static func _dictionary(value_any: Variant) -> Dictionary:
	return ScenarioLibraryStoreScript.to_dictionary(value_any)
