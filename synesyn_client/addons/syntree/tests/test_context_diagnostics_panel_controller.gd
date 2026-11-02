extends SceneTree

const DiagnosticsPanelScene = preload(
	"res://addons/syntree/scenes/context_diagnostics_panel.tscn"
)
const DiagnosticsPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_diagnostics_panel_controller.gd"
)


class FakeContentState:
	extends RefCounted

	var source_data: Dictionary = {
		"meta": {
			"name": "Source A",
			"ai_context": {"is_active": true},
		},
		"content": {
			"nodes": [
				{"node_id": "node-a", "content": "Same"},
				{"node_id": "node-b", "content": "Same"},
			],
		},
	}

	func get_source_data(_source_id: String) -> Dictionary:
		return source_data.duplicate(true)

	func get_context_graph_edges(_source_id: String) -> Array:
		return []


class FakeHubClient:
	extends RefCounted

	var document: Dictionary = {}
	var fork_document: Dictionary = {}

	func get_artifact_json(_artifact_id: String) -> Dictionary:
		return {
			"ok": true,
			"json": document.duplicate(true),
			"record": {"id": "old-version"},
		}

	func create_artifact_inline_json(
		_type_id: String,
		payload: Dictionary,
		_metadata: Dictionary
	) -> Dictionary:
		fork_document = payload.duplicate(true)
		return {"ok": true, "id": "fork-version"}


class FakeOverlayTarget:
	extends RefCounted

	var focused_ids: Array[String] = []

	func show_diagnostic_overlay(record_ids: Array[String]) -> void:
		focused_ids = record_ids.duplicate()


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var panel: Control = DiagnosticsPanelScene.instantiate()
	root.add_child(panel)
	var state := FakeContentState.new()
	var hub := FakeHubClient.new()
	var overlay := FakeOverlayTarget.new()
	var controller: RefCounted = DiagnosticsPanelControllerScript.new()
	controller.call("setup", panel, state, null, hub, overlay)
	controller.call("refresh_graph", "source-a")
	var current_document: Dictionary = controller.call(
		"_build_current_document"
	)
	hub.document = current_document.duplicate(true)
	var old_nodes: Array = hub.document.get("nodes", [])
	old_nodes.remove_at(old_nodes.size() - 1)
	hub.document["nodes"] = old_nodes
	var old_node_ids: Array[String] = []
	for node_any in old_nodes:
		old_node_ids.append(str((node_any as Dictionary).get("id", "")))
	var old_edges: Array = []
	for edge_any in hub.document.get("edges", []):
		var edge_data: Dictionary = edge_any
		if (
			old_node_ids.has(str(edge_data.get("from", "")))
			and old_node_ids.has(str(edge_data.get("to", "")))
		):
			old_edges.append(edge_data)
	hub.document["edges"] = old_edges
	panel.get_node(
		"MarginContainer/VBoxContainer/AnalyzeButton"
	).pressed.emit()
	var diagnostics_list: ItemList = panel.get_node(
		"MarginContainer/VBoxContainer/DiagnosticsList"
	)
	panel.get_node(
		"MarginContainer/VBoxContainer/FocusDiagnosticButton"
	).pressed.emit()
	var version_edit: LineEdit = panel.get_node(
		"MarginContainer/VBoxContainer/VersionRow/CompareVersionEdit"
	)
	version_edit.text = "old-version"
	panel.get_node(
		"MarginContainer/VBoxContainer/VersionRow/CompareButton"
	).pressed.emit()
	for _frame_index in range(3):
		await process_frame
	panel.get_node(
		"MarginContainer/VBoxContainer/VersionRow/ForkButton"
	).pressed.emit()
	for _frame_index in range(3):
		await process_frame
	var comparison: TextEdit = panel.get_node(
		"MarginContainer/VBoxContainer/ComparisonText"
	)
	var did_pass: bool = (
		diagnostics_list.item_count > 0
		and not overlay.focused_ids.is_empty()
		and comparison.text.contains("semantic_diff")
		and comparison.text.contains("causation_claimed")
		and hub.fork_document.get(
			"previous_version_id",
			""
		) == "old-version"
	)
	panel.queue_free()
	if did_pass:
		print("Context diagnostics panel controller tests: all passed")
		quit(0)
		return
	push_error("Diagnostics panel did not analyze, focus, or compare versions")
	quit(1)
