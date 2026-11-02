extends RefCounted
class_name WorkshopClosureAuditRecord

## What one closure audit decided: the decision under audit, why each thin quadrant is thin,
## the triage of each absence, what the concentration means, the closure debt, the required
## transition, and the reopening questions and actions that come out of it.
##
## A record rather than a controller, so the ritual's state is testable without a scene and
## survives a reload. It holds *judgements*, never geometry: coverage, dominance and
## emptiness are recomputed from the map by `workshop_closure_audit_rules.gd` on every
## refresh, and duplicating them here would let the two disagree.
##
## Deliberately permissive about order. The manual runs decision statement, then prompts,
## then diagnostics, then debt, then transition, and the surface presents it that way — but
## rooms do not proceed in order, and a record that rejected an out-of-sequence entry would
## force the facilitator to fight it. Sequence is enforced only where it changes meaning:
## completion.

const DiagnosticsScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_diagnostics.gd"
)
const ClosureOrientationScript = preload(
	"res://addons/synesyn_core/scripts/closure_orientation.gd"
)

const SCHEMA_VERSION: int = 1

var _decision_under_audit: String = ""
var _absences: Dictionary = {}
var _concentration: Dictionary = {}
var _debt: Array[Dictionary] = []
var _required_transition: Dictionary = {}
var _reopening_actions: Array[Dictionary] = []
var _routed_refs: Dictionary = {}


func initialize(saved_state: Dictionary = {}) -> void:
	_decision_under_audit = ""
	_absences = {}
	_concentration = {}
	_debt = []
	_required_transition = {}
	_reopening_actions = []
	_routed_refs = {}
	if not saved_state.is_empty():
		_load(saved_state)


## The decision the audit is *about*. Without it the whole exercise floats: "is this map
## balanced" has no answer, while "is this map balanced enough to decide X" does.
func set_decision_under_audit(decision_text: String) -> bool:
	var clean_text: String = decision_text.strip_edges()
	if clean_text == _decision_under_audit:
		return false
	_decision_under_audit = clean_text
	return true


func get_decision_under_audit() -> String:
	return _decision_under_audit


## Records why a quadrant is empty or weak, and optionally its triage (REQ-CA-005, 006).
##
## Triage is stored with the absence rather than separately because it is a judgement *about*
## that absence — consequence if this quadrant's material turns out to matter, confidence
## that it does not. Keeping them together means a reclassified quadrant cannot keep a
## verdict that was reached about a different reading of it.
func classify_absence(
	quadrant_id: String,
	classification_id: String,
	note_text: String = ""
) -> Dictionary:
	var quadrant: String = ClosureOrientationScript.normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return {"ok": false, "error": "invalid_quadrant"}
	if not DiagnosticsScript.is_valid_absence_classification(classification_id):
		return {"ok": false, "error": "invalid_classification"}
	var classification: String = classification_id.strip_edges().to_lower()
	var entry: Dictionary = _absences.get(quadrant, {})
	if (
		String(entry.get("classification", "")) == classification
		and String(entry.get("note", "")) == note_text.strip_edges()
	):
		return {"ok": true, "changed": false}
	# A reclassified absence loses its verdict: the room decided "monitor" about a quadrant
	# it believed was merely unknown, and that verdict does not carry over to one it now
	# believes is being suppressed.
	var had_triage: bool = entry.has("consequence")
	var is_reclassified: bool = (
		not String(entry.get("classification", "")).is_empty()
		and String(entry.get("classification", "")) != classification
	)
	_absences[quadrant] = {
		"classification": classification,
		"note": note_text.strip_edges(),
		"classified_at": Time.get_datetime_string_from_system(true),
	}
	return {
		"ok": true,
		"changed": true,
		"triage_cleared": had_triage and is_reclassified,
	}


