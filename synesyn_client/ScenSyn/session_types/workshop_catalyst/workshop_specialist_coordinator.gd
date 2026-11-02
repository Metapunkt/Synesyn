extends RefCounted
class_name WorkshopSpecialistCoordinator

## Produces all independent specialist summaries in one model operation.
## These are concise review outputs, never hidden reasoning tokens or votes.

const StatelessModelTaskScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_stateless_model_task.gd"
)
const SpecialistPromptsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_specialist_prompts.gd"
)
const ParticipantMapExtractorScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_participant_map_extractor.gd"
)

## Each role carries the reasoning method its brief already implies. Naming the
## method makes it instructable; it does not add a role or a visible voice.
const ROLE_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "systems_consequences",
		"title": "Systems & Consequences",
		"brief": "Identify root causes, dependencies, and second-order effects.",
		"method": "Abductive inference. Construct the most plausible account of an incomplete pattern.",
	},
	{
		"id": "stakeholder_communication",
		"title": "Stakeholder & Communication",
		"brief": "Identify affected stakeholders, framing gaps, and communication needs.",
		"method": "Perspective adoption. Reason from inside an affected position without performing it.",
	},
	{
		"id": "risk_feasibility",
		"title": "Risk & Feasibility",
		"brief": "Identify concrete failure modes, constraints, and implementation risks.",
		"method": "Iterative narrowing. Test a claim against constraints until only what survives remains.",
	},
	{
		"id": "options_innovation",
		"title": "Options & Innovation",
		"brief": "Offer alternatives and useful reframings without choosing for the group.",
		"method": "Counterfactual framing. Hold a provisional alternative open long enough to examine it.",
	},
]

## The six pairings of the four roles. Single-lens output misses the questions a
## facilitated room most often skips, and each pairing below is already demanded
## by authored stage guidance somewhere in the shipped Scenarios.
const CROSS_CHECKS: Array[String] = [
	"systems_consequences + stakeholder_communication: who absorbs the second-order effects, and where harm is displaced rather than removed.",
	"systems_consequences + options_innovation: where an intervention would actually take hold, given the dependencies.",
	"systems_consequences + risk_feasibility: the structural limit on what any intervention here can achieve.",
	"stakeholder_communication + risk_feasibility: who bears the cost when this fails, and whether they have any say.",
	"stakeholder_communication + options_innovation: whether affected parties would accept or even recognise the alternative.",
	"options_innovation + risk_feasibility: which alternatives survive the constraints, and which predictably backfire.",
]
const MAP_SCHEMA_VERSION: int = 1
const MAP_CATEGORIES: Array[String] = ["cause", "effect", "opportunity"]
const SOURCE_CLASSES: Array[String] = [
	"participant_said",
	"ai_inferred",
	"external_evidence_supported",
]
const EVIDENCE_STATUSES: Array[String] = [
	"unknown",
	"unsupported",
	"supported",
	"contested",
]
## Mirrors ThinkingMapAdapter.RELATIONS. Kept as a separate controlled vocabulary
## here (rather than importing the adapter) so the coordinator stays free of any
## Thinking Map/product dependency; the two lists must be kept in sync by hand.
const RELATIONS: Array[String] = [
	"causes",
	"supports",
	"contradicts",
	"evidenced_by",
	"related_to",
]
const MAX_RELATES_TO: int = 4
const META_MARKERS: Array[String] = [
	"stay on topic",
	"ask for clarification",
	"the group should decide",
	"the facilitator should",
	"preview",
	"commit",
	"unavailable",
	"status message",
	"cannot retain",
	"could not retain",
	"no context",
	"continue the discussion",
]


func collect(
	conversation_manager: Variant,
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary
) -> Dictionary:
	var started_at: String = Time.get_datetime_string_from_system(true)
	var model_id: String = _resolve_model_id(conversation_manager, scenario)
	if conversation_manager == null:
		return _fallback_result("", "conversation_unavailable", started_at, model_id)
	var model_override: String = _resolve_specialist_model(scenario)
	var first_response: Dictionary = await _request_model(
		conversation_manager,
		build_prompt(story_log, human_input, scenario, workshop_state),
		model_override,
		"workshop_specialist_batch"
	)
	if not bool(first_response.get("success", false)):
		var failed_result: Dictionary = _fallback_result(
			"",
			"request_failed",
			started_at,
			model_id
		)
		failed_result["assistant_response"] = (
			"The specialist model could not be reached for this turn. "
			+ "Your submitted statement is retained, and any directly stated "
			+ "map proposition remains available for facilitator review."
		)
		failed_result["recovery_path"] = "none"
		return _with_participant_map_candidates(failed_result, human_input)
	var primary: Dictionary = parse_response(
		String(first_response.get("response", "")),
		started_at,
		model_id
	)
	if String(primary.get("status", "")) == "complete":
		primary["recovery_path"] = "single"
		return _with_participant_map_candidates(primary, human_input)
	# Soften packaging, not coverage: only escalate when the full envelope failed.
	var recovered: Dictionary = await _collect_two_phase(
		conversation_manager,
		story_log,
		human_input,
		scenario,
		workshop_state,
		started_at,
		model_id,
		model_override,
		primary
	)
	return _with_participant_map_candidates(recovered, human_input)


