extends RefCounted
class_name WorkshopPathStore

const SCHEMA_VERSION: int = 1
const REVIEWED_STATES: Array[String] = ["accepted", "edited"]
const REVIEW_ACTIONS: Array[String] = ["accepted", "edited", "rejected", "deferred"]
const EVIDENCE_STATES: Array[String] = ["supported", "partial", "none", "degraded", "unavailable"]

var _session_id: String = ""
var _scenario_id: String = ""
var _paths: Array[Dictionary] = []
var _proposal_decisions: Array[Dictionary] = []
var _selection: Dictionary = {}
var _retrieval: Dictionary = {}
var _last_committed_artifact_id: String = ""
var _last_committed_payload: Dictionary = {}
var _is_dirty: bool = false


func initialize(
	session_id: String,
	scenario_id: String = "",
	saved_state: Dictionary = {}
) -> void:
	_session_id = session_id.strip_edges()
	_scenario_id = scenario_id.strip_edges()
	if saved_state.is_empty():
		_paths = [_default_do_nothing_path()]
		_is_dirty = true
	else:
		_load(saved_state)
		_repair_do_nothing_invariant()


func propose_path(candidate: Dictionary, provenance: Dictionary = {}) -> Dictionary:
	var normalized: Dictionary = normalize_path(candidate, provenance)
	if normalized.is_empty():
		return {}
	var path_id: String = String(normalized.get("id", ""))
	var existing_index: int = _path_index(path_id)
	if existing_index >= 0:
		var existing: Dictionary = _paths[existing_index]
		if bool(existing.get("facilitator_edited", false)):
			return {}
		if String(existing.get("review_state", "")) in REVIEWED_STATES:
			return {}
		_paths[existing_index] = normalized
	else:
		_paths.append(normalized)
	_repair_do_nothing_invariant()
	_is_dirty = true
	return normalized.duplicate(true)


func review_path(
	path_id: String,
	action_id: String,
	edited_fields: Dictionary = {},
	facilitator_ref: String = "Facilitator"
) -> bool:
	var path_index: int = _path_index(path_id)
	if path_index < 0 or action_id not in REVIEW_ACTIONS:
		return false
	var path_data: Dictionary = _paths[path_index]
	if String(path_data.get("review_state", "")) != "suggested":
		return false
	if action_id == "edited":
		var merged: Dictionary = path_data.duplicate(true)
		for field_id: String in [
			"title", "label", "outcomes", "biggest_risk", "assumptions",
			"uncertainty", "time_horizon", "evidence_refs", "evidence_status",
		]:
			if edited_fields.has(field_id):
				merged[field_id] = edited_fields[field_id]
		var normalized_edit: Dictionary = normalize_path(
			merged,
			path_data.get("provenance", {}) as Dictionary
		)
		if normalized_edit.is_empty():
			return false
		normalized_edit["review_state"] = "edited"
		normalized_edit["facilitator_edited"] = true
		normalized_edit["reviewed_by"] = facilitator_ref
		normalized_edit["reviewed_at"] = _now()
		normalized_edit["updated_at"] = _now()
		path_data = normalized_edit
	else:
		path_data["review_state"] = action_id
		path_data["reviewed_by"] = facilitator_ref
		path_data["reviewed_at"] = _now()
		path_data["updated_at"] = _now()
	_paths[path_index] = path_data
	_proposal_decisions.append({
		"path_id": path_id,
		"decision": action_id,
		"reviewed_by": facilitator_ref,
		"reviewed_at": path_data["reviewed_at"],
		"facilitator_edited": action_id == "edited",
	})
	_selection = {}
	_is_dirty = true
	return true


func select_path(path_id: String, facilitator_ref: String = "Facilitator") -> bool:
	if not _is_accepted_path(path_id):
		return false
	_selection = {
		"kind": "single",
		"path_ids": [path_id],
		"label": String(_paths[_path_index(path_id)].get("title", "")),
		"selected_by": facilitator_ref,
		"selected_at": _now(),
	}
	_is_dirty = true
	return true


