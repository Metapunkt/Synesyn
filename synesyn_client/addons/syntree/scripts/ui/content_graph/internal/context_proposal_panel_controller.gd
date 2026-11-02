## Purpose: Coordinate AI suggestions and human review without graph commit access.
extends RefCounted

const ProposalStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_graph_proposal_store.gd"
)
const ProposalEngineScript = preload(
	"res://addons/syntree/scripts/core/context_graph_proposal_engine.gd"
)
const ProposalGeneratorScript = preload(
	"res://addons/syntree/scripts/services/prompting/context_graph_proposal_generator.gd"
)
const ContextGraphAdapterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_adapter.gd"
)
const ContextCompilerScript = preload(
	"res://addons/syntree/scripts/core/context_compiler.gd"
)
const GraphWorkspaceArtifactClientScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_artifact_client.gd"
)

var _panel: Control = null
var _content_state: Object = null
var _conversation_manager: Object = null
var _hub_client: Object = null
var _owner_source_id: String = ""
var _store: RefCounted = ProposalStoreScript.new()
var _engine: RefCounted = ProposalEngineScript.new()
var _generator: RefCounted = ProposalGeneratorScript.new()
var _adapter: RefCounted = ContextGraphAdapterScript.new()
var _compiler: RefCounted = ContextCompilerScript.new()
var _artifact_client: RefCounted = GraphWorkspaceArtifactClientScript.new()
var _last_preview_hash: String = ""


func setup(
	panel: Control,
	content_state: Object,
	conversation_manager: Object,
	hub_client: Object
) -> void:
	_panel = panel
	_content_state = content_state
	_conversation_manager = conversation_manager
	_hub_client = hub_client
	_artifact_client.call("setup", hub_client)
	_connect_signal("generate_requested", _on_generate_requested)
	_connect_signal("review_requested", _on_review_requested)
	_connect_signal("preview_requested", _on_preview_requested)
	_connect_signal("commit_requested", _on_commit_requested)


func refresh_graph(owner_source_id: String) -> void:
	_owner_source_id = owner_source_id
	_refresh_proposals()


func _on_generate_requested(request_text: String) -> void:
	if (
		_owner_source_id.is_empty()
		or not is_instance_valid(_conversation_manager)
	):
		_panel.call("show_status", "Graph or AI service unavailable.")
		return
	_panel.call("show_status", "Generating suggestions…")
	var owner_source_ids: Array[String] = [_owner_source_id]
	var build_result: Dictionary = _adapter.call(
		"build_from_sources",
		_content_state,
		owner_source_ids,
		"Proposal input"
	)
	if not bool(build_result.get("ok", false)):
		_panel.call("show_status", "Current graph is invalid.")
		return
	var model_manager: Object = _conversation_manager.get(
		"ai_model_manager"
	)
	var model_id: String = ""
	if (
		is_instance_valid(model_manager)
		and model_manager.has_method("get_current_model")
	):
		model_id = str(model_manager.call("get_current_model"))
	var result: Dictionary = await _generator.call(
		"generate",
		_conversation_manager.get("api_service"),
		build_result.get("document", {}),
		request_text,
		model_id
	)
	if not bool(result.get("ok", false)):
		_panel.call("show_status", "Suggestion request failed: %s" % (
			result.get("error", result.get("errors", []))
		))
		return
	var saved_count: int = 0
	var suppressed_count: int = 0
	for proposal_any in result.get("proposals", []):
		var save_result: Dictionary = _store.call(
			"upsert_suggestion",
			_content_state,
			_owner_source_id,
			proposal_any
		)
		if bool(save_result.get("suppressed", false)):
			suppressed_count += 1
		elif bool(save_result.get("ok", false)):
			saved_count += 1
	_refresh_proposals()
	_panel.call(
		"show_status",
		"Saved %d suggestion(s); suppressed %d reviewed duplicate(s)."
		% [saved_count, suppressed_count]
	)


