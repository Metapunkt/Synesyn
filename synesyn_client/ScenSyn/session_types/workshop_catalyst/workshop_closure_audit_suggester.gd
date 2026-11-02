extends RefCounted
class_name WorkshopClosureAuditSuggester

## Purpose: ask a model to draft answers to the Closure Audit's steps, on demand, for the
## facilitator to accept, edit or discard (REQ-CA-021).
##
## This reverses nothing about who decides. ADR 0020's amendment held that the audit's
## diagnostics must not be inferred, and that still holds — of the *record*. What it got wrong
## was to conclude that nothing may therefore be drafted. The rest of this system already
## separates the two: a specialist's claim arrives as `suggested` and waits for review, and an
## orientation suggestion is explicitly not a tag. An audit with no assistance does not produce
## more human judgement; it produces a blank panel and a facilitator who skips it, which is a
## worse outcome for the same reason a careless tag is worse than an absent one.
##
## So: everything here is a proposal held outside `WorkshopClosureAuditRecord`. Nothing reaches
## the record without a press. The completion gate counts record entries only, so an audit
## cannot be completed by suggestions alone no matter how many come back.
##
## Two things are deliberately not suggested.
##
## Closure debt is a declaration that the room is knowingly leaving something unresolved, and
## its four conditions ask what the room did — whether the gap was named aloud, whether anyone
## dissented. A model reading the map has no access to any of that, and a plausible-sounding
## answer would forge a record of the room's own conduct.
##
## An action's owner and date are the same kind of fact: who agreed to do it, and by when. The
## model drafts what to do and what would settle it, and leaves the commitment blank, because a
## commitment nobody made is the one part of a reopening action that cannot be corrected later
## by reading it again.

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)
const DiagnosticsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_diagnostics.gd"
)
const StatelessModelTaskScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_stateless_model_task.gd"
)

## Past this the envelope grows long enough that mid-tier models truncate the JSON, and the
## audit's own reading is drawn from the distribution rather than from every individual line.
const MAX_CLAIMS_PER_PASS: int = 30

## More than this and the facilitator is reviewing a backlog rather than a suggestion.
const MAX_REOPENING_ACTIONS: int = 3


## `claims` holds `{"id", "kind", "label", "orientation"}`; `findings` is the rules module's
## reading of the same map.
func request(
	conversation_manager: Variant,
	claims: Array,
	findings: Dictionary,
	thin_quadrants: Array,
	decision_text: String = ""
) -> Dictionary:
	var usable_claims: Array[Dictionary] = _usable_claims(claims)
	if usable_claims.is_empty():
		return _failure("no_claims_to_audit")
	if not bool(findings.get("has_reading", false)):
		# Every step below reads the distribution. Drafting them over a map too sparse to
		# have one would produce answers about a shape that is not there yet.
		return _failure("map_not_readable")
	var task_runner: RefCounted = StatelessModelTaskScript.new()
	if not task_runner.can_run(conversation_manager):
		return _failure("model_unavailable")
	var response: Variant = await task_runner.run(
		conversation_manager,
		build_prompt(usable_claims, findings, thin_quadrants, decision_text)
	)
	if typeof(response) != TYPE_DICTIONARY:
		return _failure("invalid_response")
	var response_data: Dictionary = response
	if not bool(response_data.get("success", false)):
		return _failure(str(response_data.get("error", "request_failed")))
	return parse_response(str(response_data.get("response", "")), thin_quadrants, findings)


