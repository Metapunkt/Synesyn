extends Node
class_name WorkshopPathEvidenceRetriever

signal retrieval_started(request_id: String)
signal retrieval_completed(result: Dictionary)

const HubErrorTextScript = preload(
	"res://addons/synesyn_core/scripts/hub_error_text.gd"
)

var _hub_client: Object = null
var _generation: int = 0
var _active_request_id: String = ""


func configure(hub_client: Object) -> void:
	_hub_client = hub_client


func request_evidence(
	paths: Array,
	active_source_ids: Array[String] = [],
	seed_family: String = "primary"
) -> String:
	_generation += 1
	var request_generation: int = _generation
	_active_request_id = "path_evidence_%d_%d" % [
		Time.get_ticks_msec(),
		request_generation,
	]
	var request_id: String = _active_request_id
	retrieval_started.emit(request_id)
	call_deferred(
		"_retrieve_async",
		request_id,
		request_generation,
		paths.duplicate(true),
		active_source_ids.duplicate(),
		seed_family
	)
	return request_id


func cancel_stale() -> void:
	_generation += 1
	_active_request_id = ""


func get_active_request_id() -> String:
	return _active_request_id


func _retrieve_async(
	request_id: String,
	request_generation: int,
	paths: Array,
	active_source_ids: Array[String],
	seed_family: String
) -> void:
	if not is_instance_valid(_hub_client):
		_finish_if_current(request_id, request_generation, _failure_result(
			request_id,
			"unavailable",
			"Evidence service is unavailable; no supporting references were found."
		))
		return
	if not _hub_client.has_method("stfx_store_retrieve"):
		_finish_if_current(request_id, request_generation, _failure_result(
			request_id,
			"unavailable",
			"STFX Store retrieval is unavailable; evidence remains none."
		))
		return
	var query_text: String = _build_query(paths)
	if query_text.is_empty():
		_finish_if_current(request_id, request_generation, _failure_result(
			request_id,
			"degraded",
			"No complete path claims were available for evidence retrieval."
		))
		return
	var response: Dictionary = await _hub_client.call(
		"stfx_store_retrieve",
		query_text,
		active_source_ids,
		seed_family,
		8,
		1
	)
	if request_generation != _generation or request_id != _active_request_id:
		return
	if not bool(response.get("ok", false)):
		_finish_if_current(request_id, request_generation, _failure_result(
			request_id,
			"degraded",
			"Evidence retrieval failed; path evidence remains none. " +
			HubErrorTextScript.describe(response.get("error"))
		))
		return
	var trace_any: Variant = response.get("trace", {})
	var trace: Dictionary = trace_any if typeof(trace_any) == TYPE_DICTIONARY else {}
	var context_any: Variant = response.get("context_pack", {})
	var context_pack: Dictionary = (
		context_any if typeof(context_any) == TYPE_DICTIONARY else {}
	)
	var evidence_refs: Array[Dictionary] = _plain_language_refs(context_pack)
	var result: Dictionary = {
		"request_id": request_id,
		"status": "available" if not evidence_refs.is_empty() else "none",
		"trace_id": String(trace.get("trace_id", context_pack.get("trace_id", ""))),
		"context_pack_id": String(context_pack.get("context_pack_id", "")),
		"evidence_refs": evidence_refs,
		"evidence_by_path": {},
		"message": (
			"%d supporting reference(s) retrieved. Review relevance before commitment."
			% evidence_refs.size()
			if not evidence_refs.is_empty()
			else "Retrieval completed with no supporting references; evidence is none."
		),
		"retrieved_at": Time.get_datetime_string_from_system(true),
	}
	_finish_if_current(request_id, request_generation, result)


func _finish_if_current(
	request_id: String,
	request_generation: int,
	result: Dictionary
) -> void:
	if request_generation != _generation or request_id != _active_request_id:
		return
	_active_request_id = ""
	retrieval_completed.emit(result)


func _build_query(paths: Array) -> String:
	var lines: Array[String] = [
		"Find source passages relevant to comparing these workshop decision paths."
	]
	for path_any: Variant in paths:
		if typeof(path_any) != TYPE_DICTIONARY:
			continue
		var path_data: Dictionary = path_any
		lines.append(
			"Path: %s. Outcomes: %s. Biggest risk: %s. Assumptions: %s."
			% [
				String(path_data.get("title", "")),
				"; ".join(path_data.get("outcomes", []) as Array),
				String(path_data.get("biggest_risk", "")),
				"; ".join(path_data.get("assumptions", []) as Array),
			]
		)
	return "\n".join(lines) if lines.size() > 1 else ""


func _plain_language_refs(context_pack: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var chunks_any: Variant = context_pack.get("chunks", [])
	var chunks: Array = chunks_any if typeof(chunks_any) == TYPE_ARRAY else []
	for chunk_any: Variant in chunks:
		if typeof(chunk_any) != TYPE_DICTIONARY:
			continue
		var chunk: Dictionary = chunk_any
		var chunk_id: String = String(chunk.get("chunk_id", "")).strip_edges()
		if chunk_id.is_empty():
			continue
		var citation_text: String = String(chunk.get("citation", "")).strip_edges()
		if citation_text.is_empty():
			citation_text = String(chunk.get("source_id", "Source")).strip_edges()
		output.append({
			"id": chunk_id,
			"title": citation_text,
			"excerpt": String(chunk.get("text", "")).strip_edges(),
			"source_uri": String(chunk.get("source_id", "")).strip_edges(),
		})
	return output


func _failure_result(request_id: String, status_id: String, message_text: String) -> Dictionary:
	return {
		"request_id": request_id,
		"status": status_id,
		"trace_id": "",
		"context_pack_id": "",
		"evidence_refs": [],
		"evidence_by_path": {},
		"message": message_text,
		"retrieved_at": Time.get_datetime_string_from_system(true),
	}