func _collect_two_phase(
	conversation_manager: Variant,
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary,
	started_at: String,
	model_id: String,
	model_override: String,
	primary_failure: Dictionary
) -> Dictionary:
	var roles_response: Dictionary = await _request_model(
		conversation_manager,
		build_roles_prompt(story_log, human_input, scenario, workshop_state),
		model_override,
		"workshop_specialist_roles"
	)
	if not bool(roles_response.get("success", false)):
		primary_failure["recovery_path"] = "two_phase_aborted"
		return primary_failure
	var roles_result: Dictionary = parse_roles_response(
		String(roles_response.get("response", "")),
		started_at,
		model_id
	)
	if String(roles_result.get("status", "")) != "complete":
		primary_failure["recovery_path"] = "two_phase_roles_failed"
		return primary_failure
	var contributions: Array = roles_result.get("contributions", [])
	var synthesis_response: Dictionary = await _request_model(
		conversation_manager,
		build_synthesis_prompt(
			story_log,
			human_input,
			scenario,
			workshop_state,
			contributions
		),
		model_override,
		"workshop_specialist_synthesis"
	)
	if not bool(synthesis_response.get("success", false)):
		return _roles_only_result(
			contributions,
			started_at,
			model_id,
			"phase2_request_failed"
		)
	var synthesis_result: Dictionary = parse_synthesis_response(
		String(synthesis_response.get("response", "")),
		contributions,
		started_at,
		model_id
	)
	if not synthesis_result.has("recovery_path"):
		synthesis_result["recovery_path"] = "two_phase"
	return synthesis_result


func _request_model(
	conversation_manager: Variant,
	prompt: String,
	model_override: String,
	thread_suffix: String
) -> Dictionary:
	var task_runner: RefCounted = StatelessModelTaskScript.new()
	var response: Variant
	if task_runner.call("can_run", conversation_manager):
		response = await task_runner.call(
			"run",
			conversation_manager,
			prompt,
			model_override
		)
	else:
		response = await conversation_manager.chat(
			prompt,
			_scoped_thread_name(conversation_manager, thread_suffix),
			model_override
		)
	if typeof(response) != TYPE_DICTIONARY:
		return {"success": false, "response": "", "error": "invalid_response"}
	return response


func _roles_only_result(
	contributions: Array,
	started_at: String,
	model_id: String,
	failure_reason: String
) -> Dictionary:
	var typed_contributions: Array[Dictionary] = []
	for contribution_any: Variant in contributions:
		if typeof(contribution_any) == TYPE_DICTIONARY:
			typed_contributions.append(contribution_any)
	var result: Dictionary = _result(
		typed_contributions,
		"degraded",
		failure_reason,
		started_at,
		model_id,
		[],
		[],
		[{"reason": failure_reason}],
		_deterministic_assistant_response(typed_contributions)
	)
	result["synthesis_source"] = "deterministic"
	result["recovery_path"] = "two_phase_roles_only"
	return result


func build_prompt(
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary
) -> String:
	return SpecialistPromptsScript.build_full(
		ROLE_DEFINITIONS,
		CROSS_CHECKS,
		story_log,
		human_input,
		scenario,
		workshop_state
	)


func build_roles_prompt(
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary
) -> String:
	return SpecialistPromptsScript.build_roles(
		ROLE_DEFINITIONS,
		story_log,
		human_input,
		scenario,
		workshop_state
	)


func build_synthesis_prompt(
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary,
	contributions: Array
) -> String:
	return SpecialistPromptsScript.build_synthesis(
		CROSS_CHECKS,
		story_log,
		human_input,
		scenario,
		workshop_state,
		contributions
	)


