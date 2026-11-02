extends RefCounted
class_name WorkshopSpecialistPrompts

## Prompt text for Workshop Catalyst specialist inference. Kept separate from
## parsing/recovery so the coordinator stays under the soft line limit.

const PromptContextBuilderScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_prompt_context_builder.gd"
)
const ResumeHydrateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_resume_hydrate.gd"
)


static func build_full(
	role_definitions: Array,
	cross_checks: Array,
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary
) -> String:
	var role_lines: Array[String] = _role_lines(role_definitions)
	var cross_check_lines: Array[String] = _cross_check_lines(cross_checks)
	var curated_context: Dictionary = _curated_context(
		story_log,
		human_input,
		scenario,
		workshop_state
	)
	var stage_text: String = String(
		workshop_state.get("current_stage_name", "Unspecified")
	).strip_edges()
	var map_context_section: String = thinking_map_context_section(workshop_state)
	return """You are producing a batched, independent specialist review for a facilitated workshop.
Return concise analytical outputs, not private chain-of-thought. Specialists do not vote, choose,
ratify, or create decisions. They may surface concerns and options for a facilitator to consider.

WORKSHOP: %s
CURRENT STAGE: %s
LATEST FACILITATOR INPUT: %s

SCENARIO CONTEXT:
%s

RECENT TRANSCRIPT:
%s

FACILITATOR-AUTHORIZED SESSION RECORD:
%s
%s

CONTROLLED SPECIALIST ROLES:
%s

DOMAIN ADOPTION:
Each role adopts the domain expertise the current subject matter requires and reasons from inside
it. Never name, announce, or perform the adopted expertise, never attribute any output to it, and
never introduce it as a participant. Adopted expertise does not raise the evidential standing of a
claim: anything a participant did not state and retrieved evidence does not support remains
ai_inferred.

CROSS-LENS CHECKS:
%s

OUTPUT FORMAT (STRICT JSON, no markdown):
{"schema_version":1,"contributions":[{"role_id":"systems_consequences","summary":"..."},{"role_id":"stakeholder_communication","summary":"..."},{"role_id":"risk_feasibility","summary":"..."},{"role_id":"options_innovation","summary":"..."}],"map_candidates":[{"id":"local-stable-key","category":"cause|effect|opportunity","proposition":"concise scenario proposition","source_class":"participant_said|ai_inferred|external_evidence_supported","source_refs":["turn-or-trace-ref"],"rationale":"brief basis, not chain-of-thought","confidence":0.0,"evidence_status":"unknown|unsupported|supported|contested","relates_to":[{"target_id":"another-local-stable-key-in-this-same-array","relation":"causes|supports|contradicts|evidenced_by|related_to"}]}],"facilitator_cues":["brief process guidance"],"assistant_response":"2-5 concise paragraphs for the facilitator"}

Return exactly one non-empty summary per listed role, in that order. Each summary is at most
three sentences. Do not include votes, Yes/No ballots, hidden reasoning, confidence theatre,
or claims that a decision has been made.
The assistant_response is the only participant-facing response. Synthesize the specialist
summaries without listing them mechanically or revealing hidden internal analysis. Work the
cross-lens checks that the current stage's required output depends on, and prefer a check no
role raised on its own over restating agreement between roles. Do not name, number, or
enumerate the checks in the response.

MAP EXTRACTION RULES:
- Cause is a factor driving the scenario condition.
- Effect is an actual or plausible consequence.
- Opportunity is an intervention, opening, option, or actionable possibility.
- Propositions must be concise scenario claims, not facilitation instructions or status text.
- For substantive input that states a driver, consequence, or possible intervention, return at
  least one map candidate. Do not leave map_candidates empty merely because the facilitator did
  not use the words cause, effect, or opportunity.
- Put process/meta guidance only in facilitator_cues. Never turn instructions, clarification
  requests, preview/commit guidance, unavailable-context notices, or "the group should decide"
  language into map_candidates.
- Return an empty map_candidates array when no reliable semantic candidate is supported.
- relates_to is optional. Only add an entry when this candidate's relationship to another
  candidate you are returning in this same map_candidates array is clearly supported: target_id
  must be one of the ids you assigned in this same batch, never an id from a prior turn. Omit
  relates_to, or leave it an empty array, when no relation is clearly supported. Never fabricate
  a relation to fill the field.
""" % [
		String(scenario.get("name", "Workshop")),
		stage_text,
		String(human_input.get("message", "")).strip_edges(),
		String(curated_context.get("scenario", "")),
		String(curated_context.get("recent_transcript", "")),
		String(curated_context.get("session_record", "")),
		map_context_section,
		"\n".join(role_lines),
		"\n".join(cross_check_lines),
	]


