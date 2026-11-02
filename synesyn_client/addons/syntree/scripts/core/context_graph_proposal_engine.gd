## Purpose: Normalize, review, and preview Context Graph proposals without commit access.
extends RefCounted

const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)

const PROPOSAL_TYPES: Array[String] = [
	"relationship",
	"duplicate",
	"contradiction",
	"cluster",
	"missing_link",
	"node_split",
	"node_merge",
	"metaprompt_candidate",
]
const OPERATIONS: Array[String] = [
	"add_node",
	"update_node",
	"remove_node",
	"add_edge",
	"update_edge",
	"remove_edge",
]
const STATUSES: Array[String] = [
	"suggested",
	"accepted",
	"edited",
	"rejected",
	"deferred",
]


func normalize(proposal: Dictionary) -> Dictionary:
	var proposal_id: String = str(proposal.get("id", "")).strip_edges()
	if proposal_id.is_empty():
		var seed_text: String = JSON.stringify(proposal)
		proposal_id = "proposal_%s" % seed_text.sha256_text().substr(0, 20)
	return {
		"id": proposal_id,
		"proposal_type": _enum_value(
			proposal.get("proposal_type", ""),
			PROPOSAL_TYPES,
			"missing_link"
		),
		"operation": _enum_value(
			proposal.get("operation", ""),
			OPERATIONS,
			"add_edge"
		),
		"status": _enum_value(
			proposal.get("status", ""),
			STATUSES,
			"suggested"
		),
		"payload": _dictionary(proposal.get("payload", {})),
		"rationale": str(proposal.get("rationale", "")),
		"evidence_refs": _unique_strings(
			proposal.get("evidence_refs", [])
		),
		"affected_record_ids": _unique_strings(
			proposal.get("affected_record_ids", [])
		),
		"model_id": str(proposal.get("model_id", "")),
		"provider_id": str(proposal.get("provider_id", "")),
		"prompt_config": _dictionary(
			proposal.get("prompt_config", {})
		),
		"confidence": clampf(
			float(proposal.get("confidence", 0.0)),
			0.0,
			1.0
		),
		"created_at": str(proposal.get(
			"created_at",
			Time.get_datetime_string_from_system(true)
		)),
		"reviewed_at": str(proposal.get("reviewed_at", "")),
		"reviewer_note": str(proposal.get("reviewer_note", "")),
	}


func validate(proposal: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize(proposal)
	var errors: Array[String] = []
	if str(normalized.get("id", "")).is_empty():
		errors.append("proposal_id_required")
	if (normalized.get("payload", {}) as Dictionary).is_empty():
		errors.append("proposal_payload_required")
	var operation_id: String = str(normalized.get("operation", ""))
	var payload: Dictionary = normalized.get("payload", {})
	if operation_id.begins_with("remove_"):
		if str(payload.get("id", "")).is_empty():
			errors.append("remove_record_id_required")
	elif str(payload.get("id", "")).is_empty():
		errors.append("payload_record_id_required")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"proposal": normalized,
	}


func review(
	proposal: Dictionary,
	decision: String,
	edited_payload: Dictionary = {},
	reviewer_note: String = ""
) -> Dictionary:
	var normalized: Dictionary = normalize(proposal)
	var decision_id: String = _enum_value(
		decision,
		STATUSES,
		"deferred"
	)
	if decision_id == "suggested":
		decision_id = "deferred"
	normalized["status"] = decision_id
	if decision_id == "edited" and not edited_payload.is_empty():
		normalized["payload"] = edited_payload.duplicate(true)
	normalized["reviewed_at"] = Time.get_datetime_string_from_system(true)
	normalized["reviewer_note"] = reviewer_note
	return {
		"proposal": normalized,
		"event": {
			"event_type": "syntree.context_graph.proposal_reviewed",
			"proposal_id": normalized.get("id", ""),
			"decision": decision_id,
			"reviewer_note": reviewer_note,
			"created_at": normalized.get("reviewed_at", ""),
		},
	}


func preview(
	document: Dictionary,
	proposals: Array
) -> Dictionary:
	var preview_document: Dictionary = document.duplicate(true)
	var applied_ids: Array[String] = []
	var errors: Array[String] = []
	for proposal_any in proposals:
		if typeof(proposal_any) != TYPE_DICTIONARY:
			continue
		var validation: Dictionary = validate(proposal_any)
		if not bool(validation.get("ok", false)):
			errors.append_array(validation.get("errors", []))
			continue
		var proposal: Dictionary = validation.get("proposal", {})
		if str(proposal.get("status", "")) not in ["accepted", "edited"]:
			continue
		var apply_result: Dictionary = _apply_operation(
			preview_document,
			proposal
		)
		if not bool(apply_result.get("ok", false)):
			errors.append(str(apply_result.get("error", "")))
			continue
		applied_ids.append(str(proposal.get("id", "")))
	var graph_validation: Dictionary = GraphWorkspaceDocumentScript.validate(
		preview_document,
		str(document.get("graph_kind", ""))
	)
	errors.append_array(graph_validation.get("errors", []))
	return {
		"ok": errors.is_empty(),
		"document": preview_document,
		"semantic_diff": GraphWorkspaceDocumentScript.semantic_diff(
			document,
			preview_document
		),
		"applied_proposal_ids": applied_ids,
		"errors": errors,
	}


func _apply_operation(
	document: Dictionary,
	proposal: Dictionary
) -> Dictionary:
	var operation_id: String = str(proposal.get("operation", ""))
	var payload: Dictionary = (
		proposal.get("payload", {}) as Dictionary
	).duplicate(true)
	if operation_id in ["add_node", "update_node", "add_edge", "update_edge"]:
		payload["status"] = (
			"edited"
			if str(proposal.get("status", "")) == "edited"
			else "accepted"
		)
	var collection_key: String = (
		"nodes" if operation_id.ends_with("node") else "edges"
	)
	var records: Array = document.get(collection_key, [])
	var record_id: String = str(payload.get("id", ""))
	var record_index: int = _record_index(records, record_id)
	if operation_id.begins_with("add_"):
		if record_index >= 0:
			return {"ok": false, "error": "record_already_exists:%s" % record_id}
		records.append(payload)
	elif operation_id.begins_with("update_"):
		if record_index < 0:
			return {"ok": false, "error": "record_not_found:%s" % record_id}
		records[record_index] = payload
	elif operation_id.begins_with("remove_"):
		if record_index < 0:
			return {"ok": false, "error": "record_not_found:%s" % record_id}
		records.remove_at(record_index)
		if collection_key == "nodes":
			_remove_incident_edges(document, record_id)
	document[collection_key] = records
	return {"ok": true}


func _remove_incident_edges(document: Dictionary, node_id: String) -> void:
	var kept_edges: Array = []
	for edge_any in document.get("edges", []):
		var edge_data: Dictionary = edge_any
		if (
			str(edge_data.get("from", "")) != node_id
			and str(edge_data.get("to", "")) != node_id
		):
			kept_edges.append(edge_data)
	document["edges"] = kept_edges


func _record_index(records: Array, record_id: String) -> int:
	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		if str(record.get("id", "")) == record_id:
			return record_index
	return -1


func _enum_value(
	value: Variant,
	allowed_values: Array[String],
	fallback: String
) -> String:
	var value_id: String = str(value).strip_edges().to_lower()
	return value_id if allowed_values.has(value_id) else fallback


func _dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return (value as Dictionary).duplicate(true)


func _unique_strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item_any in value:
		var item_text: String = str(item_any).strip_edges()
		if not item_text.is_empty() and not result.has(item_text):
			result.append(item_text)
	return result
