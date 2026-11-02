## Purpose: Coordinate the node provenance panel with resource-owned storage.
extends RefCounted

const ContextProvenanceStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_provenance_store.gd"
)

var _panel: Control = null
var _content_state: Object = null
var _store: RefCounted = ContextProvenanceStoreScript.new()
var _owner_source_id: String = ""


func setup(panel: Control, content_state: Object) -> void:
	_panel = panel
	_content_state = content_state
	_connect_signal("node_selected", _on_node_selected)
	_connect_signal("save_requested", _on_save_requested)
	_connect_signal("open_source_requested", _on_open_source_requested)


func refresh_graph(
	owner_source_id: String,
	node_ids: Array[String]
) -> void:
	_owner_source_id = owner_source_id
	if is_instance_valid(_panel):
		var selectable_ids: Array[String] = node_ids.duplicate()
		if (
			not owner_source_id.is_empty()
			and not selectable_ids.has(owner_source_id)
		):
			selectable_ids.push_front(owner_source_id)
		_panel.call("set_node_ids", selectable_ids)


func _on_node_selected(node_id: String) -> void:
	var provenance: Dictionary = _store.call(
		"get_provenance",
		_content_state,
		_owner_source_id,
		node_id
	)
	_panel.call("show_provenance", provenance)
	var evidence: Dictionary = _evidence_paths(node_id)
	_panel.call(
		"show_evidence_paths",
		evidence.get("supporting", []),
		evidence.get("conflicting", [])
	)


func _on_save_requested(
	node_id: String,
	provenance: Dictionary
) -> void:
	var result: Dictionary = _store.call(
		"set_provenance",
		_content_state,
		_owner_source_id,
		node_id,
		provenance
	)
	if bool(result.get("ok", false)):
		_panel.call("show_provenance", result.get("provenance", {}))
		_panel.call("show_status", "Provenance saved.")
		return
	_panel.call("show_status", "Could not save provenance: %s" % (
		", ".join(result.get("errors", []))
	))


func _on_open_source_requested(source_uri: String) -> void:
	var resolved_uri: String = source_uri.strip_edges()
	if (
		resolved_uri.begins_with("res://")
		or resolved_uri.begins_with("user://")
	):
		resolved_uri = ProjectSettings.globalize_path(resolved_uri)
	var open_error: Error = OS.shell_open(resolved_uri)
	if open_error == OK:
		_panel.call("show_status", "Opened source location.")
		return
	_panel.call(
		"show_status",
		"Could not open source location (%s)." % error_string(open_error)
	)


func _evidence_paths(node_id: String) -> Dictionary:
	var edges: Array = []
	if _content_state.has_method("get_context_graph_edges"):
		edges = _content_state.call(
			"get_context_graph_edges",
			_owner_source_id
		)
	if (
		edges.is_empty()
		and _content_state.has_method("get_stack_context_graph_edges")
	):
		edges = _content_state.call(
			"get_stack_context_graph_edges",
			_owner_source_id
		)
	var local_node_id: String = node_id
	if node_id.contains("::"):
		local_node_id = node_id.split("::", false, 1)[1]
	var supporting: Array[String] = []
	var conflicting: Array[String] = []
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		var from_id: String = str(edge_data.get("from", ""))
		var to_id: String = str(edge_data.get("to", ""))
		if (
			local_node_id not in [from_id, to_id]
			and node_id not in [from_id, to_id]
		):
			continue
		var path_text: String = "%s → %s" % [from_id, to_id]
		var relation_id: String = str(edge_data.get("relation", ""))
		if relation_id == "supports":
			supporting.append(path_text)
		elif relation_id == "contradicts":
			conflicting.append(path_text)
	return {
		"supporting": supporting,
		"conflicting": conflicting,
	}


func _connect_signal(signal_id: String, callback: Callable) -> void:
	if not is_instance_valid(_panel) or not _panel.has_signal(signal_id):
		return
	var panel_signal: Signal = Signal(_panel, StringName(signal_id))
	if not panel_signal.is_connected(callback):
		panel_signal.connect(callback)
