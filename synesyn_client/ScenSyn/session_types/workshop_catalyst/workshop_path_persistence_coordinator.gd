extends Node
class_name WorkshopPathPersistenceCoordinator

signal commit_started
signal artifact_persisted(artifact_id: String)
signal commit_succeeded(artifact_id: String, closure_ref: String, payload: Dictionary)
signal commit_failed(error_text: String)

const ARTIFACT_TYPE: String = "ui.workshop_path_set"
const HubErrorTextScript = preload(
	"res://addons/synesyn_core/scripts/hub_error_text.gd"
)

var _hub_client: Object = null
var _closure_bus: Object = null
var _store: RefCounted = null
var _pending_payload: Dictionary = {}
var _persisted_artifact_id: String = ""
var _is_committing: bool = false


func configure(hub_client: Object, closure_bus: Object, path_store: RefCounted) -> void:
	_hub_client = hub_client
	_closure_bus = closure_bus
	_store = path_store


func request_commit_payload(payload: Dictionary) -> void:
	if _is_committing:
		return
	if payload.is_empty():
		commit_failed.emit("A valid Compare Paths preview is required.")
		return
	var validation: Dictionary = _store.validate_commit_payload(payload)
	if not bool(validation.get("ok", false)):
		commit_failed.emit("Path comparison is invalid: " + "; ".join(validation.get("errors", []) as Array))
		return
	_pending_payload = payload.duplicate(true)
	_persisted_artifact_id = ""
	_commit_pending()


func retry() -> void:
	if _is_committing:
		return
	if _pending_payload.is_empty():
		commit_failed.emit("There is no failed path-set commit to retry.")
		return
	_commit_pending()


func has_retryable_commit() -> bool:
	return not _pending_payload.is_empty() and not _is_committing


func get_pending_payload() -> Dictionary:
	return _pending_payload.duplicate(true)


func get_persisted_artifact_id() -> String:
	return _persisted_artifact_id


func _commit_pending() -> void:
	_is_committing = true
	commit_started.emit()
	if _persisted_artifact_id.is_empty():
		await _persist_artifact()
		if _persisted_artifact_id.is_empty():
			return
	if not _emit_explicit_closure():
		_finish_failure(
			(
				"Path set was stored as %s, but ClosureBus delivery failed. "
				+ "Closure is not claimed; retry will deliver the existing artifact without duplicating it."
			)
			% _persisted_artifact_id
		)
		return
	var closure_ref: String = "closure:path-set:" + _persisted_artifact_id
	var committed_payload: Dictionary = _pending_payload.duplicate(true)
	committed_payload["closure_ref"] = closure_ref
	_store.mark_committed(_persisted_artifact_id, committed_payload, closure_ref)
	var artifact_id: String = _persisted_artifact_id
	_pending_payload = {}
	_persisted_artifact_id = ""
	_is_committing = false
	commit_succeeded.emit(artifact_id, closure_ref, committed_payload)


func _persist_artifact() -> void:
	if (
		not is_instance_valid(_hub_client)
		or not _hub_client.has_method("create_artifact_inline_json")
	):
		_finish_failure(
			"Hub unavailable. Reviewed path comparison remains local, uncommitted, and retryable."
		)
		return
	var metadata: Dictionary = {
		"session_id": String(_pending_payload.get("session_id", "")),
		"schema_version": 1,
		# str() rather than String(): a Variant out of a Dictionary, and String()
		# converts only from String, StringName, and NodePath.
		"previous_version_id": str(_pending_payload.get("previous_version_id", "")),
		"store_trace_ids": _pending_payload.get("store_trace_ids", []),
		"provenance": {
			"produced_by": "scensyn.workshop_compare_paths@1",
			"app_id": "scensyn",
			"timestamp": Time.get_datetime_string_from_system(true),
		},
	}
	var result: Dictionary = await _hub_client.call(
		"create_artifact_inline_json",
		ARTIFACT_TYPE,
		_pending_payload,
		metadata
	)
	if not bool(result.get("ok", false)):
		_finish_failure(
			"Path-set Hub commit failed (%s). Reviewed draft remains retryable."
			% HubErrorTextScript.describe(result.get("error"))
		)
		return
	_persisted_artifact_id = str(result.get("id", "")).strip_edges()
	if _persisted_artifact_id.is_empty():
		_finish_failure("Hub returned no path-set artifact id. Draft remains uncommitted.")
		return
	artifact_persisted.emit(_persisted_artifact_id)


func _emit_explicit_closure() -> bool:
	if not is_instance_valid(_closure_bus) or not _closure_bus.has_method("emit_captured"):
		return false
	var selection_any: Variant = _pending_payload.get("selection", {})
	var selection: Dictionary = selection_any if typeof(selection_any) == TYPE_DICTIONARY else {}
	var closure_payload: Dictionary = {
		"session_type_id": "workshop_catalyst",
		"scenario_id": String(_pending_payload.get("scenario_id", "")),
		"kind": "workshop_path_set",
		"statement": String(selection.get("label", "")),
		"outcome": "committed",
		"reason": "Explicit facilitator Compare Paths commit",
		"trigger": "compare_paths_commit",
		"artifact_type": ARTIFACT_TYPE,
		"artifact_id": _persisted_artifact_id,
		"path_ids": selection.get("path_ids", []),
		"selection_kind": String(selection.get("kind", "")),
		"store_trace_ids": _pending_payload.get("store_trace_ids", []),
		"previous_version_id": String(_pending_payload.get("previous_version_id", "")),
	}
	var bus_result: Variant = _closure_bus.call("emit_captured", closure_payload)
	return bus_result != false


func _finish_failure(error_text: String) -> void:
	_is_committing = false
	commit_failed.emit(error_text)