func combine_paths(
	path_ids: Array,
	combination_label: String,
	facilitator_ref: String = "Facilitator"
) -> bool:
	var unique_ids: Array[String] = []
	for path_id_any: Variant in path_ids:
		var path_id: String = String(path_id_any).strip_edges()
		if not path_id.is_empty() and path_id not in unique_ids and _is_accepted_path(path_id):
			unique_ids.append(path_id)
	if unique_ids.size() < 2 or combination_label.strip_edges().is_empty():
		return false
	_selection = {
		"kind": "combined",
		"path_ids": unique_ids,
		"label": combination_label.strip_edges(),
		"selected_by": facilitator_ref,
		"selected_at": _now(),
	}
	_is_dirty = true
	return true


func clear_selection() -> void:
	_selection = {}
	_is_dirty = true


func apply_evidence_result(result: Dictionary) -> bool:
	var request_id: String = String(result.get("request_id", "")).strip_edges()
	if request_id.is_empty():
		return false
	_retrieval = result.duplicate(true)
	var refs_any: Variant = result.get("evidence_refs", [])
	var refs: Array = refs_any.duplicate(true) if typeof(refs_any) == TYPE_ARRAY else []
	var evidence_by_path_any: Variant = result.get("evidence_by_path", {})
	var evidence_by_path: Dictionary = (
		evidence_by_path_any if typeof(evidence_by_path_any) == TYPE_DICTIONARY else {}
	)
	for path_index: int in range(_paths.size()):
		var path_data: Dictionary = _paths[path_index]
		var path_id: String = String(path_data.get("id", ""))
		var has_path_specific_refs: bool = evidence_by_path.has(path_id)
		var path_refs_any: Variant = evidence_by_path.get(path_id, refs)
		var path_refs: Array = (
			path_refs_any.duplicate(true) if typeof(path_refs_any) == TYPE_ARRAY else []
		)
		path_data["evidence_refs"] = _normalize_evidence_refs(path_refs)
		if (path_data["evidence_refs"] as Array).is_empty():
			path_data["evidence_status"] = _degraded_evidence_status(result)
		else:
			path_data["evidence_status"] = (
				"supported" if has_path_specific_refs else "partial"
			)
		path_data["updated_at"] = _now()
		_paths[path_index] = path_data
	_is_dirty = true
	return true


func build_preview(facilitator_ref: String = "Facilitator") -> Dictionary:
	var before_state: Dictionary = get_state()
	var payload: Dictionary = build_commit_payload(facilitator_ref)
	var validation: Dictionary = validate_commit_payload(payload)
	var prior_paths: Array = _last_committed_payload.get("paths", [])
	return {
		"valid": bool(validation.get("ok", false)),
		"errors": validation.get("errors", []),
		"resulting_path_set": payload,
		"semantic_diff": _diff_paths(prior_paths, payload.get("paths", [])),
		"mutated": get_state() != before_state,
	}


func build_commit_payload(facilitator_ref: String = "Facilitator") -> Dictionary:
	var comparison_paths: Array[Dictionary] = []
	for path_data: Dictionary in _paths:
		if String(path_data.get("review_state", "")) in REVIEWED_STATES:
			comparison_paths.append(path_data.duplicate(true))
	var trace_ids: Array[String] = []
	var trace_id: String = String(_retrieval.get("trace_id", "")).strip_edges()
	if not trace_id.is_empty():
		trace_ids.append(trace_id)
	return {
		"schema_version": SCHEMA_VERSION,
		"session_id": _session_id,
		"scenario_id": _scenario_id,
		"session_type_id": "workshop_catalyst",
		"collection_id": "decision_triage",
		"review_status": "facilitator_reviewed",
		"proposal_status": "review_complete",
		"paths": comparison_paths,
		"proposal_decisions": _proposal_decisions.duplicate(true),
		"selection": _selection.duplicate(true),
		"evidence_retrieval": _retrieval.duplicate(true),
		"store_trace_ids": trace_ids,
		"facilitator_provenance": {
			"reviewed_by": facilitator_ref,
			"authorship_kind": "user_reviewed",
			"reviewed_at": _now(),
		},
		"previous_version_id": _last_committed_artifact_id,
		"closure_ref": "",
	}