func parse_response(
	raw_response: String,
	started_at: String = "",
	model_id: String = ""
) -> Dictionary:
	var parsed: Dictionary = _parse_json_object(raw_response)
	if parsed.is_empty():
		return _fallback_result(raw_response, "malformed_json", started_at, model_id)
	var roles_result: Dictionary = _normalize_contributions(
		parsed.get("contributions", []),
		raw_response,
		started_at,
		model_id
	)
	if String(roles_result.get("status", "")) != "complete":
		return roles_result
	var normalized: Array[Dictionary] = roles_result.get("contributions", [])
	var schema_version_any: Variant = parsed.get("schema_version", MAP_SCHEMA_VERSION)
	# Full-envelope replies without schema_version still accept map candidates when present.
	if not parsed.has("schema_version") and parsed.has("map_candidates"):
		schema_version_any = MAP_SCHEMA_VERSION
	var candidate_result: Dictionary = _normalize_map_candidates(
		parsed.get("map_candidates", []),
		schema_version_any
	)
	var facilitator_cues: Array[String] = _normalize_facilitator_cues(
		parsed.get("facilitator_cues", [])
	)
	var assistant_response: String = String(
		parsed.get("assistant_response", "")
	).strip_edges().left(5000)
	var synthesis_source: String = "model"
	if assistant_response.is_empty():
		assistant_response = _deterministic_assistant_response(normalized)
		synthesis_source = "deterministic"
	var result: Dictionary = _result(
		normalized,
		"complete",
		"",
		started_at,
		model_id,
		candidate_result.get("accepted", []),
		facilitator_cues,
		candidate_result.get("rejected", []),
		assistant_response
	)
	result["synthesis_source"] = synthesis_source
	return result


func parse_roles_response(
	raw_response: String,
	started_at: String = "",
	model_id: String = ""
) -> Dictionary:
	var parsed: Dictionary = _parse_json_object(raw_response)
	if parsed.is_empty():
		return _fallback_result(raw_response, "malformed_json", started_at, model_id)
	return _normalize_contributions(
		parsed.get("contributions", []),
		raw_response,
		started_at,
		model_id
	)


func parse_synthesis_response(
	raw_response: String,
	contributions: Array,
	started_at: String = "",
	model_id: String = ""
) -> Dictionary:
	var typed_contributions: Array[Dictionary] = []
	for contribution_any: Variant in contributions:
		if typeof(contribution_any) == TYPE_DICTIONARY:
			typed_contributions.append(contribution_any)
	if typed_contributions.size() != ROLE_DEFINITIONS.size():
		return _fallback_result(raw_response, "incomplete_roles", started_at, model_id)
	var parsed: Dictionary = _parse_json_object(raw_response)
	if parsed.is_empty():
		return _roles_only_result(
			typed_contributions,
			started_at,
			model_id,
			"phase2_malformed_json"
		)
	var schema_version_any: Variant = parsed.get("schema_version", MAP_SCHEMA_VERSION)
	if not parsed.has("schema_version") and parsed.has("map_candidates"):
		schema_version_any = MAP_SCHEMA_VERSION
	var candidate_result: Dictionary = _normalize_map_candidates(
		parsed.get("map_candidates", []),
		schema_version_any
	)
	var facilitator_cues: Array[String] = _normalize_facilitator_cues(
		parsed.get("facilitator_cues", [])
	)
	var assistant_response: String = String(
		parsed.get("assistant_response", "")
	).strip_edges().left(5000)
	var synthesis_source: String = "model"
	var status_id: String = "complete"
	var failure_reason: String = ""
	if assistant_response.is_empty():
		assistant_response = _deterministic_assistant_response(typed_contributions)
		synthesis_source = "deterministic"
		status_id = "degraded"
		failure_reason = "phase2_missing_assistant_response"
	var result: Dictionary = _result(
		typed_contributions,
		status_id,
		failure_reason,
		started_at,
		model_id,
		candidate_result.get("accepted", []),
		facilitator_cues,
		candidate_result.get("rejected", []),
		assistant_response
	)
	result["synthesis_source"] = synthesis_source
	return result


func _parse_json_object(raw_response: String) -> Dictionary:
	var cleaned: String = _extract_json_object(raw_response)
	var parser := JSON.new()
	if parser.parse(cleaned) != OK:
		return {}
	var parsed_any: Variant = parser.data
	if typeof(parsed_any) != TYPE_DICTIONARY:
		return {}
	return parsed_any