## Accepts the two bands one at a time. The room sets consequence, then confidence, and the
## verdict follows once both are present — so a half-answer has to be storable.
##
## It used to reject any call with an empty band, which made triage unreachable: the surface
## sends one band per selection, the record refused it, the refreshed row read its state back
## from here and found nothing, and the picker snapped to its placeholder. Neither band could
## ever be the second one. The controller tried to paper over this by mutating the dictionary
## from `get_absence()`, which is a deep copy, so it wrote the half-answer to a throwaway.
##
## An incomplete pair clears the verdict rather than leaving the previous one standing: having
## changed consequence from low to high, the room has withdrawn the verdict that was reached
## about the old pair, and showing it until the second band arrives would misreport it.
func triage_absence(
	quadrant_id: String,
	consequence_band: String,
	confidence_band: String
) -> Dictionary:
	var quadrant: String = ClosureOrientationScript.normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return {"ok": false, "error": "invalid_quadrant"}
	if not _absences.has(quadrant):
		# Triage answers "how much does this absence matter", which cannot be asked before
		# the room has said what kind of absence it is.
		return {"ok": false, "error": "not_classified"}
	var consequence: String = consequence_band.strip_edges().to_lower()
	var confidence: String = confidence_band.strip_edges().to_lower()
	if not consequence.is_empty() and not DiagnosticsScript.is_valid_band(consequence):
		return {"ok": false, "error": "invalid_band"}
	if not confidence.is_empty() and not DiagnosticsScript.is_valid_band(confidence):
		return {"ok": false, "error": "invalid_band"}
	var entry: Dictionary = _absences[quadrant]
	var verdict: String = DiagnosticsScript.triage_verdict(consequence, confidence)
	entry["consequence"] = consequence
	entry["confidence"] = confidence
	if verdict.is_empty():
		entry.erase("verdict")
	else:
		entry["verdict"] = verdict
	_absences[quadrant] = entry
	return {"ok": true, "changed": true, "verdict": verdict}


func get_absence(quadrant_id: String) -> Dictionary:
	var quadrant: String = ClosureOrientationScript.normalize_quadrant(quadrant_id)
	var entry_any: Variant = _absences.get(quadrant, {})
	return (entry_any as Dictionary).duplicate(true) if typeof(entry_any) == TYPE_DICTIONARY else {}


func get_absences() -> Dictionary:
	return _absences.duplicate(true)


func classify_concentration(
	quadrant_id: String,
	classification_id: String,
	note_text: String = ""
) -> Dictionary:
	var quadrant: String = ClosureOrientationScript.normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return {"ok": false, "error": "invalid_quadrant"}
	if not DiagnosticsScript.is_valid_concentration_classification(classification_id):
		return {"ok": false, "error": "invalid_classification"}
	_concentration = {
		"quadrant": quadrant,
		"classification": classification_id.strip_edges().to_lower(),
		"note": note_text.strip_edges(),
		"classified_at": Time.get_datetime_string_from_system(true),
	}
	return {"ok": true, "changed": true}


func get_concentration() -> Dictionary:
	return _concentration.duplicate(true)


## Records closure debt, but only when all four conditions hold (REQ-CA-007). A refusal
## returns the conditions that failed rather than a bare error, because "this is not debt"
## is itself a finding the facilitator should be able to read back to the room.
func record_debt(
	quadrant_id: String,
	conditions: Dictionary,
	note_text: String = ""
) -> Dictionary:
	var quadrant: String = ClosureOrientationScript.normalize_quadrant(quadrant_id)
	if quadrant.is_empty():
		return {"ok": false, "error": "invalid_quadrant"}
	if not DiagnosticsScript.qualifies_as_debt(conditions):
		_erase_debt(quadrant)
		return {
			"ok": true,
			"changed": true,
			"recorded": false,
			"unmet": DiagnosticsScript.describe_debt_shortfall(conditions),
		}
	var entry: Dictionary = {
		"quadrant": quadrant,
		"note": note_text.strip_edges(),
		"recorded_at": Time.get_datetime_string_from_system(true),
	}
	for condition_id: String in DiagnosticsScript.DEBT_CONDITIONS:
		entry[condition_id] = true
	_erase_debt(quadrant)
	_debt.append(entry)
	return {"ok": true, "changed": true, "recorded": true}


func get_debt() -> Array[Dictionary]:
	return _debt.duplicate(true)


