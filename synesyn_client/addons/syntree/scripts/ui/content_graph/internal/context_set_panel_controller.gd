## Purpose: Coordinate Context Set/activation UI with resource-owned stores.
extends RefCounted

const ContextSetStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_set_store.gd"
)
const ContextActivationStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_activation_store.gd"
)
const ContextGraphAdapterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_adapter.gd"
)
const GraphWorkspaceArtifactClientScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_artifact_client.gd"
)

var _panel: Control = null
var _content_state: Object = null
var _context_preview: Control = null
var _conversation_manager: Object = null
var _compiler_bridge: RefCounted = null
var _context_set_store: RefCounted = ContextSetStoreScript.new()
var _activation_store: RefCounted = ContextActivationStoreScript.new()
var _context_graph_adapter: RefCounted = ContextGraphAdapterScript.new()
var _artifact_client: RefCounted = GraphWorkspaceArtifactClientScript.new()
var _hub_client: Object = null
var _owner_source_id: String = ""
var _node_ids: Array[String] = []
var _last_preview_set: Dictionary = {}


func setup(
	panel: Control,
	content_state: Object,
	context_preview: Control,
	conversation_manager: Object,
	compiler_bridge: RefCounted,
	hub_client: Object = null
) -> void:
	_panel = panel
	_content_state = content_state
	_context_preview = context_preview
	_conversation_manager = conversation_manager
	_compiler_bridge = compiler_bridge
	_hub_client = hub_client
	if is_instance_valid(_hub_client):
		_artifact_client.call("setup", _hub_client)
	_connect_signal("save_set_requested", _on_save_set_requested)
	_connect_signal("delete_set_requested", _on_delete_set_requested)
	_connect_signal("duplicate_set_requested", _on_duplicate_set_requested)
	_connect_signal("preview_set_requested", _on_preview_set_requested)
	_connect_signal("commit_set_requested", _on_commit_set_requested)
	_connect_signal("history_requested", _on_history_requested)
	_connect_signal("activation_selected", _on_activation_selected)
	_connect_signal(
		"activation_save_requested",
		_on_activation_save_requested
	)


func refresh_graph(owner_source_id: String, node_ids: Array[String]) -> void:
	_owner_source_id = owner_source_id
	_node_ids = node_ids.duplicate()
	if not is_instance_valid(_panel) or _owner_source_id.is_empty():
		return
	_panel.call("set_node_ids", _node_ids)
	_refresh_sets()


func _refresh_sets() -> void:
	var context_sets: Array = _context_set_store.call(
		"get_sets",
		_content_state,
		_owner_source_id
	)
	_panel.call("set_context_sets", context_sets)


func _on_save_set_requested(context_set: Dictionary) -> void:
	var existing: Dictionary = _find_set(str(context_set.get("id", "")))
	if (
		str(existing.get("status", "draft")) == "committed"
		and str(context_set.get("status", "draft")) == "draft"
	):
		context_set["id"] = _next_copy_id(
			str(context_set.get("id", "context-set"))
		)
		context_set["label"] = "%s Draft" % str(
			context_set.get("label", context_set.get("id", "Context Set"))
		)
	var result: Dictionary = _context_set_store.call(
		"upsert_set",
		_content_state,
		_owner_source_id,
		context_set
	)
	if bool(result.get("ok", false)):
		_panel.call("show_status", "Local context-set draft saved.")
		_refresh_sets()
		return
	_panel.call(
		"show_status",
		"Could not save: %s" % str(result.get("errors", [])),
		true
	)


func _on_delete_set_requested(context_set_id: String) -> void:
	var existing: Dictionary = _find_set(context_set_id)
	if str(existing.get("status", "draft")) != "draft":
		_panel.call(
			"show_status",
			"Committed sets require a new artifact version; they are not deleted locally.",
			true
		)
		return
	var result: Dictionary = _context_set_store.call(
		"remove_set",
		_content_state,
		_owner_source_id,
		context_set_id
	)
	if bool(result.get("ok", false)):
		_panel.call("show_status", "Local draft deleted.")
		_refresh_sets()
		return
	_panel.call(
		"show_status",
		"Could not delete: %s" % str(result.get("errors", [])),
		true
	)