static func build_roles(
	role_definitions: Array,
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary
) -> String:
	var role_lines: Array[String] = _role_lines(role_definitions)
	var curated_context: Dictionary = _curated_context(
		story_log,
		human_input,
		scenario,
		workshop_state
	)
	return """You are producing four independent specialist summaries for a facilitated workshop.
Return concise analytical outputs only. Do not vote, choose, or create decisions.

WORKSHOP: %s
CURRENT STAGE: %s
LATEST FACILITATOR INPUT: %s

SCENARIO CONTEXT:
%s

RECENT TRANSCRIPT:
%s

FACILITATOR-AUTHORIZED SESSION RECORD:
%s

CONTROLLED SPECIALIST ROLES:
%s

DOMAIN ADOPTION:
Adopt the domain expertise the subject matter requires. Never name, announce, or perform it,
never attribute output to it, and never introduce it as a participant. Adopted expertise does
not raise evidential standing.

OUTPUT FORMAT (STRICT JSON, no markdown):
{"contributions":[{"role_id":"systems_consequences","summary":"..."},{"role_id":"stakeholder_communication","summary":"..."},{"role_id":"risk_feasibility","summary":"..."},{"role_id":"options_innovation","summary":"..."}]}

Return exactly one non-empty summary per listed role, in that order. Each summary is at most
three sentences. Do not include map candidates, facilitator cues, or an assistant_response.
""" % [
		String(scenario.get("name", "Workshop")),
		String(workshop_state.get("current_stage_name", "Unspecified")).strip_edges(),
		String(human_input.get("message", "")).strip_edges(),
		String(curated_context.get("scenario", "")),
		String(curated_context.get("recent_transcript", "")),
		String(curated_context.get("session_record", "")),
		"\n".join(role_lines),
	]


static func build_synthesis(
	cross_checks: Array,
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary,
	contributions: Array
) -> String:
	var summary_lines: Array[String] = []
	for contribution_any: Variant in contributions:
		if typeof(contribution_any) != TYPE_DICTIONARY:
			continue
		var contribution: Dictionary = contribution_any
		summary_lines.append(
			"- %s: %s"
			% [
				String(contribution.get("role_id", "")),
				String(contribution.get("summary", "")).strip_edges(),
			]
		)
	var cross_check_lines: Array[String] = _cross_check_lines(cross_checks)
	var curated_context: Dictionary = _curated_context(
		story_log,
		human_input,
		scenario,
		workshop_state
	)
	var map_context_section: String = thinking_map_context_section(workshop_state)
	return """You are synthesizing an already-complete specialist review for a facilitated workshop.
The four role summaries below are fixed. Do not invent a fifth specialist voice. Do not vote
or create decisions.

WORKSHOP: %s
CURRENT STAGE: %s
LATEST FACILITATOR INPUT: %s

SCENARIO CONTEXT:
%s

RECENT TRANSCRIPT:
%s

FACILITATOR-AUTHORIZED SESSION RECORD:
%s
%s

FIXED SPECIALIST SUMMARIES:
%s

CROSS-LENS CHECKS:
%s

OUTPUT FORMAT (STRICT JSON, no markdown):
{"schema_version":1,"map_candidates":[{"id":"local-stable-key","category":"cause|effect|opportunity","proposition":"concise scenario proposition","source_class":"participant_said|ai_inferred|external_evidence_supported","source_refs":["turn-or-trace-ref"],"rationale":"brief basis, not chain-of-thought","confidence":0.0,"evidence_status":"unknown|unsupported|supported|contested","relates_to":[{"target_id":"another-local-stable-key-in-this-same-array","relation":"causes|supports|contradicts|evidenced_by|related_to"}]}],"facilitator_cues":["brief process guidance"],"assistant_response":"2-5 concise paragraphs for the facilitator"}

assistant_response is the only participant-facing response. Synthesize the fixed summaries
without listing them mechanically. Work the cross-lens checks the current stage needs, and
prefer a check no role raised alone over restating agreement. Do not name or enumerate the
checks.

MAP EXTRACTION RULES:
- Cause is a factor driving the scenario condition.
- Effect is an actual or plausible consequence.
- Opportunity is an intervention, opening, option, or actionable possibility.
- Propositions must be concise scenario claims, not facilitation instructions or status text.
- Put process/meta guidance only in facilitator_cues.
- Return an empty map_candidates array when no reliable semantic candidate is supported.
- relates_to is optional. Only add an entry when this candidate's relationship to another
  candidate you are returning in this same map_candidates array is clearly supported: target_id
  must be one of the ids you assigned in this same batch. Omit relates_to, or leave it an empty
  array, when no relation is clearly supported.
""" % [
		String(scenario.get("name", "Workshop")),
		String(workshop_state.get("current_stage_name", "Unspecified")).strip_edges(),
		String(human_input.get("message", "")).strip_edges(),
		String(curated_context.get("scenario", "")),
		String(curated_context.get("recent_transcript", "")),
		String(curated_context.get("session_record", "")),
		map_context_section,
		"\n".join(summary_lines),
		"\n".join(cross_check_lines),
	]