func _normalize_contributions(
	contribution_values_any: Variant,
	raw_response: String,
	started_at: String,
	model_id: String
) -> Dictionary:
	if typeof(contribution_values_any) != TYPE_ARRAY:
		return _fallback_result(raw_response, "missing_contributions", started_at, model_id)
	var by_role: Dictionary = {}
	for contribution_any: Variant in contribution_values_any:
		if typeof(contribution_any) != TYPE_DICTIONARY:
			continue
		var contribution: Dictionary = contribution_any
		var role_id: String = String(contribution.get("role_id", "")).strip_edges()
		var summary_text: String = String(contribution.get("summary", "")).strip_edges()
		if _is_known_role(role_id) and not summary_text.is_empty() and not by_role.has(role_id):
			by_role[role_id] = summary_text.left(1200)
	if by_role.size() != ROLE_DEFINITIONS.size():
		return _fallback_result(raw_response, "incomplete_roles", started_at, model_id)
	var normalized: Array[Dictionary] = []
	for role_definition: Dictionary in ROLE_DEFINITIONS:
		var role_id: String = String(role_definition["id"])
		normalized.append(_contribution_record(role_definition, String(by_role[role_id])))
	var result: Dictionary = _result(
		normalized,
		"complete",
		"",
		started_at,
		model_id,
		[],
		[],
		[],
		""
	)
	return result


func _fallback_result(
	raw_response: String,
	failure_reason: String,
	started_at: String,
	model_id: String
) -> Dictionary:
	var safe_excerpt: String = raw_response.strip_edges().replace("\n", " ").left(500)
	var contributions: Array[Dictionary] = []
	for role_definition: Dictionary in ROLE_DEFINITIONS:
		var summary_text: String = (
			"Specialist output was unavailable for this role."
			if safe_excerpt.is_empty()
			else "The batch response could not be structured reliably; no role-specific claim was retained."
		)
		contributions.append(_contribution_record(role_definition, summary_text))
	return _result(
		contributions,
		"degraded",
		failure_reason,
		started_at,
		model_id,
		[],
		[],
		[{"reason": failure_reason}],
		_deterministic_assistant_response(contributions)
	)


func _result(
	contributions: Array[Dictionary],
	status_id: String,
	failure_reason: String,
	started_at: String,
	model_id: String,
	map_candidates: Array = [],
	facilitator_cues: Array[String] = [],
	rejected_candidates: Array = [],
	assistant_response: String = ""
) -> Dictionary:
	return {
		"schema_version": MAP_SCHEMA_VERSION,
		"contributions": contributions,
		"map_candidates": map_candidates,
		"facilitator_cues": facilitator_cues,
		"assistant_response": assistant_response,
		"rejected_candidates": rejected_candidates,
		"status": status_id,
		"failure_reason": failure_reason,
		"model_id": model_id,
		"started_at": started_at,
		"completed_at": Time.get_datetime_string_from_system(true),
	}


func _deterministic_assistant_response(
	contributions: Array[Dictionary]
) -> String:
	var usable: Array[String] = []
	for contribution: Dictionary in contributions:
		var summary_text: String = String(
			contribution.get("summary", "")
		).strip_edges()
		if (
			not summary_text.is_empty()
			and not summary_text.contains("could not be structured")
			and not summary_text.contains("was unavailable")
		):
			usable.append(summary_text)
	if usable.is_empty():
		return (
			"I could not retain a reliable specialist analysis for this turn. "
			+ "Please retry or continue with a more specific workshop prompt."
		)
	return "Key considerations from this turn:\n\n" + "\n\n".join(
		usable.slice(0, mini(usable.size(), 3))
	)


func _with_participant_map_candidates(
	result: Dictionary,
	human_input: Dictionary
) -> Dictionary:
	var existing_any: Variant = result.get("map_candidates", [])
	if typeof(existing_any) == TYPE_ARRAY and not (existing_any as Array).is_empty():
		return result
	var extractor: RefCounted = ParticipantMapExtractorScript.new()
	var extracted: Array = extractor.call(
		"extract",
		String(human_input.get("message", ""))
	)
	var normalized: Dictionary = _normalize_map_candidates(
		extracted,
		MAP_SCHEMA_VERSION
	)
	var accepted: Array = normalized.get("accepted", [])
	if accepted.is_empty():
		return result
	result["map_candidates"] = accepted
	result["candidate_delivery_status"] = "local_validated"
	result["map_candidate_origin"] = "participant_statement"
	var rejected_any: Variant = result.get("rejected_candidates", [])
	var rejected: Array = (
		rejected_any.duplicate(true)
		if typeof(rejected_any) == TYPE_ARRAY
		else []
	)
	rejected.append_array(normalized.get("rejected", []))
	result["rejected_candidates"] = rejected
	return result