static func build_prompt(
	claims: Array,
	findings: Dictionary,
	thin_quadrants: Array,
	decision_text: String
) -> String:
	var dominant: String = String(findings.get("dominant_quadrant", ""))
	var lines: Array[String] = [
		"You are assisting a facilitator running a Closure Audit on a workshop's Thinking",
		"Map. The audit asks what the room has not examined. Draft an answer to each step",
		"below. The facilitator reviews every answer and accepts, edits or discards it, so",
		"give your single best reading rather than hedging.",
		"",
		"The four positions claims are tagged with:",
	]
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		lines.append("- %s = %s. %s" % [
			quadrant_id,
			ClosureOrientationScript.get_canonical_with_gloss(quadrant_id),
			String(ClosureOrientationScript.CHARACTER_BY_QUADRANT.get(quadrant_id, "")),
		])
	lines.append_array(["", "How this map came out:"])
	var coverage: Dictionary = findings.get("coverage", {})
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		lines.append("- %s: %d claim(s)" % [quadrant_id, int(coverage.get(quadrant_id, 0))])
	if not dominant.is_empty():
		lines.append("- %s holds the most." % dominant)
	if not thin_quadrants.is_empty():
		lines.append("- Thin (empty or nearly so): %s" % ", ".join(
			PackedStringArray(_as_string_array(thin_quadrants))
		))
	if not decision_text.strip_edges().is_empty():
		lines.append("- The facilitator says the decision under audit is: %s" % decision_text)
	lines.append_array(["", "Claims on the map:"])
	for claim_any: Variant in claims:
		if typeof(claim_any) != TYPE_DICTIONARY:
			continue
		var claim: Dictionary = claim_any
		var orientation: String = str(claim.get("orientation", "")).strip_edges()
		lines.append("- [%s%s] %s" % [
			str(claim.get("kind", "")),
			", %s" % orientation if not orientation.is_empty() else ", untagged",
			str(claim.get("label", "")),
		])
	lines.append_array([
		"",
		"Draft these.",
		"",
		"1. decision: one sentence naming the decision this map is being read in order to",
		"   make. Infer it from the claims. If the facilitator already stated one above,",
		"   repeat theirs unchanged.",
		"",
		"2. absences: for each thin position listed above, why it is thin, and how much the",
		"   gap could cost. Choose one reason from:",
	])
	for classification_id: String in DiagnosticsScript.ABSENCE_CLASSIFICATIONS:
		lines.append("   - %s: %s" % [
			classification_id,
			String(DiagnosticsScript.ABSENCE_HELP.get(classification_id, "")),
		])
	lines.append_array([
		"   Then two bands, each low, medium or high:",
		"   - consequence: what it costs if this gap turns out to matter.",
		"   - confidence: how sure you are that it does not matter.",
		"   Do not reach for \"not_applicable\" to tidy the map. A position is thin because",
		"   nobody looked, far more often than because there was nothing to see, and saying",
		"   otherwise destroys the finding the facilitator asked for.",
		"",
		"3. concentration: what the pile-up in the position holding the most means. One of:",
	])
	for classification_id: String in DiagnosticsScript.CONCENTRATION_CLASSIFICATIONS:
		lines.append("   - %s: %s" % [
			classification_id,
			String(DiagnosticsScript.CONCENTRATION_HELP.get(classification_id, "")),
		])
	lines.append_array([
		"",
		"4. transition: one move from the position holding the most into a thin one, and a",
		"   concrete action that would accomplish it. Name something a workshop could",
		"   actually do, not \"consider\" or \"explore\".",
		"",
		"5. reopening_actions: up to %d things to do that would test the riskiest gap." % MAX_REOPENING_ACTIONS,
		"   For each, an action and a falsifier: what result would change the decision. Do",
		"   not name an owner or a date; only the room can commit those.",
		"",
		"Reply with strict JSON and nothing else, in this shape:",
		"{",
		"  \"decision\": \"<one sentence>\",",
		"  \"absences\": [{\"quadrant\": \"A|B|C|D\", \"classification\": \"<from the list>\",",
		"    \"reason\": \"<one short sentence>\", \"consequence\": \"low|medium|high\",",
		"    \"confidence\": \"low|medium|high\"}],",
		"  \"concentration\": {\"classification\": \"<from the list>\", \"reason\": \"<one sentence>\"},",
		"  \"transition\": {\"from\": \"A|B|C|D\", \"to\": \"A|B|C|D\", \"action\": \"<what to do>\"},",
		"  \"reopening_actions\": [{\"action\": \"<what to do>\", \"falsifier\": \"<what would change the decision>\"}]",
		"}",
	])
	return "\n".join(lines)