## REQ-CA-009. One edge, one direction, one action. Stored as its parts as well as its
## rendered line so an export does not have to parse the sentence back apart.
func set_required_transition(
	from_quadrant: String,
	to_quadrant: String,
	action_text: String
) -> Dictionary:
	var summary: String = DiagnosticsScript.format_required_transition(
		from_quadrant, to_quadrant, action_text
	)
	if summary.is_empty():
		return {"ok": false, "error": "invalid_transition"}
	_required_transition = {
		"from": ClosureOrientationScript.normalize_quadrant(from_quadrant),
		"to": ClosureOrientationScript.normalize_quadrant(to_quadrant),
		"action": action_text.strip_edges(),
		"summary": summary,
		"transformation": DiagnosticsScript.describe_transition_edge(from_quadrant, to_quadrant),
	}
	return {"ok": true, "changed": true, "summary": summary}


func get_required_transition() -> Dictionary:
	return _required_transition.duplicate(true)


## REQ-CA-008. An owner, a date, and what evidence would change the decision. All three are
## required, and the falsifier is the one that makes the difference: an action with an owner
## and a date is a task, while an action that also says what would change the decision is a
## test. Without it the room cannot tell, later, whether running the action settled anything.
func add_reopening_action(
	action_text: String,
	owner_ref: String,
	due_date: String,
	falsifier_text: String
) -> Dictionary:
	var clean_action: String = action_text.strip_edges()
	if clean_action.is_empty():
		return {"ok": false, "error": "missing_action"}
	var missing: Array[String] = []
	if owner_ref.strip_edges().is_empty():
		missing.append("an owner")
	if due_date.strip_edges().is_empty():
		missing.append("a date")
	if falsifier_text.strip_edges().is_empty():
		missing.append("what evidence would change the decision")
	if not missing.is_empty():
		return {"ok": false, "error": "incomplete", "missing": missing}
	for existing: Dictionary in _reopening_actions:
		if String(existing.get("action", "")) == clean_action:
			return {"ok": true, "changed": false, "id": String(existing.get("id", ""))}
	var action_id: String = "wca_%d_%s" % [
		_reopening_actions.size(),
		str(clean_action.hash()),
	]
	_reopening_actions.append({
		"id": action_id,
		"action": clean_action,
		"owner": owner_ref.strip_edges(),
		"due_date": due_date.strip_edges(),
		"falsifier": falsifier_text.strip_edges(),
		"created_at": Time.get_datetime_string_from_system(true),
	})
	return {"ok": true, "changed": true, "id": action_id}


func get_reopening_actions() -> Array[Dictionary]:
	return _reopening_actions.duplicate(true)


## Notes that an action or question reached the Session Record, so a second routing pass
## does not propose it again. Keyed by the audit's own id rather than the Session Record's,
## because a proposal the facilitator rejects should not come back either — the room decided.
func mark_routed(audit_ref: String, record_category: String, proposal_id: String) -> void:
	_routed_refs[audit_ref] = {
		"category": record_category,
		"proposal_id": proposal_id,
		"routed_at": Time.get_datetime_string_from_system(true),
	}


func is_routed(audit_ref: String) -> bool:
	return _routed_refs.has(audit_ref)


func get_routed_refs() -> Dictionary:
	return _routed_refs.duplicate(true)


