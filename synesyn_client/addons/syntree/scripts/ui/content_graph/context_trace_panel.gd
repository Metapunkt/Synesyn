## Purpose: Inspect the latest immutable Context Compiler execution trace.
extends PanelContainer

signal refresh_requested

@onready var status_label: Label = %TraceStatus
@onready var included_list: ItemList = %IncludedNodes
@onready var omitted_list: ItemList = %OmittedNodes
@onready var details_text: TextEdit = %TraceDetails
@onready var compiled_context: TextEdit = %CompiledContext


func _ready() -> void:
	%RefreshTraceButton.pressed.connect(
		func() -> void: refresh_requested.emit()
	)
	clear_trace()


func set_trace(trace: Dictionary) -> void:
	if trace.is_empty():
		clear_trace()
		return
	included_list.clear()
	omitted_list.clear()
	for included_any in trace.get("included_nodes", []):
		var included_item: Dictionary = included_any
		included_list.add_item("%s — %s%s" % [
			str(included_item.get("node_id", "")),
			str(included_item.get("reason", "included")),
			_path_suffix(included_item),
		])
	for omitted_any in trace.get("omitted_nodes", []):
		var omitted_item: Dictionary = omitted_any
		omitted_list.add_item("%s — %s" % [
			str(omitted_item.get("node_id", "")),
			str(omitted_item.get("reason", "omitted")),
		])
	status_label.text = "%s · %d/%d tokens · %s" % [
		str(trace.get("status", "unknown")),
		int(trace.get("estimated_tokens", 0)),
		int(trace.get("token_budget", 0)),
		str(trace.get("context_path", "context_compiler")),
	]
	details_text.text = JSON.stringify({
		"run_id": trace.get("run_id", ""),
		"graph_artifact_id": trace.get("graph_artifact_id", ""),
		"graph_version_id": trace.get("graph_version_id", ""),
		"context_set_id": trace.get("context_set_id", ""),
		"prompt_chain_id": trace.get("prompt_chain_id", ""),
		"model_id": trace.get("model_id", ""),
		"provider_id": trace.get("provider_id", ""),
		"message_refs": trace.get("message_refs", {}),
		"store_trace_id": trace.get("store_trace_id", ""),
		"compiled_text_hash": trace.get("compiled_text_hash", ""),
	}, "  ")
	compiled_context.text = str(trace.get(
		"runtime_compiled_text",
		"Unavailable after restart; the canonical trace stores only its hash."
	))


func clear_trace() -> void:
	status_label.text = "No context execution trace is available."
	included_list.clear()
	omitted_list.clear()
	details_text.text = ""
	compiled_context.text = ""


func _path_suffix(item: Dictionary) -> String:
	var path_values: Array = item.get("traversal_path", [])
	if path_values.is_empty():
		return ""
	var path_text: PackedStringArray = []
	for path_value in path_values:
		path_text.append(str(path_value))
	return " via %s" % " → ".join(path_text)
