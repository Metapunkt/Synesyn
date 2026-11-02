extends SceneTree

const GraphRendererScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_renderer.gd"
)


func _init() -> void:
	var graph_view := GraphEdit.new()
	root.add_child(graph_view)
	var node_a := GraphNode.new()
	var node_b := GraphNode.new()
	node_a.name = "node-a"
	node_b.name = "node-b"
	node_a.add_child(Label.new())
	node_b.add_child(Label.new())
	for _slot_index in range(4):
		node_a.add_child(Label.new())
		node_b.add_child(Label.new())
	graph_view.add_child(node_a)
	graph_view.add_child(node_b)
	node_a.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
	node_b.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
	for slot_index in range(1, 5):
		node_a.set_slot(slot_index, true, 0, Color.WHITE, true, 0, Color.WHITE)
		node_b.set_slot(slot_index, true, 0, Color.WHITE, true, 0, Color.WHITE)
	var created_nodes: Dictionary = {"node-a": node_a, "node-b": node_b}
	var typed_edges: Array = [{
		"id": "edge-a-b",
		"from": "node-a",
		"to": "node-b",
		"relation": "supports",
	}]
	var renderer: RefCounted = GraphRendererScript.new()
	renderer.call(
		"connect_typed_edges",
		graph_view,
		created_nodes,
		typed_edges
	)
	var is_connected: bool = graph_view.is_node_connected(
		"node-a",
		3,
		"node-b",
		3
	)
	graph_view.queue_free()
	if is_connected:
		print("Graph renderer typed edge tests: all passed")
		quit(0)
		return
	push_error("Graph renderer did not draw a non-structural typed edge")
	quit(1)
