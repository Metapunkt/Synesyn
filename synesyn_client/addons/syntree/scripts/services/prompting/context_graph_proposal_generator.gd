## Purpose: Request suggested graph changes without access to graph commit APIs.
extends RefCounted

const ProposalEngineScript = preload(
	"res://addons/syntree/scripts/core/context_graph_proposal_engine.gd"
)

var _engine: RefCounted = ProposalEngineScript.new()


func generate(
	api_service: Object,
	document: Dictionary,
	request_text: String,
	model_id: String = ""
) -> Dictionary:
	if (
		not is_instance_valid(api_service)
		or not api_service.has_method("process_message_with_history")
	):
		return {"ok": false, "error": "api_service_unavailable"}
	var system_context: String = (
		"You propose Context Graph changes for human review. "
		+ "Return only a JSON array. Never claim to commit changes. "
		+ "Each item must contain proposal_type, operation, payload, "
		+ "rationale, evidence_refs, affected_record_ids, confidence. "
		+ "Allowed operations: add_node, update_node, remove_node, "
		+ "add_edge, update_edge, remove_edge. Proposed node/edge payloads "
		+ "must include stable id, status='suggested', and provenance_refs. "
		+ "Graph:\n"
		+ JSON.stringify(document)
	)
	var messages: Array = [{
		"role": "user",
		"content": request_text,
	}]
	var response: Dictionary = await api_service.call(
		"process_message_with_history",
		messages,
		system_context,
		model_id
	)
	if not bool(response.get("success", false)):
		return {
			"ok": false,
			"error": str(response.get("error", "proposal_request_failed")),
		}
	var parsed: Variant = _parse_json_array(
		str(response.get("response", ""))
	)
	if typeof(parsed) != TYPE_ARRAY:
		return {"ok": false, "error": "proposal_response_not_array"}
	var proposals: Array[Dictionary] = []
	var errors: Array[String] = []
	for proposal_any in parsed:
		if typeof(proposal_any) != TYPE_DICTIONARY:
			errors.append("proposal_must_be_object")
			continue
		var proposal: Dictionary = (
			proposal_any as Dictionary
		).duplicate(true)
		proposal["status"] = "suggested"
		if str(proposal.get("model_id", "")).is_empty():
			proposal["model_id"] = model_id
		var validation: Dictionary = _engine.call(
			"validate",
			proposal
		)
		if not bool(validation.get("ok", false)):
			errors.append_array(validation.get("errors", []))
			continue
		proposals.append(validation.get("proposal", {}))
	return {
		"ok": not proposals.is_empty(),
		"proposals": proposals,
		"errors": errors,
	}


func _parse_json_array(response_text: String) -> Variant:
	var clean_text: String = response_text.strip_edges()
	if clean_text.begins_with("```"):
		var first_newline: int = clean_text.find("\n")
		if first_newline >= 0:
			clean_text = clean_text.substr(first_newline + 1)
		if clean_text.ends_with("```"):
			clean_text = clean_text.left(-3).strip_edges()
	return JSON.parse_string(clean_text)