## Returns `{ok, suggestions, error}`. `suggestions` carries only values that survived
## validation against the vocabularies: an unrecognised classification is dropped rather than
## coerced to the nearest match, because a suggestion the facilitator accepts on trust has to
## mean what it says.
static func parse_response(
	raw_response: String,
	thin_quadrants: Array,
	findings: Dictionary
) -> Dictionary:
	var parsed: Dictionary = _parse_json_object(raw_response)
	if parsed.is_empty():
		return _failure("unparseable_response")
	var suggestions: Dictionary = {}
	var decision: String = str(parsed.get("decision", "")).strip_edges()
	if not decision.is_empty():
		suggestions["decision"] = decision
	var thin_ids: Array[String] = _as_string_array(thin_quadrants)
	var absences: Dictionary = _parse_absences(parsed.get("absences", []), thin_ids)
	if not absences.is_empty():
		suggestions["absences"] = absences
	var concentration: Dictionary = _parse_concentration(
		parsed.get("concentration", {}), String(findings.get("dominant_quadrant", ""))
	)
	if not concentration.is_empty():
		suggestions["concentration"] = concentration
	var transition: Dictionary = _parse_transition(parsed.get("transition", {}))
	if not transition.is_empty():
		suggestions["transition"] = transition
	var actions: Array[Dictionary] = _parse_actions(parsed.get("reopening_actions", []))
	if not actions.is_empty():
		suggestions["reopening_actions"] = actions
	if suggestions.is_empty():
		return _failure("no_usable_suggestions")
	return {"ok": true, "suggestions": suggestions, "error": ""}


## Only quadrants the reading calls thin. A drafted answer about a well-covered position has
## no step to land in, and keeping it would put a row on screen the audit never asked for.
static func _parse_absences(entries_any: Variant, thin_ids: Array[String]) -> Dictionary:
	if typeof(entries_any) != TYPE_ARRAY:
		return {}
	var absences: Dictionary = {}
	for entry_any: Variant in (entries_any as Array):
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var quadrant: String = ClosureOrientationScript.normalize_quadrant(
			str(entry.get("quadrant", ""))
		)
		if quadrant.is_empty() or quadrant not in thin_ids or absences.has(quadrant):
			continue
		var classification: String = str(entry.get("classification", "")).strip_edges().to_lower()
		if not DiagnosticsScript.is_valid_absence_classification(classification):
			continue
		var absence: Dictionary = {
			"classification": classification,
			"reason": str(entry.get("reason", "")).strip_edges(),
		}
		# The bands are optional in a way the classification is not: a triage without a
		# classification has nothing to be a triage of, so a dropped classification drops the
		# row, while dropped bands just leave the facilitator to set them.
		var consequence: String = str(entry.get("consequence", "")).strip_edges().to_lower()
		var confidence: String = str(entry.get("confidence", "")).strip_edges().to_lower()
		if DiagnosticsScript.is_valid_band(consequence):
			absence["consequence"] = consequence
		if DiagnosticsScript.is_valid_band(confidence):
			absence["confidence"] = confidence
		absences[quadrant] = absence
	return absences


static func _parse_concentration(entry_any: Variant, dominant_quadrant: String) -> Dictionary:
	if typeof(entry_any) != TYPE_DICTIONARY or dominant_quadrant.is_empty():
		return {}
	var entry: Dictionary = entry_any
	var classification: String = str(entry.get("classification", "")).strip_edges().to_lower()
	if not DiagnosticsScript.is_valid_concentration_classification(classification):
		return {}
	return {
		"quadrant": dominant_quadrant,
		"classification": classification,
		"reason": str(entry.get("reason", "")).strip_edges(),
	}


static func _parse_transition(entry_any: Variant) -> Dictionary:
	if typeof(entry_any) != TYPE_DICTIONARY:
		return {}
	var entry: Dictionary = entry_any
	var from_quadrant: String = ClosureOrientationScript.normalize_quadrant(
		str(entry.get("from", ""))
	)
	var to_quadrant: String = ClosureOrientationScript.normalize_quadrant(
		str(entry.get("to", ""))
	)
	var action_text: String = str(entry.get("action", "")).strip_edges()
	# The same three conditions the record enforces, checked here so an unusable draft never
	# reaches the pickers and cannot be accepted into a refusal.
	if from_quadrant.is_empty() or to_quadrant.is_empty() or from_quadrant == to_quadrant:
		return {}
	if action_text.is_empty():
		return {}
	return {"from": from_quadrant, "to": to_quadrant, "action": action_text}


