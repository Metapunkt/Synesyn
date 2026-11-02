extends RefCounted
class_name WorkshopOrientationSuggester

## Purpose: ask a model to suggest a Closure Map quadrant per claim, on demand,
## during a Closure Audit (ADR 0020 as amended 2026-09-06, REQ-CA-004).
##
## A suggestion is not a tag. Nothing here writes `annotations.orientation`; this
## returns proposals and the facilitator accepts or changes each one, exactly as they
## accept or edit an AI-proposed claim under ADR 0019. An unactioned suggestion counts
## as untagged everywhere, including in coverage and concentration.
##
## The reason assistance exists at all: orienting from a blank page against four
## abstract quadrants is the real cost of this instrument, and an unassisted room will
## either stall or tag carelessly. A careless tag is worse than an absent one, because
## it silently corrupts the reading the audit exists to produce.
##
## Two things keep it honest. "None of these applies" is a first-class answer, as
## available to the model as the four quadrants (REQ-CA-004a) — without it a
## classifier under pressure to choose would populate every quadrant, and the
## empty-quadrant diagnostic would measure the model's willingness to guess rather
## than the room's attention. And the pass runs only when asked: specialist batch
## extraction still cannot emit orientation (REQ-CA-004c), so orientation never
## arrives as a side effect of ordinary facilitation.

const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)
const StatelessModelTaskScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_stateless_model_task.gd"
)

## What the model answers when no quadrant fits. Declining is a result, not a
## failure, and is reported separately from an unparseable response.
const NONE_APPLIES: String = "none"

## Beyond this many claims per pass the envelope gets long enough that mid-tier local
## models truncate the JSON. The caller batches rather than losing the tail.
const MAX_CLAIMS_PER_PASS: int = 24


## `claims` holds `{"id": String, "kind": String, "label": String}` entries.
func request(conversation_manager: Variant, claims: Array) -> Dictionary:
	var usable_claims: Array[Dictionary] = _usable_claims(claims)
	if usable_claims.is_empty():
		return _failure("no_claims_to_orient")
	var task_runner: RefCounted = StatelessModelTaskScript.new()
	if not task_runner.can_run(conversation_manager):
		return _failure("model_unavailable")
	var response: Variant = await task_runner.run(
		conversation_manager,
		build_prompt(usable_claims)
	)
	if typeof(response) != TYPE_DICTIONARY:
		return _failure("invalid_response")
	var response_data: Dictionary = response
	if not bool(response_data.get("success", false)):
		return _failure(str(response_data.get("error", "request_failed")))
	return parse_response(
		str(response_data.get("response", "")),
		_claim_ids(usable_claims)
	)


static func build_prompt(claims: Array) -> String:
	var lines: Array[String] = [
		"You are assisting a facilitator running a Closure Audit on a workshop's",
		"Thinking Map. For each claim below, suggest which one of four Closure Map",
		"quadrants it belongs to, or state that none applies.",
		"",
		"The two axes. Distal means out there, beyond this group. Deep means in here,",
		"within how this group already works. Past means already the case. Future means",
		"not yet the case.",
		"",
		"The four quadrants:",
	]
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		lines.append("- %s = %s. %s; %s. %s" % [
			quadrant_id,
			ClosureOrientationScript.get_canonical_with_gloss(quadrant_id),
			String(ClosureOrientationScript.TEMPORAL_ROLE_BY_QUADRANT.get(quadrant_id, "")),
			String(ClosureOrientationScript.AXIS_HINT_BY_QUADRANT.get(quadrant_id, "")),
			String(ClosureOrientationScript.CHARACTER_BY_QUADRANT.get(quadrant_id, "")),
		])
	lines.append_array([
		"",
		"Rules.",
		"1. Answer \"%s\" whenever no quadrant genuinely fits. That is a complete and" % NONE_APPLIES,
		"   correct answer, not a failure, and it is preferred over a weak fit. Do not",
		"   spread claims across quadrants to achieve coverage, and do not avoid leaving",
		"   a quadrant empty: whether a quadrant is empty is exactly what the",
		"   facilitator needs to find out, so a guess destroys the finding.",
		"2. A claim about the wider world belongs in A or B. A claim about this group's",
		"   own habits, incentives, culture or latent capability belongs in C or D.",
		"3. Suggest for every claim id given, once each. Do not invent claims, do not",
		"   omit any, and do not alter any claim's text.",
		"4. These are suggestions. The facilitator accepts or changes each one, so do",
		"   not hedge or explain; give your single best answer per claim.",
		"",
		"Claims:",
	])
	for claim_any: Variant in claims:
		if typeof(claim_any) != TYPE_DICTIONARY:
			continue
		var claim: Dictionary = claim_any
		lines.append("- id=%s kind=%s: %s" % [
			str(claim.get("id", "")),
			str(claim.get("kind", "")),
			str(claim.get("label", "")),
		])
	lines.append_array([
		"",
		"Reply with strict JSON and nothing else, in this shape:",
		"{\"orientations\": [{\"id\": \"<claim id>\", \"quadrant\": \"A|B|C|D|%s\"}]}" % NONE_APPLIES,
	])
	return "\n".join(lines)


