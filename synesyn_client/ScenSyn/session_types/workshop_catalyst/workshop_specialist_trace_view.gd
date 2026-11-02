extends RefCounted
class_name WorkshopSpecialistTraceView

## Owns the reusable specialist-summary disclosure component. This view renders
## retained summaries and provenance metadata, never private chain-of-thought.

var _disclosure_node: VBoxContainer
var _status_label_node: Label
var _summaries_node: RichTextLabel
var _latest_trace: Dictionary = {}


func mount(shell_root_node: Control) -> bool:
	var toggle_node: CheckButton = shell_root_node.find_child(
		"ShowReasoningToggle", true, false
	) as CheckButton
	_disclosure_node = shell_root_node.find_child(
		"ReasoningDisclosure", true, false
	) as VBoxContainer
	_status_label_node = shell_root_node.find_child(
		"ReasoningStatus", true, false
	) as Label
	_summaries_node = shell_root_node.find_child(
		"ReasoningSummaries", true, false
	) as RichTextLabel
	if (
		not toggle_node
		or not _disclosure_node
		or not _status_label_node
		or not _summaries_node
	):
		return false
	if not toggle_node.toggled.is_connected(_on_toggled):
		toggle_node.toggled.connect(_on_toggled)
	_connect_trace_store()
	return true


func set_expanded(is_expanded: bool) -> void:
	_on_toggled(is_expanded)


func set_trace(trace: Dictionary) -> void:
	_on_trace_updated(trace)


func _connect_trace_store() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		_render({})
		return
	var trace_store_node: Node = tree.get_first_node_in_group(
		"workshop_specialist_trace_store"
	)
	if not trace_store_node:
		_render({})
		return
	var trace_callable := Callable(self, "_on_trace_updated")
	if not trace_store_node.is_connected("trace_updated", trace_callable):
		trace_store_node.connect("trace_updated", trace_callable)
	if trace_store_node.has_method("get_latest_trace"):
		var trace_any: Variant = trace_store_node.call("get_latest_trace")
		if typeof(trace_any) == TYPE_DICTIONARY:
			_latest_trace = trace_any
	_render(_latest_trace)


func _on_toggled(is_expanded: bool) -> void:
	_disclosure_node.visible = is_expanded
	if is_expanded:
		_render(_latest_trace)


func _on_trace_updated(trace: Dictionary) -> void:
	_latest_trace = trace.duplicate(true)
	_render(_latest_trace)


func _render(trace: Dictionary) -> void:
	if trace.is_empty():
		_status_label_node.text = "Unavailable: no specialist trace has been retained yet."
		_summaries_node.text = "[i]No retained summaries are available.[/i]"
		return
	var trace_status: String = String(trace.get("status", "degraded"))
	var persistence_status: String = String(trace.get("persistence_status", "pending"))
	var model_id: String = String(trace.get("model_id", "default"))
	var turn_id: String = String(trace.get("turn_id", "unknown"))
	_status_label_node.text = (
		"Trace %s | model: %s | analysis: %s | retention: %s"
		% [turn_id, model_id, trace_status, persistence_status]
	)
	var contribution_values_any: Variant = trace.get("contributions", [])
	var contribution_values: Array = (
		contribution_values_any if typeof(contribution_values_any) == TYPE_ARRAY else []
	)
	var lines: Array[String] = []
	for contribution_any: Variant in contribution_values:
		if typeof(contribution_any) != TYPE_DICTIONARY:
			continue
		var contribution: Dictionary = contribution_any
		var role_title: String = String(contribution.get("role_title", "Specialist"))
		var summary_text: String = String(contribution.get("summary", "")).strip_edges()
		lines.append("[b]%s[/b]\n%s" % [role_title, summary_text])
	var extraction_any: Variant = trace.get("map_candidate_extraction", {})
	var extraction: Dictionary = (
		extraction_any if typeof(extraction_any) == TYPE_DICTIONARY else {}
	)
	var cues_any: Variant = extraction.get("facilitator_cues", [])
	if typeof(cues_any) == TYPE_ARRAY and not (cues_any as Array).is_empty():
		var cue_lines: Array[String] = []
		for cue_any: Variant in cues_any:
			var cue_text: String = String(cue_any).strip_edges()
			if not cue_text.is_empty():
				cue_lines.append("• " + cue_text)
		if not cue_lines.is_empty():
			lines.append("[b]Facilitator guidance[/b]\n" + "\n".join(cue_lines))
	_summaries_node.text = (
		"\n\n".join(lines)
		if not lines.is_empty()
		else "[i]Trace metadata exists, but specialist summaries are unavailable or degraded.[/i]"
	)
