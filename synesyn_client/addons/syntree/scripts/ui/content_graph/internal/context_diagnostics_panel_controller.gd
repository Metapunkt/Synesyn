## Purpose: Coordinate diagnostics/version comparison without applying repairs.
extends RefCounted

const DiagnosticsScript = preload(
	"res://addons/syntree/scripts/core/context_graph_diagnostics.gd"
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
const LatestDeferredJobScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/latest_deferred_job.gd"
)

var _panel: Control = null
var _content_state: Object = null
var _conversation_manager: Object = null
var _overlay_target: Object = null
var _owner_source_id: String = ""
var _diagnostics: RefCounted = DiagnosticsScript.new()
var _adapter: RefCounted = ContextGraphAdapterScript.new()
var _compiler: RefCounted = ContextCompilerScript.new()
var _artifact_client: RefCounted = GraphWorkspaceArtifactClientScript.new()
var _latest_job: RefCounted = LatestDeferredJobScript.new()


func setup(
	panel: Control,
	content_state: Object,
	conversation_manager: Object,
	hub_client: Object,
	overlay_target: Object
) -> void:
	_panel = panel
	_content_state = content_state
	_conversation_manager = conversation_manager
	_overlay_target = overlay_target
	_artifact_client.call("setup", hub_client)
	_connect_signal("analyze_requested", _on_analyze_requested)
	_connect_signal("compare_requested", _on_compare_requested)
	_connect_signal("fork_requested", _on_fork_requested)
	_connect_signal("focus_requested", _on_focus_requested)


func refresh_graph(owner_source_id: String) -> void:
	_latest_job.call("cancel")
	_owner_source_id = owner_source_id


func _on_analyze_requested() -> void:
	var current_document: Dictionary = _build_current_document()
	if current_document.is_empty():
		_panel.call("show_status", "Current graph is unavailable.")
		return
	var compile_result: Dictionary = {}
	if is_instance_valid(_conversation_manager):
		compile_result = _conversation_manager.get_meta(
			"last_context_compile_result",
			{}
		)
	_panel.call("show_status", "Analyzing graph…")
	var frozen_document: Dictionary = current_document.duplicate(true)
	var frozen_compile_result: Dictionary = compile_result.duplicate(true)
	_latest_job.call(
		"schedule",
		func() -> Array[Dictionary]:
			return _diagnostics.call(
				"analyze",
				frozen_document,
				frozen_compile_result
			),
		func(result_any: Variant) -> void:
			_panel.call("set_diagnostics", result_any)
	)


func _on_compare_requested(version_id: String) -> void:
	if version_id.is_empty():
		_panel.call("show_status", "Enter a graph artifact/version id.")
		return
	var load_result: Dictionary = await _artifact_client.call(
		"load_graph",
		version_id,
		"context_graph"
	)
	if not bool(load_result.get("ok", false)):
		_panel.call("show_status", "Version load failed: %s" % str(
			load_result.get("error", load_result)
		))
		return
	var before_document: Dictionary = load_result.get("document", {})
	var after_document: Dictionary = _build_current_document()
	var options: Dictionary = _compiler.call("preset", "balanced")
	var before_compile: Dictionary = _compiler.call(
		"compile",
		before_document,
		_context_set(before_document),
		options
	)
	var after_compile: Dictionary = _compiler.call(
		"compile",
		after_document,
		_context_set(after_document),
		options
	)
	_panel.call("show_comparison", _diagnostics.call(
		"compare_versions",
		before_document,
		after_document,
		before_compile,
		after_compile
	))


func _on_fork_requested(version_id: String) -> void:
	if version_id.is_empty():
		_panel.call("show_status", "Enter a version id to fork.")
		return
	var load_result: Dictionary = await _artifact_client.call(
		"load_graph",
		version_id,
		"context_graph"
	)
	if not bool(load_result.get("ok", false)):
		_panel.call("show_status", "Fork source load failed.")
		return
	var fork_result: Dictionary = await _artifact_client.call(
		"commit_graph",
		"ui.context_graph",
		load_result.get("document", {}),
		{
			"owner_source_id": _owner_source_id,
			"generated_by": "syntree.context_graph.version_fork",
			"forked_from": version_id,
		},
		version_id
	)
	if not bool(fork_result.get("ok", false)):
		_panel.call("show_status", "Fork failed: %s" % str(
			fork_result.get("error", fork_result)
		))
		return
	_panel.call("show_status", "Created fork %s from %s." % [
		str(fork_result.get(
			"artifact_id",
			fork_result.get("id", "")
		)),
		version_id,
	])


func _on_focus_requested(record_ids: Array[String]) -> void:
	if (
		is_instance_valid(_overlay_target)
		and _overlay_target.has_method("show_diagnostic_overlay")
	):
		_overlay_target.call("show_diagnostic_overlay", record_ids)


func _build_current_document() -> Dictionary:
	if _owner_source_id.is_empty():
		return {}
	var source_ids: Array[String] = [_owner_source_id]
	var result: Dictionary = _adapter.call(
		"build_from_sources",
		_content_state,
		source_ids,
		"Context Graph diagnostics"
	)
	if not bool(result.get("ok", false)):
		return {}
	return result.get("document", {})


func _context_set(document: Dictionary) -> Dictionary:
	for context_set_any in document.get("context_sets", []):
		if typeof(context_set_any) != TYPE_DICTIONARY:
			continue
		var context_set: Dictionary = context_set_any
		if str(context_set.get("id", "")) == "active-sources":
			return context_set.duplicate(true)
	return {
		"id": "active-sources",
		"entry_node_ids": [_owner_source_id],
	}


func _connect_signal(signal_id: String, callback: Callable) -> void:
	if not is_instance_valid(_panel) or not _panel.has_signal(signal_id):
		return
	var panel_signal: Signal = Signal(_panel, StringName(signal_id))
	if not panel_signal.is_connected(callback):
		panel_signal.connect(callback)