func validate_commit_payload(payload: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var paths_any: Variant = payload.get("paths", [])
	var paths: Array = paths_any if typeof(paths_any) == TYPE_ARRAY else []
	var do_nothing_count: int = 0
	var path_ids: Array[String] = []
	for path_any: Variant in paths:
		if typeof(path_any) != TYPE_DICTIONARY:
			errors.append("Every path must be an object.")
			continue
		var path_data: Dictionary = path_any
		var field_errors: Array[String] = validate_path(path_data)
		errors.append_array(field_errors)
		var path_id: String = String(path_data.get("id", ""))
		if path_id in path_ids:
			errors.append("Path ids must be unique.")
		path_ids.append(path_id)
		if bool(path_data.get("is_do_nothing", false)):
			do_nothing_count += 1
	if do_nothing_count != 1:
		errors.append("A committed comparison requires exactly one do-nothing path.")
	var selection_any: Variant = payload.get("selection", {})
	var selection: Dictionary = selection_any if typeof(selection_any) == TYPE_DICTIONARY else {}
	var selected_ids_any: Variant = selection.get("path_ids", [])
	var selected_ids: Array = selected_ids_any if typeof(selected_ids_any) == TYPE_ARRAY else []
	if selected_ids.is_empty():
		errors.append("The facilitator must explicitly select or combine accepted paths.")
	for selected_id_any: Variant in selected_ids:
		if String(selected_id_any) not in path_ids:
			errors.append("Selection references a path outside the reviewed comparison.")
	if String(selection.get("kind", "")) == "combined" and selected_ids.size() < 2:
		errors.append("A combined selection requires at least two paths.")
	return {"ok": errors.is_empty(), "errors": errors}


func mark_committed(artifact_id: String, payload: Dictionary, closure_ref: String) -> void:
	_last_committed_artifact_id = artifact_id.strip_edges()
	_last_committed_payload = payload.duplicate(true)
	_last_committed_payload["closure_ref"] = closure_ref
	_is_dirty = false


func build_session_record_outcomes() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if _last_committed_payload.is_empty():
		return output
	var selected_ids_any: Variant = (
		_last_committed_payload.get("selection", {}) as Dictionary
	).get("path_ids", [])
	var selected_ids: Array = selected_ids_any if typeof(selected_ids_any) == TYPE_ARRAY else []
	for path_any: Variant in _last_committed_payload.get("paths", []):
		if typeof(path_any) != TYPE_DICTIONARY:
			continue
		var path_data: Dictionary = path_any
		if String(path_data.get("id", "")) not in selected_ids:
			continue
		for outcome_any: Variant in path_data.get("outcomes", []):
			var outcome_text: String = String(outcome_any).strip_edges()
			if not outcome_text.is_empty():
				output.append({
					"category": "decisions",
					"text": outcome_text,
					"path_id": String(path_data.get("id", "")),
					"path_set_artifact_id": _last_committed_artifact_id,
				})
	return output


func get_paths() -> Array[Dictionary]:
	return _paths.duplicate(true)


func get_selection() -> Dictionary:
	return _selection.duplicate(true)


func get_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session_id": _session_id,
		"scenario_id": _scenario_id,
		"paths": _paths.duplicate(true),
		"proposal_decisions": _proposal_decisions.duplicate(true),
		"selection": _selection.duplicate(true),
		"retrieval": _retrieval.duplicate(true),
		"last_committed_artifact_id": _last_committed_artifact_id,
		"last_committed_payload": _last_committed_payload.duplicate(true),
		"is_dirty": _is_dirty,
	}


func get_last_committed_artifact_id() -> String:
	return _last_committed_artifact_id


func is_dirty() -> bool:
	return _is_dirty


