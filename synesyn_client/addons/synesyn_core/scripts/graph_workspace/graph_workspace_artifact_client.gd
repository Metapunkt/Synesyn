## Purpose: Runtime-safe facade for versioned Graph Workspace Hub artifacts.
extends RefCounted

const GraphWorkspaceDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)

var _hub_client: Object = null


func setup(hub_client: Object) -> bool:
	_hub_client = hub_client
	return is_instance_valid(_hub_client)


func load_graph(artifact_id: String, expected_graph_kind: String = "") -> Dictionary:
	if not _can_load():
		return {"ok": false, "error": "hub_client_unavailable"}
	var normalized_id: String = artifact_id.strip_edges()
	if normalized_id.is_empty():
		return {"ok": false, "error": "artifact_id_required"}
	var response: Dictionary = await _hub_client.call("get_artifact_json", normalized_id)
	if not bool(response.get("ok", false)):
		return response
	var document_any: Variant = response.get("json", {})
	if typeof(document_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "artifact_json_object_required"}
	var document: Dictionary = document_any
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(
		document,
		expected_graph_kind
	)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": "invalid_graph_document",
			"validation_errors": validation.get("errors", []),
		}
	return {
		"ok": true,
		"document": document,
		"record": response.get("record", {}),
	}


func commit_graph(
	artifact_type: String,
	document: Dictionary,
	metadata: Dictionary = {},
	previous_version_id: String = "",
	trace_refs: Array = []
) -> Dictionary:
	if not _can_commit():
		return {"ok": false, "error": "hub_client_unavailable"}
	var validation: Dictionary = GraphWorkspaceDocumentScript.validate(document)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"error": "invalid_graph_document",
			"validation_errors": validation.get("errors", []),
		}
	var commit_document: Dictionary = document.duplicate(true)
	var previous_id: String = previous_version_id.strip_edges()
	if not previous_id.is_empty():
		commit_document["previous_version_id"] = previous_id
	var commit_metadata: Dictionary = metadata.duplicate(true)
	if not trace_refs.is_empty():
		commit_metadata["trace_refs"] = trace_refs.duplicate(true)
	return await _hub_client.call(
		"create_artifact_inline_json",
		artifact_type.strip_edges(),
		commit_document,
		commit_metadata
	)


func list_graph_versions(
	artifact_type: String,
	metadata_filters: Dictionary = {},
	limit: int = 50
) -> Dictionary:
	if (
		not _can_query()
		or not _hub_client.has_method("query_artifacts_by_type")
	):
		return {"ok": false, "error": "hub_query_unavailable"}
	var response: Dictionary = await _hub_client.call(
		"query_artifacts_by_type",
		artifact_type,
		limit
	)
	if not bool(response.get("ok", false)):
		return response
	var result: Dictionary = response.get("result", {})
	var columns: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	var versions: Array = []
	for row_any in rows:
		var record: Dictionary = _record_from_row(columns, row_any)
		if record.is_empty():
			continue
		var metadata: Dictionary = _metadata_from(
			record.get("metadata_json", {})
		)
		if not _metadata_matches(metadata, metadata_filters):
			continue
		versions.append({
			"id": str(record.get("id", "")),
			"created_at": str(record.get("created_at", "")),
			"metadata": metadata,
		})
	versions.sort_custom(_newest_first)
	return {"ok": true, "versions": versions}


func _can_load() -> bool:
	return (
		is_instance_valid(_hub_client)
		and _hub_client.has_method("get_artifact_json")
	)


func _can_commit() -> bool:
	return (
		is_instance_valid(_hub_client)
		and _hub_client.has_method("create_artifact_inline_json")
	)


func _can_query() -> bool:
	return is_instance_valid(_hub_client)


func _record_from_row(columns: Array, row_any: Variant) -> Dictionary:
	if typeof(row_any) == TYPE_DICTIONARY:
		return (row_any as Dictionary).duplicate(true)
	if typeof(row_any) != TYPE_ARRAY:
		return {}
	var row: Array = row_any
	var record: Dictionary = {}
	for column_index in range(columns.size()):
		if column_index < row.size():
			record[str(columns[column_index])] = row[column_index]
	return record


func _metadata_from(metadata_any: Variant) -> Dictionary:
	if typeof(metadata_any) == TYPE_DICTIONARY:
		return (metadata_any as Dictionary).duplicate(true)
	if typeof(metadata_any) == TYPE_STRING:
		var parsed: Variant = JSON.parse_string(str(metadata_any))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}


func _metadata_matches(
	metadata: Dictionary,
	metadata_filters: Dictionary
) -> bool:
	for filter_key in metadata_filters:
		if metadata.get(filter_key) != metadata_filters[filter_key]:
			return false
	return true


func _newest_first(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("created_at", "")) > str(right.get("created_at", ""))