func _normalize_map_candidates(values_any: Variant, schema_version_any: Variant) -> Dictionary:
	var accepted: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	if int(schema_version_any) != MAP_SCHEMA_VERSION:
		return {
			"accepted": accepted,
			"rejected": [{"reason": "unsupported_map_schema_version"}],
		}
	if typeof(values_any) != TYPE_ARRAY:
		return {
			"accepted": accepted,
			"rejected": [{"reason": "map_candidates_not_array"}],
		}
	var semantic_keys: Dictionary = {}
	for candidate_any: Variant in values_any:
		if typeof(candidate_any) != TYPE_DICTIONARY:
			rejected.append({"reason": "candidate_not_object"})
			continue
		var normalized: Dictionary = _normalize_map_candidate(candidate_any)
		var rejection_reason: String = String(normalized.get("rejection_reason", ""))
		if not rejection_reason.is_empty():
			rejected.append({
				"reason": rejection_reason,
				"id": String((candidate_any as Dictionary).get("id", "")).left(120),
			})
			continue
		var semantic_key: String = String(normalized.get("semantic_key", ""))
		if semantic_keys.has(semantic_key):
			rejected.append({
				"reason": "duplicate_semantic_key",
				"id": String(normalized.get("id", "")),
			})
			continue
		semantic_keys[semantic_key] = true
		normalized.erase("semantic_key")
		accepted.append(normalized)
	return {"accepted": accepted, "rejected": rejected}


func _normalize_map_candidate(candidate: Dictionary) -> Dictionary:
	var category_id: String = String(candidate.get("category", "")).strip_edges().to_lower()
	var proposition: String = String(
		candidate.get("proposition", candidate.get("text", ""))
	).strip_edges()
	var source_class: String = String(candidate.get("source_class", "")).strip_edges()
	var evidence_status: String = String(candidate.get("evidence_status", "")).strip_edges()
	var source_refs_any: Variant = candidate.get("source_refs", [])
	if category_id not in MAP_CATEGORIES:
		return {"rejection_reason": "unknown_category"}
	if proposition.length() < 12 or proposition.split(" ").size() < 3:
		return {"rejection_reason": "empty_or_vague_proposition"}
	if _is_meta_candidate(proposition):
		return {"rejection_reason": "facilitation_or_meta_guidance"}
	if source_class not in SOURCE_CLASSES or typeof(source_refs_any) != TYPE_ARRAY:
		return {"rejection_reason": "malformed_provenance"}
	var source_refs: Array[String] = []
	for source_ref_any: Variant in source_refs_any:
		var source_ref: String = String(source_ref_any).strip_edges()
		if not source_ref.is_empty():
			source_refs.append(source_ref.left(240))
	if source_refs.is_empty():
		return {"rejection_reason": "malformed_provenance"}
	if evidence_status not in EVIDENCE_STATUSES:
		return {"rejection_reason": "invalid_evidence_status"}
	var confidence_value: float = clampf(float(candidate.get("confidence", 0.0)), 0.0, 1.0)
	var semantic_key: String = (
		category_id + "|" + proposition.to_lower().strip_edges()
	).sha256_text()
	var candidate_id: String = String(candidate.get("id", "")).strip_edges()
	if candidate_id.is_empty():
		candidate_id = "map_" + semantic_key.left(16)
	candidate_id = candidate_id.left(120)
	var relates_to: Array[Dictionary] = _normalize_relates_to(
		candidate.get("relates_to", []),
		candidate_id
	)
	return {
		"id": candidate_id,
		"category": category_id,
		"proposition": proposition.left(500),
		"source_class": source_class,
		"source_refs": source_refs,
		"rationale": String(candidate.get("rationale", "")).strip_edges().left(500),
		"confidence": confidence_value,
		"evidence_status": evidence_status,
		"relates_to": relates_to,
		"semantic_key": semantic_key,
	}


