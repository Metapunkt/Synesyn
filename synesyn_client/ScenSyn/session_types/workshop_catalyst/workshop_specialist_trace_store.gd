extends Node
class_name WorkshopSpecialistTraceStore

signal trace_updated(trace: Dictionary)
signal candidate_batch_ready(batch_payload: Dictionary)

const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const SynesynSessionScript = preload("res://addons/synesyn_core/scripts/synesyn_session.gd")
const ARTIFACT_TYPE := "json.workshop_specialist_trace"

var _latest_trace: Dictionary = {}
var _hub_client: Node


func _ready() -> void:
	add_to_group("workshop_specialist_trace_store")


func retain_and_persist(
	turn_id: String,
	batch_result: Dictionary,
	synthesis_reference: Dictionary,
	stage_name: String = ""
) -> void:
	_latest_trace = build_trace(turn_id, batch_result, synthesis_reference)
	trace_updated.emit(_latest_trace.duplicate(true))
	candidate_batch_ready.emit({
		"schema_version": int(batch_result.get("schema_version", 1)),
		"turn_id": turn_id,
		"trace_ref": "specialist-trace:" + turn_id,
		"created_at": String(batch_result.get("completed_at", "")),
		"map_candidates": _safe_array(batch_result.get("map_candidates", [])),
		"facilitator_cues": _safe_array(batch_result.get("facilitator_cues", [])),
		"status": String(batch_result.get("status", "degraded")),
		"candidate_delivery_status": String(
			batch_result.get("candidate_delivery_status", "")
		),
		"map_candidate_origin": String(
			batch_result.get("map_candidate_origin", "model_structured")
		),
		"stage_name": stage_name.strip_edges(),
	})
	call_deferred("_persist_latest_trace", turn_id)


func get_latest_trace() -> Dictionary:
	return _latest_trace.duplicate(true)


func build_trace(
	turn_id: String,
	batch_result: Dictionary,
	synthesis_reference: Dictionary
) -> Dictionary:
	var contribution_values_any: Variant = batch_result.get("contributions", [])
	var contribution_values: Array = (
		contribution_values_any if typeof(contribution_values_any) == TYPE_ARRAY else []
	)
	var retained_contributions: Array[Dictionary] = []
	for contribution_any: Variant in contribution_values:
		if typeof(contribution_any) != TYPE_DICTIONARY:
			continue
		var contribution: Dictionary = contribution_any
		retained_contributions.append({
			"role_id": String(contribution.get("role_id", "")),
			"role_title": String(contribution.get("role_title", "")),
			"summary": String(contribution.get("summary", "")).left(1200),
			"created_at": String(batch_result.get("completed_at", "")),
		})
	var batch_status: String = String(batch_result.get("status", "degraded"))
	return {
		"schema_version": 2,
		"session_id": SynesynSessionScript.get_or_create_session_id("scensyn"),
		"turn_id": turn_id,
		"specialist_roles": retained_contributions.map(
			func(record: Dictionary) -> String: return String(record.get("role_id", ""))
		),
		"contributions": retained_contributions,
		"map_candidate_extraction": {
			"schema_version": int(batch_result.get("schema_version", 1)),
			"accepted": _safe_array(batch_result.get("map_candidates", [])),
			"rejected": _safe_array(batch_result.get("rejected_candidates", [])),
			"facilitator_cues": _safe_array(batch_result.get("facilitator_cues", [])),
		},
		"model_id": String(batch_result.get("model_id", "default")),
		"started_at": String(batch_result.get("started_at", "")),
		"completed_at": String(batch_result.get("completed_at", "")),
		"synthesis_reference": synthesis_reference.duplicate(true),
		"privacy": {
			"classification": "workshop_participant_visible_on_request",
			"contains_chain_of_thought": false,
			"contains_credentials": false,
		},
		"retention": {
			"status": "retained_local_pending_hub",
			"scope": "session",
			"revocable_display": true,
		},
		"status": batch_status,
		"failure_reason": String(batch_result.get("failure_reason", "")),
		"persistence_status": "pending",
	}


func _safe_array(value_any: Variant) -> Array:
	return (value_any as Array).duplicate(true) if typeof(value_any) == TYPE_ARRAY else []


func _persist_latest_trace(expected_turn_id: String) -> void:
	if String(_latest_trace.get("turn_id", "")) != expected_turn_id:
		return
	if not _ensure_hub_client():
		_set_persistence_status(expected_turn_id, "unavailable", "hub_client_unavailable")
		return
	var provenance: Dictionary = {
		"produced_by": "scensyn.workshop_specialist_coordinator@1",
		"inputs": [],
		"parameters": {"batched_specialist_operation": true},
		"timestamp": Time.get_datetime_string_from_system(true),
	}
	var response: Dictionary = await _hub_client.call(
		"stfx_store_commit_artifact",
		ARTIFACT_TYPE,
		_latest_trace.duplicate(true),
		provenance
	)
	if String(_latest_trace.get("turn_id", "")) != expected_turn_id:
		return
	if bool(response.get("ok", false)):
		var artifact_id: String = String(
			response.get("artifact_id", response.get("id", ""))
		).strip_edges()
		_latest_trace["artifact_id"] = artifact_id
		_set_persistence_status(expected_turn_id, "persisted", "")
	else:
		_set_persistence_status(
			expected_turn_id,
			"degraded",
			str(response.get("error", "hub_commit_failed")).left(240)
		)


func _ensure_hub_client() -> bool:
	if is_instance_valid(_hub_client):
		return true
	_hub_client = HubSubstrateClientScript.new()
	add_child(_hub_client)
	_hub_client.configure_from_runtime_config()
	return true


func _set_persistence_status(
	expected_turn_id: String,
	status_id: String,
	failure_reason: String
) -> void:
	if String(_latest_trace.get("turn_id", "")) != expected_turn_id:
		return
	_latest_trace["persistence_status"] = status_id
	if not failure_reason.is_empty():
		_latest_trace["persistence_failure"] = failure_reason
	var retention_any: Variant = _latest_trace.get("retention", {})
	var retention: Dictionary = retention_any if typeof(retention_any) == TYPE_DICTIONARY else {}
	retention["status"] = (
		"retained_hub"
		if status_id == "persisted"
		else "retained_in_memory_hub_unavailable"
	)
	_latest_trace["retention"] = retention
	trace_updated.emit(_latest_trace.duplicate(true))
