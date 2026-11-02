extends RefCounted
class_name WorkshopPathProposalEngine

## Converts generated/imported candidates into isolated proposals. It has no
## persistence or selection authority.

func import_candidates(
	candidates: Array,
	path_store: RefCounted,
	source_ref: String = "facilitator_import"
) -> Array[Dictionary]:
	var imported: Array[Dictionary] = []
	if not path_store:
		return imported
	for candidate_any: Variant in candidates:
		if typeof(candidate_any) != TYPE_DICTIONARY:
			continue
		var candidate: Dictionary = candidate_any
		var proposed: Dictionary = path_store.propose_path(candidate, {
			"authorship_kind": "proposal",
			"origin_ref": source_ref,
			"produced_by": "scensyn.workshop_path_proposal_engine@1",
			"created_at": Time.get_datetime_string_from_system(true),
		})
		if not proposed.is_empty():
			imported.append(proposed)
	return imported


func candidates_from_reviewed_record(reviewed_record: Dictionary) -> Array[Dictionary]:
	var decisions: Array = _items(reviewed_record, "decisions")
	var risks: Array = _items(reviewed_record, "risks")
	var next_steps: Array = _items(reviewed_record, "next_steps")
	var output: Array[Dictionary] = []
	for decision_any: Variant in decisions:
		if typeof(decision_any) != TYPE_DICTIONARY:
			continue
		var decision: Dictionary = decision_any
		var decision_text: String = String(decision.get("text", "")).strip_edges()
		if decision_text.is_empty():
			continue
		output.append({
			"title": decision_text,
			"label": decision_text,
			"outcomes": _texts(next_steps, "Implementation outcomes require facilitator review."),
			"biggest_risk": _first_text(risks, "No reviewed risk has been attached."),
			"assumptions": ["The reviewed decision remains feasible under current conditions."],
			"uncertainty": "Evidence and downstream effects require facilitator review.",
			"time_horizon": "To be set by the facilitator",
			"is_do_nothing": false,
			"evidence_refs": [],
			"evidence_status": "none",
			"previous_path_id": "",
			"provenance": {
				"record_item_id": String(decision.get("id", "")),
				"authorship_kind": "derived_proposal",
			},
		})
	return output


func _items(record_data: Dictionary, category_id: String) -> Array:
	var values_any: Variant = record_data.get(category_id, [])
	return values_any if typeof(values_any) == TYPE_ARRAY else []


func _texts(items: Array, fallback_text: String) -> Array[String]:
	var output: Array[String] = []
	for item_any: Variant in items:
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item_text: String = String(item_any.get("text", "")).strip_edges()
		if not item_text.is_empty():
			output.append(item_text)
	if output.is_empty():
		output.append(fallback_text)
	return output


func _first_text(items: Array, fallback_text: String) -> String:
	var values: Array[String] = _texts(items, fallback_text)
	return values[0]