func _on_duplicate_set_requested(context_set_id: String) -> void:
	var source_set: Dictionary = _find_set(context_set_id)
	if source_set.is_empty():
		_panel.call("show_status", "Select a context set to duplicate.", true)
		return
	var duplicate_set: Dictionary = source_set.duplicate(true)
	duplicate_set["id"] = _next_copy_id(context_set_id)
	duplicate_set["label"] = "%s Copy" % str(
		source_set.get("label", context_set_id)
	)
	duplicate_set["status"] = "draft"
	_on_save_set_requested(duplicate_set)


func _on_preview_set_requested(context_set: Dictionary) -> void:
	if not is_instance_valid(_context_preview):
		return
	var preview_set: Dictionary = context_set.duplicate(true)
	_last_preview_set = context_set.duplicate(true)
	preview_set["entry_node_ids"] = _artifact_entry_ids(
		context_set.get("entry_node_ids", [])
	)
	var options: Dictionary = _context_preview.call("get_options")
	options["context_set_override"] = preview_set
	var source_ids: Array[String] = [_owner_source_id]
	var result: Dictionary = _compiler_bridge.call(
		"compile_sources",
		_content_state,
		source_ids,
		options
	)
	_context_preview.call("set_compile_result", result)
	var sidebar: TabContainer = _context_preview.get_parent()
	sidebar.current_tab = 1
	if (
		is_instance_valid(_conversation_manager)
		and bool(_conversation_manager.get_meta("use_context_compiler", false))
	):
		_conversation_manager.set_meta(
			"frozen_context_compile_result",
			result
		)


func _on_commit_set_requested(context_set: Dictionary) -> void:
	if not is_instance_valid(_hub_client):
		_panel.call("show_status", "Hub client is unavailable.", true)
		return
	var context_set_id: String = str(context_set.get("id", "")).strip_edges()
	if context_set_id.is_empty():
		_panel.call("show_status", "A stable context-set id is required.", true)
		return
	if context_set != _last_preview_set:
		_panel.call(
			"show_status",
			"Preview this exact draft before committing it.",
			true
		)
		return
	var existing: Dictionary = _find_set(context_set_id)
	if str(existing.get("status", "draft")) == "committed":
		_panel.call(
			"show_status",
			"Duplicate the committed set before making a new version.",
			true
		)
		return
	var draft_result: Dictionary = _context_set_store.call(
		"upsert_set",
		_content_state,
		_owner_source_id,
		context_set
	)
	if not bool(draft_result.get("ok", false)):
		_panel.call(
			"show_status",
			"Could not persist the previewed draft before commit.",
			true
		)
		return
	_panel.call("show_status", "Committing Context Graph version…")
	var health_result: Dictionary = {"ok": true}
	if _hub_client.has_method("check_health"):
		health_result = await _hub_client.call("check_health")
	if not bool(health_result.get("ok", false)):
		_panel.call("show_status", "Hub is not reachable.", true)
		return
	var source_ids: Array[String] = [_owner_source_id]
	var mapped: Dictionary = _context_graph_adapter.call(
		"build_from_sources",
		_content_state,
		source_ids,
		"Context Graph · %s" % _owner_source_id
	)
	if not bool(mapped.get("ok", false)):
		_panel.call(
			"show_status",
			"Graph validation failed: %s"
			% str(mapped.get("validation_errors", [])),
			true
		)
		return
	var document: Dictionary = mapped.get("document", {})
	var artifact_set_id: String = "%s::%s" % [
		_owner_source_id,
		context_set_id,
	]
	var committed_sets: Array = []
	for candidate_any in document.get("context_sets", []):
		var candidate: Dictionary = candidate_any
		var candidate_id: String = str(candidate.get("id", ""))
		if candidate_id == "active-sources" or candidate_id == artifact_set_id:
			var committed_candidate: Dictionary = candidate.duplicate(true)
			committed_candidate["status"] = "committed"
			committed_sets.append(committed_candidate)
	document["context_sets"] = committed_sets
	var lineage: Dictionary = _lineage()
	var metadata: Dictionary = {
		"owner_source_id": _owner_source_id,
		"context_set_id": context_set_id,
		"generated_by": "syntree.context_sets.commit",
	}
	var commit_result: Dictionary = await _artifact_client.call(
		"commit_graph",
		"ui.context_graph",
		document,
		metadata,
		str(lineage.get("version_id", ""))
	)
	if not bool(commit_result.get("ok", false)):
		_panel.call(
			"show_status",
			"Commit failed: %s" % str(commit_result.get("error", commit_result)),
			true
		)
		return
	var version_id: String = str(
		commit_result.get("artifact_id", commit_result.get("id", ""))
	)
	if version_id.is_empty():
		_panel.call(
			"show_status",
			"Hub committed without returning an artifact id.",
			true
		)
		return
	var committed_set: Dictionary = context_set.duplicate(true)
	committed_set["status"] = "committed"
	var local_commit_result: Dictionary = _context_set_store.call(
		"upsert_set",
		_content_state,
		_owner_source_id,
		committed_set
	)
	var did_persist_lineage: bool = _persist_lineage(
		str(lineage.get("artifact_id", version_id)),
		version_id
	)
	if (
		not bool(local_commit_result.get("ok", false))
		or not did_persist_lineage
	):
		_panel.call(
			"show_status",
			"Hub committed %s, but local lineage needs repair." % version_id,
			true
		)
	else:
		_panel.call(
			"show_status",
			"Committed Context Graph version %s." % version_id
		)
	_last_preview_set.clear()
	_refresh_sets()
	await _refresh_history()