func _on_review_requested(
	proposal_ids: Array[String],
	decision: String,
	edited_payload: Dictionary,
	reviewer_note: String
) -> void:
	var reviewed_count: int = 0
	for proposal_id in proposal_ids:
		var result: Dictionary = _store.call(
			"review",
			_content_state,
			_owner_source_id,
			proposal_id,
			decision,
			edited_payload,
			reviewer_note
		)
		if bool(result.get("ok", false)):
			reviewed_count += 1
			_emit_review_event(result.get("event", {}))
	_refresh_proposals()
	_panel.call(
		"show_status",
		"Recorded %d %s decision(s)." % [reviewed_count, decision]
	)


func _on_preview_requested(proposal_ids: Array[String]) -> void:
	var proposals: Array[Dictionary] = _store.call(
		"get_proposals",
		_content_state,
		_owner_source_id
	)
	var selected: Array = []
	for proposal in proposals:
		if proposal_ids.has(str(proposal.get("id", ""))):
			var preview_proposal: Dictionary = proposal.duplicate(true)
			if str(preview_proposal.get("status", "")) in [
				"suggested",
				"deferred",
			]:
				preview_proposal["status"] = "accepted"
			selected.append(preview_proposal)
	var owner_source_ids: Array[String] = [_owner_source_id]
	var build_result: Dictionary = _adapter.call(
		"build_from_sources",
		_content_state,
		owner_source_ids,
		"Proposal review"
	)
	if not bool(build_result.get("ok", false)):
		_panel.call("show_status", "Current graph is invalid.")
		return
	var document: Dictionary = build_result.get("document", {})
	var preview_result: Dictionary = _engine.call(
		"preview",
		document,
		selected
	)
	var context_set_id: String = "active-sources"
	var context_set: Dictionary = _find_context_set(
		document,
		context_set_id
	)
	var options: Dictionary = _compiler.call("preset", "balanced")
	var baseline_compile: Dictionary = _compiler.call(
		"compile",
		document,
		context_set,
		options
	)
	var preview_compile: Dictionary = _compiler.call(
		"compile",
		preview_result.get("document", {}),
		context_set,
		options
	)
	_last_preview_hash = JSON.stringify(
		preview_result.get("document", {})
	).sha256_text()
	_panel.call("show_impact", {
		"ok": bool(preview_result.get("ok", false)),
		"semantic_diff": preview_result.get("semantic_diff", {}),
		"applied_proposal_ids": preview_result.get(
			"applied_proposal_ids",
			[]
		),
		"errors": preview_result.get("errors", []),
		"token_estimate_before": baseline_compile.get(
			"estimated_tokens",
			0
		),
		"token_estimate_after": preview_compile.get(
			"estimated_tokens",
			0
		),
		"included_before": (
			baseline_compile.get("included_nodes", []) as Array
		).size(),
		"included_after": (
			preview_compile.get("included_nodes", []) as Array
		).size(),
	})


func _on_commit_requested() -> void:
	var proposals: Array[Dictionary] = _store.call(
		"get_proposals",
		_content_state,
		_owner_source_id
	)
	var accepted: Array = []
	for proposal in proposals:
		if str(proposal.get("status", "")) in ["accepted", "edited"]:
			accepted.append(proposal)
	if accepted.is_empty():
		_panel.call("show_status", "No accepted proposals to commit.")
		return
	var owner_source_ids: Array[String] = [_owner_source_id]
	var build_result: Dictionary = _adapter.call(
		"build_from_sources",
		_content_state,
		owner_source_ids,
		"Proposal review"
	)
	var preview_result: Dictionary = _engine.call(
		"preview",
		build_result.get("document", {}),
		accepted
	)
	if not bool(preview_result.get("ok", false)):
		_panel.call("show_status", "Accepted proposal preview is invalid.")
		return
	var preview_document: Dictionary = preview_result.get("document", {})
	var preview_hash: String = JSON.stringify(
		preview_document
	).sha256_text()
	if preview_hash != _last_preview_hash:
		_panel.call(
			"show_status",
			"Preview the currently accepted proposals before committing."
		)
		return
	var commit_document: Dictionary = preview_document.duplicate(true)
	_mark_applied_records_committed(commit_document, accepted)
	var lineage: Dictionary = _lineage()
	var commit_result: Dictionary = await _artifact_client.call(
		"commit_graph",
		"ui.context_graph",
		commit_document,
		{
			"owner_source_id": _owner_source_id,
			"generated_by": "syntree.context_graph.proposal_commit",
			"proposal_ids": preview_result.get(
				"applied_proposal_ids",
				[]
			),
		},
		str(lineage.get("version_id", ""))
	)
	if not bool(commit_result.get("ok", false)):
		_panel.call("show_status", "Commit failed: %s" % str(
			commit_result.get("error", commit_result)
		))
		return
	var version_id: String = str(commit_result.get(
		"artifact_id",
		commit_result.get("id", "")
	))
	if version_id.is_empty():
		_panel.call("show_status", "Hub returned no committed version id.")
		return
	var root_artifact_id: String = str(lineage.get(
		"artifact_id",
		version_id
	))
	var did_persist: bool = _persist_lineage(
		root_artifact_id,
		version_id
	)
	_last_preview_hash = ""
	_panel.call(
		"show_status",
		(
			"Committed Context Graph version %s."
			if did_persist
			else "Committed %s; local lineage needs repair."
		) % version_id
	)


