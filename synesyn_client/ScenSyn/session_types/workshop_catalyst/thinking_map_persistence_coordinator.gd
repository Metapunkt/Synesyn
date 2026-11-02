extends Node
class_name ThinkingMapPersistenceCoordinator

signal commit_started
signal commit_succeeded(artifact_id: String, payload: Dictionary)
signal commit_failed(error_text: String)

const GraphArtifactClientScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_artifact_client.gd"
)
const HubErrorTextScript = preload(
	"res://addons/synesyn_core/scripts/hub_error_text.gd"
)
const ARTIFACT_TYPE: String = "ui.workshop_thinking_map"

var _adapter: RefCounted = null
var _artifact_client: RefCounted = null
var _pending_payload: Dictionary = {}
var _is_committing: bool = false


func configure(hub_client: Object, adapter: RefCounted) -> void:
	_adapter = adapter
	_artifact_client = GraphArtifactClientScript.new()
	_artifact_client.setup(hub_client)


func request_commit(facilitator_ref: String = "Facilitator") -> void:
	if _is_committing:
		return
	if not _adapter:
		commit_failed.emit("Thinking Map adapter is unavailable.")
		return
	_pending_payload = _adapter.build_commit_document(facilitator_ref)
	_commit_pending()


func request_commit_payload(payload: Dictionary) -> void:
	if _is_committing:
		return
	if payload.is_empty():
		commit_failed.emit("A reviewed Thinking Map preview is required.")
		return
	_pending_payload = payload.duplicate(true)
	_commit_pending()


func retry() -> void:
	if _is_committing:
		return
	if _pending_payload.is_empty():
		commit_failed.emit("There is no failed Thinking Map commit to retry.")
		return
	_commit_pending()


func has_retryable_commit() -> bool:
	return not _pending_payload.is_empty() and not _is_committing


func get_pending_payload() -> Dictionary:
	return _pending_payload.duplicate(true)


func _commit_pending() -> void:
	_is_committing = true
	commit_started.emit()
	if not _artifact_client:
		_finish_failure("Hub unavailable. Reviewed map retained locally and remains uncommitted.")
		return
	var provenance_any: Variant = _pending_payload.get("facilitator_provenance", {})
	var provenance: Dictionary = (
		provenance_any if typeof(provenance_any) == TYPE_DICTIONARY else {}
	)
	# str() rather than String() throughout: these read out of a Dictionary, so
	# they are Variants, and String() converts only from String, StringName, and
	# NodePath. A session_id or id that arrives as a number would otherwise abort
	# this function mid-commit and leave _is_committing stuck true.
	var facilitator_ref: String = str(provenance.get("reviewed_by", "Facilitator"))
	var previous_version_id: String = str(_pending_payload.get("previous_version_id", ""))
	var metadata: Dictionary = {
		"session_id": str(_pending_payload.get("session_id", "")),
		"schema_version": 1,
		"graph_kind": "workshop_thinking_map",
		"previous_version_id": previous_version_id,
		"provenance": {
			"produced_by": "scensyn.workshop_thinking_map@1",
			"app_id": "scensyn",
			"facilitator": facilitator_ref,
			"timestamp": Time.get_datetime_string_from_system(true),
		},
	}
	var result: Dictionary = await _artifact_client.commit_graph(
		ARTIFACT_TYPE,
		_pending_payload,
		metadata,
		previous_version_id,
		[facilitator_ref]
	)
	if not bool(result.get("ok", false)):
		_finish_failure(
			"Map commit failed (%s). Reviewed local draft remains retryable."
			% HubErrorTextScript.describe(result.get("error"))
		)
		return
	var artifact_id: String = str(result.get("id", "")).strip_edges()
	if artifact_id.is_empty():
		_finish_failure("Hub returned no map artifact id. Draft remains uncommitted.")
		return
	var committed_payload: Dictionary = _pending_payload.duplicate(true)
	_adapter.mark_committed(artifact_id, committed_payload)
	_pending_payload = {}
	_is_committing = false
	commit_succeeded.emit(artifact_id, committed_payload)


func _finish_failure(error_text: String) -> void:
	_is_committing = false
	commit_failed.emit(error_text)
