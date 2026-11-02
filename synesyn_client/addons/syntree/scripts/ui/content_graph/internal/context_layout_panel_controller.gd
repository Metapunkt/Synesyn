## Purpose: Coordinate local named layouts without touching semantic state.
extends RefCounted

const LayoutStoreScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_layout_store.gd"
)

var _panel: Control = null
var _canvas_target: Object = null
var _owner_id: String = ""
var _store: RefCounted = LayoutStoreScript.new()


func setup(panel: Control, canvas_target: Object) -> void:
	_panel = panel
	_canvas_target = canvas_target
	_connect_signal("save_requested", _on_save_requested)
	_connect_signal("load_requested", _on_load_requested)
	_connect_signal("delete_requested", _on_delete_requested)


func refresh_graph(owner_id: String) -> void:
	_owner_id = owner_id
	_refresh_layouts()


func _on_save_requested(label_text: String, layout_id: String) -> void:
	if not is_instance_valid(_canvas_target):
		return
	var canvas_state: Dictionary = _canvas_target.call("capture_canvas_layout")
	var result: Dictionary = _store.call(
		"save_layout",
		_owner_id,
		label_text,
		canvas_state,
		layout_id
	)
	if not bool(result.get("ok", false)):
		_panel.call("show_status", "Layout save failed: %s" % str(
			result.get("error", "unknown error")
		))
		return
	_panel.call("show_status", "Visual layout saved locally.")
	_refresh_layouts()


func _on_load_requested(layout_id: String) -> void:
	for layout_data in _store.call("list_layouts", _owner_id):
		if str(layout_data.get("id", "")) != layout_id:
			continue
		_canvas_target.call("apply_canvas_layout", layout_data)
		_panel.call("show_status", "Visual layout loaded.")
		return


func _on_delete_requested(layout_id: String) -> void:
	var result: Dictionary = _store.call(
		"delete_layout",
		_owner_id,
		layout_id
	)
	if bool(result.get("ok", false)):
		_panel.call("show_status", "Visual layout deleted.")
		_refresh_layouts()


func _refresh_layouts() -> void:
	if is_instance_valid(_panel):
		_panel.call("set_layouts", _store.call("list_layouts", _owner_id))


func _connect_signal(signal_id: String, callback: Callable) -> void:
	if not is_instance_valid(_panel) or not _panel.has_signal(signal_id):
		return
	var panel_signal: Signal = Signal(_panel, StringName(signal_id))
	if not panel_signal.is_connected(callback):
		panel_signal.connect(callback)
