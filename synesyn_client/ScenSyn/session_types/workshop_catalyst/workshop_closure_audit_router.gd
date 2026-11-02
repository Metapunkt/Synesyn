extends RefCounted
class_name WorkshopClosureAuditRouter

## Carries the audit's output into the Session Record (REQ-CA-013).
##
## Proposes; never commits. Everything here goes through `WorkshopSessionRecordStore.propose`
## and lands as `suggested`, so the facilitator reviews each entry in the panel exactly as
## they review a specialist's suggestion. An audit that wrote straight into the reviewed
## record would give a derived reading more authority than a human claim, which inverts
## ADR 0019.
##
## Split from the record for a reason: the record holds judgements and knows nothing about
## the Session Record, and the router knows both but stores nothing. That keeps the record
## headlessly testable without a store, and keeps the Session Record's categories from
## leaking into the audit's vocabulary.

## Where each kind of audit output belongs. Reopening *questions* are open questions;
## reopening *actions* are next steps, and their owner is additionally proposed into owners,
## because an action whose owner exists only inside the audit is not owned by anyone the
## Session Record knows about.
const CATEGORY_OPEN_QUESTIONS: String = "open_questions"
const CATEGORY_NEXT_STEPS: String = "next_steps"
const CATEGORY_OWNERS: String = "owners"


## Routes everything outstanding and reports what happened. Idempotent through the record's
## own routed refs, so pressing the button twice does not queue a second copy — and a
## proposal the facilitator rejected stays rejected rather than returning on the next pass.
##
## `store` is untyped because `WorkshopSessionRecordStore` is a host class this module must
## not preload to stay testable in isolation; it is duck-typed on `propose`.
static func route_audit(
	store: Object,
	audit_record: RefCounted,
	closure_findings: Dictionary
) -> Dictionary:
	if not store or not store.has_method("propose"):
		return {"ok": false, "error": "no_store"}
	var proposed: Array[Dictionary] = []
	var skipped: int = 0
	for question_text: String in build_reopening_questions(audit_record, closure_findings):
		var question_ref: String = "question:%s" % str(question_text.hash())
		if audit_record.is_routed(question_ref):
			skipped += 1
			continue
		var result: Dictionary = _propose(
			store, CATEGORY_OPEN_QUESTIONS, question_text, question_ref, audit_record
		)
		if not result.is_empty():
			proposed.append(result)
		else:
			skipped += 1
	for action_any: Variant in audit_record.get_reopening_actions():
		var action: Dictionary = action_any
		var action_id: String = String(action.get("id", ""))
		var action_ref: String = "action:%s" % action_id
		if audit_record.is_routed(action_ref):
			skipped += 1
			continue
		var result: Dictionary = _propose(
			store, CATEGORY_NEXT_STEPS, format_action_text(action), action_ref, audit_record
		)
		if not result.is_empty():
			proposed.append(result)
		else:
			skipped += 1
		var owner_ref: String = String(action.get("owner", "")).strip_edges()
		var owner_key: String = "owner:%s" % owner_ref.to_lower()
		if owner_ref.is_empty() or audit_record.is_routed(owner_key):
			continue
		var owner_result: Dictionary = _propose(
			store,
			CATEGORY_OWNERS,
			"%s — owns: %s" % [owner_ref, String(action.get("action", ""))],
			owner_key,
			audit_record
		)
		if not owner_result.is_empty():
			proposed.append(owner_result)
	return {"ok": true, "proposed": proposed, "skipped": skipped}


## The action as the Session Record should read it: what to do, who owns it, by when, and
## what would change the decision. Kept as one entry rather than four fields because the
## Session Record stores prose, and splitting a test into parts it cannot reassemble would
## lose the falsifier — the part that makes it a test rather than a task.
static func format_action_text(action: Dictionary) -> String:
	return "%s (owner: %s, by %s). Would change the decision: %s" % [
		String(action.get("action", "")).strip_edges(),
		String(action.get("owner", "")).strip_edges(),
		String(action.get("due_date", "")).strip_edges(),
		String(action.get("falsifier", "")).strip_edges(),
	]


## The questions the audit's own findings raise, in the manual's terms. Derived rather than
## typed, because these are the questions the room has already implied by its answers, and
## making the facilitator retype them is how they get skipped.
##
## Contested placement earns a question because a room that cannot agree where a claim sits
## does not share a reading of its situation; suppression and unknown absences earn one
## because those are the two classifications that name something missing rather than
## something excluded; a single-source quadrant earns one because coverage resting on one
## voice is not coverage.
static func build_reopening_questions(
	audit_record: RefCounted,
	closure_findings: Dictionary
) -> Array[String]:
	var questions: Array[String] = []
	var decision_text: String = String(audit_record.get_decision_under_audit()).strip_edges()
	var about_suffix: String = (
		" for the decision: %s" % decision_text if not decision_text.is_empty() else ""
	)
	for quadrant_id: String in audit_record.get_absences().keys():
		var entry: Dictionary = audit_record.get_absences()[quadrant_id]
		var classification: String = String(entry.get("classification", ""))
		var verdict: String = String(entry.get("verdict", ""))
		if classification == "suppressed":
			questions.append(
				"Quadrant %s was classified as suppressed: what is keeping it off the table%s?"
				% [quadrant_id, about_suffix]
			)
		elif classification == "unknown":
			questions.append(
				"Quadrant %s is unknown to the room: who would know, and what would it take"
				% quadrant_id
				+ " to find out%s?" % about_suffix
			)
		if verdict == "reopen":
			questions.append(
				"Triage put quadrant %s at reopen: what has to be revisited before the"
				% quadrant_id
				+ " decision stands%s?" % about_suffix
			)
	var concentration: Dictionary = audit_record.get_concentration()
	var concentration_class: String = String(concentration.get("classification", ""))
	if concentration_class in ["fixation", "suppression", "premature_closure"]:
		questions.append(
			"The weight in quadrant %s was read as %s: what is the room not looking at%s?"
			% [
				String(concentration.get("quadrant", "")),
				concentration_class.replace("_", " "),
				about_suffix,
			]
		)
	var single_source: Dictionary = closure_findings.get("single_source_quadrants", {})
	for quadrant_id: String in single_source.keys():
		questions.append(
			"Quadrant %s rests entirely on %s: who else can speak to it%s?"
			% [
				quadrant_id,
				String((single_source[quadrant_id] as Dictionary).get("author", "")),
				about_suffix,
			]
		)
	if int(closure_findings.get("contested_count", 0)) > 0:
		questions.append(
			"%d claim(s) are contested: what test would settle where they sit%s?"
			% [int(closure_findings.get("contested_count", 0)), about_suffix]
		)
	return questions


static func _propose(
	store: Object,
	category_id: String,
	text_value: String,
	audit_ref: String,
	audit_record: RefCounted
) -> Dictionary:
	var proposal: Dictionary = store.propose(category_id, text_value, {
		"authorship_kind": "ai_inference",
		"origin_ref": "scensyn.workshop_closure_audit@1",
		"audit_ref": audit_ref,
	})
	# An empty return means the store rejected it as a duplicate or suppressed key. Marking it
	# routed anyway is correct: the entry is already in the record, or the room has
	# suppressed it, and either way proposing it again would be noise.
	audit_record.mark_routed(audit_ref, category_id, String(proposal.get("id", "")))
	if proposal.is_empty():
		return {}
	return {
		"category": category_id,
		"proposal_id": String(proposal.get("id", "")),
		"text": text_value,
	}
