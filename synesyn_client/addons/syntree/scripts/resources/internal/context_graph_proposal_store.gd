## Purpose: Persist proposal/review state without mutating canonical graph records.
extends RefCounted

const ProposalEngineScript = preload(
	"res://addons/syntree/scripts/core/context_graph_proposal_engine.gd"
)

var _engine: RefCounted = ProposalEngineScript.new()


func get_proposals(
	content_state: Object,
	source_id: String
) -> Array[Dictionary]:
	var source_data: Dictionary = content_state.call(
		"get_source_data",
		source_id
	)
	var ai_context: Dictionary = (
		source_data.get("meta", {}) as Dictionary
	).get("ai_context", {})
	var proposals_any: Variant = ai_context.get(
		"context_graph_proposals",
		[]
	)
	var proposals: Array[Dictionary] = []
	if typeof(proposals_any) != TYPE_ARRAY:
		return proposals
	for proposal_any in proposals_any:
		if typeof(proposal_any) == TYPE_DICTIONARY:
			proposals.append(_engine.call("normalize", proposal_any))
	proposals.sort_custom(_newest_first)
	return proposals


func upsert_suggestion(
	content_state: Object,
	source_id: String,
	proposal: Dictionary
) -> Dictionary:
	var normalized: Dictionary = _engine.call("normalize", proposal)
	normalized["status"] = "suggested"
	var validation: Dictionary = _engine.call("validate", normalized)
	if not bool(validation.get("ok", false)):
		return validation
	var proposals: Array[Dictionary] = get_proposals(
		content_state,
		source_id
	)
	var signature: String = _signature(normalized)
	for existing in proposals:
		if (
			_signature(existing) == signature
			and str(existing.get("status", "")) in [
				"rejected",
				"deferred",
			]
		):
			return {
				"ok": true,
				"suppressed": true,
				"proposal": existing,
			}
	var proposal_index: int = _proposal_index(
		proposals,
		str(normalized.get("id", ""))
	)
	if proposal_index >= 0:
		proposals[proposal_index] = normalized
	else:
		proposals.append(normalized)
	return _write(content_state, source_id, proposals, normalized)


func review(
	content_state: Object,
	source_id: String,
	proposal_id: String,
	decision: String,
	edited_payload: Dictionary = {},
	reviewer_note: String = ""
) -> Dictionary:
	var proposals: Array[Dictionary] = get_proposals(
		content_state,
		source_id
	)
	var proposal_index: int = _proposal_index(proposals, proposal_id)
	if proposal_index < 0:
		return {"ok": false, "errors": ["proposal_not_found"]}
	var review_result: Dictionary = _engine.call(
		"review",
		proposals[proposal_index],
		decision,
		edited_payload,
		reviewer_note
	)
	var reviewed: Dictionary = review_result.get("proposal", {})
	proposals[proposal_index] = reviewed
	var write_result: Dictionary = _write(
		content_state,
		source_id,
		proposals,
		reviewed
	)
	write_result["event"] = review_result.get("event", {})
	return write_result


func _write(
	content_state: Object,
	source_id: String,
	proposals: Array[Dictionary],
	changed_proposal: Dictionary
) -> Dictionary:
	var source_data: Dictionary = content_state.call(
		"get_source_data",
		source_id
	)
	if source_data.is_empty():
		return {"ok": false, "errors": ["source_not_found"]}
	var source_meta: Dictionary = source_data.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	ai_context["context_graph_proposals"] = proposals
	source_meta["ai_context"] = ai_context
	source_data["meta"] = source_meta
	var did_save: bool = bool(content_state.call(
		"update_source",
		source_id,
		source_data
	))
	return {
		"ok": did_save,
		"proposal": changed_proposal,
		"errors": [] if did_save else ["source_update_failed"],
	}


func _proposal_index(
	proposals: Array[Dictionary],
	proposal_id: String
) -> int:
	for proposal_index in range(proposals.size()):
		if str(proposals[proposal_index].get("id", "")) == proposal_id:
			return proposal_index
	return -1


func _signature(proposal: Dictionary) -> String:
	return JSON.stringify({
		"proposal_type": proposal.get("proposal_type", ""),
		"operation": proposal.get("operation", ""),
		"payload": proposal.get("payload", {}),
		"evidence_refs": proposal.get("evidence_refs", []),
	}).sha256_text()


func _newest_first(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("created_at", "")) > str(
		right.get("created_at", "")
	)