## Validates model-declared candidate-to-candidate references. Resolution of
## target_id against actual accepted node ids happens later, once duplicate
## rejection and stable-node-id assignment are known (see
## ThinkingMapAdapter.specialist_candidate_commands); this stage only rejects
## structurally invalid entries.
func _normalize_relates_to(values_any: Variant, own_candidate_id: String) -> Array[Dictionary]:
	var relates_to: Array[Dictionary] = []
	if typeof(values_any) != TYPE_ARRAY:
		return relates_to
	var seen_pairs: Dictionary = {}
	for relation_any: Variant in (values_any as Array):
		if relates_to.size() >= MAX_RELATES_TO:
			break
		if typeof(relation_any) != TYPE_DICTIONARY:
			continue
		var relation_entry: Dictionary = relation_any
		var target_id: String = String(
			relation_entry.get("target_id", "")
		).strip_edges().left(120)
		var relation_id: String = String(
			relation_entry.get("relation", "")
		).strip_edges().to_lower()
		if target_id.is_empty() or target_id == own_candidate_id:
			continue
		if relation_id not in RELATIONS:
			continue
		var pair_key: String = target_id + "|" + relation_id
		if seen_pairs.has(pair_key):
			continue
		seen_pairs[pair_key] = true
		relates_to.append({"target_id": target_id, "relation": relation_id})
	return relates_to


func _normalize_facilitator_cues(values_any: Variant) -> Array[String]:
	var cues: Array[String] = []
	if typeof(values_any) != TYPE_ARRAY:
		return cues
	for cue_any: Variant in values_any:
		var cue_text: String = String(cue_any).strip_edges()
		if not cue_text.is_empty() and cue_text not in cues:
			cues.append(cue_text.left(300))
	return cues.slice(0, mini(cues.size(), 6))


func _is_meta_candidate(proposition: String) -> bool:
	var lower_text: String = proposition.to_lower()
	for marker: String in META_MARKERS:
		if lower_text.contains(marker):
			return true
	return (
		lower_text.begins_with("ask ")
		or lower_text.begins_with("please ")
		or lower_text.begins_with("facilitator:")
	)


func _contribution_record(role_definition: Dictionary, summary_text: String) -> Dictionary:
	return {
		"role_id": String(role_definition["id"]),
		"role_title": String(role_definition["title"]),
		"summary": summary_text,
		"vote": null,
	}


func _is_known_role(role_id: String) -> bool:
	for role_definition: Dictionary in ROLE_DEFINITIONS:
		if String(role_definition["id"]) == role_id:
			return true
	return false


func _strip_code_fence(raw_response: String) -> String:
	var cleaned: String = raw_response.strip_edges()
	if not cleaned.begins_with("```"):
		return cleaned
	var first_newline: int = cleaned.find("\n")
	if first_newline >= 0:
		cleaned = cleaned.substr(first_newline + 1)
	var final_fence: int = cleaned.rfind("```")
	if final_fence >= 0:
		cleaned = cleaned.substr(0, final_fence)
	return cleaned.strip_edges()


func _extract_json_object(raw_response: String) -> String:
	var cleaned: String = _strip_code_fence(raw_response)
	var object_start: int = cleaned.find("{")
	if object_start < 0:
		return cleaned
	var depth: int = 0
	var is_inside_string: bool = false
	var is_escaped: bool = false
	for char_index: int in range(object_start, cleaned.length()):
		var current_char: String = cleaned[char_index]
		if is_inside_string:
			if is_escaped:
				is_escaped = false
			elif current_char == "\\":
				is_escaped = true
			elif current_char == "\"":
				is_inside_string = false
			continue
		if current_char == "\"":
			is_inside_string = true
		elif current_char == "{":
			depth += 1
		elif current_char == "}":
			depth -= 1
			if depth == 0:
				return cleaned.substr(
					object_start,
					char_index - object_start + 1
				)
	return cleaned


func _resolve_specialist_model(scenario: Dictionary) -> String:
	var config_any: Variant = scenario.get("system_config", {})
	var config: Dictionary = config_any if typeof(config_any) == TYPE_DICTIONARY else {}
	return String(config.get("specialist_model", "")).strip_edges()


func _resolve_model_id(conversation_manager: Variant, scenario: Dictionary) -> String:
	var override_id: String = _resolve_specialist_model(scenario)
	if not override_id.is_empty():
		return override_id
	if (
		conversation_manager
		and "ai_model_manager" in conversation_manager
		and conversation_manager.ai_model_manager
		and conversation_manager.ai_model_manager.has_method("get_current_model")
	):
		return String(conversation_manager.ai_model_manager.get_current_model()).strip_edges()
	return "default"


func _scoped_thread_name(conversation_manager: Variant, suffix: String) -> String:
	if conversation_manager and conversation_manager.has_method("get_current_thread"):
		var base_thread: String = String(
			conversation_manager.get_current_thread()
		).strip_edges()
		if not base_thread.is_empty():
			return base_thread + "__" + suffix
	return suffix
