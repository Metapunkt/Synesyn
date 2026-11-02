## Purpose: Apply pure focus/filter results to the current graph canvas.
extends RefCounted

const FocusFilterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_focus_filter.gd"
)
const ContextGraphAdapterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_adapter.gd"
)
const LatestDeferredJobScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/latest_deferred_job.gd"
)

var _panel: Control = null
var _content_state: Object = null
var _overlay_target: Object = null
var _owner_source_id: String = ""
var _filter: RefCounted = FocusFilterScript.new()
var _adapter: RefCounted = ContextGraphAdapterScript.new()
var _latest_job: RefCounted = LatestDeferredJobScript.new()


func setup(
	panel: Control,
	content_state: Object,
	overlay_target: Object
) -> void:
	_panel = panel
	_content_state = content_state
	_overlay_target = overlay_target
	_connect_signal("apply_requested", _on_apply_requested)
	_connect_signal("reset_requested", _on_reset_requested)
	_connect_signal("fit_relevant_requested", _on_fit_relevant_requested)


func refresh_graph(
	owner_source_id: String,
	node_ids: Array[String]
) -> void:
	_latest_job.call("cancel")
	_owner_source_id = owner_source_id
	_panel.call("set_node_ids", node_ids)


func _on_apply_requested(options: Dictionary) -> void:
	var source_ids: Array[String] = [_owner_source_id]
	var build_result: Dictionary = _adapter.call(
		"build_from_sources",
		_content_state,
		source_ids,
		"Context Graph focus"
	)
	if not bool(build_result.get("ok", false)):
		return
	var document: Dictionary = build_result.get("document", {}).duplicate(true)
	var frozen_options: Dictionary = options.duplicate(true)
	_panel.call("show_status", "Filtering…")
	_latest_job.call(
		"schedule",
		func() -> Dictionary:
			return _filter.call("evaluate", document, frozen_options),
		_on_filter_completed
	)


func _on_filter_completed(result_any: Variant) -> void:
	var result: Dictionary = result_any
	if (
		is_instance_valid(_overlay_target)
		and _overlay_target.has_method("apply_focus_filter")
	):
		_overlay_target.call("apply_focus_filter", result)
	_panel.call("show_result", result)


func _on_reset_requested() -> void:
	_latest_job.call("cancel")
	if (
		is_instance_valid(_overlay_target)
		and _overlay_target.has_method("reset_focus_filter")
	):
		_overlay_target.call("reset_focus_filter")
	_panel.call("show_reset")


func _on_fit_relevant_requested() -> void:
	if (
		is_instance_valid(_overlay_target)
		and _overlay_target.has_method("fit_relevant_context")
	):
		_overlay_target.call("fit_relevant_context")


func _connect_signal(signal_id: String, callback: Callable) -> void:
	if not is_instance_valid(_panel) or not _panel.has_signal(signal_id):
		return
	var panel_signal: Signal = Signal(_panel, StringName(signal_id))
	if not panel_signal.is_connected(callback):
		panel_signal.connect(callback)