func _on_history_requested() -> void:
	await _refresh_history()


func _refresh_history() -> void:
	if not is_instance_valid(_hub_client):
		_panel.call("show_status", "Hub client is unavailable.", true)
		return
	var result: Dictionary = await _artifact_client.call(
		"list_graph_versions",
		"ui.context_graph",
		{"owner_source_id": _owner_source_id},
		100
	)
	if bool(result.get("ok", false)):
		_panel.call("set_version_history", result.get("versions", []))
		return
	_panel.call(
		"show_status",
		"Could not load history: %s" % str(result.get("error", result)),
		true
	)


func _on_activation_selected(node_id: String) -> void:
	var activation: Dictionary = _activation_store.call(
		"get_activation",
		_content_state,
		_owner_source_id,
		node_id
	)
	_panel.call("show_activation", activation)


func _on_activation_save_requested(
	node_id: String,
	activation: Dictionary
) -> void:
	var result: Dictionary = _activation_store.call(
		"set_activation",
		_content_state,
		_owner_source_id,
		node_id,
		activation
	)
	if bool(result.get("ok", false)):
		_panel.call("show_status", "Node activation saved.")
		if (
			is_instance_valid(_context_preview)
			and is_instance_valid(_conversation_manager)
			and bool(_conversation_manager.get_meta(
				"use_context_compiler",
				false
			))
		):
			_context_preview.call("refresh_preview")
		return
	_panel.call(
		"show_status",
		"Could not save activation: %s" % str(result.get("errors", [])),
		true
	)


func _find_set(context_set_id: String) -> Dictionary:
	for context_set_any in _context_set_store.call(
		"get_sets",
		_content_state,
		_owner_source_id
	):
		var context_set: Dictionary = context_set_any
		if str(context_set.get("id", "")) == context_set_id:
			return context_set
	return {}


func _next_copy_id(base_id: String) -> String:
	var existing_ids: Array[String] = []
	for context_set_any in _context_set_store.call(
		"get_sets",
		_content_state,
		_owner_source_id
	):
		existing_ids.append(str(
			(context_set_any as Dictionary).get("id", "")
		))
	var copy_index: int = 1
	var candidate_id: String = "%s-copy" % base_id
	while existing_ids.has(candidate_id):
		copy_index += 1
		candidate_id = "%s-copy-%d" % [base_id, copy_index]
	return candidate_id


func _artifact_entry_ids(entry_ids_any: Variant) -> Array[String]:
	var entry_ids: Array[String] = []
	if typeof(entry_ids_any) != TYPE_ARRAY:
		return entry_ids
	for entry_id_any in (entry_ids_any as Array):
		var entry_id: String = str(entry_id_any)
		if entry_id.contains("::") or entry_id == _owner_source_id:
			entry_ids.append(entry_id)
		else:
			entry_ids.append("%s::%s" % [_owner_source_id, entry_id])
	return entry_ids


func _lineage() -> Dictionary:
	var source_data: Dictionary = _content_state.call(
		"get_source_data",
		_owner_source_id
	)
	var source_meta: Dictionary = source_data.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	return {
		"artifact_id": str(
			ai_context.get("context_graph_artifact_id", "")
		),
		"version_id": str(
			ai_context.get("context_graph_version_id", "")
		),
	}


func _persist_lineage(artifact_id: String, version_id: String) -> bool:
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


func _connect_signal(event_id: String, callback: Callable) -> void:
	if not is_instance_valid(_panel) or not _panel.has_signal(event_id):
		return
	var panel_signal: Signal = Signal(_panel, StringName(event_id))
	if not panel_signal.is_connected(callback):
		panel_signal.connect(callback)