func _mark_applied_records_committed(
	document: Dictionary,
	proposals: Array
) -> void:
	var node_ids: Array[String] = []
	var edge_ids: Array[String] = []
	for proposal_any in proposals:
		var proposal: Dictionary = proposal_any
		var payload: Dictionary = proposal.get("payload", {})
		var record_id: String = str(payload.get("id", ""))
		if str(proposal.get("operation", "")).ends_with("node"):
			node_ids.append(record_id)
		else:
			edge_ids.append(record_id)
	for node_any in document.get("nodes", []):
		var node_data: Dictionary = node_any
		if node_ids.has(str(node_data.get("id", ""))):
			node_data["status"] = "committed"
	for edge_any in document.get("edges", []):
		var edge_data: Dictionary = edge_any
		if edge_ids.has(str(edge_data.get("id", ""))):
			edge_data["status"] = "committed"


func _lineage() -> Dictionary:
	var source_data: Dictionary = _content_state.call(
		"get_source_data",
		_owner_source_id
	)
	var ai_context: Dictionary = (
		source_data.get("meta", {}) as Dictionary
	).get("ai_context", {})
	return {
		"artifact_id": str(
			ai_context.get("context_graph_artifact_id", "")
		),
		"version_id": str(
			ai_context.get("context_graph_version_id", "")
		),
	}


func _persist_lineage(
	artifact_id: String,
	version_id: String
) -> bool:
	var source_data: Dictionary = _content_state.call(
		"get_source_data",
		_owner_source_id
	)
	var source_meta: Dictionary = source_data.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	ai_context["context_graph_artifact_id"] = artifact_id
	ai_context["context_graph_version_id"] = version_id
	source_meta["ai_context"] = ai_context
	source_data["meta"] = source_meta
	return bool(_content_state.call(
		"update_source",
		_owner_source_id,
		source_data
	))


func _find_context_set(
	document: Dictionary,
	context_set_id: String
) -> Dictionary:
	for context_set_any in document.get("context_sets", []):
		if typeof(context_set_any) != TYPE_DICTIONARY:
			continue
		var context_set: Dictionary = context_set_any
		if str(context_set.get("id", "")) == context_set_id:
			return context_set.duplicate(true)
	return {
		"id": context_set_id,
		"entry_node_ids": [_owner_source_id],
	}


func _refresh_proposals() -> void:
	if not is_instance_valid(_panel) or _owner_source_id.is_empty():
		return
	_panel.call("set_proposals", _store.call(
		"get_proposals",
		_content_state,
		_owner_source_id
	))


func _emit_review_event(event_data: Dictionary) -> void:
	if (
		event_data.is_empty()
		or not is_instance_valid(_hub_client)
		or not _hub_client.has_method("create_event_fire_and_forget")
	):
		return
	_hub_client.call(
		"create_event_fire_and_forget",
		"syntree.context_graph.proposal_reviewed",
		event_data
	)


func _connect_signal(signal_id: String, callback: Callable) -> void:
	if not is_instance_valid(_panel) or not _panel.has_signal(signal_id):
		return
	var panel_signal: Signal = Signal(_panel, StringName(signal_id))
	if not panel_signal.is_connected(callback):
		panel_signal.connect(callback)
