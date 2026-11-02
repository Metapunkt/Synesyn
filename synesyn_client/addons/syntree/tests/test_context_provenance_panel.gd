extends SceneTree

const ProvenancePanelScene = preload(
	"res://addons/syntree/scenes/context_provenance_panel.tscn"
)
const ProvenancePanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_provenance_panel_controller.gd"
)


class FakeContentState:
	extends RefCounted

	var source_data: Dictionary = {
		"meta": {
			"name": "Source A",
			"path": "res://fixtures/source-a.md",
		},
		"content": {
			"nodes": [{"node_id": "node-a", "content": "A"}],
		},
	}

	func get_source_data(_source_id: String) -> Dictionary:
		return source_data.duplicate(true)

	func update_source(
		_source_id: String,
		updated_source: Dictionary
	) -> bool:
		source_data = updated_source.duplicate(true)
		return true

	func get_context_graph_edges(_source_id: String) -> Array:
		return [
			{
				"from": "evidence-a",
				"to": "node-a",
				"relation": "supports",
			},
			{
				"from": "evidence-b",
				"to": "node-a",
				"relation": "contradicts",
			},
		]


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var panel: Control = ProvenancePanelScene.instantiate()
	root.add_child(panel)
	var state := FakeContentState.new()
	var controller: RefCounted = ProvenancePanelControllerScript.new()
	controller.call("setup", panel, state)
	var node_ids: Array[String] = ["node-a"]
	controller.call("refresh_graph", "source-a", node_ids)
	var node_selector: OptionButton = panel.get_node(
		"MarginContainer/VBoxContainer/ProvenanceNodeSelector"
	)
	var source_uri: LineEdit = panel.get_node(
		"MarginContainer/VBoxContainer/SourceUriEdit"
	)
	var evidence_selector: OptionButton = panel.get_node(
		"MarginContainer/VBoxContainer/EvidenceSelector"
	)
	var evidence_paths: RichTextLabel = panel.get_node(
		"MarginContainer/VBoxContainer/EvidencePaths"
	)
	node_selector.select(1)
	node_selector.item_selected.emit(1)
	for item_index in range(evidence_selector.item_count):
		if str(
			evidence_selector.get_item_metadata(item_index)
		) == "supported":
			evidence_selector.select(item_index)
	panel.get_node(
		"MarginContainer/VBoxContainer/Actions/SaveProvenanceButton"
	).pressed.emit()
	var stored_node: Dictionary = (
		state.source_data.get("content", {}) as Dictionary
	).get("nodes", [])[0]
	var stored_provenance: Dictionary = stored_node.get("provenance", {})
	var did_pass: bool = (
		node_selector.item_count == 2
		and source_uri.text.is_empty()
		and stored_provenance.get("evidence_status", "") == "supported"
		and stored_provenance.get(
			"origin_ref",
			""
		) == "source:source-a"
		and evidence_paths.text.contains("evidence-a")
		and evidence_paths.text.contains("evidence-b")
	)
	panel.queue_free()
	if did_pass:
		print("Context provenance panel tests: all passed")
		quit(0)
		return
	push_error("Node provenance inspector did not load or persist its record")
	quit(1)