static func thinking_map_context_section(workshop_state: Dictionary) -> String:
	var context_any: Variant = workshop_state.get("thinking_map_prompt_context", {})
	if typeof(context_any) == TYPE_DICTIONARY and not (context_any as Dictionary).is_empty():
		var context_payload: Dictionary = context_any
		var artifact_id: String = String(context_payload.get("artifact_id", "")).strip_edges()
		var trace_ref: String = String(context_payload.get("trace_ref", "")).strip_edges()
		var items_any: Variant = context_payload.get("items", [])
		if not artifact_id.is_empty() and not trace_ref.is_empty() and typeof(items_any) == TYPE_ARRAY:
			var map_lines: Array[String] = []
			for item_any: Variant in (items_any as Array):
				if map_lines.size() >= 12:
					break
				if typeof(item_any) != TYPE_DICTIONARY:
					continue
				var item_data: Dictionary = item_any
				var label_text: String = String(item_data.get("label", "")).strip_edges()
				if not label_text.is_empty():
					map_lines.append(
						"- [%s] %s"
						% [String(item_data.get("category", "item")), label_text.left(300)]
					)
			if not map_lines.is_empty():
				return "\nCOMMITTED THINKING MAP CONTEXT (explicitly enabled; trace %s, artifact %s):\n%s" % [
					trace_ref,
					artifact_id,
					"\n".join(map_lines),
				]
	if String(workshop_state.get("resume_mode", "")) != "continue_prior_session":
		return ""
	var resume_lines: Array[String] = ResumeHydrateScript.thinking_map_resume_lines(
		workshop_state,
		12
	)
	if resume_lines.is_empty():
		return ""
	return "\nRESUMED THINKING MAP (carried forward from the saved session):\n%s" % [
		"\n".join(resume_lines),
	]


static func _role_lines(role_definitions: Array) -> Array[String]:
	var role_lines: Array[String] = []
	for role_definition_any: Variant in role_definitions:
		if typeof(role_definition_any) != TYPE_DICTIONARY:
			continue
		var role_definition: Dictionary = role_definition_any
		role_lines.append(
			"- %s: %s\n  Method: %s"
			% [
				String(role_definition["id"]),
				String(role_definition["brief"]),
				String(role_definition["method"]),
			]
		)
	return role_lines


static func _cross_check_lines(cross_checks: Array) -> Array[String]:
	var lines: Array[String] = []
	for cross_check_any: Variant in cross_checks:
		lines.append("- " + String(cross_check_any))
	return lines


static func _curated_context(
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary
) -> Dictionary:
	var context_builder: RefCounted = PromptContextBuilderScript.new()
	return context_builder.call(
		"build",
		story_log,
		human_input,
		scenario,
		workshop_state
	)