static func _parse_actions(entries_any: Variant) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if typeof(entries_any) != TYPE_ARRAY:
		return actions
	for entry_any: Variant in (entries_any as Array):
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var action_text: String = str(entry.get("action", "")).strip_edges()
		var falsifier_text: String = str(entry.get("falsifier", "")).strip_edges()
		if action_text.is_empty() or falsifier_text.is_empty():
			# An action without a falsifier is a task, and the record refuses it. Offering one
			# would put a button on screen that cannot succeed.
			continue
		actions.append({"action": action_text, "falsifier": falsifier_text})
		if actions.size() >= MAX_REOPENING_ACTIONS:
			break
	return actions


## One line for the facilitator, naming what came back and what it does not yet mean.
static func format_summary(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return "Could not draft answers (%s). Answer the steps yourself, or try again." % (
			describe_error(str(result.get("error", "unknown")))
		)
	var suggestions: Dictionary = result.get("suggestions", {})
	var parts: Array[String] = []
	if suggestions.has("decision"):
		parts.append("a decision")
	var absences: Dictionary = suggestions.get("absences", {})
	if not absences.is_empty():
		parts.append("%d absence(s)" % absences.size())
	if suggestions.has("concentration"):
		parts.append("what the pile-up means")
	if suggestions.has("transition"):
		parts.append("a move")
	var actions: Array = suggestions.get("reopening_actions", [])
	if not actions.is_empty():
		parts.append("%d action(s)" % actions.size())
	if parts.is_empty():
		return "Nothing usable came back. Answer the steps yourself, or try again."
	return "Drafted %s. Nothing counts until you accept it." % _join_with_and(parts)


## Plain readings of the failures a facilitator can actually do something about.
static func describe_error(error_id: String) -> String:
	match error_id:
		"map_not_readable":
			return "not enough claims are tagged yet"
		"no_claims_to_audit":
			return "the map has no claims"
		"model_unavailable":
			return "no model is available"
		"unparseable_response", "invalid_response":
			return "the reply came back malformed"
		"no_usable_suggestions":
			return "nothing in the reply was usable"
		_:
			return error_id


static func _join_with_and(parts: Array[String]) -> String:
	if parts.size() <= 1:
		return "".join(parts)
	var head: Array[String] = parts.slice(0, parts.size() - 1)
	return "%s and %s" % [", ".join(head), parts[parts.size() - 1]]


static func _usable_claims(claims: Array) -> Array[Dictionary]:
	var usable: Array[Dictionary] = []
	for claim_any: Variant in claims:
		if typeof(claim_any) != TYPE_DICTIONARY:
			continue
		var claim: Dictionary = claim_any
		if str(claim.get("label", "")).strip_edges().is_empty():
			continue
		usable.append(claim)
		if usable.size() >= MAX_CLAIMS_PER_PASS:
			break
	return usable


static func _as_string_array(values: Array) -> Array[String]:
	var strings: Array[String] = []
	for value_any: Variant in values:
		var value: String = str(value_any).strip_edges()
		if not value.is_empty():
			strings.append(value)
	return strings


static func _parse_json_object(raw_response: String) -> Dictionary:
	var opening_index: int = raw_response.find("{")
	var closing_index: int = raw_response.rfind("}")
	if opening_index < 0 or closing_index <= opening_index:
		return {}
	var parser := JSON.new()
	if parser.parse(raw_response.substr(opening_index, closing_index - opening_index + 1)) != OK:
		return {}
	var parsed_any: Variant = parser.data
	if typeof(parsed_any) != TYPE_DICTIONARY:
		return {}
	return parsed_any


static func _failure(error_id: String) -> Dictionary:
	return {"ok": false, "suggestions": {}, "error": error_id}