## Returns `{ok, suggestions, declined, unmatched, error}`. `suggestions` maps a
## claim id to a quadrant; a declined claim is deliberately absent from it rather
## than present-and-empty, so a caller cannot mistake "no quadrant fits" for a tag.
static func parse_response(raw_response: String, valid_ids: Array) -> Dictionary:
	var parsed: Dictionary = _parse_json_object(raw_response)
	if parsed.is_empty():
		return _failure("unparseable_response")
	var entries_any: Variant = parsed.get("orientations", [])
	if typeof(entries_any) != TYPE_ARRAY:
		return _failure("missing_orientations")
	var suggestions: Dictionary = {}
	var declined_ids: Array[String] = []
	var unmatched_count: int = 0
	for entry_any: Variant in (entries_any as Array):
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var claim_id: String = str(entry.get("id", "")).strip_edges()
		if claim_id.is_empty() or not valid_ids.has(claim_id):
			unmatched_count += 1
			continue
		if suggestions.has(claim_id) or declined_ids.has(claim_id):
			continue
		var raw_quadrant: String = str(entry.get("quadrant", "")).strip_edges()
		if _is_declined(raw_quadrant):
			declined_ids.append(claim_id)
			continue
		var quadrant_id: String = _to_quadrant(raw_quadrant)
		if quadrant_id.is_empty():
			# An unreadable value is not a decline. Dropping it leaves the claim
			# untagged with no suggestion, which is the safe reading.
			unmatched_count += 1
			continue
		suggestions[claim_id] = quadrant_id
	if suggestions.is_empty() and declined_ids.is_empty():
		return _failure("no_usable_suggestions")
	return {
		"ok": true,
		"suggestions": suggestions,
		"declined": declined_ids,
		"unmatched": unmatched_count,
		"error": "",
	}


## One line for the facilitator, stating what came back and what it costs them.
static func format_summary(result: Dictionary) -> String:
	if not bool(result.get("ok", false)):
		return "Could not suggest orientations (%s). Orient by hand, or try again." % str(
			result.get("error", "unknown")
		)
	var suggestions: Dictionary = result.get("suggestions", {})
	var declined: Array = result.get("declined", [])
	var parts: Array[String] = [
		"Suggested %d orientation(s)" % suggestions.size(),
	]
	if not declined.is_empty():
		parts.append("%d where the model says none applies" % declined.size())
	parts.append("nothing is tagged until you accept or change it")
	return " \u00b7 ".join(parts) + "."


static func _usable_claims(claims: Array) -> Array[Dictionary]:
	var usable: Array[Dictionary] = []
	for claim_any: Variant in claims:
		if typeof(claim_any) != TYPE_DICTIONARY:
			continue
		var claim: Dictionary = claim_any
		if str(claim.get("id", "")).strip_edges().is_empty():
			continue
		if str(claim.get("label", "")).strip_edges().is_empty():
			continue
		usable.append(claim)
		if usable.size() >= MAX_CLAIMS_PER_PASS:
			break
	return usable


static func _claim_ids(claims: Array) -> Array[String]:
	var claim_ids: Array[String] = []
	for claim_any: Variant in claims:
		if typeof(claim_any) == TYPE_DICTIONARY:
			claim_ids.append(str((claim_any as Dictionary).get("id", "")))
	return claim_ids


## Tolerant of how a model might phrase declining, because the alternative — reading
## a decline as unparseable — would quietly discard the answer the audit most needs
## to be able to hear.
static func _is_declined(raw_quadrant: String) -> bool:
	var candidate: String = raw_quadrant.strip_edges().to_lower()
	return candidate in [
		NONE_APPLIES, "", "none of these applies", "n/a", "na", "null", "unknown", "untagged",
	]


## Accepts a bare letter, a canonical display name, or a stored machine label, so a
## model that answers "deep_past" or "Deep Past" is not discarded on formatting.
static func _to_quadrant(raw_quadrant: String) -> String:
	var direct: String = ClosureOrientationScript.normalize_quadrant(raw_quadrant)
	if not direct.is_empty():
		return direct
	var candidate: String = raw_quadrant.strip_edges().to_lower().replace(" ", "_")
	for quadrant_id: String in ClosureOrientationScript.QUADRANTS:
		if candidate == String(ClosureOrientationScript.LABEL_BY_QUADRANT[quadrant_id]):
			return quadrant_id
		if candidate == String(
			ClosureOrientationScript.PLAIN_BY_QUADRANT[quadrant_id]
		).to_lower().replace(" ", "_"):
			return quadrant_id
	return ""


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
	return {
		"ok": false,
		"suggestions": {},
		"declined": [] as Array[String],
		"unmatched": 0,
		"error": error_id,
	}
