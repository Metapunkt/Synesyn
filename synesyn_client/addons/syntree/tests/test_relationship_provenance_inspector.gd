extends SceneTree

const RelationshipInspectorScene = preload(
	"res://addons/syntree/scenes/relationship_inspector.tscn"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var inspector: Control = RelationshipInspectorScene.instantiate()
	root.add_child(inspector)
	var saved_edges: Array[Dictionary] = []
	inspector.save_requested.connect(
		func(edge_data: Dictionary) -> void:
			saved_edges.append(edge_data)
	)
	inspector.call("show_edge", {
		"id": "edge-a",
		"from": "node-a",
		"to": "node-b",
		"relation": "supports",
		"confidence": 0.9,
		"provenance": {
			"authorship_kind": "ai_inference",
			"origin_ref": "artifact:evidence-a",
			"review_status": "needs_review",
			"evidence_status": "supported",
		},
	})
	inspector.get_node(
		"MarginContainer/VBoxContainer/EditorContainer/PrimaryActions/SaveButton"
	).pressed.emit()
	var saved_provenance: Dictionary = {}
	if not saved_edges.is_empty():
		saved_provenance = saved_edges[0].get("provenance", {})
	var did_pass: bool = (
		saved_edges.size() == 1
		and saved_provenance.get(
			"authorship_kind",
			""
		) == "ai_inference"
		and saved_provenance.get(
			"origin_ref",
			""
		) == "artifact:evidence-a"
		and saved_provenance.get(
			"review_status",
			""
		) == "needs_review"
		and saved_provenance.get(
			"evidence_status",
			""
		) == "supported"
	)
	inspector.queue_free()
	if did_pass:
		print("Relationship provenance inspector tests: all passed")
		quit(0)
		return
	push_error("Relationship Inspector lost provenance or evidence state")
	quit(1)