static func normalize_path(candidate: Dictionary, provenance: Dictionary = {}) -> Dictionary:
	var title_text: String = String(
		candidate.get("title", candidate.get("label", ""))
	).strip_edges()
	if title_text.is_empty():
		return {}
	var is_do_nothing_path: bool = bool(candidate.get("is_do_nothing", false))
	var outcomes: Array[String] = _normalize_string_array(candidate.get("outcomes", []))
	var assumptions: Array[String] = _normalize_string_array(candidate.get("assumptions", []))
	var biggest_risk_text: String = String(candidate.get("biggest_risk", "")).strip_edges()
	var uncertainty_text: String = String(candidate.get("uncertainty", "")).strip_edges()
	var horizon_text: String = String(candidate.get("time_horizon", "")).strip_edges()
	var refs: Array[Dictionary] = _normalize_evidence_refs(candidate.get("evidence_refs", []))
	var evidence_status_id: String = String(candidate.get("evidence_status", "")).strip_edges()
	if refs.is_empty():
		evidence_status_id = "none" if evidence_status_id not in ["degraded", "unavailable"] else evidence_status_id
	elif evidence_status_id not in EVIDENCE_STATES or evidence_status_id == "none":
		evidence_status_id = "supported"
	var source_key: String = String(candidate.get("id", "")).strip_edges()
	if source_key.is_empty():
		source_key = "%s|%s" % [title_text.to_lower(), str(is_do_nothing_path)]
	var created_at_text: String = String(candidate.get("created_at", _now()))
	return {
		"id": source_key if source_key.begins_with("wpath_") else "wpath_" + source_key.sha256_text().left(20),
		"title": title_text,
		"label": String(candidate.get("label", title_text)).strip_edges(),
		"outcomes": outcomes,
		"biggest_risk": biggest_risk_text,
		"assumptions": assumptions,
		"uncertainty": uncertainty_text,
		"time_horizon": horizon_text,
		"is_do_nothing": is_do_nothing_path,
		"evidence_refs": refs,
		"evidence_status": evidence_status_id,
		"proposal_state": "proposal",
		"review_state": String(candidate.get("review_state", "suggested")),
		"facilitator_edited": bool(candidate.get("facilitator_edited", false)),
		"provenance": provenance.duplicate(true) if not provenance.is_empty() else candidate.get("provenance", {}).duplicate(true),
		"created_at": created_at_text,
		"updated_at": String(candidate.get("updated_at", created_at_text)),
		"reviewed_at": String(candidate.get("reviewed_at", "")),
		"reviewed_by": String(candidate.get("reviewed_by", "")),
		"previous_path_id": String(candidate.get("previous_path_id", "")),
	}


