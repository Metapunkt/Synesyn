extends Node
class_name WorkshopSummaryPersistenceCoordinator

signal commit_started
signal commit_succeeded(artifact_id: String, payload: Dictionary)
signal commit_failed(error_text: String)

const ARTIFACT_TYPE: String = "ui.workshop_summary"
const HubErrorTextScript = preload(
	"res://addons/synesyn_core/scripts/hub_error_text.gd"
)

var _hub_client: Object = null
var _store: RefCounted = null
var _pending_payload: Dictionary = {}
var _is_committing: bool = false


func configure(hub_client: Object, store: RefCounted) -> void:
	_hub_client = hub_client
	_store = store


func request_commit(facilitator_ref: String, closure_refs: Array = []) -> void:
	if _is_committing:
		return
	if not _store:
		commit_failed.emit("Session Record store is unavailable.")
		return
	_pending_payload = _store.build_commit_payload(facilitator_ref, closure_refs)
	_commit_pending()


func retry() -> void:
	if _is_committing:
		return
	if _pending_payload.is_empty():
		commit_failed.emit("There is no failed Workshop summary commit to retry.")
		return
	_commit_pending()


func has_retryable_commit() -> bool:
	return not _pending_payload.is_empty() and not _is_committing


func is_committing() -> bool:
	return _is_committing


func get_pending_payload() -> Dictionary:
	return _pending_payload.duplicate(true)


func _commit_pending() -> void:
	_is_committing = true
	commit_started.emit()
	if (
		not is_instance_valid(_hub_client)
		or not _hub_client.has_method("create_artifact_inline_json")
	):
		_finish_failure("Hub unavailable. Reviewed draft retained locally and remains uncommitted.")
		return
	# str() rather than String(): these are Variants out of a Dictionary, and
	# String() converts only from String, StringName, and NodePath.
	var metadata: Dictionary = {
		"session_id": str(_pending_payload.get("session_id", "")),
		"schema_version": int(_pending_payload.get("schema_version", 1)),
		"previous_version_id": str(_pending_payload.get("previous_version_id", "")),
		"provenance": {
			"produced_by": "scensyn.workshop_session_record@1",
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
		var error_text: String = HubErrorTextScript.describe(
			result.get("error"), "Hub rejected Workshop summary."
		)
		_finish_failure(
			"Commit failed (%s). Reviewed draft retained locally and is retryable." % error_text
		)
		return
	var artifact_id: String = str(result.get("id", "")).strip_edges()
	if artifact_id.is_empty():
		_finish_failure("Hub returned no artifact id. Reviewed draft remains uncommitted.")
		return
	var committed_payload: Dictionary = _pending_payload.duplicate(true)
	_store.mark_committed(artifact_id, committed_payload)
	_pending_payload = {}
	_is_committing = false
	commit_succeeded.emit(artifact_id, committed_payload)


func _finish_failure(error_text: String) -> void:
	_is_committing = false
	commit_failed.emit(error_text)
