extends SceneTree

const ContentGraphNodeScene = preload(
	"res://addons/syntree/scenes/content_source_graph_node.tscn"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var graph_node: GraphNode = ContentGraphNodeScene.instantiate()
	root.add_child(graph_node)
	graph_node.call("set_node_data", {
		"node_id": "node-a",
		"title": "Node A",
		"content": "Evidence",
		"provenance": {
			"authorship_kind": "ai_inference",
			"evidence_status": "conflicting",
		},
	})
	var badge: Label = graph_node.get_node(
		"MainContainer/VBoxContainer/HeaderSection/ProvenanceBadge"
	)
	var did_pass: bool = (
		badge.text.contains("ai inference")
		and badge.text.contains("conflicting")
		and badge.modulate.is_equal_approx(Color(1.0, 0.52, 0.7))
	)
	graph_node.queue_free()
	if did_pass:
		print("Context provenance badge tests: all passed")
		quit(0)
		return
	push_error("Graph provenance badge was missing or color-only")
	quit(1)