## REQ-CA-005: the audit cannot be marked complete while a weak or empty quadrant is
## unclassified. `thin_quadrants` comes from the rules module's empty and weak readings, so
## the gate follows the live map rather than a snapshot taken when the audit opened.
##
## The orientation counts are not optional. The rules module deliberately reports no empty or
## weak quadrants until enough claims are oriented to draw a reading — correct for it, and a
## trap for this gate: with nothing oriented, there are no thin quadrants, so an audit over a
## completely unexamined map satisfied every condition and announced itself complete. That is
## the exact false assurance the instrument exists to prevent, stated in the tool's own voice.
##
## They are counts rather than a `has_reading` bool so the gate can say how far off the room
## is. "Orient enough claims" gives a facilitator no way to know whether that means one more
## or twenty; the numbers are already in the findings, so withholding them was a choice.
##
## Returns what is outstanding rather than a bare bool, because the facilitator needs to know
## what is left, and a disabled button with no explanation is the worst version of this.
func describe_completion_gaps(
	thin_quadrants: Array,
	oriented_count: int = 0,
	min_oriented_for_reading: int = 0,
	dominant_quadrant: String = ""
) -> Array[String]:
	var gaps: Array[String] = []
	if _decision_under_audit.is_empty():
		gaps.append("name the decision under audit")
	if oriented_count < min_oriented_for_reading:
		gaps.append(
			"tag at least %d claims with a quadrant so the spread can be read (%d so far)" % [
				min_oriented_for_reading, oriented_count
			]
		)
	var unclassified: Array[String] = []
	for quadrant_any: Variant in thin_quadrants:
		var quadrant: String = ClosureOrientationScript.normalize_quadrant(String(quadrant_any))
		if quadrant.is_empty():
			continue
		if not _absences.has(quadrant):
			unclassified.append(quadrant)
	if not unclassified.is_empty():
		# Canonical terms rather than bare letters, and no in-house shorthand: this line is
		# read by a facilitator who has met neither.
		gaps.append(
			"say why %s %s nearly empty" % [
				ClosureOrientationScript.join_canonical_terms(unclassified, " and "),
				"is" if unclassified.size() == 1 else "are",
			]
		)
	# The third diagnostic, gated on the same reasoning as the second. A dominant quadrant is
	# the finding most likely to be read as self-explanatory — the map "obviously" shows where
	# the room's attention went — and it is the one the manual insists is ambiguous between
	# sensible focus and having stopped looking. An audit that closed with this step untouched
	# would have skipped the reading it was least safe to skip.
	if not dominant_quadrant.is_empty() and not _concentration.has("classification"):
		gaps.append(
			"say what the pile-up in %s means"
			% ClosureOrientationScript.get_canonical_term(dominant_quadrant)
		)
	# Debt without a reopening action is a note to nobody. The manual's whole output is the
	# Closure-to-Action Sheet, so debt that produces no action has not been audited, only
	# observed.
	if not _debt.is_empty() and _reopening_actions.is_empty():
		gaps.append("add at least one action for the debt you recorded")
	return gaps


func is_complete(
	thin_quadrants: Array,
	oriented_count: int = 0,
	min_oriented_for_reading: int = 0,
	dominant_quadrant: String = ""
) -> bool:
	return describe_completion_gaps(
		thin_quadrants, oriented_count, min_oriented_for_reading, dominant_quadrant
	).is_empty()


func get_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"decision_under_audit": _decision_under_audit,
		"absences": _absences.duplicate(true),
		"concentration": _concentration.duplicate(true),
		"debt": _debt.duplicate(true),
		"required_transition": _required_transition.duplicate(true),
		"reopening_actions": _reopening_actions.duplicate(true),
		"routed_refs": _routed_refs.duplicate(true),
	}


func _load(saved_state: Dictionary) -> void:
	_decision_under_audit = String(saved_state.get("decision_under_audit", "")).strip_edges()
	_absences = _dictionary_from(saved_state.get("absences", {}))
	_concentration = _dictionary_from(saved_state.get("concentration", {}))
	_debt.assign(_dictionaries_from(saved_state.get("debt", [])))
	_required_transition = _dictionary_from(saved_state.get("required_transition", {}))
	_reopening_actions.assign(_dictionaries_from(saved_state.get("reopening_actions", [])))
	_routed_refs = _dictionary_from(saved_state.get("routed_refs", {}))


func _erase_debt(quadrant_id: String) -> void:
	for index: int in range(_debt.size() - 1, -1, -1):
		if String(_debt[index].get("quadrant", "")) == quadrant_id:
			_debt.remove_at(index)


func _dictionary_from(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func _dictionaries_from(value: Variant) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return entries
	for entry_any: Variant in (value as Array):
		if typeof(entry_any) == TYPE_DICTIONARY:
			entries.append((entry_any as Dictionary).duplicate(true))
	return entries