static func validate_path(path_data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field_id: String in ["id", "title", "biggest_risk", "uncertainty", "time_horizon"]:
		if String(path_data.get(field_id, "")).strip_edges().is_empty():
			errors.append("Path '%s' requires %s." % [String(path_data.get("title", "untitled")), field_id])
	if _normalize_string_array(path_data.get("outcomes", [])).is_empty():
		errors.append("Every path requires at least one outcome.")
	if _normalize_string_array(path_data.get("assumptions", [])).is_empty():
		errors.append("Every path requires at least one assumption.")
	var refs: Array[Dictionary] = _normalize_evidence_refs(path_data.get("evidence_refs", []))
	var evidence_status_id: String = String(path_data.get("evidence_status", ""))
	if refs.is_empty() and evidence_status_id not in ["none", "degraded", "unavailable"]:
		errors.append("A path without references must explicitly label evidence as none or unavailable.")
	if not refs.is_empty() and evidence_status_id == "none":
		errors.append("Evidence status none cannot include references.")
	if String(path_data.get("review_state", "")) not in REVIEWED_STATES:
		errors.append("Only accepted or facilitator-edited paths can be committed.")
	return errors


static func _normalize_string_array(values_any: Variant) -> Array[String]:
	var output: Array[String] = []
	if typeof(values_any) != TYPE_ARRAY:
		return output
	for value_any: Variant in values_any:
		var clean_text: String = String(value_any).strip_edges()
		if not clean_text.is_empty() and clean_text not in output:
			output.append(clean_text)
	return output


static func _normalize_evidence_refs(values_any: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if typeof(values_any) != TYPE_ARRAY:
		return output
	for value_any: Variant in values_any:
		if typeof(value_any) == TYPE_DICTIONARY:
			var ref_data: Dictionary = value_any
			var ref_id: String = String(ref_data.get("id", ref_data.get("source_id", ""))).strip_edges()
			if ref_id.is_empty():
				continue
			output.append({
				"id": ref_id,
				"title": String(ref_data.get("title", ref_data.get("label", ref_id))).strip_edges(),
				"excerpt": String(ref_data.get("excerpt", ref_data.get("text", ""))).strip_edges(),
				"source_uri": String(ref_data.get("source_uri", ref_data.get("path", ""))).strip_edges(),
			})
		elif not String(value_any).strip_edges().is_empty():
			var ref_id_text: String = String(value_any).strip_edges()
			output.append({"id": ref_id_text, "title": ref_id_text, "excerpt": "", "source_uri": ""})
	return output


func _default_do_nothing_path() -> Dictionary:
	return normalize_path({
		"title": "Continue without a new intervention",
		"label": "Do nothing / continue current course",
		"outcomes": ["Current course and existing commitments continue."],
		"biggest_risk": "Existing problems may persist or worsen without intervention.",
		"assumptions": ["Current conditions remain sufficiently stable to continue."],
		"uncertainty": "Consequences of delay and external changes remain uncertain.",
		"time_horizon": "Current planning horizon",
		"is_do_nothing": true,
		"evidence_refs": [],
		"evidence_status": "none",
		"provenance": {
			"authorship_kind": "system_required_proposal",
			"produced_by": "scensyn.workshop_compare_paths@1",
		},
	})


func _repair_do_nothing_invariant() -> void:
	var first_index: int = -1
	for path_index: int in range(_paths.size() - 1, -1, -1):
		if not bool(_paths[path_index].get("is_do_nothing", false)):
			continue
		if first_index < 0:
			first_index = path_index
		else:
			_paths.remove_at(path_index)
	if first_index < 0:
		_paths.append(_default_do_nothing_path())


func _path_index(path_id: String) -> int:
	for path_index: int in range(_paths.size()):
		if String(_paths[path_index].get("id", "")) == path_id:
			return path_index
	return -1


func _is_accepted_path(path_id: String) -> bool:
	var path_index: int = _path_index(path_id)
	return (
		path_index >= 0
		and String(_paths[path_index].get("review_state", "")) in REVIEWED_STATES
	)


func _load(saved_state: Dictionary) -> void:
	# JSON / Variant-backed arrays are untyped Array; .assign() coerces into
	# Array[Dictionary] (direct assignment raises a runtime type error).
	_paths.clear()
	var paths_any: Variant = saved_state.get("paths", [])
	if typeof(paths_any) == TYPE_ARRAY:
		_paths.assign((paths_any as Array).duplicate(true))
	_proposal_decisions.clear()
	var decisions_any: Variant = saved_state.get("proposal_decisions", [])
	if typeof(decisions_any) == TYPE_ARRAY:
		_proposal_decisions.assign((decisions_any as Array).duplicate(true))
	var selection_any: Variant = saved_state.get("selection", {})
	_selection = selection_any.duplicate(true) if typeof(selection_any) == TYPE_DICTIONARY else {}
	var retrieval_any: Variant = saved_state.get("retrieval", {})
	_retrieval = retrieval_any.duplicate(true) if typeof(retrieval_any) == TYPE_DICTIONARY else {}
	_last_committed_artifact_id = String(saved_state.get("last_committed_artifact_id", ""))
	var committed_any: Variant = saved_state.get("last_committed_payload", {})
	_last_committed_payload = (
		committed_any.duplicate(true) if typeof(committed_any) == TYPE_DICTIONARY else {}
	)
	_is_dirty = bool(saved_state.get("is_dirty", false))


func _degraded_evidence_status(result: Dictionary) -> String:
	var retrieval_status: String = String(result.get("status", "none"))
	return retrieval_status if retrieval_status in ["degraded", "unavailable"] else "none"


func _diff_paths(previous_paths: Array, current_paths: Array) -> Dictionary:
	var previous_by_id: Dictionary = {}
	for path_any: Variant in previous_paths:
		if typeof(path_any) == TYPE_DICTIONARY:
			previous_by_id[String(path_any.get("id", ""))] = path_any
	var current_by_id: Dictionary = {}
	for path_any: Variant in current_paths:
		if typeof(path_any) == TYPE_DICTIONARY:
			current_by_id[String(path_any.get("id", ""))] = path_any
	var added: Array = []
	var removed: Array = []
	var changed: Array = []
	for path_id: String in current_by_id:
		if not previous_by_id.has(path_id):
			added.append(current_by_id[path_id])
		elif JSON.stringify(previous_by_id[path_id]) != JSON.stringify(current_by_id[path_id]):
			changed.append({"before": previous_by_id[path_id], "after": current_by_id[path_id]})
	for path_id: String in previous_by_id:
		if not current_by_id.has(path_id):
			removed.append(previous_by_id[path_id])
	return {"added": added, "changed": changed, "removed": removed}


static func _now() -> String:
	return Time.get_datetime_string_from_system(true)
