extends SceneTree

const ProposalPanelScene = preload(
	"res://addons/syntree/scenes/context_proposal_panel.tscn"
)
const ProposalPanelControllerScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/context_proposal_panel_controller.gd"
)
const ProposalStoreScript = preload(
	"res://addons/syntree/scripts/resources/internal/context_graph_proposal_store.gd"
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
				{"node_id": "node-a", "content": "A"},
				{"node_id": "node-b", "content": "B"},
			],
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
		return []


class FakeHubClient:
	extends RefCounted

	var committed_document: Dictionary = {}

	func get_artifact_json(_artifact_id: String) -> Dictionary:
		return {"ok": false, "error": "not_used"}

	func create_artifact_inline_json(
		_artifact_type: String,
		document: Dictionary,
		_metadata: Dictionary
	) -> Dictionary:
		committed_document = document.duplicate(true)
		return {"ok": true, "id": "graph-version-a"}


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var panel: Control = ProposalPanelScene.instantiate()
	root.add_child(panel)
	var state := FakeContentState.new()
	var store: RefCounted = ProposalStoreScript.new()
	store.call("upsert_suggestion", state, "source-a", {
		"id": "proposal-a",
		"proposal_type": "relationship",
		"operation": "add_edge",
		"payload": {
			"id": "edge-a",
			"from": "source-a::node-a",
			"to": "source-a::node-b",
			"relation": "supports",
			"provenance_refs": ["trace:a"],
		},
	})
	var controller: RefCounted = ProposalPanelControllerScript.new()
	var hub := FakeHubClient.new()
	controller.call("setup", panel, state, null, hub)
	controller.call("refresh_graph", "source-a")
	panel.get_node(
		"MarginContainer/VBoxContainer/ReviewActions/AcceptButton"
	).pressed.emit()
	var proposals: Array = store.call(
		"get_proposals",
		state,
		"source-a"
	)
	panel.get_node(
		"MarginContainer/VBoxContainer/PreviewButton"
	).pressed.emit()
	panel.get_node(
		"MarginContainer/VBoxContainer/CommitAcceptedButton"
	).pressed.emit()
	for _frame_index in range(4):
		await process_frame
	var impact: TextEdit = panel.get_node(
		"MarginContainer/VBoxContainer/ProposalImpact"
	)
	var did_pass: bool = (
		proposals.size() == 1
		and (
			proposals[0] as Dictionary
		).get("status", "") == "accepted"
		and impact.text.contains("edge-a")
		and impact.text.contains("token_estimate_before")
		and (
			state.source_data.get("meta", {}) as Dictionary
		).get("ai_context", {}).get(
			"context_graph_version_id",
			""
		) == "graph-version-a"
		and (
			hub.committed_document.get("edges", [])[0] as Dictionary
		).get("status", "") == "committed"
	)
	panel.queue_free()
	if did_pass:
		print("Context proposal panel controller tests: all passed")
		quit(0)
		return
	push_error(
		"Proposal review UI mutated graph or omitted impact preview: %s"
		% JSON.stringify({
			"proposals": proposals,
			"impact": impact.text,
			"status": panel.get_node(
				"MarginContainer/VBoxContainer/ProposalStatus"
			).text,
			"source_data": state.source_data,
			"committed_document": hub.committed_document,
		})
	)
	quit(1)
